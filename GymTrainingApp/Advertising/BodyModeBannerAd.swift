import GoogleMobileAds
import SwiftUI
import UIKit

struct BodyModeBannerAd: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var advertising = AdvertisingManager.shared
    @State private var loadState: LoadState = .loading
    @State private var reloadID = UUID()
    @State private var retryTask: Task<Void, Never>?

    private static let loadTimeout: Duration = .seconds(8)
    private static let retryDelay: Duration = .seconds(30)

    private enum LoadState {
        case loading
        case loaded
        case failed
    }

    var body: some View {
        if advertising.canDisplayAds {
            VStack(spacing: 0) {
                if advertising.isUITestPlaceholderEnabled {
                    Text(L10n.string("core_ui.35145a2177b1", fallback: "固定テスト広告"))
                        .font(.headline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        let adSize = largeAnchoredAdaptiveBanner(width: width)

                        ZStack {
                            fallbackBanner

                            if loadState != .failed {
                                BannerViewContainer(
                                    adSize: adSize,
                                    adUnitID: advertising.activeBannerUnitID
                                ) { didLoad in
                                    handleLoadResult(didLoad)
                                }
                                .id(reloadID)
                                .frame(width: adSize.size.width, height: adSize.size.height)
                                .frame(maxWidth: .infinity)
                                .opacity(loadState == .loaded ? 1 : 0)
                            }
                        }
                    }
                    .frame(height: 100)

                    Divider()
                }
            }
            .background(AppTheme.elevatedBackground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("persistentBannerAd")
            .task(id: reloadID) {
                await failOverIfLoadingTimesOut()
            }
            .onDisappear {
                retryTask?.cancel()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, loadState == .failed else { return }
                restartLoading()
            }
        }
    }

    private var fallbackBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("BodyMode")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("今日の記録を、次の一手へ")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedInk)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 100)
        .accessibilityHidden(true)
    }

    @MainActor
    private func failOverIfLoadingTimesOut() async {
        guard !advertising.isUITestPlaceholderEnabled, loadState == .loading else { return }
        try? await Task.sleep(for: Self.loadTimeout)
        guard !Task.isCancelled, loadState == .loading else { return }

        AppDiagnostics.shared.record(
            category: "advertising.banner",
            message: "Banner ad load timed out"
        )
        handleLoadResult(false)
    }

    private func handleLoadResult(_ didLoad: Bool) {
        retryTask?.cancel()
        loadState = didLoad ? .loaded : .failed

        guard !didLoad else { return }
        retryTask = Task { @MainActor in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled else { return }
            restartLoading()
        }
    }

    private func restartLoading() {
        retryTask?.cancel()
        loadState = .loading
        reloadID = UUID()
    }
}

private struct BannerViewContainer: UIViewRepresentable {
    let adSize: AdSize
    let adUnitID: String
    let onLoadResult: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadResult: onLoadResult)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.delegate = context.coordinator
        context.coordinator.loadWhenReady(banner, adUnitID: adUnitID)
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {
        guard banner.adSize.size != adSize.size else { return }
        banner.adSize = adSize
    }

    private static var rootViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow }
        return window?.rootViewController
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let onLoadResult: (Bool) -> Void
        private var requestedAdUnitID: String?

        init(onLoadResult: @escaping (Bool) -> Void) {
            self.onLoadResult = onLoadResult
        }

        @MainActor
        func loadWhenReady(
            _ banner: BannerView,
            adUnitID: String,
            attemptsRemaining: Int = 20
        ) {
            guard requestedAdUnitID == nil else { return }

            guard let rootViewController = BannerViewContainer.rootViewController else {
                guard attemptsRemaining > 0 else {
                    onLoadResult(false)
                    AppDiagnostics.shared.record(
                        category: "advertising.banner",
                        message: "Banner root view controller was unavailable"
                    )
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak banner] in
                    guard let self, let banner else { return }
                    self.loadWhenReady(
                        banner,
                        adUnitID: adUnitID,
                        attemptsRemaining: attemptsRemaining - 1
                    )
                }
                return
            }

            requestedAdUnitID = adUnitID
            banner.adUnitID = adUnitID
            banner.rootViewController = rootViewController

            let request = Request()
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
            banner.load(request)
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onLoadResult(true)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            onLoadResult(false)
            AppDiagnostics.shared.record(
                error: error,
                category: "advertising.banner",
                message: "Banner ad failed to load"
            )
        }
    }
}
