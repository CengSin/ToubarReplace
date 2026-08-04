import CoreGraphics
import Foundation

enum ToubarReplaceSmokeTest {
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
        let workspaceRootSize = TouchBarWindowMetrics.rootSize(
            forMirrorSize: TouchBarWindowMetrics.defaultSize
        )
        expect(
            workspaceRootSize == CGSize(width: 1_186, height: 35),
            "Workspace rail must extend rather than shrink the mirror viewport",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.mirrorSize(
                forRootSize: workspaceRootSize
            ) == TouchBarWindowMetrics.defaultSize,
            "Workspace root-to-mirror conversion must round-trip",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.rootSize(
                forMirrorSize: TouchBarWindowMetrics.minimumSize
            ).width == TouchBarWindowMetrics.minimumSize.width + 36,
            "minimum root width must reserve the Workspace rail",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.rootSize(
                forMirrorSize: TouchBarWindowMetrics.defaultSize,
                edgeRailWidth: 0
            ) == TouchBarWindowMetrics.defaultSize,
            "floating Workspace switcher must not change the mirror window size",
            failures: &failures
        )
        expect(
            WorkspaceTouchBarLayout.presentationMode == "app"
                && WorkspaceTouchBarLayout.placement == 1,
            "Workspace must use the full-width Touch Bar presentation",
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
            WorkspaceTouchBarLayout.pathFraction == 0.70,
            "Workspace path region must use seventy percent of the content",
            failures: &failures
        )
        expect(
            WorkspaceTouchBarLayout.preferredContentWidth == 680
                && WorkspaceTouchBarStyle.controlHeight == 30
                && WorkspaceTouchBarStyle.cornerRadius == 6.25
                && WorkspaceTouchBarStyle.agentItemWidth == 32
                && WorkspaceTouchBarLayout.contentGap == 12,
            "Workspace icon row must keep the compact geometry",
            failures: &failures
        )
        expect(
            WorkspaceTouchBarStyle.failureSymbolName == nil,
            "undisplayed directories must not use a warning symbol",
            failures: &failures
        )
        let workspaceRegions = WorkspaceTouchBarLayout.regionFrames(
            in: NSRect(x: 0, y: 0, width: 1_000, height: 30)
        )
        expect(
            workspaceRegions.path.width > workspaceRegions.agents.width
                && workspaceRegions.path.maxX
                    < workspaceRegions.agents.minX,
            "Workspace 70/30 regions must be separate and ordered",
            failures: &failures
        )
        let centeredWorkspaceControl = WorkspaceTouchBarLayout
            .centeredControlFrame(
                in: workspaceRegions.path,
                preferredWidth: 160
            )
        expect(
            centeredWorkspaceControl.midX == workspaceRegions.path.midX
                && centeredWorkspaceControl.midY
                    == workspaceRegions.path.midY
                && centeredWorkspaceControl.height
                    == WorkspaceTouchBarStyle.controlHeight,
            "Workspace controls must stay centered inside their regions",
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
            WorkspaceSwitcherSide.allCases == [.left, .right],
            "Workspace switcher side ordering changed unexpectedly",
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
        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
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
