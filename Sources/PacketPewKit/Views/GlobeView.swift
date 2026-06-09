#if canImport(SceneKit)
import SwiftUI
import SceneKit
import Combine

/// SwiftUI wrapper around the SceneKit globe.
struct GlobeView: View {
    let engine: TrafficEngine
    var body: some View {
        GlobeRepresentable(engine: engine)
            .ignoresSafeArea()
    }
}

/// Shared coordinator: owns the renderer and subscribes to the event stream.
@MainActor
final class GlobeCoordinator {
    let engine: TrafficEngine
    let renderer = GlobeRenderer()
    private var cancellable: AnyCancellable?

    init(engine: TrafficEngine) {
        self.engine = engine
    }

    func makeView() -> SCNView {
        let view = SCNView()
        view.scene = renderer.scene
        view.pointOfView = renderer.cameraNode
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.backgroundColor = PlatformColor(hex: 0x04070E)
        view.antialiasingMode = .multisampling4X
        view.rendersContinuously = true
        view.isPlaying = true
        view.preferredFramesPerSecond = 60

        // Delivered on RunLoop.main, so we can safely assume main isolation.
        cancellable = engine.pulse
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                MainActor.assumeIsolated {
                    self?.renderer.fire(event)
                }
            }
        return view
    }
}

#if os(macOS)
struct GlobeRepresentable: NSViewRepresentable {
    let engine: TrafficEngine

    func makeCoordinator() -> GlobeCoordinator { GlobeCoordinator(engine: engine) }

    func makeNSView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        // Reads homeGeo so the marker updates once our own position is found.
        context.coordinator.renderer.updateHome(engine.homeGeo)
    }
}
#else
struct GlobeRepresentable: UIViewRepresentable {
    let engine: TrafficEngine

    func makeCoordinator() -> GlobeCoordinator { GlobeCoordinator(engine: engine) }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.makeView()
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.renderer.updateHome(engine.homeGeo)
    }
}
#endif
#endif
