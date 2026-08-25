import GoogleMobileAds
import SwiftUI

@MainActor
final class RewardedCreditAdManager: ObservableObject {
    static let shared = RewardedCreditAdManager()

    @Published private(set) var isBusy = false
    private var presentationDelegate: RewardedPresentationDelegate?

    func watchAndClaim(settings: AISettings) async throws -> AIRewardedAdClaimResponse {
        guard AdvertisingManager.shared.canDisplayAds else {
            throw AIClientError.transport("Rewarded ads unavailable")
        }
        let unitID = AdvertisingManager.shared.activeRewardedUnitID
        guard !unitID.isEmpty else { throw AIClientError.invalidResponse }
        isBusy = true
        defer { isBusy = false }

        let client = AIAPIClient(settings: settings)
        UsageAnalytics.shared.record(.rewardedAdStarted)
        do {
            return try await performWatchAndClaim(client: client, unitID: unitID)
        } catch is CancellationError {
            UsageAnalytics.shared.record(.rewardedAdFailed, dimension: "cancelled")
            throw CancellationError()
        } catch let error as AIClientError {
            let reason: String
            if case .rewardedAdVerificationPending = error {
                reason = "verification_pending"
            } else {
                reason = "service"
            }
            UsageAnalytics.shared.record(.rewardedAdFailed, dimension: reason)
            throw error
        } catch {
            UsageAnalytics.shared.record(.rewardedAdFailed, dimension: "ad_sdk")
            throw error
        }
    }

    func preview() async throws {
        guard AdvertisingManager.shared.canDisplayAds,
              AdvertisingManager.shared.canPreviewRewardedAd else {
            throw AIClientError.transport("Rewarded ads unavailable")
        }
        let unitID = AdvertisingManager.shared.activeRewardedUnitID
        guard !unitID.isEmpty else { throw AIClientError.invalidResponse }
        isBusy = true
        defer { isBusy = false }
        try await presentRewardedAd(unitID: unitID, customData: nil)
    }

    private func performWatchAndClaim(
        client: AIAPIClient,
        unitID: String
    ) async throws -> AIRewardedAdClaimResponse {
        let challenge = try await client.createRewardedAdChallenge()

        try await presentRewardedAd(unitID: unitID, customData: challenge.customData)
        UsageAnalytics.shared.record(.rewardedAdCompleted)
        for attempt in 0..<12 {
            let claim = try await client.claimRewardedAd(challengeID: challenge.challengeID)
            if !claim.pending {
                if claim.granted {
                    UsageAnalytics.shared.record(.rewardedCreditGranted)
                }
                return claim
            }
            if attempt < 11 { try await Task.sleep(for: .seconds(1)) }
        }
        throw AIClientError.rewardedAdVerificationPending
    }

    private func presentRewardedAd(unitID: String, customData: String?) async throws {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        let ad = try await RewardedAd.load(with: unitID, request: request)
        if let customData {
            let verificationOptions = ServerSideVerificationOptions()
            verificationOptions.customRewardText = customData
            ad.serverSideVerificationOptions = verificationOptions
        }
        try await withCheckedThrowingContinuation { continuation in
            let delegate = RewardedPresentationDelegate(continuation: continuation)
            presentationDelegate = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(from: nil) {
                delegate.didEarnReward()
            }
        }
        presentationDelegate = nil
    }
}

@MainActor
private final class RewardedPresentationDelegate: NSObject, FullScreenContentDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var earnedReward = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func didEarnReward() {
        earnedReward = true
        continuation?.resume(returning: ())
        continuation = nil
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        guard !earnedReward else { return }
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
