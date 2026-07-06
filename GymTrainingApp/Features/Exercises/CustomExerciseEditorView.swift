import SwiftUI

struct CustomExerciseEditorView: View {
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var primaryMuscle: MuscleGroup = .chest
    @State private var equipment: Equipment = .machine
    @State private var instruction = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("種目名", text: $name)
                        .accessibilityIdentifier("customExerciseNameField")

                    Picker("主な部位", selection: $primaryMuscle) {
                        ForEach(MuscleGroup.allCases) { muscle in
                            Text(muscle.displayName).tag(muscle)
                        }
                    }

                    Picker("器具", selection: $equipment) {
                        ForEach(Equipment.allCases) { equipment in
                            Text(equipment.displayName).tag(equipment)
                        }
                    }
                }

                Section("メモ") {
                    TextField("フォームや注意点", text: $instruction, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }
            }
            .navigationTitle("カスタム種目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveCustomExerciseButton")
                }
            }
        }
    }

    private func save() {
        appStore.saveCustomExercise(
            Exercise(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                primaryMuscle: primaryMuscle,
                equipment: equipment,
                instruction: instruction.isEmpty ? "ユーザー追加種目" : instruction
            )
        )
        dismiss()
    }
}

#Preview {
    CustomExerciseEditorView()
        .environmentObject(AppStore())
}
