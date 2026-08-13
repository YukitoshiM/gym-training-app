import SwiftUI

struct WatchWeightEntryView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    let exerciseID: UUID
    let setID: UUID
    let unit: WatchWeightUnit
    let kilogramRange: ClosedRange<Double>

    @State private var displayedWeight: Double
    @State private var editText: String
    @State private var valueBeforeEditing: Double
    @FocusState private var isTextFieldFocused: Bool
    private let availableStepRange: ClosedRange<Int>

    init(
        exerciseID: UUID,
        setID: UUID,
        currentWeight: Double,
        unit: WatchWeightUnit,
        supportsAssistedLoad: Bool
    ) {
        self.exerciseID = exerciseID
        self.setID = setID
        self.unit = unit
        kilogramRange = supportsAssistedLoad ? AssistedLoadSupport.kilogramRange : 0...999
        let initialKilograms = currentWeight != 0 || supportsAssistedLoad ? currentWeight : 50
        let initialValue = unit == .kg ? initialKilograms : initialKilograms * 2.2046226218
        _displayedWeight = State(initialValue: initialValue)
        _editText = State(initialValue: Self.formatted(initialValue))
        _valueBeforeEditing = State(initialValue: initialValue)
        let conversion = unit == .kg ? 1.0 : 2.2046226218
        let minimumStepIndex = Int((kilogramRange.lowerBound * conversion * 10).rounded(.up))
        let maximumStepIndex = Int((kilogramRange.upperBound * conversion * 10).rounded(.down))
        let center = min(
            maximumStepIndex,
            max(minimumStepIndex, Int((initialValue * 10).rounded()))
        )
        availableStepRange = max(minimumStepIndex, center - 200)...min(maximumStepIndex, center + 200)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Picker("重量", selection: stepIndex) {
                        ForEach(availableStepRange, id: \.self) { value in
                            Text(Self.formatted(Double(value) / 10))
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 118, height: 76)
                    .clipped()
                    .accessibilityLabel("重量")
                    .accessibilityIdentifier("watchWeightPicker")

                    Text(unit.displayName)
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                        .frame(width: 24, alignment: .leading)
                }

                HStack(spacing: 6) {
                    TextField("手入力", text: $editText)
                    .multilineTextAlignment(.center)
                    .focused($isTextFieldFocused)
                    .accessibilityIdentifier("watchWeightField")

                    Text(unit.displayName)
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                }

                Button("反映") {
                    commitManualEntry()
                    let kilograms = unit == .kg ? displayedWeight : displayedWeight / 2.2046226218
                    workoutStore.setWeight(exerciseID: exerciseID, setID: setID, weight: kilograms)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchAppTheme.positive)
                .accessibilityIdentifier("saveWatchWeightButton")
            }
        }
        .navigationTitle("重量")
        .onChange(of: displayedWeight) { _, value in
            guard !isTextFieldFocused else { return }
            editText = Self.formatted(value)
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                valueBeforeEditing = displayedWeight
                editText = ""
            } else {
                commitManualEntry()
            }
        }
    }

    private var displayedStepRange: ClosedRange<Int> {
        let conversion = unit == .kg ? 1.0 : 2.2046226218
        let lowerBound = Int((kilogramRange.lowerBound * conversion * 10).rounded(.up))
        let upperBound = Int((kilogramRange.upperBound * conversion * 10).rounded(.down))
        return lowerBound...upperBound
    }

    private var stepIndex: Binding<Int> {
        Binding(
            get: {
                min(
                    displayedStepRange.upperBound,
                    max(displayedStepRange.lowerBound, Int((displayedWeight * 10).rounded()))
                )
            },
            set: { displayedWeight = Double($0) / 10 }
        )
    }

    private func commitManualEntry() {
        let normalized = editText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else {
            displayedWeight = valueBeforeEditing
            editText = Self.formatted(valueBeforeEditing)
            return
        }
        let rounded = (value * 10).rounded() / 10
        let displayedMinimum = Double(displayedStepRange.lowerBound) / 10
        let displayedMaximum = Double(displayedStepRange.upperBound) / 10
        displayedWeight = min(displayedMaximum, max(displayedMinimum, rounded))
        editText = Self.formatted(displayedWeight)
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

struct WatchTempoEntryView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    let exerciseID: UUID
    let setID: UUID

    @State private var concentricSeconds: Int
    @State private var eccentricSeconds: Int
    @State private var beatSpeed: Int
    @State private var concentricText: String
    @State private var eccentricText: String
    @State private var beatSpeedText: String
    @State private var valueBeforeEditingConcentric: Int
    @State private var valueBeforeEditingEccentric: Int
    @State private var valueBeforeEditingBeatSpeed: Int
    @FocusState private var focusedField: TempoField?

    private enum TempoField: Hashable {
        case concentric
        case eccentric
        case beatSpeed
    }

    init(exerciseID: UUID, setID: UUID, concentricSeconds: Int?, eccentricSeconds: Int?, beatSpeed: Int?) {
        self.exerciseID = exerciseID
        self.setID = setID
        let initialConcentric = concentricSeconds ?? 2
        let initialEccentric = eccentricSeconds ?? 3
        let initialBeatSpeed = beatSpeed ?? 1

        _concentricSeconds = State(initialValue: min(10, max(1, initialConcentric)))
        _eccentricSeconds = State(initialValue: min(10, max(1, initialEccentric)))
        _beatSpeed = State(initialValue: min(3, max(1, initialBeatSpeed)))
        _concentricText = State(initialValue: String(min(10, max(1, initialConcentric))))
        _eccentricText = State(initialValue: String(min(10, max(1, initialEccentric))))
        _beatSpeedText = State(initialValue: String(min(3, max(1, initialBeatSpeed))))
        _valueBeforeEditingConcentric = State(initialValue: min(10, max(1, initialConcentric)))
        _valueBeforeEditingEccentric = State(initialValue: min(10, max(1, initialEccentric)))
        _valueBeforeEditingBeatSpeed = State(initialValue: min(3, max(1, initialBeatSpeed)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                concentricTempoInput

                HStack(spacing: 0) {
                    Picker("下げ", selection: $eccentricSeconds) {
                        ForEach(1...10, id: \.self) { value in
                            Text("\(value)秒")
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 116, height: 76)
                    .clipped()
                    .accessibilityLabel("下げ時間")
                    .accessibilityIdentifier("watchTempoEccentricPicker")

                    Text("下")
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                        .frame(width: 32, alignment: .leading)
                }

                TextField("下げ時間を直接入力", text: $eccentricText)
                    .multilineTextAlignment(.center)
                    .focused($focusedField, equals: .eccentric)
                    .accessibilityIdentifier("watchTempoEccentricField")

                HStack(spacing: 0) {
                    Picker("振動速度", selection: $beatSpeed) {
                        ForEach(1...3, id: \.self) { value in
                            Text("\(value)回/秒")
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 106, height: 76)
                    .clipped()
                    .accessibilityLabel("1秒あたりの振動回数")
                    .accessibilityIdentifier("watchTempoSpeedPicker")

                    Text("速")
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                        .frame(width: 30, alignment: .leading)
                }

                TextField("振動回数(1〜3回/秒)", text: $beatSpeedText)
                    .multilineTextAlignment(.center)
                    .focused($focusedField, equals: .beatSpeed)
                    .accessibilityIdentifier("watchTempoSpeedField")

                Button("反映") {
                    commitManualEntries()
                    workoutStore.setPlannedTempo(
                        exerciseID: exerciseID,
                        setID: setID,
                        concentricSeconds: concentricSeconds,
                        eccentricSeconds: eccentricSeconds,
                        beatSpeed: beatSpeed
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchAppTheme.positive)
                .accessibilityIdentifier("saveWatchTempoButton")
            }
        }
        .navigationTitle("テンポ")
        .onChange(of: concentricSeconds) { _, value in
            guard focusedField != .concentric else { return }
            concentricText = String(value)
        }
        .onChange(of: eccentricSeconds) { _, value in
            guard focusedField != .eccentric else { return }
            eccentricText = String(value)
        }
        .onChange(of: beatSpeed) { _, value in
            guard focusedField != .beatSpeed else { return }
            beatSpeedText = String(value)
        }
        .onChange(of: focusedField) { _, field in
            switch field {
            case .concentric:
                valueBeforeEditingConcentric = concentricSeconds
                concentricText = ""
            case .eccentric:
                valueBeforeEditingEccentric = eccentricSeconds
                eccentricText = ""
            case .beatSpeed:
                valueBeforeEditingBeatSpeed = beatSpeed
                beatSpeedText = ""
            case .none:
                commitManualEntries()
            }
        }
    }

    private var concentricTempoInput: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Picker("上げ", selection: $concentricSeconds) {
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value)秒")
                            .monospacedDigit()
                            .tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(width: 116, height: 76)
                .clipped()
                .accessibilityLabel("上げ時間")
                .accessibilityIdentifier("watchTempoConcentricPicker")

                Text("上")
                    .font(.caption)
                    .foregroundStyle(WatchAppTheme.mutedInk)
                    .frame(width: 32, alignment: .leading)
            }

            TextField("上げ時間を直接入力", text: $concentricText)
                .multilineTextAlignment(.center)
                .focused($focusedField, equals: .concentric)
                .accessibilityIdentifier("watchTempoConcentricField")
        }
    }

    private func commitManualEntries() {
        let parsedConcentric = parse(concentricText, fallback: concentricSeconds, minValue: 1, maxValue: 10)
        let parsedEccentric = parse(eccentricText, fallback: eccentricSeconds, minValue: 1, maxValue: 10)
        let parsedBeatSpeed = parse(beatSpeedText, fallback: beatSpeed, minValue: 1, maxValue: 3)
        concentricSeconds = parsedConcentric
        eccentricSeconds = parsedEccentric
        beatSpeed = parsedBeatSpeed
        concentricText = String(parsedConcentric)
        eccentricText = String(parsedEccentric)
        beatSpeedText = String(parsedBeatSpeed)
    }

    private func parse(
        _ text: String,
        fallback: Int,
        minValue: Int,
        maxValue: Int
    ) -> Int {
        let parsedValue = Int(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
        guard let value = parsedValue else {
            return fallback
        }
        let lower = minValue
        let upper = maxValue
        return Swift.min(Swift.max(lower, value), upper)
    }
}

struct WatchRepsEntryView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    let exerciseID: UUID
    let setID: UUID

    @State private var reps: Int
    @State private var editText: String
    @State private var valueBeforeEditing: Int
    @FocusState private var isTextFieldFocused: Bool

    init(exerciseID: UUID, setID: UUID, currentReps: Int) {
        self.exerciseID = exerciseID
        self.setID = setID
        let initialReps = currentReps > 0 ? currentReps : 10
        _reps = State(initialValue: initialReps)
        _editText = State(initialValue: String(initialReps))
        _valueBeforeEditing = State(initialValue: initialReps)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("回数", selection: $reps) {
                        ForEach(0...999, id: \.self) { value in
                            Text("\(value)")
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 104, height: 80)
                    .clipped()
                    .accessibilityLabel("回数")
                    .accessibilityIdentifier("watchRepsPicker")

                    Text("回")
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                        .frame(width: 28, alignment: .leading)
                }

                TextField("手入力", text: $editText)
                    .multilineTextAlignment(.center)
                    .focused($isTextFieldFocused)
                    .accessibilityIdentifier("watchRepsField")

                Button("反映") {
                    commitManualEntry()
                    workoutStore.setReps(exerciseID: exerciseID, setID: setID, reps: reps)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchAppTheme.positive)
                .accessibilityIdentifier("saveWatchRepsButton")
            }
        }
        .navigationTitle("回数")
        .onChange(of: reps) { _, value in
            guard !isTextFieldFocused else { return }
            editText = String(value)
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                valueBeforeEditing = reps
                editText = ""
            } else {
                commitManualEntry()
            }
        }
    }

    private func commitManualEntry() {
        guard let value = Int(editText) else {
            reps = valueBeforeEditing
            editText = String(valueBeforeEditing)
            return
        }
        reps = min(999, max(0, value))
        editText = String(reps)
    }
}

struct WatchRestTimerEntryView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var seconds: Int
    @State private var editText: String
    @State private var valueBeforeEditing: Int
    @FocusState private var isTextFieldFocused: Bool

    init(currentSeconds: Int) {
        let normalized = min(600, max(5, Int((Double(currentSeconds) / 5).rounded()) * 5))
        _seconds = State(initialValue: normalized)
        _editText = State(initialValue: String(normalized))
        _valueBeforeEditing = State(initialValue: normalized)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("休憩時間", selection: $seconds) {
                        ForEach(Array(stride(from: 5, through: 600, by: 5)), id: \.self) { value in
                            Text(formatDuration(value))
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 112, height: 76)
                    .clipped()
                    .accessibilityLabel("休憩時間")
                    .accessibilityIdentifier("watchRestSecondsPicker")

                    Text("分:秒")
                        .font(.caption2)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                        .frame(width: 36, alignment: .leading)
                }

                HStack(spacing: 6) {
                    TextField("手入力", text: $editText)
                        .multilineTextAlignment(.center)
                        .focused($isTextFieldFocused)
                        .accessibilityIdentifier("watchRestSecondsField")

                    Text("秒")
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                }

                Button("反映") {
                    commitManualEntry()
                    workoutStore.setRestTimer(seconds: seconds)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchAppTheme.positive)
                .accessibilityIdentifier("saveWatchRestSecondsButton")
            }
        }
        .navigationTitle("休憩時間")
        .onChange(of: seconds) { _, value in
            guard !isTextFieldFocused else { return }
            editText = String(value)
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                valueBeforeEditing = seconds
                editText = ""
            } else {
                commitManualEntry()
            }
        }
    }

    private func commitManualEntry() {
        guard let value = Int(editText) else {
            seconds = valueBeforeEditing
            editText = String(valueBeforeEditing)
            return
        }
        seconds = min(600, max(5, Int((Double(value) / 5).rounded()) * 5))
        editText = String(seconds)
    }
}

struct WatchRPESelectionView: View {
    @EnvironmentObject private var workoutStore: WatchWorkoutStore
    @Environment(\.dismiss) private var dismiss

    let exerciseID: UUID
    let setID: UUID

    @State private var rpe: Double
    @State private var editText: String
    @State private var valueBeforeEditing: Double
    @FocusState private var isTextFieldFocused: Bool

    init(exerciseID: UUID, setID: UUID, currentRPE: Double?) {
        self.exerciseID = exerciseID
        self.setID = setID
        let initialRPE = currentRPE ?? 8
        _rpe = State(initialValue: initialRPE)
        _editText = State(initialValue: Self.formatted(initialRPE))
        _valueBeforeEditing = State(initialValue: initialRPE)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Picker("RPE", selection: $rpe) {
                        ForEach(2...20, id: \.self) { halfStep in
                            let value = Double(halfStep) / 2
                            Text(value.formatted(.number.precision(.fractionLength(0...1))))
                                .monospacedDigit()
                                .tag(value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                    .frame(width: 104, height: 80)
                    .clipped()
                    .accessibilityLabel("RPE")
                    .accessibilityIdentifier("watchRPEPicker")

                    Text("RPE")
                        .font(.caption)
                        .foregroundStyle(WatchAppTheme.mutedInk)
                        .frame(width: 34, alignment: .leading)
                }

                TextField("手入力", text: $editText)
                    .multilineTextAlignment(.center)
                    .focused($isTextFieldFocused)
                    .accessibilityIdentifier("watchRPEField")

                Button("反映") {
                    commitManualEntry()
                    workoutStore.updateRPE(exerciseID: exerciseID, setID: setID, rpe: rpe)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchAppTheme.positive)
                .accessibilityIdentifier("saveWatchRPEButton")

                Button("RPEなし") {
                    workoutStore.updateRPE(exerciseID: exerciseID, setID: setID, rpe: nil)
                    dismiss()
                }
                .font(.caption)
                .accessibilityIdentifier("clearWatchRPEButton")
            }
        }
        .navigationTitle("RPE")
        .onChange(of: rpe) { _, value in
            guard !isTextFieldFocused else { return }
            editText = Self.formatted(value)
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                valueBeforeEditing = rpe
                editText = ""
            } else {
                commitManualEntry()
            }
        }
    }

    private func commitManualEntry() {
        let normalized = editText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else {
            rpe = valueBeforeEditing
            editText = Self.formatted(valueBeforeEditing)
            return
        }
        rpe = min(10, max(1, (value * 2).rounded() / 2))
        editText = Self.formatted(rpe)
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
