import Foundation
import simd
#if canImport(SceneKit)
import SceneKit
#endif

/// Collection of pure math helpers for the globe view.
public enum GeoMath {

    /// Convert (latitude, longitude) to a unit vector on the sphere.
    /// Y is the north/south axis. The orientation is consistent, but arbitrary
    /// relative to any texture mapping (we don't use an Earth texture by default).
    public static func unitVector(latitude: Double, longitude: Double) -> SIMD3<Double> {
        let lat = latitude * .pi / 180.0
        let lon = longitude * .pi / 180.0
        let x = cos(lat) * cos(lon)
        let y = sin(lat)
        let z = -cos(lat) * sin(lon)
        return SIMD3(x, y, z)
    }

    /// Points along a great-circle arc between two directions, lifted above the
    /// surface by a height proportional to the distance (longer arcs lob higher).
    public static func arc(
        from a: SIMD3<Double>,
        to b: SIMD3<Double>,
        radius: Double,
        segments: Int = 64
    ) -> [SIMD3<Double>] {
        let na = simd_normalize(a)
        let nb = simd_normalize(b)
        let dot = max(-1.0, min(1.0, simd_dot(na, nb)))
        let omega = acos(dot)
        let sinOmega = sin(omega)

        // How high the arc rises: ~0 for neighboring points, up to 0.45·radius for antipodes.
        let maxLift = (omega / .pi) * 0.45

        var points: [SIMD3<Double>] = []
        points.reserveCapacity(segments + 1)
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let p: SIMD3<Double>
            if sinOmega < 1e-6 {
                p = na
            } else {
                let s0 = sin((1.0 - t) * omega) / sinOmega
                let s1 = sin(t * omega) / sinOmega
                p = s0 * na + s1 * nb
            }
            let lift = sin(t * .pi) * maxLift            // 0 → peak → 0
            let r = radius * (1.0 + lift)
            points.append(simd_normalize(p) * r)
        }
        return points
    }

    /// Linear sampling along a list of points, t in [0, 1].
    public static func sample(_ points: [SIMD3<Double>], at t: Double) -> SIMD3<Double> {
        guard points.count > 1 else { return points.first ?? SIMD3(0, 0, 0) }
        let clamped = max(0.0, min(1.0, t))
        let scaled = clamped * Double(points.count - 1)
        let i = Int(scaled)
        if i >= points.count - 1 { return points[points.count - 1] }
        let frac = scaled - Double(i)
        return simd_mix(points[i], points[i + 1], SIMD3(repeating: frac))
    }
}

#if canImport(SceneKit)
public extension GeoMath {
    /// SIMD3<Double> → SCNVector3 (the component type differs between macOS/iOS).
    static func scn(_ v: SIMD3<Double>) -> SCNVector3 {
        #if os(macOS)
        return SCNVector3(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z))
        #else
        return SCNVector3(Float(v.x), Float(v.y), Float(v.z))
        #endif
    }

    static func scn(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
        scn(SIMD3(x, y, z))
    }
}
#endif
