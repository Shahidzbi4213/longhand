import SwiftUI

/// Freewrite-style bottom bar: plain words you can click, fading away while you type.
struct QuietBar: View {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject private var chrome = ChromeState.shared

    @AppStorage(Pref.fontSize) private var fontSize: Double = 16
    @AppStorage(Pref.fontFamily) private var family: FontFamily = .quattro
    @AppStorage(Pref.theme) private var theme: AppTheme = .system
    @State private var randomPicked = false

    private static let sizes: [Double] = [14, 16, 18, 20, 22, 24, 28]

    var body: some View {
        let stats = TextStats(document.text)
        HStack(spacing: 0) {
            item("\(Int(fontSize))px", help: "Text size: click to cycle (⌘+ bigger · ⌘− smaller · ⌘0 reset)") { cycleSize() }
            ForEach(FontFamily.quickPicks) { f in
                dot
                item(f.title, active: family == f && !randomPicked, help: "Font: \(f.title) (more in View › Font)") { family = f; randomPicked = false }
            }
            dot
            item(randomPicked ? "Random [\(family.title)]" : "Random", active: randomPicked, help: "Random font: try a different feel") { randomFont() }

            Spacer(minLength: 16)

            Text("\(stats.words.formatted()) words").help("Words in this file")
            dot
            Text("\(stats.minutes) min").help("Reading time at 230 words per minute")
            if stats.placeholders > 0 {
                dot
                QuietBarItem(title: "\(stats.placeholders) placeholder\(stats.placeholders == 1 ? "" : "s")",
                             active: false, tint: .orange) {
                    NotificationCenter.default.post(name: .jumpToNextPlaceholder, object: nil)
                }
                .help("Notes like [IMAGE: …] or [TODO: …] still in this file. Click to jump to the next one.")
            }
            dot
            item(theme.title, help: "Theme: click to cycle (⌥⌘1 Light · ⌥⌘2 Paper · ⌥⌘3 Sepia · ⌥⌘4 Dark)") { cycleTheme() }
            dot
            item(chrome.distractionFree ? "Exit Focus" : "Distraction-free", help: "Distraction-free: hide everything, go fullscreen (⌘⇧D)") { chrome.toggleDistractionFree() }
            dot
            Text(document.isDirty ? "Edited" : "Saved").help("Saves automatically (⌘S to save now)")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .opacity(chrome.barVisible ? 1 : 0)
        .allowsHitTesting(chrome.barVisible)
    }

    private var dot: some View {
        Text("•").padding(.horizontal, 7).foregroundStyle(.tertiary)
    }

    private func item(_ title: String, active: Bool = false, help: String = "", action: @escaping () -> Void) -> some View {
        QuietBarItem(title: title, active: active, action: action).help(help)
    }

    private func cycleSize() {
        let next = Self.sizes.first { $0 > fontSize } ?? Self.sizes[0]
        fontSize = next
    }

    private func cycleTheme() {
        let all = AppTheme.allCases
        theme = all[((all.firstIndex(of: theme) ?? 0) + 1) % all.count]
    }

    private func randomFont() {
        let options = FontFamily.allCases.filter { $0 != family }
        family = options.randomElement() ?? family
        randomPicked = true
    }
}

extension Notification.Name {
    static let jumpToNextPlaceholder = Notification.Name("longhand.jumpToNextPlaceholder")
}

private struct QuietBarItem: View {
    let title: String
    let active: Bool
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(tint ?? (active || hovering ? Color.primary : Color.secondary))
                .underline(hovering, color: .secondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
