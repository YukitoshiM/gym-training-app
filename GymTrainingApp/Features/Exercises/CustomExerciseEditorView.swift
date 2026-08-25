import SwiftUI

struct CustomExerciseEditorView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var primaryMuscle: MuscleGroup = .chest
    @State private var equipment: Equipment = .machine
    @State private var instruction = ""

    let onSaved: (Exercise) -> Void

    init(initialName: String = "", onSaved: @escaping (Exercise) -> Void = { _ in }) {
        _name = State(initialValue: initialName)
        self.onSaved = onSaved
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.string("training.ac1592e85d63", fallback: "基本")) {
                    TextField(L10n.string("training.ee4c1cfcf5fd", fallback: "種目名"), text: $name)
                        .accessibilityIdentifier("customExerciseNameField")

                    Picker(L10n.string("training.fff037a8485f", fallback: "主な部位"), selection: $primaryMuscle) {
                        ForEach(MuscleGroup.allCases) { muscle in
                            Text(muscle.displayName).tag(muscle)
                        }
                    }

                    Picker(L10n.string("training.9c2c951fe4e9", fallback: "器具"), selection: $equipment) {
                        ForEach(Equipment.allCases) { equipment in
                            Text(equipment.displayName).tag(equipment)
                        }
                    }
                }

                Section(L10n.string("training.ef172c6f0ed0", fallback: "メモ")) {
                    TextField(L10n.string("training.9b2888ed5a36", fallback: "フォームや注意点"), text: $instruction, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("training.98bbb4bec719", fallback: "カスタム種目"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("training.76c1a8f001dd", fallback: "キャンセル")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string("training.0fcb170ec7cf", fallback: "保存")) {
                        save()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveCustomExerciseButton")
                }
            }
        }
    }

    private func save() {
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryMuscle: primaryMuscle,
            equipment: equipment,
            instruction: instruction.isEmpty ? L10n.string("training.2424db9d2280", fallback: "ユーザー追加種目") : instruction
        )
        appStore.saveCustomExercise(exercise)
        onSaved(exercise)
        dismiss()
    }
}

#Preview {
    CustomExerciseEditorView()
        .environmentObject(AppStore())
}
