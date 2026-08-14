import SwiftUI

struct CoachPersonaPicker: View {
    @Binding var selection: CoachPersona

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("トレーナーを選ぶ")
                .font(.subheadline.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CoachPersona.allCases) { persona in
                        Button {
                            selection = persona
                        } label: {
                            VStack(spacing: 6) {
                                Image(persona.assetName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 68, height: 68)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                selection == persona ? AppTheme.accent : AppTheme.cardBorder,
                                                lineWidth: selection == persona ? 3 : 1
                                            )
                                    }

                                Text(persona.displayName)
                                    .font(.footnote.bold())
                                    .foregroundStyle(selection == persona ? AppTheme.accent : AppTheme.ink)
                            }
                            .frame(width: 76)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("トレーナー \(persona.displayName)")
                        .accessibilityAddTraits(selection == persona ? .isSelected : [])
                        .accessibilityIdentifier("coachPersona-\(persona.rawValue)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityIdentifier("coachPersonaPicker")
    }
}

struct CoachRecommendationPicker: View {
    @Binding var profile: UserProfile

    private var recommendations: [CoachRecommendation] {
        CoachType.recommendations(for: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("目的に合う担当", systemImage: "sparkles")
                .font(.subheadline.bold())

            Text("担当タイプを変えると、AIが優先して見る記録と提案内容が変わります。")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(recommendations) { recommendation in
                Button {
                    profile.coachType = recommendation.coachType
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: profile.coachType == recommendation.coachType ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(profile.coachType == recommendation.coachType ? AppTheme.accent : AppTheme.mutedInk)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(recommendation.coachType.displayName)
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.ink)
                            Text(recommendation.reason)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("選ぶと：\(recommendation.coachType.expertiseProfile.promise)")
                                .font(.caption.bold())
                                .foregroundStyle(AppTheme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recommendedCoach-\(recommendation.coachType.rawValue)")
                .accessibilityAddTraits(profile.coachType == recommendation.coachType ? .isSelected : [])
            }

            Text("担当タイプ＝提案の重点、人物＝名前とアバター、話し方＝言葉づかい。3つは別々に選べます。")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .accessibilityIdentifier("coachRecommendations")
    }
}
