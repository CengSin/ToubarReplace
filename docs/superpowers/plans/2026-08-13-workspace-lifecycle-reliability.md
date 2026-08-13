# Workspace 生命周期可靠性修复实施计划

> **执行要求：** 实施时使用 `superpowers:executing-plans`，逐项按 TDD 红—绿—重构推进。未经用户明确要求，不启用子代理。

**目标：** 修复软件 Workspace 唤醒、Agent 启动跨会话竞态、终端辅助进程误判成功、自定义 App 错误丢失和过时文档。

**架构：** 用纯策略类型隔离恢复动作和会话有效性判断；由 `TouchBarWindowController` 持有异步任务并以 generation 约束 UI 回写；由 `AgentProcessRunner` 明确区分启动宽限与等待退出两种进程语义。保持双 system modal、placement、PresentationMode 和镜像过渡参数不变。

**技术栈：** Swift 6、AppKit、Swift Concurrency、Foundation `Process`、现有自包含 smoke test。

---

## 文件结构

- `TouchBarHardwareCapability.swift`：增加恢复动作纯策略。
- `ContentView.swift`：接入恢复策略；管理 Workspace generation 和任务句柄。
- `WorkspaceSupport.swift`：增加进程 runner；让自定义 App 启动异步抛错。
- `ToubarReplaceSmokeTest.swift` / `ToubarReplace.swift`：增加异步回归并支持 async smoke 入口。
- `README.md` / `docs/README-developer.md`：纠正当前交互说明。

### 任务 1：软件/硬件恢复策略

**文件：**
- 修改：`Sources/ToubarReplace/ToubarReplaceSmokeTest.swift`
- 修改：`Sources/ToubarReplace/TouchBarHardwareCapability.swift`
- 修改：`Sources/ToubarReplace/ContentView.swift:1313-1356`

- [ ] **步骤 1：先写会失败的策略测试**

```swift
expect(
    TouchBarResumePolicy.action(usesSoftwareWorkspace: true)
        == .restoreSoftwareWorkspace,
    "软件 Workspace 唤醒后不能重启捕获流",
    failures: &failures
)
expect(
    TouchBarResumePolicy.action(usesSoftwareWorkspace: false)
        == .restartHardwareCapture,
    "物理 Touch Bar 唤醒后必须恢复捕获流",
    failures: &failures
)
```

- [ ] **步骤 2：运行 `Scripts/run-regression.sh`，确认因缺少 `TouchBarResumePolicy` 编译失败。**

- [ ] **步骤 3：实现最小纯策略。**

```swift
enum TouchBarResumeAction: Equatable {
    case restoreSoftwareWorkspace
    case restartHardwareCapture
}

enum TouchBarResumePolicy {
    static func action(usesSoftwareWorkspace: Bool) -> TouchBarResumeAction {
        usesSoftwareWorkspace ? .restoreSoftwareWorkspace : .restartHardwareCapture
    }
}
```

- [ ] **步骤 4：恢复通知按 action 分支。**

软件模式调用 `enterSoftwareWorkspace(isLaunch: true)`；只有硬件模式调用 `capture.restart()` 和 `presentPhysicalSwitcherIfNeeded()`。

- [ ] **步骤 5：运行 `Scripts/run-regression.sh`，确认 GREEN。**

### 任务 2：Workspace generation 与任务所有权

**文件：**
- 修改：`Sources/ToubarReplace/ToubarReplaceSmokeTest.swift`
- 修改：`Sources/ToubarReplace/ContentView.swift:481-505,994-1132,1247-1310`

- [ ] **步骤 1：先写会失败的 generation 测试。**

```swift
expect(
    WorkspaceAsyncSessionPolicy.canUpdate(
        capturedGeneration: 4,
        currentGeneration: 4,
        scene: .workspace
    ),
    "当前 generation 应允许异步回写",
    failures: &failures
)
expect(
    !WorkspaceAsyncSessionPolicy.canUpdate(
        capturedGeneration: 3,
        currentGeneration: 4,
        scene: .workspace
    ) && !WorkspaceAsyncSessionPolicy.canUpdate(
        capturedGeneration: 4,
        currentGeneration: 4,
        scene: .mirror
    ),
    "旧 generation 或已关闭 Workspace 不得异步回写",
    failures: &failures
)
```

- [ ] **步骤 2：运行回归，确认因缺少 `WorkspaceAsyncSessionPolicy` 编译失败。**

- [ ] **步骤 3：实现纯策略。**

```swift
enum WorkspaceAsyncSessionPolicy {
    static func canUpdate(
        capturedGeneration: UInt64,
        currentGeneration: UInt64,
        scene: BarScene
    ) -> Bool {
        capturedGeneration == currentGeneration && scene == .workspace
    }
}
```

- [ ] **步骤 4：增加 `workspaceGeneration`、`agentLaunchTask`、`autoCollapseTask`。**

实现 `beginWorkspaceSession()`、`cancelWorkspaceAsyncWork(invalidateSession:)` 和 `canUpdateWorkspace(from:)`。软件/硬件每次进入 Workspace 都生成新 generation；`closeWorkspace()`、presentation interruption 和 `stop()` 取消任务并使旧 generation 失效。

- [ ] **步骤 5：将 Agent 启动和自动收起绑定到捕获的 generation。**

成功、失败和 500ms 自动收起前都校验 generation 与 scene。旧任务不得回写 UI、清除新任务状态或关闭新会话。

- [ ] **步骤 6：运行完整回归，确认 GREEN。**

### 任务 3：终端辅助进程等待真实退出

**文件：**
- 修改：`Sources/ToubarReplace/ToubarReplaceSmokeTest.swift`
- 修改：`Sources/ToubarReplace/ToubarReplace.swift:295-315`
- 修改：`Sources/ToubarReplace/WorkspaceSupport.swift:907-1039`

- [ ] **步骤 1：将 smoke 入口改为 async，并先写延迟失败测试。**

```swift
do {
    try await AgentProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "sleep 0.45; exit 7"],
        workingDirectory: currentDirectory,
        agentName: "延迟失败测试",
        completionMode: .waitForTermination
    )
    failures.append("等待退出模式不能误判延迟失败为成功")
} catch AgentLaunchError.processFailed(_, let status) {
    expect(status == 7, "必须传播真实退出码", failures: &failures)
} catch {
    failures.append("辅助进程返回意外错误：\(error.localizedDescription)")
}
```

- [ ] **步骤 2：运行回归，确认因缺少 runner/completion mode 编译失败。**

- [ ] **步骤 3：实现明确的进程完成模式。**

```swift
enum AgentProcessCompletionMode {
    case launchGrace(Duration)
    case waitForTermination
}

enum AgentProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        agentName: String,
        completionMode: AgentProcessCompletionMode
    ) async throws
}
```

`launchGrace` 保留直接命令的 300ms 交接语义；`waitForTermination` 在运行前安装 termination handler，以 checked throwing continuation 等待退出。取消时终止仍运行的 helper，continuation 返回后执行 `Task.checkCancellation()`。

- [ ] **步骤 4：Codex/Cursor 的 `.process` 使用 launch grace；Otty/AppleScript 使用 wait-for-termination。**

- [ ] **步骤 5：运行回归，确认延迟 450ms 后 exit 7 被识别为失败。**

### 任务 4：传播自定义 App 启动错误

**文件：**
- 修改：`Sources/ToubarReplace/ToubarReplaceSmokeTest.swift`
- 修改：`Sources/ToubarReplace/WorkspaceSupport.swift:248-294`
- 修改：`Sources/ToubarReplace/ContentView.swift:893-906,1169-1190`

- [ ] **步骤 1：先写会失败的 opener 错误传播测试。**

```swift
enum CustomAppOpenTestError: Error { case rejected }

do {
    try await CustomWorkspaceAppLauncher.open(
        missingApp,
        fileManager: .default,
        resolveBundleIdentifier: { _ in fallbackURL },
        openApplication: { _ in throw CustomAppOpenTestError.rejected }
    )
    failures.append("自定义 App completion error 不得被忽略")
} catch CustomAppOpenTestError.rejected {
    // 预期路径
} catch {
    failures.append("自定义 App 返回意外错误：\(error)")
}
```

- [ ] **步骤 2：运行回归，确认现有同步 API 无法编译该测试。**

- [ ] **步骤 3：实现 async throws 生产重载与可注入内部重载。**

```swift
workspace.openApplication(at: url, configuration: configuration) { _, error in
    if let error {
        continuation.resume(throwing: error)
    } else {
        continuation.resume()
    }
}
```

保存路径存在时只尝试该路径；路径不存在时才按 bundle identifier 回退；两条路径都传播 completion error。

- [ ] **步骤 4：调用端 await 启动，并仅在当前 generation 仍有效时显示失败。**

- [ ] **步骤 5：运行完整回归，确认 GREEN。**

### 任务 5：更新中文文档

**文件：**
- 修改：`README.md:52-81`
- 修改：`docs/README-developer.md:20-70`

- [ ] **步骤 1：README 改为当前切换方式。**

有物理栏时可选“物理 Touch Bar”或“独立浮窗”；无物理栏时强制独立浮窗。删除默认浮窗、附着镜像左右的旧描述。

- [ ] **步骤 2：开发者说明删除可拖动镜像和 attached rail。**

改为镜像点击穿透、设置定位、双切换模式和软件 Workspace 回退现状；保留双 modal 说明。

- [ ] **步骤 3：搜索旧文案，预期无匹配。**

```sh
rg -n "附着在镜像|附着切换|左侧或右侧|可拖拽镜像|背景接收鼠标拖拽" \
  README.md docs/README-developer.md
```

### 任务 6：完整验证

- [ ] **步骤 1：运行 `Scripts/run-regression.sh`。**

预期 exit 0，并输出 `ToubarReplace smoke test passed`。

- [ ] **步骤 2：运行脚本语法、diff 和状态检查。**

```sh
zsh -n Packaging/build-app.sh Scripts/run-regression.sh
git diff --check
git status --short
```

- [ ] **步骤 3：复核架构常量。**

```sh
rg -n "placement|presentationMode|maximumContentWidth|settleDuration" \
  Sources/ToubarReplace/WorkspaceTouchBar.swift \
  Sources/ToubarReplace/ContentView.swift
```

预期：镜像 placement `0`、Workspace placement `1`、mode `app`、cap `1010`、settle `221ms` 均未改变。

- [ ] **步骤 4：交付说明记录真机待验项。**

自动回归覆盖软件路径和异步逻辑；物理 Touch Bar 的睡眠唤醒、Workspace 往返及设置开关仍需 Intel Touch Bar 真机手测。

