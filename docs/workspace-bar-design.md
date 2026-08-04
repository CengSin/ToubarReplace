# ToubarReplace Workspace Bar 设计

状态：物理 Touch Bar 交互迭代已实现，Phase 4 待后续迭代  
适用范围：ToubarReplace 桌面 Touch Bar 镜像与物理 Touch Bar Workspace  
目标版本：Workspace Bar 物理交互迭代

当前实现已包含独立浮动/镜像附着两种切换入口、system-modal 物理 `NSTouchBar`、Finder 当前目录自动同步、最近项目恢复、手动目录选择、已授权情况下的前台文档路径解析、Codex/Cursor/Claude Code/Grok Build 发现与启动、70/30 目录与大图标 Agent 滑动行、Otty/Terminal 适配、入口左右位置和启动后自动收起设置。`toubar use .`、更多 IDE/终端 resolver、Agent 隐藏与排序界面仍属于后续迭代。

## 1. 产品定位

ToubarReplace 默认是只读的系统 Touch Bar 桌面镜像。Workspace Bar 会临时替换物理 Touch Bar，增加一个面向开发工作的操作空间，用于：

- 获取并展示当前项目路径。
- 展示电脑上可用的 Agent/Harness，例如 Codex、Claude Code、Cursor。
- 通过左右滑动选择 Agent。
- 点击 Agent，在当前项目路径中启动对应应用或命令行工具。

系统 Touch Bar 镜像仍然是默认主页。Workspace 不作为设置中的展示模式，而是一个从镜像边缘打开、用完即可返回的操作抽屉。

## 2. 已确认的设计决策

### 2.1 镜像是主页，Workspace 是抽屉

应用启动后继续展示当前系统 Touch Bar 镜像。用户通过独立浮动切换按钮打开抽屉，不需要先进入“设置”切换模式。

Workspace 完成 Agent 启动后默认自动返回镜像。用户可以选择固定 Workspace，使其保持展开。

### 2.2 切换按钮默认使用独立浮窗

切换按钮默认放在一个独立、非激活式、跨 Space 的小浮窗中。浮窗可整块拖动并记忆位置，因此即使隐藏桌面镜像或物理 Touch Bar 正常显示，入口仍然可用；同时镜像窗口不再为入口预留宽度：

```text
镜像状态
     ┌──────────────────────────────────────────────┐  ┌────┐
     │              系统 Touch Bar 镜像             │  │ ▦  │
     └──────────────────────────────────────────────┘  └────┘

Workspace 状态（以下内容位于物理 Touch Bar）
┌────────────────────────────┬──────────────────────────────────┐
│       最近 · ToubarReplace  │       Codex Claude Cursor        │
└────────────────────────────┴──────────────────────────────────┘
```

入口不覆盖捕获的 `CGImage`，也不改变镜像窗口尺寸。打开后，路径和 Agent 属于物理 Touch Bar，并由显示流同步镜像到桌面。

设置中可关闭独立浮窗，并把入口附着到镜像左侧或右侧。Workspace 内不再提供额外关闭/返回按钮，所有镜像与 Workspace 的切换都经过外部切换按钮。

### 2.3 Workspace 不抢占当前前台应用

镜像窗口继续使用非激活式浮动面板。用户点击 Workspace 或“获取当前路径”时，应先保存当前前台应用，再进行 UI 切换和路径解析。

不得为了打开 Workspace 主动激活 ToubarReplace。这样可以尽量保留 Cursor、终端或 Codex 的工作上下文。

### 2.4 自定义内容由物理 Touch Bar 提供

系统镜像和 Workspace 是两套独立的内容来源：

- `TouchBarSurfaceView` 始终负责显示捕获画面、提示和错误。
- `WorkspaceTouchBarController` 创建真实 `NSTouchBar`，路径、Agent 选择和触摸交互都由它处理。
- `WorkspaceBarView` 只作为私有 system-modal API 不可用时的桌面错误回退。

现有捕获流在 Workspace 展开时继续运行，因此桌面自然显示物理 Workspace 的画面；返回系统 Touch Bar 时无需重新连接显示流。

## 3. 核心用户流程

### 3.1 打开 Workspace

1. 用户点击独立浮窗或镜像边缘的 `▦`。
2. 应用在 `mouseDown` 阶段记录当前前台应用信息。
3. 应用通过 system-modal 私有接口呈现自定义 `NSTouchBar`。
4. 桌面根容器保留捕获画面，切换按钮更新为返回状态，并保持 100% 不透明度。
5. 若 Finder 正在前台，优先读取当前 Finder 窗口目录；否则恢复上次有效路径，再尝试解析点击入口前的前台 App。

### 3.2 获取当前路径

1. 用户触摸物理 Touch Bar 上的整个路径区域。
2. 目录信息栏进入解析中状态。
3. Finder 正在前台时直接读取其当前窗口目录；否则打开系统目录选择器。
4. 成功后显示项目名和紧凑路径，并刷新可用 Agent。
5. Workspace 展开期间 Finder 成为前台时，也自动刷新为当前 Finder 目录。

路径展示示例：

```text
ToubarReplace · Sources/ToubarReplace
```

Touch Bar 中只展示来源、项目名和必要的相对路径。完整路径通过 tooltip 和辅助功能描述提供；路径区域本身始终可点击。

### 3.3 选择并启动 Agent

1. 路径可用后，在右侧 30% 图标行显示已发现且可启动的 Agent；优先读取对应 App Bundle 的真实图标，CLI-only Agent 使用系统图标回退。
2. 用户在 Agent 区域左右滑动切换选中项。
3. Agent 区域不显示左右箭头，左右边缘保留窄幅横向渐隐，以提示可以继续滑动，但不降低主体图标的清晰度。
4. 滑动只改变选择，不立即启动，避免误操作。
5. 点击已选中的 Agent 图标后，在当前路径中启动它；点击其他图标时先切换选择，再次点击才启动。
6. 启动成功后，默认延迟约 `500ms` 返回系统镜像。
7. 启动失败时保持 Workspace 展开，并在对应 Agent 附近展示简短错误。

如果全部 Agent 图标都能完整显示，用户可以直接点选目标图标，再次点击启动。

## 4. Workspace 状态模型

建议使用显式状态，而不是通过多个布尔值组合 UI：

```swift
enum WorkspaceBarState {
    case idle(lastPath: URL?)
    case resolving(context: FrontmostAppContext)
    case ready(WorkspaceContext)
    case launching(agentID: AgentID, context: WorkspaceContext)
    case failed(WorkspaceFailure, lastContext: WorkspaceContext?)
}
```

根视图的展示状态独立管理：

```swift
enum BarScene {
    case mirror
    case workspace
}
```

推荐状态流：

```text
mirror
  └─ 点击入口 → workspace.idle
                    └─ 点击获取 → workspace.resolving
                                      ├─ 成功 → workspace.ready
                                      │            └─ 点击 Agent → launching
                                      │                               ├─ 成功 → mirror
                                      │                               └─ 失败 → failed
                                      └─ 失败 → failed/选择目录
```

## 5. 当前路径解析

macOS 没有统一的“当前项目路径”系统概念，不能直接使用 ToubarReplace 进程自身的工作目录。路径解析必须由多个来源组成，并明确记录来源和可信度。

### 5.1 解析优先级

1. 点击入口时保存的前台应用专用适配器。
2. `toubar use .` 或后续 URL Scheme 最近主动上报的目录。
3. 用户固定的项目路径。
4. 用户手动选择目录。

自动解析失败时不得静默使用无关目录。若回退到固定路径或最近路径，UI 应给出可辨认的状态。

### 5.2 前台应用上下文

建议保存：

```swift
struct FrontmostAppContext {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t?
    let capturedAt: Date
}
```

第一期不强制依赖 Accessibility 或全局鼠标监控。前台应用专用解析器可逐步增加：

- Cursor：通过应用可提供的文档 URL、窗口信息或专用集成解析。
- Terminal/iTerm：优先使用 shell 主动上报；AppleScript 作为用户明确授权后的适配器。
- Codex：优先使用应用/CLI 主动传入的 workspace 路径。
- 其他 IDE：通过独立 resolver 注册。

### 5.3 主动上报接口

建议后续提供一个小型命令：

```sh
toubar use .
```

命令负责把规范化后的目录发送给正在运行的 ToubarReplace。实现可以使用本地 XPC、Unix Domain Socket 或自定义 URL Scheme；具体传输方式在实现阶段决定。

收到目录后必须校验：

- 路径存在。
- 路径是目录。
- 规范化符号链接和 `..`。
- 保留来源与更新时间。

## 6. Agent/Harness 模型

Agent 发现和启动必须数据驱动，不在图标交互事件中堆叠产品名称判断。

```swift
struct AgentDescriptor {
    let id: AgentID
    let displayName: String
    let discoveryRules: [AgentDiscoveryRule]
    let launchStrategy: AgentLaunchStrategy
}
```

### 6.1 发现来源

按以下方式组合发现结果：

- `NSWorkspace.runningApplications`
- Bundle Identifier
- `/Applications`
- `~/Applications`
- 用户配置的 CLI 可执行文件 URL
- URL Scheme

不能只扫描 `/Applications`。GUI App 可能安装在用户目录、处于运行状态或由 CLI 负责唤起。

Agent 行优先读取已发现 App Bundle 的真实图标；没有关联 GUI App 的 CLI Agent 使用系统符号回退。图标来源与启动策略保持独立，例如 Codex 可以使用 App 图标，同时仍通过 CLI 打开项目。

### 6.2 第一批 Agent

#### Codex

- 发现：Codex App、运行中的 Bundle、`codex` CLI。
- 启动：优先使用已经验证的 GUI 路径启动能力；CLI 方案使用参数数组调用 `codex app <path>`。
- GUI 应用通常不继承用户终端的 `PATH`，所以需要保存发现到的可执行文件绝对 URL。

#### Cursor

- 发现：Cursor App Bundle 内置 CLI 或 PATH 中的 Cursor CLI。
- 启动：优先执行 `cursor --new-window <项目路径>`；只有 CLI 不可用时才回退到 `NSWorkspace`。

#### Claude Code

- 发现：`claude` CLI、Claude Code URL Handler 或后续正式 App Bundle。
- 启动：交互式 CLI 必须由用户选择的终端适配器启动并保留 TTY。
- Otty：调用 `otty-cli open --command <command> <项目路径>`。
- Terminal.app：已运行时只创建一个命令窗口；首次启动时复用 Terminal 自动创建的初始窗口，避免 `activate + do script` 产生双窗口。
- 不得把 Claude Code 作为无终端后台进程启动。

#### Grok Build

- 发现：PATH 中的 `grok` CLI，并显式覆盖 GUI App 常见的 `~/.grok/bin/grok` 安装位置。
- 启动：与 Claude Code 一样，通过用户选择的终端适配器在项目目录中启动交互式 TUI 并保留 TTY。

### 6.3 启动安全

- 优先使用 `Process.executableURL` 和 `arguments`，不拼接 shell 字符串。
- 传入启动器前再次确认路径仍然存在。
- 必须支持包含空格、引号和非 ASCII 字符的路径。
- 终端适配器若必须生成 shell 命令，应集中进行安全转义并覆盖回归测试。
- 启动失败应保留原始错误供日志诊断，UI 只显示简短可操作信息。

## 7. 视图和窗口结构

建议将现有单一 `TouchBarSurfaceView` 根视图扩展为：

```text
TouchBarRootView
├── AttachedSwitcherView (可选)
└── TouchBarSurfaceView

WorkspaceSwitcherWindowController
└── WorkspaceFloatingSwitcherView (默认)

WorkspaceTouchBarController
└── NSTouchBar
    ├── PathItem (居中)
    └── NSScrubber (Agent carousel)
```

独立浮窗必须与镜像窗口保持同样的浮动层级、跨 Space 和全屏辅助行为，但它的位置、显示状态和透明度独立管理。浮窗不激活 ToubarReplace，也不参与镜像尺寸计算。

### 7.1 尺寸语义

现有“镜像宽高”设置继续表示镜像 viewport，而不是包含 Workspace 入口的整个外部窗口。

假设：

- `mirrorWidth`：用户设置的镜像逻辑宽度。
- `mirrorHeight`：用户设置的镜像逻辑高度。
- `edgeRailWidth`：默认 `36pt`。

附着入口时根窗口内容宽度为：

```text
rootWidth = mirrorWidth + edgeRailWidth
rootHeight = mirrorHeight
```

独立浮窗时：

```text
rootWidth = mirrorWidth
rootHeight = mirrorHeight
```

若入口位于左侧，应调整根窗口 origin，使镜像 viewport 的屏幕位置与升级前保持一致。入口位于右侧时同理，不改变镜像部分的对齐位置。

窗口拖拽、跨 Space、浮动层级、全屏辅助行为和屏幕底边定位继续沿用现有实现。

### 7.2 手势分区

- 独立浮窗或桌面边缘入口：短按用于呈现或 dismiss Workspace；独立浮窗长按或移动超过阈值后只拖动，不触发模式切换。
- 物理 Agent 区域：接收横向滑动和触摸选择。
- 物理路径区域：接收触摸，用于重新解析或选择目录。
- 其余背景：继续用于拖动窗口。

不增加全局鼠标轨迹监听，不增加全局快捷键。

### 7.3 切换动画

首期使用约 `120–180ms` 的淡入淡出或轻量内容位移动画。不要移动整个窗口，也不要在切换时改变镜像 viewport 的屏幕位置。

### 7.4 视觉语言

Workspace 延续系统 Touch Bar 与 Pock 的紧凑深色风格：画布保持纯黑，目录区域约占 70%，使用无按钮底板的文件夹图标和单行路径；Agent 区域约占 30%，只展示一行可触摸的系统图标，不使用文字方框、按钮底板、描边、阴影或桌面风格卡片。文字和图标使用系统前景色，触摸反馈仅通过透明度与轻微缩放表达。

## 8. 透明度和捕获行为

镜像状态继续沿用当前规则：

- 收到新的有效 Touch Bar 帧时恢复 100% 不透明度。
- 连续 5 秒没有新帧后降为 30%。

Workspace 状态：

- 展开期间固定为 100%。
- 路径解析、滑动和 Agent 启动期间保持 100%。
- 返回镜像后恢复帧驱动的空闲透明度行为。

Workspace 展开时不停止 `TouchBarCapture`。捕获流、空白帧判断、错误恢复和睡眠/唤醒重连逻辑保持不变。

## 9. 设置页面职责

设置只负责偏好，不负责日常页面导航。

建议新增：

- Workspace 切换按钮使用独立浮窗或附着于镜像。
- 附着模式下入口位于左侧或右侧。
- Agent 启动成功后是否自动返回镜像。
- 启用、隐藏和排序 Agent。
- Claude Code 使用的终端。
- 固定项目和最近项目管理。
- 清除 Workspace 上下文。

不增加“镜像模式/Workspace 模式”设置项。

建议使用现有 `ToubarReplace.*` UserDefaults 命名空间，例如：

```text
ToubarReplace.workspace.switcherSide
ToubarReplace.workspace.floatingSwitcher
ToubarReplace.workspace.autoCollapse
ToubarReplace.workspace.pinnedPath
ToubarReplace.workspace.agentOrder
ToubarReplace.workspace.disabledAgents
ToubarReplace.workspace.terminalAdapter
```

如果未来启用 App Sandbox，固定目录需要改用 security-scoped bookmark 持久化，不能只保存普通路径字符串。

## 10. 错误和权限处理

### 路径解析失败

- 保持 Workspace 展开。
- 显示“无法从当前 App 获取项目路径”。
- 提供“选择目录”。
- 若存在固定路径，可明确标记后提供回退操作。

### Agent 不可用

- 默认不展示无法启动的 Agent。
- 设置页中可以展示发现失败原因和重新扫描入口。

### 启动失败

- 不自动返回镜像。
- 在 Agent 附近显示简短错误。
- 日志记录 descriptor、启动策略和底层错误，但不记录敏感环境变量。

### 权限

- 第一阶段优先使用无需 Accessibility 的能力。
- 需要 Accessibility、Automation 或其他隐私权限的 resolver 必须由用户主动开启。
- 权限被拒绝时回退到 `toubar use .`、固定路径或手动选目录。

## 11. 物理 Touch Bar 边界

Workspace 使用与 Pock 同类的私有 system-modal 接口，把自建 `NSTouchBar` 呈现在物理 Touch Bar 上。桌面切换按钮不属于捕获像素，只负责触发呈现；呈现后的路径和 Agent 是真正的物理 Touch Bar item。

呈现前保存 `com.apple.touchbar.agent` 的 `PresentationModeGlobal`，Workspace 使用全宽 `app` 和 placement `1`，隐藏 system-modal 关闭按钮，不保留右侧 Control Strip。再次点击切换按钮、退出、锁屏或睡眠时 dismiss 自定义 Touch Bar；只有系统模式仍是 Workspace 写入的 `app` 时才恢复原值，用户期间切换到其他显示模式时必须保留新值。自定义 Touch Bar 被系统撤下时，根视图与切换按钮同步回镜像状态。调用前必须检查 selector 是否存在；私有 API 不可用时保持普通镜像，不尝试坐标事件注入。

## 12. 推荐实现分期

### Phase 1：Workspace 外壳

- 引入 `TouchBarRootView` 和边缘入口。
- 实现镜像/Workspace 场景切换。
- 保持镜像 viewport 尺寸和位置兼容。
- Workspace 展开期间维持 100% 不透明度。

### Phase 2：项目上下文

- 实现手动选择目录和固定目录。
- 实现前台应用快照。
- 定义 resolver 协议和解析结果可信度。
- 提供最近路径回退，但明确标记来源。

### Phase 3：Agent 启动器

- 实现 Agent registry、发现规则和应用图标滑动行。
- 接入 Codex、Cursor、Claude Code。
- 实现横向滑动选择和点击启动。
- 实现启动成功自动返回镜像。

### Phase 4：主动上报与自动解析

- 提供 `toubar use .`。
- 增加 Cursor、终端和其他 IDE 的专用 resolver。
- 按需增加权限引导。

### Phase 5：物理 Touch Bar 复用（已实现）

- 使用同一份 Workspace state 构建 `NSTouchBar`。
- 通过 system-modal API 跨前台 App 呈现，运行时检查接口能力。
- dismiss 时恢复用户进入 Workspace 前的 Touch Bar 模式。

## 13. 第一阶段验收标准

- 启动应用后仍默认显示系统 Touch Bar 镜像。
- 默认存在可拖动、可记忆位置的独立 Workspace 切换浮窗，且不改变镜像窗口尺寸。
- 设置中可将切换按钮改为附着在镜像左侧或右侧。
- 点击入口不会主动激活 ToubarReplace 或丢失进入前的前台 App 信息。
- Workspace 优先恢复上次有效目录，否则自动解析或手动选择目录。
- Finder 在前台时优先展示当前窗口目录；Workspace 展开期间打开 Finder 会自动同步当前目录。
- 路径后方只显示当前可启动的 Agent。
- 最近路径在左侧 70% 目录区域内展示，Workspace 不显示额外的返回或关闭按钮。
- Workspace 使用全宽布局，不保留右侧 Control Strip；目录区域约占 70%，Agent 图标行约占 30%。
- 物理 Touch Bar 的 Agent 区域支持左右滑动选择和触摸启动，不显示左右箭头，溢出时两端渐隐；桌面镜像不转发点击。
- Codex、Cursor、Claude Code、Grok Build 分别使用正确的启动策略。
- 启动成功后默认返回镜像；失败时留在 Workspace。
- Workspace 展开时捕获流保持运行。
- 镜像窗口原有尺寸语义、位置、跨 Space、全屏辅助、拖动和错误恢复行为不变。
- 镜像模式继续使用帧驱动空闲透明度；Workspace 展开时保持 100%。
- 不引入全局鼠标监听、全局快捷键或镜像坐标事件注入。

## 14. 回归验证建议

在现有 smoke test 基础上增加纯逻辑验证：

- 根窗口尺寸与镜像 viewport 尺寸换算。
- 独立浮窗模式下根窗口宽度等于镜像 viewport 宽度。
- 左右入口布局时镜像屏幕位置不变。
- Workspace 状态转换。
- 路径来源优先级和失败回退。
- Agent 发现结果去重、排序和隐藏。
- 启动参数对空格、引号和中文路径的处理。
- 启动成功自动收起、失败保持展开。
- Workspace 展开/关闭时的透明度控制。

需要在带 Touch Bar 的目标机器上人工验证：

- system-modal Touch Bar 的呈现、滑动、触摸和 dismiss。
- 点击入口前后的前台 App 是否保持一致。
- 拖动桌面窗口与物理 Agent 横向滑动是否互相独立。
- 跨 Space、全屏和睡眠唤醒后的入口布局及 PresentationMode 恢复。
- Finder 当前目录自动同步，以及路径区域打开目录选择器的行为。
- Codex、Cursor、Claude Code、Grok Build 的真实按路径启动行为。

## 15. 当前仍不在范围内

- 向捕获的系统 Touch Bar 坐标注入点击事件。
- 自动支持任意未知 IDE 或终端的项目路径。
- 允许任意未知终端 App 直接执行 Claude Code；终端必须有明确适配器。
- Agent 会话状态、token 消耗、任务进度和 Git 操作控件。
- 插件市场或第三方 Widget SDK。

这些能力可以在 Workspace Bar 的状态、resolver 和 Agent registry 稳定后继续扩展。
