import SwiftUI

enum AppTourStateStore {
    static let pendingKey = "bodymode.appTour.pending"

    static func schedule(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingKey)
    }

    static func shouldPresent(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if arguments.contains("--disable-app-tour") { return false }
        return arguments.contains("--force-app-tour") || defaults.bool(forKey: pendingKey)
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingKey)
    }
}

extension Notification.Name {
    static let startBodyModeAppTour = Notification.Name("bodymode.startAppTour")
}

struct AppTutorialStep: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let detail: String
    let destination: String
    let systemImage: String
}

enum AppTutorialContent {
    static let steps: [AppTutorialStep] = [
        AppTutorialStep(
            id: "record",
            number: 1,
            title: L10n.string("core_ui.0676a757f1f4", fallback: "写真と数値を記録する"),
            detail: L10n.string("core_ui.17de0f52b479", fallback: "食事と体型は写真で。体重・腹囲・セットは数値で残します。"),
            destination: L10n.string("core_ui.725fe331d7f6", fallback: "記録"),
            systemImage: "camera.fill"
        ),
        AppTutorialStep(
            id: "coach",
            number: 2,
            title: L10n.string("core_ui.6fe4b509ad50", fallback: "AIに今の状態を聞く"),
            detail: L10n.string("core_ui.6d1f0a3fcc4b", fallback: "記録全体から、良い変化・停滞・不足情報と次の一手を提案します。"),
            destination: "AI",
            systemImage: "sparkles"
        ),
        AppTutorialStep(
            id: "execute",
            number: 3,
            title: L10n.string("core_ui.e1de544d20a2", fallback: "今日のメニューを実行する"),
            detail: L10n.string("core_ui.7cc0b0723d1f", fallback: "提案されたメニューをiPhoneやApple Watchで、そのまま進めます。"),
            destination: L10n.string("core_ui.76f154401eec", fallback: "計画・Watch"),
            systemImage: "play.fill"
        )
    ]
}

struct AppIntroductionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 10) {
                IntroductionPoint(
                    number: 1,
                    systemImage: "camera.fill",
                    title: L10n.string("core_ui.8d02c094b191", fallback: "記録する"),
                    detail: L10n.string("core_ui.f33ef7b7b5dc", fallback: "写真と数値で、今を残す")
                )
                IntroductionPoint(
                    number: 2,
                    systemImage: "sparkles",
                    title: L10n.string("core_ui.379c080870e5", fallback: "AIに聞く"),
                    detail: L10n.string("core_ui.0307962d6266", fallback: "状態と次の一手を知る")
                )
                IntroductionPoint(
                    number: 3,
                    systemImage: "play.fill",
                    title: L10n.string("core_ui.f4b3ed35961f", fallback: "実行する"),
                    detail: L10n.string("core_ui.9418cc5a98f9", fallback: "今日のメニューをこなす")
                )
            }

            Label(L10n.string("core_ui.cfb9b70a1a45", fallback: "実行結果は、次のAI提案へつながります"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.mutedInk)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("initialSetupStep-welcome")
    }
}

struct AppTutorialOverviewView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(AppTutorialContent.steps) { step in
                AppTutorialStepRow(step: step)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("core_ui.8db1bd8f5b87", fallback: "実行するほど、次が明確になる"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("core_ui.bf6f0ec9eac4", fallback: "記録と実行結果は次のAI分析へ引き継がれます。最初の操作はホームのミッションが案内します。"))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineSpacing(3)
            }
            .padding(16)
            .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("initialSetupStep-tutorial")
    }
}

struct AppTutorialView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("core_ui.69788c65c769", fallback: "基本の使い方"))
                            .font(.largeTitle.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(L10n.string("core_ui.7538ba8df343", fallback: "記録する。AIに聞く。実行する。毎日やるのは3つだけです。"))
                            .font(.title3)
                            .foregroundStyle(AppTheme.mutedInk)
                    }

                    AppTutorialOverviewView()
                }
                .padding(20)
                .padding(.bottom, 32)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.pageBackground)
            .navigationTitle(L10n.string("core_ui.a44407ea9e94", fallback: "使い方ガイド"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("core_ui.9eeac2fd3ceb", fallback: "完了")) {
                        UsageAnalytics.shared.record(.tutorialViewed, dimension: "settings")
                        dismiss()
                    }
                    .accessibilityIdentifier("dismissTutorialButton")
                }
            }
        }
    }
}

private struct IntroductionPoint: View {
    let number: Int
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.accent)
                .frame(width: 46, height: 46)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("ACTION \(number)")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AppTutorialStepRow: View {
    let step: AppTutorialStep

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.accent.opacity(0.12))
                Image(systemName: step.systemImage)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("STEP \(step.number)")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                    Label(step.destination, systemImage: step.systemImage)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.mutedInk)
                }

                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutorialStep-\(step.id)")
    }
}

#Preview {
    AppTutorialView()
}
