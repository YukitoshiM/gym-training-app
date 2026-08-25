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

        return Double(trimmed.replacingOccurrences(of: ",", with: ".")).map { kind.storedValue(fromDisplayed: $0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("health_meals_body_ai.85361e8b23b9", fallback: "目標値")) {
                    NumericTextInputControl(
                        text: $targetValueText,
                        title: L10n.string("health_meals_body_ai.85361e8b23b9", fallback: "目標値"),
                        unit: kind.unit,
                        range: kind.displayedValue(fromStored: kind.inputRange.lowerBound)...kind.displayedValue(fromStored: kind.inputRange.upperBound),
                        step: 0.1,
                        defaultValue: kind.displayedValue(fromStored: kind.defaultInputValue),
                        accessibilityIdentifier: "bodyMetricGoalField"
                    )
                }

                Section(L10n.string("health_meals_body_ai.a75904915773", fallback: "方向")) {
                    Picker(L10n.string("health_meals_body_ai.a75904915773", fallback: "方向"), selection: $direction) {
                        ForEach(BodyMetricGoalDirection.allCases) { direction in
                            Text(direction.displayName).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("health_meals_body_ai.7b0fb61cbb59", fallback: "目標設定"))
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
                    .accessibilityIdentifier("saveBodyMetricGoalButton")
                }
            }
            .onAppear {
                let goal = appStore.bodyMetricGoal(for: kind)
                direction = goal.direction
                if let targetValue = goal.targetValue {
                    targetValueText = kind.displayedValue(fromStored: targetValue).formatted(.number.precision(.fractionLength(0...1)))
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
