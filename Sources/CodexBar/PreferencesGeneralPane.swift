import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct GeneralPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text("系统")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: "登录时启动",
                        subtitle: "Mac 启动后自动打开 CodexBar。",
                        binding: self.$settings.launchAtLogin)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("用量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(isOn: self.$settings.costUsageEnabled) {
                                Text("显示费用摘要")
                                    .font(.body)
                            }
                            .toggleStyle(.checkbox)

                            Text("读取本地用量日志，并在菜单中显示今天和最近 30 天的费用。")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)

                            if self.settings.costUsageEnabled {
                                Text("自动刷新：每小时 · 超时：10 分钟")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)

                                self.costStatusLine(provider: .claude)
                                self.costStatusLine(provider: .codex)
                            }
                        }
                    }
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("自动化")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("刷新频率")
                                    .font(.body)
                                Text("CodexBar 在后台轮询各服务的频率。")
                                    .font(.footnote)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Picker("刷新频率", selection: self.$settings.refreshFrequency) {
                                ForEach(RefreshFrequency.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }
                        if self.settings.refreshFrequency == .manual {
                            Text("自动刷新已关闭；请使用菜单里的“刷新”。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    PreferenceToggleRow(
                        title: "检查服务状态",
                        subtitle: "轮询 OpenAI/Claude 状态页，以及 Gemini/Antigravity 的 Google Workspace 状态，并在图标和菜单中提示故障。",
                        binding: self.$settings.statusChecksEnabled)
                    PreferenceToggleRow(
                        title: "会话额度通知",
                        subtitle: "5 小时会话额度耗尽或恢复可用时通知你。",
                        binding: self.$settings.sessionQuotaNotificationsEnabled)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    HStack {
                        Spacer()
                        Button("退出 CodexBar") { NSApp.terminate(nil) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func costStatusLine(provider: UsageProvider) -> some View {
        let name = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName

        guard provider == .claude || provider == .codex else {
            return Text("\(name)：不支持")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }

        if self.store.isTokenRefreshInFlight(for: provider) {
            let elapsed: String = {
                guard let startedAt = self.store.tokenLastAttemptAt(for: provider) else { return "" }
                let seconds = max(0, Date().timeIntervalSince(startedAt))
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = seconds < 60 ? [.second] : [.minute, .second]
                formatter.unitsStyle = .abbreviated
                return formatter.string(from: seconds).map { " (\($0))" } ?? ""
            }()
            return Text("\(name)：正在获取…\(elapsed)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        if let snapshot = self.store.tokenSnapshot(for: provider) {
            let updated = UsageFormatter.updatedString(from: snapshot.updatedAt)
            let cost = snapshot.last30DaysCostUSD.map { UsageFormatter.usdString($0) } ?? "—"
            return Text("\(name)：\(updated) · 30 天 \(cost)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        if let error = self.store.tokenError(for: provider), !error.isEmpty {
            let truncated = UsageFormatter.truncatedSingleLine(error, max: 120)
            return Text("\(name)：\(truncated)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        if let lastAttempt = self.store.tokenLastAttemptAt(for: provider) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .abbreviated
            let when = rel.localizedString(for: lastAttempt, relativeTo: Date())
            return Text("\(name)：上次尝试 \(when)")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        return Text("\(name)：暂无数据")
            .font(.footnote)
            .foregroundStyle(.tertiary)
    }
}
