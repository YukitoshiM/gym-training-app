import SwiftUI

struct AIHubView: View {
    @EnvironmentObject private var appStore: AppStore
    @State private var isShowingAIPlanCoach = false
    @State private var pendingAIPlan: TrainingPlan?
    @State private var aiPlanForEditing: TrainingPlan?

    private var latestWeeklyInsight: AIInsight? {
        appStore.aiInsights.first { $0.insightType == .weekly }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    AIHubSectionTitle(title: "AIコーチ")

                    NavigationLink {
                        AITrainerChatView()
                    } label: {
                        AITrainerEntryCard(
                            persona: appStore.userProfile.coachPersona,
                            coachRole: appStore.userProfile.coachType.displayName,
                            detail: appStore.userProfile.coachType.characteristic
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aiHubTrainerLink")
                    .appTourTarget(.aiTrainer)

                    Button {
                        isShowingAIPlanCoach = true
                    } label: {
                        AIHubNavigationRow(
                            title: "トレーニング計画",
                            detail: "\(appStore.userProfile.coachPersona.displayName)と作成・相談して修正",
                            systemImage: "sparkles.rectangle.stack",
                            coachPersona: appStore.userProfile.coachPersona
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aiHubPlanCoachButton")

                    AIHubSectionTitle(title: "写真で分析")

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        NavigationLink {
                            MealListView(startsWithEditor: true)
                        } label: {
                            AIHubToolCard(
                                title: "食事写真AI",
                                detail: "\(appStore.userProfile.coachPersona.displayName)が料理とPFCを確認",
                                systemImage: "fork.knife",
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiHubMealPhotoLink")

                        NavigationLink {
                            BodyPhotoListView(startsWithEditor: true)
                        } label: {
                            AIHubToolCard(
                                title: "体型写真AI",
                                detail: "\(appStore.userProfile.coachPersona.displayName)が複数方向を確認",
                                systemImage: "camera.viewfinder",
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiHubBodyPhotoLink")
                    }
                    .appTourTarget(.aiPhotoTools)

                    AIHubSectionTitle(title: "振り返り")

                    VStack(spacing: 10) {
                        NavigationLink {
                            AIReportView()
                        } label: {
                            AIHubNavigationRow(
                                title: "週次・月次レポート",
                                detail: latestWeeklyInsight?.actionSuggestion ?? "記録をまとめて次の行動と翌月目標を提案",
                                systemImage: "chart.line.text.clipboard",
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiHubReportLink")

                        NavigationLink {
                            CoachMemoryListView()
                        } label: {
                            AIHubNavigationRow(
                                title: "\(appStore.userProfile.coachPersona.displayName)が覚えていること",
                                detail: "確認済みの記憶 \(appStore.coachMemories.count)件",
                                systemImage: "brain.head.profile",
                                coachPersona: appStore.userProfile.coachPersona
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiHubMemoryLink")
                    }

                    Label(
                        appStore.aiSettings.isEnabled ? "AI接続が有効です" : "AI機能は設定でオフです",
                        systemImage: appStore.aiSettings.isEnabled ? "checkmark.circle" : "slash.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
                }
                .padding()
            }
            .background(TrainingBackground())
            .navigationTitle("AI")
            .sheet(isPresented: $isShowingAIPlanCoach, onDismiss: presentPendingAIPlan) {
                AIPlanCoachView { plan in
                    pendingAIPlan = plan
                }
            }
            .sheet(item: $aiPlanForEditing) { plan in
                PlanEditorView(plan: plan, mode: .aiCoach) {
                    aiPlanForEditing = nil
                }
            }
        }
    }

    private func presentPendingAIPlan() {
        guard let pendingAIPlan else { return }
        self.pendingAIPlan = nil
        aiPlanForEditing = pendingAIPlan
    }
}

private struct AIHubSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(AppTheme.mutedInk)
    }
}

private struct AITrainerEntryCard: View {
    let persona: CoachPersona
    let coachRole: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            CoachAvatarView(persona: persona, size: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text("担当 \(persona.displayName)")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Text(coachRole)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.accent)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.headline)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(16)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.accent.opacity(0.42), lineWidth: 1)
        }
    }
}

private struct AIHubToolCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let coachPersona: CoachPersona

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                CoachAvatarView(persona: coachPersona, size: 34)
            }

            Spacer(minLength: 2)

            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedInk)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(14)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }
}

private struct AIHubNavigationRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var coachPersona: CoachPersona? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let coachPersona {
                CoachAvatarView(persona: coachPersona, size: 44)
            } else {
                IconBadge(systemImage: systemImage, tint: AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(AppTheme.mutedInk)
        }
        .padding(14)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }
}

#Preview {
    AIHubView()
        .environmentObject(AppStore())
        .environmentObject(HealthDataManager())
}
