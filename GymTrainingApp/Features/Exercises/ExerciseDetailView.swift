import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.name)
                        .font(.title2.bold())

                    HStack(spacing: 12) {
                        Label(exercise.primaryMuscle.displayName, systemImage: exercise.primaryMuscle.systemImage)
                        Label(exercise.equipment.displayName, systemImage: exercise.equipment.systemImage)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedInk)

                    ExerciseIllustrationView(exercise: exercise)
                        .padding(.top, 6)
                }
                .padding(.vertical, 8)
            }

            Section("対象部位") {
                LabeledContent {
                    Text(exercise.primaryMuscle.displayName)
                } label: {
                    Label("メイン", systemImage: exercise.primaryMuscle.systemImage)
                }

                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent {
                        Text(exercise.secondaryMuscles.map(\.displayName).joined(separator: "、"))
                    } label: {
                        Label("サブ", systemImage: "figure.mixed.cardio")
                    }
                }
            }

            Section("器具") {
                Label(exercise.equipmentSetupName, systemImage: exercise.equipment.systemImage)
                Text(exercise.equipment.usageDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Section("やり方") {
                Label(exercise.movementName, systemImage: exercise.movementSystemImage)
                    .font(.headline)
                Text(exercise.instruction)
                    .lineSpacing(3)
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
