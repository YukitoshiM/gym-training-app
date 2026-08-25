import Foundation

struct BodyMetricEstimate: Identifiable, Equatable {
    var kind: BodyMetricKind
    var value: Double
    var lowerBound: Double
    var upperBound: Double
    var rationale: String
    var id: BodyMetricKind { kind }

    var rangeText: String {
        "\(AppFormatters.metricValue(lowerBound, unit: kind.unit))〜\(AppFormatters.metricValue(upperBound, unit: kind.unit))"
    }

    func approvedEntry(at date: Date = Date()) -> BodyMetricEntry {
        BodyMetricEntry(
            kind: kind,
            value: value,
            recordedAt: date,
            note: L10n.string("release_delta.estimate_note", fallback: "参考推定。実測値ではありません。{{value1}}", values: [rationale]),
            isEstimated: true,
            estimateLowerBound: lowerBound,
            estimateUpperBound: upperBound
        )
    }
}

enum BodyMetricEstimateService {
    static func photoEstimates(
        from references: [BodyPhotoReferenceEstimate],
        existingEntries: [BodyMetricEntry],
        at date: Date,
        calendar: Calendar = .current
    ) -> [BodyMetricEntry] {
        let grouped = Dictionary(grouping: references.compactMap { reference -> (BodyMetricKind, BodyPhotoReferenceEstimate)? in
            guard let kind = metricKind(for: reference.metric),
                  reference.lowerBound.isFinite,
                  reference.upperBound.isFinite else { return nil }
            return (kind, reference)
        }, by: { $0.0 })

        return grouped.compactMap { kind, values in
            guard !existingEntries.contains(where: {
                $0.kind == kind && calendar.isDate($0.recordedAt, inSameDayAs: date)
            }) else { return nil }

            let normalized = values.map { value -> (lower: Double, upper: Double, center: Double) in
                let lower = min(value.1.lowerBound, value.1.upperBound)
                let upper = max(value.1.lowerBound, value.1.upperBound)
                return (lower, upper, (lower + upper) / 2)
            }
            let centers = normalized.map(\.center).sorted()
            guard !centers.isEmpty else { return nil }
            let average = centers.reduce(0, +) / Double(centers.count)
            let median: Double
            if centers.count.isMultiple(of: 2) {
                median = (centers[centers.count / 2 - 1] + centers[centers.count / 2]) / 2
            } else {
                median = centers[centers.count / 2]
            }
            let value = min(average, median)
            let lowerBound = normalized.map(\.lower).min() ?? value
            let upperBound = normalized.map(\.upper).max() ?? value
            guard kind.inputRange.contains(value) else { return nil }

            return BodyMetricEntry(
                kind: kind,
                value: value,
                recordedAt: date,
                note: L10n.string(
                    "release_delta.photo_estimate_note",
                    fallback: "体型写真AIによる参考推定。実測値ではありません。{{value1}}",
                    values: [values.first?.1.rationale ?? ""]
                ),
                isEstimated: true,
                estimateLowerBound: lowerBound,
                estimateUpperBound: upperBound
            )
        }
        .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    static func estimates(
        entries: [BodyMetricEntry],
        profile: UserProfile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [BodyMetricEstimate] {
        BodyMetricKind.allCases.compactMap { kind in
            let values = entries
                .filter { $0.kind == kind && $0.isEstimated != true }
                .sorted { $0.recordedAt > $1.recordedAt }
            if let latest = values.first,
               calendar.dateComponents([.day], from: latest.recordedAt, to: now).day ?? 0 >= 7 {
                let margin = switch kind {
                case .bodyWeight: max(1, latest.value * 0.02)
                case .waist: 3.0
                case .bodyFatPercentage: 3.0
                }
                return BodyMetricEstimate(
                    kind: kind,
                    value: latest.value,
                    lowerBound: max(kind.inputRange.lowerBound, latest.value - margin),
                    upperBound: min(kind.inputRange.upperBound, latest.value + margin),
                    rationale: L10n.string("release_delta.estimate_stale_reason", fallback: "最後の実測値から期間が空いているため、変化を断定せず幅を持たせています。")
                )
            }
            let latestActualWeight = entries
                .filter { $0.kind == .bodyWeight && $0.isEstimated != true }
                .max(by: { $0.recordedAt < $1.recordedAt })?.value
            if kind == .bodyFatPercentage,
               values.isEmpty,
               let weight = latestActualWeight,
               let height = profile.heightCm, height > 0,
               let birthYear = profile.birthYear,
               let sexOffset = sexOffset(profile.sex) {
                let age = max(18, calendar.component(.year, from: now) - birthYear)
                let bmi = weight / pow(height / 100, 2)
                let center = 1.2 * bmi + 0.23 * Double(age) - sexOffset - 5.4
                let clamped = min(60, max(3, center))
                return BodyMetricEstimate(
                    kind: kind,
                    value: clamped,
                    lowerBound: max(3, clamped - 5),
                    upperBound: min(60, clamped + 5),
                    rationale: L10n.string("release_delta.body_fat_estimate_reason", fallback: "身長・体重・年齢・性別による集団式の参考範囲で、個人の体脂肪率を測定した値ではありません。")
                )
            }
            return nil
        }
    }

    private static func sexOffset(_ sex: Sex) -> Double? {
        switch sex {
        case .male: 10.8
        case .female: 0
        case .unspecified: nil
        }
    }

    private static func metricKind(for metric: String) -> BodyMetricKind? {
        switch metric {
        case "body_fat_percent": .bodyFatPercentage
        default: nil
        }
    }
}
