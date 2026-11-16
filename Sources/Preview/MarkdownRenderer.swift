import Foundation
import Markdown

/// Markdown (+ Leanpub/Markua extensions) → HTML for the preview.
///
/// Every block element carries `data-line` (1-based source line) so editor and preview can
/// scroll in sync. Markua constructs are rewritten into plain Markdown first, **one output line per
/// input line**, so source line numbers stay valid.
enum MarkdownRenderer {
    static func html(from markdown: String, documentDirectory: URL?, keepLineBreaks: Bool = true) -> String {
        let pre = MarkuaPreprocessor.process(markdown)
        let document = Document(parsing: pre.markdown, options: [])
        var walker = HTMLWalker(meta: pre, directory: documentDirectory)
        walker.keepLineBreaks = keepLineBreaks
        walker.renderDocument(document)
        walker.renderFootnotes()
        return decorate(walker.result)
    }

    /// Highlight review placeholders and ==marks== in rendered HTML (text only).
    static func decorate(_ html: String) -> String {
        var out = html.replacingOccurrences(
            of: Markua.placeholderPattern,
            with: "<span class=\"placeholder\">$0</span>",
            options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"==(?=\S)([^=<]+?)(?<=\S)=="#,
            with: "<mark>$1</mark>",
            options: .regularExpression)
        return out
    }

    /// Inline-only render (footnote bodies).
    static func inlineHTML(_ markdown: String) -> String {
        var walker = HTMLWalker(meta: MarkuaPreprocessor.Result(), directory: nil)
        walker.visit(Document(parsing: markdown))
        var s = walker.result.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: #"^<p[^>]*>"#, options: .regularExpression) { s.removeSubrange(r) }
        if s.hasSuffix("</p>") { s.removeLast(4) }
        return s
    }
}

// MARK: - Markua preprocessing

enum MarkuaPreprocessor {
    struct Result {
        var markdown = ""
        /// Attribute list found on a line by itself: line → attributes.
        var attributes: [Int: [String: String]] = [:]
        /// Blurb / aside class for a blockquote starting on that line.
        var blurbClass: [Int: String] = [:]
        /// {pagebreak}, {frontmatter}, … by line.
        var directives: [(line: Int, name: String)] = []
        /// Footnotes in reference order: (id, number, markdown text).
        var footnotes: [(id: String, number: Int, text: String)] = []
    }

    private static let directiveNames: Set<String> = ["pagebreak", "frontmatter", "mainmatter", "backmatter"]
    private static let blockOpen = try! NSRegularExpression(pattern: #"^\{(aside|blurb|blockquote)\b([^}]*)\}$"#)
    private static let blockClose = try! NSRegularExpression(pattern: #"^\{/(aside|blurb|blockquote)\}$"#)
    private static let footnoteDef = try! NSRegularExpression(pattern: #"^\[\^\^?([^\]\s]+)\]:[ \t]?(.*)$"#)
    private static let footnoteRef = try! NSRegularExpression(pattern: #"\[\^\^?([^\]\s]+)\](?!:)"#)
    private static let spanAttributes = try! NSRegularExpression(pattern: #"\]\{[^}\n]*\}"#)

    static func process(_ text: String) -> Result {
        var r = Result()
        var out: [String] = []
        let lines = text.components(separatedBy: "\n")
        var fence: String?
        var openBlock: String?          // class of a {blurb}/{aside} block in progress
        var openBlockHasContent = false
        var previousBlurbPrefix: String?
        var currentFootnote: String?
        var defs: [String: String] = [:]
        var numbers: [String: Int] = [:]
        var order: [String] = []

        for (i, raw) in lines.enumerated() {
            let n = i + 1
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let ns = trimmed as NSString
            let full = NSRange(location: 0, length: ns.length)

            // Fenced code passes through untouched.
            if let f = fence {
                if trimmed.hasPrefix(f) { fence = nil }
                out.append(openBlock != nil ? "> " + line : line)
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                out.append(openBlock != nil ? "> " + line : line)
                continue
            }

            // Footnote definition (and its indented continuation lines).
            if let m = footnoteDef.firstMatch(in: trimmed, range: full) {
                let id = ns.substring(with: m.range(at: 1))
                defs[id] = ns.substring(with: m.range(at: 2))
                currentFootnote = id
                out.append("")
                continue
            }
            if let id = currentFootnote {
                if line.hasPrefix("    ") || line.hasPrefix("\t") {
                    defs[id, default: ""] += " " + trimmed
                    out.append("")
                    continue
                }
                currentFootnote = nil
            }

            // {aside} / {blurb, class: warning} … {/blurb}
            if let open = openBlock {
                if blockClose.firstMatch(in: trimmed, range: full) != nil {
                    openBlock = nil
                    out.append("")
                    continue
                }
                if !openBlockHasContent {
                    r.blurbClass[n] = open
                    openBlockHasContent = true
                }
                out.append("> " + line)
                continue
            }
            if let m = blockOpen.firstMatch(in: trimmed, range: full) {
                let kind = ns.substring(with: m.range(at: 1))
                let attrs = Markua.parseAttributes("{" + ns.substring(with: m.range(at: 2)) + "}")
                openBlock = attrs["class"] ?? (kind == "aside" ? "aside" : kind == "blockquote" ? "quote" : "blurb")
                openBlockHasContent = false
                out.append("")
                continue
            }

            // Attribute list / directive on its own line.
            if Markua.attributeLine.firstMatch(in: trimmed, range: full) != nil {
                let attrs = Markua.parseAttributes(trimmed)
                if attrs.count == 1, let key = attrs.keys.first, directiveNames.contains(key) {
                    r.directives.append((n, key))
                } else {
                    r.attributes[n] = attrs
                }
                out.append("")
                continue
            }

            // A> W> T> … blurb lines → blockquote.
            var body = line
            if let m = Markua.blurbLine.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let prefix = (line as NSString).substring(with: m.range(at: 1))
                if previousBlurbPrefix != prefix {
                    // A class attribute directly above (`{class: warning}`) overrides the sugar.
                    r.blurbClass[n] = r.attributes[n - 1]?["class"] ?? Markua.blurbClass(forPrefix: prefix)
                }
                previousBlurbPrefix = prefix
                body = "> " + (line as NSString).substring(from: NSMaxRange(m.range))
            } else {
                previousBlurbPrefix = nil
            }

            // Footnote references → superscript links (inline HTML survives Markdown parsing).
            let bns = body as NSString
            var replaced = ""
            var last = 0
            for m in footnoteRef.matches(in: body, range: NSRange(location: 0, length: bns.length)) {
                let id = bns.substring(with: m.range(at: 1))
                if numbers[id] == nil { order.append(id); numbers[id] = order.count }
                let safe = htmlID(id)
                replaced += bns.substring(with: NSRange(location: last, length: m.range.location - last))
                replaced += "<sup class=\"fn\" id=\"fnref-\(safe)\"><a href=\"#fn-\(safe)\">\(numbers[id]!)</a></sup>"
                last = NSMaxRange(m.range)
            }
            replaced += bns.substring(from: last)

            // Markua span attributes `[text]{#id}` → drop the attribute part.
            replaced = spanAttributes.stringByReplacingMatches(
                in: replaced, range: NSRange(location: 0, length: (replaced as NSString).length), withTemplate: "]")
            out.append(replaced)
        }

        for id in defs.keys where numbers[id] == nil {
            order.append(id)
            numbers[id] = order.count
        }
        r.footnotes = order.map { ($0, numbers[$0]!, defs[$0] ?? "*(missing footnote)*") }
        r.markdown = out.joined(separator: "\n")
        return r
    }

    static func htmlID(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
    }
}

// MARK: - HTML

private func escape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.utf8.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        default: out.append(ch)
        }
    }
    return out
}

private struct HTMLWalker: MarkupWalker {
    var result = ""
    let meta: MarkuaPreprocessor.Result
    let directory: URL?
    private var inTableHead = false
    private var columnAlignments: [Table.ColumnAlignment?] = []
    private var cellIndex = 0
    private var usedSlugs: [String: Int] = [:]
    private var directiveIndex = 0
    /// Single newlines render as <br> (Markua / "what you typed") instead of joining lines.
    var keepLineBreaks = false

    init(meta: MarkuaPreprocessor.Result, directory: URL?) {
        self.meta = meta
        self.directory = directory
    }

    private func line(_ m: Markup) -> Int { m.range?.lowerBound.line ?? 0 }
    private func lineAttr(_ m: Markup) -> String {
        let l = line(m)
        return l > 0 ? " data-line=\"\(l)\"" : ""
    }

    /// Attribute list on the line(s) right above a block.
    private func attributes(above m: Markup) -> [String: String] {
        let l = line(m)
        return meta.attributes[l - 1] ?? meta.attributes[l - 2] ?? [:]
    }

    // MARK: Document

    mutating func renderDocument(_ document: Document) {
        for child in document.children {
            flushDirectives(before: line(child))
            visit(child)
        }
        flushDirectives(before: .max)
    }

    private mutating func flushDirectives(before line: Int) {
        while directiveIndex < meta.directives.count, meta.directives[directiveIndex].line < line {
            let d = meta.directives[directiveIndex]
            result += "<div class=\"directive\" data-line=\"\(d.line)\"><span>\(escape(d.name))</span></div>\n"
            directiveIndex += 1
        }
    }

    mutating func renderFootnotes() {
        guard !meta.footnotes.isEmpty else { return }
        result += "<section class=\"footnotes\"><hr><ol>\n"
        for fn in meta.footnotes {
            let id = MarkuaPreprocessor.htmlID(fn.id)
            result += "<li id=\"fn-\(id)\" value=\"\(fn.number)\">\(MarkdownRenderer.inlineHTML(fn.text)) <a class=\"back\" href=\"#fnref-\(id)\">↩</a></li>\n"
        }
        result += "</ol></section>\n"
    }

    mutating func defaultVisit(_ markup: Markup) { descendInto(markup) }

    // MARK: Blocks

    mutating func visitHeading(_ heading: Heading) {
        let attrs = attributes(above: heading)
        let slug = attrs["id"].map(MarkuaPreprocessor.htmlID) ?? makeSlug(heading.plainText)
        result += "<h\(heading.level) id=\"\(slug)\"\(lineAttr(heading))>"
        descendInto(heading)
        if attrs["sample"] == "true" { result += " <span class=\"badge\">sample</span>" }
        if let cls = attrs["class"] { result += " <span class=\"badge\">\(escape(cls))</span>" }
        result += "</h\(heading.level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        // A paragraph that is only an image renders as a Leanpub-style figure.
        if paragraph.childCount == 1, let img = paragraph.child(at: 0) as? Image {
            let attrs = attributes(above: paragraph)
            var figStyle = ""
            switch attrs["float"] {
            case "left", "inside": figStyle = "float:left;margin-right:1.2em;max-width:50%;"
            case "right", "outside": figStyle = "float:right;margin-left:1.2em;max-width:50%;"
            default: break
            }
            let align = attrs["align"] ?? "middle"
            result += "<figure class=\"align-\(escape(align))\" style=\"\(figStyle)\"\(lineAttr(paragraph))>"
            renderImage(img, attrs: attrs)
            let caption = attrs["caption"] ?? img.plainText
            if !caption.isEmpty { result += "<figcaption>\(escape(caption))</figcaption>" }
            result += "</figure>\n"
            return
        }
        result += "<p\(lineAttr(paragraph))>"
        descendInto(paragraph)
        result += "</p>\n"
    }

    mutating func visitBlockQuote(_ quote: BlockQuote) {
        if let cls = meta.blurbClass[line(quote)] {
            result += "<aside class=\"blurb \(escape(cls))\"\(lineAttr(quote))>\n"
            descendInto(quote)
            result += "</aside>\n"
        } else {
            result += "<blockquote\(lineAttr(quote))>\n"
            descendInto(quote)
            result += "</blockquote>\n"
        }
    }

    mutating func visitCodeBlock(_ code: CodeBlock) {
        let attrs = attributes(above: code)
        let langName = code.language ?? attrs["lang"] ?? attrs["format"]
        let lang = langName.map { " class=\"language-\(escape($0))\"" } ?? ""
        result += "<pre\(lineAttr(code))><code\(lang)>\(escape(code.code))</code></pre>\n"
    }

    mutating func visitThematicBreak(_ t: ThematicBreak) { result += "<hr\(lineAttr(t))>\n" }
    mutating func visitHTMLBlock(_ html: HTMLBlock) { result += html.rawHTML }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        let isTask = list.listItems.contains { $0.checkbox != nil }
        result += "<ul\(isTask ? " class=\"tasks\"" : "")\(lineAttr(list))>\n"
        descendInto(list)
        result += "</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        result += "<ol\(list.startIndex != 1 ? " start=\"\(list.startIndex)\"" : "")\(lineAttr(list))>\n"
        descendInto(list)
        result += "</ol>\n"
    }

    mutating func visitListItem(_ item: ListItem) {
        result += "<li\(item.checkbox != nil ? " class=\"task\"" : "")\(lineAttr(item))>"
        if let box = item.checkbox {
            result += "<input type=\"checkbox\" disabled\(box == .checked ? " checked" : "")> "
        }
        for child in item.children {
            if let p = child as? Paragraph, child.indexInParent == 0 {
                descendInto(p)
                if item.childCount > 1 { result += "\n" }
            } else {
                visit(child)
            }
        }
        result += "</li>\n"
    }

    mutating func visitTable(_ table: Table) {
        columnAlignments = table.columnAlignments
        result += "<table\(lineAttr(table))>\n"
        descendInto(table)
        result += "</table>\n"
    }

    mutating func visitTableHead(_ head: Table.Head) {
        inTableHead = true
        result += "<thead><tr>"
        cellIndex = 0
        descendInto(head)
        result += "</tr></thead>\n<tbody>\n"
        inTableHead = false
    }

    mutating func visitTableBody(_ body: Table.Body) {
        descendInto(body)
        result += "</tbody>\n"
    }

    mutating func visitTableRow(_ row: Table.Row) {
        result += "<tr\(lineAttr(row))>"
        cellIndex = 0
        descendInto(row)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ cell: Table.Cell) {
        let tag = inTableHead ? "th" : "td"
        var align = ""
        if cellIndex < columnAlignments.count, let a = columnAlignments[cellIndex] {
            switch a {
            case .left: align = " style=\"text-align:left\""
            case .center: align = " style=\"text-align:center\""
            case .right: align = " style=\"text-align:right\""
            }
        }
        result += "<\(tag)\(align)>"
        descendInto(cell)
        result += "</\(tag)>"
        cellIndex += 1
    }

    // MARK: Inline

    mutating func visitText(_ text: Text) { result += escape(text.string) }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) { result += keepLineBreaks ? "<br>\n" : "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) { result += "<br>\n" }
    mutating func visitEmphasis(_ emphasis: Emphasis) { wrap("em", emphasis) }
    mutating func visitStrong(_ strong: Strong) { wrap("strong", strong) }
    mutating func visitStrikethrough(_ s: Strikethrough) { wrap("del", s) }
    mutating func visitInlineCode(_ code: InlineCode) { result += "<code>\(escape(code.code))</code>" }
    mutating func visitInlineHTML(_ html: InlineHTML) { result += html.rawHTML }

    mutating func visitLink(_ link: Link) {
        result += "<a href=\"\(escape(link.destination ?? ""))\">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: Image) { renderImage(image, attrs: [:]) }

    private mutating func renderImage(_ image: Image, attrs: [String: String]) {
        let source = image.source ?? ""
        // Resolve Leanpub-style paths (resources/…, images by name) to an absolute local URL.
        var src = source
        if let url = ImageCache.resolve(source, relativeTo: directory) {
            src = LocalFileSchemeHandler.url(for: url).absoluteString
        }
        var style = ""
        if let w = attrs["width"], let f = Markua.fraction(w) { style += "width:\(Int(f * 100))%;" }
        if let h = attrs["height"], let f = Markua.fraction(h) { style += "max-height:\(Int(f * 100))vh;" }
        let alt = attrs["alt"] ?? image.plainText
        result += "<img src=\"\(escape(src))\" alt=\"\(escape(alt))\""
        if !style.isEmpty { result += " style=\"\(style)\"" }
        if let title = image.title, !title.isEmpty { result += " title=\"\(escape(title))\"" }
        result += ">"
    }

    private mutating func wrap(_ tag: String, _ markup: Markup) {
        result += "<\(tag)>"
        descendInto(markup)
        result += "</\(tag)>"
    }

    private mutating func makeSlug(_ text: String) -> String {
        let base = text.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : ($0 == " " || $0 == "-" ? "-" : "") }
            .joined()
        let n = usedSlugs[base, default: 0]
        usedSlugs[base] = n + 1
        return n == 0 ? base : "\(base)-\(n)"
    }
}
