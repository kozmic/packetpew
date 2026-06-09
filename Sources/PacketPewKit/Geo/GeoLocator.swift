import Foundation

/// Resolves IP → location. Private/LAN traffic maps to the machine's own position.
/// Public IPs are looked up against ip-api.com (cached), with a deterministic
/// country fallback when offline or when the lookup fails.
public actor GeoLocator {

    private var cache: [String: GeoPoint] = [:]
    private var inFlight: [String: Task<GeoPoint, Never>] = [:]
    private let fetcher = NetFetcher()

    /// The machine's position (used for the local end of a flow).
    public private(set) var home: GeoPoint
    private let useOnline: Bool

    public init(useOnline: Bool = true,
                home: GeoPoint = GeoPoint(latitude: 59.91, longitude: 10.75,
                                          countryCode: "NO", label: "This device")) {
        self.useOnline = useOnline
        self.home = home
    }

    /// Try to find the machine's own position (a lookup with no IP returns our own outgoing IP).
    public func refreshHome() async {
        guard useOnline, let geo = await fetcher.fetch(ip: nil) else { return }
        home = GeoPoint(latitude: geo.latitude, longitude: geo.longitude,
                        countryCode: geo.countryCode, label: "This device · \(geo.label)")
    }

    public func setHome(_ point: GeoPoint) {
        home = point
    }

    /// Non-blocking lookup: returns immediately (cache hit, LAN, or a deterministic
    /// country fallback) and starts a background lookup that updates the cache, so
    /// repeated connections to the same IP become accurate. This keeps the event
    /// stream fast even when ip-api.com is slow/unavailable.
    public func resolve(_ ip: String) -> GeoPoint {
        if let hit = cache[ip] { return hit }

        if Self.isLocal(ip) {
            let g = GeoPoint(latitude: home.latitude, longitude: home.longitude,
                             countryCode: "LAN", label: "Local network")
            cache[ip] = g
            return g
        }

        // Start one background lookup per IP (don't duplicate an in-flight one).
        if useOnline, inFlight[ip] == nil {
            let fetcher = self.fetcher
            inFlight[ip] = Task { [weak self] in
                let geo = await fetcher.fetch(ip: ip) ?? GeoData.fallbackCountry(for: ip)
                await self?.store(ip: ip, geo: geo)
                return geo
            }
        }

        // Use an approximate position now — refined once the background lookup finishes.
        return GeoData.fallbackCountry(for: ip)
    }

    private func store(ip: String, geo: GeoPoint) {
        cache[ip] = geo
        inFlight[ip] = nil
    }

    // MARK: - Local-IP detection

    public static func isLocal(_ ip: String) -> Bool {
        if ip.contains(":") { return isLocalIPv6(ip) }
        return isLocalIPv4(ip)
    }

    private static func isLocalIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return true } // unknown format → treat as local
        let (a, b) = (parts[0], parts[1])
        if a == 10 { return true }                            // 10.0.0.0/8
        if a == 127 { return true }                           // loopback
        if a == 172 && (16...31).contains(b) { return true }  // 172.16.0.0/12
        if a == 192 && b == 168 { return true }               // 192.168.0.0/16
        if a == 169 && b == 254 { return true }               // link-local
        if a == 100 && (64...127).contains(b) { return true } // CGNAT
        if a == 0 || a >= 224 { return true }                 // 0.0.0.0 / multicast / reserved
        return false
    }

    private static func isLocalIPv6(_ ip: String) -> Bool {
        let lower = ip.lowercased()
        if lower == "::1" || lower == "::" { return true }
        if lower.hasPrefix("fe80") { return true } // link-local
        if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return true } // unique local
        if lower.hasPrefix("ff") { return true }   // multicast
        return false
    }
}

/// Small, isolated network fetcher for ip-api.com.
private actor NetFetcher {
    private struct APIResponse: Decodable {
        let status: String
        let country: String?
        let countryCode: String?
        let city: String?
        let lat: Double?
        let lon: Double?
    }

    func fetch(ip: String?) async -> GeoPoint? {
        let base = ip.map { "https://ip-api.com/json/\($0)" } ?? "https://ip-api.com/json/"
        guard let url = URL(string: "\(base)?fields=status,country,countryCode,city,lat,lon") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3.0
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let r = try JSONDecoder().decode(APIResponse.self, from: data)
            guard r.status == "success", let lat = r.lat, let lon = r.lon else { return nil }
            let code = r.countryCode ?? "??"
            let label = [r.city, r.country].compactMap { $0 }.first ?? code
            return GeoPoint(latitude: lat, longitude: lon, countryCode: code, label: label)
        } catch {
            return nil
        }
    }
}
