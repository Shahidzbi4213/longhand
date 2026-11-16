import AppKit

/// Image shown inline in the editor. `widthFraction` comes from a Leanpub `{width: 60%}` attribute line.
final class InlineImage {
    let image: NSImage
    let widthFraction: CGFloat?
    init(image: NSImage, widthFraction: CGFloat?) {
        self.image = image
        self.widthFraction = widthFraction
    }

    func displaySize(maxWidth: CGFloat) -> NSSize {
        ImageCache.displaySize(for: image, maxWidth: maxWidth, widthFraction: widthFraction)
    }
}

final class ImageCache {
    static let shared = ImageCache()
    private var images: [String: NSImage] = [:]
    private var misses: Set<String> = []

    /// Set by Workspace: the open folder, and every image in it by lowercase file name.
    static var workspaceRoot: URL?
    static var imageIndex: [String: URL] = [:]

    func image(at url: URL) -> NSImage? {
        let key = url.path
        if let img = images[key] { return img }
        if misses.contains(key) { return nil }
        guard let img = NSImage(contentsOf: url), img.isValid, img.size.width > 0 else {
            misses.insert(key)
            return nil
        }
        images[key] = img
        return img
    }

    func removeAll() {
        images.removeAll()
        misses.removeAll()
    }

    /// Resolve an image path the way both plain Markdown and Leanpub/Markua do:
    /// relative to the document, then `resources/` (Markua), `manuscript/resources/`, the folder root,
    /// `images/`, and finally any image in the workspace with the same file name.
    static func resolve(_ source: String, relativeTo directory: URL?) -> URL? {
        var src = source.trimmingCharacters(in: .whitespaces)
        if src.hasPrefix("<"), src.hasSuffix(">") { src = String(src.dropFirst().dropLast()) }
        if src.isEmpty || src.hasPrefix("http://") || src.hasPrefix("https://") || src.hasPrefix("data:") { return nil }
        if src.hasPrefix("file://") { return URL(string: src) }
        let decoded = src.removingPercentEncoding ?? src
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        if decoded.hasPrefix("~") { return URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath) }

        let fm = FileManager.default
        var candidates: [URL] = []
        if let directory { candidates.append(directory.appendingPathComponent(decoded)) }
        if let root = workspaceRoot {
            candidates += [
                root.appendingPathComponent("resources").appendingPathComponent(decoded),
                root.appendingPathComponent("manuscript/resources").appendingPathComponent(decoded),
                root.appendingPathComponent(decoded),
                root.appendingPathComponent("images").appendingPathComponent(decoded),
                root.appendingPathComponent("Images").appendingPathComponent(decoded),
                root.appendingPathComponent("manuscript").appendingPathComponent(decoded),
            ]
        }
        for url in candidates where fm.fileExists(atPath: url.path) {
            return url.standardizedFileURL
        }
        let name = (decoded as NSString).lastPathComponent.lowercased()
        return imageIndex[name]
    }

    /// Size an image is drawn at inside the editor. Shared by styler (spacing) and view (drawing).
    static func displaySize(for image: NSImage, maxWidth: CGFloat, widthFraction: CGFloat? = nil) -> NSSize {
        let maxHeight: CGFloat = 460
        var size = image.size
        if let f = widthFraction, f > 0 {
            let w = maxWidth * min(1, f)
            size = NSSize(width: w, height: size.height * w / size.width)
        }
        if size.width > maxWidth {
            size = NSSize(width: maxWidth, height: size.height * maxWidth / size.width)
        }
        if size.height > maxHeight {
            size = NSSize(width: size.width * maxHeight / size.height, height: maxHeight)
        }
        return NSSize(width: floor(size.width), height: floor(size.height))
    }
}

/// Leanpub / Markua shared bits used by both editor and preview.
enum Markua {
    /// `{key: value, key2: "v"}`, `{#id}`, `{width=60%}`, `{pagebreak}` → dictionary.
    static func parseAttributes(_ raw: String) -> [String: String] {
        var inner = raw.trimmingCharacters(in: .whitespaces)
        if inner.hasPrefix("{") { inner.removeFirst() }
        if inner.hasSuffix("}") { inner.removeLast() }
        var result: [String: String] = [:]
        for part in splitTopLevel(inner) {
            let p = part.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { continue }
            if p.hasPrefix("#") { result["id"] = String(p.dropFirst()); continue }
            let sep = p.firstIndex { $0 == ":" || $0 == "=" }
            if let sep {
                let key = p[..<sep].trimmingCharacters(in: .whitespaces).lowercased()
                var value = p[p.index(after: sep)...].trimmingCharacters(in: .whitespaces)
                if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
                if result[key] == nil { result[key] = value }
            } else {
                result[p.lowercased()] = "true"
            }
        }
        return result
    }

    private static func splitTopLevel(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        for ch in s {
            if ch == "\"" { inQuotes.toggle() }
            if ch == "," && !inQuotes { parts.append(current); current = "" } else { current.append(ch) }
        }
        parts.append(current)
        return parts
    }

    /// "60%" → 0.6
    static func fraction(_ value: String?) -> CGFloat? {
        guard let v = value?.trimmingCharacters(in: CharacterSet(charactersIn: "% \"")), let d = Double(v), d > 0 else { return nil }
        return CGFloat(min(d, 100) / 100)
    }

    static let attributeLine = try! NSRegularExpression(pattern: #"^[ \t]*\{[^{}]*\}[ \t]*$"#)
    /// `A>`, `B>`, `W>` … blurb / aside line prefixes.
    static let blurbLine = try! NSRegularExpression(pattern: #"^([ABCDEGIQTWX])>( ?)"#)

    static func blurbClass(forPrefix p: String) -> String {
        switch p {
        case "A": return "aside"
        case "C": return "center"
        case "D": return "discussion"
        case "E": return "error"
        case "I": return "information"
        case "Q": return "question"
        case "T": return "tip"
        case "W": return "warning"
        case "X": return "exercise"
        default: return "blurb"
        }
    }

    static func color(forClass cls: String) -> NSColor {
        switch cls {
        case "warning": return Palette.hex(0xE8A13A)
        case "tip": return Palette.hex(0x3FA66B)
        case "error": return Palette.hex(0xD9534F)
        case "information": return Palette.hex(0x3A8DDE)
        case "question", "exercise": return Palette.hex(0x8E6BD8)
        case "discussion": return Palette.hex(0x2BA3A3)
        default: return Palette.syntax
        }
    }

    /// Review placeholders: `[IMAGE: …]`, `[WAJAHAT: confirm]`, also `[IMAGE Jim Browning…]`, `[TODO …]`.
    static let placeholderPattern = #"\[(?:[A-Z][A-Z0-9 _\-]{1,40}:[^\]\n]*|(?:IMAGE|TODO|TK|NOTE|FIXME|WAJAHAT|CITE|LINK)\b[^\]\n]*)\]"#
    static let placeholder = try! NSRegularExpression(pattern: placeholderPattern)
}
