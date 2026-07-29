import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.name)
                        .font(.title2.bold())
                    Text("\(exercise.primaryMuscle.displayName)・\(exercise.equipment.displayName)")
                        .foregroundStyle(AppTheme.mutedInk)
                }
                .padding(.vertical, 8)
            }

            Section("対象部位") {
                LabeledContent("メイン", value: exercise.primaryMuscle.displayName)

                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent(
                        "サブ",
                        value: exercise.secondaryMuscles.map(\.displayName).joined(separator: "、")
                    )
                }
            }

            Section("器具") {
                Text(exercise.equipment.displayName)
            }

            Section("やり方") {
                Text(exercise.instruction)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.pageBackground)
        .navigationTitle("種目詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ExerciseDetailView(exercise: PresetExerciseStore.exercises[0])
    }
}
