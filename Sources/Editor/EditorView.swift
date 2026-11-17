import SwiftUI
import AppKit

/// Two-way scroll sync between editor and preview, by source line (1-based, fractional).
/// A line >= 1e8 means "scrolled to the bottom".
final class ScrollBridge {
    var onEditorScroll: ((Double) -> Void)?
    var onPreviewScroll: ((Double) -> Void)?
    /// Editor ignores its own scroll events until then (it is being driven by the preview).
    var editorSuppressedUntil = Date.distantPast
}

struct EditorView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var config: EditorConfig
    var scrollBridge: ScrollBridge?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, tv) = MarkdownTextView.make()
        let c = context.coordinator
        c.textView = tv
        c.slash.textView = tv
        tv.delegate = c
        tv.textStorage?.delegate = c
        tv.onContentWidthChange = { [weak c] width in c?.contentWidthChanged(width) }
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.scrolled),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.jumpToNextPlaceholder),
                                               name: .jumpToNextPlaceholder, object: nil)
        c.parent = self
        scrollBridge?.onPreviewScroll = { [weak c] line in c?.scrollTo(line: line) }
        c.apply(config: config, force: true)
        c.load(document)
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.apply(config: config, force: false)
        if c.documentURL != document.url || c.revision != document.revision {
            c.load(document)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.slash.close()
        NotificationCenter.default.removeObserver(coordinator)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: EditorView?
        weak var textView: MarkdownTextView?
        let styler = MarkdownStyler()

        private(set) var documentURL: URL?
        private(set) var revision = -1
        private var config = EditorConfig()
        private var activeRange = NSRange(location: 0, length: 0)
        private var isLoading = false
        private var restyleWork: DispatchWorkItem?

        /// UTF-16 offsets of each line start; nil = stale.
        private var lineStarts: [Int]?
        private var pendingSyncLine: Double?
        let slash = SlashMenuController()
        private var pendingSlash: Int?

        // MARK: Loading

        func load(_ doc: MarkdownDocument) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let sameFile = documentURL == doc.url
            let keepSelection = sameFile ? tv.selectedRange() : nil

            isLoading = true
            slash.close()
            slash.documentDirectory = doc.directory
            documentURL = doc.url
            revision = doc.revision
            styler.baseDirectory = doc.directory
            storage.beginEditing()
            storage.setAttributedString(NSAttributedString(string: doc.text, attributes: styler.baseAttributes))
            storage.endEditing()
            isLoading = false

            let length = storage.length
            var sel = NSRange(location: 0, length: 0)
            if let keep = keepSelection { sel = keep }
            sel = NSRange(location: min(sel.location, length), length: 0)
            lineStarts = nil
            activeRange = (storage.string as NSString).paragraphRange(for: sel)
            restyleAll()
            if let lm = tv.layoutManager, let tc = tv.textContainer { lm.ensureLayout(for: tc) }
            tv.setSelectedRange(sel)
            if !sameFile {
                // New file always opens at the top.
                tv.undoManager?.removeAllActions()
                scrollToTop()
                DispatchQueue.main.async { [weak self] in self?.scrollToTop() }
            }
            updateFocus()
        }

        private func scrollToTop() {
            guard let scroll = textView?.enclosingScrollView else { return }
            scroll.contentView.setBoundsOrigin(.zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        // MARK: Config

        func apply(config new: EditorConfig, force: Bool) {
            guard force || new != config, let tv = textView else { return }
            let old = config
            config = new
            Palette.theme = new.theme
            styler.config = new
            if force || old.theme != new.theme { applyChrome(tv) }
            styler.contentWidth = tv.contentWidth
            tv.columnWidth = new.lineWidth.points
            tv.typewriter = new.typewriter
            tv.plainText = new.plainText
            tv.isContinuousSpellCheckingEnabled = !new.plainText
            tv.typingAttributes = styler.baseAttributes
            if force || old.theme != new.theme || old.family != new.family || old.fontSize != new.fontSize || old.hideSyntax != new.hideSyntax
                || old.inlineImages != new.inlineImages || old.scaleHeadings != new.scaleHeadings || old.plainText != new.plainText {
                restyleAll()
            }
            updateFocus()
            if new.typewriter { centerCaret() }
        }

        private func applyChrome(_ tv: MarkdownTextView) {
            tv.backgroundColor = Palette.background
            tv.insertionPointColor = Palette.accent
            tv.selectedTextAttributes = [.backgroundColor: Palette.selection]
            tv.enclosingScrollView?.backgroundColor = Palette.background
            tv.needsDisplay = true
        }

        func contentWidthChanged(_ width: CGFloat) {
            styler.contentWidth = width
            restyleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.restyleAll() }
            restyleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        private func restyleAll() {
            guard let storage = textView?.textStorage else { return }
            styler.updateCodeBlocks(in: storage.string as NSString)
            storage.beginEditing()
            styler.style(storage, in: NSRange(location: 0, length: storage.length), active: activeRange)
            storage.endEditing()
            textView?.needsDisplay = true
        }

        // MARK: NSTextStorageDelegate

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !isLoading else { return }
            lineStarts = nil
            let ns = textStorage.string as NSString
            let changed = styler.updateCodeBlocks(in: ns)
            var range = editedRange
            if !changed {
                // Neighbouring lines depend on each other (blank-line runs, {width} above images).
                let start = range.location > 0 ? ns.lineRange(for: NSRange(location: range.location - 1, length: 0)).location : 0
                let endLoc = min(ns.length, NSMaxRange(range) + 1)
                let end = endLoc < ns.length ? NSMaxRange(ns.lineRange(for: NSRange(location: endLoc, length: 0))) : ns.length
                range = NSRange(location: start, length: end - start)
            } else {
                range = NSRange(location: 0, length: textStorage.length)
            }
            styler.style(textStorage, in: range, active: activeRange)
        }

        // MARK: NSTextViewDelegate

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            pendingSlash = nil
            if !config.plainText, let r = replacementString, range.length == 0,
               SlashMenuController.shouldTrigger(r, at: range.location, in: textView.string as NSString),
               !styler.codeBlocks.contains(where: { NSLocationInRange(range.location, $0) }) {
                pendingSlash = range.location
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, !isLoading else { return }
            parent?.document.editorDidChange(tv.string)
            ChromeState.shared.typed()
            if let loc = pendingSlash {
                pendingSlash = nil
                slash.open(at: loc)
            } else if slash.isOpen {
                slash.refresh()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView, let storage = tv.textStorage, !isLoading else { return }
            let ns = storage.string as NSString
            let sel = tv.selectedRange()
            let safe = NSRange(location: min(sel.location, ns.length), length: min(sel.length, ns.length - min(sel.location, ns.length)))
            let newActive = ns.paragraphRange(for: safe)
            if newActive != activeRange {
                let old = NSIntersectionRange(activeRange, NSRange(location: 0, length: ns.length))
                activeRange = newActive
                do {   // caret line affects hidden syntax and blank-line height
                    let restyle = { [weak self] in
                        guard let self else { return }
                        storage.beginEditing()
                        if old.location < ns.length || old.length > 0 {
                            self.styler.style(storage, in: old, active: newActive)
                        }
                        self.styler.style(storage, in: newActive, active: newActive)
                        storage.endEditing()
                    }
                    if storage.editedMask.isEmpty { restyle() } else { DispatchQueue.main.async(execute: restyle) }
                }
            }
            tv.typingAttributes = styler.baseAttributes
            if slash.isOpen && pendingSlash == nil { slash.refresh() }
            updateFocus()
            if config.typewriter { centerCaret() }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if slash.isOpen {
                switch commandSelector {
                case #selector(NSResponder.moveUp(_:)): slash.move(-1); return true
                case #selector(NSResponder.moveDown(_:)): slash.move(1); return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    slash.confirm(); return true
                case #selector(NSResponder.cancelOperation(_:)): slash.close(); return true
                default: break
                }
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return indentList(by: 1)
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                return indentList(by: -1)
            }
            return false
        }

        /// Tab / Shift-Tab on a list line indents / outdents it.
        private func indentList(by step: Int) -> Bool {
            guard let tv = textView else { return false }
            let ns = tv.string as NSString
            let lineRange = ns.lineRange(for: tv.selectedRange())
            let line = ns.substring(with: lineRange)
            guard line.range(of: #"^[ \t]*([-*+]|\d+[.)])[ \t]"#, options: .regularExpression) != nil else { return false }
            let sel = tv.selectedRange()
            if step > 0 {
                let r = NSRange(location: lineRange.location, length: 0)
                if tv.shouldChangeText(in: r, replacementString: "    ") {
                    tv.replaceCharacters(in: r, with: "    "); tv.didChangeText()
                    tv.setSelectedRange(NSRange(location: sel.location + 4, length: sel.length))
                }
            } else {
                let lead = line.prefix { $0 == " " }.count
                let remove = min(4, lead)
                guard remove > 0 else { return true }
                let r = NSRange(location: lineRange.location, length: remove)
                if tv.shouldChangeText(in: r, replacementString: "") {
                    tv.replaceCharacters(in: r, with: ""); tv.didChangeText()
                    tv.setSelectedRange(NSRange(location: max(lineRange.location, sel.location - remove), length: sel.length))
                }
            }
            return true
        }

        // MARK: Focus & typewriter

        private func updateFocus() {
            guard let tv = textView, let lm = tv.layoutManager, let storage = tv.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
            guard config.focusMode, storage.length > 0 else { return }
            lm.addTemporaryAttribute(.foregroundColor, value: Palette.dimmed, forCharacterRange: full)
            let active = NSIntersectionRange(activeRange, full)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: active)
        }

        private func centerCaret() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let scroll = tv.enclosingScrollView else { return }
            let loc = tv.selectedRange().location
            var rect: NSRect
            if loc >= (tv.string as NSString).length, !lm.extraLineFragmentRect.isEmpty {
                rect = lm.extraLineFragmentRect
            } else {
                let length = (tv.string as NSString).length
                guard length > 0 else { return }
                let g = lm.glyphIndexForCharacter(at: min(loc, length - 1))
                rect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            }
            _ = tc
            let y = rect.midY + tv.textContainerOrigin.y - scroll.contentView.bounds.height / 2
            scroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: max(0, y)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        // MARK: Scroll sync

        /// Select the next review placeholder after the caret (wraps to the top).
        @objc func jumpToNextPlaceholder() {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            let matches = Markua.placeholder.matches(in: tv.string, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { return }
            let after = NSMaxRange(tv.selectedRange())
            let next = matches.first { $0.range.location >= after } ?? matches[0]
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(next.range)
            tv.scrollRangeToVisible(next.range)
            tv.showFindIndicator(for: next.range)
        }

        @objc func scrolled(_ note: Notification) {
            if slash.isOpen { slash.close() }
            guard let bridge = parent?.scrollBridge, Date() > bridge.editorSuppressedUntil,
                  let line = topVisibleLine() else { return }
            bridge.onEditorScroll?(line)
        }

        private func lineIndex(of location: Int) -> Int {
            let starts = currentLineStarts()
            var lo = 0, hi = starts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if starts[mid] <= location { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }

        private func currentLineStarts() -> [Int] {
            if let lineStarts { return lineStarts }
            var starts = [0]
            if let ns = textView?.string as NSString? {
                let length = ns.length
                var buffer = [unichar](repeating: 0, count: length)
                ns.getCharacters(&buffer, range: NSRange(location: 0, length: length))
                for i in 0..<length where buffer[i] == 0x0A { starts.append(i + 1) }
            }
            lineStarts = starts
            return starts
        }

        /// 1-based fractional source line at the top of the editor viewport.
        private func topVisibleLine() -> Double? {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let storage = tv.textStorage, let clip = tv.enclosingScrollView?.contentView else { return nil }
            let length = storage.length
            guard length > 0 else { return 0 }
            if clip.bounds.origin.y <= 1 { return 0 }
            if clip.bounds.maxY >= tv.frame.height - 2 { return 1e9 }
            let y = clip.bounds.origin.y - tv.textContainerOrigin.y
            let glyph = lm.glyphIndex(for: NSPoint(x: 0, y: max(0, y)), in: tc)
            let ci = min(lm.characterIndexForGlyph(at: glyph), length - 1)
            let ns = storage.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: ci, length: 0))
            let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: para, actualCharacterRange: nil), in: tc)
            let frac = rect.height > 0 ? min(1, max(0, (y - rect.minY) / rect.height)) : 0
            return Double(lineIndex(of: para.location) + 1) + Double(frac)
        }

        /// Scroll so that 1-based fractional source `line` sits at the top (driven by the preview).
        func scrollTo(line: Double) {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let storage = tv.textStorage, let scroll = tv.enclosingScrollView else { return }
            let clip = scroll.contentView
            let maxY = max(0, tv.frame.height - clip.bounds.height)
            var target: CGFloat
            if line <= 1 || storage.length == 0 {
                target = 0
            } else if line >= 1e8 {
                target = maxY
            } else {
                let starts = currentLineStarts()
                let idx = min(starts.count - 1, max(0, Int(line.rounded(.down)) - 1))
                let ns = storage.string as NSString
                let loc = min(starts[idx], max(0, ns.length - 1))
                let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: para, actualCharacterRange: nil), in: tc)
                target = rect.minY + CGFloat(line - line.rounded(.down)) * rect.height + tv.textContainerOrigin.y
            }
            parent?.scrollBridge?.editorSuppressedUntil = Date().addingTimeInterval(0.25)
            clip.setBoundsOrigin(NSPoint(x: 0, y: min(maxY, max(0, target))))
            scroll.reflectScrolledClipView(clip)
        }
    }
}
