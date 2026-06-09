import Foundation

/// Loads and holds the world's country borders (Natural Earth 110m, public domain),
/// compressed to rings of (longitude, latitude) for drawing on the globe.
public enum WorldMap {

    private struct World: Decodable {
        let rings: [[Double]]   // each ring: flat [lon,lat,lon,lat,...]
    }

    /// Each ring as a list of (lat, lon) points. Empty if the data is missing.
    public static let rings: [[(lat: Double, lon: Double)]] = load()

    private static func load() -> [[(lat: Double, lon: Double)]] {
        guard let data = loadData() else { return [] }
        guard let world = try? JSONDecoder().decode(World.self, from: data) else { return [] }
        return world.rings.map { flat in
            var pts: [(lat: Double, lon: Double)] = []
            pts.reserveCapacity(flat.count / 2)
            var i = 0
            while i + 1 < flat.count {
                pts.append((lat: flat[i + 1], lon: flat[i]))
                i += 2
            }
            return pts
        }
    }

    private static func loadData() -> Data? {
        // Primary: the resource bundle (works for both `swift run` and the release binary).
        if let url = Bundle.module.url(forResource: "world", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        // Fallback: look for the file next to the binary or in the working directory.
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("world.json"),
            URL(fileURLWithPath: "Sources/PacketPewKit/Resources/world.json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("world.json")
        ]
        for url in candidates {
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }
}
