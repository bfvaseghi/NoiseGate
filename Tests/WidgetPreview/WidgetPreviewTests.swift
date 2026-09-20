import XCTest
import SwiftUI
import WidgetKit

/// Renders the widget at every family it supports, in light and dark, to PNG
/// files, so the widget can be looked at without a device: the CI job uploads
/// the folder as an artifact. The widget's own file supplies
/// `WidgetPreviewCatalog` under `#if WIDGET_PREVIEW` (the scenes to draw, the
/// families, the container background and margins the system would apply).
/// This file is shared between the apps verbatim.
///
/// Outside WidgetKit `containerBackground(for: .widget)` draws nothing and
/// `ContainerRelativeShape` is a plain rectangle, so the frame below paints
/// the background and the rounded corners itself, at iPhone 15/16 Pro sizes.
@MainActor
final class WidgetPreviewTests: XCTestCase {
    func testRenderEveryFamily() throws {
        let env = ProcessInfo.processInfo.environment
        let requested = env["WIDGET_PREVIEW_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let dir = Self.writableDirectory(preferring: requested)
        var written: [String] = []
        for scene in WidgetPreviewCatalog.scenes {
            for family in WidgetPreviewCatalog.families {
                for dark in [false, true] {
                    let frame = WidgetPreviewFrame(family: family, dark: dark) { scene.view(family) }
                    let renderer = ImageRenderer(content: frame)
                    renderer.scale = 3
                    renderer.proposedSize = ProposedViewSize(WidgetPreviewGeometry.size(of: family))
                    guard let image = renderer.uiImage, let png = image.pngData() else {
                        XCTFail("No image for \(scene.name) \(family)")
                        continue
                    }
                    let name = "\(WidgetPreviewCatalog.app)--\(scene.name)--\(WidgetPreviewGeometry.slug(family))--\(dark ? "dark" : "light").png"
                    // The result bundle is the channel that always reaches the
                    // host (xcresulttool export attachments); the file on disk
                    // is a convenience when the folder happens to be reachable.
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    try png.write(to: dir.appendingPathComponent(name), options: .atomic)
                    written.append(name)
                }
            }
        }
        // The CI job reads this line to find the files.
        print("WIDGET_PREVIEWS \(written.count) files in \(dir.path)")
        XCTAssertFalse(written.isEmpty, "The catalog has no scenes")
    }

    /// The requested folder when it can be created and written, else the
    /// simulator's temporary folder (always writable).
    private static func writableDirectory(preferring requested: URL?) -> URL {
        let fm = FileManager.default
        for candidate in [requested, URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)].compactMap({ $0 }) {
            let dir = candidate.appendingPathComponent("widget-previews", isDirectory: true)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let probe = dir.appendingPathComponent(".probe")
                try Data().write(to: probe)
                try? fm.removeItem(at: probe)
                return dir
            } catch { continue }
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}

/// Sizes and names per family (kept off the generic frame so callers need no
/// type argument).
enum WidgetPreviewGeometry {
    /// Points, as WidgetKit lays them out on a 393 x 852 iPhone (15 Pro, 16 Pro).
    static func size(of family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: return CGSize(width: 158, height: 158)
        case .systemMedium: return CGSize(width: 338, height: 158)
        case .systemLarge: return CGSize(width: 338, height: 354)
        case .systemExtraLarge: return CGSize(width: 715, height: 354)
        case .accessoryCircular: return CGSize(width: 72, height: 72)
        case .accessoryRectangular: return CGSize(width: 172, height: 76)
        case .accessoryInline: return CGSize(width: 234, height: 26)
        @unknown default: return CGSize(width: 158, height: 158)
        }
    }

    static func slug(_ family: WidgetFamily) -> String {
        switch family {
        case .systemSmall: return "small"
        case .systemMedium: return "medium"
        case .systemLarge: return "large"
        case .systemExtraLarge: return "extra-large"
        case .accessoryCircular: return "lock-circular"
        case .accessoryRectangular: return "lock-rectangular"
        case .accessoryInline: return "lock-inline"
        @unknown default: return "unknown"
        }
    }

    static func isAccessory(_ family: WidgetFamily) -> Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }
}

/// The system's frame around a widget: its size for the family, the container
/// background, the content margins and the rounded corners.
struct WidgetPreviewFrame<Content: View>: View {
    let family: WidgetFamily
    let dark: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        let size = WidgetPreviewGeometry.size(of: family)
        let accessory = WidgetPreviewGeometry.isAccessory(family)
        // Lock Screen widgets are drawn by the system in vibrant monochrome on
        // the wallpaper; a translucent dark plate is the closest stand-in.
        let background: Color = accessory ? Color(white: 0.18) : WidgetPreviewCatalog.background(dark: dark)
        let radius: CGFloat = family == .accessoryCircular ? size.width / 2 : (accessory ? 14 : 22)
        content()
            .padding(WidgetPreviewCatalog.contentMargins(for: family))
            .frame(width: size.width, height: size.height)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .environment(\.colorScheme, (dark || accessory) ? .dark : .light)
    }
}
