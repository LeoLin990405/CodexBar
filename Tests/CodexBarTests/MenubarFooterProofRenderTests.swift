import AppKit
import SwiftUI
import XCTest
@testable import CodexBar
@testable import CodexBarCore

/// Fork-only render proof for the Menu Bar layout footer (#4665). Skips unless the proof
/// output directory is set; renders the production footer + editor states for all three styles.
@MainActor
final class MenubarFooterProofRenderTests: XCTestCase {
    func test_renderFooterStates() throws {
        guard let directoryPath = ProcessInfo.processInfo.environment["CODEXBAR_MENUBAR_FOOTER_PROOF_DIR"] else {
            throw XCTSkip("Set CODEXBAR_MENUBAR_FOOTER_PROOF_DIR to render footer proof images")
        }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            for style in MenuBarIconStyle.allCases {
                let settings = Self.makeSettingsStore(suite: "MenubarFooterProofRenderTests-\(style.rawValue)")
                settings.menuBarIconStyle = style
                let store = Self.makeUsageStore(settings: settings)
                let card = Self.proofCard(style: style, settings: settings, store: store, before: false)
                try Self.writePNG(AnyView(card), to: directory.appendingPathComponent("after-\(style.rawValue).png"))
            }

            // Before state: the shipped 0.79.0 footer stayed unconditional while the editor was
            // disabled for the default Critters style.
            let beforeSettings = Self.makeSettingsStore(suite: "MenubarFooterProofRenderTests-before")
            beforeSettings.menuBarIconStyle = .critters
            let beforeStore = Self.makeUsageStore(settings: beforeSettings)
            let beforeCard = Self.proofCard(style: .critters, settings: beforeSettings, store: beforeStore, before: true)
            try Self.writePNG(AnyView(beforeCard), to: directory.appendingPathComponent("before-critters.png"))
        }
    }

    @MainActor
    private static func proofCard(
        style: MenuBarIconStyle,
        settings: SettingsStore,
        store: UsageStore,
        before: Bool) -> some View
    {
        VStack(alignment: .leading, spacing: 10) {
            Text((before ? "Before (0.79.0)" : "After (this PR)") + " — Menu bar style: " + style.label)
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                MenuBarLayoutEditor(settings: settings, store: store)
                    .disabled(!MenuBarPane.layoutEditorEnabled(for: style))
                if before {
                    SettingsSectionFooter(L("menu_bar_layout_footer"))
                } else {
                    SettingsSectionFooter(MenuBarPane.layoutFooterText(for: style))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
        .padding(16)
        .frame(width: 720, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor
    private static func writePNG(_ view: AnyView, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "MenubarFooterProof", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not render \(url.lastPathComponent)",
            ])
        }
        try data.write(to: url)
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite, reset: true)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }

    private static func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }
}
