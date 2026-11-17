# Releasing longhand

1. **Bump the version** in `project.yml`: `MARKETING_VERSION` (e.g. `0.1.4`) and `CURRENT_PROJECT_VERSION`
   (+1 every release; Sparkle compares this build number to decide what's newer). Run `xcodegen`.
2. **Build, sign, notarize:** `scripts/release.sh`. It builds into `build.noindex/` (so Spotlight doesn't
   list a second longhand), re-signs Sparkle's helpers with the Developer ID (Xcode leaves them ad-hoc
   signed, which notarization rejects), notarizes, staples, and writes `dist/longhand-<version>.dmg`
   plus `dist/longhand.dmg`. Needs the `longhand-notary` notarytool keychain profile.
3. **Update `CHANGELOG.md`**, commit `Release <version>`, push.
4. **GitHub release:**
   `gh release create v<version> dist/longhand-<version>.dmg dist/longhand.dmg --target main --title "longhand <version>" --notes-file <notes>`
5. **Amore:** add a release with `dist/longhand-<version>.dmg` and the same notes. This puts it in the
   Sparkle appcast (`SUFeedURL` in `Config/Info.plist`) and behind the download link. **Skip this and
   nobody gets the update.**

Links:
- Download (latest stable): https://api.amore.computer/v1/apps/com.wajahatkarim.longhand/download
- Appcast: https://api.amore.computer/v1/apps/com.wajahatkarim.longhand/appcast.xml
- Website: https://shipkaro.dev/longhand (source: `shipkaro.dev/longhand/index.html`)
