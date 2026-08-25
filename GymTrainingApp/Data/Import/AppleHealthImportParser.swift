import Foundation

enum AppleHealthImportParser {
    static func parse(
        data: Data,
        fileName: String,
        fingerprint: String,
        options: DataImportOptions
    ) throws -> DataImportPreview {
        let delegate = AppleHealthXMLDelegate(timeZone: options.timeZone)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawHealthRoot else {
            let detail = parser.parserError?.localizedDescription ?? "Apple HealthのXMLではありません。"
            throw DataImportError.malformedFile(detail)
        }

        var warnings = delegate.warnings
        if delegate.skippedRecordCount > 0 {
            warnings.append(.init(
                severity: .caution,
                message: "未対応の種類または値が不正な\(delegate.skippedRecordCount)件を除外しました。"
            ))
        }
        if delegate.workouts.contains(where: { $0.exercises.isEmpty }) {
            warnings.append(.init(
                severity: .information,
                message: "Apple Healthのワークアウトにはセット明細がないため、実施日時と種別だけを取り込みます。"
            ))
        }
        let summary = DataImportSummary(
            workoutCount: delegate.workouts.count,
            exerciseCount: 0,
            setCount: 0,
            bodyMetricCount: delegate.bodyMetrics.count
        )
        return DataImportPreview(
            fileName: fileName,
            fingerprint: fingerprint,
            format: .appleHealthXML,
            payload: DataImportPayload(workouts: delegate.workouts, bodyMetrics: delegate.bodyMetrics),
            summary: summary,
            warnings: warnings,
            requiresWeightUnit: false,
            requiresTimeZoneConfirmation: false,
            wasPreviouslyImported: false
        )
    }
}

private final class AppleHealthXMLDelegate: NSObject, XMLParserDelegate {
    let timeZone: TimeZone
    var sawHealthRoot = false
    var workouts: [WorkoutSession] = []
    var bodyMetrics: [BodyMetricEntry] = []
    var warnings: [DataImportWarning] = []
    var skippedRecordCount = 0

    init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "HealthData", "HealthExport":
            sawHealthRoot = true
        case "Record":
            parseRecord(attributeDict)
        case "Workout":
            parseWorkout(attributeDict)
        default:
            break
        }
    }

    private func parseRecord(_ attributes: [String: String]) {
        guard let type = attributes["type"], let rawValue = attributes["value"],
              let value = Double(rawValue),
              let dateRaw = attributes["startDate"] ?? attributes["creationDate"],
              let date = ImportDateParser.parse(dateRaw, timeZone: timeZone)?.date else {
            return
        }
        let unit = attributes["unit"]?.lowercased() ?? ""
        let entry: BodyMetricEntry?
        switch type {
        case "HKQuantityTypeIdentifierBodyMass":
            guard let normalized = weightInKilograms(value, unit: unit) else {
                skippedRecordCount += 1
                return
            }
            entry = BodyMetricEntry(kind: .bodyWeight, value: normalized, recordedAt: date, note: "Imported from Apple Health")
        case "HKQuantityTypeIdentifierWaistCircumference":
            guard let normalized = lengthInCentimeters(value, unit: unit) else {
                skippedRecordCount += 1
                return
            }
            entry = BodyMetricEntry(kind: .waist, value: normalized, recordedAt: date, note: "Imported from Apple Health")
        case "HKQuantityTypeIdentifierBodyFatPercentage":
            let percentage = unit == "count" && value <= 1 ? value * 100 : value
            entry = BodyMetricEntry(kind: .bodyFatPercentage, value: percentage, recordedAt: date, note: "Imported from Apple Health")
        default:
            return
        }
        if let entry { bodyMetrics.append(entry) }
    }

    private func parseWorkout(_ attributes: [String: String]) {
        guard let startRaw = attributes["startDate"],
              let start = ImportDateParser.parse(startRaw, timeZone: timeZone)?.date else {
            skippedRecordCount += 1
            return
        }
        let end = attributes["endDate"].flatMap { ImportDateParser.parse($0, timeZone: timeZone)?.date }
            ?? durationEndDate(start: start, value: attributes["duration"], unit: attributes["durationUnit"])
            ?? start
        let activity = attributes["workoutActivityType"] ?? "Workout"
        workouts.append(WorkoutSession(
            title: workoutTitle(activity),
            sourcePlanID: nil,
            startedAt: start,
            endedAt: end,
            exercises: [],
            note: "Imported from Apple Health | \(activity)"
        ))
    }

    private func weightInKilograms(_ value: Double, unit: String) -> Double? {
        switch unit {
        case "kg": value
        case "g": value / 1_000
        case "lb", "lbs": value / 2.2046226218
        case "st": value * 6.35029318
        default: nil
        }
    }

    private func lengthInCentimeters(_ value: Double, unit: String) -> Double? {
        switch unit {
        case "cm": value
        case "m": value * 100
        case "in": value * 2.54
        default: nil
        }
    }

    private func durationEndDate(start: Date, value: String?, unit: String?) -> Date? {
        guard let value, let duration = Double(value), duration >= 0 else { return nil }
        let seconds: TimeInterval
        switch unit?.lowercased() {
        case "min": seconds = duration * 60
        case "hr": seconds = duration * 3600
        default: seconds = duration
        }
        return start.addingTimeInterval(seconds)
    }

    private func workoutTitle(_ activity: String) -> String {
        let suffix = activity.replacingOccurrences(of: "HKWorkoutActivityType", with: "")
        let spaced = suffix.reduce(into: "") { result, character in
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return spaced.isEmpty ? "Apple Health Workout" : spaced
    }
}
