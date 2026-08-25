import Foundation
import SwiftUI

enum CoachMessageBlock: Equatable {
    case heading(String)
    case paragraph(String)
    case bullet(String)
    case numbered(Int, String)
}

struct CoachMessageFormatter {
    func blocks(from rawContent: String) -> [CoachMessageBlock] {
        let content = normalizedContent(rawContent)
        guard !content.isEmpty else { return [] }

        var blocks: [CoachMessageBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            if let heading = headingText(in: line) {
                flushParagraph()
                blocks.append(.heading(heading))
            } else if let bullet = bulletText(in: line) {
                flushParagraph()
                blocks.append(.bullet(bullet))
            } else if let numbered = numberedText(in: line) {
                flushParagraph()
                blocks.append(.numbered(numbered.number, numbered.text))
            } else {
                paragraphLines.append(line)
            }
        }

        flushParagraph()
        return blocks
    }

    private func normalizedContent(_ rawContent: String) -> String {
        let content = rawContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard content.count >= 140, !content.contains("\n") else { return content }

        let sentences = sentences(in: content)
        guard sentences.count > 1 else { return content }

        var paragraphs: [String] = []
        var current = ""

        func flushCurrent() {
            guard !current.isEmpty else { return }
            paragraphs.append(current)
            current = ""
        }

        for sentence in sentences {
            let isQuestion = sentence.hasSuffix("？") || sentence.hasSuffix("?")
            if isQuestion {
                flushCurrent()
                paragraphs.append(sentence)
            } else if current.isEmpty {
                current = sentence
            } else if current.count + sentence.count > 100 {
                flushCurrent()
                current = sentence
            } else {
                current += sentence
            }
        }

        flushCurrent()
        return paragraphs.joined(separator: "\n\n")
    }

    private func sentences(in content: String) -> [String] {
        let endings: Set<Character> = ["。", "！", "？", "!", "?"]
        var result: [String] = []
        var current = ""

        for character in content {
            current.append(character)
            if endings.contains(character) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { result.append(sentence) }
                current = ""
            }
        }

        let remainder = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty { result.append(remainder) }
        return result
    }

    private func headingText(in line: String) -> String? {
        if line.hasPrefix("【"), line.hasSuffix("】"), line.count > 2 {
            return String(line.dropFirst().dropLast())
        }

        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...4).contains(markerCount) else { return nil }
        let remainder = line.dropFirst(markerCount)
        guard remainder.first == " " else { return nil }
        let heading = remainder.trimmingCharacters(in: .whitespaces)
        return heading.isEmpty ? nil : heading
    }

    private func bulletText(in line: String) -> String? {
        for prefix in ["- ", "* ", "• ", L10n.string("core_ui.3b67eb100838", fallback: "・")] where line.hasPrefix(prefix) {
            let text = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private func numberedText(in line: String) -> (number: Int, text: String)? {
        guard let separatorIndex = line.firstIndex(where: { $0 == "." || $0 == ")" }) else {
            return nil
        }
        let numberText = line[..<separatorIndex]
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              let number = Int(numberText) else {
            return nil
        }

        let textStart = line.index(after: separatorIndex)
        guard textStart < line.endIndex, line[textStart].isWhitespace else { return nil }
        let text = line[line.index(after: textStart)...].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }
}

enum CoachReplyPolicy {
    static let maximumFollowUpQuestions = 2

    static func limitingFollowUpQuestions(_ content: String) -> String {
        var result = ""
        var segment = ""
        var questionCount = 0
        let sentenceEndings: Set<Character> = ["。", "！", "？", ".", "!", "?"]

        func appendSegment() {
            guard !segment.isEmpty else { return }
            let isQuestion = segment.last == "？" || segment.last == "?"
            if isQuestion {
                questionCount += 1
            }
            if !isQuestion || questionCount <= maximumFollowUpQuestions {
                result += segment
            }
            segment = ""
        }

        for character in content {
            if character == "\n" {
                appendSegment()
                result.append(character)
                continue
            }
            segment.append(character)
            if sentenceEndings.contains(character) {
                appendSegment()
            }
        }
        appendSegment()
        return result
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CoachFormattedText: View {
    let content: String

    private var blocks: [CoachMessageBlock] {
        CoachMessageFormatter().blocks(from: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: CoachMessageBlock) -> some View {
        switch block {
        case let .heading(text):
            inlineText(text)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .padding(.top, 2)

        case let .paragraph(text):
            inlineText(text)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(4)

        case let .bullet(text):
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(AppTheme.accent)
                    .frame(width: 6, height: 6)
                    .padding(.top, 8)

                inlineText(text)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(3)
            }

        case let .numbered(number, text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minWidth: 24, alignment: .leading)

                inlineText(text)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(3)
            }
        }
    }

    private func inlineText(_ content: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let attributed = try? AttributedString(markdown: content, options: options) else {
            return Text(content)
        }
        return Text(attributed)
    }
}
