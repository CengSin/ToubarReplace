import AppKit
import TouchBarPrivateAPI

enum WorkspaceTouchBarLayout {
    static let presentationMode = "app"
    static let placement: Int64 = 1
    /// Soft floor so a tiny settings width still yields a usable principal item.
    static let minimumContentWidth: CGFloat = 400
    /// DFR-class full Function Row width (~1085×30 pt). Used for strip geometry
    /// smoke tests; runtime preferred width is capped separately (see
    /// ``maximumContentWidth``) so trailing custom slots are not clipped.
    static let designReferenceBarWidth: CGFloat = 1_010
    /// Cap preferred item width below full DFR width. Mirror settings can be
    /// larger (scaled desktop viewport); even 1085 can overflow system chrome
    /// on the Function Row and clip the trailing custom slot.
    static let maximumContentWidth: CGFloat = 1_010

    /// Preferred Workspace item size in points from mirror settings (pixels ÷ scale),
    /// clamped to ``[minimumContentWidth, maximumContentWidth]``.
    /// Default mirror `2300×70` @2x → width capped to `1010`, height `35`
    /// (height is only used by the mirror window; TB chrome stays 30pt).
    static func preferredContentSize(
        mirrorPixelSize: CGSize = TouchBarPreferences.mirrorPixelSize,
        backingScaleFactor: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    ) -> CGSize {
        let points = TouchBarWindowMetrics.pointSize(
            forPixelSize: mirrorPixelSize,
            backingScaleFactor: backingScaleFactor
        )
        let width = min(
            max(points.width, minimumContentWidth),
            maximumContentWidth
        )
        return CGSize(
            width: width,
            height: max(points.height, 1)
        )
    }

    static func preferredContentWidth(
        mirrorPixelSize: CGSize = TouchBarPreferences.mirrorPixelSize,
        backingScaleFactor: CGFloat = NSScreen.main?.backingScaleFactor ?? 2
    ) -> CGFloat {
        preferredContentSize(
            mirrorPixelSize: mirrorPixelSize,
            backingScaleFactor: backingScaleFactor
        ).width
    }

    /// Return control sits outside the 10-unit grid (design v2).
    static let switcherWidth: CGFloat = 44
    static let switcherContentGap: CGFloat = 10

    /// Design grid on the tray: Path 4/10 | Agents 3/10 | Custom 3/10.
    /// Path *zone* uses ``pathRegionScale`` of the unit share as its **base**
    /// width; when the path plate needs more room for a long folder name, the
    /// zone may grow (agents|custom share the remainder) up to
    /// ``minimumAgentsCustomWidth`` floor. Path *plate* still hugs title and
    /// is centered in the path zone.
    static let totalUnits = 10
    static let pathUnits = 4
    static let agentsUnits = 3
    static let customUnits = 3
    /// Base path zone as a fraction of the 4/10 unit share (1.0 = full design).
    static let pathRegionScale: CGFloat = 1.0
    /// Soft floor for the path plate region (includes zone insets).
    static let minimumPathRegionWidth: CGFloat = 120
    /// When a long folder name expands the path zone, agents|custom keep at
    /// least this combined width so icon slots stay usable.
    static let minimumAgentsCustomWidth: CGFloat = 280

    /// Hairline between zones on the continuous tray.
    static let zoneDividerWidth: CGFloat = 1
    /// Inset of path plate / icon slots inside each zone (design breathing room).
    static let zoneContentInset: CGFloat = 6
    /// Vertical inset of icon slots inside the tray control height.
    static let slotVerticalInset: CGFloat = 3
    /// Extra right pad inside the tray so the last custom slot (+ / app) is not
    /// clipped by system Function Row chrome.
    static let trayTrailingSafeInset: CGFloat = 6

    /// Path *zone* width: design 4/10 of the usable tray × ``pathRegionScale``,
    /// then grow if `pathPreferredWidth` (plate hug) needs more room so the
    /// folder name is not middle-truncated. Cap expansion so agents|custom
    /// retain ``minimumAgentsCustomWidth``.
    static func pathRegionWidth(
        trayWidth: CGFloat,
        pathPreferredWidth: CGFloat = 0
    ) -> CGFloat {
        guard trayWidth > 0 else { return 0 }
        let unitShare = floor(
            trayWidth * CGFloat(pathUnits) / CGFloat(totalUnits)
        )
        let baseWidth = max(floor(unitShare * pathRegionScale), 0)
        // Plate is laid out inside zoneContentRect; zone must include insets.
        let preferredZone = pathPreferredWidth > 0
            ? ceil(pathPreferredWidth) + zoneContentInset * 2
            : 0
        let maxPathWidth = max(
            trayWidth - minimumAgentsCustomWidth,
            baseWidth
        )
        let desired = max(baseWidth, preferredZone, minimumPathRegionWidth)
        return min(floor(desired), floor(maxPathWidth), trayWidth)
    }

    /// Split tray into path | agents | custom. Path uses base 4/10 (may grow
    /// for long titles); remainder after path is split 1:1 for agents|custom.
    static func trayZoneFrames(
        tray: NSRect,
        pathPreferredWidth: CGFloat = 0
    ) -> (path: NSRect, agents: NSRect, custom: NSRect) {
        let usableWidth = max(tray.width - trayTrailingSafeInset, 0)
        let pathWidth = pathRegionWidth(
            trayWidth: usableWidth,
            pathPreferredWidth: pathPreferredWidth
        )
        let remainder = max(usableWidth - pathWidth, 0)
        // agents:custom = 3:3
        let agentsWidth = floor(remainder / 2)
        let customWidth = max(remainder - agentsWidth, 0)
        let path = NSRect(
            x: tray.minX,
            y: tray.minY,
            width: pathWidth,
            height: tray.height
        )
        let agents = NSRect(
            x: path.maxX,
            y: tray.minY,
            width: agentsWidth,
            height: tray.height
        )
        let custom = NSRect(
            x: agents.maxX,
            y: tray.minY,
            width: customWidth,
            height: tray.height
        )
        return (path, agents, custom)
    }

    /// Full-bar strip: switcher (outside grid) + continuous tray.
    static func stripFrames(
        in bounds: NSRect,
        pathPreferredWidth: CGFloat = 0
    ) -> (
        switcher: NSRect,
        tray: NSRect,
        path: NSRect,
        agents: NSRect,
        custom: NSRect
    ) {
        let height = min(
            WorkspaceTouchBarStyle.controlHeight,
            max(bounds.height, 1)
        )
        let y = bounds.midY - height / 2
        let inset = WorkspaceTouchBarStyle.canvasInset
        let switcher = NSRect(
            x: bounds.minX + inset,
            y: y,
            width: switcherWidth,
            height: height
        )
        let trayX = switcher.maxX + switcherContentGap
        let trayWidth = max(
            bounds.maxX - inset - trayX,
            0
        )
        let tray = NSRect(
            x: trayX,
            y: y,
            width: trayWidth,
            height: height
        )
        let zones = trayZoneFrames(
            tray: tray,
            pathPreferredWidth: pathPreferredWidth
        )
        return (switcher, tray, zones.path, zones.agents, zones.custom)
    }

    /// Full-width tray when switcher is not embedded (mirror fallback bar).
    static func trayFrame(in bounds: NSRect) -> NSRect {
        let height = min(
            WorkspaceTouchBarStyle.controlHeight,
            max(bounds.height, 1)
        )
        let inset = WorkspaceTouchBarStyle.canvasInset
        return NSRect(
            x: bounds.minX + inset,
            y: bounds.midY - height / 2,
            width: max(bounds.width - inset * 2, 0),
            height: height
        )
    }

    /// Slot count for the agents zone (at least 1 for placeholder).
    static func agentSlotCount(agentCount: Int) -> Int {
        max(agentCount, 1)
    }

    /// Slot count for custom zone: empty label, or apps + settings button.
    static func customSlotCount(appCount: Int) -> Int {
        let count = max(0, min(appCount, CustomWorkspaceAppList.maxCount))
        return count == 0 ? 1 : count + 1
    }

    /// Equal column width inside a zone for `slotCount` items.
    static func equalSlotWidth(
        regionWidth: CGFloat,
        slotCount: Int,
        spacing: CGFloat = WorkspaceTouchBarStyle.itemSpacing
    ) -> CGFloat {
        let count = max(slotCount, 1)
        let gaps = spacing * CGFloat(count - 1)
        return max(floor((regionWidth - gaps) / CGFloat(count)), 1)
    }

    /// Frames for equally spaced slots inside a region (left → right).
    /// Region should already be inset for zone padding when used for icons.
    static func slotFrames(
        in region: NSRect,
        slotCount: Int,
        spacing: CGFloat = WorkspaceTouchBarStyle.itemSpacing
    ) -> [NSRect] {
        let count = max(slotCount, 1)
        let slotHeight = max(
            region.height - slotVerticalInset * 2,
            WorkspaceTouchBarStyle.controlHeight - slotVerticalInset * 2
        )
        let usable = NSRect(
            x: region.minX,
            y: region.midY - slotHeight / 2,
            width: region.width,
            height: slotHeight
        )
        let slotWidth = equalSlotWidth(
            regionWidth: usable.width,
            slotCount: count,
            spacing: spacing
        )
        return (0..<count).map { index in
            let x = usable.minX + CGFloat(index) * (slotWidth + spacing)
            return NSRect(
                x: x,
                y: usable.minY,
                width: slotWidth,
                height: usable.height
            )
        }
    }

    /// Inner rect of a zone after horizontal breathing room.
    static func zoneContentRect(_ region: NSRect) -> NSRect {
        region.insetBy(dx: zoneContentInset, dy: 0)
    }

    /// Tray-only regions (path | agents | custom). Prefer `stripFrames` when
    /// the return button is in the same view.
    static func regionFrames(
        in bounds: NSRect,
        pathPreferredWidth: CGFloat = 0
    ) -> (
        path: NSRect,
        agents: NSRect,
        custom: NSRect
    ) {
        trayZoneFrames(
            tray: bounds,
            pathPreferredWidth: pathPreferredWidth
        )
    }
}

enum WorkspaceTouchBarStyle {
    /// Outer padding of content item (switcher is a separate TB item).
    static let canvasInset: CGFloat = 4
    /// Continuous tray under the 10-unit strip (design v2 soft surface).
    static let trayBackground = NSColor(
        red: 32 / 255,
        green: 30 / 255,
        blue: 34 / 255,
        alpha: 1
    )
    /// Path plate + equal icon slots (same chrome weight).
    static let itemBackground = NSColor(
        red: 48 / 255,
        green: 45 / 255,
        blue: 50 / 255,
        alpha: 1
    )
    /// Pressed chrome for tray slots (agent / custom / path / switcher).
    static let itemHighlightedBackground = NSColor.white.withAlphaComponent(0.22)
    static let itemHighlightBorderColor = NSColor.white.withAlphaComponent(0.32)
    static let dividerColor = NSColor.white.withAlphaComponent(0.19)
    static let primaryTextColor = NSColor.white
    static let secondaryTextColor = NSColor.white.withAlphaComponent(0.72)
    static let controlHeight: CGFloat = 30
    static let cornerRadius: CGFloat = 7
    static let trayCornerRadius: CGFloat = 8
    /// Gap between equal icon slots (design v2).
    static let itemSpacing: CGFloat = 6
    static let horizontalPadding: CGFloat = 12
    static let imageTitleSpacing: CGFloat = 7
    static let iconWidth: CGFloat = 16
    static let agentIconSize: CGFloat = 22
    @MainActor
    static var titleFont: NSFont {
        NSFont.systemFont(ofSize: 12, weight: .semibold)
    }

    @MainActor
    static var secondaryFont: NSFont {
        NSFont.systemFont(ofSize: 10, weight: .regular)
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
            NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
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

    /// Bundled brand mark used when the agent has no local app icon.
    /// Source files live under `Resources/AgentIcons/<AgentID.rawValue>.png`.
    ///
    /// Resolution order (do **not** use `Bundle.module` here):
    /// - Packaged `.app`: `Contents/Resources/AgentIcons/` (see `Packaging/build-app.sh`)
    /// - `swift run` / release binary: SPM resource dir next to the executable
    ///   (`ToubarReplace_ToubarReplace.bundle`, flattened by `.process`)
    ///
    /// `Bundle.module` for an `executableTarget` looks for the resource bundle
    /// at `Bundle.main.bundleURL` (the `.app` root) and `fatalError`s if missing.
    /// That path is invalid for codesigned apps, and SPM's flat `.bundle` is not
    /// a codesignable package — so packaging copies icons into main Resources only.
    @MainActor
    static func agentDefaultIcon(for id: AgentID) -> NSImage? {
        let resourceName = id.rawValue
        var candidates: [URL?] = [
            Bundle.main.url(
                forResource: resourceName,
                withExtension: "png",
                subdirectory: "AgentIcons"
            ),
            Bundle.main.resourceURL?
                .appendingPathComponent("AgentIcons", isDirectory: true)
                .appendingPathComponent("\(resourceName).png"),
        ]
        // SPM layout: resource bundle sits beside the executable (not under .app root).
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let spmBundle = exeDir.appendingPathComponent(
                "ToubarReplace_ToubarReplace.bundle",
                isDirectory: true
            )
            candidates.append(
                spmBundle.appendingPathComponent("\(resourceName).png")
            )
            candidates.append(
                spmBundle
                    .appendingPathComponent("AgentIcons", isDirectory: true)
                    .appendingPathComponent("\(resourceName).png")
            )
        }
        for candidate in candidates {
            guard let url = candidate,
                FileManager.default.fileExists(atPath: url.path),
                let image = NSImage(contentsOf: url)
            else { continue }
            image.isTemplate = false
            return image
        }
        return nil
    }

    @MainActor
    static func agentIcon(for agent: AvailableAgent) -> NSImage? {
        let sourceImage: NSImage?
        if let applicationURL = agent.iconApplicationURL,
            FileManager.default.fileExists(atPath: applicationURL.path)
        {
            sourceImage = NSWorkspace.shared.icon(forFile: applicationURL.path)
            sourceImage?.isTemplate = false
        } else if let defaultIcon = agentDefaultIcon(for: agent.id) {
            sourceImage = defaultIcon
        } else {
            sourceImage = agentSymbol(for: agent.id)
        }
        return scaledIcon(from: sourceImage)
    }

    @MainActor
    static func customAppIcon(for app: CustomWorkspaceApp) -> NSImage? {
        let path = app.applicationPath
        let sourceImage: NSImage?
        if FileManager.default.fileExists(atPath: path) {
            sourceImage = NSWorkspace.shared.icon(forFile: path)
            sourceImage?.isTemplate = false
        } else if let bundleIdentifier = app.bundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            )
        {
            sourceImage = NSWorkspace.shared.icon(forFile: url.path)
            sourceImage?.isTemplate = false
        } else {
            sourceImage = symbol(
                named: "app.dashed",
                accessibilityDescription: app.displayName
            )
        }
        return scaledIcon(from: sourceImage)
    }

    @MainActor
    private static func scaledIcon(from sourceImage: NSImage?) -> NSImage? {
        guard let sourceImage else { return nil }
        let targetSize = NSSize(width: agentIconSize, height: agentIconSize)
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

    @MainActor
    static func applyItemChrome(
        to layer: CALayer?,
        highlighted: Bool,
        enabled: Bool = true
    ) {
        let showHighlight = highlighted && enabled
        layer?.backgroundColor = showHighlight
            ? itemHighlightedBackground.cgColor
            : itemBackground.cgColor
        layer?.borderWidth = showHighlight ? 1 : 0
        layer?.borderColor = itemHighlightBorderColor.cgColor
        layer?.cornerRadius = cornerRadius
    }
}

/// Borderless tray control with reliable Touch Bar target/action and press chrome.
/// Custom-styled `NSButton`s otherwise show no highlight when `isBordered` is false.
@MainActor
final class WorkspaceChromeButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureDefaults()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureDefaults() {
        isBordered = false
        bezelStyle = .rounded
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.masksToBounds = true
        font = WorkspaceTouchBarStyle.secondaryFont
        contentTintColor = WorkspaceTouchBarStyle.primaryTextColor
        WorkspaceTouchBarStyle.applyItemChrome(
            to: layer,
            highlighted: false,
            enabled: true
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        layer?.contentsScale = scale
    }

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.72
            refreshChrome()
        }
    }

    override var isHighlighted: Bool {
        didSet { refreshChrome() }
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        refreshChrome()
    }

    override func mouseDown(with event: NSEvent) {
        // Super tracks press/release and drives highlight + action. Force chrome
        // around the call so borderless layer buttons visibly depress on TB/desktop.
        refreshChrome()
        super.mouseDown(with: event)
        refreshChrome()
    }

    func refreshChrome() {
        WorkspaceTouchBarStyle.applyItemChrome(
            to: layer,
            highlighted: isHighlighted,
            enabled: isEnabled
        )
    }

    func configureTitleChrome(title: String, toolTip: String) {
        self.title = title
        self.toolTip = toolTip
        image = nil
        imagePosition = .noImage
        setAccessibilityLabel(title.isEmpty ? "添加自定义 App" : title)
        refreshChrome()
    }
}

/// Full-slot hit target that only reports highlight (chrome lives on the parent).
@MainActor
final class WorkspaceTransparentHitButton: NSButton {
    var onHighlightChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryChange)
        title = ""
        focusRingType = .none
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var isHighlighted: Bool {
        didSet { onHighlightChange?(isHighlighted && isEnabled) }
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        onHighlightChange?(flag && isEnabled)
    }

    override func mouseDown(with event: NSEvent) {
        onHighlightChange?(isEnabled)
        super.mouseDown(with: event)
        onHighlightChange?(false)
    }
}

@MainActor
final class WorkspaceTouchBarContentView: NSView {
    private let switcherButton = WorkspaceChromeButton()
    private let trayView = NSView()
    private let pathView: NSView
    private let agentsView: NSView
    private let customView: NSView
    private let pathAgentsDivider = NSView()
    private let agentsCustomDivider = NSView()
    private let agentsPlaceholder = NSTextField(labelWithString: "")

    var onWindowAttachmentChanged: ((Bool) -> Void)?
    var onToggleWorkspace: (() -> Void)?

    init(pathView: NSView, agentsView: NSView, customView: NSView) {
        self.pathView = pathView
        self.agentsView = agentsView
        self.customView = customView
        super.init(frame: .zero)
        // Sole full-bar item: hug low so system grants available Function Row width.
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        switcherButton.image = NSImage(
            systemSymbolName: "rectangle.on.rectangle.slash",
            accessibilityDescription: "返回 Touch Bar 镜像"
        )
        switcherButton.contentTintColor = .white
        switcherButton.imageScaling = .scaleProportionallyDown
        switcherButton.imagePosition = .imageOnly
        switcherButton.target = self
        switcherButton.action = #selector(toggleWorkspace)
        switcherButton.toolTip = "点击返回 Touch Bar 镜像"
        switcherButton.setAccessibilityLabel("返回 Touch Bar 镜像")
        addSubview(switcherButton)

        trayView.wantsLayer = true
        trayView.layer?.backgroundColor =
            WorkspaceTouchBarStyle.trayBackground.cgColor
        trayView.layer?.cornerRadius = WorkspaceTouchBarStyle.trayCornerRadius
        addSubview(trayView)

        addSubview(pathView)
        addSubview(agentsView)
        addSubview(customView)
        for divider in [pathAgentsDivider, agentsCustomDivider] {
            divider.wantsLayer = true
            divider.layer?.backgroundColor = WorkspaceTouchBarStyle
                .dividerColor.cgColor
            addSubview(divider)
        }
        agentsPlaceholder.font = WorkspaceTouchBarStyle.secondaryFont
        agentsPlaceholder.textColor = WorkspaceTouchBarStyle.secondaryTextColor
        agentsPlaceholder.alignment = .center
        agentsPlaceholder.lineBreakMode = .byTruncatingTail
        agentsPlaceholder.isHidden = true
        addSubview(agentsPlaceholder)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        // Stretch to hardware width; no fixed cap (design: full strip).
        NSSize(
            width: NSView.noIntrinsicMetric,
            height: WorkspaceTouchBarStyle.controlHeight
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowAttachmentChanged?(window != nil)
    }

    func setNeedsRegionLayout() {
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 1, bounds.height > 1 else { return }

        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        trayView.layer?.contentsScale = scale
        switcherButton.layer?.contentsScale = scale

        let pathPreferred =
            (pathView as? WorkspaceTouchBarPathView)?.preferredPillWidth ?? 0
        let strip = WorkspaceTouchBarLayout.stripFrames(
            in: bounds,
            pathPreferredWidth: pathPreferred
        )
        switcherButton.frame = strip.switcher
        trayView.frame = strip.tray

        // Path plate hugs title, centered in the (scaled) path zone.
        let pathInner = WorkspaceTouchBarLayout.zoneContentRect(strip.path)
        let pathHeight = max(
            strip.tray.height - WorkspaceTouchBarLayout.slotVerticalInset * 2,
            22
        )
        let pathPlateWidth = min(
            max(pathPreferred, 1),
            pathInner.width
        )
        pathView.frame = NSRect(
            x: floor(pathInner.midX - pathPlateWidth / 2),
            y: strip.tray.midY - pathHeight / 2,
            width: pathPlateWidth,
            height: pathHeight
        )

        let agentsInner = WorkspaceTouchBarLayout.zoneContentRect(strip.agents)
        let customInner = WorkspaceTouchBarLayout.zoneContentRect(strip.custom)
        agentsView.frame = NSRect(
            x: agentsInner.minX,
            y: strip.tray.minY,
            width: agentsInner.width,
            height: strip.tray.height
        )
        customView.frame = NSRect(
            x: customInner.minX,
            y: strip.tray.minY,
            width: customInner.width,
            height: strip.tray.height
        )

        let dividerHeight: CGFloat = 18
        pathAgentsDivider.frame = NSRect(
            x: floor(
                strip.agents.minX
                    - WorkspaceTouchBarLayout.zoneDividerWidth / 2
            ),
            y: floor(strip.tray.midY - dividerHeight / 2),
            width: WorkspaceTouchBarLayout.zoneDividerWidth,
            height: dividerHeight
        )
        agentsCustomDivider.frame = NSRect(
            x: floor(
                strip.custom.minX
                    - WorkspaceTouchBarLayout.zoneDividerWidth / 2
            ),
            y: floor(strip.tray.midY - dividerHeight / 2),
            width: WorkspaceTouchBarLayout.zoneDividerWidth,
            height: dividerHeight
        )
        agentsPlaceholder.frame = agentsView.frame.insetBy(dx: 4, dy: 2)
        agentsView.needsLayout = true
        customView.needsLayout = true
        customView.layoutSubtreeIfNeeded()
    }

    func showAgentsPlaceholder(_ text: String?) {
        agentsPlaceholder.stringValue = text ?? ""
        agentsPlaceholder.isHidden = text == nil
        agentsView.isHidden = text != nil
    }

    @objc private func toggleWorkspace() {
        onToggleWorkspace?()
    }
}

/// Custom-apps zone: empty "自定义app" or icons + settings — equal slots.
@MainActor
final class WorkspaceCustomAppsView: NSView {
    private let emptyButton = WorkspaceChromeButton()
    private let settingsButton = WorkspaceChromeButton()
    private var iconButtons: [WorkspaceChromeButton] = []
    private var apps: [CustomWorkspaceApp] = []
    private var slotViews: [NSView] = []

    /// Opens app settings to manage pinned custom apps (add / replace / remove).
    var onOpenSettings: (() -> Void)?
    var onOpenCustomApp: ((CustomWorkspaceApp) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        emptyButton.configureTitleChrome(
            title: "自定义app",
            toolTip: "打开设置，管理常用应用（最多 3 个）"
        )
        emptyButton.target = self
        emptyButton.action = #selector(openSettings)
        addSubview(emptyButton)

        settingsButton.configureTitleChrome(
            title: "",
            toolTip: "打开设置，管理常用应用（最多 3 个）"
        )
        settingsButton.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "设置自定义 App"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        settingsButton.imagePosition = .imageOnly
        settingsButton.imageScaling = .scaleProportionallyDown
        settingsButton.contentTintColor = WorkspaceTouchBarStyle.primaryTextColor
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        addSubview(settingsButton)

        display(apps: WorkspacePreferences.customApps)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func display(apps: [CustomWorkspaceApp]) {
        self.apps = CustomWorkspaceAppList.normalized(apps)
        iconButtons.forEach { $0.removeFromSuperview() }
        iconButtons.removeAll()

        if self.apps.isEmpty {
            emptyButton.isHidden = false
            settingsButton.isHidden = true
            slotViews = [emptyButton]
        } else {
            emptyButton.isHidden = true
            settingsButton.isHidden = false
            var views: [NSView] = []
            for (index, app) in self.apps.enumerated() {
                let button = makeAppButton(app: app, index: index)
                addSubview(button)
                iconButtons.append(button)
                views.append(button)
            }
            views.append(settingsButton)
            slotViews = views
        }
        needsLayout = true
        superview?.needsLayout = true
    }

    /// Spread controls evenly across the custom zone (3/10 of the bar).
    /// `region` must be in this view's coordinate space (usually `bounds`).
    func layoutEqualSlots(in region: NSRect) {
        guard region.width > 1, region.height > 1, !slotViews.isEmpty else {
            return
        }
        let slots = WorkspaceTouchBarLayout.slotFrames(
            in: region,
            slotCount: slotViews.count
        )
        for (index, view) in slotViews.enumerated() where index < slots.count {
            view.frame = slots[index]
        }
    }

    override func layout() {
        super.layout()
        layoutEqualSlots(in: bounds)
    }

    private func makeAppButton(
        app: CustomWorkspaceApp,
        index: Int
    ) -> WorkspaceChromeButton {
        let button = WorkspaceChromeButton()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = WorkspaceTouchBarStyle.customAppIcon(for: app)
        button.contentTintColor = nil
        button.toolTip = "打开 \(app.displayName)"
        button.setAccessibilityLabel(app.displayName)
        button.tag = index
        button.target = self
        button.action = #selector(openCustomApp(_:))
        return button
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func openCustomApp(_ sender: NSButton) {
        guard apps.indices.contains(sender.tag) else { return }
        onOpenCustomApp?(apps[sender.tag])
    }
}

@MainActor
final class WorkspaceTouchBarPathView: NSView {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let actionButton = WorkspaceTransparentHitButton()
    private var isInteractionEnabled = true
    private var showsIcon = true
    var onActivate: (() -> Void)?

    /// Content-hugging width for the path pill (before min/max clamp in layout).
    /// Parent uses this to size the plate and optionally grow the path zone so
    /// long folder names are not truncated by a fixed 4/10 grid.
    var preferredPillWidth: CGFloat {
        let title = titleLabel.stringValue as NSString
        let font = titleLabel.font ?? WorkspaceTouchBarStyle.titleFont
        // boundingRect matches AppKit drawing more closely than size(with:)
        // for CJK / semibold system fonts on Touch Bar.
        let textWidth = ceil(
            title.boundingRect(
                with: NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: 40
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).width
        )
        let iconPart: CGFloat
        if showsIcon {
            iconPart = WorkspaceTouchBarStyle.iconWidth
                + WorkspaceTouchBarStyle.imageTitleSpacing
        } else {
            iconPart = 0
        }
        let raw = WorkspaceTouchBarStyle.horizontalPadding * 2
            + iconPart
            + textWidth
        // Extra safety so the label frame is never 1–2pt short of the glyph run
        // (which would force byTruncatingMiddle even when the zone can grow).
        return max(raw + 6, 120)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        WorkspaceTouchBarStyle.applyItemChrome(
            to: layer,
            highlighted: false,
            enabled: true
        )
        imageView.imageScaling = .scaleProportionallyDown
        imageView.contentTintColor = WorkspaceTouchBarStyle.primaryTextColor
        imageView.wantsLayer = true
        addSubview(imageView)
        titleLabel.font = WorkspaceTouchBarStyle.titleFont
        titleLabel.textColor = WorkspaceTouchBarStyle.primaryTextColor
        titleLabel.alignment = .left
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.cell?.truncatesLastVisibleLine = true
        addSubview(titleLabel)

        actionButton.target = self
        actionButton.action = #selector(activatePath)
        actionButton.toolTip = nil
        actionButton.onHighlightChange = { [weak self] highlighted in
            self?.applyPathChrome(highlighted: highlighted)
        }
        addSubview(actionButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
                bounds.width - titleX - WorkspaceTouchBarStyle.horizontalPadding,
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

    @objc private func activatePath() {
        guard isInteractionEnabled else { return }
        onActivate?()
    }

    private func applyPathChrome(highlighted: Bool) {
        WorkspaceTouchBarStyle.applyItemChrome(
            to: layer,
            highlighted: highlighted,
            enabled: isInteractionEnabled
        )
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
        showsIcon = image != nil
        imageView.isHidden = image == nil
        applyPathChrome(highlighted: false)
        needsLayout = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        actionButton.setAccessibilityLabel(title)
        // Parent three-zone layout depends on preferredPillWidth.
        superview?.needsLayout = true
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
final class WorkspaceTouchBarController: NSObject, NSTouchBarDelegate {
    private enum ItemIdentifier {
        static let content = NSTouchBarItem.Identifier(
            "com.toubarreplace.workspace.content"
        )
    }

    private let touchBar = NSTouchBar()
    private let pathView = WorkspaceTouchBarPathView()
    private let agentIconRow = AgentIconRowView()
    private let customAppsView = WorkspaceCustomAppsView()
    private lazy var contentView = WorkspaceTouchBarContentView(
        pathView: pathView,
        agentsView: agentIconRow,
        customView: customAppsView
    )
    private var agents: [AvailableAgent] = []
    private var customApps: [CustomWorkspaceApp] = []
    private var context: WorkspaceContext?
    private var previousPresentationMode: String?
    private var hadPreviousPresentationMode = false
    private var agentsEnabled = false
    private var hasAttachedToTouchBarWindow = false
    private var isExplicitlyDismissing = false
    private var detachmentTask: Task<Void, Never>?
    private(set) var isPresented = false

    var onResolvePath: (() -> Void)?
    var onAgentActivated: ((AvailableAgent) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenCustomApp: ((CustomWorkspaceApp) -> Void)?
    var onPresentationInterrupted: (() -> Void)?
    var onToggleWorkspace: (() -> Void)?

    override init() {
        super.init()
        touchBar.delegate = self
        // Single full-width item: switcher + tray (design v2). Dual items
        // left a black void because principal width stayed capped.
        touchBar.defaultItemIdentifiers = [ItemIdentifier.content]
        touchBar.principalItemIdentifier = ItemIdentifier.content
        touchBar.customizationAllowedItemIdentifiers = []

        contentView.onWindowAttachmentChanged = { [weak self] attached in
            self?.handleWindowAttachmentChanged(attached)
        }
        contentView.onToggleWorkspace = { [weak self] in
            self?.onToggleWorkspace?()
        }

        pathView.onActivate = { [weak self] in
            self?.onResolvePath?()
        }

        agentIconRow.onAgentActivated = { [weak self] agent in
            guard let self, self.agentsEnabled else { return }
            self.onAgentActivated?(agent)
        }

        customAppsView.onOpenSettings = { [weak self] in
            self?.onOpenSettings?()
        }
        customAppsView.onOpenCustomApp = { [weak self] app in
            self?.onOpenCustomApp?(app)
        }

        reloadCustomAppsFromPreferences()
        showIdle(lastPath: WorkspacePreferences.lastPath)
    }

    func reloadCustomAppsFromPreferences() {
        customApps = WorkspacePreferences.customApps
        customAppsView.display(apps: customApps)
        contentView.setNeedsRegionLayout()
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
            TouchBarPresentationPreferences.setCurrentMode(nil)
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
                title: "点击获取当前项目",
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
            title: "正在获取当前项目路径…",
            toolTip: nil,
            enabled: false
        )
        reloadAgents(enabled: false, placeholder: "正在读取项目…")
    }

    func showReady(context: WorkspaceContext, agents: [AvailableAgent]) {
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

    func showLaunching(agent: AvailableAgent, context: WorkspaceContext) {
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
        agentIconRow.setEnabled(false)
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
        guard identifier == ItemIdentifier.content else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "Workspace"
        // Height stays at Touch Bar chrome (30pt) — settings height only drives
        // the mirror window. Mixing ~35pt with the host caused AL conflicts.
        contentView.heightAnchor.constraint(
            equalToConstant: WorkspaceTouchBarStyle.controlHeight
        ).isActive = true
        // Width tracks Settings mirror points, capped to maximumContentWidth
        // (1010). Asking for the full mirror point size (~1150) overflows the
        // Function Row and clips the trailing custom slot.
        let preferredWidthValue = WorkspaceTouchBarLayout.preferredContentWidth()
        let minWidth = contentView.widthAnchor.constraint(
            greaterThanOrEqualToConstant:
                WorkspaceTouchBarLayout.minimumContentWidth
        )
        minWidth.priority = .defaultHigh
        minWidth.isActive = true
        let preferredWidth = contentView.widthAnchor.constraint(
            equalToConstant: preferredWidthValue
        )
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
        item.view = contentView
        return item
    }

    private func reloadAgents(enabled: Bool, placeholder: String? = nil) {
        agentIconRow.display(agents: agents)
        agentsEnabled = enabled && !agents.isEmpty
        agentIconRow.setEnabled(agentsEnabled)
        contentView.showAgentsPlaceholder(placeholder)
        contentView.setNeedsRegionLayout()
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
