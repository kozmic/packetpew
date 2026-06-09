#if canImport(SceneKit)
import Foundation
import SceneKit
import simd

/// Builds and drives the SceneKit globe: dark sphere with a graticule and country
/// borders, great-circle arcs with animated "missiles" and impact flashes.
final class GlobeRenderer {

    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let radius: Double = 5.0
    private let globeNode = SCNNode()   // rotates; arcs are attached to this
    private let arcsNode = SCNNode()
    private var homeMarker: SCNNode?
    private let maxArcs = 56

    // Pre-generated glow textures.
    private lazy var whiteGlow = Self.glowImage(color: PlatformColor.white)

    init() {
        buildScene()
    }

    // MARK: - Construction

    private func buildScene() {
        scene.background.contents = PlatformColor(hex: 0x04070E)

        // Camera with bloom for the neon glow.
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.1
        camera.zFar = 500
        camera.wantsHDR = true
        camera.bloomIntensity = 1.3
        camera.bloomThreshold = 0.35
        camera.bloomBlurRadius = 10
        cameraNode.camera = camera
        cameraNode.position = GeoMath.scn(0, 0, radius * 3.0)
        scene.rootNode.addChildNode(cameraNode)

        // Lights: faint ambient + directional light for a soft terminator.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = PlatformColor(hex: 0x2A3D55)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = PlatformColor(hex: 0x9FC6FF)
        sun.position = GeoMath.scn(-8, 4, 8)
        sun.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sun)

        // Starfield.
        scene.rootNode.addChildNode(makeStars())

        // Atmosphere glow behind the globe.
        scene.rootNode.addChildNode(makeHalo())

        // The globe itself.
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 96
        let mat = SCNMaterial()
        mat.lightingModel = .blinn
        mat.diffuse.contents = PlatformColor(hex: 0x0A1B30)
        mat.specular.contents = PlatformColor(hex: 0x14365C)
        mat.shininess = 0.35
        mat.emission.contents = PlatformColor(hex: 0x040B16)
        sphere.firstMaterial = mat
        let sphereNode = SCNNode(geometry: sphere)
        globeNode.addChildNode(sphereNode)

        // Graticule (lat/long lines), landmasses and country dots.
        globeNode.addChildNode(makeGraticule())
        globeNode.addChildNode(makeLandmasses())
        globeNode.addChildNode(makeCountryDots())

        globeNode.addChildNode(arcsNode)
        scene.rootNode.addChildNode(globeNode)

        // Gentle rotation.
        let spin = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 120)
        )
        globeNode.runAction(spin)

        // Slight axial tilt for a nicer perspective.
        globeNode.eulerAngles = GeoMath.scn(0.35, 0, 0.0)
    }

    // MARK: - Stars / halo

    private func makeStars() -> SCNNode {
        var verts: [SCNVector3] = []
        for _ in 0..<450 {
            let u = Double.random(in: -1...1)
            let theta = Double.random(in: 0..<(2 * .pi))
            let r = sqrt(1 - u * u)
            let dir = SIMD3(r * cos(theta), u, r * sin(theta))
            verts.append(GeoMath.scn(dir * (radius * 9)))
        }
        let src = SCNGeometrySource(vertices: verts)
        let idx: [Int32] = Array(0..<Int32(verts.count))
        let elem = SCNGeometryElement(indices: idx, primitiveType: .point)
        elem.pointSize = 2.0
        elem.minimumPointScreenSpaceRadius = 1.0
        elem.maximumPointScreenSpaceRadius = 2.5
        let geo = SCNGeometry(sources: [src], elements: [elem])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = PlatformColor(white: 0.9, alpha: 1)
        m.emission.contents = PlatformColor(white: 0.9, alpha: 1)
        geo.firstMaterial = m
        return SCNNode(geometry: geo)
    }

    private func makeHalo() -> SCNNode {
        let plane = SCNPlane(width: CGFloat(radius * 3.0), height: CGFloat(radius * 3.0))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.glowImage(color: PlatformColor(hex: 0x2E6BFF))
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.position = GeoMath.scn(0, 0, -radius * 0.4)
        node.constraints = [SCNBillboardConstraint()]
        return node
    }

    // MARK: - Graticule, landmasses and country dots

    private func makeGraticule() -> SCNNode {
        var polylines: [[SIMD3<Double>]] = []
        // Meridians every 30°.
        for lonDeg in stride(from: -180.0, to: 180.0, by: 30.0) {
            var line: [SIMD3<Double>] = []
            for latDeg in stride(from: -90.0, through: 90.0, by: 5.0) {
                line.append(GeoMath.unitVector(latitude: latDeg, longitude: lonDeg) * (radius * 1.002))
            }
            polylines.append(line)
        }
        // Parallels every 30°.
        for latDeg in stride(from: -60.0, through: 60.0, by: 30.0) {
            var line: [SIMD3<Double>] = []
            for lonDeg in stride(from: -180.0, through: 180.0, by: 5.0) {
                line.append(GeoMath.unitVector(latitude: latDeg, longitude: lonDeg) * (radius * 1.002))
            }
            polylines.append(line)
        }
        let geo = Self.lineGeometry(polylines: polylines,
                                    color: PlatformColor(hex: 0x163D55), occludes: true)
        return SCNNode(geometry: geo)
    }

    /// Country borders / coastlines drawn as glowing vector lines on the sphere.
    private func makeLandmasses() -> SCNNode {
        let rings = WorldMap.rings
        guard !rings.isEmpty else { return SCNNode() }
        var polylines: [[SIMD3<Double>]] = []
        polylines.reserveCapacity(rings.count)
        for ring in rings {
            var line: [SIMD3<Double>] = []
            line.reserveCapacity(ring.count)
            for p in ring {
                line.append(GeoMath.unitVector(latitude: p.lat, longitude: p.lon) * (radius * 1.004))
            }
            if line.count >= 2 { polylines.append(line) }
        }
        let geo = Self.lineGeometry(polylines: polylines,
                                    color: PlatformColor(hex: 0x35E0C0), occludes: true)
        let node = SCNNode(geometry: geo)
        node.name = "landmasses"
        return node
    }

    private func makeCountryDots() -> SCNNode {
        var verts: [SCNVector3] = []
        for (_, c) in GeoData.countries {
            verts.append(GeoMath.scn(GeoMath.unitVector(latitude: c.lat, longitude: c.lon) * (radius * 1.01)))
        }
        let src = SCNGeometrySource(vertices: verts)
        let idx: [Int32] = Array(0..<Int32(verts.count))
        let elem = SCNGeometryElement(indices: idx, primitiveType: .point)
        elem.pointSize = 3.0
        elem.minimumPointScreenSpaceRadius = 1.5
        elem.maximumPointScreenSpaceRadius = 4.0
        let geo = SCNGeometry(sources: [src], elements: [elem])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = PlatformColor(hex: 0x1CA88E)
        m.emission.contents = PlatformColor(hex: 0x1CA88E)
        m.readsFromDepthBuffer = true
        m.writesToDepthBuffer = false
        geo.firstMaterial = m
        return SCNNode(geometry: geo)
    }

    // MARK: - Firing an event

    func updateHome(_ geo: GeoPoint) {
        homeMarker?.removeFromParentNode()
        let dir = GeoMath.unitVector(latitude: geo.latitude, longitude: geo.longitude)
        let node = SCNNode(geometry: SCNSphere(radius: 0.09))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = PlatformColor(hex: 0xFFD23F)
        m.emission.contents = PlatformColor(hex: 0xFFD23F)
        node.geometry?.firstMaterial = m
        node.position = GeoMath.scn(dir * (radius * 1.01))
        // Pulsing ring.
        let pulse = SCNAction.repeatForever(.sequence([
            .scale(to: 1.6, duration: 0.9), .scale(to: 1.0, duration: 0.9)
        ]))
        node.runAction(pulse)
        globeNode.addChildNode(node)
        homeMarker = node
    }

    func fire(_ event: NetworkEvent) {
        // Cap the number of concurrent arcs.
        if arcsNode.childNodes.count > maxArcs {
            arcsNode.childNodes.first?.removeFromParentNode()
        }

        let a = GeoMath.unitVector(latitude: event.source.latitude, longitude: event.source.longitude)
        let b = GeoMath.unitVector(latitude: event.destination.latitude, longitude: event.destination.longitude)
        // Avoid degenerate arcs (same point).
        guard simd_length(a - b) > 1e-4 else { return }

        let pts = GeoMath.arc(from: a, to: b, radius: radius, segments: 56)
        let color = PlatformColor(hex: event.direction.hex)

        let arcNode = SCNNode()
        arcsNode.addChildNode(arcNode)

        // The trajectory (faint line).
        let lineGeo = Self.lineGeometry(polylines: [pts], color: color, occludes: true)
        let lineNode = SCNNode(geometry: lineGeo)
        lineNode.opacity = 0.5
        arcNode.addChildNode(lineNode)

        // The missile.
        let missile = SCNNode(geometry: SCNSphere(radius: 0.075))
        let mm = SCNMaterial()
        mm.lightingModel = .constant
        mm.diffuse.contents = color
        mm.emission.contents = color
        mm.readsFromDepthBuffer = true
        mm.writesToDepthBuffer = false
        missile.geometry?.firstMaterial = mm
        missile.position = GeoMath.scn(pts.first ?? SIMD3(0, 0, 0))
        arcNode.addChildNode(missile)

        // Exhaust trail.
        let trail = SCNParticleSystem()
        trail.birthRate = 70
        trail.particleLifeSpan = 0.45
        trail.particleSize = 0.05
        trail.particleColor = color
        trail.spreadingAngle = 8
        trail.particleVelocity = 0.15
        trail.isAffectedByGravity = false
        trail.blendMode = .additive
        trail.isLocal = false
        missile.addParticleSystem(trail)

        let travel = 1.1 + simd_length(a - b) * 0.5
        let move = SCNAction.customAction(duration: travel) { [pts] node, elapsed in
            let t = travel > 0 ? Double(elapsed) / travel : 1.0
            node.position = GeoMath.scn(GeoMath.sample(pts, at: t))
        }
        let detonate = SCNAction.run { [weak self] _ in
            guard let self, let last = pts.last else { return }
            self.spawnImpact(at: last, color: color, on: arcNode)
        }
        missile.runAction(.sequence([move, detonate, .removeFromParentNode()]))

        // Clean up the whole arc afterwards.
        arcNode.runAction(.sequence([
            .wait(duration: travel + 0.7),
            .fadeOut(duration: 0.6),
            .removeFromParentNode()
        ]))
    }

    private func spawnImpact(at point: SIMD3<Double>, color: PlatformColor, on parent: SCNNode) {
        let plane = SCNPlane(width: 0.3, height: 0.3)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.glowImage(color: color)
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        plane.firstMaterial = m
        let node = SCNNode(geometry: plane)
        node.position = GeoMath.scn(point)
        node.constraints = [SCNBillboardConstraint()]
        parent.addChildNode(node)

        node.runAction(.sequence([
            .group([
                .scale(to: 5.0, duration: 0.6),
                .fadeOut(duration: 0.6)
            ]),
            .removeFromParentNode()
        ]))
    }

    // MARK: - Geometry helpers

    /// Build one line geometry from several polylines (line-segment pairs).
    static func lineGeometry(polylines: [[SIMD3<Double>]], color: PlatformColor, occludes: Bool) -> SCNGeometry {
        var verts: [SCNVector3] = []
        var indices: [Int32] = []
        for line in polylines {
            let base = Int32(verts.count)
            for p in line { verts.append(GeoMath.scn(p)) }
            for i in 0..<(line.count - 1) {
                indices.append(base + Int32(i))
                indices.append(base + Int32(i + 1))
            }
        }
        let src = SCNGeometrySource(vertices: verts)
        let elem = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geo = SCNGeometry(sources: [src], elements: [elem])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = occludes
        geo.firstMaterial = m
        return geo
    }

    /// Radial glow (white → transparent), tinted with the given color.
    static func glowImage(color: PlatformColor, diameter: Int = 128) -> CGImage? {
        #if os(macOS)
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let comps = rgb.cgColor.components ?? [1, 1, 1, 1]
        #else
        let comps = color.cgColor.components ?? [1, 1, 1, 1]
        #endif
        let r = comps.count > 0 ? comps[0] : 1
        let g = comps.count > 1 ? comps[1] : 1
        let b = comps.count > 2 ? comps[2] : 1

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: diameter, height: diameter,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let colors = [
            CGColor(colorSpace: cs, components: [r, g, b, 1.0])!,
            CGColor(colorSpace: cs, components: [r, g, b, 0.0])!
        ] as CFArray
        guard let grad = CGGradient(colorsSpace: cs, colors: colors,
                                    locations: [0.0, 1.0]) else { return nil }
        let c = CGPoint(x: diameter / 2, y: diameter / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                               endCenter: c, endRadius: CGFloat(diameter) / 2, options: [])
        return ctx.makeImage()
    }
}
#endif
