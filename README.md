# CodexBar 中文汉化版

这是 [steipete/CodexBar](https://github.com/steipete/CodexBar) 的中文汉化 fork，由 Leo 维护，用来在 macOS 菜单栏里实时查看 Codex、Claude、Kimi、Qwen、Doubao、Trae、Xiaomi MiMo、z.ai、Cursor、Gemini、Copilot、OpenRouter 等 AI 工具的额度、余额、重置时间和服务状态。

这个 fork 的目标很明确：让中文用户打开应用后能直接看懂、直接配置、直接排查，不再在英文设置项、英文错误提示和 provider 名称之间来回猜。

<img src="codexbar.png" alt="CodexBar 菜单截图" width="520" />

## 这个 fork 是什么

- 中文汉化版 CodexBar：菜单栏、设置页、Overview、Provider 配置、错误提示、CLI 输出、测试快照里的用户可见文案都已中文化。
- 面向中文和亚洲常用 AI 服务：额外关注 Kimi、Qwen、Doubao、Trae、Xiaomi MiMo、z.ai、MiniMax、StepFun、Alibaba Coding Plan 等 provider。
- 保留原版隐私模型：默认本机解析；浏览器 Cookie、API key、OAuth 等数据源都需要用户主动配置。
- 仍然是轻量菜单栏应用：没有 Dock 图标，主要通过菜单栏图标、合并图标模式和 Overview 查看多个 provider。

## 与原始版本相比的主要区别

### 1. 全面中文化

- 应用菜单、设置页、Provider 列表、按钮、状态、错误提示改为中文。
- Overview、多 provider 切换、余额/额度说明、刷新状态、登录提示都使用中文表达。
- CLI 输出中的状态、账号、错误、用量字段也改成中文。
- 保留必要技术词和品牌名，例如 `API key`、`Cookie`、`Token`、Codex、Claude、Kimi、Qwen。

### 2. Provider 覆盖更偏中文用户

在原版 Codex、Claude、Cursor、Gemini、Copilot、z.ai、Kiro、Vertex AI、Augment、Amp、JetBrains AI、OpenRouter、Perplexity、Abacus AI 等基础上，这个 fork 额外补充或强化了这些方向：

- Qwen/千问：面向阿里云百炼/千问相关额度入口。
- Alibaba Coding Plan：阿里 Coding Plan，和 Qwen 不是同一个 provider，配置和数据源分开。
- Doubao/豆包：火山方舟/豆包相关订阅或额度入口。
- Trae：Trae 账号用量入口。
- Xiaomi MiMo：小米 MiMo 余额读取，支持浏览器 Cookie 或手动 Cookie。
- MiniMax：MiniMax Coding Plan 用量读取。
- Kimi：Kimi 周额度和 5 小时窗口。
- Kimi K2：Kimi K2 credit 用量。
- StepFun、Zenmux、AigoCode：补充国内/亚洲开发者常见平台入口。
- OpenCode、OpenCode Go、Kilo、Ollama、Warp：补充其他开发工具和额度来源。

部分 provider 受账号地区、服务端接口和登录状态影响，可能需要 Cookie、API key 或对应 CLI 已登录。遇到失败时优先看设置页里的中文错误提示。

### 3. Overview 和实时刷新更适合多账号/多服务

- Overview 会尽量显示所有已启用、可选择的 API/provider。
- 支持合并图标模式：多个 provider 可以合并到一个菜单栏入口，再在菜单里切换。
- 支持手动、1 分钟、2 分钟、5 分钟、15 分钟等刷新节奏。
- Provider 刷新策略有 CI 覆盖，避免后台刷新和实时显示逻辑回退。

### 4. 构建和发布使用 GitHub Actions

- macOS App 通过 GitHub Actions 打包为 zip artifact。
- Linux CLI 在 GitHub Actions 中构建 x64 和 arm64。
- CI 会跑 lint、实时刷新策略测试、Swift Test 和 Linux CLI smoke test。
- 本 fork 的 Release/Actions 产物优先于上游 Homebrew cask；上游 Homebrew 默认安装的是原版。

## 安装

### 系统要求

- macOS 14 Sonoma 或更新版本。

### 从本 fork 下载

优先使用本 fork 的构建产物：

- Releases: <https://github.com/LeoLin990405/CodexBar/releases>
- Actions artifacts: <https://github.com/LeoLin990405/CodexBar/actions>

如果你使用上游 Homebrew：

```bash
brew install --cask steipete/tap/codexbar
```

请注意：这个命令安装的是上游原版，不是 Leo 的中文汉化 fork。

### Linux CLI

Linux 只支持 CLI。可以从本 fork 的 GitHub Actions/Release 下载 `CodexBarCLI` 构建产物；上游 Homebrew 安装的仍是原版 CLI。

## 第一次使用

1. 打开 CodexBar。
2. 进入设置里的 Provider 页面。
3. 只启用你实际使用的 provider。
4. 按 provider 要求登录对应 CLI、浏览器账号、OAuth，或填写 API key/Cookie。
5. 如果 macOS 弹出 Keychain 或浏览器 Cookie 解密权限，请只授权给 `CodexBar.app`。

## 当前支持的 Provider

### 核心开发工具

- [Codex](docs/codex.md)：Codex CLI RPC/PTy，本地用量扫描，可选 OpenAI 网页 dashboard 增强。
- [Claude](docs/claude.md)：OAuth API、浏览器 Cookie、CLI PTY fallback，支持 session 和 weekly 用量。
- [Cursor](docs/cursor.md)：通过浏览器 session Cookie 获取 plan、usage 和 billing reset。
- [Gemini](docs/gemini.md)：使用 Gemini CLI 凭据的 OAuth quota API。账号或 TOS 状态异常时可能不可用。
- [Copilot](docs/copilot.md)：GitHub device flow 和 Copilot internal usage API。
- [OpenCode](docs/opencode.md)：OpenCode 网页 dashboard。
- OpenCode Go：OpenCode Go 相关用量入口。

### 中文和亚洲服务

- [Kimi](docs/kimi.md)：从 `kimi-auth` Cookie/JWT 读取 weekly quota 和 5 小时 rate limit。
- [Kimi K2](docs/kimi-k2.md)：API key 读取 credit 用量。
- [z.ai](docs/zai.md)：API token 读取 quota 和 MCP window；智谱/BigModel CN 入口可按配置切换。
- [Alibaba Coding Plan](docs/alibaba-coding-plan.md)：阿里 Coding Plan，支持浏览器 session 和 API key fallback。
- Qwen/千问：阿里云百炼/千问相关入口；和 Alibaba Coding Plan 分开配置。
- Doubao/豆包：火山方舟/豆包相关订阅和额度入口。
- Trae：Trae 账号用量入口。
- [Xiaomi MiMo](docs/mimo.md)：读取小米 MiMo 余额，支持自动浏览器 Cookie 或手动 Cookie。
- [MiniMax](docs/minimax.md)：MiniMax Coding Plan。
- StepFun：阶跃星辰平台入口。
- Zenmux：Zenmux 平台入口。
- AigoCode：AigoCode 平台入口。

### 其他 Provider

- [Antigravity](docs/antigravity.md)：本地 language server 探测，实验性。
- [Droid/Factory](docs/factory.md)：Factory cookies、WorkOS token flows。
- [Kilo](docs/kilo.md)：API token 或 CLI session auth。
- [Kiro](docs/kiro.md)：`kiro-cli` 的 `/usage` 输出解析。
- [Vertex AI](docs/vertexai.md)：Google ADC OAuth 和 Cloud Monitoring quota。
- [Augment](docs/augment.md)：浏览器 Cookie、session keepalive、credits 追踪。
- [Amp](docs/amp.md)：Amp settings 页面用量。
- [JetBrains AI](docs/jetbrains.md)：读取 JetBrains IDE 本地 quota XML。
- [Ollama](docs/ollama.md)：Ollama settings 页面用量。
- [Warp](docs/warp.md)：API token 读取 request limit。
- [OpenRouter](docs/openrouter.md)：API token 读取 credits 和 key rate limit。
- Perplexity：Perplexity 账号用量入口。
- [Abacus AI](docs/abacus.md)：ChatLLM/RouteLLM compute credits。

Provider 架构和新增 provider 方法见 [docs/provider.md](docs/provider.md)。

## 菜单栏图标

CodexBar 使用两条小进度条显示额度：

- 上方：5 小时/session 窗口；如果 weekly 不可用但 credits 可用，会切换为 credits 显示。
- 下方：weekly 窗口。
- 数据异常或过期会让图标变暗。
- 服务状态异常会显示状态标记。

## 隐私和权限

CodexBar 不会全盘扫描你的电脑。它只会在你启用对应功能后读取少量已知位置，例如：

- Provider CLI 的本地配置或输出。
- 浏览器 Cookie/local storage。
- 本地 JSONL 日志。
- Keychain 中由 CLI 或 CodexBar 保存的 token。

### macOS 权限说明

- Full Disk Access：仅在读取 Safari Cookie/local storage 时可能需要。Chrome/Firefox 或 CLI-only 模式通常可以绕开。
- Keychain access：用于读取 Chrome Safe Storage、Claude OAuth 凭据、z.ai/Copilot 等 token。
- Files & Folders：如果 provider CLI 自己访问项目目录，macOS 可能把权限提示显示给 CodexBar。

CodexBar 不需要 Screen Recording、Accessibility 或 Automation 权限，也不会保存你的账号密码。

## 开发

### 本地构建

```bash
swift build -c release
./Scripts/package_app.sh
CODEXBAR_SIGNING=adhoc ./Scripts/package_app.sh
open CodexBar.app
```

### 开发循环

```bash
./Scripts/compile_and_run.sh
```

### 格式和检查

```bash
./Scripts/lint.sh lint
./Scripts/lint.sh format
swift test --no-parallel
```

本项目要求 Swift tools 6.2 或更新版本。macOS 和 Linux 的权威验证以 GitHub Actions 为准。

## 文档

- Provider 总览：[docs/providers.md](docs/providers.md)
- Provider 开发指南：[docs/provider.md](docs/provider.md)
- CLI 参考：[docs/cli.md](docs/cli.md)
- 架构说明：[docs/architecture.md](docs/architecture.md)
- 刷新循环：[docs/refresh-loop.md](docs/refresh-loop.md)
- 状态轮询：[docs/status.md](docs/status.md)
- UI 和图标：[docs/ui.md](docs/ui.md)
- Widget：[docs/widgets.md](docs/widgets.md)
- 打包发布：[docs/RELEASING.md](docs/RELEASING.md)
- Fork 快速开始：[docs/FORK_QUICK_START.md](docs/FORK_QUICK_START.md)
- 上游同步策略：[docs/UPSTREAM_STRATEGY.md](docs/UPSTREAM_STRATEGY.md)

## 与上游的关系

原始项目由 Peter Steinberger 创建并维护：<https://github.com/steipete/CodexBar>。

这个 fork 会尽量保留上游架构和隐私边界，同时在中文 UI、中文用户常用 provider、GitHub Actions 构建和本地使用体验上继续调整。适合所有用户的 bug fix 可以回馈上游；中文汉化和 fork 专属 provider/配置会优先留在本 fork。

## 许可

MIT。原始项目版权归 Peter Steinberger 及贡献者所有；本 fork 的新增改动由对应贡献者保留署名。
