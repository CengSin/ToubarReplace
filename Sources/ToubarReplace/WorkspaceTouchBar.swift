import AppKit
import TouchBarPrivateAPI

enum WorkspaceTouchBarLayout {
    static let presentationMode = "app"
    static let placement: Int64 = 1
    // Keep the combined item within the app region even when macOS still
    // reserves space for the Control Strip during the presentation transition.
    static let preferredContentWidth: CGFloat = 680
    static let minimumContentWidth: CGFloat = 520
    static let contentGap: CGFloat = 12
    static let pathFraction: CGFloat = 0.70

    static func centeredControlFrame(
        in region: NSRect,
        preferredWidth: CGFloat
    ) -> NSRect {
        let width = min(max(preferredWidth, 0), region.width)
        let height = min(WorkspaceTouchBarStyle.controlHeight, region.height)
        return NSRect(
            x: region.midX - width / 2,
            y: region.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func regionFrames(in bounds: NSRect) -> (
        path: NSRect,
        agents: NSRect
    ) {
        let contentBounds = bounds.insetBy(
            dx: WorkspaceTouchBarStyle.canvasInset,
            dy: 0
        )
        let availableWidth = max(contentBounds.width - contentGap, 0)
        let pathWidth = floor(availableWidth * pathFraction)
        return (
            path: NSRect(
                x: contentBounds.minX,
                y: contentBounds.minY,
                width: pathWidth,
                height: contentBounds.height
            ),
            agents: NSRect(
                x: contentBounds.minX + pathWidth + contentGap,
                y: contentBounds.minY,
                width: max(availableWidth - pathWidth, 0),
                height: contentBounds.height
            )
        )
    }
}

enum WorkspaceTouchBarStyle {
    static let canvasInset: CGFloat = 6
    static let itemBackground = NSColor(
        red: 45 / 255,
        green: 41 / 255,
        blue: 44 / 255,
        alpha: 1
    )
    static let dividerColor = NSColor.white.withAlphaComponent(0.24)
    static let primaryTextColor = NSColor.white
    static let secondaryTextColor = NSColor.white.withAlphaComponent(0.72)
    static let controlHeight: CGFloat = 30
    static let cornerRadius: CGFloat = 6.25
    static let itemSpacing: CGFloat = 6
    static let horizontalPadding: CGFloat = 12
    static let imageTitleSpacing: CGFloat = 7
    static let iconWidth: CGFloat = 16
    static let agentItemWidth: CGFloat = 44
    static let agentIconSize: CGFloat = 26
    static let agentEdgeFadeWidth: CGFloat = 8
    @MainActor
    static var titleFont: NSFont {
        NSFont.systemFont(
            ofSize: 12,
            weight: .semibold
        )
    }

    @MainActor
    static var secondaryFont: NSFont {
        NSFont.systemFont(
            ofSize: 10,
            weight: .regular
        )
    }

    static let failureSymbolName: String? = nil

    @MainActor
    static func symbol(
        named name: String?,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let name else { return nil }
        return NSImage(
            systemSymbolName: name,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: 11,
                weight: .medium
            )
        )
    }

    @MainActor
    static func agentSymbol(for id: AgentID) -> NSImage? {
        let symbolName: String
        switch id {
        case .codex:
            symbolName = "chevron.left.forwardslash.chevron.right"
        case .claudeCode:
            symbolName = "terminal"
        case .cursor:
            symbolName = "cursorarrow.rays"
        case .grokBuild:
            symbolName = "sparkles"
        }
        return symbol(
            named: symbolName,
            accessibilityDescription: id.rawValue
        ) ?? symbol(
            named: "circle.fill",
            accessibilityDescription: id.rawValue
        )
    }

    @MainActor
    static func agentIcon(for agent: AvailableAgent) -> NSImage? {
        let sourceImage: NSImage?
        if let applicationURL = agent.iconApplicationURL {
            sourceImage = NSWorkspace.shared.icon(forFile: applicationURL.path)
            sourceImage?.isTemplate = false
        } else {
            sourceImage = agentSymbol(for: agent.id)
        }
        guard let sourceImage else { return nil }

        let targetSize = NSSize(
            width: agentIconSize,
            height: agentIconSize
        )
        let icon = NSImage(size: targetSize, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            sourceImage.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }
        icon.isTemplate = sourceImage.isTemplate
        return icon
    }
}

@MainActor
final class WorkspaceTouchBarContentView: NSView {
    private let pathView: NSView
    private let agentsView: NSView
    private let dividerView = NSView()
    private let agentsPlaceholder = NSTextField(labelWithString: "")

    var onWindowAttachmentChanged: ((Bool) -> Void)?

    init(pathView: NSView, agentsView: NSView) {
        self.pathView = pathView
        self.agentsView = agentsView
        super.init(frame: .zero)
        addSubview(pathView)
        addSubview(agentsView)
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = WorkspaceTouchBarStyle
            .dividerColor.cgColor
        addSubview(dividerView)
        agentsPlaceholder.font = WorkspaceTouchBarStyle.secondaryFont
        agentsPlaceholder.textColor = WorkspaceTouchBarStyle
            .secondaryTextColor
        agentsPlaceholder.alignment = .center
        agentsPlaceholder.lineBreakMode = .byTruncatingTail
        agentsPlaceholder.isHidden = true
        addSubview(agentsPlaceholder)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowAttachmentChanged?(window != nil)
    }

    override func layout() {
        super.layout()
        let frames = WorkspaceTouchBarLayout.regionFrames(in: bounds)
        pathView.frame = WorkspaceTouchBarLayout.centeredControlFrame(
            in: frames.path,
            preferredWidth: frames.path.width
        )
        agentsView.frame = WorkspaceTouchBarLayout.centeredControlFrame(
            in: frames.agents,
            preferredWidth: frames.agents.width
        )
        dividerView.frame = NSRect(
            x: floor((frames.path.maxX + frames.agents.minX) / 2),
            y: floor(bounds.midY - 9),
            width: 1,
            height: 18
        )
        agentsPlaceholder.frame = agentsView.frame.insetBy(dx: 8, dy: 2)
        if let scrubber = agentsView as? NSScrubber {
            scrubber.scrubberLayout.invalidateLayout()
        }
    }

    func showAgentsPlaceholder(_ text: String?) {
        agentsPlaceholder.stringValue = text ?? ""
        agentsPlaceholder.isHidden = text == nil
        agentsView.isHidden = text != nil
    }
}

@MainActor
final class WorkspaceTouchBarPathView: NSView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private var isInteractionEnabled = true
    var onActivate: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = WorkspaceTouchBarStyle.itemBackground.cgColor
        layer?.cornerRadius = WorkspaceTouchBarStyle.cornerRadius
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = WorkspaceTouchBarStyle.primaryTextColor
        imageView.wantsLayer = true
        addSubview(imageView)
        titleLabel.font = WorkspaceTouchBarStyle.titleFont
        titleLabel.textColor = WorkspaceTouchBarStyle.primaryTextColor
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        actionButton.title = ""
        actionButton.isBordered = false
        actionButton.setButtonType(.momentaryChange)
        actionButton.target = self
        actionButton.action = #selector(activatePath)
        actionButton.toolTip = nil
        addSubview(actionButton)
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
        let contentsScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        layer?.contentsScale = contentsScale
        imageView.layer?.contentsScale = contentsScale
        actionButton.frame = bounds
        let iconSize = WorkspaceTouchBarStyle.iconWidth
        let iconX = WorkspaceTouchBarStyle.horizontalPadding
        imageView.frame = NSRect(
            x: iconX,
            y: floor(bounds.midY - iconSize / 2),
            width: iconSize,
            height: iconSize
        )
        let titleX = imageView.isHidden
            ? WorkspaceTouchBarStyle.horizontalPadding
            : imageView.frame.maxX + WorkspaceTouchBarStyle.imageTitleSpacing
        let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
        titleLabel.frame = NSRect(
            x: titleX,
            y: floor(bounds.midY - titleHeight / 2),
            width: max(
                bounds.width - titleX
                    - WorkspaceTouchBarStyle.horizontalPadding,
                0
            ),
            height: titleHeight
        )
    }

    override func accessibilityPerformPress() -> Bool {
        guard isInteractionEnabled else { return false }
        onActivate?()
        return true
    }

    @objc
    private func activatePath() {
        guard isInteractionEnabled else { return }
        onActivate?()
    }

    func display(
        image: NSImage?,
        title: String,
        toolTip: String?,
        enabled: Bool
    ) {
        imageView.image = image
        titleLabel.stringValue = title
        self.toolTip = toolTip
        isInteractionEnabled = enabled
        actionButton.isEnabled = enabled
        actionButton.toolTip = toolTip
        alphaValue = enabled ? 1 : 0.42
        imageView.isHidden = image == nil
        needsLayout = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        actionButton.setAccessibilityLabel(title)
    }
}

@MainActor
final class WorkspaceAgentScrubber: NSScrubber {
    private let edgeMask = CAGradientLayer()
    private var contentOverflows = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        edgeMask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor,
        ]
        edgeMask.startPoint = CGPoint(x: 0, y: 0.5)
        edgeMask.endPoint = CGPoint(x: 1, y: 0.5)
        // 不在这里直接挂 mask了，改为按 setContentOverflows 按需开关
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 由 layout 在 prepare() 时回调，告知内容是否超出可视宽度。
    /// 只有溢出时才需要边缘渐变，暗示"这里可以滑动"。
    func setContentOverflows(_ overflows: Bool) {
        guard overflows != contentOverflows else { return }
        contentOverflows = overflows
        layer?.mask = overflows ? edgeMask : nil
    }

    override func layout() {
        super.layout()
        edgeMask.frame = bounds
        let fadeFraction = min(
            WorkspaceTouchBarStyle.agentEdgeFadeWidth
                / max(bounds.width, 1),
            0.28
        )
        edgeMask.locations = [
            0,
            NSNumber(value: fadeFraction),
            NSNumber(value: 1 - fadeFraction),
            1,
        ]
    }
}

@MainActor
final class WorkspaceCenteredScrubberFlowLayout: NSScrubberFlowLayout {
    private var horizontalInset: CGFloat = 0

    override func prepare() {
        super.prepare()
        guard let scrubber else {
            horizontalInset = 0
            return
        }
        let itemCount = scrubber.numberOfItems
        let itemsWidth = CGFloat(itemCount) * itemSize.width
            + CGFloat(max(itemCount - 1, 0)) * itemSpacing
        let overflows = itemsWidth > visibleRect.width

        // 未溢出：把内容居中显示；溢出：贴左对齐，交给滑动+渐变来处理
        horizontalInset = overflows
            ? 0
            : max((visibleRect.width - itemsWidth) / 2, 0)

        (scrubber as? WorkspaceAgentScrubber)?.setContentOverflows(overflows)
    }

    override var scrubberContentSize: NSSize {
        var size = super.scrubberContentSize
        size.width = max(size.width + horizontalInset * 2, visibleRect.width)
        return size
    }

    override func layoutAttributesForItem(
        at index: Int
    ) -> NSScrubberLayoutAttributes? {
        guard
            let attributes = super.layoutAttributesForItem(at: index)?.copy()
                as? NSScrubberLayoutAttributes
        else {
            return nil
        }
        attributes.frame.origin.x += horizontalInset
        return attributes
    }

    override func layoutAttributesForItems(
        in rect: NSRect
    ) -> Set<NSScrubberLayoutAttributes> {
        guard let scrubber else { return [] }
        return Set(
            (0..<scrubber.numberOfItems).compactMap { index in
                guard
                    let attributes = layoutAttributesForItem(at: index),
                    attributes.frame.intersects(rect)
                else {
                    return nil
                }
                return attributes
            }
        )
    }

}

enum WorkspaceTouchBarPresentationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "当前系统不支持替换物理 Touch Bar"
        }
    }
}

enum WorkspacePresentationModeDismissalAction: Equatable {
    case preserveCurrent
    case set(String)
    case remove
}

enum WorkspacePresentationModePolicy {
    static func dismissalAction(
        currentMode: String?,
        workspaceMode: String,
        previousMode: String?,
        hadPreviousMode: Bool
    ) -> WorkspacePresentationModeDismissalAction {
        guard currentMode == workspaceMode else {
            return .preserveCurrent
        }
        if hadPreviousMode, let previousMode {
            return .set(previousMode)
        }
        return .remove
    }
}

enum WorkspacePresentationInterruptionPolicy {
    static func shouldInterrupt(
        isPresented: Bool,
        hasAttachedToWindow: Bool,
        isExplicitlyDismissing: Bool,
        isCurrentlyAttached: Bool,
        currentMode: String?,
        workspaceMode: String
    ) -> Bool {
        isPresented
            && hasAttachedToWindow
            && !isExplicitlyDismissing
            && !isCurrentlyAttached
            && currentMode != workspaceMode
    }
}

@MainActor
final class WorkspaceTouchBarAgentItemView: NSScrubberItemView {
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = WorkspaceTouchBarStyle.primaryTextColor
        imageView.wantsLayer = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let contentsScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        layer?.contentsScale = contentsScale
        imageView.layer?.contentsScale = contentsScale
        let iconSize = WorkspaceTouchBarStyle.agentIconSize
        imageView.frame = NSRect(
            x: floor(bounds.midX - iconSize / 2),
            y: floor(bounds.midY - iconSize / 2),
            width: iconSize,
            height: iconSize
        )
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    func display(_ agent: AvailableAgent) {
        let icon = WorkspaceTouchBarStyle.agentIcon(for: agent)
        imageView.image = icon
        imageView.contentTintColor = icon?.isTemplate == true
            ? WorkspaceTouchBarStyle.primaryTextColor
            : nil
        toolTip = "左右滑动选择；点按 \(agent.displayName) 启动"
        setAccessibilityLabel(agent.displayName)
        updateAppearance()
    }

    private func updateAppearance() {
        wantsLayer = true
        layer?.cornerRadius = WorkspaceTouchBarStyle.cornerRadius
        let emphasized = isSelected || isHighlighted
        layer?.backgroundColor = emphasized
            ? NSColor.white.withAlphaComponent(0.22).cgColor
            : NSColor.white.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = emphasized ? 1 : 0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        imageView.alphaValue = emphasized ? 1 : 0.94
        imageView.layer?.setAffineTransform(.identity)
    }
}

@MainActor
final class WorkspaceTouchBarController: NSObject,
    NSTouchBarDelegate,
    NSScrubberDataSource,
    NSScrubberDelegate
{
    private enum ItemIdentifier {
        static let content = NSTouchBarItem.Identifier(
            "com.toubarreplace.workspace.content"
        )
        static let agentView = NSUserInterfaceItemIdentifier(
            "com.toubarreplace.workspace.agent-view"
        )
        static let switcher = NSTouchBarItem.Identifier(
            "com.toubarreplace.workspace.switcher"
        )
    }

    private let touchBar = NSTouchBar()
    private let pathView = WorkspaceTouchBarPathView()
    private let scrubber = WorkspaceAgentScrubber()
    private lazy var contentView = WorkspaceTouchBarContentView(
        pathView: pathView,
        agentsView: scrubber
    )
    private var agents: [AvailableAgent] = []
    private var context: WorkspaceContext?
    private var previousPresentationMode: String?
    private var hadPreviousPresentationMode = false
    private var agentsEnabled = false
    private var selectedAgentIndex: Int?
    private var hasAttachedToTouchBarWindow = false
    private var isExplicitlyDismissing = false
    private var detachmentTask: Task<Void, Never>?
    private(set) var isPresented = false

    var onResolvePath: (() -> Void)?
    var onAgentActivated: ((AvailableAgent) -> Void)?
    var onPresentationInterrupted: (() -> Void)?

    override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            ItemIdentifier.content,
            ItemIdentifier.switcher,
        ]
        touchBar.principalItemIdentifier = ItemIdentifier.content
        touchBar.customizationAllowedItemIdentifiers = []

        contentView.onWindowAttachmentChanged = { [weak self] attached in
            self?.handleWindowAttachmentChanged(attached)
        }

        pathView.onActivate = { [weak self] in
            self?.onResolvePath?()
        }

        let layout = WorkspaceCenteredScrubberFlowLayout()
        layout.itemSize = NSSize(
            width: WorkspaceTouchBarStyle.agentItemWidth,
            height: WorkspaceTouchBarStyle.controlHeight
        )
        layout.itemSpacing = WorkspaceTouchBarStyle.itemSpacing
        scrubber.scrubberLayout = layout
        scrubber.mode = .free
        scrubber.isContinuous = false
        scrubber.itemAlignment = .center
        scrubber.showsArrowButtons = false
        scrubber.showsAdditionalContentIndicators = false
        scrubber.selectionBackgroundStyle = .roundedBackground
        scrubber.floatsSelectionViews = true
        scrubber.backgroundColor = .clear
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.register(
            WorkspaceTouchBarAgentItemView.self,
            forItemIdentifier: ItemIdentifier.agentView
        )
        showIdle(lastPath: WorkspacePreferences.lastPath)
    }

    func present() throws {
        guard !isPresented else { return }
        guard TBRCanPresentSystemModalTouchBar() else {
            throw WorkspaceTouchBarPresentationError.unavailable
        }

        let storedMode = TouchBarPresentationPreferences.currentMode
        hadPreviousPresentationMode = storedMode != nil
        previousPresentationMode = storedMode
        detachmentTask?.cancel()
        hasAttachedToTouchBarWindow = false
        isExplicitlyDismissing = false
        isPresented = true
        TBRSetSystemModalShowsCloseBoxWhenFrontMost(false)
        TBRPresentSystemModalTouchBar(
            touchBar,
            WorkspaceTouchBarLayout.placement
        )
        TouchBarPresentationPreferences.setCurrentMode(
            WorkspaceTouchBarLayout.presentationMode
        )
        TBRHideSystemModalCloseButton()
    }

    func dismiss() {
        guard isPresented else { return }
        isExplicitlyDismissing = true
        detachmentTask?.cancel()
        detachmentTask = nil
        let dismissalAction = WorkspacePresentationModePolicy.dismissalAction(
            currentMode: TouchBarPresentationPreferences.currentMode,
            workspaceMode: WorkspaceTouchBarLayout.presentationMode,
            previousMode: previousPresentationMode,
            hadPreviousMode: hadPreviousPresentationMode
        )
        switch dismissalAction {
        case .preserveCurrent:
            break
        case let .set(mode):
            TouchBarPresentationPreferences.setCurrentMode(mode)
        case .remove:
            TouchBarPresentationPreferences.setCurrentMode(
                nil
            )
        }
        TBRDismissSystemModalTouchBar(touchBar)
        TBRSetSystemModalShowsCloseBoxWhenFrontMost(true)
        previousPresentationMode = nil
        hadPreviousPresentationMode = false
        hasAttachedToTouchBarWindow = false
        isPresented = false
        isExplicitlyDismissing = false
    }

    func showIdle(lastPath: URL?) {
        context = nil
        agents = []
        let image = WorkspaceTouchBarStyle.symbol(
            named: "folder",
            accessibilityDescription: "项目路径"
        )
        if let lastPath {
            pathView.display(
                image: image,
                title: "最近 · \(lastPath.lastPathComponent)",
                toolTip: lastPath.path,
                enabled: true
            )
        } else {
            pathView.display(
                image: image,
                title: "获取当前项目路径",
                toolTip: nil,
                enabled: true
            )
        }
        reloadAgents(enabled: false, placeholder: "选择项目后启动 Agent")
    }

    func showResolving() {
        context = nil
        agents = []
        pathView.display(
            image: WorkspaceTouchBarStyle.symbol(
                named: "hourglass",
                accessibilityDescription: "正在获取当前项目路径"
            ),
            title: "正在获取项目路径…",
            toolTip: nil,
            enabled: false
        )
        reloadAgents(enabled: false, placeholder: "正在读取项目…")
    }

    func showReady(
        context: WorkspaceContext,
        agents: [AvailableAgent]
    ) {
        self.context = context
        self.agents = agents
        pathView.display(
            image: WorkspaceTouchBarStyle.symbol(
                named: "folder",
                accessibilityDescription: "当前项目路径"
            ),
            title: context.compactTitle,
            toolTip: context.directoryURL.path,
            enabled: true
        )
        reloadAgents(
            enabled: true,
            placeholder: agents.isEmpty ? "未发现可用 Agent" : nil
        )
    }

    func showLaunching(
        agent: AvailableAgent,
        context: WorkspaceContext
    ) {
        pathView.display(
            image: WorkspaceTouchBarStyle.symbol(
                named: "hourglass",
                accessibilityDescription: "正在启动 Agent"
            ),
            title: "\(context.directoryURL.lastPathComponent) · 正在打开 \(agent.displayName)…",
            toolTip: context.directoryURL.path,
            enabled: false
        )
        agentsEnabled = false
        scrubber.alphaValue = 0.45
    }

    func showFailure(
        _ message: String,
        context: WorkspaceContext?,
        agents: [AvailableAgent]
    ) {
        self.context = context
        self.agents = context == nil ? [] : agents
        pathView.display(
            image: WorkspaceTouchBarStyle.symbol(
                named: WorkspaceTouchBarStyle.failureSymbolName,
                accessibilityDescription: "Workspace 操作失败"
            ),
            title: message,
            toolTip: context?.directoryURL.path,
            enabled: true
        )
        let placeholder: String?
        if context == nil {
            placeholder = "请重新选择项目"
        } else if self.agents.isEmpty {
            placeholder = "未发现可用 Agent"
        } else {
            placeholder = nil
        }
        reloadAgents(enabled: context != nil, placeholder: placeholder)
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case ItemIdentifier.content:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.customizationLabel = "Workspace"
            contentView.widthAnchor.constraint(
                greaterThanOrEqualToConstant:
                    WorkspaceTouchBarLayout.minimumContentWidth
            ).isActive = true
            let preferredWidth = contentView.widthAnchor.constraint(
                equalToConstant: WorkspaceTouchBarLayout.preferredContentWidth
            )
            preferredWidth.priority = .defaultHigh
            preferredWidth.isActive = true
            item.view = contentView
            return item
        case ItemIdentifier.switcher:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.customizationLabel = "切换"
            item.view = createSwitchButton()
            return item
        default:
            return nil
        }
    }

    func numberOfItems(for scrubber: NSScrubber) -> Int {
        agents.count
    }

    func scrubber(
    _ scrubber: NSScrubber,
    viewForItemAt index: Int
    ) -> NSScrubberItemView {
        guard
        let view = scrubber.makeItem(
            withIdentifier: ItemIdentifier.agentView,
            owner: self
        ) as? WorkspaceTouchBarAgentItemView,
        agents.indices.contains(index)
        else {
            return NSScrubberItemView()
        }
        view.display(agents[index])
        return view
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
        guard agentsEnabled, agents.indices.contains(index) else { return }

        let agent = agents[index]
        selectedAgentIndex = index
        onAgentActivated?(agent)

        // 点击后主动清空选中态，避免下一次点同一个 item 时因为状态未变化而被框架吞掉
        // （我们只保留 internal memory，不让 scrubber.selectedIndex 记住它）
        selectedAgentIndex = nil
    }

    private func reloadAgents(enabled: Bool, placeholder: String? = nil) {
        scrubber.reloadData()
        agentsEnabled = enabled && !agents.isEmpty
        scrubber.alphaValue = agentsEnabled ? 1 : 0.45
        contentView.showAgentsPlaceholder(placeholder)
        if !agents.isEmpty {
            let selectedIndex = selectedAgentIndex.flatMap { index in
                agents.indices.contains(index) ? index : nil
            } ?? 0
            selectedAgentIndex = selectedIndex

            // 不再设置 scrubber.selectedIndex，避免 item 一开始就被标记为"已选中"
            // 只会做居中滚动，不触发选中态
            scrubber.scrubberLayout.invalidateLayout()
            scrubber.scrollItem(
                at: selectedIndex,
                to: .center
            )
        } else {
            selectedAgentIndex = nil
        }
    }

    private func handleWindowAttachmentChanged(_ attached: Bool) {
        detachmentTask?.cancel()
        detachmentTask = nil
        if attached {
            guard isPresented else { return }
            hasAttachedToTouchBarWindow = true
            return
        }
        guard
            isPresented,
            hasAttachedToTouchBarWindow,
            !isExplicitlyDismissing
        else {
            return
        }

        detachmentTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            guard WorkspacePresentationInterruptionPolicy.shouldInterrupt(
                isPresented: self.isPresented,
                hasAttachedToWindow: self.hasAttachedToTouchBarWindow,
                isExplicitlyDismissing: self.isExplicitlyDismissing,
                isCurrentlyAttached: self.contentView.window != nil,
                currentMode: TouchBarPresentationPreferences.currentMode,
                workspaceMode: WorkspaceTouchBarLayout.presentationMode
            ) else {
                return
            }
            self.previousPresentationMode = nil
            self.hadPreviousPresentationMode = false
            self.hasAttachedToTouchBarWindow = false
            self.isPresented = false
            TBRSetSystemModalShowsCloseBoxWhenFrontMost(true)
            self.onPresentationInterrupted?()
        }
    }
}
