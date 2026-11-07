import Foundation
import CoreLocation

/// Разовое определение местоположения. Постоянный доступ не запрашивается.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status: CLAuthorizationStatus
    @Published var location: CLLocation?
    @Published var message: String?
    @Published var isLocating = false
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool { status == .denied || status == .restricted }
    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    func request() {
        message = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isLocating = true
            manager.requestLocation()
        default:
            message = "Доступ к геолокации запрещён. Выберите адрес вручную или разрешите доступ в Настройках iOS."
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedWhenInUse || s == .authorizedAlways {
                self.isLocating = true
                manager.requestLocation()
            } else if s == .denied || s == .restricted {
                self.message = "Доступ к геолокации запрещён. Выберите адрес вручную."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            self.location = last
            self.isLocating = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLocating = false
            self.message = "Не удалось определить местоположение. Проверьте связь или выберите адрес вручную."
        }
    }
}
