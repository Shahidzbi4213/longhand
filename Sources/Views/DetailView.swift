import SwiftUI

struct DetailView: View {
    @EnvironmentObject var workspace: Workspace

    @AppStorage(Pref.viewMode) private var mode: ViewMode = .write
    @AppStorage(Pref.theme) private var theme: AppTheme = .system
    @AppStorage(Pref.keepLineBreaks) private var keepLineBreaks = true
    @AppStorage(Pref.fontFamily) private var family: FontFamily = .quattro
    @AppStorage(Pref.fontSize) private var fontSize: Double = 16
    @AppStorage(Pref.lineWidth) private var lineWidth: LineWidth = .medium
    @AppStorage(Pref.focusMode) private var focusMode = false
    @AppStorage(Pref.typewriter) private var typewriter = false
    @AppStorage(Pref.hideSyntax) private var hideSyntax = false
    @AppStorage(Pref.inlineImages) private var inlineImages = true
    @AppStorage(Pref.showStatusBar) private var showStatusBar = true

    @State private var scrollBridge = ScrollBridge()

    var body: some View {
        let _ = (Palette.theme = theme)
        VStack(spacing: 0) {
            content
            if showStatusBar, let doc = workspace.document {
                QuietBar(document: doc)
            }
        }
        .background(Color(nsColor: Palette.background))
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }

    @ViewBuilder
    private var content: some View {
        if let doc = workspace.document {
            switch mode {
            case .write:
                EditorView(document: doc, config: config(wysiwyg: true, plain: doc.isPlainText), scrollBridge: nil)
                    .id(doc.url)
            case .split:
                HSplitView {
                    EditorView(document: doc, config: config(wysiwyg: false, plain: doc.isPlainText), scrollBridge: scrollBridge)
                        .frame(minWidth: 280)
                    PreviewView(document: doc, theme: theme, family: family, fontSize: CGFloat(fontSize), lineWidth: doc.isPlainText ? .wide : lineWidth, keepLineBreaks: keepLineBreaks, plainText: doc.isPlainText,
                                scrollBridge: scrollBridge, onOpenFile: workspace.openLinkedFile)
                        .frame(minWidth: 280)
                }
                .id(doc.url)
            case .preview:
                PreviewView(document: doc, theme: theme, family: family, fontSize: CGFloat(fontSize), lineWidth: doc.isPlainText ? .wide : lineWidth, keepLineBreaks: keepLineBreaks, plainText: doc.isPlainText,
                            scrollBridge: nil, onOpenFile: workspace.openLinkedFile)
                    .id(doc.url)
            }
        } else if let image = workspace.imageURL {
            ImagePreviewView(url: image)
        } else {
            EmptyStateView()
        }
    }

    private func config(wysiwyg: Bool, plain: Bool) -> EditorConfig {
        var c = EditorConfig()
        c.theme = theme
        c.family = family
        c.fontSize = CGFloat(fontSize)
        c.lineWidth = lineWidth
        c.hideSyntax = wysiwyg && hideSyntax
        c.inlineImages = wysiwyg && inlineImages
        c.focusMode = focusMode
        c.typewriter = typewriter
        c.scaleHeadings = true
        if plain {
            c.plainText = true
            c.hideSyntax = false
            c.inlineImages = false
            c.lineWidth = .wide   // code lines are long
        }
        return c
    }

    private var title: String {
        if let doc = workspace.document {
            // Code files keep their extension: main.cpp vs main.h matters.
            let name = doc.isPlainText ? doc.url.lastPathComponent : doc.url.deletingPathExtension().lastPathComponent
            return name + (doc.isDirty ? " •" : "")
        }
        if let img = workspace.imageURL { return img.lastPathComponent }
        return workspace.rootURL?.lastPathComponent ?? "longhand"
    }

    private var subtitle: String {
        let url = workspace.document?.url ?? workspace.imageURL
        guard let url else { return "" }
        return workspace.relativePath(of: url.deletingLastPathComponent())
    }
}

struct TextStats {
    let words: Int
    let placeholders: Int
    var minutes: Int { max(1, Int((Double(words) / 230).rounded())) }


    init(_ text: String) {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let isWordChar = CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "’"
            if isWordChar && !inWord { count += 1 }
            inWord = isWordChar
        }
        words = count
        placeholders = Markua.placeholder.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

struct ImagePreviewView: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            VStack(spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(info(image))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(32)
        } else {
            Text("Can't display \(url.lastPathComponent)").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func info(_ image: NSImage) -> String {
        let px = image.representations.first.map { "\($0.pixelsWide) × \($0.pixelsHigh) px" } ?? ""
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        return [url.lastPathComponent, px, ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)]
            .filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.cursor")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            if workspace.rootURL == nil {
                Text("Open a folder to start writing").foregroundStyle(.secondary)
                Button("Open Folder…") { workspace.showOpenPanel() }
                    .keyboardShortcut("o")
            } else {
                Text("Pick a file from the sidebar").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
