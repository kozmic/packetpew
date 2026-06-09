import SwiftUI

// Thin aliases so the rest of the code avoids #if spaghetti for AppKit/UIKit.
#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformView = NSView
#else
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformView = UIView
#endif

extension Color {
    /// Build a SwiftUI color from hex (0xRRGGBB).
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension PlatformColor {
    /// Build a platform color (NSColor/UIColor) from hex.
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
