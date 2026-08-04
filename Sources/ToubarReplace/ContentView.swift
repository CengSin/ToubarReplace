import AppKit
import CoreGraphics

struct TouchBarWindowMetrics {
    // This is only the first-run size. It is intentionally not derived from
    // the captured frame: the user can resize the mirror to match their bar.
    static let defaultSize = CGSize(width: 1_150, height: 35)
    static let minimumSize = CGSize(width: 240, height: 18)
    static let edgeRailWidth: CGFloat = 36

    static func pointSize(
        forPixelSize pixelSize: CGSize,
        backingScaleFactor: CGFloat
    ) -> CGSize {
        let scale = max(backingScaleFactor, 1)
        return CGSize(
            width: pixelSize.width / scale,
            height: pixelSize.height / scale
        )
    }

    static func pixelSize(
        forPointSize pointSize: CGSize,
        backingScaleFactor: CGFloat
    ) -> CGSize {
        let scale = max(backingScaleFactor, 1)
        return CGSize(
            width: (pointSize.width * scale).rounded(),
            height: (pointSize.height * scale).rounded()
        )
    }

    static func rootSize(
        forMirrorSize mirrorSize: CGSize,
        edgeRailWidth: CGFloat = TouchBarWindowMetrics.edgeRailWidth
    ) -> CGSize {
        CGSize(
            width: max(mirrorSize.width, 1) + max(edgeRailWidth, 0),
            height: max(mirrorSize.height, 1)
        )
    }

    static func mirrorSize(
        forRootSize rootSize: CGSize,
        edgeRailWidth: CGFloat = TouchBarWindowMetrics.edgeRailWidth
    ) -> CGSize {
        CGSize(
            width: max(rootSize.width - max(edgeRailWidth, 0), 1),
            height: max(rootSize.height, 1)
        )
    }
}

enum TouchBarIdleOpacity {
    static let active: CGFloat = 1
    static let idle: CGFloat = 0.3
    static let delay: Duration = .seconds(5)
}

@MainActor
final class TouchBarIdleOpacityController {
    private weak var window: NSWindow?
    private var idleTask: Task<Void, Never>?
    private var isSuspended = false

    init(window: NSWindow) {
        self.window = window
    }

    func start() {
        registerFrameActivity()
    }

    func stop() {
        idleTask?.cancel()
        idleTask = nil
    }

    func registerFrameActivity() {
        idleTask?.cancel()
        window?.alphaValue = TouchBarIdleOpacity.active
        guard !isSuspended else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: TouchBarIdleOpacity.delay)
            guard !Task.isCancelled else { return }
            self?.window?.alphaValue = TouchBarIdleOpacity.idle
        }
    }

    func suspendAtFullOpacity() {
        isSuspended = true
        idleTask?.cancel()
        idleTask = nil
        window?.alphaValue = TouchBarIdleOpacity.active
    }

    func resumeFrameDrivenOpacity() {
        isSuspended = false
        registerFrameActivity()
    }
}

@MainActor
final class TouchBarSurfaceView: NSView {
    private let statusLabel: NSTextField
    private let imageView: NSView

    override init(frame frameRect: NSRect) {
        statusLabel = NSTextField(
            labelWithString: "正在读取 Touch Bar…"
        )
        imageView = NSView(frame: .zero)
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspect
        addSubview(imageView)

        statusLabel.textColor = .white
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.maximumNumberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.wantsLayer = true
        statusLabel.layer?.zPosition = 1
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func display(image: CGImage) {
        imageView.layer?.contents = image
        imageView.isHidden = false
        statusLabel.isHidden = true
    }

    func display(notice: TouchBarCaptureNotice) {
        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.stringValue = notice.description
        statusLabel.toolTip = notice.description
        statusLabel.isHidden = false
        addSubview(statusLabel, positioned: .above, relativeTo: imageView)
    }

    func display(error: TouchBarCaptureError) {
        statusLabel.font = .systemFont(ofSize: 8, weight: .medium)
        statusLabel.stringValue = """
        \(error.localizedDescription)

        恢复命令（终端）：
        \(ToubarReplaceAppInfo.recoveryCommands)
        """
        statusLabel.toolTip = statusLabel.stringValue
        statusLabel.isHidden = false
        addSubview(statusLabel, positioned: .above, relativeTo: imageView)
    }
}

@MainActor
final class TouchBarWindowController: NSWindowController, NSWindowDelegate {
    private let rootView: TouchBarRootView
    private let capture: TouchBarCapture
    private let idleOpacityController: TouchBarIdleOpacityController
    private let workspacePathResolver = WorkspacePathResolver()
    private let agentRegistry = AgentRegistry()
    private let terminalAdapterRegistry = TerminalAdapterRegistry()
    private lazy var agentLauncher = AgentLauncher(
        terminalAdapterRegistry: terminalAdapterRegistry
    )
    private let workspaceTouchBarController = WorkspaceTouchBarController()
    private var workspaceSwitcherWindowController:
        WorkspaceSwitcherWindowController?
    private var hasRestoredFrame = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var finderSyncTask: Task<Void, Never>?
    private var isRunning = false
    private var lastFrontmostContext: FrontmostAppContext?
    private var currentWorkspaceContext: WorkspaceContext?
    private var availableAgents: [AvailableAgent] = []
    private var isAgentLaunchInProgress = false
    private var lastLaunchSignature: (AgentID, String, Date)?
    private(set) var displayPosition = TouchBarPreferences.displayPosition
    var onPixelSizeChanged: ((CGSize) -> Void)?
    var onRequestWorkspaceDirectory: (
        (@escaping (URL?) -> Void) -> Void
    )?

    init() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let initialMirrorSize = TouchBarWindowMetrics.pointSize(
            forPixelSize: TouchBarPreferences.mirrorPixelSize,
            backingScaleFactor: scale
        )
        let initialRootSize = TouchBarWindowMetrics.rootSize(
            forMirrorSize: initialMirrorSize,
            edgeRailWidth: WorkspacePreferences.floatingSwitcher
                ? 0
                : TouchBarWindowMetrics.edgeRailWidth
        )
        let switcherSide = WorkspacePreferences.switcherSide
        rootView = TouchBarRootView(
            frame: NSRect(origin: .zero, size: initialRootSize),
            switcherSide: switcherSide,
            showsAttachedSwitcher: !WorkspacePreferences.floatingSwitcher
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialRootSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = TouchBarWindowMetrics.rootSize(
            forMirrorSize: TouchBarWindowMetrics.minimumSize,
            edgeRailWidth: WorkspacePreferences.floatingSwitcher
                ? 0
                : TouchBarWindowMetrics.edgeRailWidth
        )
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = rootView
        panel.setFrameAutosaveName("ToubarReplaceMirrorWindow")
        let restoredFrame = panel.setFrameUsingName(
            "ToubarReplaceMirrorWindow"
        )
        panel.setContentSize(initialRootSize)
        let hadMigratedAttachedFrame = WorkspacePreferences.hasMigratedRootFrame
        if restoredFrame && !hadMigratedAttachedFrame {
            if !WorkspacePreferences.floatingSwitcher && switcherSide == .left {
                var origin = panel.frame.origin
                origin.x -= TouchBarWindowMetrics.edgeRailWidth
                panel.setFrameOrigin(origin)
            }
            WorkspacePreferences.hasMigratedRootFrame = true
        } else if !restoredFrame {
            WorkspacePreferences.hasMigratedRootFrame = true
        }
        if WorkspacePreferences.floatingSwitcher {
            if restoredFrame && hadMigratedAttachedFrame
                && !WorkspacePreferences.hasMigratedFloatingMirrorFrame
                && switcherSide == .left
            {
                var origin = panel.frame.origin
                origin.x += TouchBarWindowMetrics.edgeRailWidth
                panel.setFrameOrigin(origin)
            }
            WorkspacePreferences.hasMigratedFloatingMirrorFrame = true
        }

        let idleOpacityController = TouchBarIdleOpacityController(window: panel)
        self.idleOpacityController = idleOpacityController
        capture = TouchBarCapture(
            framesPerSecond: TouchBarPreferences.displayFramesPerSecond,
            onFrame: { [weak rootView, weak idleOpacityController] image in
                Task { @MainActor in
                    rootView?.surfaceView.display(image: image)
                    idleOpacityController?.registerFrameActivity()
                }
            },
            onNotice: { [weak rootView] notice in
                Task { @MainActor in
                    rootView?.surfaceView.display(notice: notice)
                }
            },
            onError: { [weak rootView] error in
                Task { @MainActor in
                    rootView?.surfaceView.display(error: error)
                }
            }
        )

        super.init(window: panel)
        hasRestoredFrame = restoredFrame
        panel.delegate = self
        installWorkspaceActions()
        configureFloatingWorkspaceSwitcher()
        installWorkspaceObservers()
        persistCurrentPixelSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func start() {
        isRunning = true
        if !hasRestoredFrame {
            positionWindow()
        }
        window?.orderFrontRegardless()
        showFloatingWorkspaceSwitcherIfNeeded()
        idleOpacityController.start()
        capture.start()
    }

    func stop() {
        isRunning = false
        finderSyncTask?.cancel()
        finderSyncTask = nil
        workspaceTouchBarController.dismiss()
        workspaceSwitcherWindowController?.window?.orderOut(nil)
        idleOpacityController.stop()
        capture.stop()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
    }

    func setDisplayPosition(_ position: TouchBarDisplayPosition) {
        displayPosition = position
        TouchBarPreferences.displayPosition = position
        positionWindow()
    }

    var displayFramesPerSecond: Int {
        TouchBarPreferences.displayFramesPerSecond
    }

    func setDisplayFramesPerSecond(_ framesPerSecond: Int) {
        let clamped = min(
            max(framesPerSecond, TouchBarCapture.minimumFramesPerSecond),
            TouchBarCapture.maximumFramesPerSecond
        )
        TouchBarPreferences.displayFramesPerSecond = clamped
        capture.updateFramesPerSecond(clamped)
    }

    var mirrorPixelSize: CGSize {
        guard let window else {
            return TouchBarPreferences.mirrorPixelSize
        }
        return TouchBarWindowMetrics.pixelSize(
            forPointSize: rootView.mirrorViewportSize,
            backingScaleFactor: window.screen?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
        )
    }

    func setMirrorPixelSize(_ pixelSize: CGSize) {
        guard let window else { return }
        let constrainedPixelSize = CGSize(
            width: max(pixelSize.width.rounded(), 1),
            height: max(pixelSize.height.rounded(), 1)
        )
        let mirrorPointSize = TouchBarWindowMetrics.pointSize(
            forPixelSize: constrainedPixelSize,
            backingScaleFactor: window.screen?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
        )
        let mirrorOriginX = currentMirrorOriginX
        window.setContentSize(
            TouchBarWindowMetrics.rootSize(
                forMirrorSize: mirrorPointSize,
                edgeRailWidth: attachedSwitcherWidth
            )
        )
        setWindowOriginPreservingMirrorX(mirrorOriginX)
        persistCurrentPixelSize()
    }

    var workspaceSwitcherSide: WorkspaceSwitcherSide {
        rootView.switcherSide
    }

    func setWorkspaceSwitcherSide(_ side: WorkspaceSwitcherSide) {
        guard side != rootView.switcherSide else { return }
        let mirrorOriginX = currentMirrorOriginX
        WorkspacePreferences.switcherSide = side
        rootView.setSwitcherSide(side)
        rootView.layoutSubtreeIfNeeded()
        setWindowOriginPreservingMirrorX(mirrorOriginX)
    }

    var workspaceSwitcherFloats: Bool {
        WorkspacePreferences.floatingSwitcher
    }

    func setWorkspaceSwitcherFloats(_ floats: Bool) {
        guard floats != WorkspacePreferences.floatingSwitcher else { return }
        guard let window else { return }
        let mirrorOriginX = currentMirrorOriginX
        let mirrorSize = rootView.mirrorViewportSize
        WorkspacePreferences.floatingSwitcher = floats
        rootView.setAttachedSwitcherVisible(!floats)
        window.minSize = TouchBarWindowMetrics.rootSize(
            forMirrorSize: TouchBarWindowMetrics.minimumSize,
            edgeRailWidth: attachedSwitcherWidth
        )
        window.setContentSize(
            TouchBarWindowMetrics.rootSize(
                forMirrorSize: mirrorSize,
                edgeRailWidth: attachedSwitcherWidth
            )
        )
        rootView.layoutSubtreeIfNeeded()
        setWindowOriginPreservingMirrorX(mirrorOriginX)
        WorkspacePreferences.hasMigratedFloatingMirrorFrame = floats
        configureFloatingWorkspaceSwitcher()
        showFloatingWorkspaceSwitcherIfNeeded()
        persistCurrentPixelSize()
    }

    var workspaceAutoCollapse: Bool {
        WorkspacePreferences.autoCollapse
    }

    func setWorkspaceAutoCollapse(_ autoCollapse: Bool) {
        WorkspacePreferences.autoCollapse = autoCollapse
    }

    var availableTerminalAdapters: [TerminalAdapter] {
        terminalAdapterRegistry.discover()
    }

    var workspaceTerminalAdapterID: TerminalAdapterID {
        terminalAdapterRegistry.selectedAdapter()?.id
            ?? WorkspacePreferences.terminalAdapterID
    }

    func setWorkspaceTerminalAdapterID(_ adapterID: TerminalAdapterID) {
        guard availableTerminalAdapters.contains(where: { $0.id == adapterID })
        else {
            return
        }
        WorkspacePreferences.terminalAdapterID = adapterID
    }

    func windowDidResize(_ notification: Notification) {
        persistCurrentPixelSize()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        persistCurrentPixelSize()
    }

    func positionWindow() {
        guard let window else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let frame = window.frame
        let mirrorSize = rootView.mirrorViewportSize
        let mirrorX = visibleFrame.midX - mirrorSize.width / 2
        let rootX = rootView.switcherSide == .left
            ? mirrorX - attachedSwitcherWidth
            : mirrorX
        let origin: NSPoint
        switch displayPosition {
        case .bottom:
            origin = NSPoint(
                x: rootX,
                y: screen.frame.minY
            )
        case .top:
            origin = NSPoint(
                x: rootX,
                y: visibleFrame.maxY - frame.height - 18
            )
        case .center:
            origin = NSPoint(
                x: rootX,
                y: visibleFrame.midY - frame.height / 2
            )
        }
        window.setFrameOrigin(
            origin
        )
    }

    private func persistCurrentPixelSize() {
        let pixelSize = mirrorPixelSize
        TouchBarPreferences.mirrorPixelSize = pixelSize
        onPixelSizeChanged?(pixelSize)
    }

    private var currentMirrorOriginX: CGFloat {
        guard let window else { return 0 }
        return rootView.switcherSide == .left
            ? window.frame.minX + attachedSwitcherWidth
            : window.frame.minX
    }

    private func setWindowOriginPreservingMirrorX(_ mirrorOriginX: CGFloat) {
        guard let window else { return }
        var origin = window.frame.origin
        origin.x = rootView.switcherSide == .left
            ? mirrorOriginX - attachedSwitcherWidth
            : mirrorOriginX
        window.setFrameOrigin(origin)
    }

    private var attachedSwitcherWidth: CGFloat {
        rootView.showsAttachedSwitcher
            ? TouchBarWindowMetrics.edgeRailWidth
            : 0
    }

    private func installWorkspaceActions() {
        rootView.workspaceView.onResolvePath = { [weak self] in
            self?.chooseWorkspacePath()
        }
        rootView.workspaceView.onAgentActivated = { [weak self] agent in
            self?.launch(agent)
        }
        rootView.onSwitcherMouseDown = { [weak self] in
            self?.lastFrontmostContext = FrontmostAppContext.capture()
        }
        rootView.onToggleScene = { [weak self] in
            self?.toggleWorkspace()
        }
        workspaceTouchBarController.onResolvePath = { [weak self] in
            self?.chooseWorkspacePath()
        }
        workspaceTouchBarController.onAgentActivated = { [weak self] agent in
            self?.launch(agent)
        }
        workspaceTouchBarController.onPresentationInterrupted = { [weak self] in
            self?.handleWorkspacePresentationInterrupted()
        }
    }

    private func configureFloatingWorkspaceSwitcher() {
        guard WorkspacePreferences.floatingSwitcher else {
            workspaceSwitcherWindowController?.window?.orderOut(nil)
            workspaceSwitcherWindowController = nil
            return
        }
        guard workspaceSwitcherWindowController == nil else {
            workspaceSwitcherWindowController?.switcherView.setScene(
                rootView.scene
            )
            return
        }
        let controller = WorkspaceSwitcherWindowController()
        controller.switcherView.onMouseDown = { [weak self] in
            self?.lastFrontmostContext = FrontmostAppContext.capture()
        }
        controller.switcherView.onToggleScene = { [weak self] in
            self?.toggleWorkspace()
        }
        controller.switcherView.setScene(rootView.scene)
        workspaceSwitcherWindowController = controller
    }

    private func showFloatingWorkspaceSwitcherIfNeeded() {
        guard
            isRunning,
            WorkspacePreferences.floatingSwitcher,
            let controller = workspaceSwitcherWindowController,
            let mirrorWindow = window
        else {
            return
        }
        if !controller.hasRestoredFrame {
            controller.positionBesideMirror(mirrorWindow)
        }
        controller.window?.orderFrontRegardless()
    }

    private func toggleWorkspace() {
        switch rootView.scene {
        case .mirror:
            if lastFrontmostContext == nil {
                lastFrontmostContext = FrontmostAppContext.capture()
            }
            currentWorkspaceContext = nil
            availableAgents = []
            rootView.setScene(.workspace)
            workspaceSwitcherWindowController?.switcherView.setScene(
                .workspace
            )
            idleOpacityController.suspendAtFullOpacity()
            do {
                try workspaceTouchBarController.present()
                rootView.setWorkspaceFallbackVisible(false)
            } catch {
                rootView.workspaceView.showFailure(
                    error.localizedDescription,
                    context: nil,
                    agents: []
                )
                rootView.setWorkspaceFallbackVisible(true)
                return
            }

            let frontmostContext = lastFrontmostContext
                ?? FrontmostAppContext.capture()
            if frontmostContext.isFinder,
                let finderContext = workspacePathResolver.resolveFrontmostPath(
                    from: frontmostContext
                )
            {
                acceptWorkspaceContext(finderContext)
            } else if let recentContext = workspacePathResolver.recentContext(
                frontmostApplication: frontmostContext
            ) {
                acceptWorkspaceContext(recentContext)
            } else {
                workspaceTouchBarController.showIdle(lastPath: nil)
                resolveWorkspacePath(refreshFrontmostContext: false)
            }
        case .workspace:
            closeWorkspace()
        }
    }

    private func closeWorkspace() {
        finderSyncTask?.cancel()
        finderSyncTask = nil
        workspaceTouchBarController.dismiss()
        rootView.setWorkspaceFallbackVisible(false)
        rootView.setScene(.mirror)
        workspaceSwitcherWindowController?.switcherView.setScene(.mirror)
        idleOpacityController.resumeFrameDrivenOpacity()
        lastFrontmostContext = nil
        isAgentLaunchInProgress = false
    }

    private func handleWorkspacePresentationInterrupted() {
        guard rootView.scene == .workspace else { return }
        finderSyncTask?.cancel()
        finderSyncTask = nil
        rootView.setWorkspaceFallbackVisible(false)
        rootView.setScene(.mirror)
        workspaceSwitcherWindowController?.switcherView.setScene(.mirror)
        idleOpacityController.resumeFrameDrivenOpacity()
        lastFrontmostContext = nil
        isAgentLaunchInProgress = false
    }

    private func resolveWorkspacePath(refreshFrontmostContext: Bool) {
        let frontmostContext = refreshFrontmostContext
            ? FrontmostAppContext.capture()
            : lastFrontmostContext ?? FrontmostAppContext.capture()
        lastFrontmostContext = frontmostContext
        workspaceTouchBarController.showResolving()
        rootView.workspaceView.showResolving()

        if let context = workspacePathResolver.resolveFrontmostPath(
            from: frontmostContext
        ) {
            acceptWorkspaceContext(context)
            return
        }

        requestWorkspaceDirectory(frontmostContext: frontmostContext)
    }

    private func chooseWorkspacePath() {
        let frontmostContext = FrontmostAppContext.capture()
        lastFrontmostContext = frontmostContext
        workspaceTouchBarController.showResolving()
        rootView.workspaceView.showResolving()

        if frontmostContext.isFinder,
            let context = workspacePathResolver.resolveFrontmostPath(
                from: frontmostContext
            )
        {
            acceptWorkspaceContext(context)
            return
        }
        requestWorkspaceDirectory(frontmostContext: frontmostContext)
    }

    private func requestWorkspaceDirectory(
        frontmostContext: FrontmostAppContext
    ) {
        guard let onRequestWorkspaceDirectory else {
            rootView.workspaceView.showFailure(
                "无法获取当前路径",
                context: nil,
                agents: []
            )
            workspaceTouchBarController.showFailure(
                "无法获取当前路径",
                context: nil,
                agents: []
            )
            return
        }
        onRequestWorkspaceDirectory { [weak self] directoryURL in
            guard let self else { return }
            guard
                let directoryURL,
                let context = self.workspacePathResolver.manualContext(
                    directoryURL: directoryURL,
                    frontmostApplication: frontmostContext
                )
            else {
                self.rootView.workspaceView.showFailure(
                    "未选择项目目录，点击定位按钮重试",
                    context: self.currentWorkspaceContext,
                    agents: self.availableAgents
                )
                self.workspaceTouchBarController.showFailure(
                    "未选择项目目录，点击路径重试",
                    context: self.currentWorkspaceContext,
                    agents: self.availableAgents
                )
                return
            }
            self.acceptWorkspaceContext(context)
        }
    }

    private func acceptWorkspaceContext(_ context: WorkspaceContext) {
        currentWorkspaceContext = context
        WorkspacePreferences.lastPath = context.directoryURL
        availableAgents = agentRegistry.discover()
        rootView.workspaceView.showReady(
            context: context,
            agents: availableAgents
        )
        workspaceTouchBarController.showReady(
            context: context,
            agents: availableAgents
        )
    }

    private func launch(_ agent: AvailableAgent) {
        guard !isAgentLaunchInProgress else { return }
        guard let context = currentWorkspaceContext else {
            rootView.workspaceView.showFailure(
                "请先获取当前项目路径",
                context: nil,
                agents: []
            )
            workspaceTouchBarController.showFailure(
                "请先获取当前项目路径",
                context: nil,
                agents: []
            )
            return
        }
        let signature = (agent.id, context.directoryURL.path)
        if let lastLaunchSignature,
            lastLaunchSignature.0 == signature.0,
            lastLaunchSignature.1 == signature.1,
            Date().timeIntervalSince(lastLaunchSignature.2) < 1
        {
            return
        }
        lastLaunchSignature = (signature.0, signature.1, Date())
        isAgentLaunchInProgress = true
        rootView.workspaceView.showLaunching(agent: agent, context: context)
        workspaceTouchBarController.showLaunching(
            agent: agent,
            context: context
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isAgentLaunchInProgress = false }
            do {
                try await self.agentLauncher.launch(
                    agent,
                    at: context.directoryURL
                )
                guard WorkspacePreferences.autoCollapse else {
                    self.rootView.workspaceView.showReady(
                        context: context,
                        agents: self.availableAgents
                    )
                    self.workspaceTouchBarController.showReady(
                        context: context,
                        agents: self.availableAgents
                    )
                    return
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    self?.closeWorkspace()
                }
            } catch {
                self.rootView.workspaceView.showFailure(
                    error.localizedDescription,
                    context: context,
                    agents: self.availableAgents
                )
                self.workspaceTouchBarController.showFailure(
                    error.localizedDescription,
                    context: context,
                    agents: self.availableAgents
                )
            }
        }
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let pauseNotifications: [Notification.Name] = [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
        ]
        let resumeNotifications: [Notification.Name] = [
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
        ]

        for name in pauseNotifications {
            workspaceObservers.append(
                center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard self?.isRunning == true else { return }
                        if self?.rootView.scene == .workspace {
                            self?.closeWorkspace()
                        }
                        self?.capture.stop()
                    }
                }
            )
        }

        for name in resumeNotifications {
            workspaceObservers.append(
                center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard self?.isRunning == true else { return }
                        self?.capture.restart()
                    }
                }
            )
        }

        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let activatedBundleIdentifier = (
                    notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication
                )?.bundleIdentifier
                Task { @MainActor [weak self] in
                    guard
                        let self,
                        self.isRunning,
                        self.rootView.scene == .workspace,
                        activatedBundleIdentifier
                            == FrontmostAppContext.finderBundleIdentifier
                    else {
                        return
                    }
                    self.scheduleFinderPathSync()
                }
            }
        )
    }

    private func scheduleFinderPathSync() {
        finderSyncTask?.cancel()
        finderSyncTask = Task { @MainActor [weak self] in
            for delay in [150, 300, 500] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard
                    !Task.isCancelled,
                    let self,
                    self.isRunning,
                    self.rootView.scene == .workspace
                else {
                    return
                }
                let frontmostContext = FrontmostAppContext.capture()
                guard frontmostContext.isFinder else { return }
                guard
                    let context = self.workspacePathResolver
                        .resolveFrontmostPath(from: frontmostContext)
                else {
                    continue
                }
                self.lastFrontmostContext = frontmostContext
                self.acceptWorkspaceContext(context)
                return
            }
        }
    }
}
