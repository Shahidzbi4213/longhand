import AppKit

/// NSTextView (TextKit 1) that centers a fixed-width writing column and draws
/// inline images, blockquote bars and horizontal rules for the WYSIWYG mode.
final class MarkdownTextView: NSTextView {
    var columnWidth: CGFloat = 700 { didSet { updateInsets() } }
    var typewriter = false { didSet { updateInsets() } }
    /// Called when the usable text width changes (images need re-measuring).
    var onContentWidthChange: ((CGFloat) -> Void)?

    private var lastContentWidth: CGFloat = 0

    static func make() -> (NSScrollView, MarkdownTextView) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = false   // full layout: stable scrollbar, no "loading more" while scrolling
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.drawsBackground = true
        tv.backgroundColor = Palette.background
        tv.insertionPointColor = Palette.accent
        tv.selectedTextAttributes = [.backgroundColor: Palette.selection]
        tv.linkTextAttributes = [:]

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = true
        scroll.backgroundColor = Palette.background
        scroll.borderType = .noBorder
        scroll.documentView = tv
        return (scroll, tv)
    }

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        reportWidthIfChanged()
    }

    func updateInsets() {
        let horizontal = max(28, floor((bounds.width - columnWidth) / 2))
        let visibleHeight = enclosingScrollView?.contentSize.height ?? 600
        let vertical: CGFloat = typewriter ? max(60, visibleHeight / 2) : 60
        let inset = NSSize(width: horizontal, height: vertical)
        if textContainerInset != inset {
            textContainerInset = inset
        }
        if !inLiveResize { reportWidthIfChanged() }
    }

    var contentWidth: CGFloat {
        max(100, bounds.width - 2 * textContainerInset.width)
    }

    private func reportWidthIfChanged() {
        let w = contentWidth
        if abs(w - lastContentWidth) > 1 {
            lastContentWidth = w
            onContentWidthChange?(w)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else { return }
        let origin = textContainerOrigin
        let visible = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        guard glyphs.length > 0 else { return }
        var chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // Include the paragraph just above the viewport: its image may hang into view.
        let startPara = (ts.string as NSString).paragraphRange(for: NSRange(location: max(0, chars.location - 1), length: 0))
        chars = NSUnionRange(chars, startPara)
        let width = tc.size.width

        ts.enumerateAttribute(.mdImage, in: chars) { value, range, _ in
            guard let inline = value as? InlineImage, range.length > 0 else { return }
            let img = inline.image
            let glyph = lm.glyphIndexForCharacter(at: NSMaxRange(range) - 1)
            let used = lm.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let size = inline.displaySize(maxWidth: contentWidth)
            let rect = NSRect(x: origin.x + floor((width - size.width) / 2),
                              y: origin.y + used.maxY + 10,
                              width: size.width, height: size.height)
            guard rect.intersects(dirtyRect) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
            img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                     hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
            NSGraphicsContext.restoreGraphicsState()
            Palette.syntax.withAlphaComponent(0.5).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            border.lineWidth = 0.5
            border.stroke()
        }

        ts.enumerateAttribute(.mdQuote, in: chars) { value, range, _ in
            guard value != nil else { return }
            let g = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: g, in: tc)
            let bar = NSRect(x: origin.x + 2, y: origin.y + rect.minY + 3, width: 3, height: max(0, rect.height - 6))
            ((value as? NSColor) ?? Palette.syntax).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }

        ts.enumerateAttribute(.mdRule, in: chars) { value, range, _ in
            guard value != nil else { return }
            let glyph = lm.glyphIndexForCharacter(at: range.location)
            let used = lm.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = origin.y + used.maxY + 11.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: origin.x + width * 0.3, y: y))
            path.line(to: NSPoint(x: origin.x + width * 0.7, y: y))
            path.lineWidth = 1
            Palette.syntax.setStroke()
            path.stroke()
        }
    }

    // MARK: Editing niceties

    /// Continue lists / quotes on Return, like iA Writer.
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let sel = selectedRange()
        guard sel.length == 0 else { return super.insertNewline(sender) }
        let lineRange = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = ns.substring(with: NSRange(location: lineRange.location, length: sel.location - lineRange.location))
        guard let rx = try? NSRegularExpression(pattern: #"^([ \t]*)([-*+]|(\d+)([.)])|>)([ \t]+)(\[[ xX]\][ \t]+)?"#),
              let m = rx.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return super.insertNewline(sender)
        }
        let lineNS = line as NSString
        // Empty item → end the list.
        if m.range.length == lineNS.length {
            let r = NSRange(location: lineRange.location, length: lineNS.length)
            if shouldChangeText(in: r, replacementString: "") {
                replaceCharacters(in: r, with: "")
                didChangeText()
            }
            return
        }
        var prefix = lineNS.substring(with: m.range(at: 1))
        if m.range(at: 3).location != NSNotFound, let n = Int(lineNS.substring(with: m.range(at: 3))) {
            prefix += "\(n + 1)" + lineNS.substring(with: m.range(at: 4))
        } else {
            prefix += lineNS.substring(with: m.range(at: 2))
        }
        prefix += lineNS.substring(with: m.range(at: 5))
        if m.range(at: 6).location != NSNotFound { prefix += "[ ] " }
        insertText("\n" + prefix, replacementRange: sel)
    }

    /// Wrap selection with a markdown marker (⌘B / ⌘I style).
    func toggleWrap(_ marker: String) {
        let sel = selectedRange()
        let ns = string as NSString
        let m = (marker as NSString).length
        if sel.location >= m, NSMaxRange(sel) + m <= ns.length,
           ns.substring(with: NSRange(location: sel.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: m)) == marker {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            let inner = ns.substring(with: sel)
            if shouldChangeText(in: outer, replacementString: inner) {
                replaceCharacters(in: outer, with: inner)
                didChangeText()
                setSelectedRange(NSRange(location: outer.location, length: sel.length))
            }
            return
        }
        let inner = ns.substring(with: sel)
        let replacement = marker + inner + marker
        if shouldChangeText(in: sel, replacementString: replacement) {
            replaceCharacters(in: sel, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location + m, length: sel.length))
        }
    }

    @objc func toggleBold(_ sender: Any?) { toggleWrap("**") }
    @objc func toggleItalic(_ sender: Any?) { toggleWrap("_") }
    @objc func toggleCode(_ sender: Any?) { toggleWrap("`") }
}
