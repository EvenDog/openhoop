// The 3C "guided warm craft" look: every interface color and font lives here, so panels never hard-code them.
// Each color has a light value (linen and denim) and a dark value (the "Evening" walnut variant);
// macOS picks the right one automatically whenever the system appearance changes.
import AppKit
import SwiftUI

enum Theme {
    // Surfaces
    static let ground = adaptive(light: 0xF4EDE1, dark: 0x1F1A16)         // window background behind cards
    static let card = adaptive(light: 0xFFFDF8, dark: 0x2A231E)           // panels, toolbars, cards
    static let cardBorder = adaptive(light: 0xE2D6C3, dark: 0x3A3029)     // outline around cards
    static let divider = adaptive(light: 0xEDE3D3, dark: 0x3A3029)        // soft lines inside cards
    static let controlBorder = adaptive(light: 0xDCCDB6, dark: 0x43382F)  // outline around buttons and fields
    static let edge = adaptive(light: 0xD9C7A8, dark: 0x3A3029)           // the line under the docked tool strip

    // Text
    static let ink = adaptive(light: 0x2E2520, dark: 0xF2E9DC)            // main text
    static let inkSecondary = adaptive(light: 0x6B5A4C, dark: 0xBFAE9A)   // captions and hints (4.5:1 contrast on cards)

    // Accents
    static let accent = adaptive(light: 0x34507A, dark: 0x9DB7DE)         // denim: active tool, selection, toggles
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x14202F)       // text drawn on top of the accent
    static let accentSoft = adaptive(light: 0xEEF1F6, dark: 0x2C3440)     // tinted background for selected rows
    static let primaryAction = adaptive(light: 0xB0532F, dark: 0xD7774F)  // terracotta: "Save for machine"
    static let onPrimaryAction = adaptive(light: 0xFFFFFF, dark: 0x1F1A16)
    static let success = adaptive(light: 0x2F5A2B, dark: 0x9FD0A8)        // "fits the hoop" checks

    // Fonts: New York (Apple's built-in serif) for headings, SF Rounded for everything else.
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static let caption = Font.system(size: 10, weight: .bold, design: .rounded)   // small uppercase group labels

    /// Makes a SwiftUI color that switches between two hex values (written as 0xRRGGBB) with light and dark mode.
    private static func adaptive(light: Int, dark: Int) -> Color { Color(nsColor: nsAdaptive(light: light, dark: dark)) }
    /// The AppKit version of `adaptive`, for code that draws directly (the canvas).
    static func nsAdaptive(light: Int, dark: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            // bestMatch tells us whether the view asking for the color is currently drawn light or dark.
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light).withAlphaComponent(alpha)
        }
    }
    /// A fixed (not light/dark adaptive) color from 0xRRGGBB, for colors the person picks.
    static func fixed(_ hex: Int) -> NSColor { rgb(hex) }
    /// The 0xRRGGBB value of a picked SwiftUI color.
    static func hex(of color: Color) -> Int {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return 0 }
        return (Int((c.redComponent * 255).rounded()) << 16) | (Int((c.greenComponent * 255).rounded()) << 8) | Int((c.blueComponent * 255).rounded())
    }
    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    /// Colors for the design canvas: linen fabric stretched in a wooden hoop, on the linen work surface.
    enum Canvas {
        static let pasteboard = nsAdaptive(light: 0xF4EDE1, dark: 0x1F1A16)   // the surface around the hoop
        static let fabric = nsAdaptive(light: 0xEFE6D4, dark: 0x2C2824)       // cloth inside the hoop
        static let weave = nsAdaptive(light: 0xE2D5BE, dark: 0x36312B)        // faint threads of the cloth
        static let wood = nsAdaptive(light: 0xCFA36D, dark: 0x8A6640)         // hoop ring
        static let woodEdge = nsAdaptive(light: 0xB88A54, dark: 0x6E5032)     // inner rim of the ring
        static let clasp = nsAdaptive(light: 0x9C7444, dark: 0x5E4329)        // tightening clasp at the top
        static let sewingArea = nsAdaptive(light: 0xB9A384, dark: 0x5A4C40)   // dashed outline of where stitches may go
        static let grid = nsAdaptive(light: 0x9A7B55, dark: 0xF2E9DC, alpha: 0.16)
        static let ruler = nsAdaptive(light: 0xFFFDF8, dark: 0x2A231E)
        static let label = nsAdaptive(light: 0x6B5A4C, dark: 0xBFAE9A)
        static let jump = nsAdaptive(light: 0x34507A, dark: 0x9DB7DE, alpha: 0.35)  // travel moves between parts
        static let needle = nsAdaptive(light: 0x2E2520, dark: 0xF2E9DC, alpha: 0.5)
        static let handle = nsAdaptive(light: 0x34507A, dark: 0x9DB7DE)               // Bézier handle arms and knobs
        static let entry = nsAdaptive(light: 0x2F6B4F, dark: 0x9FD0A8)                // object start marker
        static let exit = nsAdaptive(light: 0xB0532F, dark: 0xD7774F)                 // object end marker
        static let selection = nsAdaptive(light: 0x2E2520, dark: 0xF2E9DC)            // dotted outline of selected objects
    }
}

/// Rounded 3C buttons. `prominent` fills the button with the accent color for the main action in a group.
struct ThemedButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        ThemedButtonLabel(configuration: configuration, prominent: prominent)
    }
    // A separate view is needed to read whether the button is enabled (button styles can't read it directly).
    private struct ThemedButtonLabel: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize   // .small in the Pro view's panels
        var body: some View {
            let small = controlSize == .small || controlSize == .mini
            configuration.label
                .font(Theme.body(small ? 11 : 12, weight: .semibold))
                .padding(.horizontal, small ? 8 : 12).frame(minHeight: small ? 22 : 28)
                .background(prominent ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: small ? 6 : 9))
                .overlay(RoundedRectangle(cornerRadius: small ? 6 : 9).strokeBorder(prominent ? Color.clear : Theme.controlBorder))
                .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
                .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
        }
    }
}

extension View {
    /// Wraps a side panel's content in a rounded card sitting on the linen background, as in the 3C mockups.
    func themedPanelCard() -> some View {
        self.padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.cardBorder))
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ground)
    }
}
