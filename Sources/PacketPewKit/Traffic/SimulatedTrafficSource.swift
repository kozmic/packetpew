import Foundation

/// Generates plausible, lively traffic without any privileges. The default source
/// when real capture isn't available (running without root, or on iOS).
public final class SimulatedTrafficSource: TrafficSource, @unchecked Sendable {

    public let label: String
    public let events: AsyncStream<NetworkEvent>
    private let continuation: AsyncStream<NetworkEvent>.Continuation
    private let locator: GeoLocator
    private var task: Task<Void, Never>?

    public init(locator: GeoLocator, reason: String? = nil) {
        self.locator = locator
        self.label = reason.map { "DEMO · \($0)" } ?? "DEMO"
        var cont: AsyncStream<NetworkEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(256)) { cont = $0 }
        self.continuation = cont
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            let home = await self.locator.home
            while !Task.isCancelled {
                self.emit(home: home)
                // Waves of activity: mostly dense, with the occasional pause.
                let gap = UInt64(Double.random(in: 0.04...0.22) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: gap)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        continuation.finish()
    }

    private func emit(home: GeoPoint) {
        let city = GeoData.cities.randomElement()!
        let remote = GeoPoint(latitude: city.lat + .random(in: -1...1),
                              longitude: city.lon + .random(in: -1...1),
                              countryCode: city.country,
                              label: "\(city.name), \(city.country)")

        // Weighted protocol mix, dominated by TCP/UDP like real traffic.
        let proto: TransportProtocol
        switch Int.random(in: 0..<100) {
        case 0..<58:  proto = .tcp
        case 58..<88: proto = .udp
        case 88..<94: proto = .icmp
        case 94..<98: proto = .icmp6
        default:      proto = .other
        }

        // Slightly more outbound than inbound (typical for a client).
        let outbound = Double.random(in: 0...1) < 0.6
        let direction: Direction = outbound ? .outbound : .inbound

        let remotePort: UInt16 = [443, 443, 443, 80, 53, 8443, 22, 123, 3478, 993]
            .randomElement()!
        let ephemeral = UInt16.random(in: 49152...65535)

        let bytes = Int(pow(10.0, Double.random(in: 1.6...4.2))) // ~40 B → ~16 KB
        let homeIP = "192.168.1.\(Int.random(in: 2...250))"
        let remoteIP = Self.randomPublicIP()

        let event: NetworkEvent
        if outbound {
            event = NetworkEvent(sourceIP: homeIP, destinationIP: remoteIP,
                                 sourcePort: ephemeral, destinationPort: remotePort,
                                 proto: proto, byteCount: bytes, direction: direction,
                                 source: home, destination: remote)
        } else {
            event = NetworkEvent(sourceIP: remoteIP, destinationIP: homeIP,
                                 sourcePort: remotePort, destinationPort: ephemeral,
                                 proto: proto, byteCount: bytes, direction: direction,
                                 source: remote, destination: home)
        }
        continuation.yield(event)
    }

    private static func randomPublicIP() -> String {
        "\(Int.random(in: 1...223)).\(Int.random(in: 0...255)).\(Int.random(in: 0...255)).\(Int.random(in: 1...254))"
    }
}
