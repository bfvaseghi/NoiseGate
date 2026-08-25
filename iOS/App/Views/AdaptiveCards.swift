import SwiftUI

/// One column on iPhone, two on iPad. The cards themselves are identical
/// either way — only the container changes — so there is no second layout to
/// keep in sync. Lives in the iOS app target because `horizontalSizeClass`
/// does not exist on macOS, where `Shared/` also compiles.
struct AdaptiveCards<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    var spacing: CGFloat = 18
    @ViewBuilder var content: Content

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: spacing, alignment: .top),
            GridItem(.flexible(), spacing: spacing, alignment: .top),
        ]
    }

    var body: some View {
        if sizeClass == .regular {
            LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
                content
            }
        } else {
            VStack(spacing: spacing) { content }
        }
    }
}

extension View {
    /// The reading width for a scrolling column of cards. iPad gets a wider
    /// measure because it is showing two columns inside it.
    func ngReadingWidth(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        frame(maxWidth: sizeClass == .regular ? 940 : 560)
            .frame(maxWidth: .infinity)
    }
}
