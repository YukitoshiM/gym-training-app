import SwiftUI
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
                    TextField("食品名を検索", text: $query)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("foodDatabaseSearchField")
                }

                Section("食品") {
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
                                    Text("100g: \(Int(food.calories.rounded()))kcal  P\(food.protein.formatted(.number.precision(.fractionLength(0...1))))  F\(food.fat.formatted(.number.precision(.fractionLength(0...1))))  C\(food.carbs.formatted(.number.precision(.fractionLength(0...1))))")
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
                    Text("\(FoodCompositionDatabase.shared.catalog.basis)・訂正 \(FoodCompositionDatabase.shared.catalog.correctionDate)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                    Text("「-」は未測定として合計から除外し、「Tr」は微量として0で概算します。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .navigationTitle("食品DB")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
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
    @State private var notice: String?

    let onSelect: (MealCompositionItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("商品コード") {
                    HStack(spacing: 10) {
                        TextField("JAN / EAN", text: $code)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("barcodeManualField")
                        Button {
                            lookup()
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("登録済み商品を検索")
                    }

                    if DataScannerViewController.isSupported,
                       DataScannerViewController.isAvailable {
                        Button {
                            isShowingScanner = true
                        } label: {
                            Label("カメラで読み取る", systemImage: "barcode.viewfinder")
                        }
                        .accessibilityIdentifier("scanBarcodeButton")
                    }

                    if let notice {
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                }

                Section("商品") {
                    TextField("商品名", text: $name)
                        .accessibilityIdentifier("barcodeProductNameField")
                    NumericTextInputControl(
                        text: $basisAmount,
                        title: "ラベルの基準量",
                        unit: "g",
                        range: 0.1...2_000,
                        step: 0.1,
                        defaultValue: 100,
                        accessibilityIdentifier: "barcodeBasisAmountField"
                    )
                    NumericTextInputControl(
                        text: $amount,
                        title: "実食量",
                        unit: "g",
                        range: 0...2_000,
                        step: 1,
                        defaultValue: 100,
                        accessibilityIdentifier: "barcodeAmountField"
                    )
                }

                Section("基準量当たり") {
                    NumericTextInputControl(
                        text: $calories,
                        title: "カロリー",
                        unit: "kcal",
                        range: 0...1_000,
                        step: 1,
                        defaultValue: 0,
                        accessibilityIdentifier: "barcodeCaloriesField"
                    )
                    NumericTextInputControl(
                        text: $protein,
                        title: "たんぱく質",
                        unit: "g",
                        range: 0...100,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "barcodeProteinField"
                    )
                    NumericTextInputControl(
                        text: $fat,
                        title: "脂質",
                        unit: "g",
                        range: 0...100,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "barcodeFatField"
                    )
                    NumericTextInputControl(
                        text: $carbs,
                        title: "炭水化物",
                        unit: "g",
                        range: 0...100,
                        step: 0.1,
                        defaultValue: 0,
                        accessibilityIdentifier: "barcodeCarbsField"
                    )
                    Text("未登録商品は入力後に端末へ保存し、次回の読取で再利用します。")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                }
            }
            .navigationTitle("バーコード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("追加") { addProduct() }
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
        }
    }

    private var normalizedCode: String {
        code.filter(\.isNumber)
    }

    private func lookup() {
        code = normalizedCode
        guard !code.isEmpty else {
            notice = "商品コードを入力してください。"
            return
        }
        guard let product = BarcodeFoodProductStore().product(for: code) else {
            notice = "未登録です。ラベルの100g当たりの数値を入力してください。"
            return
        }
        name = product.name
        basisAmount = formatted(product.basisAmountGrams)
        calories = formatted(product.nutritionPerBasis.calories)
        protein = formatted(product.nutritionPerBasis.protein)
        fat = formatted(product.nutritionPerBasis.fat)
        carbs = formatted(product.nutritionPerBasis.carbs)
        notice = "端末に保存した商品を読み込みました。"
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
            )
        )
        do {
            try BarcodeFoodProductStore().save(product)
            onSelect(product.mealItem(amountGrams: parsed(amount)))
            dismiss()
        } catch {
            notice = "商品を保存できませんでした。"
            AppDiagnostics.shared.record(error: error, category: "food.barcode", message: "Failed to save barcode food")
        }
    }

    private func parsed(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
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
                    "カメラ読取を利用できません",
                    systemImage: "barcode.viewfinder",
                    description: Text("商品コードを手入力してください。")
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
