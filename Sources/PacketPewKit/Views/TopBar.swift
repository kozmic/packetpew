import SwiftUI

/// Top bar: title, mode picker (the two visualizations) and live/demo status.
struct TopBar: View {
    @Bindable var engine: TrafficEngine

    var body: some View {
        HStack(spacing: 16) {
            // Branding
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent, radius: 6)
                Text("PACKET PEW")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .kerning(3)
                    .foregroundStyle(.white)
            }

            Spacer()

            // Mode switch
            Picker("Mode", selection: $engine.mode) {
                ForEach(VizMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Spacer()

            // Pause/play
            Button { engine.togglePause() } label: {
                Image(systemName: engine.paused ? "play.fill" : "pause.fill")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help(engine.paused ? "Resume" : "Pause")

            // Status indicator
            HStack(spacing: 7) {
                Circle()
                    .fill(engine.isLive ? Color(hex: 0xFF2D6B) : Theme.accent)
                    .frame(width: 9, height: 9)
                    .shadow(color: engine.isLive ? Color(hex: 0xFF2D6B) : Theme.accent, radius: 5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(engine.isLive ? "LIVE" : "DEMO")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(engine.isLive ? Color(hex: 0xFF2D6B) : Theme.accent)
                    Text(engine.sourceLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(Color(hex: 0x05090F, opacity: 0.85))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.stroke).frame(height: 1)
                }
        )
    }
}
