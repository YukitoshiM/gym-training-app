import SwiftUI

enum AppTourTarget: String, Hashable {
    case homeTodayTraining
    case recordQuickActions
    case aiTrainer
    case aiPhotoTools
    case planCoach
    case exerciseLibrary
    case historyTimeline
}

struct AppTourTargetFramePreferenceKey: PreferenceKey {
    static let defaultValue: [AppTourTarget: CGRect] = [:]

    static func reduce(
        value: inout [AppTourTarget: CGRect],
        nextValue: () -> [AppTourTarget: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

extension View {
    func appTourTarget(_ target: AppTourTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: AppTourTargetFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .global)]
                )
            }
        }
    }
}
