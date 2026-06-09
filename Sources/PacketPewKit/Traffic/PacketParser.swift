import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Result of interpreting one raw packet.
public struct ParsedPacket: Sendable {
    public let sourceIP: String
    public let destinationIP: String
    public let sourcePort: UInt16
    public let destinationPort: UInt16
    public let proto: TransportProtocol
    public let length: Int
}

/// Stateless interpretation of raw link-layer bytes into IP info.
/// Handles the datalink types macOS actually gives us: Ethernet, loopback (NULL/LOOP) and RAW.
public enum PacketParser {

    // DLT_* from pcap-bpf.h
    private static let DLT_NULL: Int32 = 0
    private static let DLT_EN10MB: Int32 = 1
    private static let DLT_RAW: Int32 = 12
    private static let DLT_LOOP: Int32 = 108

    public static func parse(_ bytes: [UInt8], datalink: Int32) -> ParsedPacket? {
        switch datalink {
        case DLT_EN10MB:
            return parseEthernet(bytes)
        case DLT_NULL:
            return parseLoopback(bytes, bigEndianFamily: false)
        case DLT_LOOP:
            return parseLoopback(bytes, bigEndianFamily: true)
        case DLT_RAW:
            return parseIP(bytes, offset: 0)
        default:
            // Unknown link type: try Ethernet as the best guess.
            return parseEthernet(bytes)
        }
    }

    // MARK: - Link layer

    private static func parseEthernet(_ b: [UInt8]) -> ParsedPacket? {
        guard b.count >= 14 else { return nil }
        var offset = 14
        var ethertype = UInt16(b[12]) << 8 | UInt16(b[13])
        // Skip an optional 802.1Q VLAN tag.
        if ethertype == 0x8100, b.count >= 18 {
            ethertype = UInt16(b[16]) << 8 | UInt16(b[17])
            offset = 18
        }
        switch ethertype {
        case 0x0800, 0x86DD: return parseIP(b, offset: offset)
        default: return nil
        }
    }

    private static func parseLoopback(_ b: [UInt8], bigEndianFamily: Bool) -> ParsedPacket? {
        guard b.count >= 4 else { return nil }
        let family: UInt32 = bigEndianFamily
            ? (UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
            : (UInt32(b[3]) << 24 | UInt32(b[2]) << 16 | UInt32(b[1]) << 8 | UInt32(b[0]))
        // AF_INET = 2, AF_INET6 = 30 on macOS.
        guard family == 2 || family == 30 else { return nil }
        return parseIP(b, offset: 4)
    }

    // MARK: - IP

    private static func parseIP(_ b: [UInt8], offset: Int) -> ParsedPacket? {
        guard b.count > offset else { return nil }
        let version = b[offset] >> 4
        if version == 4 { return parseIPv4(b, offset: offset) }
        if version == 6 { return parseIPv6(b, offset: offset) }
        return nil
    }

    private static func parseIPv4(_ b: [UInt8], offset: Int) -> ParsedPacket? {
        guard b.count >= offset + 20 else { return nil }
        let ihl = Int(b[offset] & 0x0F) * 4
        guard ihl >= 20, b.count >= offset + ihl else { return nil }

        let totalLength = Int(UInt16(b[offset + 2]) << 8 | UInt16(b[offset + 3]))
        let protoByte = b[offset + 9]
        let src = ipv4String(b, at: offset + 12)
        let dst = ipv4String(b, at: offset + 16)

        let (proto, ports) = transport(protoByte, b, l4Offset: offset + ihl, isV6: false)
        return ParsedPacket(sourceIP: src, destinationIP: dst,
                            sourcePort: ports.0, destinationPort: ports.1,
                            proto: proto, length: max(totalLength, b.count - offset))
    }

    private static func parseIPv6(_ b: [UInt8], offset: Int) -> ParsedPacket? {
        guard b.count >= offset + 40 else { return nil }
        let payloadLength = Int(UInt16(b[offset + 4]) << 8 | UInt16(b[offset + 5]))
        let nextHeader = b[offset + 6]
        let src = ipv6String(b, at: offset + 8)
        let dst = ipv6String(b, at: offset + 24)

        // We don't parse IPv6 extension headers; ports are only read on direct TCP/UDP.
        let (proto, ports) = transport(nextHeader, b, l4Offset: offset + 40, isV6: true)
        return ParsedPacket(sourceIP: src, destinationIP: dst,
                            sourcePort: ports.0, destinationPort: ports.1,
                            proto: proto, length: 40 + payloadLength)
    }

    private static func transport(_ proto: UInt8, _ b: [UInt8], l4Offset: Int, isV6: Bool)
        -> (TransportProtocol, (UInt16, UInt16)) {
        switch proto {
        case 6, 17: // TCP / UDP
            var ports: (UInt16, UInt16) = (0, 0)
            if b.count >= l4Offset + 4 {
                ports.0 = UInt16(b[l4Offset]) << 8 | UInt16(b[l4Offset + 1])
                ports.1 = UInt16(b[l4Offset + 2]) << 8 | UInt16(b[l4Offset + 3])
            }
            return (proto == 6 ? .tcp : .udp, ports)
        case 1:  return (.icmp, (0, 0))
        case 58: return (.icmp6, (0, 0))
        default: return (.other, (0, 0))
        }
    }

    // MARK: - Address formatting (via inet_ntop)

    private static func ipv4String(_ b: [UInt8], at i: Int) -> String {
        "\(b[i]).\(b[i + 1]).\(b[i + 2]).\(b[i + 3])"
    }

    private static func ipv6String(_ b: [UInt8], at i: Int) -> String {
        #if canImport(Darwin)
        var addr = in6_addr()
        withUnsafeMutableBytes(of: &addr) { raw in
            for k in 0..<16 { raw[k] = b[i + k] }
        }
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result = inet_ntop(AF_INET6, &addr, &buf, socklen_t(INET6_ADDRSTRLEN))
        if result != nil { return String(cString: buf) }
        #endif
        // Fallback: raw hex groups.
        var parts: [String] = []
        for k in stride(from: 0, to: 16, by: 2) {
            parts.append(String(format: "%02x%02x", b[i + k], b[i + k + 1]))
        }
        return parts.joined(separator: ":")
    }
}
