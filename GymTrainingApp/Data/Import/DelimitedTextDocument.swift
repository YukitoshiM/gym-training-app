import Foundation

struct DelimitedTextDocument {
    var headers: [String]
    var rows: [[String: String]]

    init(data: Data) throws {
        guard var text = String(data: data, encoding: .utf8) else {
            throw DataImportError.malformedFile("UTF-8のCSVではありません。")
        }
        text = text.trimmingPrefix("\u{feff}")
        let delimiter = Self.detectDelimiter(in: text)
        let records = try Self.parseRecords(text, delimiter: delimiter)
        guard let first = records.first, !first.isEmpty else {
            throw DataImportError.malformedFile("ヘッダーがありません。")
        }
        let parsedHeaders = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let parsedRows = records.dropFirst().filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }.map { values in
            Dictionary(uniqueKeysWithValues: parsedHeaders.enumerated().map { index, header in
                (header, values.indices.contains(index) ? values[index] : "")
            })
        }
        headers = parsedHeaders
        rows = parsedRows
    }

    private static func detectDelimiter(in text: String) -> Character {
        let firstRecord = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? text
        let candidates: [Character] = [",", "\t", ";", "|"]
        return candidates.max { lhs, rhs in
            firstRecord.filter { $0 == lhs }.count < firstRecord.filter { $0 == rhs }.count
        } ?? ","
    }

    private static func parseRecords(_ text: String, delimiter: Character) throws -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var isQuoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if isQuoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                isQuoted.toggle()
            } else if character == delimiter, !isQuoted {
                record.append(field)
                field = ""
            } else if character.isNewline, !isQuoted {
                if character == "\n" || !field.isEmpty || !record.isEmpty {
                    record.append(field)
                    records.append(record)
                    record = []
                    field = ""
                }
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        guard !isQuoted else {
            throw DataImportError.malformedFile("引用符が閉じられていません。")
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
