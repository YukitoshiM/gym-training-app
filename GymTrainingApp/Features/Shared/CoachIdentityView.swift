import SwiftUI

struct CoachAvatarView: View {
    let persona: CoachPersona
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 8

    var body: some View {
        Image(persona.assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(AppTheme.accent.opacity(0.5), lineWidth: 1)
            }
            .accessibilityHidden(true)
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
        .accessibilityLabel("担当トレーナー \(persona.displayName)、\(role)")
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
