import Foundation
import Combine

final class MarkdownDocument: ObservableObject {
    let url: URL
    @Published private(set) var text: String
    @Published private(set) var isDirty = false
    /// Bumped when the text is replaced from disk, so the editor knows to reload.
    @Published private(set) var revision = 0

    private var lastKnownModDate: Date?
    private var autosave: DispatchWorkItem?

    init?(url: URL) {
        // Refuse binary / non-UTF-8 files: decoding them lossily and autosaving would overwrite the original bytes.
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
        self.url = url
        self.text = text
        self.lastKnownModDate = Self.modDate(url)
    }

    var directory: URL { url.deletingLastPathComponent() }

    /// Code/config/other text files get plain-text mode: no Markdown styling, source preview.
    var isPlainText: Bool { FileKind.of(url) != .markdown }

    /// Called by the editor on every keystroke.
    func editorDidChange(_ newText: String) {
        guard newText != text else { return }
        text = newText
        isDirty = true
        scheduleAutosave()
    }

    func save() {
        autosave?.cancel()
        guard isDirty else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            lastKnownModDate = Self.modDate(url)
            isDirty = false
        } catch {
            NSLog("longhand: save failed for \(url.path): \(error)")
        }
    }

    /// Reload if the file was changed by someone else and we have no unsaved edits.
    func reloadIfChangedOnDisk() {
        guard !isDirty, let date = Self.modDate(url), date != lastKnownModDate,
              let data = try? Data(contentsOf: url), let newText = String(data: data, encoding: .utf8) else { return }
        lastKnownModDate = date
        if newText != text {
            text = newText
            revision += 1
        }
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        autosave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private static func modDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
