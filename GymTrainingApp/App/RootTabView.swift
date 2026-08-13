import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var watchPlanSyncService: WatchPlanSyncService
    @EnvironmentObject private var gymLocationManager: GymLocationManager
    @State private var selectedTab: RootTab = .home
    @State private var planCreationRequest: PlanCreationRequest?
    @State private var isShowingAppTour = false
    @State private var appTourStepIndex = 0
    @State private var tabResetTokens: [RootTab: Int] = [:]
    @State private var rootTabFrames: [RootTab: CGRect] = [:]
    @State private var appTourTargetFrames: [AppTourTarget: CGRect] = [:]

    var body: some View {
        rootContent
            .tint(AppTheme.accent)
            .onAppear {
                watchPlanSyncService.bind(appStore: appStore)
                gymLocationManager.bind(appStore: appStore)
                AdvertisingManager.shared.prepare()
                if AppTourStateStore.shouldPresent() {
                    startAppTour()
                }
            }
            .onChange(of: selectedTab) { _, tab in
                UsageAnalytics.shared.record(.tabSelected, dimension: tab.rawValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .startBodyModeAppTour)) { _ in
                startAppTour()
            }
            .overlay {
                if isShowingAppTour {
                    AppTourOverlay(
                        step: currentAppTourStep,
                        currentIndex: appTourStepIndex,
                        total: AppTourStep.steps.count,
                        targetFrame: currentAppTourTargetFrame,
                        onSkip: finishAppTour,
                        onNext: advanceAppTour
                    )
                    .transition(.opacity)
                    .zIndex(100)
                }
            }
            .alert(
                "予定したトレーニング記録がありません",
                isPresented: Binding(
                    get: { appStore.pendingMissedGymPlan != nil },
                    set: { if !$0 { appStore.resolveMissedGymPlan(rescheduleForToday: false) } }
                )
            ) {
                Button("今日へ変更") {
                    appStore.resolveMissedGymPlan(rescheduleForToday: true)
                }
                Button("実施しなかった", role: .cancel) {
                    appStore.resolveMissedGymPlan(rescheduleForToday: false)
                }
            } message: {
                Text("\(appStore.pendingMissedGymPlanName ?? "選択したメニュー")の予定日に、ジム訪問またはトレーニング実績が見つかりませんでした。")
            }
            .alert(
                "計画重量を更新しますか？",
                isPresented: Binding(
                    get: { watchPlanSyncService.pendingPlanWeightUpdateSuggestion != nil },
                    set: {
                        if !$0 {
                            watchPlanSyncService.declinePlanWeightUpdateSuggestion()
                        }
                    }
                )
            ) {
                Button("計画に反映") {
                    watchPlanSyncService.acceptPlanWeightUpdateSuggestion()
                }
                Button("今回は変更しない", role: .cancel) {
                    watchPlanSyncService.declinePlanWeightUpdateSuggestion()
                }
            } message: {
                Text(watchPlanSyncService.pendingPlanWeightUpdateSuggestion?.message ?? "")
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        VStack(spacing: 0) {
            persistentBanner

            if #available(iOS 26.0, *) {
                selectedTabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                customTabBar
            } else {
                systemTabView
            }
        }
        .background(AppTheme.cardBackground.ignoresSafeArea(edges: .bottom))
        .onPreferenceChange(RootTabFramePreferenceKey.self) { frames in
            rootTabFrames = frames
        }
        .onPreferenceChange(AppTourTargetFramePreferenceKey.self) { frames in
            appTourTargetFrames = frames
        }
    }

    private var persistentBanner: some View {
        BodyModeBannerAd()
    }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 0) {
                ForEach(RootTab.allCases) { tab in
                    Button {
                        if selectedTab == tab {
                            tabResetTokens[tab, default: 0] += 1
                        } else {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.systemImage)
                                .font(.title2.weight(.semibold))
                            Text(tab.title)
                                .font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .foregroundStyle(selectedTab == tab ? AppTheme.accent : AppTheme.mutedInk)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityIdentifier("rootTab-\(tab.title)")
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RootTabFramePreferenceKey.self,
                                value: [tab: proxy.frame(in: .global)]
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .background(AppTheme.cardBackground)
        }
    }

    private var systemTabView: some View {
        TabView(selection: $selectedTab) {
            homeView
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }
                .tag(RootTab.home)

            AIHubView()
                .tabItem {
                    Label("AI", systemImage: "sparkles")
                }
                .tag(RootTab.ai)

            PlanListView(
                creationRequest: planCreationRequest,
                onCreationRequestHandled: clearPlanCreationRequest
            )
                .tabItem {
                    Label("計画", systemImage: "list.bullet.rectangle")
                }
                .tag(RootTab.plans)

            RecordHubView()
                .tabItem {
                    Label("記録", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(RootTab.record)

            HistoryListView()
                .tabItem {
                    Label("履歴", systemImage: "clock.arrow.circlepath")
                }
                .tag(RootTab.history)

        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .home:
            homeView
                .id(tabResetTokens[.home, default: 0])
        case .ai:
            AIHubView()
                .id(tabResetTokens[.ai, default: 0])
        case .plans:
            PlanListView(
                creationRequest: planCreationRequest,
                onCreationRequestHandled: clearPlanCreationRequest
            )
            .id(tabResetTokens[.plans, default: 0])
        case .record:
            RecordHubView()
                .id(tabResetTokens[.record, default: 0])
        case .history:
            HistoryListView()
                .id(tabResetTokens[.history, default: 0])
        }
    }

    private var homeView: some View {
        HomeView(
            onCreatePlan: openPlanCreation,
            onOpenPlans: openPurposePlanCreation,
            onOpenRecord: { selectedTab = .record }
        )
    }

    private func openPlanCreation() {
        if appStore.userProfile.experienceLevel == .beginner {
            planCreationRequest = .beginnerStarter(appStore.makeBeginnerStarterPlan())
        } else {
            planCreationRequest = .blank
        }
        selectedTab = .plans
    }

    private func openPurposePlanCreation() {
        planCreationRequest = nil
        selectedTab = .plans
    }

    private func clearPlanCreationRequest() {
        planCreationRequest = nil
    }

    private var currentAppTourStep: AppTourStep {
        AppTourStep.steps[appTourStepIndex]
    }

    private var currentAppTourTargetFrame: CGRect? {
        if let target = currentAppTourStep.target {
            return appTourTargetFrames[target]
        }
        return rootTabFrames[currentAppTourStep.tab]
    }

    private func startAppTour() {
        guard !isShowingAppTour else { return }
        appTourStepIndex = 0
        selectedTab = AppTourStep.steps[0].tab
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingAppTour = true
        }
        UsageAnalytics.shared.record(.tutorialViewed, dimension: "started")
    }

    private func advanceAppTour() {
        guard appTourStepIndex < AppTourStep.steps.count - 1 else {
            finishAppTour()
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            appTourStepIndex += 1
            selectedTab = AppTourStep.steps[appTourStepIndex].tab
        }
    }

    private func finishAppTour() {
        AppTourStateStore.markCompleted()
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingAppTour = false
        }
        UsageAnalytics.shared.record(.tutorialViewed, dimension: "completed")
    }
}

private enum RootTab: String, CaseIterable, Identifiable {
    case home
    case ai
    case plans
    case record
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "ホーム"
        case .ai: "AI"
        case .plans: "計画"
        case .record: "記録"
        case .history: "履歴"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .ai: "sparkles"
        case .plans: "list.bullet.rectangle"
        case .record: "figure.strengthtraining.traditional"
        case .history: "clock.arrow.circlepath"
        }
    }
}

private struct RootTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [RootTab: CGRect] = [:]

    static func reduce(value: inout [RootTab: CGRect], nextValue: () -> [RootTab: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct AppTourStep: Identifiable {
    let id: String
    let tab: RootTab
    let target: AppTourTarget?
    let title: String
    let detail: String

    var isTabStep: Bool { target == nil }

    static let steps: [AppTourStep] = [
        AppTourStep(
            id: "home-tab",
            tab: .home,
            target: nil,
            title: "今日やることはここ",
            detail: "ホーム"
        ),
        AppTourStep(
            id: "home-today",
            tab: .home,
            target: .homeTodayTraining,
            title: "ここから今日を開始",
            detail: "メニューを選ぶ・始める"
        ),
        AppTourStep(
            id: "record-tab",
            tab: .record,
            target: nil,
            title: "写真と数値はここ",
            detail: "記録"
        ),
        AppTourStep(
            id: "record-quick-actions",
            tab: .record,
            target: .recordQuickActions,
            title: "記録する項目をタップ",
            detail: "体重・腹囲・食事・体型写真"
        ),
        AppTourStep(
            id: "ai-tab",
            tab: .ai,
            target: nil,
            title: "迷ったらここ",
            detail: "AI"
        ),
        AppTourStep(
            id: "ai-trainer",
            tab: .ai,
            target: .aiTrainer,
            title: "担当コーチに相談",
            detail: "記録を見て次の行動を提案"
        ),
        AppTourStep(
            id: "ai-photo-tools",
            tab: .ai,
            target: .aiPhotoTools,
            title: "写真からすぐ分析",
            detail: "食事と体型"
        ),
        AppTourStep(
            id: "plans-tab",
            tab: .plans,
            target: nil,
            title: "メニューはここ",
            detail: "計画"
        ),
        AppTourStep(
            id: "plans-coach",
            tab: .plans,
            target: .planCoach,
            title: "AIとメニューを作る",
            detail: "相談しながら修正"
        ),
        AppTourStep(
            id: "plans-exercises",
            tab: .plans,
            target: .exerciseLibrary,
            title: "種目を探す・追加する",
            detail: "器具や部位から選択"
        ),
        AppTourStep(
            id: "history-tab",
            tab: .history,
            target: nil,
            title: "変化はここ",
            detail: "履歴"
        ),
        AppTourStep(
            id: "history-timeline",
            tab: .history,
            target: .historyTimeline,
            title: "記録はここにたまる",
            detail: "日付ごとに振り返る"
        ),
    ]
}

private struct AppTourOverlay: View {
    let step: AppTourStep
    let currentIndex: Int
    let total: Int
    let targetFrame: CGRect?
    let onSkip: () -> Void
    let onNext: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let tabIndex = RootTab.allCases.firstIndex(of: step.tab) ?? 0
            let tabWidth = proxy.size.width / CGFloat(RootTab.allCases.count)
            let bottomInset = max(proxy.safeAreaInsets.bottom, 8)
            let fallbackFrame = CGRect(
                x: tabWidth * CGFloat(tabIndex) + 4,
                y: proxy.size.height - bottomInset - 58,
                width: max(64, tabWidth - 8),
                height: 68
            )
            let overlayGlobalFrame = proxy.frame(in: .global)
            let measuredFrame = targetFrame?
                .offsetBy(dx: -overlayGlobalFrame.minX, dy: -overlayGlobalFrame.minY) ?? fallbackFrame
            let spotlightFrame = step.isTabStep
                ? CGRect(
                    x: measuredFrame.minX + 4,
                    y: measuredFrame.minY - 2,
                    width: max(64, measuredFrame.width - 8),
                    height: measuredFrame.height + 4
                )
                : measuredFrame.insetBy(dx: -6, dy: -6)
            let spotlightCenter = CGPoint(x: spotlightFrame.midX, y: spotlightFrame.midY)
            let availableAbove = spotlightFrame.minY
            let availableBelow = proxy.size.height - spotlightFrame.maxY
            let shouldPlaceCardBelow = availableBelow >= 210 || availableBelow > availableAbove
            let cardTopPadding = max(24, spotlightFrame.maxY + 24)
            let cardBottomPadding = max(24, proxy.size.height - spotlightFrame.minY + 24)

            ZStack {
                Color.black.opacity(0.72)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .frame(width: spotlightFrame.width, height: spotlightFrame.height)
                            .position(spotlightCenter)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()

                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.accent, lineWidth: 3)
                    .frame(width: spotlightFrame.width, height: spotlightFrame.height)
                    .position(spotlightCenter)

                VStack(spacing: 10) {
                    HStack {
                        Label(progressText, systemImage: step.tab.systemImage)
                            .font(.headline)
                            .foregroundStyle(AppTheme.accent)
                        Spacer()
                        Button("スキップ", action: onSkip)
                            .font(.headline)
                            .foregroundStyle(AppTheme.mutedInk)
                            .accessibilityIdentifier("appTourSkipButton")
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(step.title)
                            .font(.title2.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(step.detail)
                            .font(.headline)
                            .foregroundStyle(AppTheme.mutedInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Spacer()
                        Button(action: onNext) {
                            Label(
                                nextButtonTitle,
                                systemImage: currentIndex == total - 1 ? "checkmark" : "chevron.right"
                            )
                            .labelStyle(AppTourButtonLabelStyle())
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(
                            currentIndex == total - 1 ? "appTourFinishButton" : "appTourNextButton"
                        )
                    }
                }
                .padding(18)
                .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.cardBorder, lineWidth: 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, shouldPlaceCardBelow ? cardTopPadding : 0)
                .padding(.bottom, shouldPlaceCardBelow ? 0 : cardBottomPadding)
                .frame(maxHeight: .infinity, alignment: shouldPlaceCardBelow ? .top : .bottom)

                Image(systemName: shouldPlaceCardBelow ? "arrow.up" : "arrow.down")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.accent)
                    .position(
                        x: spotlightCenter.x,
                        y: shouldPlaceCardBelow ? spotlightFrame.maxY + 15 : spotlightFrame.minY - 15
                    )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appTourOverlay")
        .ignoresSafeArea()
    }

    private var progressText: String {
        "\(currentIndex + 1) / \(total)"
    }

    private var nextButtonTitle: String {
        currentIndex == total - 1 ? "始める" : "次へ"
    }
}

private struct AppTourButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AppStore())
        .environmentObject(WatchPlanSyncService())
        .environmentObject(HealthDataManager())
        .environmentObject(GymLocationManager())
}
