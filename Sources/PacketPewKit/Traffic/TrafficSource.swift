import Foundation

/// A source of geolocated network events. Concrete implementations:
///  - `SimulatedTrafficSource` (always available, no privileges)
///  - `PcapTrafficSource` (real capture via libpcap, requires root — macOS only)
public protocol TrafficSource: AnyObject, Sendable {
    /// Human-readable description of the source ("LIVE · en0", "DEMO …").
    var label: String { get }
    /// Stream of fully geolocated events.
    var events: AsyncStream<NetworkEvent> { get }
    func start()
    func stop()
}
