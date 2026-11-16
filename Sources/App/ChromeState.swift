import AppKit
import SwiftUI

/// Window-level UI state shared by the editor, bars and commands.
final class ChromeState: ObservableObject {
    static let shared = ChromeState()

    /// The quiet bar hides while you type and comes back when the mouse moves.
    @Published private(set) var barVisible = true
    /// Sidebar + toolbar + bar hidden, window fullscreen.
    @Published var distractionFree = false

    private var lastTyped = Date.distantPast
    private var monitor: Any?
    private var keyMonitor: Any?

    private init() {}

    func typed() {
        lastTyped = Date()
        if barVisible {
            withAnimation(.easeOut(duration: 0.6)) { barVisible = false }
        }
    }

    func revealBar() {
        // Ignore tiny trackpad jitter right after a keystroke.
        guard !barVisible, Date().timeIntervalSince(lastTyped) > 0.6 else { return }
        withAnimation(.easeIn(duration: 0.25)) { barVisible = true }
    }

    func installMouseMonitor() {
        guard monitor == nil else { return }
        for w in NSApp.windows { w.acceptsMouseMovedEvents = true }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .scrollWheel]) { [weak self] e in
            self?.revealBar()
            return e
        }
        // ⌘⇧D handled here (not only via the menu) so it works whatever has focus:
        // editor, preview web view, sidebar — and while the toolbar/menu bar is hidden.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == [.command, .shift], e.charactersIgnoringModifiers?.lowercased() == "d" {
                self?.toggleDistractionFree()
                return nil
            }
            return e
        }
    }

    func toggleDistractionFree() {
        withAnimation(.easeInOut(duration: 0.3)) { distractionFree.toggle() }
    }

    /// Keep the window's fullscreen state in step with distraction-free mode.
    func syncFullScreen() {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        let isFull = window.styleMask.contains(.fullScreen)
        if isFull != distractionFree { window.toggleFullScreen(nil) }
    }
}
