import SwiftUI

// Shared style tokens for the HUD.
enum Theme {
    static let bg = Color(hex: 0x04070E)
    static let panel = Color(hex: 0x0A1422, opacity: 0.66)
    static let stroke = Color(hex: 0x1E3A5F, opacity: 0.8)
    static let accent = Color(hex: 0x36F1CD)
    static let dim = Color(hex: 0x8AA0B6)
    static let mono = Font.system(.body, design: .monospaced)
}

/// Glassy panel background with a thin neon border.
struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.panel)
                    .background(.ultraThinMaterial.opacity(0.25),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

extension View {
    func panel() -> some View { modifier(Panel()) }
}

/// Small label "NAME  value".
struct Stat: View {
    let label: String
    let value: String
    var color: Color = .white
    var body: some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

/// Statistics panel: rate, total and protocol breakdown.
struct StatsPanel: View {
    let engine: TrafficEngine

    private var protocolTotal: Int {
        max(1, engine.protocolCounts.values.reduce(0, +))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TRAFFIC")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .kerning(2)

            Stat(label: "packets/s", value: "\(engine.packetsPerSecond)", color: Theme.accent)
            Stat(label: "throughput", value: Format.rate(engine.bytesPerSecond))
            Stat(label: "total pkts", value: "\(engine.totalPackets)")
            Stat(label: "total data", value: Format.bytes(engine.totalBytes))

            Divider().overlay(Theme.stroke)

            ForEach(TransportProtocol.allCases, id: \.self) { proto in
                let count = engine.protocolCounts[proto] ?? 0
                ProtocolBar(proto: proto,
                            fraction: Double(count) / Double(protocolTotal),
                            count: count)
            }
        }
        .frame(width: 220)
        .panel()
    }
}

struct ProtocolBar: View {
    let proto: TransportProtocol
    let fraction: Double
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(proto.rawValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: proto.hex))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(Color(hex: proto.hex))
                        .frame(width: max(2, geo.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
    }
}

/// Most active remote peers.
struct TopTalkersPanel: View {
    let engine: TrafficEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP TALKERS")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .kerning(2)

            if engine.topTalkers.isEmpty {
                Text("listening…")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.dim)
            } else {
                ForEach(engine.topTalkers) { talker in
                    HStack(spacing: 8) {
                        Text(talker.geo.countryCode.flagEmoji.isEmpty ? "🛰️"
                             : talker.geo.countryCode.flagEmoji)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(talker.ip)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(talker.geo.label)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(Format.bytes(talker.bytes))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .frame(width: 240)
        .panel()
    }
}

/// Color legend for direction.
struct DirectionLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legendDot(Direction.outbound, "OUTBOUND")
            legendDot(Direction.inbound, "INBOUND")
            legendDot(Direction.local, "LOCAL")
        }
        .panel()
    }

    private func legendDot(_ dir: Direction, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color(hex: dir.hex)).frame(width: 8, height: 8)
                .shadow(color: Color(hex: dir.hex), radius: 4)
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.dim)
        }
    }
}
