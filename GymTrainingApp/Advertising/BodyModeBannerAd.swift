import GoogleMobileAds
import SwiftUI
import UIKit

struct BodyModeBannerAd: View {
    @ObservedObject private var advertising = AdvertisingManager.shared
    @State private var loadState: LoadState = .loading
    @State private var reloadID = UUID()
    @State private var retryTask: Task<Void, Never>?

    private enum LoadState {
        case loading
        case loaded
        case failed
    }

    var body: some View {
        if advertising.canDisplayAds {
            VStack(spacing: 0) {
                if advertising.isUITestPlaceholderEnabled {
                    Text("固定テスト広告")
                        .font(.headline)
                        .foregroundStyle(AppTheme.mutedInk)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    GeometryReader { proxy in
                        let width = max(proxy.size.width, 1)
                        let adSize = largeAnchoredAdaptiveBanner(width: width)

                        ZStack {
                            if loadState != .loaded {
                                ProgressView()
                                    .accessibilityLabel("広告を読み込み中")
                            }

                            BannerViewContainer(
                                adSize: adSize,
                                adUnitID: advertising.configuration.bannerUnitID
                            ) { didLoad in
                                handleLoadResult(didLoad)
                            }
                            .id(reloadID)
                            .frame(width: adSize.size.width, height: adSize.size.height)
                            .frame(maxWidth: .infinity)
                            .opacity(loadState == .loaded ? 1 : 0)
                        }
                    }
                    .frame(height: 100)
                }

                Divider()
            }
            .background(AppTheme.elevatedBackground)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("persistentBannerAd")
            .onDisappear {
                retryTask?.cancel()
            }
        }
    }

    private func handleLoadResult(_ didLoad: Bool) {
        retryTask?.cancel()
        loadState = didLoad ? .loaded : .failed

        guard !didLoad else { return }
        retryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            loadState = .loading
            reloadID = UUID()
        }
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
        banner.adUnitID = adUnitID
        banner.rootViewController = Self.rootViewController
        banner.delegate = context.coordinator

        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        banner.load(request)
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

        init(onLoadResult: @escaping (Bool) -> Void) {
            self.onLoadResult = onLoadResult
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
