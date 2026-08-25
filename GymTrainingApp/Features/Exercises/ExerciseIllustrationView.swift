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
                    Label(L10n.string("training.91665e47ba14", fallback: "フォーム参考"), systemImage: "camera.fill")
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
            L10n.string("training.eb836dfced6d", fallback: "{{value1}}のフォーム参考画像。主な部位は{{value2}}、{{value3}}を使って{{value4}}種目です", values: [String(describing: exercise.name), String(describing: exercise.primaryMuscle.displayName), String(describing: exercise.equipmentSetupName), String(describing: exercise.movementName)])
        )
        .accessibilityIdentifier("exerciseIllustration")
    }
}

#Preview {
    ExerciseIllustrationView(exercise: PresetExerciseStore.exercises[0])
        .padding()
        .background(AppTheme.pageBackground)
}
