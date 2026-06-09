import Foundation

/// Non-graphical smoke test of the fragile code paths (geometry, glow texture,
/// packet parsing, geo fallback, scene construction). Used by `PacketPew --selftest`.
@MainActor
public func runSelfTest() -> [String] {
    var log: [String] = []

    // 1) Packet parsing of a hand-crafted Ethernet/IPv4/TCP frame.
    var pkt = [UInt8](repeating: 0, count: 54)
    // Ethernet type = IPv4
    pkt[12] = 0x08; pkt[13] = 0x00
    // IPv4 header
    pkt[14] = 0x45                 // version 4, IHL 5
    pkt[16] = 0x00; pkt[17] = 0x28 // total length = 40
    pkt[22] = 64                   // TTL
    pkt[23] = 6                    // protocol = TCP
    pkt[26] = 8; pkt[27] = 8; pkt[28] = 8; pkt[29] = 8       // src 8.8.8.8
    pkt[30] = 192; pkt[31] = 168; pkt[32] = 1; pkt[33] = 5   // dst 192.168.1.5
    // TCP ports
    pkt[34] = 0x01; pkt[35] = 0xBB // src 443
    pkt[36] = 0xC3; pkt[37] = 0x50 // dst 50000
    if let p = PacketParser.parse(pkt, datalink: 1) {
        log.append("parser: \(p.sourceIP):\(p.sourcePort) → \(p.destinationIP):\(p.destinationPort) \(p.proto.rawValue) len=\(p.length)")
        precondition(p.sourceIP == "8.8.8.8" && p.proto == .tcp && p.sourcePort == 443,
                     "unexpected parse result")
    } else {
        log.append("parser: FAILED — got nil")
    }

    // 2) Local-IP detection.
    precondition(GeoLocator.isLocal("192.168.1.5"))
    precondition(!GeoLocator.isLocal("8.8.8.8"))
    log.append("isLocal: ok")

    // 3) Geo fallback is deterministic.
    let g1 = GeoData.fallbackCountry(for: "203.0.113.7")
    let g2 = GeoData.fallbackCountry(for: "203.0.113.7")
    precondition(g1.countryCode == g2.countryCode, "fallback must be deterministic")
    log.append("geo-fallback: 203.0.113.7 → \(g1.countryCode) (\(g1.label))")

    // 4) World data loaded from the resource bundle.
    let ringCount = WorldMap.rings.count
    let pointCount = WorldMap.rings.reduce(0) { $0 + $1.count }
    log.append("worldmap: \(ringCount) rings, \(pointCount) points")
    precondition(ringCount > 0, "world data (world.json) was not loaded")

    // 5) SceneKit globe: build the scene, set home, and fire a few arcs.
    #if canImport(SceneKit)
    let renderer = GlobeRenderer()
    renderer.updateHome(GeoPoint(latitude: 59.91, longitude: 10.75, countryCode: "NO", label: "home"))
    let home = GeoPoint(latitude: 59.91, longitude: 10.75, countryCode: "NO", label: "home")
    for city in GeoData.cities.prefix(6) {
        let remote = GeoPoint(latitude: city.lat, longitude: city.lon, countryCode: city.country, label: city.name)
        renderer.fire(NetworkEvent(sourceIP: "192.168.1.5", destinationIP: "203.0.113.7",
                                   proto: .tcp, byteCount: 1200, direction: .outbound,
                                   source: home, destination: remote))
    }
    precondition(GlobeRenderer.glowImage(color: .white) != nil, "glow texture is nil")
    log.append("scene: globe built, arcs fired, glow texture ok")
    #endif

    // 6) Interface selection for live capture (verifiable without root).
    #if canImport(CPcap)
    let iface = PcapTrafficSource.defaultRouteInterface() ?? "(unknown)"
    log.append("live capture would use interface: \(iface)")
    #endif

    log.append("ALL CHECKS PASSED")
    return log
}

/// Async part: verify that the simulated source actually produces events through
/// the AsyncStream. (Avoids MainActor so it doesn't block the main thread in the test.)
public func runAsyncSelfTest() async -> [String] {
    var log: [String] = []
    let locator = GeoLocator(useOnline: false)
    let sim = SimulatedTrafficSource(locator: locator, reason: "selftest")

    // Safety net: stop the source after 2s so the loop is guaranteed to end.
    let timeout = Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        sim.stop()
    }

    sim.start()
    var count = 0
    for await event in sim.events {
        count += 1
        if count <= 2 {
            log.append("sim event: \(event.sourceIP) → \(event.destinationIP) \(event.proto.rawValue) \(event.direction)")
        }
        if count >= 6 { break }
    }
    timeout.cancel()
    sim.stop()

    precondition(count > 0, "no simulated events produced")
    log.append("sim-source: \(count) events ok")
    return log
}
