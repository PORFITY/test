import Foundation
import MapKit
import MealCore

/// Поиск продуктовых магазинов через Apple MapKit. Никакого фиксированного списка сетей — ищутся любые магазины.
enum StoreSearchService {
    static let queries = ["продукты", "супермаркет", "продуктовый магазин", "гипермаркет", "овощи и фрукты", "мясная лавка"]

    static func search(center: CLLocationCoordinate2D, radiusM: Double) async -> [StoreInfo] {
        // Для больших радиусов делим область на ячейки: MapKit возвращает ограниченное число результатов на запрос.
        let n = radiusM <= 3000 ? 1 : (radiusM <= 10_000 ? 2 : 3)
        let cellSpan = radiusM * 2 / Double(n)
        var found: [StoreInfo] = []
        var seen = Set<String>()
        for ix in 0..<n {
            for iy in 0..<n {
                let dx = (Double(ix) - Double(n - 1) / 2) * cellSpan
                let dy = (Double(iy) - Double(n - 1) / 2) * cellSpan
                let c = offset(center, eastM: dx, northM: dy)
                for q in (n == 1 ? queries : Array(queries.prefix(3))) {
                    let req = MKLocalSearch.Request()
                    req.naturalLanguageQuery = q
                    req.region = MKCoordinateRegion(center: c, latitudinalMeters: cellSpan * 1.2, longitudinalMeters: cellSpan * 1.2)
                    req.resultTypes = .pointOfInterest
                    guard let resp = try? await MKLocalSearch(request: req).start() else { continue }
                    for item in resp.mapItems {
                        let coord = item.placemark.coordinate
                        let name = item.name ?? "Магазин"
                        let key = "\(name)|\(Int(coord.latitude * 10_000))|\(Int(coord.longitude * 10_000))"
                        if !seen.insert(key).inserted { continue }
                        let dist = Geo.distance(lat1: center.latitude, lon1: center.longitude, lat2: coord.latitude, lon2: coord.longitude)
                        if dist > radiusM { continue }
                        if let cat = item.pointOfInterestCategory, cat != .foodMarket, cat != .store { continue }
                        found.append(StoreInfo(id: "mk:\(key)", name: name, chain: StoreDirectory.chain(forName: name),
                                               address: item.placemark.title, lat: coord.latitude, lon: coord.longitude, distanceM: dist,
                                               shopType: StoreDirectory.shopType(forName: name), source: "mapkit"))
                    }
                }
            }
        }
        return found
    }

    static func offset(_ c: CLLocationCoordinate2D, eastM: Double, northM: Double) -> CLLocationCoordinate2D {
        let dLat = northM / 111_320
        let dLon = eastM / (111_320 * max(0.1, cos(c.latitude * .pi / 180)))
        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
    }

    /// Геокодирование адреса, введённого вручную.
    static func geocode(_ text: String) async -> (CLLocationCoordinate2D, String)? {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.resultTypes = .address
        guard let resp = try? await MKLocalSearch(request: req).start(), let item = resp.mapItems.first else { return nil }
        return (item.placemark.coordinate, item.placemark.title ?? text)
    }
}
