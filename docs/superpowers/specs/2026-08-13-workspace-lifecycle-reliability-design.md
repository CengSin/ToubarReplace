# Workspace 生命周期可靠性修复设计

日期：2026-08-13

## 目标

修复代码审查发现的软件 Workspace 唤醒路径、Agent 启动竞态、启动错误丢失和切换按钮文档过时问题；不改变双 system modal 架构、Touch Bar placement 或镜像过渡时序。

## 范围

### 软件 Workspace 生命周期

- 没有可用物理 Touch Bar 的 Mac 在启动和恢复时，都不得调用 `TouchBarCapture.start()` 或 `TouchBarCapture.restart()`。
- 睡眠和锁屏通知可以暂时离开软件 Workspace，但相应的恢复通知必须重新进入可交互的软件 Workspace，不得启动显示流重试循环。
- 硬件模式保留现有的捕获重启和物理切换按钮恢复路径。
- 硬件/软件模式仍只由私有 API 能力决定，禁止使用 CPU 架构判断。

### Agent 启动任务的会话归属

- 每次进入 Workspace 都生成单调递增的会话 generation。
- Agent 启动任务和延迟自动收起任务属于创建它们的 generation。
- 关闭 Workspace、停止控制器或开始更新的启动操作时，取消已经过期的任务。
- 成功、失败和自动收起仅在 generation 仍为当前值且 Workspace 仍处于打开状态时更新 UI。
- 关闭 Workspace 不得只通过清除布尔值来假装尚未取消的启动任务已经结束。

### 进程完成语义

- Codex、Cursor 等直接应用启动命令保留短启动宽限期；超过宽限期仍在运行视为已经成功交接。
- Terminal adapter 的辅助命令（`otty-cli` 和 `osascript`）是短生命周期控制命令，必须等待真实退出，让非零状态传递到 Workspace 失败 UI。
- 取消时只终止当前启动操作创建且仍在运行的辅助命令，不终止已经打开的 Agent 应用。

### 自定义 App 错误

- 打开固定的自定义 App 改为异步且可抛错。
- 保存路径启动和 bundle identifier 回退路径都必须传播 `NSWorkspace` completion error。
- 保存路径不存在时可以按 bundle identifier 回退；保存路径存在但启动失败时直接报告，不能静默忽略。
- 启动失败后保留当前 Workspace 路径和 Agent 按钮的可用性。

### 文档

- 用户文档和开发者文档只描述当前两种切换按钮：物理 Touch Bar 或独立浮窗。
- 文档继续明确镜像窗口点击穿透，通过设置定位，不能拖动。
- 从本设计开始，仓库内新增或更新的设计、计划和说明使用中文。

## 设计

增加纯策略辅助类型，把硬件恢复动作和 generation 有效性判断从窗口/UI 中分离，使 smoke test 无需创建窗口或调用私有 API 就能覆盖关键分支。`TouchBarWindowController` 持有 Agent 启动任务和自动收起任务句柄，在生命周期边界取消任务，并在所有异步 UI 回写前校验捕获的 generation。

`AgentLauncher` 使用两条明确的进程完成路径：直接 Agent 命令使用启动宽限期；终端辅助命令等待退出。进程等待通过支持取消的 continuation 完成。自定义 App 启动使用 checked throwing continuation 包装 `NSWorkspace.openApplication`。

以下内容不变：`SwitcherTouchBarController`、`WorkspaceTouchBarController`、placement `0/1`、`PresentationModeGlobal` 策略、Workspace 1010 点宽度上限、221ms 过渡 settle。

## 验证

- 实现前先增加会失败的 smoke 断言，覆盖软件/硬件恢复策略和 Workspace generation 归属。
- 增加异步进程回归：运行延迟后非零退出的辅助进程，让旧有“300ms 后误判成功”能够稳定暴露。
- 增加可注入的自定义 App opener 回归，证明 completion error 会传递给调用者。
- 运行 `Scripts/run-regression.sh`、shell 语法检查和 `git diff --check`。
- 物理 Touch Bar modal 行为仍需真机手测，因为 smoke 路径不会 present 私有 system modal。

