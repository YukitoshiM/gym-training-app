import Foundation
@preconcurrency import CoreMotion

@MainActor
final class WatchMotionAnalyzer {
    var onEstimateChanged: ((WatchMotionEstimate) -> Void)?
    var onSetInactivityDetected: (() -> Void)?
    var onSetStartCandidateDetected: ((WatchMotionEstimate) -> Void)?
    var onTempoDeviationDetected: (() -> Void)?

    private enum Mode {
        case monitoring
        case analyzing
    }

    private let motionManager = CMMotionManager()
    private var mode = Mode.analyzing
    private var repTimestamps: [TimeInterval] = []
    private var peakMagnitudes: [Double] = []
    private var concentricDurations: [Double] = []
    private var eccentricDurations: [Double] = []
    private var pauseDurations: [Double] = []
    private var movementBurstTimestamps: [TimeInterval] = []
    private var isAboveThreshold = false
    private var smoothedMagnitude = 0.0
    private var lastRepTimestamp: TimeInterval?
    private var movementStartedAt: TimeInterval?
    private var peakStartedAt: TimeInterval?
    private var lastMovementEndedAt: TimeInterval?
    private var hasReportedInactivity = false
    private var hasReportedStartCandidate = false
    private var lastTempoAlertRepCount = 0
    private var axisTotals = (x: 0.0, y: 0.0, z: 0.0)
    private var rotationTotal = 0.0
    private var accelerationTotal = 0.0

    private(set) var estimate = WatchMotionEstimate.empty

    var isMotionAvailable: Bool {
        motionManager.isDeviceMotionAvailable
    }

    func start(reducedSampling: Bool) {
        begin(mode: .analyzing, reducedSampling: reducedSampling)
    }

    func startMonitoring(reducedSampling _: Bool) {
        begin(mode: .monitoring, reducedSampling: true)
    }

    func updateSampling(reduced: Bool) {
        guard motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = reduced ? 1.0 / 20.0 : 1.0 / 50.0
    }

    func stop() -> WatchMotionEstimate {
        motionManager.stopDeviceMotionUpdates()
        return estimate
    }

    func reset() {
        motionManager.stopDeviceMotionUpdates()
        repTimestamps = []
        peakMagnitudes = []
        concentricDurations = []
        eccentricDurations = []
        pauseDurations = []
        movementBurstTimestamps = []
        isAboveThreshold = false
        smoothedMagnitude = 0
        lastRepTimestamp = nil
        movementStartedAt = nil
        peakStartedAt = nil
        lastMovementEndedAt = nil
        hasReportedInactivity = false
        hasReportedStartCandidate = false
        lastTempoAlertRepCount = 0
        axisTotals = (0, 0, 0)
        rotationTotal = 0
        accelerationTotal = 0
        estimate = .empty
    }

    private func begin(mode: Mode, reducedSampling: Bool) {
        reset()
        self.mode = mode
        guard motionManager.isDeviceMotionAvailable else {
            onEstimateChanged?(.empty)
            return
        }

        motionManager.deviceMotionUpdateInterval = reducedSampling ? 1.0 / 20.0 : 1.0 / 50.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            Task { @MainActor [weak self] in
                self?.consume(motion)
            }
        }
    }

    private func consume(_ motion: CMDeviceMotion) {
        let acceleration = motion.userAcceleration
        let magnitude = sqrt(
            acceleration.x * acceleration.x
            + acceleration.y * acceleration.y
            + acceleration.z * acceleration.z
        )
        let rotation = motion.rotationRate
        let rotationMagnitude = sqrt(
            rotation.x * rotation.x
            + rotation.y * rotation.y
            + rotation.z * rotation.z
        )

        smoothedMagnitude = smoothedMagnitude * 0.72 + magnitude * 0.28
        axisTotals.x += abs(acceleration.x)
        axisTotals.y += abs(acceleration.y)
        axisTotals.z += abs(acceleration.z)
        accelerationTotal += magnitude
        rotationTotal += rotationMagnitude * 0.12

        switch mode {
        case .monitoring:
            consumeMonitoringSample(timestamp: motion.timestamp)
        case .analyzing:
            consumeAnalyzingSample(timestamp: motion.timestamp)
        }
    }

    private func consumeMonitoringSample(timestamp: TimeInterval) {
        let highThreshold = 0.14
        let lowThreshold = 0.065

        if smoothedMagnitude >= highThreshold, !isAboveThreshold {
            movementBurstTimestamps.append(timestamp)
            movementBurstTimestamps.removeAll { timestamp - $0 > 4 }
            isAboveThreshold = true

            if movementBurstTimestamps.count >= 3, !hasReportedStartCandidate {
                hasReportedStartCandidate = true
                let movementTotal = rotationTotal + accelerationTotal
                estimate = WatchMotionEstimate(
                    estimatedReps: movementBurstTimestamps.count,
                    averageRepDuration: nil,
                    movementConsistency: nil,
                    confidence: min(0.75, 0.35 + Double(movementBurstTimestamps.count) * 0.08),
                    dominantAxis: dominantAxis(),
                    rotationalMovementRatio: movementTotal > 0 ? rotationTotal / movementTotal : nil
                )
                onSetStartCandidateDetected?(estimate)
            }
        } else if smoothedMagnitude <= lowThreshold {
            isAboveThreshold = false
        }
    }

    private func consumeAnalyzingSample(timestamp: TimeInterval) {
        let highThreshold = 0.16
        let lowThreshold = 0.075
        let minimumRepInterval = 0.32

        if smoothedMagnitude > lowThreshold, movementStartedAt == nil {
            movementStartedAt = timestamp
            if let lastMovementEndedAt {
                pauseDurations.append(max(0, timestamp - lastMovementEndedAt))
            }
        }

        if repTimestamps.count >= 2,
           let lastRepTimestamp,
           timestamp - lastRepTimestamp >= 4,
           !hasReportedInactivity {
            hasReportedInactivity = true
            onSetInactivityDetected?()
        }

        if smoothedMagnitude >= highThreshold, !isAboveThreshold {
            let enoughTimeElapsed = lastRepTimestamp.map { timestamp - $0 >= minimumRepInterval } ?? true
            if enoughTimeElapsed {
                repTimestamps.append(timestamp)
                peakMagnitudes.append(smoothedMagnitude)
                if let movementStartedAt {
                    concentricDurations.append(max(0, timestamp - movementStartedAt))
                }
                peakStartedAt = timestamp
                lastRepTimestamp = timestamp
                hasReportedInactivity = false
                publishEstimate()
                notifyTempoDeviationIfNeeded()
            }
            isAboveThreshold = true
        } else if smoothedMagnitude <= lowThreshold {
            if isAboveThreshold, let peakStartedAt {
                eccentricDurations.append(max(0, timestamp - peakStartedAt))
                lastMovementEndedAt = timestamp
            }
            isAboveThreshold = false
            movementStartedAt = nil
            peakStartedAt = nil
        } else if isAboveThreshold, !peakMagnitudes.isEmpty {
            peakMagnitudes[peakMagnitudes.count - 1] = max(peakMagnitudes.last ?? 0, smoothedMagnitude)
        }
    }

    private func publishEstimate() {
        let intervals = zip(repTimestamps.dropFirst(), repTimestamps).map { $0 - $1 }
        let averageInterval = average(intervals)
        let intervalConsistency = consistency(of: intervals)
        let amplitudeConsistency = consistency(of: peakMagnitudes)
        let movementConsistency: Double? = {
            guard !peakMagnitudes.isEmpty else { return nil }
            if intervals.isEmpty { return amplitudeConsistency }
            return (intervalConsistency + amplitudeConsistency) / 2
        }()
        let countFactor = min(1, Double(repTimestamps.count) / 5)
        let confidence = min(1, max(0, countFactor * 0.65 + (movementConsistency ?? 0) * 0.35))
        let relativeRange = peakMagnitudes.isEmpty
            ? nil
            : min(1, max(0, (average(peakMagnitudes) ?? 0) / 0.65))
        let velocityLoss = velocityLossPercent(intervals: intervals)
        let axis = dominantAxis()
        let movementTotal = rotationTotal + accelerationTotal

        estimate = WatchMotionEstimate(
            estimatedReps: repTimestamps.count,
            averageRepDuration: averageInterval,
            movementConsistency: movementConsistency,
            confidence: confidence,
            averageConcentricDuration: average(concentricDurations),
            averageEccentricDuration: average(eccentricDurations),
            averagePauseDuration: average(pauseDurations.filter { $0 <= 3 }),
            relativeRangeOfMotion: relativeRange,
            rangeOfMotionConsistency: peakMagnitudes.isEmpty ? nil : amplitudeConsistency,
            velocityLossPercent: velocityLoss,
            dominantAxis: axis,
            rotationalMovementRatio: movementTotal > 0 ? rotationTotal / movementTotal : nil,
            isTempoDeviationDetected: isTempoDeviation(intervals: intervals)
        )
        onEstimateChanged?(estimate)
    }

    private func notifyTempoDeviationIfNeeded() {
        guard estimate.isTempoDeviationDetected,
              repTimestamps.count >= lastTempoAlertRepCount + 3 else {
            return
        }
        lastTempoAlertRepCount = repTimestamps.count
        onTempoDeviationDetected?()
    }

    private func isTempoDeviation(intervals: [Double]) -> Bool {
        guard intervals.count >= 4, let latest = intervals.last else { return false }
        let baselineValues = Array(intervals.prefix(3)).sorted()
        let baseline = baselineValues[baselineValues.count / 2]
        guard baseline > 0 else { return false }
        return abs(latest / baseline - 1) >= 0.35
    }

    private func velocityLossPercent(intervals: [Double]) -> Double? {
        guard intervals.count >= 4 else { return nil }
        let window = max(2, intervals.count / 3)
        guard let first = average(Array(intervals.prefix(window))),
              let last = average(Array(intervals.suffix(window))),
              first > 0 else {
            return nil
        }
        return min(100, max(-100, (last / first - 1) * 100))
    }

    private func dominantAxis() -> String? {
        let values = [("x", axisTotals.x), ("y", axisTotals.y), ("z", axisTotals.z)]
        guard let dominant = values.max(by: { $0.1 < $1.1 }), dominant.1 > 0 else { return nil }
        return dominant.0
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func consistency(of values: [Double]) -> Double {
        guard values.count >= 2 else { return values.isEmpty ? 0 : 0.5 }
        let average = values.reduce(0, +) / Double(values.count)
        guard average > 0 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - average, 2) } / Double(values.count)
        let coefficientOfVariation = sqrt(variance) / average
        return min(1, max(0, 1 - coefficientOfVariation * 1.8))
    }
}
