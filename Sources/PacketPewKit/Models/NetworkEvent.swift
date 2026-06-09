import Foundation
import SwiftUI

/// A geographic point with a little metadata for display.
public struct GeoPoint: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    /// ISO 3166-1 alpha-2 (e.g. "NO"), "LAN" for the local network, or "??" when unknown.
    public var countryCode: String
    /// Human-readable label (city/country) for the HUD.
    public var label: String

    public init(latitude: Double, longitude: Double, countryCode: String, label: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.countryCode = countryCode
        self.label = label
    }
}

/// Transport protocol derived from the IP packet.
public enum TransportProtocol: String, Sendable, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
    case icmp = "ICMP"
    case icmp6 = "ICMPv6"
    case other = "OTHER"

    /// Neon color associated with the protocol (used in the radar view and the legend).
    public var hex: UInt32 {
        switch self {
        case .tcp:   return 0x36F1CD // teal
        case .udp:   return 0xFFC24B // amber
        case .icmp:  return 0xFF6B9D // pink
        case .icmp6: return 0xC792EA // purple
        case .other: return 0x8AA0B6 // gray-blue
        }
    }
}

/// Traffic direction as seen from this machine.
public enum Direction: Sendable {
    case inbound   // from outside → here
    case outbound  // from here → out
    case local     // between two local addresses

    public var hex: UInt32 {
        switch self {
        case .outbound: return 0x36F1CD // teal-green = we fire outward
        case .inbound:  return 0xFF2D6B // hot pink/red = incoming hit
        case .local:    return 0xFFD23F // yellow = local
        }
    }
}

/// A single observed network event (a flow sample, not necessarily one packet).
public struct NetworkEvent: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let sourceIP: String
    public let destinationIP: String
    public let sourcePort: UInt16
    public let destinationPort: UInt16
    public let proto: TransportProtocol
    public let byteCount: Int
    public let direction: Direction
    public let source: GeoPoint
    public let destination: GeoPoint

    public init(
        timestamp: Date = Date(),
        sourceIP: String,
        destinationIP: String,
        sourcePort: UInt16 = 0,
        destinationPort: UInt16 = 0,
        proto: TransportProtocol,
        byteCount: Int,
        direction: Direction,
        source: GeoPoint,
        destination: GeoPoint
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sourceIP = sourceIP
        self.destinationIP = destinationIP
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.proto = proto
        self.byteCount = byteCount
        self.direction = direction
        self.source = source
        self.destination = destination
    }

    /// The remote (non-local) end, the way the HUD prefers to show it.
    public var remoteIP: String {
        direction == .inbound ? sourceIP : destinationIP
    }

    public var remoteGeo: GeoPoint {
        direction == .inbound ? source : destination
    }
}

public extension String {
    /// Turns an ISO country code into a flag emoji ("NO" → "🇳🇴"). Empty for "LAN"/"??".
    var flagEmoji: String {
        guard count == 2 else { return "" }
        let base: UInt32 = 0x1F1E6
        var s = ""
        for scalar in unicodeScalars {
            guard let v = scalar.value as UInt32?,
                  scalar.properties.isAlphabetic,
                  let u = UnicodeScalar(base + (v - 65)) else { return "" }
            s.unicodeScalars.append(u)
        }
        return s
    }
}
