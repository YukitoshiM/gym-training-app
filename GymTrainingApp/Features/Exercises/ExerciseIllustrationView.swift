import SwiftUI

struct ExercisePhotoCropView: View {
    let exercise: Exercise

    var body: some View {
        let reference = exercise.photoReference

        GeometryReader { geometry in
            Image(reference.atlasName)
                .resizable()
                .scaledToFill()
                .frame(
                    width: geometry.size.width * 3,
                    height: geometry.size.height * 2
                )
                .offset(
                    x: -CGFloat(reference.column) * geometry.size.width,
                    y: -CGFloat(reference.row) * geometry.size.height
                )
        }
        .clipped()
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct ExerciseIllustrationView: View {
    let exercise: Exercise

    var body: some View {
        VStack(spacing: 12) {
            ExercisePhotoCropView(exercise: exercise)
                .overlay(alignment: .bottomLeading) {
                    Label("フォーム参考", systemImage: "camera.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.68), in: Capsule())
                        .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .accessibilityIdentifier("exercisePhoto")

            HStack(spacing: 8) {
                Label(exercise.movementName, systemImage: exercise.movementSystemImage)
                Spacer(minLength: 8)
                Label(exercise.equipmentSetupName, systemImage: exercise.equipment.systemImage)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(exercise.name)のフォーム参考画像。主な部位は\(exercise.primaryMuscle.displayName)、\(exercise.equipmentSetupName)を使って\(exercise.movementName)種目です"
        )
        .accessibilityIdentifier("exerciseIllustration")
    }
}

#Preview {
    ExerciseIllustrationView(exercise: PresetExerciseStore.exercises[0])
        .padding()
        .background(AppTheme.pageBackground)
}
