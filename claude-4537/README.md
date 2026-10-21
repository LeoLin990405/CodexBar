# Running-app evidence — CodexBar #4537 / PR #4687

Genuine screenshots and runtime output from the **freshly built CodexBar app** running in a real
Aqua session on a GitHub-hosted `macos-26` runner. Not offscreen rendering: the app was built from
the PR head, launched, the real Settings window was put on screen, and it was captured with
`screencapture -l <windowNumber>`.

Scenario: a **successful Claude usage answer that reports no quota windows**
(`five_hour: null`, `seven_day: null` — Claude Free, issue #4537). The shipped app injects
`UsageSnapshot(primary: nil, secondary: nil, updatedAt: now)` for `.claude` through the existing
DEBUG `UsageStore` hooks, i.e. a fresh, successful, error-free snapshot with zero measured rate
windows and no cost surface. The Settings → Claude provider pane then shows **“Limits not
available”** in the provider subtitle and in the Usage section, instead of a relative timestamp.

- **Workflow run (green):** https://github.com/LeoLin990405/CodexBar/actions/runs/39601686948
- **Proof branch:** `proof/4687-app-proof` on the contributor fork, head `cbd723a09`
- **Upstream PR head under test:** `52a2dee42` (`fix/claude-empty-quota-availability`). The proof
  branch only adds a fork-only workflow, a `#if DEBUG` screenshot harness, DEBUG-gated wiring in
  `CodexbarApp.swift`, and an env-gated `Scripts/package_app.sh` option. Production paths are
  unchanged: `git diff 52a2dee42..cbd723a09 -- Sources/CodexBarCore Tests docs CHANGELOG.md
  Sources/CodexBar/PreferencesProvidersPane.swift` is empty.
- **App:** debug build (the harness is `#if DEBUG`), ad-hoc signed, version `0.79.1`,
  bundle id `com.steipete.codexbar.debug`, embedded git commit `cbd723a09` (proof head; parent
  chain includes PR head `52a2dee42`).
- **Runner:** macOS 26.6.2, Xcode 26.6, Swift 6.3.3, 1024×768 Aqua session
  (`launchctl print gui/501` → `type = login`, `session = Aqua`, WindowServer/Finder/Dock running).

## How it was produced

1. `CODEXBAR_SIGNING=adhoc CODEXBAR_PROOF_SKIP_WIDGET_EXTENSION=1 ./Scripts/package_app.sh debug`
   built and packaged the real `.app` from source.
2. The app was launched with a fork-only, file-gated `#if DEBUG` harness. It injects the
   quota-less successful snapshot for `.claude`, opens the real Settings window on the Claude
   provider pane, and writes a handshake JSON with the WindowServer window number plus the
   production `ProvidersPane.providerSubtitle(_:)`, `providerSidebarSubtitle(_:)` and menu-card
   placeholder values.
3. The workflow captured the live window with `screencapture -x -l <windowNumber>` and printed
   the harness runtime evidence into the job log (redacted: no cookies, credentials, tokens, or
   personal account data are touched — the runner starts with no Claude configuration).
4. Disclaimer: the CI runner has no Claude CLI/credentials, so the harness forces the provider's
   enabled presentation (`settings.providerEnablement[.claude] = true`) to render the pane the way
   a configured user sees it. The snapshot, footer, subtitle and availability values all come from
   production code; only the provider-enabled toggle state is forced.

Images in this directory are the unmodified `screencapture -l` captures (1120×770 incl. window
shadow, in `raw/`) cropped to the window bounds; the `-zoom.png` files are 2× upscaled crops of
the same captures for legibility. No content was edited or composited.

## Files

| File | What it shows |
| --- | --- |
| `01-claude-quoteless-providers-pane.png` | Settings → Claude pane for the quota-less successful answer: provider subtitle **“claude not detected • Limits not available”**, Usage section **“Limits not available”**, provider enabled. |
| `02-provider-subtitle-zoom.png` | 2× crop of the provider header: `Claude` / `claude not detected • Limits not available`. |
| `03-usage-section-zoom.png` | 2× crop of the Usage section: `Limits not available`. |
| `04-claude-quoteless-providers-pane-scrolled.png` | Same window scrolled to the connection/advanced settings. |
| `05-desktop.png` | Full 1024×768 desktop capture (real menu bar + Dock, app running). |
| `raw/` | Unmodified `screencapture -l` PNGs (step 0/1 windows) and the full-screen capture. |
| `evidence/marker-step0.json`, `marker-step1.json` | Handshake JSON: injected snapshot shape (primary/secondary nil, 0 measured windows, providerCost nil, relative description “just now”), `knownLimitsAvailability` before/after (nil — cleared by the successful path), resolved availability `unavailable`, production subtitle strings, WindowServer window number/bounds, git commit. |
| `evidence/runtime-evidence.txt` | Harness runtime evidence exactly as printed by the built app. |
| `evidence/app-claude-quota-less.log` | App stdout (harness runtime output). |
| `evidence/capture-trace.txt` | Workflow capture trace excerpt with the runtime evidence lines and markers. |
| `evidence/build-package.log` | Full build/package log (`swift build` + app packaging + ad-hoc codesign). |
