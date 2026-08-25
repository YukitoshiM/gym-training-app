import CoreLocation
import HealthKit

extension WatchWorkoutStore: CLLocationManagerDelegate {
    func startOutdoorRouteCollection() {
        guard activeSession?.isOutdoorCardio == true else { return }
        workoutRoutePointCount = 0
        workoutRouteBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        switch workoutLocationManager.authorizationStatus {
        case .notDetermined:
            workoutLocationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            workoutLocationManager.startUpdatingLocation()
        default:
            WatchDiagnostics.shared.record(
                level: "info",
                category: "route.permission",
                message: "Route permission unavailable; workout metrics continue"
            )
        }
    }

    func stopOutdoorRouteCollection(discard: Bool) {
        workoutLocationManager.stopUpdatingLocation()
        if discard {
            workoutRouteBuilder?.discard()
            workoutRouteBuilder = nil
            workoutRoutePointCount = 0
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let isAuthorized = manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse
        Task { @MainActor [weak self] in
            guard let self, activeSession?.isOutdoorCardio == true else { return }
            if isAuthorized {
                workoutLocationManager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let usable = locations.filter {
            $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy <= 50
                && abs($0.timestamp.timeIntervalSinceNow) < 30
        }
        guard !usable.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self, let routeBuilder = workoutRouteBuilder else { return }
            routeBuilder.insertRouteData(usable) { [weak self] inserted, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if inserted {
                        workoutRoutePointCount += usable.count
                    } else if let error {
                        WatchDiagnostics.shared.record(
                            level: "error",
                            category: "route.insert",
                            message: "Route points could not be stored",
                            metadata: ["error": error.localizedDescription]
                        )
                    }
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        WatchDiagnostics.shared.record(
            level: "error",
            category: "route.location",
            message: "Outdoor location update failed",
            metadata: ["error": error.localizedDescription]
        )
    }

    func finishOutdoorRoute(
        with workout: HKWorkout,
        session: WatchWorkoutSessionSnapshot,
        completion: @escaping @Sendable (WatchWorkoutSessionSnapshot) -> Void
    ) {
        stopOutdoorRouteCollection(discard: false)
        guard let routeBuilder = workoutRouteBuilder, workoutRoutePointCount > 0 else {
            workoutRouteBuilder?.discard()
            workoutRouteBuilder = nil
            completion(session)
            return
        }
        let pointCount = workoutRoutePointCount
        routeBuilder.finishRoute(with: workout, metadata: nil) { [weak self] route, error in
            var updated = session
            if var cardio = updated.outdoorCardio {
                cardio.routePointCount = pointCount
                cardio.routeStoredInHealthKit = route != nil && error == nil
                updated.outdoorCardio = cardio
            }
            Task { @MainActor [weak self] in
                self?.workoutRouteBuilder = nil
                self?.workoutRoutePointCount = 0
                if let error {
                    WatchDiagnostics.shared.record(
                        level: "error",
                        category: "route.finish",
                        message: "Workout route could not be finalized",
                        metadata: ["error": error.localizedDescription]
                    )
                }
                completion(updated)
            }
        }
    }
}
