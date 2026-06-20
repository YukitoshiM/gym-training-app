import SwiftUI

struct ExerciseListView: View {
    @State private var searchText = ""

    private var filteredExercises: [Exercise] {
        guard !searchText.isEmpty else {
            return PresetExerciseStore.exercises
        }

        return PresetExerciseStore.exercises.filter {
            $0.name.localizedStandardContains(searchText)
            || $0.primaryMuscle.displayName.localizedStandardContains(searchText)
            || $0.equipment.displayName.localizedStandardContains(searchText)
        }
    }

    private var groupedExercises: [(muscle: MuscleGroup, exercises: [Exercise])] {
        MuscleGroup.allCases.compactMap { muscle in
            let exercises = filteredExercises.filter { $0.primaryMuscle == muscle }
            return exercises.isEmpty ? nil : (muscle, exercises)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedExercises, id: \.muscle) { group in
                    Section(group.muscle.displayName) {
                        ForEach(group.exercises) { exercise in
                            NavigationLink(value: exercise) {
                                ExerciseRow(exercise: exercise)
                            }
                        }
                    }
                }
            }
            .navigationTitle("種目")
            .searchable(text: $searchText, prompt: "種目名・部位・器具")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
        }
    }
}

private struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.headline)
            Text("\(exercise.primaryMuscle.displayName)・\(exercise.equipment.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ExerciseListView()
}

