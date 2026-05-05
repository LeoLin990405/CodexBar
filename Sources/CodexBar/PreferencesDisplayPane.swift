import CodexBarCore
import SwiftUI

@MainActor
struct DisplayPane: View {
    private static let maxOverviewProviders = SettingsStore.mergedOverviewProviderLimit

    @State private var isOverviewProviderPopoverPresented = false
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(contentSpacing: 12) {
                    Text("菜单栏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: "合并图标",
                        subtitle: "使用单个菜单栏图标，并在菜单中切换服务。",
                        binding: self.$settings.mergeIcons)
                    PreferenceToggleRow(
                        title: "切换器显示图标",
                        subtitle: "在切换器中显示服务图标；关闭后显示每周进度线。",
                        binding: self.$settings.switcherShowsIcons)
                        .disabled(!self.settings.mergeIcons)
                        .opacity(self.settings.mergeIcons ? 1 : 0.5)
                    PreferenceToggleRow(
                        title: "显示最常用服务",
                        subtitle: "菜单栏自动显示最接近额度上限的服务。",
                        binding: self.$settings.menuBarShowsHighestUsage)
                        .disabled(!self.settings.mergeIcons)
                        .opacity(self.settings.mergeIcons ? 1 : 0.5)
                    PreferenceToggleRow(
                        title: "菜单栏显示百分比",
                        subtitle: "用服务品牌图标和百分比替代进度条图标。",
                        binding: self.$settings.menuBarShowsBrandIconWithPercent)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("显示模式")
                                .font(.body)
                            Text("选择菜单栏显示内容（节奏会显示实际用量与预期用量的对比）。")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Picker("显示模式", selection: self.$settings.menuBarDisplayMode) {
                            ForEach(MenuBarDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 200)
                    }
                    .disabled(!self.settings.menuBarShowsBrandIconWithPercent)
                    .opacity(self.settings.menuBarShowsBrandIconWithPercent ? 1 : 0.5)
                }

                Divider()

                SettingsSection(contentSpacing: 12) {
                    Text("菜单内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    PreferenceToggleRow(
                        title: "按已用量显示",
                        subtitle: "进度条随额度消耗而填充，而不是显示剩余额度。",
                        binding: self.$settings.usageBarsShowUsed)
                    PreferenceToggleRow(
                        title: "用具体时间显示重置",
                        subtitle: "显示具体重置时刻，而不是倒计时。",
                        binding: self.$settings.resetTimesShowAbsolute)
                    PreferenceToggleRow(
                        title: "显示 Credits 和额外用量",
                        subtitle: "在菜单中显示 Codex Credits 和 Claude Extra 用量区域。",
                        binding: self.$settings.showOptionalCreditsAndExtraUsage)
                    PreferenceToggleRow(
                        title: "显示所有 token 账号",
                        subtitle: "在菜单中展开所有 token 账号；关闭后显示账号切换栏。",
                        binding: self.$settings.showAllTokenAccountsInMenu)
                    self.overviewProviderSelector
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onAppear {
                self.reconcileOverviewSelection()
            }
            .onChange(of: self.settings.mergeIcons) { _, isEnabled in
                guard isEnabled else {
                    self.isOverviewProviderPopoverPresented = false
                    return
                }
                self.reconcileOverviewSelection()
            }
            .onChange(of: self.activeProvidersInOrder) { _, _ in
                if self.activeProvidersInOrder.isEmpty {
                    self.isOverviewProviderPopoverPresented = false
                }
                self.reconcileOverviewSelection()
            }
        }
    }

    private var overviewProviderSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text("概览页服务")
                    .font(.body)
                Spacer(minLength: 0)
                if self.showsOverviewConfigureButton {
                    Button("配置…") {
                        self.isOverviewProviderPopoverPresented = true
                    }
                    .offset(y: 1)
                    .popover(isPresented: self.$isOverviewProviderPopoverPresented, arrowEdge: .bottom) {
                        self.overviewProviderPopover
                    }
                }
            }

            if !self.settings.mergeIcons {
                Text("启用“合并图标”后可配置概览页服务。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else if self.activeProvidersInOrder.isEmpty {
                Text("没有可用于概览页的已启用服务。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                Text(self.overviewProviderSelectionSummary)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }

    private var overviewProviderPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择服务")
                .font(.headline)
            Text("概览行始终按服务顺序排列。")
                .font(.footnote)
                .foregroundStyle(.tertiary)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(self.activeProvidersInOrder, id: \.self) { provider in
                        Toggle(
                            isOn: Binding(
                                get: { self.overviewSelectedProviders.contains(provider) },
                                set: { shouldSelect in
                                    self.setOverviewProviderSelection(provider: provider, isSelected: shouldSelect)
                                })) {
                            Text(self.providerDisplayName(provider))
                                .font(.body)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .frame(width: 280)
    }

    private var activeProvidersInOrder: [UsageProvider] {
        self.store.enabledProviders()
    }

    private var overviewSelectedProviders: [UsageProvider] {
        self.settings.resolvedMergedOverviewProviders(
            activeProviders: self.activeProvidersInOrder,
            maxVisibleProviders: Self.maxOverviewProviders)
    }

    private var showsOverviewConfigureButton: Bool {
        self.settings.mergeIcons && !self.activeProvidersInOrder.isEmpty
    }

    private var overviewProviderSelectionSummary: String {
        let selectedNames = self.overviewSelectedProviders.map(self.providerDisplayName)
        guard !selectedNames.isEmpty else { return "未选择服务" }
        return selectedNames.joined(separator: ", ")
    }

    private func providerDisplayName(_ provider: UsageProvider) -> String {
        ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
    }

    private func setOverviewProviderSelection(provider: UsageProvider, isSelected: Bool) {
        _ = self.settings.setMergedOverviewProviderSelection(
            provider: provider,
            isSelected: isSelected,
            activeProviders: self.activeProvidersInOrder,
            maxVisibleProviders: Self.maxOverviewProviders)
    }

    private func reconcileOverviewSelection() {
        _ = self.settings.reconcileMergedOverviewSelectedProviders(
            activeProviders: self.activeProvidersInOrder,
            maxVisibleProviders: Self.maxOverviewProviders)
    }
}
