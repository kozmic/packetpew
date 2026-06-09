#if os(macOS) && canImport(CPcap)
import Foundation
import CPcap

public enum PcapError: Error, CustomStringConvertible {
    case message(String)
    public var description: String {
        switch self { case .message(let m): return m }
    }
}

/// Real packet capture via libpcap. Requires access to /dev/bpf (run as root, or
/// install ChmodBPF). `make` throws a readable error if the device can't be opened —
/// in that case the engine falls back to the simulated source.
public final class PcapTrafficSource: TrafficSource, @unchecked Sendable {

    public let label: String
    public let events: AsyncStream<NetworkEvent>
    private let eventContinuation: AsyncStream<NetworkEvent>.Continuation

    private let rawStream: AsyncStream<RawFlow>
    private let rawContinuation: AsyncStream<RawFlow>.Continuation

    private let handle: UnsafeMutableRawPointer
    private let datalink: Int32
    private let locator: GeoLocator

    private var captureThread: Thread?
    private var consumer: Task<Void, Never>?
    private let runningLock = NSLock()
    private var running = false

    /// Raw flow without geo — filled on the capture thread, geolocated in the consumer.
    private struct RawFlow: Sendable {
        let localIP: String
        let remoteIP: String
        let localPort: UInt16
        let remotePort: UInt16
        let proto: TransportProtocol
        let length: Int
        let direction: Direction
    }

    private init(locator: GeoLocator, handle: UnsafeMutableRawPointer,
                 device: String, datalink: Int32) {
        self.locator = locator
        self.handle = handle
        self.datalink = datalink
        self.label = "LIVE · \(device)"

        var ec: AsyncStream<NetworkEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(512)) { ec = $0 }
        self.eventContinuation = ec

        var rc: AsyncStream<RawFlow>.Continuation!
        self.rawStream = AsyncStream(bufferingPolicy: .bufferingNewest(2048)) { rc = $0 }
        self.rawContinuation = rc
    }

    /// Try to open the capture device. Throws on missing privileges / unknown device.
    /// Selects the default route's interface (the one that actually reaches the
    /// internet) — otherwise we risk opening a virtual Apple interface (anpi*/en3/…)
    /// that carries no traffic.
    public static func make(locator: GeoLocator, device: String? = nil) throws -> PcapTrafficSource {
        var errbuf = [CChar](repeating: 0, count: 256)

        let dev: String
        if let device {
            dev = device
        } else if let routed = defaultRouteInterface() {
            dev = routed
        } else {
            var namebuf = [CChar](repeating: 0, count: 256)
            if cpcap_default_device(&namebuf, 256, &errbuf, 256) != 0 {
                throw PcapError.message("No capture device found: \(String(cString: errbuf))")
            }
            dev = String(cString: namebuf)
        }

        guard let handle = dev.withCString({ cpcap_open($0, 256, &errbuf, 256) }) else {
            throw PcapError.message(String(cString: errbuf))
        }
        _ = "ip or ip6".withCString { cpcap_set_filter(handle, $0) }
        let dl = cpcap_datalink(handle)
        log("LIVE capture on \(dev) (datalink \(dl)) — set PACKETPEW_IFACE to override")
        return PcapTrafficSource(locator: locator, handle: handle, device: dev, datalink: dl)
    }

    /// The default route's interface (`route -n get default`), or an env override.
    public static func defaultRouteInterface() -> String? {
        if let env = ProcessInfo.processInfo.environment["PACKETPEW_IFACE"],
           !env.isEmpty { return env }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/route")
        proc.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let out = String(data: data, encoding: .utf8) else { return nil }
            for raw in out.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("interface:") {
                    let name = line.dropFirst("interface:".count).trimmingCharacters(in: .whitespaces)
                    return name.isEmpty ? nil : name
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("PacketPew: \(message)\n".utf8))
    }

    public func start() {
        runningLock.lock()
        guard !running else { runningLock.unlock(); return }
        running = true
        runningLock.unlock()

        startConsumer()

        let thread = Thread { [weak self] in self?.captureLoop() }
        thread.name = "PacketPew.pcap"
        thread.stackSize = 1 << 20
        captureThread = thread
        thread.start()
    }

    public func stop() {
        runningLock.lock()
        running = false
        runningLock.unlock()
        consumer?.cancel()
        consumer = nil
        rawContinuation.finish()
        eventContinuation.finish()
        // The handle itself is closed once the capture thread has exited the loop (within ~200ms).
    }

    private func isRunning() -> Bool {
        runningLock.lock(); defer { runningLock.unlock() }
        return running
    }

    // MARK: - Capture thread

    private func captureLoop() {
        let dl = datalink
        var captured = 0
        var parsed = 0
        var lastLog = Date()
        while isRunning() {
            var dataPtr: UnsafePointer<UInt8>? = nil
            var caplen: Int32 = 0
            let r = cpcap_next(handle, &dataPtr, &caplen)
            if r == 1, let dp = dataPtr, caplen > 0 {
                captured += 1
                let bytes = Array(UnsafeBufferPointer(start: dp, count: Int(caplen)))
                if let p = PacketParser.parse(bytes, datalink: dl), let raw = classify(p) {
                    parsed += 1
                    rawContinuation.yield(raw)
                }
                // Periodic visibility in the console.
                if Date().timeIntervalSince(lastLog) >= 3 {
                    Self.log("captured \(captured) packets, parsed \(parsed) IP flows")
                    lastLog = Date()
                }
            } else if r < 0 {
                Self.log("capture stopped (pcap_next_ex returned \(r))")
                break // -1 error or -2 EOF
            }
            // r == 0 is a timeout → keep looping (lets us check isRunning()).
        }
        cpcap_close(handle)
    }

    private func classify(_ p: ParsedPacket) -> RawFlow? {
        let srcLocal = GeoLocator.isLocal(p.sourceIP)
        let dstLocal = GeoLocator.isLocal(p.destinationIP)

        if srcLocal && !dstLocal {
            return RawFlow(localIP: p.sourceIP, remoteIP: p.destinationIP,
                           localPort: p.sourcePort, remotePort: p.destinationPort,
                           proto: p.proto, length: p.length, direction: .outbound)
        } else if dstLocal && !srcLocal {
            return RawFlow(localIP: p.destinationIP, remoteIP: p.sourceIP,
                           localPort: p.destinationPort, remotePort: p.sourcePort,
                           proto: p.proto, length: p.length, direction: .inbound)
        } else if srcLocal && dstLocal {
            return RawFlow(localIP: p.sourceIP, remoteIP: p.destinationIP,
                           localPort: p.sourcePort, remotePort: p.destinationPort,
                           proto: p.proto, length: p.length, direction: .local)
        }
        // Both external (unusual on an endpoint machine) — treat as outbound.
        return RawFlow(localIP: p.sourceIP, remoteIP: p.destinationIP,
                       localPort: p.sourcePort, remotePort: p.destinationPort,
                       proto: p.proto, length: p.length, direction: .outbound)
    }

    // MARK: - Consumer (geo + throttling)

    private func startConsumer() {
        let locator = self.locator
        let raws = self.rawStream
        let out = self.eventContinuation
        consumer = Task.detached(priority: .utility) {
            // Throttle per remote IP so the visualization doesn't drown under load.
            var lastEmit: [String: Date] = [:]
            var pendingBytes: [String: Int] = [:]
            let interval: TimeInterval = 0.12

            for await raw in raws {
                if Task.isCancelled { break }
                let now = Date()
                pendingBytes[raw.remoteIP, default: 0] += raw.length
                if let last = lastEmit[raw.remoteIP], now.timeIntervalSince(last) < interval {
                    continue // accumulate bytes, hold off on sending
                }
                lastEmit[raw.remoteIP] = now
                let bytes = pendingBytes[raw.remoteIP] ?? raw.length
                pendingBytes[raw.remoteIP] = 0

                let home = await locator.home
                let remoteGeo = await locator.resolve(raw.remoteIP)

                let event: NetworkEvent
                switch raw.direction {
                case .outbound:
                    event = NetworkEvent(sourceIP: raw.localIP, destinationIP: raw.remoteIP,
                                         sourcePort: raw.localPort, destinationPort: raw.remotePort,
                                         proto: raw.proto, byteCount: bytes, direction: .outbound,
                                         source: home, destination: remoteGeo)
                case .inbound:
                    event = NetworkEvent(sourceIP: raw.remoteIP, destinationIP: raw.localIP,
                                         sourcePort: raw.remotePort, destinationPort: raw.localPort,
                                         proto: raw.proto, byteCount: bytes, direction: .inbound,
                                         source: remoteGeo, destination: home)
                case .local:
                    event = NetworkEvent(sourceIP: raw.localIP, destinationIP: raw.remoteIP,
                                         sourcePort: raw.localPort, destinationPort: raw.remotePort,
                                         proto: raw.proto, byteCount: bytes, direction: .local,
                                         source: home, destination: home)
                }
                out.yield(event)
            }
        }
    }
}
#endif
