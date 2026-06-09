import SwiftUI

/// The app's root view. Owns the engine and switches between the two visualizations.
public struct RootView: View {
    @State private var engine = TrafficEngine()

    public init() {}

    public var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            // The visualization itself fills the whole surface.
            Group {
                switch engine.mode {
                case .globe:
                    GlobeView(engine: engine)
                case .radar:
                    RadarView(engine: engine)
                }
            }
            .ignoresSafeArea()

            // HUD layer on top.
            VStack(spacing: 0) {
                TopBar(engine: engine)
                Spacer()
                HStack(alignment: .bottom) {
                    StatsPanel(engine: engine)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        DirectionLegend()
                        TopTalkersPanel(engine: engine)
                    }
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .task { engine.start() }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }
}
