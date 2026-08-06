import AppKit
import CoreGraphics

struct TouchBarWindowMetrics {
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

/// Mirror-window cover used while physical Touch Bar modals swap.
/// Freezes the last captured frame, then fades out after a short settle.
enum MirrorSceneTransition {
    /// Keep the cover opaque while system modal + capture settle.
    static let settleDuration: Duration = .milliseconds(221)
    /// Fade-out of the frozen frame overlay.
    static let fadeDuration: TimeInterval = 0.12
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
        statusLabel = NSTextField(labelWithString: "正在读取 Touch Bar…")
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

    /// Latest mirror bitmap (or nil before the first frame).
    var currentFrameContents: Any? {
        imageView.layer?.contents
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
    private let switcherTouchBarController = SwitcherTouchBarController()
    private var workspaceSwitcherWindowController:
        WorkspaceSwitcherWindowController?
    /// True only when launch restored an autosaved frame under `.lastSaved`.
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
    var onCustomTopLeftChanged: ((CGPoint) -> Void)?
    var onRequestWorkspaceDirectory: (
        (@escaping (URL?) -> Void) -> Void
    )?

    init() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let initialMirrorSize = TouchBarWindowMetrics.pointSize(
            forPixelSize: TouchBarPreferences.mirrorPixelSize,
            backingScaleFactor: scale
        )
        // Switcher is either physical Touch Bar or floating window — never attached rail.
        let initialRootSize = TouchBarWindowMetrics.rootSize(
            forMirrorSize: initialMirrorSize,
            edgeRailWidth: 0
        )
        let switcherSide = WorkspacePreferences.switcherSide
        rootView = TouchBarRootView(
            frame: NSRect(origin: .zero, size: initialRootSize),
            switcherSide: switcherSide,
            showsAttachedSwitcher: false
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
            edgeRailWidth: 0
        )
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = rootView
        // Always record frames so "上次关闭时的位置" can restore later.
        panel.setFrameAutosaveName(TouchBarPreferences.mirrorWindowAutosaveName)
        var restoredFrame = false
        if TouchBarPreferences.displayPosition.restoresAutosavedFrame {
            restoredFrame = panel.setFrameUsingName(
                TouchBarPreferences.mirrorWindowAutosaveName
            )
        }
        panel.setContentSize(initialRootSize)
        WorkspacePreferences.hasMigratedRootFrame = true
        WorkspacePreferences.hasMigratedFloatingMirrorFrame = true

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
        // Autosave restore only when setting is "上次关闭时的位置".
        if !(displayPosition.restoresAutosavedFrame && hasRestoredFrame) {
            positionWindow()
        }
        window?.orderFrontRegardless()
        showFloatingWorkspaceSwitcherIfNeeded()
        idleOpacityController.start()
        capture.start()
        presentPhysicalSwitcherIfNeeded()
    }

    func stop() {
        isRunning = false
        finderSyncTask?.cancel()
        finderSyncTask = nil
        workspaceTouchBarController.dismiss()
        switcherTouchBarController.dismiss()
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
        if position.restoresAutosavedFrame, let window {
            let restored = window.setFrameUsingName(
                TouchBarPreferences.mirrorWindowAutosaveName
            )
            hasRestoredFrame = restored
            if restored {
                let scale = window.screen?.backingScaleFactor
                    ?? NSScreen.main?.backingScaleFactor
                    ?? 2
                let mirrorPointSize = TouchBarWindowMetrics.pointSize(
                    forPixelSize: TouchBarPreferences.mirrorPixelSize,
                    backingScaleFactor: scale
                )
                window.setContentSize(
                    TouchBarWindowMetrics.rootSize(
                        forMirrorSize: mirrorPointSize,
                        edgeRailWidth: 0
                    )
                )
                return
            }
        } else {
            hasRestoredFrame = false
        }
        positionWindow()
    }

    /// Current top-left of the mirror window in AppKit screen points.
    var customTopLeft: CGPoint {
        guard let window else {
            return TouchBarPreferences.hasCustomTopLeft
                ? TouchBarPreferences.customTopLeft
                : defaultCustomTopLeftFallback()
        }
        return CGPoint(x: window.frame.minX, y: window.frame.maxY)
    }

    func setCustomTopLeft(_ topLeft: CGPoint) {
        TouchBarPreferences.customTopLeft = topLeft
        onCustomTopLeftChanged?(topLeft)
        if displayPosition.usesCustomTopLeft {
            positionWindow()
        }
    }

    /// Re-hide the mirror switcher close box after the app becomes frontmost.
    func suppressPhysicalSwitcherCloseBox() {
        switcherTouchBarController.suppressCloseBox()
    }

    /// Ensure the mirror-mode physical switcher is present (and close box hidden).
    func ensurePhysicalSwitcherPresented() {
        presentPhysicalSwitcherIfNeeded()
        suppressPhysicalSwitcherCloseBox()
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
                edgeRailWidth: 0
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

    var workspaceSwitcherDisplayMode: WorkspaceSwitcherDisplayMode {
        WorkspacePreferences.switcherDisplayMode
    }

    func setWorkspaceSwitcherFloats(_ floats: Bool) {
        setWorkspaceSwitcherDisplayMode(floats ? .floating : .touchBar)
    }

    func setWorkspaceSwitcherDisplayMode(_ mode: WorkspaceSwitcherDisplayMode) {
        guard mode != WorkspacePreferences.switcherDisplayMode else { return }
        WorkspacePreferences.switcherDisplayMode = mode
        rootView.setAttachedSwitcherVisible(false)
        configureFloatingWorkspaceSwitcher()
        showFloatingWorkspaceSwitcherIfNeeded()
        if mode == .floating {
            switcherTouchBarController.dismiss()
        } else {
            presentPhysicalSwitcherIfNeeded()
        }
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
        let origin: NSPoint
        switch displayPosition {
        case .bottom:
            origin = NSPoint(x: mirrorX, y: screen.frame.minY)
        case .top:
            origin = NSPoint(
                x: mirrorX,
                y: visibleFrame.maxY - frame.height - 18
            )
        case .center:
            origin = NSPoint(
                x: mirrorX,
                y: visibleFrame.midY - frame.height / 2
            )
        case .lastSaved:
            // Caller already tried autosave restore; fall back to bottom.
            origin = NSPoint(x: mirrorX, y: screen.frame.minY)
        case .custom:
            let topLeft: CGPoint
            if TouchBarPreferences.hasCustomTopLeft {
                topLeft = TouchBarPreferences.customTopLeft
            } else {
                topLeft = CGPoint(
                    x: mirrorX,
                    y: screen.frame.minY + frame.height
                )
                TouchBarPreferences.customTopLeft = topLeft
                onCustomTopLeftChanged?(topLeft)
            }
            // AppKit window origin is bottom-left.
            origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        }
        window.setFrameOrigin(origin)
    }

    private func defaultCustomTopLeftFallback() -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? .zero
        let scale = screen?.backingScaleFactor ?? 2
        let mirrorPointSize = TouchBarWindowMetrics.pointSize(
            forPixelSize: TouchBarPreferences.mirrorPixelSize,
            backingScaleFactor: scale
        )
        let rootSize = TouchBarWindowMetrics.rootSize(
            forMirrorSize: mirrorPointSize,
            edgeRailWidth: 0
        )
        let mirrorX = visibleFrame.midX - mirrorPointSize.width / 2
        let bottomY = screen?.frame.minY ?? 0
        return CGPoint(x: mirrorX, y: bottomY + rootSize.height)
    }

    private func persistCurrentPixelSize() {
        let pixelSize = mirrorPixelSize
        TouchBarPreferences.mirrorPixelSize = pixelSize
        onPixelSizeChanged?(pixelSize)
    }

    private var currentMirrorOriginX: CGFloat {
        guard let window else { return 0 }
        return window.frame.minX
    }

    private func setWindowOriginPreservingMirrorX(_ mirrorOriginX: CGFloat) {
        guard let window else { return }
        var origin = window.frame.origin
        origin.x = mirrorOriginX
        window.setFrameOrigin(origin)
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
        workspaceTouchBarController.onToggleWorkspace = { [weak self] in
            self?.toggleWorkspace()
        }
        switcherTouchBarController.onToggleWorkspace = { [weak self] in
            self?.lastFrontmostContext = FrontmostAppContext.capture()
            self?.toggleWorkspace()
        }
        switcherTouchBarController.onPresentationInterrupted = { [weak self] in
            // Close-box / system dismissal while still in mirror mode.
            self?.presentPhysicalSwitcherIfNeeded()
        }
    }

    private func configureFloatingWorkspaceSwitcher() {
        guard WorkspacePreferences.switcherDisplayMode == .floating else {
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
            WorkspacePreferences.switcherDisplayMode == .floating,
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

    private func presentPhysicalSwitcherIfNeeded() {
        guard isRunning, rootView.scene == .mirror else { return }
        guard WorkspacePreferences.switcherDisplayMode == .touchBar else {
            switcherTouchBarController.dismiss()
            return
        }
        switcherTouchBarController.present()
    }

    private func toggleWorkspace() {
        switch rootView.scene {
        case .mirror:
            rootView.beginSceneTransitionCover()
            if lastFrontmostContext == nil {
                lastFrontmostContext = FrontmostAppContext.capture()
            }
            currentWorkspaceContext = nil
            availableAgents = []
            rootView.setScene(.workspace)
            workspaceSwitcherWindowController?.switcherView.setScene(.workspace)
            idleOpacityController.suspendAtFullOpacity()

            switcherTouchBarController.dismiss()

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
                presentPhysicalSwitcherIfNeeded()
                rootView.scheduleSceneTransitionCoverFade()
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
            rootView.scheduleSceneTransitionCoverFade()
        case .workspace:
            closeWorkspace()
        }
    }

    private func closeWorkspace() {
        rootView.beginSceneTransitionCover()
        finderSyncTask?.cancel()
        finderSyncTask = nil
        workspaceTouchBarController.dismiss()
        rootView.setWorkspaceFallbackVisible(false)
        rootView.setScene(.mirror)
        workspaceSwitcherWindowController?.switcherView.setScene(.mirror)
        idleOpacityController.resumeFrameDrivenOpacity()
        lastFrontmostContext = nil
        isAgentLaunchInProgress = false
        presentPhysicalSwitcherIfNeeded()
        rootView.scheduleSceneTransitionCoverFade()
    }

    private func handleWorkspacePresentationInterrupted() {
        guard rootView.scene == .workspace else { return }
        rootView.beginSceneTransitionCover()
        finderSyncTask?.cancel()
        finderSyncTask = nil
        rootView.setWorkspaceFallbackVisible(false)
        rootView.setScene(.mirror)
        workspaceSwitcherWindowController?.switcherView.setScene(.mirror)
        idleOpacityController.resumeFrameDrivenOpacity()
        lastFrontmostContext = nil
        isAgentLaunchInProgress = false
        presentPhysicalSwitcherIfNeeded()
        rootView.scheduleSceneTransitionCoverFade()
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
                self.rootView.workspaceView.showReady(
                    context: context,
                    agents: self.availableAgents
                )
                self.workspaceTouchBarController.showReady(
                    context: context,
                    agents: self.availableAgents
                )
                guard WorkspacePreferences.autoCollapse else { return }
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
                        self?.switcherTouchBarController.dismiss()
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
                        self?.presentPhysicalSwitcherIfNeeded()
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
