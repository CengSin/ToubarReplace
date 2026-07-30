# ToubarReplace

在桌面上显示真实硬件 Touch Bar 的镜像。物理 Touch Bar 继续负责触摸，本程序只读取系统已经渲染好的画面，因此不会改写 Touch Bar 内容或抢占触摸输入。

## 运行

需要一台带 Touch Bar 的 Mac。当前实现针对 macOS 26.6 验证，镜像刷新率约 12 FPS。

```sh
swift build
./.build/debug/ToubarReplace
```

应用会在菜单栏显示图标，菜单中会显示当前版本并提供“帮助…”。镜像窗口默认以 `2300 × 70` 像素贴住屏幕底边，并且会出现在所有桌面空间。窗口支持直接拖拽边缘调整宽高，程序不会再根据画面帧自动改变窗口大小；拖动窗口背景可以改变位置。从菜单栏图标选择“设置…”可以打开设置窗口，选择“退出 ToubarReplace”可以退出程序。设置中可以选择底部、顶部或屏幕中央，查看或输入当前窗口的宽高像素，并设置镜像帧率。

如果显示流不可用、启动失败、Control Strip 布局为空或 TouchBarServer 只返回黑帧，镜像窗口会直接显示对应原因，不再笼统提示“等待画面”。

如果镜像窗口出现错误，菜单栏“帮助…”会显示恢复命令。也可以在终端依次执行：

```sh
defaults delete com.apple.controlstrip FullCustomized
defaults delete com.apple.controlstrip MiniCustomized
killall ControlStrip
```

## 实现边界

- 画面来自 `SLSDFRDisplayStreamCreate` 创建的持续 Touch Bar 显示流，帧数据由 `IOSurface` 提供。程序不再定时启动 `/usr/sbin/screencapture -b`，因此不会为每次刷新新建截图进程和临时 PNG。
- 默认镜像上限为 12 FPS，可在 1–30 FPS 之间调整。显示流只在 Touch Bar 内容改变时交付新帧；静止画面不会被无意义地重复复制。
- 首次启动窗口为 `2300 × 70` 像素（Retina 屏幕上约 `1150 × 35` 点）。用户调整后的实际像素宽高会自动写入设置并在下次启动时恢复；画面按窗口大小等比缩放，不再强制套用某个机型的 Touch Bar 宽度。
- 锁屏、屏幕休眠或系统休眠时会停止显示流；解锁、亮屏或唤醒后会自动重建。系统返回的全黑帧不会覆盖最后一张有效画面。
- 桌面窗口不接收鼠标点击；请继续触摸物理 Touch Bar。这样不会改变系统 Touch Bar 的输入路径。
- `SLSDFRDisplayStreamCreate` 是 SkyLight 私有接口，未来 macOS 更新可能改变或移除它。接口不可用时，后续可切换为类似 Pock 的方案：应用创建并展示自己的 `NSTouchBar`，再把同一套内容映射到桌面窗口；这类后备方案展示的是应用自建内容，不是任意系统 Touch Bar 的最终像素。

尺寸参考：Apple 将 Touch Bar 定义为 Retina 显示/输入设备；公开的 Touch Bar 截图资料通常以 `2170 × 60` 像素描述其完整画布。本程序还用本机 `DFRGetScreenSize()` 实测到 `1085 × 30` 逻辑点，再与实际 `screencapture -b` 帧的 `2008 × 60` 像素对齐。
