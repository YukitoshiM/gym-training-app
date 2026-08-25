import Foundation
import XCTest
@testable import GymTrainingApp

@MainActor
final class AICreditStoreKitTests: XCTestCase {
    func testLocalConfigurationDefinesEveryConsumableCreditProduct() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "BodyMode", withExtension: "storekit"))
        let data = try Data(contentsOf: url)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(payload["products"] as? [[String: Any]])
        let productsByID = Dictionary(uniqueKeysWithValues: products.compactMap { product in
            (product["productID"] as? String).map { ($0, product) }
        })

        XCTAssertEqual(Set(productsByID.keys), Set(AICreditPurchaseStore.productIDs))
        assertProduct(productsByID["com.yukitoshim.gymtrainingapp.credits50"], price: "1.99")
        assertProduct(productsByID["com.yukitoshim.gymtrainingapp.credits150"], price: "4.99")
        assertProduct(productsByID["com.yukitoshim.gymtrainingapp.credits500"], price: "12.99")
    }

    func testCreditAmountsMatchConfiguredProductIdentifiers() {
        XCTAssertEqual(AICreditPurchaseStore.creditAmount(for: AICreditPurchaseStore.productIDs[0]), 50)
        XCTAssertEqual(AICreditPurchaseStore.creditAmount(for: AICreditPurchaseStore.productIDs[1]), 150)
        XCTAssertEqual(AICreditPurchaseStore.creditAmount(for: AICreditPurchaseStore.productIDs[2]), 500)
    }

    func testUsageExamplesReflectFeatureCreditCosts() {
        XCTAssertEqual(
            AICreditPurchaseStore.usageExamples(for: "com.yukitoshim.gymtrainingapp.credits50"),
            .init(chat: 50, mealAnalysis: 16, bodyPhotoAnalysis: 12)
        )
        XCTAssertEqual(
            AICreditPurchaseStore.usageExamples(for: "com.yukitoshim.gymtrainingapp.credits150"),
            .init(chat: 150, mealAnalysis: 50, bodyPhotoAnalysis: 37)
        )
        XCTAssertEqual(
            AICreditPurchaseStore.usageExamples(for: "com.yukitoshim.gymtrainingapp.credits500"),
            .init(chat: 500, mealAnalysis: 166, bodyPhotoAnalysis: 125)
        )
    }

    private func assertProduct(
        _ product: [String: Any]?,
        price: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let product else {
            XCTFail("Missing StoreKit product", file: file, line: line)
            return
        }
        XCTAssertEqual(product["type"] as? String, "Consumable", file: file, line: line)
        XCTAssertEqual(product["displayPrice"] as? String, price, file: file, line: line)
        let localizations = product["localizations"] as? [[String: Any]] ?? []
        XCTAssertEqual(
            Set(localizations.compactMap { $0["locale"] as? String }),
            Set(["ja_JP", "en_US"]),
            file: file,
            line: line
        )
        XCTAssertTrue(
            localizations.allSatisfy {
                !($0["displayName"] as? String ?? "").isEmpty
                    && !($0["description"] as? String ?? "").isEmpty
            },
            file: file,
            line: line
        )
    }
}
