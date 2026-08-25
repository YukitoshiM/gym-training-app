import SwiftUI

struct CoachAvatarView: View {
    let persona: CoachPersona
    var size: CGFloat = 52
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 8

    var body: some View {
        Image(persona.assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: height ?? size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.accent.opacity(0.5), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct CoachAssignmentSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let persona: CoachPersona
    let coachType: CoachType
    let coachingStyle: CoachingStyle
    var recommendationReason: String? = nil

    private var expertise: CoachExpertiseProfile {
        coachType.expertiseProfile
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    CoachAvatarView(persona: persona, size: 124, height: 138)
                    details
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    CoachAvatarView(persona: persona, size: 96, height: 112)
                    details
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coachAssignmentSummary")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("core_ui.57f7d1515dab", fallback: "担当 {{value1}}", values: [String(describing: persona.displayName)]))
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)

            Text(L10n.string("core_ui.3071da6bb538", fallback: "{{value1}}・{{value2}}", values: [String(describing: coachType.displayName), String(describing: coachingStyle.displayName)]))
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.accent)

            Text(persona.bodyGoal)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)

            Text(persona.tagline)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(expertise.promise)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Label(expertise.topFocusAreas.joined(separator: L10n.string("core_ui.3b67eb100838", fallback: "・")), systemImage: "scope")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            if let recommendationReason, !recommendationReason.isEmpty {
                Text(recommendationReason)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CoachIdentityView: View {
    let persona: CoachPersona
    let role: String
    var detail: String? = nil
    var avatarSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoachAvatarView(persona: persona, size: avatarSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(persona.displayName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Text(role)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.accent)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("core_ui.395989968966", fallback: "担当トレーナー {{value1}}、{{value2}}", values: [String(describing: persona.displayName), String(describing: role)]))
        .accessibilityIdentifier("activeCoachIdentity")
    }
}

struct CoachAttributionLabel: View {
    let persona: CoachPersona
    let text: String
    var avatarSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            CoachAvatarView(
                persona: persona,
                size: avatarSize,
                cornerRadius: min(7, avatarSize / 4)
            )
            Text(text)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.accent)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
