import SwiftUI
import Sparkle

/// Sparkle auto-updates. The feed (SUFeedURL) and signing key (SUPublicEDKey) live in Config/Info.plist;
/// releases are published to that feed through Amore.
final class Updater: ObservableObject {
    static let shared = Updater()

    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheckForUpdates = false

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// "Check for Updates…" menu item, disabled while a check is already running.
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
