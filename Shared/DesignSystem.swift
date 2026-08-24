import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias NativeColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias NativeColor = NSColor
#endif

// MARK: - NG: the NoiseGate design system
//
// One visual world across iPhone, iPad, Mac, widgets, and extensions:
// alarm-poster red on warm paper, condensed-black display type, hazard
// stripes for the over-budget state. Never use raw color literals in
// views — pull from these tokens so light/dark stay coherent everywhere.

enum NG {
    // Grounds
    static let paper   = Color(light: 0xFAF6F3, dark: 0x17090B)
    static let card    = Color(light: 0xFFFFFF, dark: 0x241214)
    static let line    = Color(light: 0xE8DCD8, dark: 0x3B2426)
    // Ink
    static let ink     = Color(light: 0x1C0D0F, dark: 0xF5EAE7)
    static let inkSoft = Color(light: 0x6E5A5C, dark: 0xB39A96)
    // Voice
    static let alarm     = Color(light: 0xE0231E, dark: 0xF23B33)
    static let alarmDeep = Color(light: 0x8E0E0C, dark: 0x7A0B09)
    // Categories
    static let noise = Color(light: 0xE07C0E, dark: 0xF59A2E)
    static let msg   = Color(light: 0x18988F, dark: 0x2BB3A9)
    static let focus = Color(light: 0x5B5BD6, dark: 0x8181E8)

    /// The red slab used for shields, slams, and over-budget states.
    static var alarmGradient: LinearGradient {
        LinearGradient(colors: [alarm, alarmDeep],
                       startPoint: .top, endPoint: .bottom)
    }

    static var overBannerGradient: LinearGradient {
        LinearGradient(colors: [alarm, noise],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var focusGradient: LinearGradient {
        LinearGradient(colors: [focus, Color(light: 0x3D3DAF, dark: 0x5555C8)],
                       startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    /// Adaptive color from light/dark hex values (0xRRGGBB).
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark) : UIColor(hex: light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(hex: dark) : NSColor(hex: light)
        }))
        #endif
    }
}

private extension NativeColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography

extension Font {
    /// Poster voice: condensed black caps, the "STOP." face.
    static func ngDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }

    /// Numerals: heavy rounded, used for every time readout.
    static func ngNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Small caps labels (pair with `.tracking(2)` and uppercased text).
    static func ngLabel(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold)
    }
}

// MARK: - Components

/// Diagonal hazard stripes — the texture of the over-budget world.
struct HazardStripes: View {
    var color: Color = .white
    var opacity: Double = 0.12
    var lineWidth: CGFloat = 10
    var gap: CGFloat = 20

    var body: some View {
        Canvas { context, size in
            let step = lineWidth + gap
            var x = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color.opacity(opacity)),
                               lineWidth: lineWidth)
                x += step
            }
        }
        .allowsHitTesting(false)
    }
}

/// Standard NoiseGate card surface.
struct NGCardStyle: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(NG.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(NG.line, lineWidth: 1)
            )
            .shadow(color: NG.ink.opacity(0.07), radius: 16, y: 8)
    }
}

extension View {
    func ngCard(padding: CGFloat = 20) -> some View {
        modifier(NGCardStyle(padding: padding))
    }
}

/// Poster-style screen header: red eyebrow, giant condensed title.
struct PosterHeader: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.ngLabel(12))
                .tracking(2.5)
                .foregroundStyle(NG.alarm)
            Text(title)
                .font(.ngDisplay(46))
                .foregroundStyle(NG.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small caps chip in a category color.
struct NGChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.ngLabel(10))
            .tracking(1.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint, in: Capsule())
    }
}
