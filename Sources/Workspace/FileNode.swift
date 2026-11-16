import Foundation

enum FileKind {
    case folder, markdown, image

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdx", "txt"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp", "svg"]

    static func of(_ url: URL) -> FileKind? {
        let ext = url.pathExtension.lowercased()
        if markdownExtensions.contains(ext) { return .markdown }
        if imageExtensions.contains(ext) { return .image }
        return nil
    }

    var symbol: String {
        switch self {
        case .folder: return "folder"
        case .markdown: return "doc.text"
        case .image: return "photo"
        }
    }
}

struct FileNode: Identifiable, Hashable {
    let url: URL
    let kind: FileKind
    var children: [FileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    /// Flattened list of all non-folder descendants (used for search / quick open).
    var allFiles: [FileNode] {
        if kind != .folder { return [self] }
        return (children ?? []).flatMap(\.allFiles)
    }
}

enum FileTreeLoader {
    static let skippedFolders: Set<String> = ["node_modules", "build", "DerivedData", "Pods", ".build", "dist", "out"]

    static func load(_ directory: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var folders: [FileNode] = []
        var files: [FileNode] = []
        for url in items {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if skippedFolders.contains(url.lastPathComponent) { continue }
                let children = load(url)
                if !children.isEmpty {
                    folders.append(FileNode(url: url, kind: .folder, children: children))
                }
            } else if let kind = FileKind.of(url) {
                files.append(FileNode(url: url, kind: kind, children: nil))
            }
        }
        let sort: (FileNode, FileNode) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return folders.sorted(by: sort) + files.sorted(by: sort)
    }
}
