import AppKit

enum BarScene {
    case mirror
    case workspace
}

@MainActor
final class WorkspaceActionButton: NSButton {
    var onMouseDown: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

}

@MainActor
final class WorkspaceFloatingSwitcherView: NSView {
    enum Gesture {
        static let maximumClickDuration: TimeInterval = 0.35
        static let dragThreshold: CGFloat = 4

        static func shouldToggle(
            duration: TimeInterval,
            distance: CGFloat
        ) -> Bool {
            duration < maximumClickDuration && distance < dragThreshold
        }
    }

    private let imageView = NSImageView()
    private(set) var scene: BarScene = .mirror

    var onMouseDown: (() -> Void)?
    var onToggleScene: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = WorkspaceTouchBarStyle.itemBackground.cgColor
        layer?.cornerRadius = WorkspaceTouchBarStyle.cornerRadius
        layer?.borderWidth = 0

        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = .white
        addSubview(imageView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds.insetBy(dx: 13, dy: 8)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            onMouseDown?()
            onToggleScene?()
            return
        }
        let initialMouseLocation = NSEvent.mouseLocation
        let originalOrigin = window.frame.origin
        var maximumDistance: CGFloat = 0
        var didDrag = false
        var mouseUpTimestamp = event.timestamp

        while let nextEvent = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture,
            inMode: .eventTracking,
            dequeue: true
        ) {
            let mouseLocation = NSEvent.mouseLocation
            let deltaX = mouseLocation.x - initialMouseLocation.x
            let deltaY = mouseLocation.y - initialMouseLocation.y
            let distance = hypot(deltaX, deltaY)
            maximumDistance = max(maximumDistance, distance)

            if nextEvent.type == .leftMouseUp {
                mouseUpTimestamp = nextEvent.timestamp
                break
            }

            let duration = nextEvent.timestamp - event.timestamp
            if distance >= Gesture.dragThreshold
                || duration >= Gesture.maximumClickDuration
            {
                didDrag = true
            }
            if didDrag {
                window.setFrameOrigin(
                    NSPoint(
                        x: originalOrigin.x + deltaX,
                        y: originalOrigin.y + deltaY
                    )
                )
            }
        }

        let duration = mouseUpTimestamp - event.timestamp
        if !didDrag && Gesture.shouldToggle(
            duration: duration,
            distance: maximumDistance
        ) {
            onMouseDown?()
            onToggleScene?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onMouseDown?()
        onToggleScene?()
        return true
    }

    func setScene(_ scene: BarScene) {
        self.scene = scene
        updateAppearance()
    }

    private func updateAppearance() {
        switch scene {
        case .mirror:
            imageView.image = NSImage(
                systemSymbolName: "square.grid.2x2",
                accessibilityDescription: "打开 Workspace"
            )
            toolTip = "点击打开 Workspace；长按拖动可调整位置"
            setAccessibilityLabel("打开 Workspace")
        case .workspace:
            imageView.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle.slash",
                accessibilityDescription: "返回 Touch Bar 镜像"
            )
            toolTip = "点击返回 Touch Bar 镜像；长按拖动可调整位置"
            setAccessibilityLabel("返回 Touch Bar 镜像")
        }
    }
}

@MainActor
final class WorkspaceSwitcherWindowController: NSWindowController {
    static let size = NSSize(width: 48, height: 36)

    let switcherView: WorkspaceFloatingSwitcherView
    private(set) var hasRestoredFrame = false

    init() {
        switcherView = WorkspaceFloatingSwitcherView(
            frame: NSRect(origin: .zero, size: Self.size)
        )
        let panel = NSPanel(
            contentRect: switcherView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.contentView = switcherView
        panel.setFrameAutosaveName("ToubarReplaceWorkspaceSwitcherWindow")
        hasRestoredFrame = panel.setFrameUsingName(
            "ToubarReplaceWorkspaceSwitcherWindow"
        )
        panel.setContentSize(Self.size)
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func positionBesideMirror(_ mirrorWindow: NSWindow) {
        guard let window else { return }
        let gap: CGFloat = 8
        var origin = NSPoint(
            x: mirrorWindow.frame.minX - window.frame.width - gap,
            y: mirrorWindow.frame.midY - window.frame.height / 2
        )
        if origin.x < (mirrorWindow.screen?.visibleFrame.minX ?? 0) {
            origin.x = mirrorWindow.frame.maxX + gap
        }
        window.setFrameOrigin(origin)
    }
}

/// Agent zone: equal icon slots via real `NSButton`s (same pattern as custom apps).
@MainActor
final class AgentIconRowView: NSView {
    private let emptyLabel = NSTextField(labelWithString: "未发现 Agent")
    private var iconButtons: [WorkspaceChromeButton] = []
    private var agents: [AvailableAgent] = []

    var onAgentActivated: ((AvailableAgent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Transparent so design-v2 continuous tray shows through.
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        emptyLabel.textColor = WorkspaceTouchBarStyle.secondaryTextColor
        emptyLabel.alignment = .center
        emptyLabel.font = WorkspaceTouchBarStyle.secondaryFont
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        emptyLabel.frame = bounds.insetBy(dx: 4, dy: 1)
        guard !iconButtons.isEmpty else { return }
        let slots = WorkspaceTouchBarLayout.slotFrames(
            in: bounds,
            slotCount: iconButtons.count
        )
        for (index, button) in iconButtons.enumerated() where index < slots.count {
            button.frame = slots[index]
        }
    }

    func display(agents: [AvailableAgent]) {
        self.agents = agents
        iconButtons.forEach { $0.removeFromSuperview() }
        iconButtons.removeAll()

        emptyLabel.isHidden = !agents.isEmpty
        for (index, agent) in agents.enumerated() {
            let button = makeAgentButton(agent: agent, index: index)
            addSubview(button)
            iconButtons.append(button)
        }
        needsLayout = true
    }

    func setEnabled(_ enabled: Bool) {
        iconButtons.forEach { $0.isEnabled = enabled }
    }

    private func makeAgentButton(
        agent: AvailableAgent,
        index: Int
    ) -> WorkspaceChromeButton {
        let button = WorkspaceChromeButton()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let icon = WorkspaceTouchBarStyle.agentIcon(for: agent)
        button.image = icon
        button.contentTintColor = icon?.isTemplate == true
            ? WorkspaceTouchBarStyle.primaryTextColor
            : nil
        button.toolTip = "用 \(agent.displayName) 打开当前项目"
        button.setAccessibilityLabel(agent.displayName)
        button.tag = index
        button.target = self
        button.action = #selector(activateAgent(_:))
        return button
    }

    @objc private func activateAgent(_ sender: NSButton) {
        guard agents.indices.contains(sender.tag) else { return }
        onAgentActivated?(agents[sender.tag])
    }
}

@MainActor
final class WorkspaceBarView: NSView {
    private let trayView = NSView()
    private let pathView = WorkspaceTouchBarPathView()
    private let agentIconRow = AgentIconRowView()
    private let customAppsView = WorkspaceCustomAppsView()
    private let pathAgentsDivider = NSView()
    private let agentsCustomDivider = NSView()
    private var context: WorkspaceContext?
    private var agentCount = 0
    private var customAppCount = 0

    var onResolvePath: (() -> Void)?
    var onAgentActivated: ((AvailableAgent) -> Void)? {
        didSet {
            agentIconRow.onAgentActivated = onAgentActivated
        }
    }
    var onAddCustomApp: (() -> Void)? {
        didSet {
            customAppsView.onAddCustomApp = onAddCustomApp
        }
    }
    var onOpenCustomApp: ((CustomWorkspaceApp) -> Void)? {
        didSet {
            customAppsView.onOpenCustomApp = onOpenCustomApp
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        trayView.wantsLayer = true
        trayView.layer?.backgroundColor =
            WorkspaceTouchBarStyle.trayBackground.cgColor
        trayView.layer?.cornerRadius = WorkspaceTouchBarStyle.trayCornerRadius
        addSubview(trayView)

        pathView.onActivate = { [weak self] in
            self?.onResolvePath?()
        }
        addSubview(pathView)

        agentIconRow.onAgentActivated = { [weak self] agent in
            self?.onAgentActivated?(agent)
        }
        addSubview(agentIconRow)

        customAppsView.onAddCustomApp = { [weak self] in
            self?.onAddCustomApp?()
        }
        customAppsView.onOpenCustomApp = { [weak self] app in
            self?.onOpenCustomApp?(app)
        }
        addSubview(customAppsView)

        for divider in [pathAgentsDivider, agentsCustomDivider] {
            divider.wantsLayer = true
            divider.layer?.backgroundColor = WorkspaceTouchBarStyle
                .dividerColor.cgColor
            addSubview(divider)
        }
        reloadCustomAppsFromPreferences()
        showIdle(lastPath: WorkspacePreferences.lastPath)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func reloadCustomAppsFromPreferences() {
        let apps = WorkspacePreferences.customApps
        customAppCount = apps.count
        customAppsView.display(apps: apps)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 1, bounds.height > 1 else { return }

        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        trayView.layer?.contentsScale = scale

        // Mirror fallback: no embedded switcher; tray full width.
        // Path plate hugs title and is centered in the path zone.
        let tray = WorkspaceTouchBarLayout.trayFrame(in: bounds)
        trayView.frame = tray
        let pathPreferred = pathView.preferredPillWidth
        let regions = WorkspaceTouchBarLayout.regionFrames(
            in: tray,
            pathPreferredWidth: pathPreferred
        )
        let pathInner = WorkspaceTouchBarLayout.zoneContentRect(regions.path)
        let pathHeight = max(
            tray.height - WorkspaceTouchBarLayout.slotVerticalInset * 2,
            22
        )
        let pathPlateWidth = min(max(pathPreferred, 1), pathInner.width)
        pathView.frame = NSRect(
            x: floor(pathInner.midX - pathPlateWidth / 2),
            y: tray.midY - pathHeight / 2,
            width: pathPlateWidth,
            height: pathHeight
        )

        let agentsInner = WorkspaceTouchBarLayout.zoneContentRect(regions.agents)
        let customInner = WorkspaceTouchBarLayout.zoneContentRect(regions.custom)
        agentIconRow.frame = NSRect(
            x: agentsInner.minX,
            y: tray.minY,
            width: agentsInner.width,
            height: tray.height
        )
        customAppsView.frame = NSRect(
            x: customInner.minX,
            y: tray.minY,
            width: customInner.width,
            height: tray.height
        )

        let dividerHeight: CGFloat = 18
        pathAgentsDivider.frame = NSRect(
            x: floor(
                regions.agents.minX
                    - WorkspaceTouchBarLayout.zoneDividerWidth / 2
            ),
            y: floor(tray.midY - dividerHeight / 2),
            width: WorkspaceTouchBarLayout.zoneDividerWidth,
            height: dividerHeight
        )
        agentsCustomDivider.frame = NSRect(
            x: floor(
                regions.custom.minX
                    - WorkspaceTouchBarLayout.zoneDividerWidth / 2
            ),
            y: floor(tray.midY - dividerHeight / 2),
            width: WorkspaceTouchBarLayout.zoneDividerWidth,
            height: dividerHeight
        )
    }

    func showIdle(lastPath: URL?) {
        context = nil
        agentCount = 0
        if let lastPath {
            pathView.display(
                image: WorkspaceTouchBarStyle.symbol(
                    named: "folder",
                    accessibilityDescription: "最近使用的项目"
                ),
                title: "最近 · \(lastPath.lastPathComponent)",
                toolTip: "点击重新获取；上次路径：\(lastPath.path)",
                enabled: true
            )
        } else {
            pathView.display(
                image: WorkspaceTouchBarStyle.symbol(
                    named: "folder",
                    accessibilityDescription: "获取当前项目路径"
                ),
                title: "点击获取当前项目",
                toolTip: nil,
                enabled: true
            )
        }
        agentIconRow.display(agents: [])
        needsLayout = true
    }

    func showResolving() {
        context = nil
        agentCount = 0
        pathView.display(
            image: WorkspaceTouchBarStyle.symbol(
                named: "hourglass",
                accessibilityDescription: "正在获取当前项目路径"
            ),
            title: "正在获取当前项目路径…",
            toolTip: nil,
            enabled: false
        )
        agentIconRow.display(agents: [])
        needsLayout = true
    }

    func showReady(
        context: WorkspaceContext,
        agents: [AvailableAgent]
    ) {
        self.context = context
        agentCount = agents.count
        pathView.display(
            image: WorkspaceTouchBarStyle.symbol(
                named: "folder",
                accessibilityDescription: "当前项目路径"
            ),
            title: context.compactTitle,
            toolTip: context.directoryURL.path,
            enabled: true
        )
        agentIconRow.display(agents: agents)
        agentIconRow.setEnabled(true)
        needsLayout = true
    }

    func showLaunching(
        agent: AvailableAgent,
        context: WorkspaceContext
    ) {
        self.context = context
        pathView.display(
            image: WorkspaceTouchBarStyle.symbol(
                named: "hourglass",
                accessibilityDescription: "正在启动 Agent"
            ),
            title: "\(context.compactTitle) · 正在打开 \(agent.displayName)…",
            toolTip: context.directoryURL.path,
            enabled: false
        )
        agentIconRow.setEnabled(false)
    }

    func showFailure(
        _ message: String,
        context: WorkspaceContext?,
        agents: [AvailableAgent]
    ) {
        self.context = context
        agentCount = context == nil ? 0 : agents.count
        pathView.display(
            image: nil,
            title: message,
            toolTip: context?.directoryURL.path,
            enabled: true
        )
        agentIconRow.display(agents: context == nil ? [] : agents)
        agentIconRow.setEnabled(context != nil)
        needsLayout = true
    }

}

@MainActor
final class TouchBarRootView: NSView {
    let surfaceView: TouchBarSurfaceView
    let workspaceView: WorkspaceBarView
    private let switcherButton = WorkspaceActionButton()
    /// Freezes the last mirror frame over the viewport during scene switches.
    private let transitionCoverView = NSView(frame: .zero)
    private var transitionCoverTask: Task<Void, Never>?
    private(set) var scene: BarScene = .mirror
    private(set) var switcherSide: WorkspaceSwitcherSide
    private(set) var showsAttachedSwitcher: Bool
    private var showsWorkspaceFallback = false

    var onSwitcherMouseDown: (() -> Void)?
    var onToggleScene: (() -> Void)?

    init(
        frame frameRect: NSRect,
        switcherSide: WorkspaceSwitcherSide,
        showsAttachedSwitcher: Bool
    ) {
        self.switcherSide = switcherSide
        self.showsAttachedSwitcher = showsAttachedSwitcher
        surfaceView = TouchBarSurfaceView(frame: .zero)
        workspaceView = WorkspaceBarView(frame: .zero)
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        switcherButton.isBordered = false
        switcherButton.imagePosition = .imageOnly
        switcherButton.contentTintColor = .white
        switcherButton.target = self
        switcherButton.action = #selector(toggleScene)
        switcherButton.onMouseDown = { [weak self] in
            self?.onSwitcherMouseDown?()
        }
        addSubview(switcherButton)
        switcherButton.isHidden = !showsAttachedSwitcher

        surfaceView.autoresizingMask = [.width, .height]
        addSubview(surfaceView)
        workspaceView.autoresizingMask = [.width, .height]
        workspaceView.isHidden = true
        addSubview(workspaceView)

        transitionCoverView.wantsLayer = true
        transitionCoverView.layer?.contentsGravity = .resizeAspect
        transitionCoverView.layer?.backgroundColor = NSColor.black.cgColor
        transitionCoverView.autoresizingMask = [.width, .height]
        transitionCoverView.isHidden = true
        addSubview(transitionCoverView)

        updateSwitcherAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        let railWidth = showsAttachedSwitcher
            ? min(TouchBarWindowMetrics.edgeRailWidth, bounds.width)
            : 0
        let contentWidth = max(bounds.width - railWidth, 0)
        let railX: CGFloat
        let contentX: CGFloat
        switch switcherSide {
        case .left:
            railX = 0
            contentX = railWidth
        case .right:
            railX = contentWidth
            contentX = 0
        }
        switcherButton.frame = NSRect(
            x: railX,
            y: 0,
            width: railWidth,
            height: bounds.height
        )
        let contentFrame = NSRect(
            x: contentX,
            y: 0,
            width: contentWidth,
            height: bounds.height
        )
        surfaceView.frame = contentFrame
        workspaceView.frame = contentFrame
        transitionCoverView.frame = contentFrame
    }

    /// Snapshot the current mirror pixels and pin them above the live surface.
    func beginSceneTransitionCover() {
        transitionCoverTask?.cancel()
        transitionCoverTask = nil
        transitionCoverView.layer?.removeAllAnimations()
        if let contents = surfaceView.currentFrameContents {
            transitionCoverView.layer?.contents = contents
        } else {
            transitionCoverView.layer?.contents = nil
        }
        transitionCoverView.alphaValue = 1
        transitionCoverView.isHidden = false
        // Keep cover above surface / fallback workspace chrome.
        addSubview(transitionCoverView, positioned: .above, relativeTo: nil)
    }

    /// After modal swap settles, fade the frozen frame out to reveal live capture.
    func scheduleSceneTransitionCoverFade(
        settle: Duration = MirrorSceneTransition.settleDuration,
        fadeDuration: TimeInterval = MirrorSceneTransition.fadeDuration
    ) {
        transitionCoverTask?.cancel()
        transitionCoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self else { return }
            guard !self.transitionCoverView.isHidden else { return }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = fadeDuration
                    context.allowsImplicitAnimation = true
                    self.transitionCoverView.animator().alphaValue = 0
                }, completionHandler: {
                    continuation.resume()
                })
            }

            guard !Task.isCancelled else { return }
            self.transitionCoverView.isHidden = true
            self.transitionCoverView.layer?.contents = nil
            self.transitionCoverView.alphaValue = 1
            self.transitionCoverTask = nil
        }
    }

    var mirrorViewportSize: CGSize {
        CGSize(
            width: max(
                bounds.width - attachedSwitcherWidth,
                1
            ),
            height: max(bounds.height, 1)
        )
    }

    func setScene(_ scene: BarScene) {
        self.scene = scene
        updateContentVisibility()
        updateSwitcherAppearance()
    }

    func setWorkspaceFallbackVisible(_ visible: Bool) {
        showsWorkspaceFallback = visible
        updateContentVisibility()
    }

    func setSwitcherSide(_ side: WorkspaceSwitcherSide) {
        switcherSide = side
        needsLayout = true
    }

    func setAttachedSwitcherVisible(_ visible: Bool) {
        showsAttachedSwitcher = visible
        switcherButton.isHidden = !visible
        needsLayout = true
    }

    private var attachedSwitcherWidth: CGFloat {
        showsAttachedSwitcher ? TouchBarWindowMetrics.edgeRailWidth : 0
    }

    private func updateSwitcherAppearance() {
        switch scene {
        case .mirror:
            switcherButton.image = NSImage(
                systemSymbolName: "square.grid.2x2",
                accessibilityDescription: "打开 Workspace"
            )
            switcherButton.toolTip = "打开 Workspace"
        case .workspace:
            switcherButton.image = NSImage(
                systemSymbolName: "chevron.backward",
                accessibilityDescription: "返回 Touch Bar 镜像"
            )
            switcherButton.toolTip = "返回 Touch Bar 镜像"
        }
    }

    private func updateContentVisibility() {
        let showFallback = scene == .workspace && showsWorkspaceFallback
        surfaceView.isHidden = showFallback
        workspaceView.isHidden = !showFallback
    }

    @objc
    private func toggleScene() {
        onToggleScene?()
    }
}
