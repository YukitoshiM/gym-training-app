import XCTest
@testable import GymTrainingApp

final class CoachMessageFormattingTests: XCTestCase {
    func testMarkdownReplyBecomesScannableBlocks() {
        let content = """
        今週は重量を維持して、回復を優先しましょう。

        ### 現状
        - 睡眠時間が不足しています
        - 主力種目のRPEが高めです

        ### 次にやること
        1. 今夜は7時間以上眠る
        2. 次回はセット数を1つ減らす
        """

        XCTAssertEqual(
            CoachMessageFormatter().blocks(from: content),
            [
                .paragraph("今週は重量を維持して、回復を優先しましょう。"),
                .heading("現状"),
                .bullet("睡眠時間が不足しています"),
                .bullet("主力種目のRPEが高めです"),
                .heading("次にやること"),
                .numbered(1, "今夜は7時間以上眠る"),
                .numbered(2, "次回はセット数を1つ減らす")
            ]
        )
    }

    func testLegacyLongReplyIsSplitIntoParagraphs() {
        let content = "近年のトレーニング記録を見ると、主力種目では安定したセット数をこなせています。体感的な疲労の増大は回復と栄養のバランスを確認するサインかもしれません。筋肉の成長には適切な刺激だけでなく、十分な睡眠とたんぱく質を含む総摂取量の確保が不可欠です。直近1週間で不足していると感じる要素はありますか？まずは回復の質を確認しましょう。"

        let blocks = CoachMessageFormatter().blocks(from: content)
        XCTAssertGreaterThanOrEqual(blocks.count, 3)
        XCTAssertTrue(blocks.allSatisfy {
            if case .paragraph = $0 { return true }
            return false
        })
        XCTAssertTrue(blocks.contains(.paragraph("直近1週間で不足していると感じる要素はありますか？")))
    }

    func testPlainTextHeadingsAndJapaneseBulletsRemainReadableInOlderBuilds() {
        let content = """
        結論です。

        【現状】
        ・疲労度が高めです

        【次にやること】
        1. セット数を減らす
        """

        XCTAssertEqual(
            CoachMessageFormatter().blocks(from: content),
            [
                .paragraph("結論です。"),
                .heading("現状"),
                .bullet("疲労度が高めです"),
                .heading("次にやること"),
                .numbered(1, "セット数を減らす")
            ]
        )
    }

    func testFollowUpQuestionsAreLimitedToTwo() {
        let content = """
        ### 確認したいこと
        睡眠は何時間でしたか？
        疲労感は10段階でいくつですか？
        食事量は足りていますか？

        回答できる範囲で大丈夫です。
        """

        let sanitized = CoachReplyPolicy.limitingFollowUpQuestions(content)

        XCTAssertTrue(sanitized.contains("睡眠は何時間でしたか？"))
        XCTAssertTrue(sanitized.contains("疲労感は10段階でいくつですか？"))
        XCTAssertFalse(sanitized.contains("食事量は足りていますか？"))
        XCTAssertTrue(sanitized.contains("回答できる範囲で大丈夫です。"))
    }
}
