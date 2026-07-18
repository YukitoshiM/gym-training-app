import SwiftUI

struct BodyMetricEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var healthDataManager: HealthDataManager

    let kind: BodyMetricKind

    @State private var valueText = ""
    @State private var recordedAt = Date()
    @State private var note = ""
    @State private var isShowingValidation = false

    private var parsedValue: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: "."))
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
                        title: "値",
                        unit: kind.unit,
                        range: kind.inputRange,
                        step: 0.1,
                        defaultValue: kind.defaultInputValue,
                        accessibilityIdentifier: "bodyMetricValueField"
                    )

                    DatePicker("記録日", selection: $recordedAt, displayedComponents: .date)
                }

                Section("メモ") {
                    TextField("任意", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("\(kind.displayName)を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveBodyMetricEntryButton")
                }
            }
            .onAppear {
                if valueText.isEmpty,
                   let latest = appStore.latestBodyMetricEntry(for: kind) {
                    valueText = latest.value.formatted(.number.precision(.fractionLength(0...1)))
                }
            }
            .alert("保存できません", isPresented: $isShowingValidation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("0より大きい数値を入力してください。")
            }
        }
    }

    private func save() {
        guard let parsedValue, parsedValue > 0 else {
            isShowingValidation = true
            return
        }

        let entry = BodyMetricEntry(
            kind: kind,
            value: parsedValue,
            recordedAt: recordedAt,
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
