# Changelog

All notable changes to longhand. Versions match the [GitHub releases](https://github.com/wajahatkarim3/longhand/releases).

## 0.1.3 · 2026-11-17

- **Automatic updates** with [Sparkle](https://sparkle-project.org), served through [Amore](https://amore.computer). longhand checks for new versions by itself, and **longhand → Check for Updates…** checks on demand.
- Downloads (website and README) now go through Amore's link, which always serves the latest stable DMG.

## 0.1.2 · 2026-11-17

- **Open With longhand.** Finder's Open With, double-click, and dropping a file or folder on the Dock icon all work. A file opens inside its folder in the sidebar.
- **Plain-text mode for code and config files** (`.json`, `.yaml`, `.xml`, `.html`, `.css`, `.swift`, `.kt`, `.cpp`, `.py` and more): monospace, no Markdown styling or shortcuts, Return keeps indentation, Preview shows the source as-is. They're listed in the sidebar with a `</>` icon.
- Files that aren't valid UTF-8 are no longer opened, so autosave can't write garbled text over them.

## 0.1.1 · 2026-11-16

- Styled DMG installer window with a drag-to-Applications arrow.
- New About window with links to the author and the project.

## 0.1.0 · 2026-11-16

First release.

- Three views: Write (iA-style faded Markdown, images on the page), Split (source and preview scrolling together) and Preview.
- Folder sidebar for a whole manuscript, with autosave and live reload.
- `/` commands for headings, lists, quotes, code, tables, images, footnotes and Leanpub blurbs.
- Quiet bar that fades while you type, distraction-free fullscreen, focus and typewriter modes.
- Themes: Light, Paper, Sepia, Dark, System. Fonts: iA Writer Quattro/Duo/Mono, Lato, New York, Charter, Georgia.
- Leanpub / Markua syntax: blurbs, `{blurb}`/`{aside}`, `{width: 60%}` figures, `{pagebreak}`, footnotes.
- Review notes like `[IMAGE: …]` and `[TODO: …]` highlighted, counted and one click away.
