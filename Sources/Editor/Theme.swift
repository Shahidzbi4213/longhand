import AppKit
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case write, split, preview
    var id: String { rawValue }
    var title: String {
        switch self {
        case .write: return "Write"
        case .split: return "Split"
        case .preview: return "Preview"
        }
    }
    var symbol: String {
        switch self {
        case .write: return "pencil.line"
        case .split: return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }
}

enum FontFamily: String, CaseIterable, Identifiable {
    case quattro, duo, iaMono, mono, sans, lato, serif, charter, georgia
    var id: String { rawValue }

    var title: String {
        switch self {
        case .quattro: return "Quattro"
        case .duo: return "Duo"
        case .iaMono: return "iA Mono"
        case .mono: return "SF Mono"
        case .sans: return "System"
        case .lato: return "Lato"
        case .serif: return "New York"
        case .charter: return "Charter"
        case .georgia: return "Georgia"
        }
    }

    /// Shown directly in the quiet bar; the rest live in the View menu and Settings.
    static let quickPicks: [FontFamily] = [.quattro, .duo, .mono, .lato, .serif, .charter]

    var isMonospaced: Bool { self == .mono || self == .iaMono }

    /// PostScript names for regular / bold / italic / bold-italic (bundled or system fonts).
    var postScriptNames: (regular: String, bold: String, italic: String, boldItalic: String)? {
        switch self {
        case .quattro: return ("iAWriterQuattroS-Regular", "iAWriterQuattroS-Bold", "iAWriterQuattroS-Italic", "iAWriterQuattroS-BoldItalic")
        case .duo: return ("iAWriterDuoS-Regular", "iAWriterDuoS-Bold", "iAWriterDuoS-Italic", "iAWriterDuoS-BoldItalic")
        case .iaMono: return ("iAWriterMonoS-Regular", "iAWriterMonoS-Bold", "iAWriterMonoS-Italic", "iAWriterMonoS-BoldItalic")
        case .lato: return ("Lato-Regular", "Lato-Bold", "Lato-Italic", "Lato-BoldItalic")
        case .charter: return ("Charter-Roman", "Charter-Bold", "Charter-Italic", "Charter-BoldItalic")
        case .georgia: return ("Georgia", "Georgia-Bold", "Georgia-Italic", "Georgia-BoldItalic")
        case .mono, .sans, .serif: return nil
        }
    }

    /// Bundled font files (for the preview's @font-face).
    var bundledFiles: [(file: String, weight: Int, italic: Bool)] {
        guard let ps = postScriptNames, self != .charter, self != .georgia else { return [] }
        return [(ps.regular, 400, false), (ps.bold, 700, false), (ps.italic, 400, true), (ps.boldItalic, 700, true)]
    }

    /// CSS font family used by the preview so it matches the editor.
    var cssStack: String {
        switch self {
        case .quattro: return "'lh-quattro', -apple-system, sans-serif"
        case .duo: return "'lh-duo', ui-monospace, monospace"
        case .iaMono: return "'lh-iamono', ui-monospace, monospace"
        case .mono: return "ui-monospace, 'SF Mono', Menlo, monospace"
        case .sans: return "-apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif"
        case .lato: return "'lh-lato', 'Helvetica Neue', sans-serif"
        case .serif: return "ui-serif, 'New York', Georgia, serif"
        case .charter: return "Charter, 'Iowan Old Style', Georgia, serif"
        case .georgia: return "Georgia, serif"
        }
    }

    /// @font-face rules pointing at the bundled files through the preview's local scheme.
    static func fontFaceCSS() -> String {
        guard let dir = Bundle.main.resourceURL else { return "" }
        var css = ""
        for family in allCases {
            for f in family.bundledFiles {
                let url = LocalFileSchemeHandler.url(for: dir.appendingPathComponent(f.file + ".ttf")).absoluteString
                css += "@font-face { font-family: 'lh-\(family.rawValue == "iaMono" ? "iamono" : family.rawValue)'; src: url('\(url)'); font-weight: \(f.weight); font-style: \(f.italic ? "italic" : "normal"); }\n"
            }
        }
        return css
    }

    /// Register bundled fonts for this process (call once at launch).
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}

enum LineWidth: String, CaseIterable, Identifiable {
    case narrow, medium, wide
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var points: CGFloat {
        switch self {
        case .narrow: return 580
        case .medium: return 700
        case .wide: return 880
        }
    }
}

/// Keys for @AppStorage, in one place.
enum Pref {
    static let viewMode = "viewMode"
    static let fontFamily = "fontFamily"
    static let fontSize = "fontSize"
    static let lineWidth = "lineWidth"
    static let focusMode = "focusMode"
    static let typewriter = "typewriter"
    static let hideSyntax = "hideSyntax"
    static let inlineImages = "inlineImages"
    static let showStatusBar = "showStatusBar"
    static let theme = "theme"
    static let keepLineBreaks = "keepLineBreaks"
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, paper, sepia, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        }
    }
    /// Forced window appearance (nil = follow macOS).
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        default: return NSAppearance(named: .aqua)
        }
    }
    var colors: ThemeColors {
        switch self {
        case .system, .light: return .light
        case .paper: return .paper
        case .sepia: return .sepia
        case .dark: return .dark
        }
    }
    /// Swatch for menus.
    var swatch: (bg: UInt32, fg: UInt32) {
        switch self {
        case .system: return (0xD0D0D0, 0x2A2A2A)
        default: return (colors.background, colors.text)
        }
    }
}

/// Raw palette per theme (sRGB hex).
struct ThemeColors {
    var background, text, heading, syntax, marker, dimmed, accent, link: UInt32
    var codeBackground, codeText, quote, placeholder, highlight, rule, blurbBackground: UInt32
    var sidebar: UInt32?

    /// iA Writer–style clean white.
    static let light = ThemeColors(
        background: 0xFBFBFA, text: 0x2A2A2A, heading: 0x111111, syntax: 0xBDBDB8, marker: 0x9A9A95,
        dimmed: 0xC9C9C4, accent: 0x0A9DFF, link: 0x1C76C9, codeBackground: 0xEFEFEC, codeText: 0x5B4A8A,
        quote: 0x6D6D68, placeholder: 0xFFE3A1, highlight: 0xFFF29A, rule: 0xE2E2DE, blurbBackground: 0xF3F3F0,
        sidebar: nil)

    /// Bright paper white with crisp ink; sidebar matches the page so the window reads as one sheet.
    static let paper = ThemeColors(
        background: 0xFFFFFF, text: 0x1E1E1E, heading: 0x000000, syntax: 0xC6C6C6, marker: 0x9A9A9A,
        dimmed: 0xD2D2D2, accent: 0x1F6FEB, link: 0x1F5FAF, codeBackground: 0xF4F4F4, codeText: 0x5A3E8A,
        quote: 0x666666, placeholder: 0xFFE08A, highlight: 0xFFF3A0, rule: 0xE6E6E6, blurbBackground: 0xF6F6F6,
        sidebar: 0xFFFFFF)

    /// Brownish book-app sepia (Apple Books / Kindle style).
    static let sepia = ThemeColors(
        background: 0xF4ECD8, text: 0x5B4636, heading: 0x3B2A1E, syntax: 0xC8B597, marker: 0x9F8A6C,
        dimmed: 0xD3C4A6, accent: 0xB0651E, link: 0x985A1F, codeBackground: 0xEADDBF, codeText: 0x7A4B2A,
        quote: 0x7E6852, placeholder: 0xE9C578, highlight: 0xEFD98A, rule: 0xDCCAA8, blurbBackground: 0xEDE2C8,
        sidebar: 0xEAE0C8)

    static let dark = ThemeColors(
        background: 0x1A1A1C, text: 0xD4D4D2, heading: 0xEDEDEB, syntax: 0x56565A, marker: 0x7A7A7E,
        dimmed: 0x4A4A4E, accent: 0x2BAAFF, link: 0x5AB0F5, codeBackground: 0x26262A, codeText: 0xC2B3F0,
        quote: 0x9A9A9E, placeholder: 0x5C4716, highlight: 0x5A5216, rule: 0x333336, blurbBackground: 0x222225,
        sidebar: nil)

    func css() -> String {
        func h(_ v: UInt32) -> String { String(format: "#%06X", v) }
        return """
        --bg: \(h(background)); --text: \(h(text)); --heading: \(h(heading)); --muted: \(h(marker));
        --rule: \(h(rule)); --link: \(h(link)); --code-bg: \(h(codeBackground)); --code: \(h(codeText));
        --placeholder: \(h(placeholder)); --mark: \(h(highlight)); --blurb-bg: \(h(blurbBackground));
        --accent: \(h(accent));
        """
    }
}

/// Colors for the current theme. `System` resolves light/dark dynamically.
enum Palette {
    static var theme: AppTheme = .system

    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    private static func color(_ kp: KeyPath<ThemeColors, UInt32>, _ alpha: CGFloat = 1) -> NSColor {
        if theme == .system {
            return dynamic(hex(ThemeColors.light[keyPath: kp], alpha), hex(ThemeColors.dark[keyPath: kp], alpha))
        }
        return hex(theme.colors[keyPath: kp], alpha)
    }

    static var background: NSColor { color(\.background) }
    static var text: NSColor { color(\.text) }
    static var heading: NSColor { color(\.heading) }
    static var syntax: NSColor { color(\.syntax) }
    static var marker: NSColor { color(\.marker) }
    static var dimmed: NSColor { color(\.dimmed) }
    static var accent: NSColor { color(\.accent) }
    static var link: NSColor { color(\.link) }
    static var codeBackground: NSColor { color(\.codeBackground) }
    static var codeText: NSColor { color(\.codeText) }
    static var quote: NSColor { color(\.quote) }
    static var placeholder: NSColor { color(\.placeholder) }
    static var highlight: NSColor { color(\.highlight) }
    static var selection: NSColor { color(\.accent, theme == .dark ? 0.30 : 0.22) }
    static var sidebar: NSColor? { theme.colors.sidebar.map { hex($0) } }
}

struct EditorConfig: Equatable {
    var theme: AppTheme = .system
    var family: FontFamily = .mono
    var fontSize: CGFloat = 16
    var lineWidth: LineWidth = .medium
    var hideSyntax = false         // true = hide markdown marks off the caret line (Typora-style)
    var inlineImages = true
    var focusMode = false
    var typewriter = false
    var scaleHeadings = true
}

/// Builds and caches fonts for the editor.
final class FontBook {
    /// A 13pt sample of a family, for menus.
    static func preview(_ family: FontFamily) -> NSFont {
        let b = FontBook()
        b.family = family
        return b.font(size: 13)
    }

    private var cache: [String: NSFont] = [:]
    var family: FontFamily = .quattro { didSet { if family != oldValue { cache.removeAll() } } }

    /// `mono: true` forces the code font (SF Mono) regardless of family.
    func font(size: CGFloat, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> NSFont {
        let key = "\(size)-\(bold)-\(italic)-\(mono)"
        if let f = cache[key] { return f }
        let weight: NSFont.Weight = bold ? .bold : .regular
        var font: NSFont
        if mono || family == .mono {
            font = .monospacedSystemFont(ofSize: size, weight: weight)
        } else if let ps = family.postScriptNames {
            let name = bold ? (italic ? ps.boldItalic : ps.bold) : (italic ? ps.italic : ps.regular)
            font = NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
            if italic && NSFont(name: name, size: size) != nil { cache[key] = font; return font }
        } else if family == .serif {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            font = base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        } else {
            font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        }
        if italic {
            let desc = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
            font = NSFont(descriptor: desc, size: size) ?? font
        }
        cache[key] = font
        return font
    }

    /// Add bold/italic to an existing font from this book.
    func adding(_ trait: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        let traits = font.fontDescriptor.symbolicTraits
        let bold = traits.contains(.bold) || trait.contains(.bold)
        let italic = traits.contains(.italic) || trait.contains(.italic)
        // Code spans use SF Mono; keep them mono unless the whole family is monospaced.
        let isCodeFont = font.familyName == NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).familyName
        let mono = isCodeFont && family != .mono
        return self.font(size: font.pointSize, bold: bold, italic: italic, mono: mono)
    }
}
