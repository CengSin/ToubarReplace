# ToubarReplace

在桌面上显示真实硬件 Touch Bar 的镜像。默认镜像只读取系统已经渲染好的画面；打开 Workspace 时，应用会临时以自定义 `NSTouchBar` 替换物理 Touch Bar，使项目路径和 Agent 可以直接触摸操作。

## 运行

需要一台带 Touch Bar 的 Mac。当前实现针对 macOS 26.6 验证，默认镜像刷新率为 30 FPS。

```sh
swift build
./.build/debug/ToubarReplace
```

构建分发包时，通过环境变量指定版本；生成的 App 信息与菜单栏版本会自动使用该值，无须再手动编辑源文件：

```sh
TOUBAR_VERSION=1.2.3 Packaging/build-app.sh
```

当前 Command Line Tools 的 macOS 15.4 SDK 不提供 XCTest 或 Swift Testing；回归检查改为可实际执行的 smoke-test 入口：

```sh
Scripts/run-regression.sh
```

它会验证镜像尺寸、帧率、空白 Control Strip 判断、Touch Bar 上下文模式，以及 Cursor/Otty/Terminal 的启动参数；任一断言失败会以非零状态退出。该模式不会创建窗口或连接私有 Touch Bar 显示流。

应用会在菜单栏显示图标，菜单中会显示当前版本并提供“帮助…”。系统镜像 viewport 默认以 `2300 × 70` 像素贴住屏幕底边，并且会出现在所有桌面空间；Workspace 切换按钮默认使用可拖动、位置可记忆的独立浮窗，不改变镜像宽度或对齐。短按浮窗切换模式，长按或拖动只调整位置，不触发切换。收到新的有效 Touch Bar 画面时窗口会以 100% 不透明度显示，连续 5 秒没有新画面后自动降至 30%。可拖拽镜像窗口背景，把它与物理 Touch Bar 的边缘对齐；请在“设置…”中选择位置、镜像宽高、帧率、切换按钮使用浮窗还是附着于镜像两侧、Claude Code 使用的终端，以及启动后是否自动返回镜像。选择“退出 ToubarReplace”可以退出程序。

## Workspace Bar

点击独立浮窗中的网格按钮会在物理 Touch Bar 上打开 Workspace，再次点击同一按钮即可恢复系统 Touch Bar；设置中也可以把按钮附着到镜像左侧或右侧。物理 Workspace 条最左侧另有返回控件（在 10 格网格之外），与浮窗/附着切换按钮作用相同。展开期间镜像捕获流继续运行，因此桌面窗口会镜像这套真实可触摸的 Workspace 内容，并保持 100% 不透明度。

如果打开 Workspace 时 Finder 正在前台，应用会通过 Automation 权限优先读取并展示当前 Finder 窗口的目录；Workspace 已展开期间切换到 Finder，也会稍作等待后自动刷新，避免 Finder 窗口尚未准备完成时读到空路径。其他应用的文档路径解析仍需要 ToubarReplace 的辅助功能权限。触摸整个路径区域时，如果 Finder 正在前台会直接读取当前目录，否则打开系统目录选择器供用户选择。

路径可用后，Workspace 会显示本机能够实际启动的 Agent：

- Codex：通过发现到的 `codex` 绝对路径执行 `codex app <项目路径>`，并把子进程工作目录同步设为该项目路径；没有 CLI 时回退到 Codex App。
- Cursor：优先执行 Cursor App 内置 CLI 的 `cursor --new-window <项目路径>`，同时把子进程工作目录同步设为该项目路径，保证指定目录被打开；没有内置 CLI 时查找 PATH 中的 Cursor CLI，最后才回退到 App URL 打开。
- Claude Code：通过设置中选择的终端在项目目录中启动交互式 `claude`。当前支持已安装的 Otty 和 Terminal.app；Otty 使用 `otty-cli`，Terminal 适配器首次使用时 macOS 可能请求 Automation 权限。
- Grok Build：发现 `grok` CLI（包含 `~/.grok/bin/grok`），并通过所选终端在项目目录中启动交互式 Grok Build TUI。

物理 Touch Bar 的 Workspace 按设计稿 v2：**单条 full-width item** 内左侧返回（网格外），右侧 continuous tray。tray 为 **Path（4/10 base）| Agents | Custom**；目录名较长时 Path 区可扩展（agents|custom 均分剩余，并保留最小可用宽），目录 plate 在 Path 区内按标题收窄并水平居中，Agent/自定义为等分槽位（自定义空态「自定义app」，最多 3 个 + 添加位，满员 FIFO）。点自定义图标仅打开 App。item 目标宽度由设置中的镜像像素宽换算为点，并**上限为 `1010` pt**（低于 DFR 全宽约 `1085`，避免右侧自定义/`+` 被 Function Row 裁切；默认镜像 `2300` @2x 点宽会被 cap）；高度固定为 Touch Bar chrome（约 30pt）。启动 Agent 期间会立即禁用；成功后默认约 0.5 秒返回镜像，可在设置中关闭。

如果“App 控制”或“快速操作”模式暂时没有可显示的上下文内容，镜像窗口会保留最后一张有效画面并显示非错误提示；切换到支持触控栏的 App 或启用快速操作后会自动恢复。显示流不可用、启动失败、Control Strip 布局为空，或者固定内容模式下 TouchBarServer 持续只返回黑帧时，镜像窗口仍会显示对应错误原因。

如果镜像窗口出现错误，菜单栏“帮助…”会显示恢复命令。也可以在终端依次执行：

```sh
defaults delete com.apple.controlstrip FullCustomized
defaults delete com.apple.controlstrip MiniCustomized
killall ControlStrip
```

## 实现边界

- 画面来自 `SLSDFRDisplayStreamCreate` 创建的持续 Touch Bar 显示流，帧数据由 `IOSurface` 提供。程序不再定时启动 `/usr/sbin/screencapture -b`，因此不会为每次刷新新建截图进程和临时 PNG。
- 默认镜像刷新率为 30 FPS，可在 1–30 FPS 之间调整。显示流只在 Touch Bar 内容改变时交付新帧；限流期间会保留并补发最新画面，避免切换结束时停留在过渡帧。
- 首次启动窗口为 `2300 × 70` 像素（Retina 屏幕上约 `1150 × 35` 点）。用户调整后的实际像素宽高会自动写入设置并在下次启动时恢复；画面按窗口大小等比缩放，不再强制套用某个机型的 Touch Bar 宽度。
- 锁屏、屏幕休眠或系统休眠时会停止显示流；解锁、亮屏或唤醒后会自动重建。显示流启动后 5 秒没有返回任何状态会自动重连；系统返回的全黑帧持续至少 0.5 秒才会被判定为异常，且不会覆盖最后一张有效画面。
- 桌面镜像窗口背景接收鼠标拖拽；独立切换浮窗可整块拖动并记忆位置。切换按钮只负责打开或关闭 Workspace。捕获到的镜像仍不做坐标映射或点击转发；路径、Agent 点按启动与自定义 App 打开全部发生在物理 Touch Bar 上。
- Workspace 通过 Pock 同类的私有 `presentSystemModalTouchBar`/`dismissSystemModalTouchBar` 接口临时呈现自建 `NSTouchBar`。Workspace 使用全宽 `app` 模式，不保留右侧 Control Strip；退出、锁屏、睡眠或再次点击切换按钮时会 dismiss。只有系统模式仍是 Workspace 设置的 `app` 时才恢复进入前的 `PresentationModeGlobal`；若用户期间已在系统设置中切换模式，则保留用户的新选择，并把切换按钮同步回镜像状态。
- `SLSDFRDisplayStreamCreate` 和 system-modal Touch Bar 都是私有接口，未来 macOS 更新可能改变或移除。应用会在运行时检查呈现 selector；不可用时保留普通镜像并显示错误，不执行未知调用。

尺寸参考：Apple 将 Touch Bar 定义为 Retina 显示/输入设备；公开的 Touch Bar 截图资料通常以 `2170 × 60` 像素描述其完整画布。本程序还用本机 `DFRGetScreenSize()` 实测到 `1085 × 30` 逻辑点，再与实际 `screencapture -b` 帧的 `2008 × 60` 像素对齐。
