# CodexBar 中文汉化版

这是 Leo 维护的 [steipete/CodexBar](https://github.com/steipete/CodexBar) 中文汉化 fork。

CodexBar 是一个 macOS 菜单栏工具，用来集中查看 Codex、Claude、Cursor、Gemini、Copilot、OpenRouter、月之暗面 Kimi、千问、豆包、Trae、小米 Mimo、智谱 z.ai、MiniMax、阶跃星辰、阿里云百炼 Coding Plan 等 AI 工具的额度、余额、重置时间和服务状态。

这个 fork 的目标很直接：让中文用户打开应用后能直接看懂、直接配置、直接排查，不需要在英文设置项、英文错误提示、provider 名称和不同 API 来源之间来回猜。

<img src="codexbar.png" alt="CodexBar 菜单截图" width="520" />

## 这个版本适合谁

- 同时使用多款 AI 编程工具，希望在菜单栏里快速看额度、余额、窗口重置时间和服务状态。
- 主要使用中文或亚洲区域常见 AI 服务，例如月之暗面 Kimi、千问、豆包、Trae、小米 Mimo、智谱 z.ai、MiniMax、阶跃星辰、阿里云百炼。
- 想使用中文界面、中文错误提示和更贴近国内服务命名习惯的 provider 名称。
- 希望通过 GitHub Actions 获取本 fork 的 macOS App 和 Linux CLI 构建产物，而不是安装上游原版。

## 与上游版本的区别

### 中文化体验

- 菜单栏、Overview、Provider 设置页、按钮、状态、错误提示、CLI 输出中的用户可见文案已中文化。
- 国内 AI provider 使用中文名称，例如千问、豆包、阶跃星辰、小米 Mimo、智谱 z.ai、月之暗面 Kimi、阿里云百炼。
- 保留必要技术词和品牌名，例如 `API key`、`Cookie`、`Token`、OAuth、Codex、Claude、Cursor、OpenRouter。

### Provider 覆盖

在上游 Codex、Claude、Cursor、Gemini、Copilot、Kiro、Vertex AI、Augment、Amp、JetBrains AI、OpenRouter、Perplexity、Abacus AI 等 provider 的基础上，本 fork 额外补充或强化了这些中文用户更常见的服务：

- 月之暗面 Kimi：读取 weekly quota 和 5 小时窗口。
- 月之暗面 Kimi K2：读取 API credit 用量。
- 千问：面向阿里云百炼/千问相关额度入口。
- 阿里云百炼 Coding Plan：独立于千问 provider 的 Coding Plan 数据源。
- 豆包：火山方舟/豆包相关订阅和额度入口。
- Trae：Trae 账号用量入口。
- 小米 Mimo：读取小米 Mimo token plan 和余额，支持 API key、浏览器 Cookie 或手动 Cookie。
- 智谱 z.ai：支持 z.ai/BigModel 相关 quota 和 MCP window。
- MiniMax：MiniMax Coding Plan 用量读取。
- 阶跃星辰、Zenmux、AigoCode：补充国内/亚洲开发者常见平台入口。

### Overview 和刷新

- Overview 会尽量显示所有已启用、可选择的 API/provider。
- 支持合并图标模式，多个 provider 可以合并到同一个菜单栏入口。
- 支持手动刷新以及 1 分钟、2 分钟、5 分钟、15 分钟等刷新节奏。
- Provider 刷新策略有 CI 覆盖，避免后台刷新、实时显示和 Overview 逻辑回退。

### 构建和发布

- macOS App 通过 GitHub Actions 打包为 zip artifact，并更新 continuous pre-release。
- Linux CLI 通过 GitHub Actions 构建 x64 和 arm64。
- CI 会运行 lint、实时刷新策略测试、Swift Test 和 Linux CLI smoke test。

## 安装

### 系统要求

- macOS 14 Sonoma 或更新版本。
- Linux 仅支持 CLI，不支持菜单栏 App。

### 从本 fork 下载

优先使用 Leo fork 的构建产物：

- Releases: <https://github.com/LeoLin990405/CodexBar/releases>
- Actions artifacts: <https://github.com/LeoLin990405/CodexBar/actions>

### 关于 Homebrew

如果你运行：

```bash
brew install --cask steipete/tap/codexbar
```

安装的是上游原版 CodexBar，不是这个中文汉化 fork。需要中文版本时，请使用本 fork 的 Release 或 GitHub Actions 产物。

## 第一次使用

1. 打开 CodexBar。
2. 进入设置里的 Provider 页面。
3. 只启用你实际使用的 provider。
4. 按 provider 要求登录对应 CLI、浏览器账号、OAuth，或填写 API key/Cookie。
5. 如果 macOS 弹出 Keychain 或浏览器 Cookie 解密权限，请只授权给 `CodexBar.app`。
6. 回到 Overview 或菜单栏，手动刷新一次确认数据源是否可用。

## 当前支持的 Provider

不同 provider 的数据来源不同：有些读 CLI 输出，有些读 OAuth/API，有些需要浏览器 Cookie，有些只提供状态探测。具体限制请以设置页错误提示和 `docs/` 下的 provider 文档为准。

### 核心开发工具

- [Codex](docs/codex.md)：Codex CLI RPC/PTy、本地用量扫描，可选 OpenAI 网页 dashboard 增强。
- [Claude](docs/claude.md)：OAuth API、浏览器 Cookie、CLI PTY fallback，支持 session 和 weekly 用量。
- [Cursor](docs/cursor.md)：通过浏览器 session Cookie 获取 plan、usage 和 billing reset。
- [Gemini](docs/gemini.md)：使用 Gemini CLI 凭据的 OAuth quota API。账号或 TOS 状态异常时可能不可用。
- [Copilot](docs/copilot.md)：GitHub device flow 和 Copilot internal usage API。
- [OpenCode](docs/opencode.md)：OpenCode 网页 dashboard。
- OpenCode Go：OpenCode Go 相关用量入口。

### 中文和亚洲服务

- [月之暗面 Kimi](docs/kimi.md)：从 `kimi-auth` Cookie/JWT 读取 weekly quota 和 5 小时 rate limit。
- [月之暗面 Kimi K2](docs/kimi-k2.md)：API key 读取 credit 用量。
- [智谱 z.ai](docs/zai.md)：API token 读取 quota 和 MCP window；智谱/BigModel CN 入口可按配置切换。
- [阿里云百炼 Coding Plan](docs/alibaba-coding-plan.md)：阿里 Coding Plan，支持浏览器 session 和 API key fallback。
- 千问：阿里云百炼/千问相关入口；和阿里云百炼 Coding Plan 分开配置。
- 豆包：火山方舟/豆包相关订阅和额度入口。
- Trae：Trae 账号用量入口。
- [小米 Mimo](docs/mimo.md)：读取小米 Mimo token plan 和余额，支持 API key、自动浏览器 Cookie 或手动 Cookie。
- [MiniMax](docs/minimax.md)：MiniMax Coding Plan。
- 阶跃星辰：阶跃星辰平台入口。
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

## 配置和凭据

CodexBar 支持多种数据来源：

- CLI：读取本机已登录 CLI 的账号、计划或用量输出。
- OAuth/API：通过 provider 的 token 或 API key 请求额度接口。
- 浏览器 Cookie：从已登录浏览器会话导入必要 Cookie。
- 手动 Cookie：在设置页粘贴从浏览器 Network 面板复制的 `Cookie:` header。
- 本地文件：读取部分工具产生的本地日志或配置文件。

常见配置文件位置：

```text
~/.codexbar/config.json
```

请不要把 API key、Cookie、Authorization header 或完整日志提交到仓库。

## 菜单栏图标

CodexBar 使用两条小进度条显示额度：

- 上方：5 小时/session 窗口；如果 weekly 不可用但 credits 可用，会切换为 credits 显示。
- 下方：weekly 窗口。
- 数据异常、数据过期或登录失效时，图标会变暗或显示错误状态。
- 服务状态异常时会显示状态标记。

## 隐私和权限

CodexBar 保留上游的本机优先隐私模型。它不会全盘扫描你的电脑，只会在你启用对应 provider 后读取少量已知位置，例如：

- Provider CLI 的本地配置或输出。
- 浏览器 Cookie/local storage。
- 本地 JSONL 日志。
- Keychain 中由 CLI 或 CodexBar 保存的 token。

### macOS 权限说明

- Full Disk Access：读取 Safari Cookie/local storage 时可能需要。Chrome/Firefox 或 CLI-only 模式通常可以绕开。
- Keychain access：用于读取 Chrome Safe Storage、Claude OAuth 凭据、z.ai/Copilot 等 token。
- Files & Folders：如果 provider CLI 自己访问项目目录，macOS 可能把权限提示显示给 CodexBar。

CodexBar 不需要 Screen Recording、Accessibility 或 Automation 权限，也不会保存你的账号密码。

## 排错

如果某个 provider 不显示数据，优先按这个顺序检查：

1. 该 provider 是否已在设置里启用。
2. 数据源是否选择正确，例如 Auto、Web、API、Manual Cookie。
3. 对应 CLI 或网页账号是否仍然登录。
4. API key、region、base URL 是否写入了 `~/.codexbar/config.json` 或环境变量。
5. macOS 是否允许 CodexBar 读取 Keychain 或浏览器 Cookie。
6. 设置页里的中文错误提示是否指出了缺失的 Cookie、API key、region 或登录状态。

常见 provider 的详细说明见 `docs/*.md`。

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

## GitHub Actions

本 fork 使用这些 workflow：

- `CI`：lint、实时刷新策略测试、Swift Test、Linux CLI 构建和 smoke test。
- `Release macOS App`：构建并打包 macOS App，上传 artifact，更新 continuous pre-release。
- `Build App` / `Release CLI`：用于补充打包和 CLI 发布流程。
- `Monitor Upstream Changes`：用于跟踪上游变更。

## 文档

- Provider 总览：[docs/providers.md](docs/providers.md)
- Provider 开发指南：[docs/provider.md](docs/provider.md)
- 配置说明：[docs/configuration.md](docs/configuration.md)
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

这个 fork 会尽量保留上游架构、隐私边界和核心行为，同时在中文 UI、中文用户常用 provider、GitHub Actions 构建和本地使用体验上继续调整。适合所有用户的 bug fix 可以回馈上游；中文汉化、中文 provider 命名和 fork 专属配置会优先留在本 fork。

## 许可

MIT。原始项目版权归 Peter Steinberger 及贡献者所有；本 fork 的新增改动由对应贡献者保留署名。
