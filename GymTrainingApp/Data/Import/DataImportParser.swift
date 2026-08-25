import CryptoKit
import Foundation

enum DataImportParser {
    static let currentBodyModeSchema = 8

    static func parse(
        data: Data,
        fileName: String,
        options: DataImportOptions,
        knownExercises: [Exercise]
    ) throws -> DataImportPreview {
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let trimmed = data.drop { byte in
            byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d || byte == 0xef || byte == 0xbb || byte == 0xbf
        }

        if trimmed.first == Character("{").asciiValue {
            return try parseBodyModeJSON(data, fileName: fileName, fingerprint: fingerprint)
        }
        if trimmed.first == Character("<").asciiValue {
            return try AppleHealthImportParser.parse(
                data: data,
                fileName: fileName,
                fingerprint: fingerprint,
                options: options
            )
        }
        return try WorkoutCSVImportParser.parse(
            data: data,
            fileName: fileName,
            fingerprint: fingerprint,
            options: options,
            knownExercises: knownExercises
        )
    }

    private static func parseBodyModeJSON(
        _ data: Data,
        fileName: String,
        fingerprint: String
    ) throws -> DataImportPreview {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export: GymDataExport
        do {
            export = try decoder.decode(GymDataExport.self, from: data)
        } catch {
            throw DataImportError.malformedFile("BodyModeバックアップとして解析できません。")
        }
        guard export.schemaVersion <= currentBodyModeSchema else {
            throw DataImportError.newerBodyModeSchema(export.schemaVersion)
        }
        guard export.schemaVersion >= 1 else {
            throw DataImportError.malformedFile("スキーマ番号が不正です。")
        }

        let summary = DataImportSummary(
            workoutCount: export.workoutHistory.count,
            exerciseCount: export.workoutHistory.reduce(0) { $0 + $1.exercises.count },
            setCount: export.workoutHistory.reduce(0) { total, workout in
                total + workout.exercises.reduce(0) { $0 + $1.sets.count }
            },
            bodyMetricCount: export.bodyMetricEntries.count,
            planCount: export.plans.count,
            mealCount: export.mealEntries.count,
            photoCount: export.bodyPhotoEntries.count
        )
        var warnings = [
            DataImportWarning(
                severity: .caution,
                message: "BodyModeの現在の記録を、このバックアップの内容で置き換えます。取り込み後は一括で元に戻せます。"
            )
        ]
        if export.schemaVersion < currentBodyModeSchema {
            warnings.append(.init(
                severity: .information,
                message: "旧スキーマ\(export.schemaVersion)をスキーマ\(currentBodyModeSchema)として復元します。"
            ))
        }
        return DataImportPreview(
            fileName: fileName,
            fingerprint: fingerprint,
            format: .bodyModeJSON,
            payload: DataImportPayload(bodyModeRestore: export),
            summary: summary,
            warnings: warnings,
            requiresWeightUnit: false,
            requiresTimeZoneConfirmation: false,
            wasPreviouslyImported: false
        )
    }
}

private enum WorkoutCSVImportParser {
    private struct ColumnMap {
        var date: String
        var title: String?
        var endDate: String?
        var duration: String?
        var exercise: String
        var setOrder: String?
        var weight: String?
        var weightUnit: WeightUnit?
        var reps: String?
        var rpe: String?
        var setType: String?
        var exerciseNotes: String?
        var workoutNotes: String?
        var distance: String?
        var distanceUnit: String?
        var seconds: String?
    }

    static func parse(
        data: Data,
        fileName: String,
        fingerprint: String,
        options: DataImportOptions,
        knownExercises: [Exercise]
    ) throws -> DataImportPreview {
        let document = try DelimitedTextDocument(data: data)
        let headerIndex = Dictionary(uniqueKeysWithValues: document.headers.map { (normalizedHeader($0), $0) })
        let format = detectFormat(headers: Set(headerIndex.keys), fileName: fileName)
        let columns = try columns(for: format, headers: headerIndex)
        let hasAmbiguousWeights = columns.weight != nil && columns.weightUnit == nil
            && document.rows.contains { double(value($0, columns.weight)) != nil }
        var warnings: [DataImportWarning] = []
        if hasAmbiguousWeights, options.ambiguousWeightUnit == nil {
            warnings.append(.init(severity: .blocking, message: "このCSVには重量単位がありません。kgまたはlbを選択してください。"))
        }

        let grouped = Dictionary(grouping: document.rows) { row in
            let date = value(row, columns.date)
            let title = value(row, columns.title).ifEmpty(format.displayName)
            return "\(date)|\(title)"
        }
        var resolver = ExerciseNameResolver(knownExercises: knownExercises)
        var workouts: [WorkoutSession] = []
        var skippedRows = 0
        var sawMissingTimeZone = false

        for rows in grouped.values {
            guard let first = rows.first,
                  let parsedStart = ImportDateParser.parse(value(first, columns.date), timeZone: options.timeZone) else {
                skippedRows += rows.count
                continue
            }
            sawMissingTimeZone = sawMissingTimeZone || parsedStart.timeZoneWasMissing
            let title = value(first, columns.title).ifEmpty(format.displayName)
            var exerciseGroups: [(String, [[String: String]])] = []
            for row in rows {
                let name = value(row, columns.exercise).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    skippedRows += 1
                    continue
                }
                if let index = exerciseGroups.firstIndex(where: { ExerciseNameResolver.key($0.0) == ExerciseNameResolver.key(name) }) {
                    exerciseGroups[index].1.append(row)
                } else {
                    exerciseGroups.append((name, [row]))
                }
            }

            let exercises = exerciseGroups.enumerated().map { exerciseIndex, group in
                let exercise = resolver.resolve(group.0)
                let rawOrders = group.1.compactMap { int(value($0, columns.setOrder)) }
                let startsAtZero = rawOrders.min() == 0
                let sets = group.1.enumerated().map { rowIndex, row in
                    let rawWeight = double(value(row, columns.weight)) ?? 0
                    let unit = columns.weightUnit ?? options.ambiguousWeightUnit ?? .kg
                    let weight = unit == .lb ? rawWeight / 2.2046226218 : rawWeight
                    let reps = max(0, int(value(row, columns.reps)) ?? 0)
                    let rawOrder = int(value(row, columns.setOrder)) ?? rowIndex + 1
                    let order = startsAtZero ? rawOrder + 1 : max(1, rawOrder)
                    let note = setNote(row: row, columns: columns, format: format)
                    return WorkoutSet(
                        setOrder: order,
                        targetWeight: weight,
                        targetReps: reps,
                        actualWeight: weight,
                        actualReps: reps,
                        isCompleted: true,
                        isAdded: true,
                        rpe: clampedRPE(double(value(row, columns.rpe))),
                        startedAt: parsedStart.date,
                        completedAt: parsedStart.date,
                        note: note
                    )
                }.sorted { $0.setOrder < $1.setOrder }
                return WorkoutExercise(
                    exercise: exercise,
                    sortOrder: exerciseIndex,
                    restSeconds: 90,
                    sets: sets
                )
            }

            guard !exercises.isEmpty else { continue }
            let explicitEnd = value(first, columns.endDate)
            let endedAt = ImportDateParser.parse(explicitEnd, timeZone: options.timeZone)?.date
                ?? ImportDurationParser.endDate(start: parsedStart.date, rawValue: value(first, columns.duration))
                ?? parsedStart.date
            workouts.append(WorkoutSession(
                title: title,
                sourcePlanID: nil,
                startedAt: parsedStart.date,
                endedAt: endedAt,
                exercises: exercises,
                note: importWorkoutNote(first, columns: columns, format: format)
            ))
        }

        if skippedRows > 0 {
            warnings.append(.init(severity: .caution, message: "日時または種目名を読み取れない\(skippedRows)行を除外しました。"))
        }
        if sawMissingTimeZone, !options.hasConfirmedTimeZone {
            warnings.append(.init(
                severity: .blocking,
                message: "日時にタイムゾーンがありません。\(options.timeZone.identifier)として読み込むか確認してください。"
            ))
        }
        if resolver.createdExercises.isEmpty == false {
            warnings.append(.init(
                severity: .information,
                message: "未登録の\(resolver.createdExercises.count)種目は、元の名前を保ったカスタム種目として追加します。"
            ))
        }
        if format == .genericCSV {
            warnings.append(.init(severity: .information, message: "列名から一般CSVとして判定しました。プレビューの件数と単位を確認してください。"))
        }

        let exerciseCount = workouts.reduce(0) { $0 + $1.exercises.count }
        let setCount = workouts.reduce(0) { total, workout in
            total + workout.exercises.reduce(0) { $0 + $1.sets.count }
        }
        return DataImportPreview(
            fileName: fileName,
            fingerprint: fingerprint,
            format: format,
            payload: DataImportPayload(workouts: workouts, customExercises: resolver.createdExercises),
            summary: DataImportSummary(workoutCount: workouts.count, exerciseCount: exerciseCount, setCount: setCount),
            warnings: warnings,
            requiresWeightUnit: hasAmbiguousWeights,
            requiresTimeZoneConfirmation: sawMissingTimeZone,
            wasPreviouslyImported: false
        )
    }

    private static func detectFormat(headers: Set<String>, fileName: String) -> DataImportFormat {
        if ["date", "workoutname", "exercisename", "setorder"].allSatisfy(headers.contains) {
            return .strongCSV
        }
        if ["title", "starttime", "exercisetitle", "setindex"].allSatisfy(headers.contains) {
            return .hevyCSV
        }
        let normalizedFileName = normalizedHeader(fileName)
        if normalizedFileName.contains("jefit")
            || headers.contains("onerm")
            || headers.contains("routineid")
            || (headers.contains("exercise") && headers.contains("logdate")) {
            return .jefitCSV
        }
        return .genericCSV
    }

    private static func columns(for format: DataImportFormat, headers: [String: String]) throws -> ColumnMap {
        func column(_ aliases: [String]) -> String? {
            aliases.compactMap { headers[normalizedHeader($0)] }.first
        }
        guard let date = column(["date", "start_time", "start date", "workout_date", "log_date", "timestamp"]),
              let exercise = column(["exercise name", "exercise_title", "exercise", "exercise_name", "name"]) else {
            throw DataImportError.malformedFile("日時列と種目名列が必要です。")
        }
        let kgColumn = column(["weight_kg", "weight (kg)", "kg"])
        let lbColumn = column(["weight_lbs", "weight_lb", "weight (lb)", "lbs"])
        let distanceMeters = column(["distance_meters", "distance_m"])
        let distanceKM = column(["distance_km"])
        return ColumnMap(
            date: date,
            title: column(["workout name", "title", "routine", "routine_name", "workout", "session_name"]),
            endDate: column(["end_time", "end date", "end_time_local"]),
            duration: column(["duration", "workout_duration"]),
            exercise: exercise,
            setOrder: column(["set order", "set_index", "set", "set_number", "set_no"]),
            weight: kgColumn ?? lbColumn ?? column(["weight", "lifting_mass"]),
            weightUnit: kgColumn != nil ? .kg : (lbColumn != nil ? .lb : nil),
            reps: column(["reps", "rep", "repetitions"]),
            rpe: column(["rpe"]),
            setType: column(["set_type", "set type"]),
            exerciseNotes: column(["notes", "exercise_notes", "set_notes"]),
            workoutNotes: column(["workout notes", "description", "workout_notes"]),
            distance: distanceMeters ?? distanceKM ?? column(["distance"]),
            distanceUnit: distanceMeters != nil ? "m" : (distanceKM != nil ? "km" : nil),
            seconds: column(["seconds", "duration_seconds"])
        )
    }

    private static func value(_ row: [String: String], _ column: String?) -> String {
        guard let column else { return "" }
        return row[column]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func double(_ rawValue: String) -> Double? {
        let cleaned = rawValue.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private static func int(_ rawValue: String) -> Int? {
        Int(rawValue) ?? Double(rawValue).map(Int.init)
    }

    private static func clampedRPE(_ value: Double?) -> Double? {
        value.map { min(10, max(1, $0)) }
    }

    private static func setNote(row: [String: String], columns: ColumnMap, format: DataImportFormat) -> String? {
        var details = ["Imported from \(format.displayName)"]
        let setType = value(row, columns.setType)
        if !setType.isEmpty, setType.lowercased() != "normal" {
            details.append("Set type: \(setType)")
        }
        let distance = value(row, columns.distance)
        if !distance.isEmpty {
            details.append("Distance: \(distance)\(columns.distanceUnit.map { " \($0)" } ?? "")")
        }
        let seconds = value(row, columns.seconds)
        if !seconds.isEmpty { details.append("Duration: \(seconds) sec") }
        let note = value(row, columns.exerciseNotes)
        if !note.isEmpty { details.append(note) }
        return details.joined(separator: " | ")
    }

    private static func importWorkoutNote(_ row: [String: String], columns: ColumnMap, format: DataImportFormat) -> String {
        let note = value(row, columns.workoutNotes)
        return ["Imported from \(format.displayName)", note].filter { !$0.isEmpty }.joined(separator: " | ")
    }

    private static func normalizedHeader(_ value: String) -> String {
        String(
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        )
    }
}

private struct ExerciseNameResolver {
    private var knownExercises: [Exercise]
    private(set) var createdExercises: [Exercise] = []

    init(knownExercises: [Exercise]) {
        self.knownExercises = knownExercises
    }

    mutating func resolve(_ sourceName: String) -> Exercise {
        let sourceKey = Self.key(sourceName)
        if let match = (knownExercises + createdExercises).first(where: { Self.key($0.name) == sourceKey }) {
            return match
        }
        if let match = knownExercises.first(where: { aliasMatch(sourceKey, exerciseName: $0.name) }) {
            return match
        }
        let exercise = Exercise(
            name: sourceName.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryMuscle: inferredMuscle(sourceKey),
            equipment: inferredEquipment(sourceKey),
            instruction: "Imported exercise. Add instructions in the exercise editor."
        )
        createdExercises.append(exercise)
        return exercise
    }

    static func key(_ value: String) -> String {
        String(
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        )
    }

    private func aliasMatch(_ sourceKey: String, exerciseName: String) -> Bool {
        let target = Self.key(exerciseName)
        let aliases: [[String]] = [
            ["benchpress", "barbellbenchpress", "ベンチプレス"],
            ["squat", "barbellsquat", "スクワット"],
            ["deadlift", "barbelldeadlift", "デッドリフト"],
            ["latpulldown", "ラットプルダウン"],
            ["overheadpress", "shoulderpress", "ショルダープレス"],
            ["pullup", "chinup", "チンニング", "懸垂"],
            ["dip", "dips", "ディップス"]
        ]
        return aliases.contains { group in
            group.contains(sourceKey) && group.contains(where: { target.contains(Self.key($0)) })
        }
    }

    private func inferredEquipment(_ key: String) -> Equipment {
        if key.contains("dumbbell") || key.contains("ダンベル") { return .dumbbell }
        if key.contains("barbell") || key.contains("バーベル") { return .barbell }
        if key.contains("cable") || key.contains("ケーブル") { return .cable }
        if key.contains("smith") || key.contains("スミス") { return .smithMachine }
        if key.contains("machine") || key.contains("マシン") { return .machine }
        if key.contains("bodyweight") || key.contains("pushup") || key.contains("pullup") { return .bodyweight }
        return .other
    }

    private func inferredMuscle(_ key: String) -> MuscleGroup {
        if key.contains("bench") || key.contains("chest") || key.contains("fly") { return .chest }
        if key.contains("row") || key.contains("pull") || key.contains("deadlift") { return .back }
        if key.contains("shoulder") || key.contains("overhead") { return .shoulders }
        if key.contains("curl") || key.contains("bicep") { return .biceps }
        if key.contains("tricep") || key.contains("dip") { return .triceps }
        if key.contains("squat") || key.contains("legpress") || key.contains("extension") { return .quadriceps }
        if key.contains("hamstring") || key.contains("legcurl") { return .hamstrings }
        if key.contains("calf") { return .calves }
        if key.contains("ab") || key.contains("crunch") || key.contains("plank") { return .core }
        return .fullBody
    }
}

enum ImportDateParser {
    struct Result {
        var date: Date
        var timeZoneWasMissing: Bool
    }

    static func parse(_ rawValue: String, timeZone: TimeZone) -> Result? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let hasOffset = value.hasSuffix("Z") || value.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return Result(date: date, timeZoneWasMissing: !hasOffset) }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return Result(date: date, timeZoneWasMissing: !hasOffset) }

        let formats = [
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "d MMM yyyy, HH:mm:ss",
            "d MMM yyyy, HH:mm",
            "MMM d, yyyy HH:mm:ss",
            "MMM d, yyyy HH:mm",
            "M/d/yyyy H:mm",
            "MM/dd/yyyy HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return Result(date: date, timeZoneWasMissing: !format.contains("Z"))
            }
        }
        return nil
    }
}

private enum ImportDurationParser {
    static func endDate(start: Date, rawValue: String) -> Date? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value), seconds > 0 {
            return start.addingTimeInterval(seconds)
        }
        let clock = value.split(separator: ":").compactMap { Double($0) }
        if clock.count == 3 {
            return start.addingTimeInterval(clock[0] * 3600 + clock[1] * 60 + clock[2])
        }
        if clock.count == 2 {
            return start.addingTimeInterval(clock[0] * 60 + clock[1])
        }
        let hours = capture(value, pattern: #"([0-9.]+)\s*h"#) ?? 0
        let minutes = capture(value, pattern: #"([0-9.]+)\s*m"#) ?? 0
        let seconds = capture(value, pattern: #"([0-9.]+)\s*s"#) ?? 0
        let total = hours * 3600 + minutes * 60 + seconds
        return total > 0 ? start.addingTimeInterval(total) : nil
    }

    private static func capture(_ value: String, pattern: String) -> Double? {
        guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(value[range].filter { $0.isNumber || $0 == "." })
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
