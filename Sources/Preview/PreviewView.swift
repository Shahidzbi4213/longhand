import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Serves local files to the preview: mdlocal://file/<absolute path>
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdlocal"

    static func url(for file: URL) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "file"
        c.path = file.standardizedFileURL.path
        return c.url!
    }

    static func baseURL(for directory: URL) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "file"
        c.path = directory.standardizedFileURL.path + "/"
        return c.url!
    }

    static func fileURL(from url: URL) -> URL? {
        guard url.scheme == scheme else { return nil }
        return URL(fileURLWithPath: url.path)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let file = Self.fileURL(from: url),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Avoids WKUserContentController retaining the coordinator.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}

struct PreviewView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var theme: AppTheme
    var family: FontFamily
    var fontSize: CGFloat
    var lineWidth: LineWidth
    var keepLineBreaks: Bool = true
    var plainText = false
    var scrollBridge: ScrollBridge?
    var onOpenFile: (URL) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let c = context.coordinator
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)
        config.userContentController.add(WeakMessageHandler(c), name: "scroll")
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = c
        c.web = web
        c.parent = self
        scrollBridge?.onEditorScroll = { [weak c] line in c?.sync(toLine: line) }
        c.update(force: true)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(force: false)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "scroll")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var parent: PreviewView?
        private var loadedDirectory: URL?
        private var loadedStyleKey = ""
        private var pageReady = false
        private var pendingHTML: String?
        private var lastText: String?
        private var lastBreaks = true
        private var renderWork: DispatchWorkItem?
        private var syncInFlight = false
        private var pendingLine: Double?

        func update(force: Bool) {
            guard let parent, let web else { return }
            let styleKey = "\(parent.theme.rawValue)-\(parent.family.rawValue)-\(parent.fontSize)-\(parent.lineWidth.rawValue)"
            if force || loadedDirectory != parent.document.directory || styleKey != loadedStyleKey {
                loadedDirectory = parent.document.directory
                loadedStyleKey = styleKey
                pageReady = false
                lastText = nil
                web.loadHTMLString(PreviewTemplate.page(theme: parent.theme, family: parent.family, fontSize: parent.fontSize, width: parent.lineWidth.points),
                                   baseURL: LocalFileSchemeHandler.baseURL(for: parent.document.directory))
            }
            let text = parent.document.text
            let breaks = parent.keepLineBreaks
            if breaks != lastBreaks { lastBreaks = breaks; lastText = nil }
            guard text != lastText else { return }
            let first = lastText == nil
            lastText = text
            let directory = parent.document.directory
            let plain = parent.plainText
            renderWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.push(plain ? MarkdownRenderer.sourceHTML(from: text)
                                 : MarkdownRenderer.html(from: text, documentDirectory: directory, keepLineBreaks: breaks))
            }
            renderWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (first ? 0 : 0.15), execute: work)
        }

        private func push(_ html: String) {
            guard pageReady, let web else { pendingHTML = html; return }
            guard let data = try? JSONSerialization.data(withJSONObject: [html]),
                  let json = String(data: data, encoding: .utf8) else { return }
            web.evaluateJavaScript("window.__render(\(json)[0])")
        }

        /// Editor → preview. Coalesced so fast scrolling never queues up JS calls.
        func sync(toLine line: Double) {
            guard pageReady, let web else { return }
            if syncInFlight { pendingLine = line; return }
            syncInFlight = true
            web.evaluateJavaScript("window.__syncLine(\(line))") { [weak self] _, _ in
                guard let self else { return }
                self.syncInFlight = false
                if let next = self.pendingLine {
                    self.pendingLine = nil
                    self.sync(toLine: next)
                }
            }
        }

        /// Preview → editor.
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "scroll", let line = (message.body as? NSNumber)?.doubleValue else { return }
            parent?.scrollBridge?.onPreviewScroll?(line)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            if let html = pendingHTML {
                pendingHTML = nil
                push(html)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                return decisionHandler(.allow)
            }
            decisionHandler(.cancel)
            let file = LocalFileSchemeHandler.fileURL(from: url)
            if let fragment = url.fragment, file.map({ $0.path.hasSuffix("/") || $0.pathExtension.isEmpty }) ?? false {
                let safe = fragment.replacingOccurrences(of: "'", with: "")
                webView.evaluateJavaScript("document.getElementById(decodeURIComponent('\(safe)'))?.scrollIntoView({behavior:'smooth', block:'center'})")
            } else if let file {
                if parent?.onOpenFile(file) != true { NSWorkspace.shared.open(file) }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

enum PreviewTemplate {
    static func themeCSS(_ theme: AppTheme) -> String {
        if theme == .system {
            return ":root { \(ThemeColors.light.css()) }\n@media (prefers-color-scheme: dark) { :root { \(ThemeColors.dark.css()) } }"
        }
        return ":root { \(theme.colors.css()) }"
    }

    static func page(theme: AppTheme, family: FontFamily, fontSize: CGFloat, width: CGFloat) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="color-scheme" content="\(theme == .system ? "light dark" : theme == .dark ? "dark" : "light")">
        <style>
        \(themeCSS(theme))
        \(FontFamily.fontFaceCSS())
        html { background: var(--bg); }
        body {
          margin: 0; padding: 60px 28px 50vh; color: var(--text); background: var(--bg);
          font: \(fontSize)px/1.65 \(family.cssStack);
          -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
        }
        #content { max-width: \(Int(width))px; margin: 0 auto; }
        h1, h2, h3, h4, h5, h6 { color: var(--heading); line-height: 1.3; margin: 1.6em 0 0.6em; font-weight: 700; }
        h1 { font-size: 1.6em; } h2 { font-size: 1.35em; } h3 { font-size: 1.18em; } h4 { font-size: 1.06em; }
        #content > :first-child { margin-top: 0; }
        p, ul, ol, blockquote, pre, table, figure, aside { margin: 0 0 1em; }
        a { color: var(--link); text-decoration: none; border-bottom: 1px solid color-mix(in srgb, var(--link) 35%, transparent); }
        strong { color: var(--heading); }
        blockquote { margin-left: 0; padding: 0.1em 0 0.1em 1.1em; border-left: 3px solid var(--rule); color: var(--muted); font-style: italic; }
        code { font: 0.9em ui-monospace, 'SF Mono', Menlo, monospace; background: var(--code-bg); color: var(--code); padding: 0.12em 0.35em; border-radius: 4px; }
        pre { background: var(--code-bg); padding: 14px 16px; border-radius: 8px; overflow-x: auto; line-height: 1.45; }
        pre code { background: none; padding: 0; color: var(--text); }
        .source { font: 0.88em/1.45 ui-monospace, 'SF Mono', Menlo, monospace; white-space: pre-wrap; overflow-wrap: anywhere; tab-size: 4; }
        hr { border: 0; height: 1px; background: var(--rule); margin: 2.4em 30%; }
        figure { margin-left: 0; margin-right: 0; }
        figure img { max-width: 100%; border-radius: 6px; display: block; margin: 0 auto; }
        figure.align-left img { margin-left: 0; } figure.align-right img { margin-right: 0; }
        figcaption { text-align: center; color: var(--muted); font-size: 0.85em; margin-top: 0.5em; }
        img { max-width: 100%; }
        table { border-collapse: collapse; width: 100%; font-size: 0.92em; }
        th, td { border-bottom: 1px solid var(--rule); padding: 6px 10px; text-align: left; vertical-align: top; }
        th { color: var(--heading); }
        li.task { list-style: none; }
        li.task input { margin: 0 0.45em 0 -1.35em; }
        li { margin: 0.2em 0; }
        .placeholder { background: var(--placeholder); color: var(--heading); padding: 0.1em 0.35em; border-radius: 4px; }
        mark { background: var(--mark); color: inherit; padding: 0 0.15em; border-radius: 3px; }
        /* Leanpub blurbs & asides */
        aside.blurb { --c: var(--muted); background: var(--blurb-bg); border-left: 3px solid var(--c); padding: 0.7em 1em; border-radius: 0 6px 6px 0; }
        aside.blurb > :last-child, blockquote > :last-child, li > :last-child { margin-bottom: 0; }
        aside.blurb::before { display: block; font: 600 0.72em -apple-system, sans-serif; letter-spacing: 0.06em; text-transform: uppercase; color: var(--c); margin-bottom: 0.3em; }
        aside.aside::before { content: "Aside"; }
        aside.warning { --c: #E8A13A; } aside.warning::before { content: "Warning"; }
        aside.tip { --c: #3FA66B; } aside.tip::before { content: "Tip"; }
        aside.error { --c: #D9534F; } aside.error::before { content: "Error"; }
        aside.information { --c: #3A8DDE; } aside.information::before { content: "Info"; }
        aside.question { --c: #8E6BD8; } aside.question::before { content: "Question"; }
        aside.exercise { --c: #8E6BD8; } aside.exercise::before { content: "Exercise"; }
        aside.discussion { --c: #2BA3A3; } aside.discussion::before { content: "Discussion"; }
        aside.center { text-align: center; border-left: 0; border-radius: 6px; }
        .directive { text-align: center; margin: 2em 0; border-top: 1px dashed var(--rule); height: 0; }
        .directive span { position: relative; top: -0.75em; background: var(--bg); padding: 0 0.6em; font: 600 0.7em -apple-system, sans-serif; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); }
        .badge { font: 600 0.45em -apple-system, sans-serif; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); border: 1px solid var(--rule); border-radius: 4px; padding: 0.15em 0.5em; vertical-align: middle; }
        sup.fn a { border: 0; font-size: 0.75em; padding: 0 0.1em; }
        .footnotes { font-size: 0.85em; color: var(--muted); margin-top: 3em; }
        .footnotes hr { margin: 0 0 1.5em; width: 30%; }
        .footnotes a.back { border: 0; }
        ::selection { background: color-mix(in srgb, var(--accent) 25%, transparent); }
        </style>
        <script>
        (function () {
          let anchors = null;
          let suppressUntil = 0;
          let ticking = false;

          function collect() {
            anchors = [];
            let lastY = -1;
            const els = document.querySelectorAll('[data-line]');
            for (const el of els) {
              const l = +el.dataset.line;
              const y = el.getBoundingClientRect().top + window.scrollY;
              anchors.push({ l, y });
            }
            anchors.sort((a, b) => a.l - b.l);
            // keep y monotonic so interpolation never goes backwards
            for (const a of anchors) { if (a.y < lastY) a.y = lastY; lastY = a.y; }
          }
          function maxScroll() { return document.documentElement.scrollHeight - window.innerHeight; }
          function yForLine(L) {
            if (!anchors) collect();
            if (L >= 1e8) return maxScroll();
            if (L <= 1 || anchors.length === 0) return 0;
            let a = null, b = null;
            for (const x of anchors) { if (x.l <= L) a = x; else { b = x; break; } }
            if (!a) return 0;
            if (!b) return a.y;
            return a.y + (b.y - a.y) * (L - a.l) / (b.l - a.l);
          }
          function lineForY(Y) {
            if (!anchors) collect();
            if (Y <= 1 || anchors.length === 0) return 0;
            if (Y >= maxScroll() - 1) return 1e9;
            let a = null, b = null;
            for (const x of anchors) { if (x.y <= Y) a = x; else { b = x; break; } }
            if (!a) return 0;
            if (!b || b.y === a.y) return a.l;
            return a.l + (b.l - a.l) * (Y - a.y) / (b.y - a.y);
          }

          window.__render = function (html) {
            document.getElementById('content').innerHTML = html;
            anchors = null;
            for (const img of document.images) img.addEventListener('load', () => { anchors = null; });
          };
          window.__syncLine = function (L) {
            suppressUntil = Date.now() + 250;
            window.scrollTo(0, Math.max(0, yForLine(L)));
          };
          window.addEventListener('resize', () => { anchors = null; });
          window.addEventListener('scroll', () => {
            if (Date.now() < suppressUntil || ticking) return;
            ticking = true;
            requestAnimationFrame(() => {
              ticking = false;
              if (Date.now() < suppressUntil) return;
              window.webkit.messageHandlers.scroll.postMessage(lineForY(window.scrollY));
            });
          }, { passive: true });
        })();
        </script>
        </head><body><article id="content"></article></body></html>
        """
    }
}
