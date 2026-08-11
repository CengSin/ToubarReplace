import AppKit
import CoreGraphics
import Foundation

enum ToubarReplaceSmokeTest {
    @MainActor
    static func failures() -> [String] {
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
}
