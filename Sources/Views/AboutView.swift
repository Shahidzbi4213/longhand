import SwiftUI

/// Custom About window: app, author, links, and "made with ♥ by shipkaro".
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.top, 8)

            Text("longhand")
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 6)
            Text(version)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text("A quiet Markdown editor for writing books.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Divider().padding(.vertical, 16)

            VStack(spacing: 3) {
                Text("Created by **Wajahat Karim**")
                    .font(.system(size: 13))
                Text("Google Developer Expert for Android")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                link("Website", "https://wajahatkarim.com")
                dot
                link("X", "https://x.com/WajahatKarim")
                dot
                link("LinkedIn", "https://linkedin.com/in/wajahatkarim")
                dot
                link("YouTube", "https://youtube.com/c/wajahatkarim3")
                dot
                link("GitHub", "https://github.com/wajahatkarim3")
            }
            .font(.system(size: 12))
            .padding(.top, 10)

            HStack(spacing: 6) {
                link("longhand on GitHub", "https://github.com/wajahatkarim3/longhand")
                dot
                link("RemoteKaro", "https://remotekaro.com")
            }
            .font(.system(size: 12))
            .padding(.top, 6)

            Link(destination: URL(string: "https://shipkaro.dev")!) {
                HStack(spacing: 5) {
                    Text("made with")
                        .foregroundStyle(.secondary)
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("by")
                        .foregroundStyle(.secondary)
                    Text("shipkaro")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if let key = NSImage(named: "shipkaro-key") {
                        Image(nsImage: key)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 18, height: 16)
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.quaternary.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help("shipkaro.dev")
            .padding(.top, 18)

            Text("© 2026 Wajahat Karim · MIT License")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 22)
        .frame(width: 380)
    }

    private var dot: some View {
        Text("·").foregroundStyle(.tertiary)
    }

    private func link(_ title: String, _ url: String) -> some View {
        Link(title, destination: URL(string: url)!)
            .foregroundStyle(Color.accentColor)
    }
}
