# Running-app screenshots — CodexBar #4665 / PR #4680

Genuine screenshots of the **freshly built CodexBar app** running in a real Aqua session on a
GitHub-hosted `macos-26` runner. These are not offscreen `ImageRenderer` reconstructions: the app
was built from the PR head, launched, its real `NSWindow` put on screen, and captured with
`screencapture -l <windowNumber>` against the WindowServer.

- **Workflow run (green):** https://github.com/LeoLin990405/CodexBar/actions/runs/39592316839
- **Proof branch:** `proof/4680-app-proof` on the contributor fork, head `dd11a717c`
- **Upstream PR head under test:** `bc9c9c84b` — the proof branch only adds a `#if DEBUG`
  screenshot harness, a fork-only workflow, and an env-gated `Scripts/package_app.sh` option.
  `git diff bc9c9c84b..dd11a717c -- Sources/CodexBar/PreferencesMenuBarPane.swift
  Sources/CodexBar/Resources Tests CHANGELOG.md` is empty.
- **App:** debug build (the harness is `#if DEBUG`), ad-hoc signed, version `0.79.1`,
  bundle id `com.steipete.codexbar.debug`, git commit embedded in Info.plist: `dd11a717c`
  (proof head; parent chain includes the PR head `bc9c9c84b`).
- **Runner:** macOS 26.6.2, Xcode 26.6, Swift 6.3.3, 1024×768 Aqua session — `launchctl
  print gui/501` shows `type = login`, `session = Aqua`, WindowServer/Finder/Dock running.

## How these were produced

1. `CODEXBAR_SIGNING=adhoc CODEXBAR_PROOF_SKIP_WIDGET_EXTENSION=1 ./Scripts/package_app.sh debug`
   built and packaged the real `.app` bundle from source.
2. The app was launched with a fork-only, file-gated `#if DEBUG` harness. It opens the real
   Settings window on the **Menu Bar** pane, applies the requested `MenuBarIconStyle` through the
   production `SettingsStore`, waits for the real `NSWindow`, and writes a handshake JSON with the
   WindowServer window number plus the production `MenuBarPane.layoutEditorEnabled(for:)` /
   `layoutFooterText(for:)` values for the selected style.
3. The workflow captured the live window at six scroll offsets with
   `screencapture -x -l <windowNumber>`, then quit and relaunched the app for the next style.
4. The harness is only compiled in debug builds, only runs when `/tmp/codexbar-proof/` exists, and
   does not change any production code path: the footer copy and enabled/disabled state in the
   screenshots come from the PR's production helpers.

The images in this directory are the same captures as `raw/`, cropped to the window bounds. Files
ending in `-zoom.png` are 2× upscaled crops of the corresponding full-window capture for
legibility. No content was edited or composited.

## Files

| File | What it shows |
| --- | --- |
| `01-critters-style-selected.png` | Menu Bar pane with **Critters** selected; Layout editor disabled. |
| `02-critters-layout-explanation.png` | Scrolled to the Layout section: disabled editor + new explanation footer. |
| `03-critters-editor-footer-zoom.png` | 2× crop of the disabled editor controls + explanation footer. |
| `04-meter-bars-style-selected.png` | Menu Bar pane with **Meter bars** selected; Layout editor disabled. |
| `05-meter-bars-layout-explanation.png` | Scrolled to the Layout section: disabled editor + new explanation footer. |
| `06-meter-bars-editor-footer-zoom.png` | 2× crop of the disabled editor controls + explanation footer. |
| `07-icon-and-percent-style-selected.png` | Menu Bar pane with **Icon & percent** selected; Layout editor enabled. |
| `08-icon-and-percent-layout-instructions.png` | Scrolled to the Layout section: enabled editor + restored drag instructions. |
| `09-icon-and-percent-editor-footer-zoom.png` | 2× crop of the enabled editor controls + drag instructions. |
| `desktop-critters.png`, `desktop-meter-bars.png`, `desktop-icon-and-percent.png` | Full 1024×768 desktop captures (real menu bar + Dock) for each style. |
| `menubar-status-*.png` | 3× crops of the live menu bar status item for each style. |
| `raw/` | Unmodified `screencapture -l` PNGs (1120×770, includes window shadow) and the full-screen captures. |
| `evidence/marker-*.json` | Harness handshake JSON per style/scroll step: window number, WindowServer bounds, applied style, production footer text, editor enabled state, git commit. |
| `evidence/capture-trace.txt` | Workflow capture log excerpt (launch PIDs, window numbers per step). |
| `evidence/build-package.log` | Full build/package log (`swift build` + app packaging + ad-hoc codesign). |
