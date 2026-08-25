import SwiftUI
import PhotosUI
import UIKit
@preconcurrency import Vision
import VisionKit

struct FoodCompositionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onSelect: (MealCompositionItem) -> Void

    private var results: [FoodCompositionItem] {
        FoodCompositionDatabase.shared.search(query)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L10n.string("health_meals_body_ai.4d24a28d4ef0", fallback: "食品名を検索"), text: $query)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("foodDatabaseSearchField")
                }

                Section(L10n.string("health_meals_body_ai.51b278066b12", fallback: "食品")) {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        ForEach(results) { food in
                            Button {
                                onSelect(MealCompositionItem(food: food))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(food.name)
                                        .font(.body.bold())
                                        .foregroundStyle(AppTheme.ink)
                                    Text("100g: \(Int(food.calories.rounded()))kcal  P\(Int(food.protein.rounded()))  F\(Int(food.fat.rounded()))  C\(Int(food.carbs.rounded()))")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.mutedInk)
                                    if let note = food.dataQualityNote {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.warning)
                                    }
                                }
                            }
                            .accessibilityIdentifier("foodDatabaseResult-\(food.id)")
                        }
                    }
                }

                Section {
                    Text(FoodCompositionDatabase.shared.catalog.attribution)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                    Text(L10n.string("health_meals_body_ai.066be6f8dc2d", fallback: "{{value1}}・訂正 {{value2}}", values: [String(describing: FoodCompositionDatabase.shared.catalog.basis), String(describing: FoodCompositionDatabase.shared.catalog.correctionDate)]))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                    Text(L10n.string("health_meals_body_ai.42539e8231ed", fallback: "「-」は未測定として合計から除外し、「Tr」は微量として0で概算します。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .navigationTitle(L10n.string("health_meals_body_ai.3d6e7d3996d5", fallback: "食品DB"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("health_meals_body_ai.ffadd0622088", fallback: "閉じる")) { dismiss() }
                }
            }
        }
    }
}

struct BarcodeFoodPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var basisAmount = "100"
    @State private var amount = "100"
    @State private var calories = "0"
    @State private var protein = "0"
    @State private var fat = "0"
    @State private var carbs = "0"
    @State private var isShowingScanner = false
    @State private var nutritionLabelPhoto: PhotosPickerItem?
    @State private var isReadingNutritionLabel = false
    @State private var nutritionSourceDescription: String?
    @State private var nutritionSourceUpdatedAt: Date?
    @State private var notice: String?

    let onSelect: (MealCompositionItem) -> Void

    var body: some View {
        let nutritionLabelButtonTitle = isReadingNutritionLabel
            ? L10n.string("health_meals_body_ai.78cd1b7ccb8e", fallback: "栄養表示を読取中")
            : L10n.string("health_meals_body_ai.a3f776f9b426", fallback: "栄養表示の写真から入力")

        NavigationStack {
            Form {
                Section(L10n.string("health_meals_body_ai.5ce14bc41fd3", fallback: "商品コード")) {
                    HStack(spacing: 10) {
                        TextField("JAN / EAN", text: $code)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("barcodeManualField")
                        Button {
                            lookup()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(L10n.string("health_meals_body_ai.6bfd0c245861", fallback: "登録済み商品を検索"))
                    }

                    if DataScannerViewController.isSupported,
                       DataScannerViewController.isAvailable {
                        Button {
                            isShowingScanner = true
                        } label: {
                            Label(L10n.string("health_meals_body_ai.db59ae95c8ef", fallback: "カメラで読み取る"), systemImage: "barcode.viewfinder")
                        }
                        .accessibilityIdentifier("scanBarcodeButton")
                    }

                    PhotosPicker(selection: $nutritionLabelPhoto, matching: .images) {
                        Label(
                            nutritionLabelButtonTitle,
                            systemImage: "text.viewfinder"
                        )
                    }
                    .disabled(isReadingNutritionLabel)
                    .accessibilityIdentifier("scanNutritionLabelButton")

                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                Section(L10n.string("health_meals_body_ai.6622f6b6d24f", fallback: "商品")) {
                    TextField(L10n.string("health_meals_body_ai.2a6a23ccdb93", fallback: "商品名"), text: $name)
                        .accessibilityIdentifier("barcodeProductNameField")
                    NumericTextInputControl(
                        text: $basisAmount,
                        title: L10n.string("health_meals_body_ai.9bf285f4e0ce", fallback: "ラベルの基準量"),
                        unit: "g",
                        range: 0.1...2_000,
                        step: 0.1,
                        defaultValue: 100,
                        accessibilityIdentifier: "barcodeBasisAmountField"
                    )
                    NumericTextInputControl(
                        text: $amount,
                        title: L10n.string("health_meals_body_ai.33cef63d33eb", fallback: "実食量"),
                        unit: "g",
                        range: 0...2_000,
                        step: 1,
                        defaultValue: 100,
                        accessibilityIdentifier: "barcodeAmountField"
                    )
                }

                Section(L10n.string("health_meals_body_ai.ea5962a2dde7", fallback: "基準量当たり")) {
                    NumericTextInputControl(
                        text: $calories,
                        title: L10n.string("health_meals_body_ai.a412f109a6d5", fallback: "カロリー"),
                        unit: "kcal",
                        range: 0...1_000,
                        step: 1,
                        defaultValue: 0,
                        accessibilityIdentifier: "barcodeCaloriesField"
                    )
                    NumericTextInputControl(
                        text: $protein,
                        title: L10n.string("health_meals_body_ai.140a2c34da87", fallback: "たんぱく質"),
                        unit: "g",
                        range: 0...100,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "barcodeProteinField"
                    )
                    NumericTextInputControl(
                        text: $fat,
                        title: L10n.string("health_meals_body_ai.c20a7b4dbb8b", fallback: "脂質"),
                        unit: "g",
                        range: 0...100,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "barcodeFatField"
                    )
                    NumericTextInputControl(
                        text: $carbs,
                        title: L10n.string("health_meals_body_ai.09beaa3b972f", fallback: "炭水化物"),
                        unit: "g",
                        range: 0...100,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "barcodeCarbsField"
                    )
                    Text(L10n.string("health_meals_body_ai.1b0c2ec5452e", fallback: "未登録商品は入力後に端末へ保存し、次回の読取で再利用します。"))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                    if let nutritionSourceDescription {
                        Text(
                            L10n.string("health_meals_body_ai.048097c4c2a5", fallback: "情報源：{{value1}}", values: [String(describing: nutritionSourceDescription)])
                            + (nutritionSourceUpdatedAt.map { L10n.string("health_meals_body_ai.ac2ad0f51452", fallback: "・{{value1}}", values: [String(describing: $0.formatted(date: .abbreviated, time: .omitted))]) } ?? "")
                        )
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedInk)
                    }
                }
            }
            .navigationTitle(L10n.string("health_meals_body_ai.f15118749eab", fallback: "バーコード"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("health_meals_body_ai.76b8d9691185", fallback: "追加")) { addProduct() }
                        .disabled(normalizedCode.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("addBarcodeFoodButton")
                }
            }
            .fullScreenCover(isPresented: $isShowingScanner) {
                BarcodeScannerView { scannedCode in
                    code = scannedCode
                    isShowingScanner = false
                    lookup()
                } onCancel: {
                    isShowingScanner = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: nutritionLabelPhoto) { _, item in
                readNutritionLabel(from: item)
            }
        }
    }

    private var normalizedCode: String {
        code.filter(\.isNumber)
    }

    private func lookup() {
        code = normalizedCode
        guard !code.isEmpty else {
            notice = L10n.string("health_meals_body_ai.43dc3b27e76e", fallback: "商品コードを入力してください。")
            return
        }
        guard let product = BarcodeFoodProductStore().product(for: code) else {
            notice = L10n.string("health_meals_body_ai.406225b8c87e", fallback: "未登録です。ラベルの100g当たりの数値を入力してください。")
            return
        }
        name = product.name
        basisAmount = formatted(product.basisAmountGrams)
        calories = formatted(product.nutritionPerBasis.calories)
        protein = formatted(product.nutritionPerBasis.protein)
        fat = formatted(product.nutritionPerBasis.fat)
        carbs = formatted(product.nutritionPerBasis.carbs)
        nutritionSourceDescription = product.sourceDescription
        nutritionSourceUpdatedAt = product.sourceUpdatedAt
        notice = L10n.string("health_meals_body_ai.4fd6f0c4f98f", fallback: "端末に保存した商品を読み込みました。")
    }

    private func readNutritionLabel(from item: PhotosPickerItem?) {
        guard let item else { return }
        isReadingNutritionLabel = true
        notice = nil
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw NutritionLabelReaderError.invalidImage
                }
                let draft = try await NutritionLabelReader.read(from: data)
                await MainActor.run {
                    if let value = draft.basisAmountGrams { basisAmount = formatted(value) }
                    if let value = draft.calories { calories = formatted(value) }
                    if let value = draft.protein { protein = formatted(value) }
                    if let value = draft.fat { fat = formatted(value) }
                    if let value = draft.carbs { carbs = formatted(value) }
                    nutritionSourceDescription = L10n.string("health_meals_body_ai.31969faf266a", fallback: "栄養成分表示OCR（要確認）")
                    nutritionSourceUpdatedAt = Date()
                    notice = L10n.string("health_meals_body_ai.0eea7055641a", fallback: "栄養表示から数値を入力しました。基準量と各数値を確認してください。")
                    isReadingNutritionLabel = false
                }
            } catch {
                await MainActor.run {
                    notice = L10n.string("health_meals_body_ai.d4de549ad1bc", fallback: "栄養表示を読み取れませんでした。明るい場所で正面から撮り直すか、手入力してください。")
                    isReadingNutritionLabel = false
                }
            }
        }
    }

    private func addProduct() {
        let product = BarcodeFoodProduct(
            code: normalizedCode,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            basisAmountGrams: max(0.1, parsed(basisAmount)),
            nutritionPerBasis: NutritionAmount(
                calories: parsed(calories),
                protein: parsed(protein),
                fat: parsed(fat),
                carbs: parsed(carbs)
            ),
            sourceDescription: nutritionSourceDescription == L10n.string("health_meals_body_ai.31969faf266a", fallback: "栄養成分表示OCR（要確認）")
                ? L10n.string("health_meals_body_ai.8fa1b3c8eff2", fallback: "栄養成分表示OCR（ユーザー確認）")
                : nutritionSourceDescription,
            sourceUpdatedAt: nutritionSourceUpdatedAt
        )
        do {
            try BarcodeFoodProductStore().save(product)
            onSelect(product.mealItem(amountGrams: parsed(amount)))
            dismiss()
        } catch {
            notice = L10n.string("health_meals_body_ai.6a08e330f48e", fallback: "商品を保存できませんでした。")
            AppDiagnostics.shared.record(error: error, category: "food.barcode", message: "Failed to save barcode food")
        }
    }

    private func parsed(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

struct NutritionLabelDraft: Equatable, Sendable {
    var basisAmountGrams: Double?
    var calories: Double?
    var protein: Double?
    var fat: Double?
    var carbs: Double?

    var hasNutrition: Bool {
        calories != nil || protein != nil || fat != nil || carbs != nil
    }
}

enum NutritionLabelReaderError: Error {
    case invalidImage
    case nutritionNotFound
}

enum NutritionLabelReader {
    static func read(from imageData: Data) async throws -> NutritionLabelDraft {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
                throw NutritionLabelReaderError.invalidImage
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
            return try parse(text)
        }.value
    }

    static func parse(_ recognizedText: String) throws -> NutritionLabelDraft {
        let text = normalizedNumbers(in: recognizedText)
            .replacingOccurrences(of: "\n", with: " ")
        let draft = NutritionLabelDraft(
            basisAmountGrams: firstValue(
                in: text,
                patterns: [#"([0-9]+(?:\.[0-9]+)?)\s*g\s*(?:当たり|あたり|当り)"#]
            ),
            calories: firstValue(
                in: text,
                patterns: [#"(?:熱量|エネルギー|calories?)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*k?cal"#]
            ),
            protein: firstValue(
                in: text,
                patterns: [#"(?:たんぱく質|タンパク質|蛋白質|protein)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*g"#]
            ),
            fat: firstValue(
                in: text,
                patterns: [#"(?:脂質|fat)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*g"#]
            ),
            carbs: firstValue(
                in: text,
                patterns: [#"(?:炭水化物|糖質|carbohydrates?|carbs?)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*g"#]
            )
        )
        guard draft.hasNutrition else { throw NutritionLabelReaderError.nutritionNotFound }
        return draft
    }

    private static func normalizedNumbers(in text: String) -> String {
        let replacements: [Character: Character] = [
            "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
            "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
            "．": ".", "，": ","
        ]
        return String(text.map { replacements[$0] ?? $0 })
    }

    private static func firstValue(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = expression.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                  ),
                  let range = Range(match.range(at: 1), in: text),
                  let value = Double(text[range]) else {
                continue
            }
            return value
        }
        return nil
    }
}

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            return UIHostingController(
                rootView: ContentUnavailableView(
                    L10n.string("health_meals_body_ai.0b497fb0939d", fallback: "カメラ読取を利用できません"),
                    systemImage: "barcode.viewfinder",
                    description: Text(L10n.string("health_meals_body_ai.e9d4a9038ed6", fallback: "商品コードを手入力してください。"))
                )
            )
        }
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let item = addedItems.first,
                  case .barcode(let barcode) = item,
                  let payload = barcode.payloadStringValue else { return }
            dataScanner.stopScanning()
            onScan(payload)
        }
    }
}
