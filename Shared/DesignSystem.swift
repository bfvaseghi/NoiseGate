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
// ivory chassis, ink instrument face, condensed readouts, and calibrated
// amber/teal meters, with red reserved for the over-budget state. Never use
// raw color literals in views — pull from these tokens so light/dark
// stay coherent everywhere.

enum NG {
    // Grounds
    static let paper   = Color(light: 0xEDEBE4, dark: 0x171918)
    static let card    = Color(light: 0xF5F3ED, dark: 0x202321)
    static let cardSoft = Color(light: 0xE2E0D8, dark: 0x2C302D)
    static let line    = Color(light: 0xC8C8BF, dark: 0x414842)
    // Ink
    static let ink     = Color(light: 0x252B27, dark: 0xEEEFE7)
    static let inkSoft = Color(light: 0x5A635C, dark: 0xADB7AC)
    static let onInk   = Color(light: 0xF5F3ED, dark: 0x171918)
    // The primary instrument stays dark in both appearances. Its own ink
    // and category colors must be used rather than the surrounding paper's.
    static let instrument = Color(light: 0x252C28, dark: 0x101512)
    static let instrumentInk = Color(light: 0xF3F0DF, dark: 0xF3F0DF)
    static let instrumentSoft = Color(light: 0xB5C0B2, dark: 0xB5C0B2)
    static let instrumentLine = Color(light: 0x495348, dark: 0x3A453A)
    static var instrumentAccent: Color { AccentTheme.current.instrumentColor }
    static let instrumentAlarm = Color(light: 0xFF9B87, dark: 0xFF9B87)
    static let brand = Color(light: 0xA7611A, dark: 0xE5AE55)
    // Voice
    static let alarm     = Color(light: 0xB52D24, dark: 0xFF8A7C)
    static let warning   = Color(light: 0x885C11, dark: 0xE4B963)
    static let alarmDeep = Color(light: 0x8E0E0C, dark: 0x7A0B09)
    // Categories. The Distractions accent is user-selectable; Messages and
    // focus stay fixed so the two ledgers never read as the same colour.
    static var distraction: Color { AccentTheme.current.color }
    static let msg   = Color(light: 0x146D69, dark: 0x70C9BE)
    static let focus = Color(light: 0x5B5BD6, dark: 0x8181E8)

    /// Primary-action fill (onboarding CTA).
    static var alarmGradient: LinearGradient {
        LinearGradient(colors: [alarm, alarmDeep],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// The signature progress arc: a thick track, an angular-gradient sweep, and
/// an endpoint dot so it reads as a needle rather than a donut. Defined once
/// here because both the in-app gauge and the widgets draw it.
struct RingArc: View {
    let fraction: Double
    let color: Color
    let size: CGFloat
    /// Drawn hollow when there is nothing to report yet, so an empty ring is
    /// never mistaken for a zero measurement.
    var isIndeterminate: Bool = false

    private var stroke: CGFloat { max(6, size * 0.105) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            if isIndeterminate {
                Circle()
                    .stroke(
                        color.opacity(0.4),
                        style: StrokeStyle(
                            lineWidth: max(1.5, stroke * 0.28),
                            lineCap: .round,
                            dash: [1, max(4, stroke * 0.62)]
                        )
                    )
            } else {
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.55), color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if fraction > 0.03 {
                    Circle()
                        .fill(color)
                        .frame(width: stroke * 0.5, height: stroke * 0.5)
                        .offset(y: -size / 2 + stroke / 2)
                        .rotationEffect(.degrees(360 * min(1, fraction)))
                }
            }
        }
        .frame(width: size, height: size)
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
    /// Display face: condensed black caps for screen titles.
    static func ngDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }

    /// Condensed instrument numerals. The caller scales display values.
    static func ngNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).width(.condensed)
    }

    static func ngScreenTitle(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold).width(.condensed)
    }

    static func ngMono(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    /// Small caps labels (pair with `.tracking(2)` and uppercased text).
    static func ngLabel(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold)
    }
}

// MARK: - Components

/// Flush chassis sections share a ruled edge rather than floating card chrome.
struct NGCardStyle: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(NG.card)
            .overlay(alignment: .top) { Rectangle().fill(NG.line).frame(height: 1) }
    }
}

extension View {
    func ngCard(padding: CGFloat = 20) -> some View {
        modifier(NGCardStyle(padding: padding))
    }
}

/// The masthead is the same on the app and its smaller Mac instrument.
struct SignalHeader: View {
    let title: String
    var detail: String? = nil
    var badge: String? = nil
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(NG.brand)
                        .accessibilityHidden(true)
                    Text("NOISEGATE")
                        .font(.ngDisplay(21)).tracking(0.5)
                        .foregroundStyle(NG.ink)
                }
                Spacer()
                if let badge { Text(badge).font(.ngMono(10)) }
            }
            .foregroundStyle(NG.inkSoft)
            Rectangle().fill(NG.ink).frame(height: 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.ngScreenTitle(titleSize))
                    .foregroundStyle(NG.ink)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail)
                        .font(.ngMono())
                        .foregroundStyle(NG.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Unit letters stay subordinate to the measured time.
struct SignalTimeReadout: View {
    let minutes: Int
    let size: CGFloat

    private func number(_ value: Int) -> Text { Text("\(value)").font(.ngNumber(size)) }
    private func unit(_ label: String) -> Text { Text(label).font(.ngNumber(size * 0.43)) }

    private var reading: Text {
        let value = max(0, minutes)
        if value < 60 { return number(value) + unit("m") }
        let hours = number(value / 60) + unit("h")
        if value.isMultiple(of: 60) { return hours }
        return hours + Text(" ") + number(value % 60) + unit("m")
    }

    var body: some View {
        reading.tracking(size > 50 ? -2 : -0.5)
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
    }
}

/// Each segment encodes the same span. The last illuminated segment is
/// partially filled, so an exact report never rounds up to the next mark.
struct SignalSegments: View {
    let fraction: Double
    let tint: Color
    var track: Color = NG.line
    var height: CGFloat = 22
    var count: Int = 40

    var body: some View {
        Canvas { context, size in
            let total = max(1, count)
            let step = size.width / CGFloat(total)
            let width = max(0, step - min(3, step * 0.3))
            let fill = fraction.isFinite ? min(1, max(0, fraction)) : 0
            for index in 0..<total {
                let barHeight = index.isMultiple(of: 5) ? size.height : size.height * 0.72
                let rect = CGRect(x: CGFloat(index) * step, y: size.height - barHeight,
                                  width: width, height: barHeight)
                context.fill(Path(rect), with: .color(track))
                let part = min(1, max(0, fill * Double(total) - Double(index)))
                if part > 0 {
                    let active = CGRect(x: rect.minX, y: rect.minY,
                                        width: width * CGFloat(part), height: barHeight)
                    context.fill(Path(active), with: .color(tint))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct SignalMeter: View {
    let minutes: Int
    let budget: Int
    let tint: Color
    var inverted: Bool = false

    var body: some View {
        VStack(spacing: 7) {
            SignalSegments(fraction: Double(minutes) / Double(max(1, budget)), tint: tint,
                           track: inverted ? NG.instrumentLine : NG.line)
            HStack(alignment: .firstTextBaseline) {
                Text("0").frame(maxWidth: .infinity, alignment: .leading)
                Text("\((Double(budget) / 2).formatted(.number.precision(.fractionLength(0...1))))m")
                    .frame(maxWidth: .infinity)
                Text("\(budget.asHoursMinutes) target")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.ngMono(10))
            .foregroundStyle(inverted ? NG.instrumentSoft : NG.inkSoft)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily target")
        .accessibilityValue("\(minutes) of \(budget) minutes")
    }
}

struct SignalLabel: View {
    let title: String
    let tint: Color
    var foreground: Color = NG.ink

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(tint).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(title.uppercased()).font(.ngMono(11)).tracking(1).foregroundStyle(foreground)
        }
    }
}

/// Small caps chip in a category color.
struct NGChip: View {
    let text: String
    let tint: Color
    /// Chips are a saturated fill with white on top, which holds for every
    /// category colour. A chip tinted with `NG.ink` must pass `NG.paper`
    /// instead: ink is near-white in dark mode, and white on white is
    /// invisible.
    var foreground: Color = .white

    var body: some View {
        Text(text.uppercased())
            .font(.ngLabel(10))
            .tracking(1.5)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint, in: Capsule())
    }
}
