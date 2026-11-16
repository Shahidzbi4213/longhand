import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var workspace: Workspace
    @State private var query = ""
    @AppStorage(Pref.theme) private var theme: AppTheme = .system

    var body: some View {
        Group {
            if workspace.rootURL == nil {
                VStack(spacing: 12) {
                    Text("No folder open").foregroundStyle(.secondary)
                    Button("Open Folder…") { workspace.showOpenPanel() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.isEmpty {
                List(selection: $workspace.selection) {
                    if let root = workspace.rootURL {
                        Section(root.lastPathComponent) {
                            OutlineGroup(workspace.tree, children: \.children) { node in
                                row(node)
                            }
                        }
                    }
                }
            } else {
                List(selection: $workspace.selection) {
                    ForEach(searchResults) { node in
                        VStack(alignment: .leading, spacing: 1) {
                            Label(node.name, systemImage: node.kind.symbol)
                            Text(workspace.relativePath(of: node.url.deletingLastPathComponent()))
                                .font(.caption).foregroundStyle(.tertiary)
                                .padding(.leading, 26)
                        }
                        .tag(node.url)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(theme.colors.sidebar == nil ? .automatic : .hidden)
        .background(theme.colors.sidebar.map { Color(nsColor: Palette.hex($0)) } ?? Color.clear)
        .searchable(text: $query, placement: .sidebar, prompt: "Filter files")
        .frame(minWidth: 200)
    }

    private var searchResults: [FileNode] {
        let q = query.lowercased()
        return workspace.allFiles.filter {
            workspace.relativePath(of: $0.url).lowercased().contains(q)
        }
    }

    @ViewBuilder
    private func row(_ node: FileNode) -> some View {
        Label {
            Text(displayName(node)).lineLimit(1).truncationMode(.middle)
        } icon: {
            Image(systemName: node.kind.symbol)
                .foregroundStyle(node.kind == .folder ? Color.accentColor : .secondary)
        }
        .tag(node.url)
        .contextMenu {
            Button("Reveal in Finder") { workspace.revealInFinder(node.url) }
            if node.kind == .folder {
                Button("New Markdown File") { workspace.createMarkdownFile(in: node.url) }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
        }
    }

    /// Hide ".md" for a cleaner, writer-focused list.
    private func displayName(_ node: FileNode) -> String {
        node.kind == .markdown && node.url.pathExtension.lowercased() == "md"
            ? node.url.deletingPathExtension().lastPathComponent
            : node.name
    }
}
