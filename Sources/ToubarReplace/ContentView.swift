import AppKit
import CoreGraphics
import Foundation

struct TouchBarWindowMetrics {
    static let defaultSize = CGSize(width: 1_150, height: 35)
    static let minimumSize = CGSize(width: 240, height: 18)

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

    /// Root panel size equals the mirror viewport (no attached switcher rail).
    static func rootSize(forMirrorSize mirrorSize: CGSize) -> CGSize {
        CGSize(
            width: max(mirrorSize.width, 1),
            height: max(mirrorSize.height, 1)
        )
    }
}

enum TouchBarIdleOpacity {
    static let active: CGFloat = 1
    static let idle: CGFloat = 0.3
    static let minimumDelaySeconds = 1
    static let defaultDelaySeconds = 5
    static let maximumDelaySeconds = 300
    static let delay: Duration = .seconds(defaultDelaySeconds)
    /// How often to re-check whether the mirror covers other app content.
    static let occlusionPollInterval: Duration = .milliseconds(750)
    /// Minimum overlapping area (points²) to count as obscuring content.
    static let minimumOverlapArea: CGFloat = 80

    static func clampedDelaySeconds(_ seconds: Int) -> Int {
        min(max(seconds, minimumDelaySeconds), maximumDelaySeconds)
    }

    static func shouldPollOcclusion(isIdle: Bool) -> Bool {
        isIdle
    }

    static func targetAlpha(
        isIdle: Bool,
        isObscuringOtherAppContent: Bool
    ) -> CGFloat {
        isIdle && isObscuringOtherAppContent ? idle : active
    }
}

/// One on-screen window entry for occlusion tests (Cocoa coordinates).
struct MirrorOcclusionWindowInfo: Equatable {
    var windowNumber: Int
    var ownerPID: pid_t
    var layer: Int
    var bounds: CGRect
    var ownerName: String?
    var bundleIdentifier: String?
}

/// Gates delayed idle transparency: only while the mirror floats over other apps' content.
/// Over empty desktop / wallpaper only → stay fully opaque.
enum MirrorWindowOcclusion {
    /// System UI that should not trigger idle fade when under the mirror.
    static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        "com.apple.Spotlight",
        "com.apple.TextInputUI.xpc.CursorUIViewService",
    ]

    static let excludedOwnerNames: Set<String> = [
        "Dock",
        "Control Center",
        "Notification Centre",
        "Notification Center",
        "SystemUIServer",
        "Window Server",
        "WindowManager",
        "Wallpaper",
    ]

    /// Convert `CGWindowList` bounds (Quartz, top-left origin) to Cocoa (bottom-left).
    static func cocoaRect(
        fromCGWindowBounds cgRect: CGRect,
        mainDisplayHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: cgRect.origin.x,
            y: mainDisplayHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, !intersection.isInfinite else { return 0 }
        return max(0, intersection.width) * max(0, intersection.height)
    }

    /// Pure helper: whether a candidate window under the mirror counts as "app content".
    static func isObscurableContentWindow(
        ownerPID: pid_t,
        selfPID: pid_t,
        layer: Int,
        bundleIdentifier: String?,
        ownerName: String?
    ) -> Bool {
        guard ownerPID != selfPID else { return false }
        // Desktop wallpaper / icons sit on negative layers; skip them.
        guard layer >= 0 else { return false }
        // Menubar / overlays sit well above normal app content (layer 0).
        // Keep a generous band so Chromium / Electron helpers still count.
        guard layer <= 25 else { return false }

        if let bundleIdentifier, excludedBundleIdentifiers.contains(bundleIdentifier) {
            return false
        }
        if let ownerName, excludedOwnerNames.contains(ownerName) {
            return false
        }
        return true
    }

    /// `windowsFrontToBack` must be ordered front → back (CGWindowList default).
    static func isObscuringOtherAppContent(
        mirrorWindowNumber: Int,
        mirrorBounds: CGRect,
        selfPID: pid_t,
        windowsFrontToBack: [MirrorOcclusionWindowInfo],
        minimumOverlapArea: CGFloat = TouchBarIdleOpacity.minimumOverlapArea
    ) -> Bool {
        guard mirrorBounds.width > 1, mirrorBounds.height > 1 else { return false }

        let mirrorIndex = windowsFrontToBack.firstIndex {
            $0.windowNumber == mirrorWindowNumber
        }

        // Windows strictly behind the mirror in z-order; if the mirror is missing
        // from the list (transient), still scan every other candidate.
        let behind: ArraySlice<MirrorOcclusionWindowInfo>
        if let mirrorIndex {
            behind = windowsFrontToBack[(mirrorIndex + 1)...]
        } else {
            behind = windowsFrontToBack[...]
        }

        for window in behind {
            if window.windowNumber == mirrorWindowNumber { continue }
            guard isObscurableContentWindow(
                ownerPID: window.ownerPID,
                selfPID: selfPID,
                layer: window.layer,
                bundleIdentifier: window.bundleIdentifier,
                ownerName: window.ownerName
            ) else {
                continue
            }
            if overlapArea(mirrorBounds, window.bounds) >= minimumOverlapArea {
                return true
            }
        }
        return false
    }

    /// Live check for the mirror `NSWindow`.
    @MainActor
    static func isObscuringOtherAppContent(mirrorWindow: NSWindow) -> Bool {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let mirrorNumber = mirrorWindow.windowNumber
        let mirrorBounds = mirrorWindow.frame
        let windows = snapshotOnScreenWindows()
        return isObscuringOtherAppContent(
            mirrorWindowNumber: mirrorNumber,
            mirrorBounds: mirrorBounds,
            selfPID: selfPID,
            windowsFrontToBack: windows
        )
    }

    private static func snapshotOnScreenWindows() -> [MirrorOcclusionWindowInfo] {
        let options = CGWindowListOption(
            arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements
        )
        guard
            let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else {
            return []
        }

        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        var bundleByPID: [pid_t: String] = [:]

        func bundleID(for pid: pid_t) -> String? {
            if let cached = bundleByPID[pid] { return cached }
            let value = NSRunningApplication(processIdentifier: pid)?
                .bundleIdentifier
            if let value {
                bundleByPID[pid] = value
            }
            return value
        }

        var result: [MirrorOcclusionWindowInfo] = []
        result.reserveCapacity(infoList.count)
        for info in infoList {
            guard
                let number = info[kCGWindowNumber as String] as? Int,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let cgBounds = CGRect(dictionaryRepresentation: boundsDict)
            else {
                continue
            }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let ownerName = info[kCGWindowOwnerName as String] as? String
            let cocoaBounds = cocoaRect(
                fromCGWindowBounds: cgBounds,
                mainDisplayHeight: mainDisplayHeight
            )
            result.append(
                MirrorOcclusionWindowInfo(
                    windowNumber: number,
                    ownerPID: ownerPID,
                    layer: layer,
                    bounds: cocoaBounds,
                    ownerName: ownerName,
                    bundleIdentifier: bundleID(for: ownerPID)
                )
            )
        }
        return result
    }
}

/// Mirror-window cover used while physical Touch Bar modals swap.
/// Freezes the last captured frame, then fades out after a short settle.
enum MirrorSceneTransition {
    /// Keep the cover opaque while system modal + capture settle.
    static let settleDuration: Duration = .milliseconds(221)
    /// Fade-out of the frozen frame overlay.
    static let fadeDuration: TimeInterval = 0.12
}

enum WorkspaceAsyncSessionPolicy {
    static func canUpdate(
        capturedGeneration: UInt64,
        currentGeneration: UInt64,
        scene: BarScene
    ) -> Bool {
        capturedGeneration == currentGeneration && scene == .workspace
    }
}

@MainActor
final class TouchBarIdleOpacityController {
    private weak var window: NSWindow?
    private let clock = ContinuousClock()
    private var idleMonitorTask: Task<Void, Never>?
    private var occlusionPollTask: Task<Void, Never>?
    private var occlusionObservers: [NSObjectProtocol] = []
    private var lastFrameActivityAt: ContinuousClock.Instant?
    private var isIdle = false
    private var idleDelay: Duration

    init(
        window: NSWindow,
        idleDelaySeconds: Int = TouchBarPreferences.idleOpacityDelaySeconds
    ) {
        self.window = window
        self.idleDelay = .seconds(
            TouchBarIdleOpacity.clampedDelaySeconds(idleDelaySeconds)
        )
    }

    func start() {
        installOcclusionObservers()
        registerFrameActivity()
    }

    func stop() {
        removeOcclusionObservers()
        idleMonitorTask?.cancel()
        idleMonitorTask = nil
        occlusionPollTask?.cancel()
        occlusionPollTask = nil
        lastFrameActivityAt = nil
        isIdle = false
        window?.alphaValue = TouchBarIdleOpacity.active
    }

    func registerFrameActivity() {
        lastFrameActivityAt = clock.now
        isIdle = false
        occlusionPollTask?.cancel()
        occlusionPollTask = nil
        if window?.alphaValue != TouchBarIdleOpacity.active {
            window?.alphaValue = TouchBarIdleOpacity.active
        }
        startIdleMonitorIfNeeded()
    }

    func setIdleDelaySeconds(_ seconds: Int) {
        idleDelay = .seconds(
            TouchBarIdleOpacity.clampedDelaySeconds(seconds)
        )
        guard lastFrameActivityAt != nil else { return }

        // Re-evaluate from the latest real frame so this setting takes effect
        // immediately without counting the settings interaction as activity.
        idleMonitorTask?.cancel()
        idleMonitorTask = nil
        occlusionPollTask?.cancel()
        occlusionPollTask = nil
        isIdle = false
        window?.alphaValue = TouchBarIdleOpacity.active
        startIdleMonitorIfNeeded()
    }

    /// One monitor follows the latest activity deadline. Frames only update the
    /// timestamp; they do not allocate and cancel a new sleeping task.
    private func startIdleMonitorIfNeeded() {
        guard idleMonitorTask == nil else { return }
        idleMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let observedActivity = self.lastFrameActivityAt else {
                    self.idleMonitorTask = nil
                    return
                }
                do {
                    try await self.clock.sleep(
                        until: observedActivity.advanced(
                            by: self.idleDelay
                        )
                    )
                } catch {
                    return
                }
                guard self.lastFrameActivityAt == observedActivity else {
                    continue
                }
                self.idleMonitorTask = nil
                self.enterIdleState()
                return
            }
        }
    }

    private func enterIdleState() {
        isIdle = true
        refreshOcclusionWhileIdle()
        startIdleOcclusionPolling()
    }

    private func installOcclusionObservers() {
        removeOcclusionObservers()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let notificationCenter = NotificationCenter.default
        occlusionObservers = [
            workspaceCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshOcclusionWhileIdle()
                }
            },
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshOcclusionWhileIdle()
                }
            },
            notificationCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshOcclusionWhileIdle()
                }
            },
        ]
        if let window {
            occlusionObservers.append(
                notificationCenter.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshOcclusionWhileIdle()
                    }
                }
            )
            occlusionObservers.append(
                notificationCenter.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshOcclusionWhileIdle()
                    }
                }
            )
        }
    }

    private func startIdleOcclusionPolling() {
        guard
            TouchBarIdleOpacity.shouldPollOcclusion(isIdle: isIdle),
            occlusionPollTask == nil
        else {
            return
        }
        occlusionPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: TouchBarIdleOpacity.occlusionPollInterval)
                guard !Task.isCancelled else { return }
                guard let self, self.isIdle else { return }
                self.refreshOcclusionWhileIdle()
            }
        }
    }

    private func removeOcclusionObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let notificationCenter = NotificationCenter.default
        for observer in occlusionObservers {
            workspaceCenter.removeObserver(observer)
            notificationCenter.removeObserver(observer)
        }
        occlusionObservers.removeAll()
        occlusionPollTask?.cancel()
        occlusionPollTask = nil
    }

    private func refreshOcclusionWhileIdle() {
        guard isIdle else { return }
        guard let window else { return }
        let isObscuring = MirrorWindowOcclusion.isObscuringOtherAppContent(
            mirrorWindow: window
        )
        let targetAlpha = TouchBarIdleOpacity.targetAlpha(
            isIdle: isIdle,
            isObscuringOtherAppContent: isObscuring
        )
        if window.alphaValue != targetAlpha {
            window.alphaValue = targetAlpha
        }
    }
}

/// Bounds queued UI work when the main actor is temporarily busy. The display
/// stream can replace `latestImage`, but at most one delivery task is pending.
final class TouchBarFrameDeliveryCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private let onFrame: @MainActor @Sendable (CGImage) -> Void
    private var latestImage: CGImage?
    private var isDeliveryScheduled = false

    @MainActor
    init(onFrame: @escaping @MainActor @Sendable (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func submit(_ image: CGImage) {
        lock.lock()
        latestImage = image
        guard !isDeliveryScheduled else {
            lock.unlock()
            return
        }
        isDeliveryScheduled = true
        lock.unlock()

        Task { @MainActor [weak self] in
            self?.deliverLatest()
        }
    }

    @MainActor
    private func deliverLatest() {
        lock.lock()
        let image = latestImage
        latestImage = nil
        isDeliveryScheduled = false
        lock.unlock()

        guard let image else { return }
        onFrame(image)
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

    /// Placeholder when there is no physical Touch Bar (software Workspace mode).
    func displaySoftwareWorkspaceIdle() {
        imageView.layer?.contents = nil
        imageView.isHidden = true
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.stringValue = """
        当前 Mac 无物理 Touch Bar
        点击切换按钮打开 Workspace，选择路径并启动 Agent
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
    private var resumeToWorkspace = false
    private var isRunning = false
    private var lastFrontmostContext: FrontmostAppContext?
    private var currentWorkspaceContext: WorkspaceContext?
    private var availableAgents: [AvailableAgent] = []
    private var isAgentLaunchInProgress = false
    private var workspaceGeneration: UInt64 = 0
    private var agentLaunchTask: Task<Void, Never>?
    private var autoCollapseTask: Task<Void, Never>?
    private var lastLaunchSignature: (AgentID, String, Date)?
    private(set) var displayPosition = TouchBarPreferences.displayPosition
    var onPixelSizeChanged: ((CGSize) -> Void)?
    var onCustomTopLeftChanged: ((CGPoint) -> Void)?
    var onRequestWorkspaceDirectory: (
        (@escaping (URL?) -> Void) -> Void
    )?
    /// Opens the settings window (custom apps are managed there).
    var onOpenSettings: (() -> Void)?

    init() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let initialMirrorSize = TouchBarWindowMetrics.pointSize(
            forPixelSize: TouchBarPreferences.mirrorPixelSize,
            backingScaleFactor: scale
        )
        // Switcher is either physical Touch Bar or floating window (no attached rail).
        let initialRootSize = TouchBarWindowMetrics.rootSize(
            forMirrorSize: initialMirrorSize
        )
        rootView = TouchBarRootView(
            frame: NSRect(origin: .zero, size: initialRootSize)
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
        // Pure display: mouse events pass through to apps behind the mirror.
        // Reposition via settings (display position / custom coordinates), not drag.
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = TouchBarWindowMetrics.rootSize(
            forMirrorSize: TouchBarWindowMetrics.minimumSize
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

        let idleOpacityController = TouchBarIdleOpacityController(window: panel)
        self.idleOpacityController = idleOpacityController
        let frameDelivery = TouchBarFrameDeliveryCoalescer {
            [weak rootView, weak idleOpacityController] image in
            rootView?.surfaceView.display(image: image)
            idleOpacityController?.registerFrameActivity()
        }
        capture = TouchBarCapture(
            framesPerSecond: TouchBarPreferences.displayFramesPerSecond,
            onFrame: { image in
                frameDelivery.submit(image)
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
        configureFloatingWorkspaceSwitcher()
        showFloatingWorkspaceSwitcherIfNeeded()
        idleOpacityController.start()

        let enterWorkspace =
            SoftwareWorkspaceLaunchPolicy.shouldEnterWorkspaceAtLaunch(
                usesSoftwareWorkspace: usesSoftwareWorkspace,
                preferredScene: WorkspacePreferences.startupScene
            )
        if SoftwareWorkspaceLaunchPolicy.shouldStartHardwareCapture(
            usesSoftwareWorkspace: usesSoftwareWorkspace
        ) {
            capture.start()
        }
        if enterWorkspace {
            if usesSoftwareWorkspace {
                enterSoftwareWorkspace(isLaunch: true)
            } else {
                enterHardwareWorkspace(isLaunch: true)
            }
        } else {
            if usesSoftwareWorkspace {
                rootView.surfaceView.displaySoftwareWorkspaceIdle()
            }
            presentPhysicalSwitcherIfNeeded()
            updateMirrorClickThrough()
        }
    }

    func stop() {
        isRunning = false
        finderSyncTask?.cancel()
        finderSyncTask = nil
        cancelWorkspaceAsyncWork(invalidateSession: true)
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
                        forMirrorSize: mirrorPointSize
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

    var idleOpacityDelaySeconds: Int {
        TouchBarPreferences.idleOpacityDelaySeconds
    }

    func setIdleOpacityDelaySeconds(_ seconds: Int) {
        let clamped = TouchBarIdleOpacity.clampedDelaySeconds(seconds)
        TouchBarPreferences.idleOpacityDelaySeconds = clamped
        idleOpacityController.setIdleDelaySeconds(clamped)
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
            TouchBarWindowMetrics.rootSize(forMirrorSize: mirrorPointSize)
        )
        setWindowOriginPreservingMirrorX(mirrorOriginX)
        persistCurrentPixelSize()
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
        // Software mode cannot host a physical switcher; force floating without
        // fighting the user on every open — still allow storing .floating.
        let modeToStore: WorkspaceSwitcherDisplayMode
        if usesSoftwareWorkspace {
            modeToStore = .floating
        } else {
            modeToStore = mode
        }
        if modeToStore != WorkspacePreferences.switcherDisplayMode {
            WorkspacePreferences.switcherDisplayMode = modeToStore
        }
        configureFloatingWorkspaceSwitcher()
        showFloatingWorkspaceSwitcherIfNeeded()
        if effectiveSwitcherDisplayMode == .floating {
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

    var workspaceStartupScene: WorkspaceStartupScene {
        WorkspacePreferences.startupScene
    }

    func setWorkspaceStartupScene(_ scene: WorkspaceStartupScene) {
        WorkspacePreferences.startupScene = scene
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
            forMirrorSize: mirrorPointSize
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
        rootView.workspaceView.onSelectRecentProject = { [weak self] url in
            self?.selectRecentProject(url)
        }
        rootView.workspaceView.onBrowseWorkspaceDirectory = { [weak self] in
            self?.browseWorkspaceDirectory()
        }
        rootView.workspaceView.onCancelPathPicker = { [weak self] in
            self?.cancelWorkspacePathPicker()
        }
        rootView.workspaceView.onAgentActivated = { [weak self] agent in
            self?.launch(agent)
        }
        rootView.workspaceView.onOpenSettings = { [weak self] in
            self?.onOpenSettings?()
        }
        rootView.workspaceView.onOpenCustomApp = { [weak self] app in
            self?.openCustomWorkspaceApp(app)
        }
        workspaceTouchBarController.onResolvePath = { [weak self] in
            self?.chooseWorkspacePath()
        }
        workspaceTouchBarController.onSelectRecentProject = { [weak self] url in
            self?.selectRecentProject(url)
        }
        workspaceTouchBarController.onBrowseWorkspaceDirectory = { [weak self] in
            self?.browseWorkspaceDirectory()
        }
        workspaceTouchBarController.onCancelPathPicker = { [weak self] in
            self?.cancelWorkspacePathPicker()
        }
        workspaceTouchBarController.onAgentActivated = { [weak self] agent in
            self?.launch(agent)
        }
        workspaceTouchBarController.onOpenSettings = { [weak self] in
            self?.onOpenSettings?()
        }
        workspaceTouchBarController.onOpenCustomApp = { [weak self] app in
            self?.openCustomWorkspaceApp(app)
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

    private var usesSoftwareWorkspace: Bool {
        TouchBarHardwareCapability.usesSoftwareWorkspace
    }

    private var effectiveSwitcherDisplayMode: WorkspaceSwitcherDisplayMode {
        SoftwareWorkspaceLaunchPolicy.effectiveSwitcherDisplayMode(
            usesSoftwareWorkspace: usesSoftwareWorkspace,
            preferred: WorkspacePreferences.switcherDisplayMode
        )
    }

    private func updateMirrorClickThrough() {
        window?.ignoresMouseEvents = MirrorClickThroughPolicy.ignoresMouseEvents(
            usesSoftwareWorkspace: usesSoftwareWorkspace,
            scene: rootView.scene,
            showsWorkspaceFallback: rootView.showsWorkspaceFallback
        )
    }

    private func configureFloatingWorkspaceSwitcher() {
        guard effectiveSwitcherDisplayMode == .floating else {
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
            effectiveSwitcherDisplayMode == .floating,
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
        guard !usesSoftwareWorkspace else {
            switcherTouchBarController.dismiss()
            return
        }
        guard effectiveSwitcherDisplayMode == .touchBar else {
            switcherTouchBarController.dismiss()
            return
        }
        switcherTouchBarController.present()
    }

    /// Software path: Workspace lives on the desktop mirror (clickable tray).
    private func enterSoftwareWorkspace(isLaunch: Bool) {
        beginWorkspaceSession()
        if !isLaunch {
            rootView.beginSceneTransitionCover()
        }
        if lastFrontmostContext == nil {
            lastFrontmostContext = FrontmostAppContext.capture()
        }
        currentWorkspaceContext = nil
        availableAgents = []
        rootView.setScene(.workspace)
        workspaceSwitcherWindowController?.switcherView.setScene(.workspace)
        idleOpacityController.registerFrameActivity()
        switcherTouchBarController.dismiss()
        rootView.setWorkspaceFallbackVisible(true)
        updateMirrorClickThrough()

        applyInitialWorkspacePath()
        if !isLaunch {
            rootView.scheduleSceneTransitionCoverFade()
        }
    }

    private func toggleWorkspace() {
        switch rootView.scene {
        case .mirror:
            if usesSoftwareWorkspace {
                enterSoftwareWorkspace(isLaunch: false)
                return
            }
            enterHardwareWorkspace(isLaunch: false)
        case .workspace:
            closeWorkspace()
        }
    }

    private func enterHardwareWorkspace(isLaunch: Bool) {
        beginWorkspaceSession()
        if !isLaunch {
            rootView.beginSceneTransitionCover()
        }
        if lastFrontmostContext == nil {
            lastFrontmostContext = FrontmostAppContext.capture()
        }
        currentWorkspaceContext = nil
        availableAgents = []
        rootView.setScene(.workspace)
        workspaceSwitcherWindowController?.switcherView.setScene(.workspace)
        idleOpacityController.registerFrameActivity()
        switcherTouchBarController.dismiss()

        do {
            try workspaceTouchBarController.present()
            rootView.setWorkspaceFallbackVisible(false)
            updateMirrorClickThrough()
        } catch {
            rootView.workspaceView.showFailure(
                error.localizedDescription,
                context: nil,
                agents: []
            )
            rootView.setWorkspaceFallbackVisible(true)
            updateMirrorClickThrough()
            presentPhysicalSwitcherIfNeeded()
            if !isLaunch {
                rootView.scheduleSceneTransitionCoverFade()
            }
            return
        }

        applyInitialWorkspacePath()
        if !isLaunch {
            rootView.scheduleSceneTransitionCoverFade()
        }
    }

    private func applyInitialWorkspacePath() {
        let frontmostContext = lastFrontmostContext
            ?? FrontmostAppContext.capture()
        lastFrontmostContext = frontmostContext
        if let context = workspacePathResolver.resolveFrontmostPath(
            from: frontmostContext
        ) {
            acceptWorkspaceContext(context)
            return
        }
        if let recentContext = workspacePathResolver.recentContext(
            frontmostApplication: frontmostContext
        ) {
            acceptWorkspaceContext(recentContext)
            return
        }
        rootView.workspaceView.showIdle(
            lastPath: WorkspacePreferences.lastPath
        )
        workspaceTouchBarController.showIdle(
            lastPath: WorkspacePreferences.lastPath
        )
    }

    private func closeWorkspace() {
        cancelWorkspaceAsyncWork(invalidateSession: true)
        rootView.beginSceneTransitionCover()
        finderSyncTask?.cancel()
        finderSyncTask = nil
        if !usesSoftwareWorkspace {
            workspaceTouchBarController.dismiss()
        }
        rootView.setWorkspaceFallbackVisible(false)
        rootView.setScene(.mirror)
        workspaceSwitcherWindowController?.switcherView.setScene(.mirror)
        idleOpacityController.registerFrameActivity()
        lastFrontmostContext = nil
        if usesSoftwareWorkspace {
            rootView.surfaceView.displaySoftwareWorkspaceIdle()
        } else {
            presentPhysicalSwitcherIfNeeded()
        }
        updateMirrorClickThrough()
        rootView.scheduleSceneTransitionCoverFade()
    }

    private func handleWorkspacePresentationInterrupted() {
        guard rootView.scene == .workspace else { return }
        // Software mode never presents a system modal; ignore hardware interrupts.
        guard !usesSoftwareWorkspace else { return }
        cancelWorkspaceAsyncWork(invalidateSession: true)
        rootView.beginSceneTransitionCover()
        finderSyncTask?.cancel()
        finderSyncTask = nil
        rootView.setWorkspaceFallbackVisible(false)
        rootView.setScene(.mirror)
        workspaceSwitcherWindowController?.switcherView.setScene(.mirror)
        idleOpacityController.registerFrameActivity()
        lastFrontmostContext = nil
        presentPhysicalSwitcherIfNeeded()
        updateMirrorClickThrough()
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
        let recents = recentProjectURLsForDisplay()
        if recents.isEmpty {
            requestWorkspaceDirectory(frontmostContext: frontmostContext)
            return
        }
        rootView.workspaceView.showRecents(recents)
        workspaceTouchBarController.showRecents(recents)
    }

    private func selectRecentProject(_ directoryURL: URL) {
        let frontmostContext = lastFrontmostContext
            ?? FrontmostAppContext.capture()
        guard
            let context = workspacePathResolver.manualContext(
                directoryURL: directoryURL,
                frontmostApplication: frontmostContext
            )
        else {
            chooseWorkspacePath()
            return
        }
        acceptWorkspaceContext(
            WorkspaceContext(
                directoryURL: context.directoryURL,
                source: .recent,
                frontmostApplication: frontmostContext
            )
        )
    }

    private func browseWorkspaceDirectory() {
        requestWorkspaceDirectory(
            frontmostContext: lastFrontmostContext
                ?? FrontmostAppContext.capture()
        )
    }

    private func cancelWorkspacePathPicker() {
        if let context = currentWorkspaceContext {
            rootView.workspaceView.showReady(
                context: context,
                agents: availableAgents
            )
            workspaceTouchBarController.showReady(
                context: context,
                agents: availableAgents
            )
            return
        }
        rootView.workspaceView.showIdle(lastPath: WorkspacePreferences.lastPath)
        workspaceTouchBarController.showIdle(
            lastPath: WorkspacePreferences.lastPath
        )
    }

    private func recentProjectURLsForDisplay() -> [URL] {
        WorkspaceRecentProjectList.displayURLs(
            stored: WorkspacePreferences.recentProjects,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            existingDirectory: WorkspacePathResolver.existingDirectory(at:)
        )
    }

    func reloadCustomAppsFromPreferences() {
        rootView.workspaceView.reloadCustomAppsFromPreferences()
        workspaceTouchBarController.reloadCustomAppsFromPreferences()
    }

    private func openCustomWorkspaceApp(_ app: CustomWorkspaceApp) {
        let generation = workspaceGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await CustomWorkspaceAppLauncher.open(app)
            } catch {
                guard self.canUpdateWorkspace(from: generation) else { return }
                // Soft failure: path / agent messaging surfaces stay usable.
                self.rootView.workspaceView.showFailure(
                    error.localizedDescription,
                    context: self.currentWorkspaceContext,
                    agents: self.availableAgents
                )
                self.workspaceTouchBarController.showFailure(
                    error.localizedDescription,
                    context: self.currentWorkspaceContext,
                    agents: self.availableAgents
                )
            }
        }
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

    @discardableResult
    private func beginWorkspaceSession() -> UInt64 {
        cancelWorkspaceAsyncWork(invalidateSession: false)
        workspaceGeneration &+= 1
        return workspaceGeneration
    }

    private func cancelWorkspaceAsyncWork(invalidateSession: Bool) {
        agentLaunchTask?.cancel()
        agentLaunchTask = nil
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
        isAgentLaunchInProgress = false
        if invalidateSession {
            workspaceGeneration &+= 1
        }
    }

    private func canUpdateWorkspace(from generation: UInt64) -> Bool {
        WorkspaceAsyncSessionPolicy.canUpdate(
            capturedGeneration: generation,
            currentGeneration: workspaceGeneration,
            scene: rootView.scene
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
        let generation = workspaceGeneration
        agentLaunchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.canUpdateWorkspace(from: generation) {
                    self.isAgentLaunchInProgress = false
                    self.agentLaunchTask = nil
                }
            }
            do {
                try Task.checkCancellation()
                try await self.agentLauncher.launch(
                    agent,
                    at: context.directoryURL
                )
                try Task.checkCancellation()
                guard self.canUpdateWorkspace(from: generation) else { return }
                self.rootView.workspaceView.showReady(
                    context: context,
                    agents: self.availableAgents
                )
                self.workspaceTouchBarController.showReady(
                    context: context,
                    agents: self.availableAgents
                )
                guard WorkspacePreferences.autoCollapse else { return }
                self.autoCollapseTask?.cancel()
                self.autoCollapseTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                    } catch {
                        return
                    }
                    guard
                        let self,
                        self.canUpdateWorkspace(from: generation)
                    else {
                        return
                    }
                    self.autoCollapseTask = nil
                    self.closeWorkspace()
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.canUpdateWorkspace(from: generation) else { return }
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
                        guard let self, self.isRunning else { return }
                        self.resumeToWorkspace = self.rootView.scene == .workspace
                        if self.rootView.scene == .workspace {
                            self.closeWorkspace()
                        }
                        self.switcherTouchBarController.dismiss()
                        self.capture.stop()
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
                        guard let self, self.isRunning else { return }
                        switch TouchBarResumePolicy.action(
                            usesSoftwareWorkspace: self.usesSoftwareWorkspace,
                            restoreWorkspace: self.resumeToWorkspace
                        ) {
                        case .restoreSoftwareWorkspace:
                            if self.rootView.scene != .workspace {
                                self.enterSoftwareWorkspace(isLaunch: true)
                            }
                        case .restartHardwareCapture:
                            self.capture.restart()
                            self.presentPhysicalSwitcherIfNeeded()
                        case .restoreHardwareWorkspace:
                            self.capture.restart()
                            if self.rootView.scene != .workspace {
                                self.enterHardwareWorkspace(isLaunch: true)
                            }
                        }
                        self.resumeToWorkspace = false
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
                            || activatedBundleIdentifier
                                == FrontmostAppContext.ottyBundleIdentifier
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
                guard frontmostContext.isFinder || frontmostContext.isOtty else {
                    return
                }
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
