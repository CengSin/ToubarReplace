# ToubarReplace

在桌面上显示真实硬件 Touch Bar 的镜像。物理 Touch Bar 继续负责触摸，本程序只读取系统已经渲染好的画面，因此不会改写 Touch Bar 内容或抢占触摸输入。

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

它会验证镜像尺寸、帧率、空白 Control Strip 判断和 Touch Bar 上下文模式策略；任一断言失败会以非零状态退出。该模式不会创建窗口或连接私有 Touch Bar 显示流。

应用会在菜单栏显示图标，菜单中会显示当前版本并提供“帮助…”。镜像窗口默认以 `2300 × 70` 像素贴住屏幕底边，并且会出现在所有桌面空间。收到新的有效 Touch Bar 画面时窗口会以 100% 不透明度显示，连续 5 秒没有新画面后自动降至 30%。可拖拽镜像窗口背景，把它与物理 Touch Bar 的边缘对齐；请在“设置…”中选择位置、查看或输入窗口宽高像素，并设置镜像帧率。选择“退出 ToubarReplace”可以退出程序。

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
- 桌面窗口接收鼠标拖拽，用于与物理 Touch Bar 对齐；触控操作仍请直接触摸物理 Touch Bar。这样不会改变系统 Touch Bar 的输入路径。
- `SLSDFRDisplayStreamCreate` 是 SkyLight 私有接口，未来 macOS 更新可能改变或移除它。接口不可用时，后续可切换为类似 Pock 的方案：应用创建并展示自己的 `NSTouchBar`，再把同一套内容映射到桌面窗口；这类后备方案展示的是应用自建内容，不是任意系统 Touch Bar 的最终像素。

尺寸参考：Apple 将 Touch Bar 定义为 Retina 显示/输入设备；公开的 Touch Bar 截图资料通常以 `2170 × 60` 像素描述其完整画布。本程序还用本机 `DFRGetScreenSize()` 实测到 `1085 × 30` 逻辑点，再与实际 `screencapture -b` 帧的 `2008 × 60` 像素对齐。
