import Foundation
import Combine
import Observation

/// The two visualization modes.
public enum VizMode: String, CaseIterable, Identifiable, Sendable {
    case globe
    case radar

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .globe: return "Globe"
        case .radar: return "Packet Radar"
        }
    }
    public var systemImage: String {
        switch self {
        case .globe: return "globe.europe.africa.fill"
        case .radar: return "dot.radiowaves.left.and.right"
        }
    }
}

/// One of the most active remote peers.
public struct TopTalker: Identifiable, Sendable {
    public var id: String { ip }
    public var ip: String
    public var geo: GeoPoint
    public var bytes: Int
    public var packets: Int
    public var lastSeen: Date
}

/// Central state: picks the traffic source, consumes events, tracks statistics,
/// and broadcasts every event to the imperative views via `pulse`.
@MainActor
@Observable
public final class TrafficEngine {

    // MARK: - Observed state (drives SwiftUI)
    public var mode: VizMode = .globe
    public var paused: Bool = false

    public private(set) var isRunning = false
    public private(set) var isLive = false
    public private(set) var sourceLabel = "Starting…"
    public private(set) var statusDetail = ""

    public private(set) var totalPackets = 0
    public private(set) var totalBytes = 0
    public private(set) var packetsPerSecond = 0
    public private(set) var bytesPerSecond = 0
    public private(set) var protocolCounts: [TransportProtocol: Int] = [:]
    public private(set) var topTalkers: [TopTalker] = []
    public private(set) var homeGeo = GeoPoint(latitude: 59.91, longitude: 10.75,
                                               countryCode: "NO", label: "This device")

    // MARK: - Non-observed machinery
    @ObservationIgnored public let pulse = PassthroughSubject<NetworkEvent, Never>()
    @ObservationIgnored private let locator = GeoLocator(useOnline: true)
    @ObservationIgnored private var source: TrafficSource?
    @ObservationIgnored private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var rateTimer: Timer?
    @ObservationIgnored private var lastPackets = 0
    @ObservationIgnored private var lastBytes = 0
    @ObservationIgnored private var talkers: [String: TopTalker] = [:]

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        // Find the machine's own position in the background.
        Task { [weak self] in
            guard let self else { return }
            await self.locator.refreshHome()
            let home = await self.locator.home
            self.homeGeo = home
        }

        let src = makeSource()
        source = src
        sourceLabel = src.label
        isLive = src.label.hasPrefix("LIVE")
        src.start()

        let stream = src.events
        consumeTask = Task { [weak self] in
            for await event in stream {
                self?.ingest(event)
            }
        }

        startRateTimer()
    }

    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
        source?.stop()
        source = nil
        rateTimer?.invalidate()
        rateTimer = nil
        isRunning = false
    }

    public func togglePause() { paused.toggle() }

    private func makeSource() -> TrafficSource {
        #if canImport(CPcap)
        do {
            let pcap = try PcapTrafficSource.make(locator: locator)
            statusDetail = "Live capture · /dev/bpf"
            return pcap
        } catch {
            statusDetail = "No capture access (\(error)) — demo stream"
            return SimulatedTrafficSource(locator: locator, reason: "no /dev/bpf access")
        }
        #else
        statusDetail = "Demo stream (live capture is macOS-only)"
        return SimulatedTrafficSource(locator: locator, reason: "iOS")
        #endif
    }

    // MARK: - Ingest

    private func ingest(_ event: NetworkEvent) {
        guard !paused else { return }

        totalPackets += 1
        totalBytes += event.byteCount
        protocolCounts[event.proto, default: 0] += 1

        let key = event.remoteIP
        var talker = talkers[key] ?? TopTalker(ip: key, geo: event.remoteGeo,
                                               bytes: 0, packets: 0, lastSeen: event.timestamp)
        talker.bytes += event.byteCount
        talker.packets += 1
        talker.geo = event.remoteGeo
        talker.lastSeen = event.timestamp
        talkers[key] = talker

        if talkers.count > 256 {
            let keep = talkers.values.sorted { $0.lastSeen > $1.lastSeen }.prefix(160)
            talkers = Dictionary(uniqueKeysWithValues: keep.map { ($0.ip, $0) })
        }

        topTalkers = talkers.values.sorted { $0.bytes > $1.bytes }.prefix(6).map { $0 }

        pulse.send(event)
    }

    private func startRateTimer() {
        rateTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.packetsPerSecond = self.totalPackets - self.lastPackets
                self.bytesPerSecond = self.totalBytes - self.lastBytes
                self.lastPackets = self.totalPackets
                self.lastBytes = self.totalBytes
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rateTimer = timer
    }
}

// MARK: - Formatting helpers

public enum Format {
    public static func bytes(_ value: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(value)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(value) B" : String(format: "%.1f %@", v, units[i])
    }

    public static func rate(_ bytesPerSecond: Int) -> String {
        bytes(bytesPerSecond) + "/s"
    }
}
