import SwiftUI

struct CoachPersonaPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: CoachPersona
    @Binding var coachingStyle: CoachingStyle
    let coachType: CoachType

    private var personas: [CoachPersona] {
        CoachPersona.options(for: coachType)
    }

    private var cardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 224 : 188
    }

    private var imageHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 190 : 158
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("core_ui.c7b878740639", fallback: "この目的のトレーナー"))
                .font(.subheadline.bold())

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(personas) { persona in
                            Button {
                                selection = persona
                                coachingStyle = persona.recommendedStyle
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(persona.assetName)
                                            .resizable()
                                            .interpolation(.high)
                                            .scaledToFill()
                                            .frame(width: cardWidth, height: imageHeight)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))

                                        if selection == persona {
                                            Image(systemName: "checkmark")
                                                .font(.headline.bold())
                                                .foregroundStyle(AppTheme.onAccent)
                                                .frame(width: 34, height: 34)
                                                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 7))
                                                .padding(6)
                                        }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                selection == persona ? AppTheme.accent : AppTheme.cardBorder,
                                                lineWidth: selection == persona ? 3 : 1
                                            )
                                    }

                                    Text(persona.displayName)
                                        .font(.title3.bold())
                                        .foregroundStyle(selection == persona ? AppTheme.accent : AppTheme.ink)
                                        .lineLimit(1)

                                    Text(persona.bodyGoal)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(AppTheme.ink)
                                        .lineLimit(2)

                                    Text(persona.characterSummary)
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.mutedInk)
                                        .lineLimit(3)
                                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 74 : 54, alignment: .top)
                                }
                                .frame(width: cardWidth, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                L10n.string("core_ui.5b622cf96e0e", fallback: "トレーナー {{value1}}、{{value2}}、{{value3}}、{{value4}}", values: [String(describing: persona.displayName), String(describing: persona.gender.displayName), String(describing: persona.bodyGoal), String(describing: persona.characterSummary)])
                            )
                            .accessibilityValue(selection == persona ? L10n.string("core_ui.1588c48590fa", fallback: "選択中") : "")
                            .accessibilityAddTraits(selection == persona ? .isSelected : [])
                            .accessibilityIdentifier("coachPersona-\(persona.rawValue)")
                            .id(persona.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    alignSelection()
                    proxy.scrollTo(selection.id, anchor: .center)
                }
                .onChange(of: coachType) { _, _ in
                    alignSelection()
                }
                .onChange(of: selection) { _, persona in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(persona.id, anchor: .center)
                    }
                }
            }
        }
        .accessibilityIdentifier("coachPersonaPicker")
    }

    private func alignSelection() {
        let resolved = selection.replacement(for: coachType)
        guard resolved != selection else { return }
        selection = resolved
        coachingStyle = resolved.recommendedStyle
    }
}

struct CoachRecommendationPicker: View {
    @Binding var profile: UserProfile

    private var recommendations: [CoachRecommendation] {
        CoachType.recommendations(for: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("core_ui.0ec1ab5accd8", fallback: "目的に合う担当"), systemImage: "sparkles")
                .font(.subheadline.bold())

            Text(L10n.string("core_ui.a2190945ec45", fallback: "担当タイプを変えると、AIが優先して見る記録と提案内容が変わります。"))
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(recommendations) { recommendation in
                Button {
                    profile.coachType = recommendation.coachType
                    profile.coachPersona = profile.coachPersona.replacement(for: recommendation.coachType)
                    profile.coachingStyle = profile.coachPersona.recommendedStyle
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
                            Text(L10n.string("core_ui.9de73676efe0", fallback: "選ぶと：{{value1}}", values: [String(describing: recommendation.coachType.expertiseProfile.promise)]))
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

            Text(L10n.string("core_ui.6d46fc51fc89", fallback: "目的ごとに2人の人物を用意しています。人物を変えると、理想体型と話し方が変わります。"))
                .font(.caption)
                .foregroundStyle(AppTheme.mutedInk)
        }
        .accessibilityIdentifier("coachRecommendations")
    }
}
