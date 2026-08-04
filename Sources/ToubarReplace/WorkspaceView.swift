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

@MainActor
final class WorkspaceAgentIconView: NSView {
    private let imageView = NSImageView()
    private var agent: AvailableAgent?
    private var isInteractionEnabled = true

    var onActivate: ((AvailableAgent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = WorkspaceTouchBarStyle.primaryTextColor
        imageView.wantsLayer = true
        addSubview(imageView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
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
        let iconSize = WorkspaceTouchBarStyle.agentIconSize
        imageView.frame = NSRect(
            x: floor(bounds.midX - iconSize / 2),
            y: floor(bounds.midY - iconSize / 2),
            width: iconSize,
            height: iconSize
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractionEnabled, let agent else { return }
        imageView.alphaValue = 0.45
        super.mouseDown(with: event)
        imageView.alphaValue = 0.82
        onActivate?(agent)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isInteractionEnabled, let agent else { return false }
        onActivate?(agent)
        return true
    }

    func display(_ agent: AvailableAgent) {
        self.agent = agent
        imageView.image = WorkspaceTouchBarStyle.agentSymbol(for: agent.id)
        toolTip = "用 \(agent.displayName) 打开当前项目"
        setAccessibilityLabel(agent.displayName)
    }

    func setEnabled(_ enabled: Bool) {
        isInteractionEnabled = enabled
        imageView.alphaValue = enabled ? 0.82 : 0.34
    }
}

@MainActor
final class AgentIconRowView: NSView {
    private let stackView = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "未发现 Agent")
    private var iconViews: [WorkspaceAgentIconView] = []

    var onAgentActivated: ((AvailableAgent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = WorkspaceTouchBarStyle.itemSpacing
        addSubview(stackView)

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
        let contentSize = stackView.fittingSize
        stackView.frame = NSRect(
            x: floor(bounds.midX - contentSize.width / 2),
            y: floor(bounds.midY - WorkspaceTouchBarStyle.controlHeight / 2),
            width: contentSize.width,
            height: WorkspaceTouchBarStyle.controlHeight
        )
        emptyLabel.frame = bounds.insetBy(dx: 4, dy: 1)
    }

    func display(agents: [AvailableAgent]) {
        iconViews.forEach { iconView in
            stackView.removeArrangedSubview(iconView)
            iconView.removeFromSuperview()
        }
        iconViews.removeAll()

        emptyLabel.isHidden = !agents.isEmpty
        stackView.isHidden = agents.isEmpty
        for agent in agents {
            let iconView = WorkspaceAgentIconView(frame: .zero)
            iconView.display(agent)
            iconView.onActivate = { [weak self] selectedAgent in
                self?.onAgentActivated?(selectedAgent)
            }
            iconView.widthAnchor.constraint(
                equalToConstant: WorkspaceTouchBarStyle.agentItemWidth
            ).isActive = true
            iconView.heightAnchor.constraint(
                equalToConstant: WorkspaceTouchBarStyle.controlHeight
            ).isActive = true
            stackView.addArrangedSubview(iconView)
            iconViews.append(iconView)
        }
        needsLayout = true
    }

    func setEnabled(_ enabled: Bool) {
        iconViews.forEach { $0.setEnabled(enabled) }
    }
}

@MainActor
final class WorkspaceBarView: NSView {
    private let pathView = WorkspaceTouchBarPathView()
    private let agentIconRow = AgentIconRowView()
    private let dividerView = NSView()
    private var context: WorkspaceContext?

    var onResolvePath: (() -> Void)?
    var onAgentActivated: ((AvailableAgent) -> Void)? {
        didSet {
            agentIconRow.onAgentActivated = onAgentActivated
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        pathView.onActivate = { [weak self] in
            self?.onResolvePath?()
        }
        addSubview(pathView)

        agentIconRow.onAgentActivated = { [weak self] agent in
            self?.onAgentActivated?(agent)
        }
        addSubview(agentIconRow)
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = WorkspaceTouchBarStyle
            .dividerColor.cgColor
        addSubview(dividerView)
        showIdle(lastPath: WorkspacePreferences.lastPath)
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
        let regions = WorkspaceTouchBarLayout.regionFrames(in: bounds)
        pathView.frame = WorkspaceTouchBarLayout.centeredControlFrame(
            in: regions.path,
            preferredWidth: regions.path.width
        )
        agentIconRow.frame = WorkspaceTouchBarLayout.centeredControlFrame(
            in: regions.agents,
            preferredWidth: regions.agents.width
        )
        dividerView.frame = NSRect(
            x: floor((regions.path.maxX + regions.agents.minX) / 2),
            y: floor(bounds.midY - 9),
            width: 1,
            height: 18
        )
    }

    func showIdle(lastPath: URL?) {
        context = nil
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
    }

    func showResolving() {
        context = nil
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
    }

    func showReady(
        context: WorkspaceContext,
        agents: [AvailableAgent]
    ) {
        self.context = context
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
        pathView.display(
            image: nil,
            title: message,
            toolTip: context?.directoryURL.path,
            enabled: true
        )
        agentIconRow.display(agents: context == nil ? [] : agents)
        agentIconRow.setEnabled(context != nil)
    }

}

@MainActor
final class TouchBarRootView: NSView {
    let surfaceView: TouchBarSurfaceView
    let workspaceView: WorkspaceBarView
    private let switcherButton = WorkspaceActionButton()
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
