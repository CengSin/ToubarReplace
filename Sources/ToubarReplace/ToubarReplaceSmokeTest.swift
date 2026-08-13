import AppKit
import CoreGraphics
import Foundation

@MainActor
private final class SmokeFrameDeliveryProbe {
    var deliveredWidths: [Int] = []
}

enum ToubarReplaceSmokeTest {
    @MainActor
    static func failures() async -> [String] {
        enum CustomAppOpenTestError: Error {
            case rejected
        }

        var failures: [String] = []

        expect(
            TouchBarWindowMetrics.defaultSize
                == CGSize(width: 1_150, height: 35),
            "default mirror size changed unexpectedly",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.minimumSize.width
                < TouchBarWindowMetrics.defaultSize.width,
            "minimum mirror width must be below the default width",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.pixelSize(
                forPointSize: CGSize(width: 1_150, height: 35),
                backingScaleFactor: 2
            ) == CGSize(width: 2_300, height: 70),
            "point-to-pixel conversion changed unexpectedly",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.rootSize(
                forMirrorSize: TouchBarWindowMetrics.defaultSize
            ) == TouchBarWindowMetrics.defaultSize,
            "mirror root size equals viewport (no attached switcher rail)",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.rootSize(
                forMirrorSize: TouchBarWindowMetrics.minimumSize
            ) == TouchBarWindowMetrics.minimumSize,
            "minimum root size equals minimum mirror size",
            failures: &failures
        )
        expect(
            WorkspaceTouchBarLayout.presentationMode == "app"
                && WorkspaceTouchBarLayout.placement == 1,
            "Workspace must use the full-width Touch Bar presentation",
            failures: &failures
        )
        expect(
            MirrorSceneTransition.fadeDuration > 0
                && MirrorSceneTransition.fadeDuration <= 0.3,
            "mirror scene cover fade should be a short crossfade",
            failures: &failures
        )
        expect(
            MirrorSceneTransition.settleDuration > .milliseconds(0)
                && MirrorSceneTransition.settleDuration <= .milliseconds(500),
            "mirror scene cover settle should hide modal-swap glitches briefly",
            failures: &failures
        )
        expect(
            WorkspacePresentationModePolicy.dismissalAction(
                currentMode: "app",
                workspaceMode: "app",
                previousMode: "quickActions",
                hadPreviousMode: true
            ) == .set("quickActions"),
            "closing Workspace must restore the mode saved at presentation",
            failures: &failures
        )
        expect(
            !WorkspacePresentationInterruptionPolicy.shouldInterrupt(
                isPresented: true,
                hasAttachedToWindow: true,
                isExplicitlyDismissing: false,
                isCurrentlyAttached: false,
                currentMode: "app",
                workspaceMode: "app"
            ),
            "transient Touch Bar detachment must not reset Workspace",
            failures: &failures
        )
        expect(
            WorkspacePresentationInterruptionPolicy.shouldInterrupt(
                isPresented: true,
                hasAttachedToWindow: true,
                isExplicitlyDismissing: false,
                isCurrentlyAttached: false,
                currentMode: "spaces",
                workspaceMode: "app"
            ),
            "an external system mode change must reset Workspace",
            failures: &failures
        )
        expect(
            WorkspacePresentationModePolicy.dismissalAction(
                currentMode: "spaces",
                workspaceMode: "app",
                previousMode: "quickActions",
                hadPreviousMode: true
            ) == .preserveCurrent,
            "closing Workspace must preserve a mode changed by the user",
            failures: &failures
        )
        expect(
            WorkspacePresentationModePolicy.dismissalAction(
                currentMode: "app",
                workspaceMode: "app",
                previousMode: nil,
                hadPreviousMode: false
            ) == .remove,
            "closing Workspace must remove an originally absent mode",
            failures: &failures
        )
        expect(
            CustomWorkspaceAppList.maxCount == 3,
            "Workspace custom apps must cap at three favorites",
            failures: &failures
        )
        let pinSeed = [
            CustomWorkspaceApp(
                bundleIdentifier: "a.one",
                applicationPath: "/Applications/One.app",
                displayName: "One"
            ),
            CustomWorkspaceApp(
                bundleIdentifier: "a.two",
                applicationPath: "/Applications/Two.app",
                displayName: "Two"
            ),
            CustomWorkspaceApp(
                bundleIdentifier: "a.three",
                applicationPath: "/Applications/Three.app",
                displayName: "Three"
            ),
        ]
        let fullAdd = CustomWorkspaceAppList.adding(
            CustomWorkspaceApp(
                bundleIdentifier: "a.four",
                applicationPath: "/Applications/Four.app",
                displayName: "Four"
            ),
            to: pinSeed
        )
        expect(
            fullAdd == nil,
            "custom app add must refuse when already at maxCount",
            failures: &failures
        )
        let replaceMid = CustomWorkspaceAppList.replacing(
            at: 1,
            with: CustomWorkspaceApp(
                bundleIdentifier: "a.four",
                applicationPath: "/Applications/Four.app",
                displayName: "Four"
            ),
            in: pinSeed
        )
        expect(
            replaceMid?.map(\.bundleIdentifier) == ["a.one", "a.four", "a.three"],
            "custom app replace must update the chosen slot only",
            failures: &failures
        )
        let refreshExisting = CustomWorkspaceAppList.adding(
            CustomWorkspaceApp(
                bundleIdentifier: "a.two",
                applicationPath: "/Applications/Two.app",
                displayName: "Two"
            ),
            to: pinSeed
        )
        expect(
            refreshExisting?.map(\.bundleIdentifier)
                == ["a.one", "a.two", "a.three"],
            "re-adding an existing custom app must refresh in place",
            failures: &failures
        )
        let removed = CustomWorkspaceAppList.removing(at: 0, from: pinSeed)
        expect(
            removed?.map(\.bundleIdentifier) == ["a.two", "a.three"],
            "custom app remove must drop the chosen slot",
            failures: &failures
        )
        let appendWhenRoom = CustomWorkspaceAppList.adding(
            CustomWorkspaceApp(
                bundleIdentifier: "a.four",
                applicationPath: "/Applications/Four.app",
                displayName: "Four"
            ),
            to: Array(pinSeed.prefix(2))
        )
        expect(
            appendWhenRoom?.map(\.bundleIdentifier)
                == ["a.one", "a.two", "a.four"],
            "custom app add must append when under capacity",
            failures: &failures
        )
        let missingCustomApp = CustomWorkspaceApp(
            bundleIdentifier: "a.missing",
            applicationPath:
                "/private/tmp/ToubarReplaceMissingCustomApp-\(UUID().uuidString).app",
            displayName: "Missing"
        )
        let fallbackCustomAppURL = URL(
            fileURLWithPath: "/Applications/Fallback.app",
            isDirectory: true
        )
        do {
            try await CustomWorkspaceAppLauncher.open(
                missingCustomApp,
                fileManager: .default,
                resolveBundleIdentifier: { _ in fallbackCustomAppURL },
                openApplication: { _ in
                    throw CustomAppOpenTestError.rejected
                }
            )
            failures.append("自定义 App completion error 不得被忽略")
        } catch CustomAppOpenTestError.rejected {
            // Expected: completion errors must reach the caller.
        } catch {
            failures.append("自定义 App 返回了意外错误：\(error)")
        }
        expect(
            WorkspaceTouchBarLayout.totalUnits == 10
                && WorkspaceTouchBarLayout.pathUnits == 4
                && WorkspaceTouchBarLayout.agentsUnits == 3
                && WorkspaceTouchBarLayout.customUnits == 3
                && abs(WorkspaceTouchBarLayout.pathRegionScale - 1.0) < 0.001
                && WorkspaceTouchBarLayout.minimumAgentsCustomWidth == 280
                && WorkspaceTouchBarLayout.minimumContentWidth == 400
                && WorkspaceTouchBarLayout.designReferenceBarWidth == 1_010
                && WorkspaceTouchBarLayout.maximumContentWidth == 1_010
                && WorkspaceTouchBarLayout.switcherWidth == 44
                && WorkspaceTouchBarLayout.zoneContentInset == 6
                && WorkspaceTouchBarLayout.slotVerticalInset == 3
                && WorkspaceTouchBarStyle.controlHeight == 30
                && WorkspaceTouchBarStyle.cornerRadius == 7
                && WorkspaceTouchBarStyle.trayCornerRadius == 8
                && WorkspaceTouchBarStyle.agentIconSize == 22
                && WorkspaceTouchBarStyle.itemSpacing == 6
                && WorkspaceTouchBarStyle.canvasInset == 4,
            "Workspace design-v2 10-unit geometry must stay stable",
            failures: &failures
        )
        let settingsPreferred = WorkspaceTouchBarLayout.preferredContentSize(
            mirrorPixelSize: TouchBarPreferences.defaultMirrorPixelSize,
            backingScaleFactor: 2
        )
        // Mirror default 2300×70 @2x → 1150×35 points, but item width is capped
        // to maximumContentWidth (1010) so trailing custom slots are not clipped.
        expect(
            abs(
                settingsPreferred.width
                    - WorkspaceTouchBarLayout.maximumContentWidth
            ) < 0.5
                && abs(settingsPreferred.height - 35) < 0.5,
            "preferred Workspace width must cap at hardware-class maximumContentWidth",
            failures: &failures
        )
        let narrowPreferred = WorkspaceTouchBarLayout.preferredContentWidth(
            mirrorPixelSize: CGSize(width: 400, height: 60),
            backingScaleFactor: 2
        )
        expect(
            narrowPreferred == WorkspaceTouchBarLayout.minimumContentWidth,
            "preferred width must not fall below minimumContentWidth",
            failures: &failures
        )
        let midMirrorPreferred = WorkspaceTouchBarLayout.preferredContentWidth(
            mirrorPixelSize: CGSize(width: 1_600, height: 70),
            backingScaleFactor: 2
        )
        expect(
            abs(midMirrorPreferred - 800) < 0.5,
            "preferred width must track mirror points when below the hardware cap",
            failures: &failures
        )
        let strip = WorkspaceTouchBarLayout.stripFrames(
            in: NSRect(
                x: 0,
                y: 0,
                width: WorkspaceTouchBarLayout.designReferenceBarWidth,
                height: 30
            )
        )
        let stripUsable = strip.tray.width
            - WorkspaceTouchBarLayout.trayTrailingSafeInset
        let expectedPathWidth = floor(
            floor(
                stripUsable * CGFloat(WorkspaceTouchBarLayout.pathUnits)
                    / CGFloat(WorkspaceTouchBarLayout.totalUnits)
            ) * WorkspaceTouchBarLayout.pathRegionScale
        )
        expect(
            abs(strip.switcher.width - WorkspaceTouchBarLayout.switcherWidth) < 1
                && strip.tray.minX > strip.switcher.maxX
                && abs(strip.path.width - expectedPathWidth) < 1
                && abs(strip.agents.width - strip.custom.width) <= 1
                && abs(
                    strip.path.width + strip.agents.width + strip.custom.width
                        - stripUsable
                ) < 1
                && abs(
                    strip.switcher.width + WorkspaceTouchBarLayout.switcherContentGap
                        + strip.tray.width
                        + WorkspaceTouchBarStyle.canvasInset * 2
                        - WorkspaceTouchBarLayout.designReferenceBarWidth
                ) < 2,
            "full bar strip: switcher outside; path 4/10 base; agents|custom share rest",
            failures: &failures
        )
        // Short path preferred width must not shrink the base 4/10 zone.
        let fixedGridStrip = WorkspaceTouchBarLayout.stripFrames(
            in: NSRect(
                x: 0,
                y: 0,
                width: WorkspaceTouchBarLayout.designReferenceBarWidth,
                height: 30
            ),
            pathPreferredWidth: 160
        )
        expect(
            abs(fixedGridStrip.path.width - strip.path.width) < 1
                && abs(fixedGridStrip.agents.width - strip.agents.width) < 1
                && abs(fixedGridStrip.custom.width - strip.custom.width) < 1,
            "short path preferred must not shrink the base 4/10 zone",
            failures: &failures
        )
        // Long folder name: path zone grows so the plate (and title) can fit.
        let longNamePreferred: CGFloat = 460
        let expandedStrip = WorkspaceTouchBarLayout.stripFrames(
            in: NSRect(
                x: 0,
                y: 0,
                width: WorkspaceTouchBarLayout.designReferenceBarWidth,
                height: 30
            ),
            pathPreferredWidth: longNamePreferred
        )
        let expandedUsable = expandedStrip.tray.width
            - WorkspaceTouchBarLayout.trayTrailingSafeInset
        let expectedExpandedPath = min(
            floor(
                longNamePreferred
                    + WorkspaceTouchBarLayout.zoneContentInset * 2
            ),
            floor(
                expandedUsable
                    - WorkspaceTouchBarLayout.minimumAgentsCustomWidth
            ),
            expandedUsable
        )
        expect(
            expandedStrip.path.width > strip.path.width + 1
                && abs(expandedStrip.path.width - expectedExpandedPath) < 1
                && abs(
                    expandedStrip.agents.width - expandedStrip.custom.width
                ) <= 1
                && expandedStrip.agents.width
                    + expandedStrip.custom.width
                    + 0.5
                    >= WorkspaceTouchBarLayout.minimumAgentsCustomWidth,
            "long path preferred must grow path zone and keep agents|custom floor",
            failures: &failures
        )
        let pathPillProbe = WorkspaceTouchBarPathView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 30)
        )
        pathPillProbe.display(
            image: nil,
            title: "VeryLongWorkspaceFolderNameForDisplay",
            toolTip: nil,
            enabled: true
        )
        let measuredPill = pathPillProbe.preferredPillWidth
        expect(
            measuredPill > 200,
            "path preferredPillWidth must track long folder title width",
            failures: &failures
        )
        let pathControl = WorkspaceTouchBarPathView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 30)
        )
        var pathControlActivated = false
        pathControl.onActivate = {
            pathControlActivated = true
        }
        pathControl.display(
            image: nil,
            title: "选择项目",
            toolTip: nil,
            enabled: true
        )
        pathControl.layoutSubtreeIfNeeded()
        pathControl.subviews.compactMap { $0 as? NSButton }
            .first?.performClick(nil)
        expect(
            pathControlActivated,
            "Workspace path region must expose a real button action",
            failures: &failures
        )
        for agentID in AgentID.allCases {
            let defaultIcon = WorkspaceTouchBarStyle.agentDefaultIcon(for: agentID)
            expect(
                defaultIcon != nil,
                "Agent \(agentID.rawValue) must ship a bundled default icon",
                failures: &failures
            )
            let agentWithoutAppIcon = AvailableAgent(
                id: agentID,
                displayName: agentID.rawValue,
                iconApplicationURL: nil,
                launchStrategy: .process(
                    executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                    leadingArguments: []
                )
            )
            let resolved = WorkspaceTouchBarStyle.agentIcon(for: agentWithoutAppIcon)
            expect(
                resolved != nil && resolved?.isTemplate == false,
                "Agent \(agentID.rawValue) without app icon must resolve a non-template default",
                failures: &failures
            )
        }
        let sampleAgent = AvailableAgent(
            id: .codex,
            displayName: "Codex",
            iconApplicationURL: nil,
            launchStrategy: .process(
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                leadingArguments: []
            )
        )
        let agentRow = AgentIconRowView(
            frame: NSRect(x: 0, y: 0, width: 200, height: 30)
        )
        var agentActivatedName: String?
        agentRow.onAgentActivated = { agent in
            agentActivatedName = agent.displayName
        }
        agentRow.display(agents: [sampleAgent])
        agentRow.setEnabled(true)
        agentRow.layoutSubtreeIfNeeded()
        let agentButtons = agentRow.subviews.compactMap {
            $0 as? WorkspaceChromeButton
        }
        expect(
            agentButtons.count == 1,
            "Workspace agent region must use WorkspaceChromeButton slots",
            failures: &failures
        )
        agentButtons.first?.performClick(nil)
        expect(
            agentActivatedName == "Codex",
            "Workspace agent region must expose a real button action",
            failures: &failures
        )
        let chromeProbe = WorkspaceChromeButton(
            frame: NSRect(x: 0, y: 0, width: 44, height: 28)
        )
        chromeProbe.highlight(true)
        expect(
            chromeProbe.layer?.borderWidth == 1
                && chromeProbe.layer?.backgroundColor != nil,
            "Workspace chrome button must show pressed chrome while highlighted",
            failures: &failures
        )
        chromeProbe.highlight(false)
        expect(
            chromeProbe.layer?.borderWidth == 0,
            "Workspace chrome button must clear pressed chrome after release",
            failures: &failures
        )
        expect(
            WorkspaceTouchBarStyle.failureSymbolName == nil,
            "undisplayed directories must not use a warning symbol",
            failures: &failures
        )
        let barWidth: CGFloat = 1_000
        let barBounds = NSRect(x: 0, y: 0, width: barWidth, height: 30)
        let fullStrip = WorkspaceTouchBarLayout.stripFrames(in: barBounds)
        let usableTray = fullStrip.tray.width
            - WorkspaceTouchBarLayout.trayTrailingSafeInset
        let expectedFullPath = floor(
            floor(
                usableTray * CGFloat(WorkspaceTouchBarLayout.pathUnits)
                    / CGFloat(WorkspaceTouchBarLayout.totalUnits)
            ) * WorkspaceTouchBarLayout.pathRegionScale
        )
        expect(
            fullStrip.tray.maxX <= barWidth - WorkspaceTouchBarStyle.canvasInset + 0.5
                && fullStrip.switcher.minX
                    >= WorkspaceTouchBarStyle.canvasInset - 0.5,
            "strip must stay inside canvas insets",
            failures: &failures
        )
        expect(
            fullStrip.path.maxX <= fullStrip.agents.minX + 0.5
                && fullStrip.agents.maxX <= fullStrip.custom.minX + 0.5,
            "Workspace path|agents|custom regions must be separate and ordered",
            failures: &failures
        )
        expect(
            abs(fullStrip.path.width - expectedFullPath) < 1,
            "path region base must be 4/10 of usable tray × pathRegionScale",
            failures: &failures
        )
        expect(
            abs(fullStrip.agents.width - fullStrip.custom.width) <= 1,
            "agents and custom must share the remainder equally",
            failures: &failures
        )
        expect(
            abs(
                fullStrip.path.width
                    + fullStrip.agents.width
                    + fullStrip.custom.width
                    - usableTray
            ) < 1,
            "three zones must cover the usable tray width",
            failures: &failures
        )
        expect(
            WorkspaceTouchBarLayout.agentSlotCount(agentCount: 4) == 4
                && WorkspaceTouchBarLayout.customSlotCount(appCount: 2) == 3
                && WorkspaceTouchBarLayout.customSlotCount(appCount: 0) == 1,
            "slot counts: agents by count; custom apps+settings or empty label",
            failures: &failures
        )
        let agentsInner = WorkspaceTouchBarLayout.zoneContentRect(
            fullStrip.agents
        )
        let agentSlot = WorkspaceTouchBarLayout.equalSlotWidth(
            regionWidth: agentsInner.width,
            slotCount: 4
        )
        let customInner = WorkspaceTouchBarLayout.zoneContentRect(
            fullStrip.custom
        )
        let customSlot = WorkspaceTouchBarLayout.equalSlotWidth(
            regionWidth: customInner.width,
            slotCount: 3
        )
        expect(
            agentSlot > 0 && customSlot > 0,
            "equal slots inside agents/custom must be positive",
            failures: &failures
        )
        let slots = WorkspaceTouchBarLayout.slotFrames(
            in: agentsInner,
            slotCount: 4
        )
        let tiledWidth = slots.reduce(CGFloat(0)) { partial, slot in
            partial + slot.width
        } + WorkspaceTouchBarStyle.itemSpacing * 3
        expect(
            slots.count == 4
                && abs(slots[0].width - agentSlot) < 1
                && abs(tiledWidth - agentsInner.width) < 4
                && slots[0].minX == agentsInner.minX,
            "agent slots must equal-split the inset agents zone",
            failures: &failures
        )
        expect(
            WorkspaceFloatingSwitcherView.Gesture.shouldToggle(
                duration: 0.1,
                distance: 0
            ),
            "short stationary switcher presses must toggle Workspace",
            failures: &failures
        )
        expect(
            !WorkspaceFloatingSwitcherView.Gesture.shouldToggle(
                duration: 0.5,
                distance: 0
            ) && !WorkspaceFloatingSwitcherView.Gesture.shouldToggle(
                duration: 0.1,
                distance: 12
            ),
            "long presses and drags must not toggle Workspace",
            failures: &failures
        )
        expect(
            AgentID.allCases == [.codex, .claudeCode, .cursor, .grokBuild],
            "default Agent ordering changed unexpectedly",
            failures: &failures
        )
        expect(
            FrontmostAppContext(
                bundleIdentifier: FrontmostAppContext.finderBundleIdentifier,
                localizedName: "Finder",
                processIdentifier: nil,
                capturedAt: Date()
            ).isFinder,
            "Finder context recognition changed unexpectedly",
            failures: &failures
        )
        expect(
            TerminalAdapterID.allCases == [.otty, .terminal],
            "supported terminal adapter ordering changed unexpectedly",
            failures: &failures
        )
        expect(
            AgentLaunchCommand.cursorLeadingArguments == ["--new-window"],
            "Cursor must open the selected project in a new window",
            failures: &failures
        )
        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
        ).standardizedFileURL
        let agentProcess = AgentProcess.make(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: ["workspace-test"],
            workingDirectory: currentDirectory,
            inheritedEnvironment: ["PATH": "/usr/bin"]
        )
        expect(
            agentProcess.currentDirectoryURL?.standardizedFileURL
                == currentDirectory,
            "Agent processes must inherit the selected Workspace directory",
            failures: &failures
        )
        expect(
            agentProcess.arguments == ["workspace-test"],
            "Agent process configuration must preserve launch arguments",
            failures: &failures
        )
        expect(
            agentProcess.environment?["PATH"] == "/usr/bin:/usr/bin",
            "Agent process configuration must preserve executable discovery",
            failures: &failures
        )
        let pwdPipe = Pipe()
        let pwdProcess = AgentProcess.make(
            executableURL: URL(fileURLWithPath: "/bin/pwd"),
            arguments: [],
            workingDirectory: currentDirectory,
            inheritedEnvironment: ["PATH": "/usr/bin:/bin"]
        )
        pwdProcess.standardOutput = pwdPipe
        pwdProcess.standardError = FileHandle.nullDevice
        do {
            try pwdProcess.run()
            pwdProcess.waitUntilExit()
            let output = String(
                data: pwdPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            expect(
                pwdProcess.terminationStatus == 0
                    && output == currentDirectory.path,
                "Agent subprocess did not start in the selected "
                    + "Workspace directory",
                failures: &failures
            )
        } catch {
            failures.append(
                "Agent subprocess working-directory probe failed: \(error)"
            )
        }
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
            expect(
                status == 7,
                "必须传播辅助进程的真实退出码",
                failures: &failures
            )
        } catch {
            failures.append(
                "辅助进程返回了意外错误：\(error.localizedDescription)"
            )
        }
        let testToolURL = URL(fileURLWithPath: "/tmp/Claude Tool/claude")
        let testProjectURL = URL(fileURLWithPath: "/tmp/Project Folder")
        expect(
            TerminalLaunchCommand.ottyArguments(
                toolURL: testToolURL,
                projectDirectory: testProjectURL
            ) == [
                "open",
                "--command",
                "export PATH='/tmp/Claude Tool':$PATH; exec '/tmp/Claude Tool/claude'",
                "/tmp/Project Folder",
            ],
            "Otty launch arguments must preserve the command and project path",
            failures: &failures
        )
        expect(
            TerminalLaunchCommand.shellQuote("a'b") == "'a'\\''b'",
            "terminal shell quoting must escape single quotes",
            failures: &failures
        )
        let terminalArguments = TerminalLaunchCommand
            .terminalAppleScriptArguments(
                toolURL: testToolURL,
                projectDirectory: testProjectURL
            )
        expect(
            terminalArguments.count == 4
                && terminalArguments[1].contains("terminalWasRunning")
                && terminalArguments[1].contains(
                    "do script shellCommand in front window"
                ),
            "Terminal launch must reuse its initial window when starting",
            failures: &failures
        )
        expect(
            WorkspacePathResolver.existingDirectory(at: currentDirectory)
                != nil,
            "Workspace directory validation rejected the current directory",
            failures: &failures
        )
        expect(
            FinderPathResolver.directoryURL(
                from: "  \(currentDirectory.path)\n"
            ) == currentDirectory.standardizedFileURL,
            "Finder path parsing must trim Apple Event output",
            failures: &failures
        )
        expect(
            WorkspacePathResolver.existingDirectory(
                at: currentDirectory.appendingPathComponent("Package.swift")
            ) == nil,
            "Workspace directory validation accepted a file",
            failures: &failures
        )
        expect(
            TouchBarCapture.minimumFramesPerSecond == 1
                && TouchBarCapture.defaultFramesPerSecond == 30
                && TouchBarCapture.maximumFramesPerSecond == 30,
            "capture frame-rate bounds changed unexpectedly",
            failures: &failures
        )
        expect(
            TouchBarIdleOpacity.active == 1
                && TouchBarIdleOpacity.idle == 0.3
                && TouchBarIdleOpacity.delay == .seconds(5),
            "idle-opacity defaults changed unexpectedly",
            failures: &failures
        )
        expect(
            !TouchBarIdleOpacity.shouldPollOcclusion(isIdle: false)
                && TouchBarIdleOpacity.shouldPollOcclusion(isIdle: true),
            "occlusion polling must run only after capture becomes idle",
            failures: &failures
        )
        expect(
            TouchBarIdleOpacity.targetAlpha(
                isIdle: false,
                isObscuringOtherAppContent: true
            ) == TouchBarIdleOpacity.active
                && TouchBarIdleOpacity.targetAlpha(
                    isIdle: true,
                    isObscuringOtherAppContent: true
                ) == TouchBarIdleOpacity.idle
                && TouchBarIdleOpacity.targetAlpha(
                    isIdle: true,
                    isObscuringOtherAppContent: false
                ) == TouchBarIdleOpacity.active,
            "idle opacity must remain active unless idle content is obscured",
            failures: &failures
        )
        if let firstImage = makeTestImage(width: 1),
            let secondImage = makeTestImage(width: 2),
            let latestImage = makeTestImage(width: 3)
        {
            let probe = SmokeFrameDeliveryProbe()
            let coalescer = TouchBarFrameDeliveryCoalescer { image in
                probe.deliveredWidths.append(image.width)
            }
            coalescer.submit(firstImage)
            coalescer.submit(secondImage)
            coalescer.submit(latestImage)
            await Task.yield()
            await Task.yield()
            expect(
                probe.deliveredWidths == [3],
                "main-actor frame delivery must coalesce queued frames to the latest",
                failures: &failures
            )
        } else {
            failures.append("could not create frame-coalescing smoke-test images")
        }
        expect(
            !MirrorWindowOcclusion.isObscurableContentWindow(
                ownerPID: 42,
                selfPID: 42,
                layer: 0,
                bundleIdentifier: "com.example.App",
                ownerName: "App"
            ),
            "own process windows must not count as occlusion content",
            failures: &failures
        )
        expect(
            !MirrorWindowOcclusion.isObscurableContentWindow(
                ownerPID: 7,
                selfPID: 42,
                layer: 0,
                bundleIdentifier: "com.apple.dock",
                ownerName: "Dock"
            ),
            "Dock must not count as occlusion content",
            failures: &failures
        )
        expect(
            MirrorWindowOcclusion.isObscurableContentWindow(
                ownerPID: 7,
                selfPID: 42,
                layer: 0,
                bundleIdentifier: "com.google.Chrome",
                ownerName: "Google Chrome"
            ),
            "Chrome content must count as occlusion content",
            failures: &failures
        )
        expect(
            !MirrorWindowOcclusion.isObscurableContentWindow(
                ownerPID: 7,
                selfPID: 42,
                layer: -2_147_483_646,
                bundleIdentifier: nil,
                ownerName: "Wallpaper"
            ),
            "desktop/negative-layer windows must not count as occlusion",
            failures: &failures
        )
        let mirrorBounds = CGRect(x: 100, y: 0, width: 1_000, height: 40)
        let windows: [MirrorOcclusionWindowInfo] = [
            MirrorOcclusionWindowInfo(
                windowNumber: 1,
                ownerPID: 42,
                layer: 3,
                bounds: mirrorBounds,
                ownerName: "ToubarReplace",
                bundleIdentifier: "com.toubarreplace.app"
            ),
            MirrorOcclusionWindowInfo(
                windowNumber: 2,
                ownerPID: 7,
                layer: 0,
                bounds: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                ownerName: "Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            ),
        ]
        expect(
            MirrorWindowOcclusion.isObscuringOtherAppContent(
                mirrorWindowNumber: 1,
                mirrorBounds: mirrorBounds,
                selfPID: 42,
                windowsFrontToBack: windows
            ),
            "mirror over Chrome must enable occlusion-gated idle fade",
            failures: &failures
        )
        expect(
            !MirrorWindowOcclusion.isObscuringOtherAppContent(
                mirrorWindowNumber: 1,
                mirrorBounds: mirrorBounds,
                selfPID: 42,
                windowsFrontToBack: [
                    windows[0],
                    MirrorOcclusionWindowInfo(
                        windowNumber: 3,
                        ownerPID: 9,
                        layer: 0,
                        bounds: CGRect(x: 0, y: 200, width: 800, height: 600),
                        ownerName: "Notes",
                        bundleIdentifier: "com.apple.Notes"
                    ),
                ]
            ),
            "mirror over empty strip (app window elsewhere) must not enable idle fade",
            failures: &failures
        )
        expect(
            MirrorWindowOcclusion.overlapArea(
                CGRect(x: 0, y: 0, width: 100, height: 40),
                CGRect(x: 50, y: 0, width: 100, height: 40)
            ) == 2_000,
            "overlap area math",
            failures: &failures
        )
        let converted = MirrorWindowOcclusion.cocoaRect(
            fromCGWindowBounds: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            mainDisplayHeight: 900
        )
        expect(
            converted == CGRect(x: 0, y: 0, width: 1_440, height: 900),
            "main-display full CG bounds must map to Cocoa (0,0,W,H)",
            failures: &failures
        )
        expect(
            TouchBarSystemState.isControlStripExplicitlyEmpty(
                fullCustomized: [],
                miniCustomized: []
            ),
            "empty Control Strip must be detected",
            failures: &failures
        )
        expect(
            !TouchBarSystemState.isControlStripExplicitlyEmpty(
                fullCustomized: ["com.apple.system.volume"],
                miniCustomized: []
            ),
            "non-empty Control Strip must not be reported as empty",
            failures: &failures
        )
        expect(
            !TouchBarSystemState.isControlStripExplicitlyEmpty(
                fullCustomized: nil,
                miniCustomized: []
            ),
            "missing Control Strip settings must not be reported as empty",
            failures: &failures
        )

        for presentationMode in [
            "app",
            "appWithControlStrip",
            "quickActions",
            "quickActionsWithControlStrip",
            "workflows",
            "workflowsWithControlStrip",
        ] {
            expect(
                TouchBarSystemState.allowsEmptyContent(
                    presentationMode: presentationMode
                ),
                "\(presentationMode) must allow empty content",
                failures: &failures
            )
        }
        for presentationMode in [
            "fullControlStrip",
            "functionKeys",
            "spaces",
            "spacesWithControlStrip",
        ] {
            expect(
                !TouchBarSystemState.allowsEmptyContent(
                    presentationMode: presentationMode
                ),
                "\(presentationMode) must not allow empty content",
                failures: &failures
            )
        }
        expect(
            !TouchBarSystemState.allowsEmptyContent(presentationMode: nil),
            "missing presentation mode must not allow empty content",
            failures: &failures
        )

        // Apple Silicon / no-Touch-Bar software Workspace policies.
        expect(
            !TouchBarHardwareCapability.softwareWorkspaceMode(
                canPresentSystemModal: true,
                canCreateDisplayStream: true,
                canInstantiateDisplayStream: true
            ),
            "usable physical Touch Bar stack must not enter software Workspace mode",
            failures: &failures
        )
        expect(
            TouchBarHardwareCapability.softwareWorkspaceMode(
                canPresentSystemModal: false,
                canCreateDisplayStream: true,
                canInstantiateDisplayStream: true
            ),
            "missing system-modal present must enter software Workspace mode",
            failures: &failures
        )
        expect(
            TouchBarHardwareCapability.softwareWorkspaceMode(
                canPresentSystemModal: true,
                canCreateDisplayStream: false,
                canInstantiateDisplayStream: false
            ),
            "missing display-stream symbol must enter software Workspace mode",
            failures: &failures
        )
        expect(
            TouchBarHardwareCapability.softwareWorkspaceMode(
                canPresentSystemModal: true,
                canCreateDisplayStream: true,
                canInstantiateDisplayStream: false
            ),
            "stream symbol without instantiable stream must enter software Workspace mode",
            failures: &failures
        )
        expect(
            SoftwareWorkspaceLaunchPolicy.shouldEnterWorkspaceAtLaunch(
                usesSoftwareWorkspace: true
            )
                && !SoftwareWorkspaceLaunchPolicy.shouldEnterWorkspaceAtLaunch(
                    usesSoftwareWorkspace: false
                ),
            "software mode must default to Workspace at launch; hardware must not",
            failures: &failures
        )
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
        expect(
            WorkspaceAsyncSessionPolicy.canUpdate(
                capturedGeneration: 4,
                currentGeneration: 4,
                scene: .workspace
            ),
            "当前 Workspace generation 应允许异步回写",
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
        expect(
            SoftwareWorkspaceLaunchPolicy.effectiveSwitcherDisplayMode(
                usesSoftwareWorkspace: true,
                preferred: .touchBar
            ) == .floating
                && SoftwareWorkspaceLaunchPolicy.effectiveSwitcherDisplayMode(
                    usesSoftwareWorkspace: false,
                    preferred: .touchBar
                ) == .touchBar,
            "software mode forces floating switcher; hardware honors preference",
            failures: &failures
        )
        expect(
            MirrorClickThroughPolicy.ignoresMouseEvents(
                usesSoftwareWorkspace: false,
                scene: .mirror,
                showsWorkspaceFallback: false
            )
                && MirrorClickThroughPolicy.ignoresMouseEvents(
                    usesSoftwareWorkspace: false,
                    scene: .workspace,
                    showsWorkspaceFallback: false
                ),
            "hardware mirror and physical Workspace must stay click-through",
            failures: &failures
        )
        expect(
            !MirrorClickThroughPolicy.ignoresMouseEvents(
                usesSoftwareWorkspace: true,
                scene: .workspace,
                showsWorkspaceFallback: true
            )
                && !MirrorClickThroughPolicy.ignoresMouseEvents(
                    usesSoftwareWorkspace: false,
                    scene: .workspace,
                    showsWorkspaceFallback: true
                ),
            "desktop Workspace fallback must accept mouse events",
            failures: &failures
        )
        expect(
            MirrorClickThroughPolicy.ignoresMouseEvents(
                usesSoftwareWorkspace: true,
                scene: .mirror,
                showsWorkspaceFallback: false
            ),
            "software idle/mirror surface must stay click-through",
            failures: &failures
        )
        // Live probe: when this Mac has a usable stack, software mode must stay off
        // (Intel Touch Bar regression guard). Soft machines correctly report true.
        if TouchBarHardwareCapability.canPresentSystemModal
            && TouchBarHardwareCapability.canInstantiateDisplayStream
        {
            expect(
                !TouchBarHardwareCapability.usesSoftwareWorkspace,
                "live hardware probe must keep software Workspace mode off",
                failures: &failures
            )
        }

        return failures
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        failures: inout [String]
    ) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func makeTestImage(width: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: width,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}
