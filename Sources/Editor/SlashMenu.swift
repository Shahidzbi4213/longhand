import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Commands

enum SlashAction {
    /// Turn the current line into this block type (replaces any existing block prefix).
    case linePrefix(String)
    /// Insert inline text at the slash. `$0` marks where the caret lands.
    case snippet(String)
    /// Insert a block on its own line(s). `$0` marks where the caret lands.
    case block(String)
    /// Pick an image file and insert it (optionally with a Leanpub attribute line).
    case image(leanpub: Bool)
    /// Insert the next numbered footnote reference + a definition at the end of the file.
    case footnote
}

struct SlashCommand: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let section: String
    let keywords: [String]
    let action: SlashAction

    static let all: [SlashCommand] = [
        .init(id: "text", title: "Text", detail: "Plain paragraph", symbol: "text.alignleft", section: "Basic", keywords: ["paragraph", "plain", "p"], action: .linePrefix("")),
        .init(id: "h1", title: "Heading 1", detail: "Chapter title", symbol: "textformat.size.larger", section: "Basic", keywords: ["h1", "title", "#"], action: .linePrefix("# ")),
        .init(id: "h2", title: "Heading 2", detail: "Section", symbol: "textformat.size", section: "Basic", keywords: ["h2", "section", "##"], action: .linePrefix("## ")),
        .init(id: "h3", title: "Heading 3", detail: "Subsection", symbol: "textformat.size.smaller", section: "Basic", keywords: ["h3", "subsection", "###"], action: .linePrefix("### ")),
        .init(id: "bullet", title: "Bulleted list", detail: "Simple bullet list", symbol: "list.bullet", section: "Basic", keywords: ["ul", "list", "bullet", "-"], action: .linePrefix("- ")),
        .init(id: "number", title: "Numbered list", detail: "1, 2, 3…", symbol: "list.number", section: "Basic", keywords: ["ol", "list", "number", "1."], action: .linePrefix("1. ")),
        .init(id: "todo", title: "To-do", detail: "Checkbox item", symbol: "checklist", section: "Basic", keywords: ["task", "checkbox", "todo", "[]"], action: .linePrefix("- [ ] ")),
        .init(id: "quote", title: "Quote", detail: "Blockquote", symbol: "text.quote", section: "Basic", keywords: ["blockquote", ">"], action: .linePrefix("> ")),
        .init(id: "code", title: "Code block", detail: "Fenced code", symbol: "chevron.left.forwardslash.chevron.right", section: "Basic", keywords: ["code", "fence", "```", "snippet"], action: .block("```$0\n\n```")),
        .init(id: "divider", title: "Divider", detail: "Horizontal rule / scene break", symbol: "minus", section: "Basic", keywords: ["hr", "rule", "line", "---", "scene"], action: .block("---\n$0")),
        .init(id: "table", title: "Table", detail: "2-column table", symbol: "tablecells", section: "Basic", keywords: ["table", "grid"], action: .block("| $0 | Column |\n| --- | --- |\n|  |  |")),
        .init(id: "image", title: "Image", detail: "Pick an image file", symbol: "photo", section: "Media", keywords: ["image", "picture", "photo", "img", "figure"], action: .image(leanpub: false)),
        .init(id: "figure", title: "Figure (Leanpub)", detail: "Image with width & caption", symbol: "photo.on.rectangle", section: "Media", keywords: ["figure", "caption", "width", "leanpub", "image"], action: .image(leanpub: true)),
        .init(id: "link", title: "Link", detail: "[text](url)", symbol: "link", section: "Media", keywords: ["url", "href", "link"], action: .snippet("[$0](https://)")),
        .init(id: "footnote", title: "Footnote", detail: "Numbered note at chapter end", symbol: "textformat.superscript", section: "Media", keywords: ["footnote", "note", "reference", "cite", "source"], action: .footnote),
        .init(id: "warning", title: "Warning", detail: "W> blurb", symbol: "exclamationmark.triangle", section: "Leanpub", keywords: ["warning", "caution", "w>"], action: .linePrefix("W> ")),
        .init(id: "tip", title: "Tip", detail: "T> blurb", symbol: "lightbulb", section: "Leanpub", keywords: ["tip", "hint", "t>"], action: .linePrefix("T> ")),
        .init(id: "info", title: "Information", detail: "I> blurb", symbol: "info.circle", section: "Leanpub", keywords: ["info", "information", "note", "i>"], action: .linePrefix("I> ")),
        .init(id: "aside", title: "Aside", detail: "A> sidebar", symbol: "sidebar.right", section: "Leanpub", keywords: ["aside", "sidebar", "a>"], action: .linePrefix("A> ")),
        .init(id: "error", title: "Error", detail: "E> blurb", symbol: "xmark.octagon", section: "Leanpub", keywords: ["error", "mistake", "e>"], action: .linePrefix("E> ")),
        .init(id: "question", title: "Question", detail: "Q> blurb", symbol: "questionmark.circle", section: "Leanpub", keywords: ["question", "q>"], action: .linePrefix("Q> ")),
        .init(id: "exercise", title: "Exercise", detail: "X> blurb", symbol: "pencil.and.list.clipboard", section: "Leanpub", keywords: ["exercise", "homework", "x>"], action: .linePrefix("X> ")),
        .init(id: "discussion", title: "Discussion", detail: "D> blurb", symbol: "bubble.left.and.bubble.right", section: "Leanpub", keywords: ["discussion", "d>"], action: .linePrefix("D> ")),
        .init(id: "pagebreak", title: "Page break", detail: "{pagebreak}", symbol: "doc.badge.plus", section: "Leanpub", keywords: ["pagebreak", "page", "break"], action: .block("{pagebreak}\n$0")),
        .init(id: "sample", title: "Sample chapter", detail: "{sample: true} above heading", symbol: "eye", section: "Leanpub", keywords: ["sample", "free", "preview"], action: .block("{sample: true}\n# $0")),
        .init(id: "ph-image", title: "Image placeholder", detail: "[IMAGE: …]", symbol: "photo.badge.plus", section: "Review", keywords: ["placeholder", "image", "todo"], action: .snippet("[IMAGE: $0]")),
        .init(id: "ph-note", title: "Author note", detail: "[WAJAHAT: …]", symbol: "person.crop.circle.badge.questionmark", section: "Review", keywords: ["note", "confirm", "wajahat", "todo", "check"], action: .snippet("[WAJAHAT: $0]")),
        .init(id: "ph-todo", title: "TODO", detail: "[TODO: …]", symbol: "checkmark.circle", section: "Review", keywords: ["todo", "fixme", "later"], action: .snippet("[TODO: $0]")),
        .init(id: "highlight", title: "Highlight", detail: "==marked text==", symbol: "highlighter", section: "Review", keywords: ["highlight", "mark", "=="], action: .snippet("==$0==")),
    ]

    func score(_ query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let q = query.lowercased()
        let t = title.lowercased()
        if t.hasPrefix(q) { return 0 }
        if keywords.contains(where: { $0.hasPrefix(q) }) { return 1 }
        if t.contains(q) { return 2 }
        if keywords.contains(where: { $0.contains(q) }) { return 3 }
        // loose subsequence match: "hd1" → "heading 1"
        var it = t.makeIterator()
        for ch in q where ch != " " {
            var found = false
            while let c = it.next() { if c == ch { found = true; break } }
            if !found { return nil }
        }
        return 4
    }
}

// MARK: - Model & view

final class SlashMenuModel: ObservableObject {
    @Published var items: [SlashCommand] = []
    @Published var selected = 0
    /// Direction of the last keyboard move (+1 down, -1 up, 0 = reset/jump).
    var lastDelta = 0
    /// Hover is ignored briefly after keyboard moves (the list scrolls under a still mouse).
    var keyboardNavAt = Date.distantPast
    /// Row frames in the scroll view's visible coordinate space, and the viewport height.
    var rowFrames: [String: CGRect] = [:]
    var viewportHeight: CGFloat = 0
    var onPick: (SlashCommand) -> Void = { _ in }
}

private struct SlashMenuView: View {
    @ObservedObject var model: SlashMenuModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { i, cmd in
                        // Header + first row share one id, so scrolling to the row shows its header.
                        VStack(alignment: .leading, spacing: 1) {
                            if i == 0 || model.items[i - 1].section != cmd.section {
                                Text(cmd.section.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.top, i == 0 ? 2 : 8)
                                    .padding(.bottom, 2)
                            }
                            row(cmd, selected: i == model.selected)
                                .contentShape(Rectangle())
                                .onTapGesture { model.onPick(cmd) }
                                .onHover { inside in
                                    if inside, Date().timeIntervalSince(model.keyboardNavAt) > 0.4 { model.selected = i }
                                }
                        }
                        .id(cmd.id)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: RowFramesKey.self, value: [cmd.id: g.frame(in: .named("slashMenu"))])
                        })
                    }
                }
                .padding(6)
            }
            .coordinateSpace(name: "slashMenu")
            .background(GeometryReader { g in
                Color.clear.onAppear { model.viewportHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in model.viewportHeight = h }
            })
            .onPreferenceChange(RowFramesKey.self) { model.rowFrames = $0 }
            .onChange(of: model.selected) { _, i in
                guard model.items.indices.contains(i), model.lastDelta != 0 else { return }
                let id = model.items[i].id
                // Scroll only when the row (with its section header) is not fully visible.
                guard let f = model.rowFrames[id], model.viewportHeight > 0 else {
                    proxy.scrollTo(id, anchor: model.lastDelta > 0 ? .bottom : .top)
                    return
                }
                if f.minY < 0 {
                    proxy.scrollTo(id, anchor: .top)
                } else if f.maxY > model.viewportHeight {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onChange(of: model.items.map(\.id)) { _, ids in
                if let first = ids.first { proxy.scrollTo(first, anchor: .top) }
            }
        }
        .frame(width: 290)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }

    private func row(_ cmd: SlashCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(.background.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(cmd.title).font(.system(size: 13))
                Text(cmd.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.18) : .clear))
    }
}

private struct RowFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private final class SlashPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

/// Owns the popup and applies the chosen command to the text view.
final class SlashMenuController {
    weak var textView: NSTextView?
    var documentDirectory: URL?
    private(set) var slashLocation: Int?
    private var panel: SlashPanel?
    private let model = SlashMenuModel()

    var isOpen: Bool { slashLocation != nil }

    init() {
        model.onPick = { [weak self] cmd in self?.apply(cmd) }
    }

    /// Should typing `replacement` at `location` open the menu?
    static func shouldTrigger(_ replacement: String, at location: Int, in ns: NSString) -> Bool {
        guard replacement == "/" else { return false }
        if location == 0 { return true }
        let prev = ns.character(at: location - 1)
        return prev == 0x20 || prev == 0x09 || prev == 0x0A || prev == 0x28 // space, tab, newline, "("
    }

    func open(at location: Int) {
        slashLocation = location
        refresh()
    }

    func close() {
        slashLocation = nil
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    /// Call after every text or selection change while open.
    func refresh() {
        guard let loc = slashLocation, let tv = textView else { return close() }
        let ns = tv.string as NSString
        let caret = tv.selectedRange()
        guard caret.length == 0, caret.location > loc, loc < ns.length, ns.character(at: loc) == 0x2F /* / */ else { return close() }
        let query = ns.substring(with: NSRange(location: loc + 1, length: caret.location - loc - 1))
        if query.contains("\n") || query.count > 24 || query.hasPrefix(" ") { return close() }
        let ranked = SlashCommand.all.enumerated().compactMap { i, c in c.score(query).map { (c, $0, i) } }
        let items = (query.isEmpty ? ranked : ranked.sorted { ($0.1, $0.2) < ($1.1, $1.2) }).map(\.0)
        if items.isEmpty {
            // Allow a little slack for typos, then give up.
            if query.count > 3 || query.hasSuffix(" ") { return close() }
        }
        if model.items.map(\.id) != items.map(\.id) {
            model.lastDelta = 0
            model.items = items
            model.selected = 0
        }
        show(itemCount: items.count)
    }

    func move(_ delta: Int) {
        guard !model.items.isEmpty else { return }
        model.keyboardNavAt = Date()
        model.lastDelta = delta
        let next = model.selected + delta
        // Only scroll when the row would leave the view; SwiftUI handles that via anchor.
        model.selected = (next + model.items.count) % model.items.count
    }

    func confirm() {
        guard model.items.indices.contains(model.selected) else { return close() }
        apply(model.items[model.selected])
    }

    // MARK: Panel

    private func show(itemCount: Int) {
        guard let tv = textView, let window = tv.window, let loc = slashLocation else { return }
        if itemCount == 0 { panel?.orderOut(nil); return }
        let panel = self.panel ?? makePanel()
        let sections = Set(model.items.map(\.section)).count
        let height = min(360, CGFloat(itemCount) * 41 + CGFloat(sections) * 22 + 14)
        var rect = tv.firstRect(forCharacterRange: NSRange(location: loc, length: 1), actualRange: nil)
        if rect.isEmpty { rect = NSRect(x: window.frame.midX, y: window.frame.midY, width: 1, height: 18) }
        var origin = NSPoint(x: rect.minX - 6, y: rect.minY - height - 6)
        if let screen = window.screen?.visibleFrame, origin.y < screen.minY {
            origin.y = rect.maxY + 6
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: 290, height: height)), display: true)
        panel.appearance = window.effectiveAppearance
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    private func makePanel() -> SlashPanel {
        let p = SlashPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isFloatingPanel = true
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.becomesKeyOnlyIfNeeded = true
        let host = NSHostingView(rootView: SlashMenuView(model: model))
        host.wantsLayer = true
        p.contentView = host
        panel = p
        return p
    }

    // MARK: Apply

    private func apply(_ cmd: SlashCommand) {
        guard let tv = textView, let loc = slashLocation else { return }
        let ns = tv.string as NSString
        let caret = max(loc + 1, min(tv.selectedRange().location, ns.length))
        let trigger = NSRange(location: loc, length: caret - loc)   // "/query"
        close()

        switch cmd.action {
        case .snippet(let s):
            insert(s, replacing: trigger)

        case .block(let s):
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            let before = ns.substring(with: NSRange(location: line.location, length: loc - line.location))
            let afterStart = NSMaxRange(trigger)
            let lineEnd = line.location + (ns.substring(with: line) as NSString).length - (ns.substring(with: line).hasSuffix("\n") ? 1 : 0)
            let after = afterStart < lineEnd ? ns.substring(with: NSRange(location: afterStart, length: lineEnd - afterStart)) : ""
            var text = s
            if !before.trimmingCharacters(in: .whitespaces).isEmpty { text = "\n" + text }
            if !after.trimmingCharacters(in: .whitespaces).isEmpty { text += "\n" }
            insert(text, replacing: trigger)

        case .linePrefix(let prefix):
            applyLinePrefix(prefix, trigger: trigger)

        case .footnote:
            let numbers = (try? NSRegularExpression(pattern: #"\[\^(\d+)\]"#))?
                .matches(in: tv.string, range: NSRange(location: 0, length: ns.length))
                .compactMap { Int(ns.substring(with: $0.range(at: 1))) } ?? []
            let n = (numbers.max() ?? 0) + 1
            insert("[^\(n)]$0", replacing: trigger)
            // Definition at the end of the file.
            let end = (tv.string as NSString).length
            let sep = tv.string.hasSuffix("\n\n") ? "" : (tv.string.hasSuffix("\n") ? "\n" : "\n\n")
            let def = "\(sep)[^\(n)]: "
            let keep = tv.selectedRange()
            if tv.shouldChangeText(in: NSRange(location: end, length: 0), replacementString: def) {
                tv.replaceCharacters(in: NSRange(location: end, length: 0), with: def)
                tv.didChangeText()
            }
            tv.setSelectedRange(keep)

        case .image(let leanpub):
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.message = "Choose an image to insert"
            if let root = ImageCache.workspaceRoot {
                let images = root.appendingPathComponent("Images")
                panel.directoryURL = FileManager.default.fileExists(atPath: images.path) ? images : root
            }
            guard panel.runModal() == .OK, let file = panel.url else {
                insert("", replacing: trigger)
                return
            }
            let path = relativePath(from: documentDirectory, to: file)
            let name = file.deletingPathExtension().lastPathComponent
            let markup = leanpub
                ? "{width: 80%, caption: \"$0\"}\n![\(name)](\(path))"
                : "![$0\(name)](\(path))"
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            let before = ns.substring(with: NSRange(location: line.location, length: loc - line.location))
            insert((before.trimmingCharacters(in: .whitespaces).isEmpty ? "" : "\n") + markup + "\n", replacing: trigger)
        }
    }

    /// Replace `range` with `template`; caret goes where `$0` is (or the end).
    private func insert(_ template: String, replacing range: NSRange) {
        guard let tv = textView else { return }
        let marker = (template as NSString).range(of: "$0")
        let text = template.replacingOccurrences(of: "$0", with: "")
        guard tv.shouldChangeText(in: range, replacementString: text) else { return }
        tv.replaceCharacters(in: range, with: text)
        tv.didChangeText()
        let caret = range.location + (marker.location != NSNotFound ? marker.location : (text as NSString).length)
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        tv.scrollRangeToVisible(tv.selectedRange())
    }

    private static let blockPrefix = try! NSRegularExpression(
        pattern: #"^([ \t]*)(#{1,6}[ \t]+|[-*+][ \t]+\[[ xX]\][ \t]+|[-*+][ \t]+|\d+[.)][ \t]+|>[ \t]?|[ABCDEGIQTWX]>[ \t]?)?"#)

    private func applyLinePrefix(_ prefix: String, trigger: NSRange) {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        var line = ns.lineRange(for: NSRange(location: trigger.location, length: 0))
        if ns.substring(with: line).hasSuffix("\n") { line.length -= 1 }
        let original = ns.substring(with: line) as NSString
        let slashInLine = trigger.location - line.location
        // Remove "/query" from the line text.
        let without = original.replacingCharacters(in: NSRange(location: slashInLine, length: trigger.length), with: "") as NSString
        let m = Self.blockPrefix.firstMatch(in: without as String, range: NSRange(location: 0, length: without.length))
        let indent = m.map { without.substring(with: $0.range(at: 1)) } ?? ""
        let oldPrefixLength = m?.range.length ?? 0
        let body = without.substring(from: oldPrefixLength)
        let newLine = indent + prefix + body
        guard tv.shouldChangeText(in: line, replacementString: newLine) else { return }
        tv.replaceCharacters(in: line, with: newLine)
        tv.didChangeText()
        // Caret where the slash was, shifted by the prefix change.
        let caretInBody = max(0, slashInLine - oldPrefixLength)
        let caret = line.location + (indent as NSString).length + (prefix as NSString).length + min(caretInBody, (body as NSString).length)
        tv.setSelectedRange(NSRange(location: caret, length: 0))
    }

    private func relativePath(from directory: URL?, to file: URL) -> String {
        guard let directory else { return file.path }
        let from = directory.standardizedFileURL.pathComponents
        let to = file.standardizedFileURL.pathComponents
        var i = 0
        while i < from.count, i < to.count, from[i] == to[i] { i += 1 }
        let ups = Array(repeating: "..", count: from.count - i)
        let path = (ups + to[i...]).joined(separator: "/")
        return path.contains(" ") ? "<\(path)>" : path
    }
}
