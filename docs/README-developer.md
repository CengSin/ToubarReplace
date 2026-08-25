# ToubarReplace 开发说明

ToubarReplace 是 macOS 菜单栏应用：带 Touch Bar 的 Mac 通过私有显示流镜像真实物理栏，并可临时呈现全宽 Workspace；没有可用物理栏时直接在桌面窗口中运行可交互的软件 Workspace。

## 构建与回归

```sh
swift build
./.build/debug/ToubarReplace
Scripts/run-regression.sh
```

分发包通过下列命令构建；脚本尽量合并 arm64 与 x86_64，单侧交叉编译失败时回退为可用架构。

```sh
TOUBAR_VERSION=1.2.3 Packaging/build-app.sh
```

smoke test 不创建窗口、不连接私有 Touch Bar 显示流，主要验证尺寸、布局、placement、PresentationMode 策略、启动参数、硬件能力策略和异步辅助进程错误传播。私有 system modal 行为仍需带 Touch Bar 的 Intel 真机验证。

## 桌面窗口与切换按钮

镜像 viewport 默认是 `2300 × 70` 像素，在 Retina 屏幕上约为 `1150 × 35` 点。窗口不可拖动且点击穿透；位置由设置中的底部、顶部、中央、上次关闭位置或自定义左上角坐标控制。

有物理 Touch Bar 时，切换按钮有两种互斥模式：

- 物理 Touch Bar 网格按钮：`SwitcherTouchBarController`，placement `0`，保留 Control Strip。
- 独立浮窗：`WorkspaceSwitcherWindowController`，短按切换，长按或拖动只调整浮窗位置。

无物理 Touch Bar 时，有效模式固定为独立浮窗。启动场景由设置「启动后进入」决定，默认 Workspace；选镜像则显示无硬件说明态。硬件模式即使启动进入 Workspace 也要先开显示流。睡眠前若在 Workspace，唤醒后恢复 Workspace。软件模式不得启动显示流或呈现 system modal。

镜像有新帧时保持 100% 不透明。仅当窗口遮挡其他 App 内容且无新帧达到透明延迟时降至 30%；延迟默认 5 秒，可设置 1–300 秒。浮在空桌面区域上保持 100%。

## Workspace

物理 Workspace 使用独立的 `WorkspaceTouchBarController`：placement `1`，`PresentationModeGlobal = app`，不保留右侧 Control Strip。退出 Workspace 时按策略恢复进入前的 PresentationMode。镜像与 Workspace 两套 modal 不得合并。

Workspace 是一条 full-width item：左侧返回按钮位于 10 格 tray 之外，tray 基础比例为 Path `4/10`、Agents `3/10`、Custom `3/10`。长目录名可扩展 Path 区，但 Agent 与 Custom 保留最小可用宽度。物理 item 宽度上限是 `1010` 点，避免 Function Row 裁切右侧内容；高度固定约 30 点。

路径优先读取 Finder 前台窗口；Otty 在前台时读取焦点 pane 的 cwd（官方 `otty-cli`）。其他应用可通过辅助功能读取文档路径。失败时使用本机最近项目（排除家目录），或点路径区在 4/10 目录区内横向滑动选取。左侧 × 取消。最近项目列表只显示设置里能清空的那份，不再把 Otty `jump:ls` 混进栏上。原生 Terminal 第一版不解析 cwd。Workspace 展开期间切换到 Finder 或 Otty 会延迟同步一次路径。选择态不得占满 tray、不得藏起 Agent/自定义。

Agent 启动方式：

- Codex：优先执行 `codex app <项目路径>`，没有 CLI 时回退 Codex App。
- Cursor：优先内置 CLI，再查找 PATH 中的 CLI，最后回退 Cursor App。
- Claude Code / Grok Build：通过设置选择的 Otty 或 Terminal.app 在项目目录启动。

直接 Agent 启动命令使用短启动宽限期；Otty 和 `osascript` 是短生命周期辅助命令，必须等待真实退出并传播非零状态。Agent 启动和自动收起任务绑定 Workspace generation，旧会话任务不得回写或关闭新会话。

自定义 App 最多 3 个，在设置中新增、替换或移除；不会 FIFO 挤出已有项目。点击图标只打开应用，齿轮进入设置。`NSWorkspace` completion error 必须显示在 Workspace 中，不能静默忽略。

## 捕获与生命周期

物理画面来自 `SLSDFRDisplayStreamCreate` 创建的持续显示流，帧数据由 `IOSurface` 提供；默认 30 FPS，可设置为 1–30 FPS。限流期间保留并补发最新帧。

锁屏、屏幕休眠或系统休眠时停止捕获并 dismiss 物理栏；解锁或唤醒后，硬件模式重建显示流和物理切换按钮，软件模式重新进入桌面 Workspace。显示流启动后 5 秒没有任何状态会自动重连；持续至少 0.5 秒的全黑帧才判定为异常，且不覆盖最后一张有效画面。

镜像场景切换使用 `MirrorSceneTransition` 冻结最后一帧，当前 settle 为 221ms，fade 为 0.12s。该 cover 只改善桌面镜像观感，无法消除物理栏 placement/mode 重排。

## 私有 API 边界

- 私有调用只通过 `TouchBarPrivateAPI` 封装。
- 硬件能力只检查显示流和 system modal API 是否可用，不按 CPU 或 `uname` 判断。
- 不调用未验证的 DFRDisplay selector，不合并双 modal，不实现镜像鼠标坐标映射。
- 私有 API 可能随 macOS 更新改变；不可用时进入软件 Workspace 或显示明确错误。
