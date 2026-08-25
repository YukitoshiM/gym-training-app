import SwiftUI

struct BodyMetricEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager

    let kind: BodyMetricKind
    let entry: BodyMetricEntry?

    @State private var valueText = ""
    @State private var recordedAt = Date()
    @State private var note = ""
    @State private var isShowingValidation = false

    init(kind: BodyMetricKind, entry: BodyMetricEntry? = nil) {
        self.kind = kind
        self.entry = entry
    }

    private var parsedValue: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: ".")).map { kind.storedValue(fromDisplayed: $0) }
    }

    private var canSave: Bool {
        guard let parsedValue else {
            return false
        }

        return parsedValue > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.displayName) {
                    NumericTextInputControl(
                        text: $valueText,
                        title: L10n.string("health_meals_body_ai.8bb7c26634ce", fallback: "値"),
                        unit: kind.unit,
                        range: displayedRange,
                        step: 0.1,
                        defaultValue: kind.displayedValue(fromStored: kind.defaultInputValue),
                        accessibilityIdentifier: "bodyMetricValueField"
                    )

                    DatePicker(
                        L10n.string("health_meals_body_ai.c5deaf60f00d", fallback: "記録日"),
                        selection: $recordedAt,
                        in: RecordDatePolicy.allowedRange(),
                        displayedComponents: .date
                    )
                }

                Section(L10n.string("health_meals_body_ai.03b5d7044111", fallback: "メモ")) {
                    TextField(L10n.string("health_meals_body_ai.d7efe8748167", fallback: "任意"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("health_meals_body_ai.7b34b98fc5f0", fallback: "{{value1}}を記録", values: [String(describing: kind.displayName)]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("health_meals_body_ai.dd84abcb6681", fallback: "キャンセル")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("health_meals_body_ai.1e18f9b0644c", fallback: "保存")) {
                        save()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveBodyMetricEntryButton")
                }
            }
            .onAppear {
                guard valueText.isEmpty else { return }
                let initialValue = entry?.value
                    ?? appStore.latestBodyMetricEntry(for: kind)?.value
                    ?? kind.defaultInputValue
                valueText = kind.displayedValue(fromStored: initialValue).formatted(.number.precision(.fractionLength(0...1)))
                recordedAt = RecordDatePolicy.normalizedDay(entry?.recordedAt ?? Date())
                note = entry?.note ?? ""
            }
            .alert(L10n.string("health_meals_body_ai.06aa9ac77950", fallback: "保存できません"), isPresented: $isShowingValidation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(L10n.string("health_meals_body_ai.24a8a9fb448f", fallback: "0より大きい数値を入力してください。"))
            }
        }
    }

    private var displayedRange: ClosedRange<Double> {
        kind.displayedValue(fromStored: kind.inputRange.lowerBound)...kind.displayedValue(fromStored: kind.inputRange.upperBound)
    }

    private func save() {
        guard let parsedValue, parsedValue > 0 else {
            isShowingValidation = true
            return
        }

        let entry = BodyMetricEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            value: parsedValue,
            recordedAt: RecordDatePolicy.normalizedDay(recordedAt),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        appStore.saveBodyMetricEntry(entry)
        Task { await healthDataManager.saveBodyMetricIfAuthorized(entry) }
        dismiss()
    }
}

#Preview {
    BodyMetricEntryEditorView(kind: .bodyWeight)
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
}
