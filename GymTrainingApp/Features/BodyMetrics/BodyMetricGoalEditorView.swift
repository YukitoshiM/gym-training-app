import SwiftUI

struct BodyMetricGoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore

    let kind: BodyMetricKind

    @State private var targetValueText = ""
    @State private var direction: BodyMetricGoalDirection = .decrease

    private var parsedTargetValue: Double? {
        let trimmed = targetValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("目標値") {
                    NumericTextInputControl(
                        text: $targetValueText,
                        title: "目標値",
                        unit: kind.unit,
                        range: kind.inputRange,
                        step: 0.1,
                        defaultValue: kind.defaultInputValue,
                        accessibilityIdentifier: "bodyMetricGoalField"
                    )
                }

                Section("方向") {
                    Picker("方向", selection: $direction) {
                        ForEach(BodyMetricGoalDirection.allCases) { direction in
                            Text(direction.displayName).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("目標設定")
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
                    .accessibilityIdentifier("saveBodyMetricGoalButton")
                }
            }
            .onAppear {
                let goal = appStore.bodyMetricGoal(for: kind)
                direction = goal.direction
                if let targetValue = goal.targetValue {
                    targetValueText = targetValue.formatted(.number.precision(.fractionLength(0...1)))
                }
            }
        }
    }

    private func save() {
        appStore.saveBodyMetricGoal(
            BodyMetricGoal(
                kind: kind,
                targetValue: parsedTargetValue,
                direction: direction
            )
        )
        dismiss()
    }
}

#Preview {
    BodyMetricGoalEditorView(kind: .bodyWeight)
        .environmentObject(AppStore())
}
