import Foundation
@preconcurrency import CoreLocation

@MainActor
final class GymLocationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentDistanceMeters: Double?
    @Published private(set) var isAtGym = false
    @Published private(set) var statusMessage = "位置情報は未設定です"
    @Published private(set) var isLocating = false

    private let locationManager = CLLocationManager()
    private weak var appStore: AppStore?
    private var isPendingGymRegistration = false

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 25
    }

    func bind(appStore: AppStore) {
        self.appStore = appStore
        if let gym = appStore.gymLocation,
           appStore.sensorSettings.gymVisitDetectionEnabled {
            startMonitoring(gym)
        }
    }

    func registerCurrentLocationAsGym() {
        isPendingGymRegistration = true
        isLocating = true
        statusMessage = "現在地を確認中"

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            statusMessage = "設定アプリで位置情報を許可すると登録できます"
        @unknown default:
            isLocating = false
        }
    }

    func enableBackgroundVisitDetection() {
        guard let gym = appStore?.gymLocation else {
            statusMessage = "先に現在地をジムとして登録してください"
            return
        }

        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
        startMonitoring(gym)
        statusMessage = "ジム周辺への到着を検知します"
    }

    func disableVisitDetection() {
        for region in locationManager.monitoredRegions where region.identifier == Self.gymRegionIdentifier {
            locationManager.stopMonitoring(for: region)
        }
        locationManager.stopUpdatingLocation()
        statusMessage = "ジム訪問の自動検知はオフです"
    }

    func removeGymLocation() {
        disableVisitDetection()
        appStore?.saveGymLocation(nil)
        currentDistanceMeters = nil
        isAtGym = false
        statusMessage = "ジムの場所を削除しました"
    }

    func manualCheckIn() {
        appStore?.recordGymArrival(source: "manual")
        isAtGym = true
        statusMessage = "ジム到着を記録しました"
    }

    func manualCheckOut() {
        appStore?.recordGymDeparture()
        isAtGym = false
        statusMessage = "ジム退出を記録しました"
    }

    private func startMonitoring(_ gym: GymLocation) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            statusMessage = "この端末では周辺検知を利用できません"
            return
        }

        let center = CLLocationCoordinate2D(latitude: gym.latitude, longitude: gym.longitude)
        let radius = min(gym.radiusMeters, locationManager.maximumRegionMonitoringDistance)
        let region = CLCircularRegion(
            center: center,
            radius: max(100, radius),
            identifier: Self.gymRegionIdentifier
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
        locationManager.startUpdatingLocation()
    }

    private func handleLocation(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double
    ) {
        isLocating = false
        guard horizontalAccuracy >= 0 else {
            statusMessage = "位置精度が安定してから再度お試しください"
            return
        }

        if isPendingGymRegistration {
            isPendingGymRegistration = false
            let gym = GymLocation(
                name: "マイジム",
                latitude: latitude,
                longitude: longitude,
                radiusMeters: 150
            )
            appStore?.saveGymLocation(gym)
            if var settings = appStore?.sensorSettings {
                settings.gymVisitDetectionEnabled = true
                appStore?.saveSensorSettings(settings)
            }
            startMonitoring(gym)
            statusMessage = "現在地をマイジムとして登録しました"
        }

        guard let gym = appStore?.gymLocation else { return }
        let current = CLLocation(latitude: latitude, longitude: longitude)
        let gymPoint = CLLocation(latitude: gym.latitude, longitude: gym.longitude)
        let distance = current.distance(from: gymPoint)
        currentDistanceMeters = distance

        let wasAtGym = isAtGym
        isAtGym = distance <= gym.radiusMeters
        if isAtGym, !wasAtGym {
            appStore?.recordGymArrival(source: "location")
            statusMessage = "ジム到着を記録しました"
        } else if !isAtGym, wasAtGym {
            appStore?.recordGymDeparture()
            statusMessage = "ジム退出を記録しました"
        }
    }

    nonisolated private static let gymRegionIdentifier = "gym.training.savedGym"
}

extension GymLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            authorizationStatus = status
            if isPendingGymRegistration,
               status == .authorizedAlways || status == .authorizedWhenInUse {
                locationManager.requestLocation()
            }
            if status == .denied || status == .restricted {
                isPendingGymRegistration = false
                isLocating = false
                statusMessage = "位置情報は許可されていません。手動チェックインは使えます"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy
        Task { @MainActor [weak self] in
            self?.handleLocation(
                latitude: latitude,
                longitude: longitude,
                horizontalAccuracy: accuracy
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.isLocating = false
            self?.statusMessage = "現在地を取得できませんでした"
            NSLog("Gym location failed: \(error.localizedDescription)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.gymRegionIdentifier else { return }
        Task { @MainActor [weak self] in
            self?.appStore?.recordGymArrival(source: "region")
            self?.isAtGym = true
            self?.statusMessage = "ジム到着を記録しました"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.gymRegionIdentifier else { return }
        Task { @MainActor [weak self] in
            self?.appStore?.recordGymDeparture()
            self?.isAtGym = false
            self?.statusMessage = "ジム退出を記録しました"
        }
    }
}
