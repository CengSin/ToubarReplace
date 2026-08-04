import AppKit
import Darwin

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
        windowController = controller
        installStatusItem()
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController?.stop()
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
                currentPixelSize: windowController?.mirrorPixelSize
                    ?? TouchBarPreferences.mirrorPixelSize,
                currentFramesPerSecond: windowController?.displayFramesPerSecond
                    ?? TouchBarPreferences.displayFramesPerSecond,
                onPositionChanged: { [weak self] position in
                    self?.windowController?.setDisplayPosition(position)
                },
                onPixelSizeChanged: { [weak self] pixelSize in
                    self?.windowController?.setMirrorPixelSize(pixelSize)
                },
                onFramesPerSecondChanged: { [weak self] framesPerSecond in
                    self?.windowController?.setDisplayFramesPerSecond(
                        framesPerSecond
                    )
                },
                onWindowClosed: {
                    NSApp.setActivationPolicy(.accessory)
                }
            )
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
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

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}

@main
@MainActor
struct ToubarReplaceMain {
    static func main() {
        if CommandLine.arguments.contains("--smoke-test") {
            let failures = ToubarReplaceSmokeTest.failures()
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
