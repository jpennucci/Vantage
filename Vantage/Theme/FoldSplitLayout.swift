import SwiftUI

/// Two panes split at the fold of an unfolded iPhone Duo, along whichever way the fold
/// runs in the current orientation. Where there's no fold (iPad, older iOS) it splits
/// down the middle: top and bottom when the space is taller than it is wide, side by
/// side when it's wider — decided from the space it's given, never the device
/// orientation, per Apple's resizability guidance.
///
/// With `showsSecondary` off it's just the primary pane, inside the same container —
/// so folding or unfolding keeps the primary pane's identity (and the map's camera,
/// sheets and navigation state with it) instead of rebuilding it.
struct FoldSplitLayout<Primary: View, Secondary: View>: View {
    var showsSecondary: Bool
    /// When given, a chevron handle on the primary pane's inner edge hides the
    /// secondary pane (primary goes full screen) and brings it back.
    var isSecondaryCollapsed: Binding<Bool>? = nil
    @ViewBuilder var primary: Primary
    @ViewBuilder var secondary: Secondary

    var body: some View {
        GeometryReader { geometry in
            let split = Split(in: geometry)
            let layout = split.sideBySide
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            let collapsed = isSecondaryCollapsed?.wrappedValue ?? false
            let showsSecondary = showsSecondary && !collapsed
            layout {
                primary
                    .frame(
                        width: showsSecondary && split.sideBySide ? split.primaryLength : nil,
                        height: showsSecondary && !split.sideBySide ? split.primaryLength : nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: split.sideBySide ? .trailing : .bottom) {
                        if self.showsSecondary, let isSecondaryCollapsed {
                            CollapseHandle(sideBySide: split.sideBySide, isCollapsed: isSecondaryCollapsed)
                        }
                    }
                if showsSecondary {
                    if split.gap > 0 {
                        // Half-folded: keep content out of the crease itself.
                        Color.clear.frame(
                            width: split.sideBySide ? split.gap : nil,
                            height: split.sideBySide ? nil : split.gap
                        )
                    } else {
                        Divider()
                    }
                    secondary
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// A small tab on the primary pane's inner edge. The chevron points the way the
    /// secondary pane will move: away to hide it, back in to show it.
    private struct CollapseHandle: View {
        var sideBySide: Bool
        @Binding var isCollapsed: Bool

        var body: some View {
            Button {
                withAnimation(.easeInOut(duration: 0.3)) { isCollapsed.toggle() }
            } label: {
                Image(systemName: sideBySide
                      ? (isCollapsed ? "chevron.left" : "chevron.right")
                      : (isCollapsed ? "chevron.up" : "chevron.down"))
                    .font(.footnote.weight(.bold))
                    .frame(width: sideBySide ? 22 : 56, height: sideBySide ? 56 : 22)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(isCollapsed ? "Show Spots" : "Full Screen Map")
        }
    }

    /// Where the panes divide, in the GeometryReader's own coordinates.
    private struct Split {
        var sideBySide: Bool
        var primaryLength: CGFloat
        var gap: CGFloat = 0

        init(in geometry: GeometryProxy) {
            let size = geometry.size
            #if os(iOS)
            if #available(iOS 27.1, *),
               let fold = geometry.reservedRegions(kind: .division, options: .includeInactive).first {
                // A fold taller than it is wide runs top to bottom, so the halves sit
                // side by side; otherwise they stack.
                sideBySide = fold.frame.height > fold.frame.width
                let start = sideBySide ? fold.frame.minX : fold.frame.minY
                let end = sideBySide ? fold.frame.maxX : fold.frame.maxY
                let length = sideBySide ? size.width : size.height
                // Only use the fold if it actually crosses this view (it won't when the
                // view is a narrow window on one side of it).
                if start > 0, end < length {
                    if fold.isActive {
                        primaryLength = start
                        gap = end - start
                    } else {
                        primaryLength = (start + end) / 2
                    }
                    return
                }
            }
            #endif
            sideBySide = size.width > size.height
            primaryLength = (sideBySide ? size.width : size.height) / 2
        }
    }
}
