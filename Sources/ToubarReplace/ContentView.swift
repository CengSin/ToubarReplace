import AppKit
import CoreGraphics

struct TouchBarWindowMetrics {
    // This is only the first-run size. It is intentionally not derived from
    // the captured frame: the user can resize the mirror to match their bar.
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
    private let surfaceView: TouchBarSurfaceView
    private let capture: TouchBarCapture
    private var hasRestoredFrame = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isRunning = false
    private(set) var displayPosition = TouchBarPreferences.displayPosition
    var onPixelSizeChanged: ((CGSize) -> Void)?

    init() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let initialSize = TouchBarWindowMetrics.pointSize(
            forPixelSize: TouchBarPreferences.mirrorPixelSize,
            backingScaleFactor: scale
        )
        surfaceView = TouchBarSurfaceView(
            frame: NSRect(origin: .zero, size: initialSize)
        )
        surfaceView.autoresizingMask = [.width, .height]

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
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
        panel.minSize = TouchBarWindowMetrics.minimumSize
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = surfaceView
        panel.setFrameAutosaveName("ToubarReplaceMirrorWindow")
        hasRestoredFrame = panel.setFrameUsingName(
            "ToubarReplaceMirrorWindow"
        )
        panel.setContentSize(initialSize)

        capture = TouchBarCapture(
            framesPerSecond: TouchBarPreferences.displayFramesPerSecond,
            onFrame: { [weak surfaceView] image in
                Task { @MainActor in
                    surfaceView?.display(image: image)
                }
            },
            onNotice: { [weak surfaceView] notice in
                Task { @MainActor in
                    surfaceView?.display(notice: notice)
                }
            },
            onError: { [weak surfaceView] error in
                Task { @MainActor in
                    surfaceView?.display(error: error)
                }
            }
        )

        super.init(window: panel)
        panel.delegate = self
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
        capture.start()
    }

    func stop() {
        isRunning = false
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
            forPointSize: window.contentView?.bounds.size
                ?? window.contentLayoutRect.size,
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
        let pointSize = TouchBarWindowMetrics.pointSize(
            forPixelSize: constrainedPixelSize,
            backingScaleFactor: window.screen?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
        )
        window.setContentSize(pointSize)
        persistCurrentPixelSize()
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
        let origin: NSPoint
        switch displayPosition {
        case .bottom:
            origin = NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: screen.frame.minY
            )
        case .top:
            origin = NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.maxY - frame.height - 18
            )
        case .center:
            origin = NSPoint(
                x: visibleFrame.midX - frame.width / 2,
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
    }

}
