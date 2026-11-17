import AppKit

extension NSAttributedString.Key {
    /// Value: NSImage. Drawn below the line by MarkdownTextView.
    static let mdImage = NSAttributedString.Key("md.image")
    /// Value: true. Blockquote bar drawn by MarkdownTextView.
    static let mdQuote = NSAttributedString.Key("md.quote")
    /// Value: true. Horizontal rule drawn by MarkdownTextView.
    static let mdRule = NSAttributedString.Key("md.rule")
}

/// Live, line-based markdown styling for an NSTextStorage.
///
/// Styling is idempotent per line: restyling any range always produces the same result for the
/// same text + caret position, so callers can safely over-restyle.
final class MarkdownStyler {
    var config = EditorConfig() {
        didSet { fonts.family = config.family }
    }
    /// Folder of the current document, for resolving relative image paths.
    var baseDirectory: URL?
    /// Usable text width, for sizing inline images.
    var contentWidth: CGFloat = 640

    let fonts = FontBook()
    private(set) var codeBlocks: [NSRange] = []

    private let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    // MARK: Regexes

    private static func rx(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [])
    }

    private static let heading = rx(#"^(#{1,6})([ \t]+)(.*)$"#)
    private static let quote = rx(#"^([ \t]*>[ \t]?)+"#)
    private static let list = rx(#"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let rule = rx(#"^[ \t]{0,3}([-*_])([ \t]*\1){2,}[ \t]*$"#)
    private static let imageLine = rx(#"^[ \t]*!\[([^\]]*)\]\(([^)\s]+)(?:[ \t]+"[^"]*")?\)[ \t]*$"#)
    private static let table = rx(#"^[ \t]*\|"#)

    private static let codeSpan = rx(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)
    private static let inlineImage = rx(#"!\[([^\]]*)\]\(([^)]*)\)"#)
    private static let link = rx(#"(?<!!)\[([^\]]+)\]\(([^)]*)\)"#)
    private static let refLink = rx(#"(?<![!\]])\[([^\]]+)\]\[([^\]]*)\]"#)
    private static let autolink = rx(#"<(https?://[^>\s]+)>|(?<![(<\w])(https?://[^\s)<>\]]+)"#)
    private static let boldItalic = rx(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#)
    private static let bold = rx(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let italicStar = rx(#"(?<![*\w\\])(\*)(?=[^\s*])(.+?)(?<=[^\s*\\])(\*)(?!\*)"#)
    private static let italicUnderscore = rx(#"(?<![_\w\\])(_)(?=[^\s_])(.+?)(?<=[^\s_\\])(_)(?![_\w])"#)
    private static let strike = rx(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)
    private static let highlight = rx(#"(==)(?=\S)(.+?)(?<=\S)(==)"#)
    private static let footnote = rx(#"\[\^[^\]]+\]"#)
    private static let htmlComment = rx(#"<!--.*?-->"#)

    // MARK: Attributes

    private var bodyFont: NSFont { fonts.font(size: config.fontSize) }

    private func paragraphStyle(headIndent: CGFloat = 0, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0, multiple: CGFloat = 1.5) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = multiple
        p.headIndent = headIndent
        p.paragraphSpacingBefore = spacingBefore
        p.paragraphSpacing = spacingAfter
        return p
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        if config.plainText {
            // Slightly smaller than prose so typical code lines fit the column.
            return [.font: fonts.font(size: max(11, config.fontSize - 2), mono: true), .foregroundColor: Palette.text,
                    .paragraphStyle: paragraphStyle(multiple: 1.3)]
        }
        return [.font: bodyFont, .foregroundColor: Palette.text, .paragraphStyle: paragraphStyle()]
    }

    // MARK: Code blocks

    /// Recompute fenced code block ranges. Returns true if they changed.
    @discardableResult
    func updateCodeBlocks(in string: NSString) -> Bool {
        if config.plainText {
            defer { codeBlocks = [] }
            return !codeBlocks.isEmpty
        }
        var blocks: [NSRange] = []
        var openStart: Int?
        var fence = ""
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byLines) { sub, lineRange, _, _ in
            guard let sub else { return }
            let t = sub.trimmingCharacters(in: .whitespaces)
            if openStart == nil {
                if t.hasPrefix("```") || t.hasPrefix("~~~") {
                    openStart = lineRange.location
                    fence = String(t.prefix(3))
                }
            } else if t.hasPrefix(fence) && t.trimmingCharacters(in: CharacterSet(charactersIn: fence.first.map { String($0) } ?? "")).isEmpty {
                blocks.append(NSRange(location: openStart!, length: NSMaxRange(lineRange) - openStart!))
                openStart = nil
            }
        }
        if let s = openStart { blocks.append(NSRange(location: s, length: string.length - s)) }
        let changed = blocks != codeBlocks
        codeBlocks = blocks
        return changed
    }

    private func codeBlock(containing location: Int) -> NSRange? {
        codeBlocks.first { NSLocationInRange(location, $0) }
    }

    // MARK: Styling

    /// Style every line touching `requested`. `active` is the paragraph range holding the caret;
    /// syntax there stays visible in WYSIWYG mode. Caller manages begin/endEditing.
    func style(_ storage: NSTextStorage, in requested: NSRange, active: NSRange) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        let clamped = NSIntersectionRange(requested, NSRange(location: 0, length: ns.length))
        let range = ns.paragraphRange(for: NSRange(location: clamped.location, length: clamped.length))
        storage.setAttributes(baseAttributes, range: range)
        if config.plainText { return }

        ns.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosing, _ in
            let isActive: Bool = {
                if active.length == 0 { return active.location >= lineRange.location && active.location <= NSMaxRange(lineRange) }
                return NSIntersectionRange(enclosing, active).length > 0 || active.location == lineRange.location
            }()
            self.styleLine(storage, ns, lineRange: lineRange, enclosing: enclosing, active: isActive)
        }
    }

    private func styleLine(_ s: NSTextStorage, _ ns: NSString, lineRange: NSRange, enclosing: NSRange, active: Bool) {
        let hide = config.hideSyntax && !active
        let base = lineRange.location
        let line = ns.substring(with: lineRange) as NSString
        let full = NSRange(location: 0, length: line.length)
        func abs(_ r: NSRange) -> NSRange { NSRange(location: r.location + base, length: r.length) }

        // Fenced code
        if codeBlock(containing: lineRange.location) != nil {
            let mono = fonts.font(size: config.fontSize * 0.92, mono: true)
            s.addAttributes([.font: mono, .backgroundColor: Palette.codeBackground, .paragraphStyle: paragraphStyle(multiple: 1.35)], range: enclosing)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                s.addAttribute(.foregroundColor, value: Palette.syntax, range: lineRange)
            }
            return
        }
        // Blank lines keep normal height: Return always moves a full line.
        if line.length == 0 { return }

        // Leanpub/Markua attribute list or directive: {width: 60%}, {#id}, {pagebreak}, {aside} …
        if Markua.attributeLine.firstMatch(in: line as String, range: full) != nil {
            s.addAttributes([.font: fonts.font(size: config.fontSize * 0.82, mono: true),
                             .foregroundColor: Palette.marker], range: lineRange)
            return
        }

        // Image on its own line → rendered inline below the line in WYSIWYG mode
        if let m = Self.imageLine.firstMatch(in: line as String, range: full) {
            let src = line.substring(with: m.range(at: 2))
            var drewImage = false
            if config.inlineImages,
               let url = ImageCache.resolve(src, relativeTo: baseDirectory),
               let img = ImageCache.shared.image(at: url) {
                let inline = InlineImage(image: img, widthFraction: attributeWidth(above: lineRange, in: ns))
                let size = inline.displaySize(maxWidth: contentWidth)
                s.addAttribute(.mdImage, value: inline, range: lineRange)
                s.addAttribute(.paragraphStyle, value: paragraphStyle(spacingBefore: 6, spacingAfter: size.height + 22), range: enclosing)
                drewImage = true
            }
            if hide && drewImage {
                hideRange(s, lineRange)
            } else {
                s.addAttribute(.foregroundColor, value: Palette.syntax, range: lineRange)
                s.addAttribute(.foregroundColor, value: Palette.link, range: abs(m.range(at: 1)))
            }
            return
        }

        // Horizontal rule
        if Self.rule.firstMatch(in: line as String, range: full) != nil {
            if hide {
                hideRange(s, lineRange)
                s.addAttribute(.mdRule, value: true, range: lineRange)
                s.addAttribute(.paragraphStyle, value: paragraphStyle(spacingBefore: 12, spacingAfter: 24), range: enclosing)
            } else {
                s.addAttribute(.foregroundColor, value: Palette.syntax, range: lineRange)
            }
            return
        }

        var protected: [NSRange] = []

        // Headings
        if let m = Self.heading.firstMatch(in: line as String, range: full) {
            let level = m.range(at: 1).length
            let scales: [CGFloat] = [1.6, 1.35, 1.18, 1.06, 1.0, 1.0]
            let size = config.scaleHeadings ? config.fontSize * scales[level - 1] : config.fontSize
            s.addAttributes([.font: fonts.font(size: size, bold: true), .foregroundColor: Palette.heading], range: lineRange)
            s.addAttribute(.paragraphStyle, value: paragraphStyle(spacingBefore: level <= 2 ? size * 0.5 : size * 0.25, multiple: 1.3), range: enclosing)
            syntax(s, NSRange(location: base, length: m.range(at: 1).length + m.range(at: 2).length), hide: hide)
        }
        // Leanpub blurbs / asides: A> W> T> E> I> Q> D> X> C> B> G>
        else if let m = Markua.blurbLine.firstMatch(in: line as String, range: full) {
            let cls = Markua.blurbClass(forPrefix: line.substring(with: m.range(at: 1)))
            let color = Markua.color(forClass: cls)
            s.addAttribute(.mdQuote, value: color, range: lineRange)
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.5
            p.headIndent = 22
            p.firstLineHeadIndent = 22
            s.addAttribute(.paragraphStyle, value: p, range: enclosing)
            if hide {
                hideRange(s, abs(m.range))
            } else {
                s.addAttribute(.foregroundColor, value: color, range: abs(m.range))
            }
        }
        // Blockquote
        else if let m = Self.quote.firstMatch(in: line as String, range: full) {
            s.addAttributes([.foregroundColor: Palette.quote, .mdQuote: true], range: lineRange)
            s.addAttribute(.font, value: fonts.font(size: config.fontSize, italic: !config.family.isMonospaced), range: lineRange)
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.5
            p.headIndent = 22
            p.firstLineHeadIndent = 22
            s.addAttribute(.paragraphStyle, value: p, range: enclosing)
            syntax(s, abs(m.range), hide: hide)
        }
        // List item
        else if let m = Self.list.firstMatch(in: line as String, range: full) {
            s.addAttribute(.foregroundColor, value: Palette.marker, range: abs(m.range(at: 2)))
            let prefix = line.substring(with: m.range) as NSString
            let indent = prefix.size(withAttributes: [.font: bodyFont]).width
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.5
            p.headIndent = indent
            s.addAttribute(.paragraphStyle, value: p, range: enclosing)
            let box = m.range(at: 4)
            if box.location != NSNotFound {
                let checked = line.substring(with: box).lowercased().contains("x")
                s.addAttribute(.foregroundColor, value: Palette.accent, range: abs(box))
                if checked {
                    let rest = NSRange(location: NSMaxRange(box), length: line.length - NSMaxRange(box))
                    s.addAttributes([.foregroundColor: Palette.quote, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: abs(rest))
                }
            }
        }
        // Table row
        else if Self.table.firstMatch(in: line as String, range: full) != nil {
            s.addAttribute(.font, value: fonts.font(size: config.fontSize * 0.92, mono: true), range: lineRange)
            for (i, ch) in (line as String).utf16.enumerated() where ch == 0x7C /* | */ {
                s.addAttribute(.foregroundColor, value: Palette.syntax, range: NSRange(location: base + i, length: 1))
            }
        }

        // MARK: Inline
        func overlaps(_ r: NSRange) -> Bool { protected.contains { NSIntersectionRange($0, r).length > 0 } }
        func each(_ rx: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for m in rx.matches(in: line as String, range: full) where !overlaps(m.range) { body(m) }
        }

        each(Self.htmlComment) { m in
            s.addAttribute(.foregroundColor, value: Palette.syntax, range: abs(m.range))
            protected.append(m.range)
        }

        each(Self.codeSpan) { m in
            let ticks = m.range(at: 1).length
            let inner = NSRange(location: m.range.location + ticks, length: m.range.length - 2 * ticks)
            s.addAttributes([.font: fonts.font(size: config.fontSize * 0.92, mono: true),
                             .foregroundColor: Palette.codeText,
                             .backgroundColor: Palette.codeBackground], range: abs(inner))
            syntax(s, abs(NSRange(location: m.range.location, length: ticks)), hide: hide)
            syntax(s, abs(NSRange(location: NSMaxRange(inner), length: ticks)), hide: hide)
            protected.append(m.range)
        }

        each(Self.inlineImage) { m in
            s.addAttribute(.foregroundColor, value: Palette.syntax, range: abs(m.range))
            s.addAttribute(.foregroundColor, value: Palette.link, range: abs(m.range(at: 1)))
            protected.append(m.range)
        }

        each(Self.link) { m in
            let text = m.range(at: 1)
            s.addAttributes([.foregroundColor: Palette.link,
                             .underlineStyle: NSUnderlineStyle.single.rawValue,
                             .underlineColor: Palette.link.withAlphaComponent(0.35)], range: abs(text))
            syntax(s, abs(NSRange(location: m.range.location, length: 1)), hide: hide)
            syntax(s, abs(NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text))), hide: hide)
            protected.append(NSRange(location: NSMaxRange(text), length: NSMaxRange(m.range) - NSMaxRange(text)))
        }

        each(Self.refLink) { m in
            s.addAttribute(.foregroundColor, value: Palette.link, range: abs(m.range(at: 1)))
            syntax(s, abs(NSRange(location: m.range.location, length: 1)), hide: false)
            let tail = NSRange(location: NSMaxRange(m.range(at: 1)), length: NSMaxRange(m.range) - NSMaxRange(m.range(at: 1)))
            syntax(s, abs(tail), hide: false)
            protected.append(tail)
        }

        each(Self.autolink) { m in
            s.addAttribute(.foregroundColor, value: Palette.link, range: abs(m.range))
            protected.append(m.range)
        }

        // Emphasis (order matters: *** before ** before *)
        each(Self.boldItalic) { m in
            addTrait(s, abs(m.range(at: 2)), [.bold, .italic])
            delimiters(s, m, abs, hide: hide)
        }
        each(Self.bold) { m in
            addTrait(s, abs(m.range(at: 2)), .bold)
            delimiters(s, m, abs, hide: hide)
        }
        for rx in [Self.italicStar, Self.italicUnderscore] {
            each(rx) { m in
                addTrait(s, abs(m.range(at: 2)), .italic)
                syntax(s, abs(m.range(at: 1)), hide: hide)
                syntax(s, abs(m.range(at: 3)), hide: hide)
            }
        }
        each(Self.strike) { m in
            s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                             .foregroundColor: Palette.quote], range: abs(m.range(at: 2)))
            syntax(s, abs(m.range(at: 1)), hide: hide)
            syntax(s, abs(m.range(at: 3)), hide: hide)
        }
        each(Self.highlight) { m in
            s.addAttribute(.backgroundColor, value: Palette.highlight, range: abs(m.range(at: 2)))
            syntax(s, abs(m.range(at: 1)), hide: hide)
            syntax(s, abs(m.range(at: 3)), hide: hide)
        }

        // Review placeholders like [IMAGE: ...] or [WAJAHAT: confirm] — always visible.
        for m in Markua.placeholder.matches(in: line as String, range: full) {
            s.addAttributes([.backgroundColor: Palette.placeholder, .foregroundColor: Palette.heading], range: abs(m.range))
        }
        each(Self.footnote) { m in
            s.addAttribute(.foregroundColor, value: Palette.marker, range: abs(m.range))
        }
    }

    // MARK: Helpers

    /// Leanpub `{width: 60%}` on the line directly above an image (blank line between allowed).
    private func attributeWidth(above lineRange: NSRange, in ns: NSString) -> CGFloat? {
        var loc = lineRange.location
        for _ in 0..<2 {
            guard loc > 0 else { return nil }
            let prev = ns.lineRange(for: NSRange(location: loc - 1, length: 0))
            let text = ns.substring(with: prev).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("{"), text.hasSuffix("}") {
                return Markua.fraction(Markua.parseAttributes(text)["width"])
            }
            if !text.isEmpty { return nil }
            loc = prev.location
        }
        return nil
    }

    private func delimiters(_ s: NSTextStorage, _ m: NSTextCheckingResult, _ abs: (NSRange) -> NSRange, hide: Bool) {
        let len = m.range(at: 1).length
        syntax(s, abs(NSRange(location: m.range.location, length: len)), hide: hide)
        syntax(s, abs(NSRange(location: NSMaxRange(m.range) - len, length: len)), hide: hide)
    }

    private func syntax(_ s: NSTextStorage, _ r: NSRange, hide: Bool) {
        guard r.length > 0 else { return }
        if hide {
            hideRange(s, r)
        } else {
            s.addAttribute(.foregroundColor, value: Palette.syntax, range: r)
        }
    }

    private func hideRange(_ s: NSTextStorage, _ r: NSRange) {
        s.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear], range: r)
    }

    private func addTrait(_ s: NSTextStorage, _ r: NSRange, _ trait: NSFontDescriptor.SymbolicTraits) {
        guard r.length > 0 else { return }
        s.enumerateAttribute(.font, in: r) { value, sub, _ in
            guard let f = value as? NSFont, f.pointSize > 1 else { return }
            s.addAttribute(.font, value: fonts.adding(trait, to: f), range: sub)
        }
    }
}
