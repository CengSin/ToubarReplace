import AppKit
import Darwin
import UniformTypeIdentifiers

@MainActor
final class ToubarReplaceAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: TouchBarWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: TouchBarSettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = TouchBarWindowController()
        controller.onPixelSizeChanged = { [weak self] pixelSize in
            self?.settingsWindowController?.updatePixelSize(pixelSize)
        }
        controller.onRequestWorkspaceDirectory = { [weak self] completion in
            self?.chooseWorkspaceDirectory(completion: completion)
        }
        controller.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        windowController = controller
        installStatusItem()
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Settings / alerts make the app frontmost and can re-show the
        // system-modal close box next to the mirror grid switcher.
        windowController?.suppressPhysicalSwitcherCloseBox()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.inset.filled",
            accessibilityDescription: "ToubarReplace"
        )

        let menu = NSMenu()
        let toggleItem = NSMenuItem(
            title: "显示或隐藏 Touch Bar",
            action: #selector(toggleWindow),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let versionItem = NSMenuItem(
            title: "版本 \(ToubarReplaceAppInfo.version)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let helpItem = NSMenuItem(
            title: "帮助…",
            action: #selector(showHelp),
            keyEquivalent: ""
        )
        helpItem.target = self
        menu.addItem(helpItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 ToubarReplace",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc
    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = TouchBarSettingsWindowController(
                currentPosition: windowController?.displayPosition
                    ?? TouchBarPreferences.displayPosition,
                currentCustomTopLeft: windowController?.customTopLeft
                    ?? (TouchBarPreferences.hasCustomTopLeft
                        ? TouchBarPreferences.customTopLeft
                        : .zero),
                currentPixelSize: windowController?.mirrorPixelSize
                    ?? TouchBarPreferences.mirrorPixelSize,
                currentFramesPerSecond: windowController?.displayFramesPerSecond
                    ?? TouchBarPreferences.displayFramesPerSecond,
                currentWorkspaceSwitcherFloats:
                    windowController?.workspaceSwitcherFloats
                    ?? WorkspacePreferences.floatingSwitcher,
                currentWorkspaceAutoCollapse:
                    windowController?.workspaceAutoCollapse
                    ?? WorkspacePreferences.autoCollapse,
                terminalAdapters:
                    windowController?.availableTerminalAdapters ?? [],
                currentTerminalAdapterID:
                    windowController?.workspaceTerminalAdapterID
                    ?? WorkspacePreferences.terminalAdapterID,
                onPositionChanged: { [weak self] position in
                    self?.windowController?.setDisplayPosition(position)
                    if let topLeft = self?.windowController?.customTopLeft {
                        self?.settingsWindowController?.updateCustomTopLeft(
                            topLeft
                        )
                    }
                },
                onCustomTopLeftChanged: { [weak self] topLeft in
                    self?.windowController?.setCustomTopLeft(topLeft)
                },
                onWorkspaceFloatingSwitcherChanged: { [weak self] floats in
                    self?.windowController?.setWorkspaceSwitcherFloats(floats)
                },
                onWorkspaceAutoCollapseChanged: { [weak self] autoCollapse in
                    self?.windowController?.setWorkspaceAutoCollapse(
                        autoCollapse
                    )
                },
                onTerminalAdapterChanged: { [weak self] adapterID in
                    self?.windowController?.setWorkspaceTerminalAdapterID(
                        adapterID
                    )
                },
                onPixelSizeChanged: { [weak self] pixelSize in
                    self?.windowController?.setMirrorPixelSize(pixelSize)
                },
                onFramesPerSecondChanged: { [weak self] framesPerSecond in
                    self?.windowController?.setDisplayFramesPerSecond(
                        framesPerSecond
                    )
                },
                onPickApplication: { [weak self] completion in
                    self?.chooseCustomApplication(completion: completion)
                },
                onCustomAppsChanged: { [weak self] in
                    self?.windowController?.reloadCustomAppsFromPreferences()
                },
                onWindowClosed: { [weak self] in
                    NSApp.setActivationPolicy(.accessory)
                    self?.windowController?.ensurePhysicalSwitcherPresented()
                }
            )
            windowController?.onCustomTopLeftChanged = {
                [weak self] topLeft in
                self?.settingsWindowController?.updateCustomTopLeft(topLeft)
            }
        }
        // Refresh pin list if settings was already open (e.g. preferences
        // changed externally); always re-show the window.
        settingsWindowController?.reloadCustomAppsRows()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        // Activation can reintroduce the Touch Bar close box; suppress again
        // after the function row rebuilds.
        windowController?.suppressPhysicalSwitcherCloseBox()
        DispatchQueue.main.async { [weak self] in
            self?.windowController?.suppressPhysicalSwitcherCloseBox()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.windowController?.suppressPhysicalSwitcherCloseBox()
        }
    }

    @objc
    private func showHelp() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "ToubarReplace 帮助"
        alert.informativeText = """
        如果镜像窗口显示 Touch Bar 错误，请打开“终端”并依次执行以下命令，随后等待几秒钟让显示流自动恢复：

        \(ToubarReplaceAppInfo.recoveryCommands)

        这些命令会恢复 Control Strip 的默认布局并重启 ControlStrip。
        """
        alert.addButton(withTitle: "完成")

        let settingsIsVisible =
            settingsWindowController?.window?.isVisible == true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        if !settingsIsVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        windowController?.ensurePhysicalSwitcherPresented()
    }

    @objc
    private func toggleWindow() {
        guard let window = windowController?.window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    private func chooseWorkspaceDirectory(
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "选择当前项目目录"
        panel.prompt = "选择项目"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let lastPath = WorkspacePreferences.lastPath {
            panel.directoryURL = lastPath
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            Task { @MainActor in
                let directoryURL = response == .OK ? panel.url : nil
                if self?.settingsWindowController?.window?.isVisible != true {
                    NSApp.setActivationPolicy(.accessory)
                }
                self?.windowController?.ensurePhysicalSwitcherPresented()
                completion(directoryURL)
            }
        }
    }

    private func chooseCustomApplication(
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "选择常用应用"
        panel.prompt = "选择"
        panel.message = "固定到 Workspace 自定义区（最多 3 个，在设置中管理）"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(
            fileURLWithPath: "/Applications",
            isDirectory: true
        )

        // Prefer sheet on settings when visible so activation policy stays
        // consistent with the settings window.
        if let settingsWindow = settingsWindowController?.window,
            settingsWindow.isVisible
        {
            panel.beginSheetModal(for: settingsWindow) { response in
                Task { @MainActor in
                    completion(response == .OK ? panel.url : nil)
                }
            }
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            Task { @MainActor in
                let applicationURL = response == .OK ? panel.url : nil
                if self?.settingsWindowController?.window?.isVisible != true {
                    NSApp.setActivationPolicy(.accessory)
                }
                self?.windowController?.ensurePhysicalSwitcherPresented()
                completion(applicationURL)
            }
        }
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}

@main
@MainActor
struct ToubarReplaceMain {
    static func main() async {
        if CommandLine.arguments.contains("--smoke-test") {
            let failures = await ToubarReplaceSmokeTest.failures()
            guard failures.isEmpty else {
                let message = "ToubarReplace smoke test failed:\n"
                    + failures.map { "- \($0)" }.joined(separator: "\n")
                    + "\n"
                FileHandle.standardError.write(Data(message.utf8))
                exit(EXIT_FAILURE)
            }
            print("ToubarReplace smoke test passed")
            return
        }
        let application = NSApplication.shared
        let delegate = ToubarReplaceAppDelegate()
        application.delegate = delegate
        application.run()
    }
}
