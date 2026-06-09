import Foundation

/// Coarse country centroids and a selection of major cities. Used for:
///  - the offline fallback when an IP lookup can't be done, and
///  - the simulated traffic stream (so the demo always looks alive).
public enum GeoData {

    /// ISO alpha-2 → (latitude, longitude, name).
    public static let countries: [String: (lat: Double, lon: Double, name: String)] = [
        "US": (39.8, -98.6, "United States"),
        "CA": (56.1, -106.3, "Canada"),
        "MX": (23.6, -102.5, "Mexico"),
        "BR": (-14.2, -51.9, "Brazil"),
        "AR": (-38.4, -63.6, "Argentina"),
        "CL": (-35.7, -71.5, "Chile"),
        "CO": (4.6, -74.3, "Colombia"),
        "PE": (-9.2, -75.0, "Peru"),
        "GB": (54.0, -2.0, "United Kingdom"),
        "IE": (53.4, -8.2, "Ireland"),
        "FR": (46.2, 2.2, "France"),
        "ES": (40.5, -3.7, "Spain"),
        "PT": (39.4, -8.2, "Portugal"),
        "DE": (51.2, 10.4, "Germany"),
        "NL": (52.1, 5.3, "Netherlands"),
        "BE": (50.5, 4.5, "Belgium"),
        "CH": (46.8, 8.2, "Switzerland"),
        "AT": (47.5, 14.6, "Austria"),
        "IT": (41.9, 12.6, "Italy"),
        "NO": (60.5, 8.5, "Norway"),
        "SE": (60.1, 18.6, "Sweden"),
        "DK": (56.3, 9.5, "Denmark"),
        "FI": (61.9, 25.7, "Finland"),
        "IS": (64.9, -19.0, "Iceland"),
        "PL": (51.9, 19.1, "Poland"),
        "CZ": (49.8, 15.5, "Czechia"),
        "RO": (45.9, 24.9, "Romania"),
        "UA": (48.4, 31.2, "Ukraine"),
        "RU": (61.5, 105.3, "Russia"),
        "GR": (39.1, 21.8, "Greece"),
        "TR": (38.9, 35.2, "Türkiye"),
        "IL": (31.0, 34.8, "Israel"),
        "SA": (23.9, 45.1, "Saudi Arabia"),
        "AE": (23.4, 53.8, "UAE"),
        "EG": (26.8, 30.8, "Egypt"),
        "ZA": (-30.6, 22.9, "South Africa"),
        "NG": (9.1, 8.7, "Nigeria"),
        "KE": (-0.0, 37.9, "Kenya"),
        "MA": (31.8, -7.1, "Morocco"),
        "IN": (20.6, 79.0, "India"),
        "PK": (30.4, 69.3, "Pakistan"),
        "CN": (35.9, 104.2, "China"),
        "HK": (22.3, 114.2, "Hong Kong"),
        "TW": (23.7, 121.0, "Taiwan"),
        "JP": (36.2, 138.3, "Japan"),
        "KR": (35.9, 127.8, "South Korea"),
        "SG": (1.35, 103.8, "Singapore"),
        "MY": (4.2, 101.98, "Malaysia"),
        "ID": (-0.8, 113.9, "Indonesia"),
        "TH": (15.9, 100.99, "Thailand"),
        "VN": (14.06, 108.3, "Vietnam"),
        "PH": (12.9, 121.8, "Philippines"),
        "AU": (-25.3, 133.8, "Australia"),
        "NZ": (-40.9, 174.9, "New Zealand")
    ]

    /// Major cities (name, country code, lat, lon). A bit more precise than centroids.
    public struct City: Sendable {
        public let name: String
        public let country: String
        public let lat: Double
        public let lon: Double
    }

    public static let cities: [City] = [
        City(name: "New York", country: "US", lat: 40.71, lon: -74.01),
        City(name: "Ashburn", country: "US", lat: 39.04, lon: -77.49),
        City(name: "San Francisco", country: "US", lat: 37.77, lon: -122.42),
        City(name: "Seattle", country: "US", lat: 47.61, lon: -122.33),
        City(name: "Dallas", country: "US", lat: 32.78, lon: -96.80),
        City(name: "Toronto", country: "CA", lat: 43.65, lon: -79.38),
        City(name: "São Paulo", country: "BR", lat: -23.55, lon: -46.63),
        City(name: "London", country: "GB", lat: 51.51, lon: -0.13),
        City(name: "Dublin", country: "IE", lat: 53.35, lon: -6.26),
        City(name: "Paris", country: "FR", lat: 48.86, lon: 2.35),
        City(name: "Amsterdam", country: "NL", lat: 52.37, lon: 4.90),
        City(name: "Frankfurt", country: "DE", lat: 50.11, lon: 8.68),
        City(name: "Stockholm", country: "SE", lat: 59.33, lon: 18.07),
        City(name: "Oslo", country: "NO", lat: 59.91, lon: 10.75),
        City(name: "Helsinki", country: "FI", lat: 60.17, lon: 24.94),
        City(name: "Warsaw", country: "PL", lat: 52.23, lon: 21.01),
        City(name: "Moscow", country: "RU", lat: 55.76, lon: 37.62),
        City(name: "Istanbul", country: "TR", lat: 41.01, lon: 28.98),
        City(name: "Dubai", country: "AE", lat: 25.20, lon: 55.27),
        City(name: "Tel Aviv", country: "IL", lat: 32.09, lon: 34.78),
        City(name: "Lagos", country: "NG", lat: 6.52, lon: 3.38),
        City(name: "Johannesburg", country: "ZA", lat: -26.20, lon: 28.05),
        City(name: "Mumbai", country: "IN", lat: 19.08, lon: 72.88),
        City(name: "Bengaluru", country: "IN", lat: 12.97, lon: 77.59),
        City(name: "Singapore", country: "SG", lat: 1.35, lon: 103.82),
        City(name: "Hong Kong", country: "HK", lat: 22.32, lon: 114.17),
        City(name: "Shanghai", country: "CN", lat: 31.23, lon: 121.47),
        City(name: "Beijing", country: "CN", lat: 39.90, lon: 116.41),
        City(name: "Tokyo", country: "JP", lat: 35.68, lon: 139.69),
        City(name: "Seoul", country: "KR", lat: 37.57, lon: 126.98),
        City(name: "Sydney", country: "AU", lat: -33.87, lon: 151.21),
        City(name: "Jakarta", country: "ID", lat: -6.21, lon: 106.85)
    ]

    /// Deterministic fallback: map a string (IP) to a fixed country.
    public static func fallbackCountry(for key: String) -> GeoPoint {
        let codes = Array(countries.keys).sorted()
        var hash: UInt64 = 1469598103934665603 // FNV-1a
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let code = codes[Int(hash % UInt64(codes.count))]
        let c = countries[code]!
        // A little spread around the centroid so arrows don't stack on top of each other.
        let jitterLat = Double((hash >> 8) % 600) / 100.0 - 3.0
        let jitterLon = Double((hash >> 20) % 1200) / 100.0 - 6.0
        return GeoPoint(latitude: c.lat + jitterLat,
                        longitude: c.lon + jitterLon,
                        countryCode: code,
                        label: c.name)
    }
}
