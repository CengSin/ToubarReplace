import CoreGraphics
import CoreImage
import Foundation
import IOSurface
import OSLog
import TouchBarPrivateAPI

enum ToubarReplaceAppInfo {
    static var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "开发版"
    }
    static let recoveryCommands = """
    defaults delete com.apple.controlstrip FullCustomized
    defaults delete com.apple.controlstrip MiniCustomized
    killall ControlStrip
    """
}

enum TouchBarCaptureError: LocalizedError, Equatable {
    case streamUnavailable
    case streamStartFailed(Int32)
    case invalidSurface
    case controlStripEmpty
    case blackFrame
    case streamStopped
    case streamStartupTimedOut

    var errorDescription: String? {
        switch self {
        case .streamUnavailable:
            return "无法创建 Touch Bar 显示流；当前 macOS 可能已不支持此接口"
        case let .streamStartFailed(code):
            return "Touch Bar 显示流启动失败（错误码 \(code)）"
        case .invalidSurface:
            return "TouchBarServer 返回了无效画面"
        case .controlStripEmpty:
            return "Control Strip 没有任何按钮；请先在系统设置中恢复默认布局"
        case .blackFrame:
            return "TouchBarServer 只返回黑画面；请重启 ControlStrip 和 TouchBarServer"
        case .streamStopped:
            return "Touch Bar 显示流已中断，正在自动重连…"
        case .streamStartupTimedOut:
            return "Touch Bar 显示流启动后没有返回画面，正在自动重连…"
        }
    }
}

enum TouchBarCaptureNotice: Equatable {
    case contextualContentUnavailable

    var description: String {
        switch self {
        case .contextualContentUnavailable:
            return """
            当前触控栏模式暂时没有可显示的内容
            切换到支持触控栏的 App，或启用一个快速操作后会自动恢复
            """
        }
    }
}

enum TouchBarSystemState {
    private static let contextualPresentationModes: Set<String> = [
        "app",
        "appWithControlStrip",
        "quickActions",
        "quickActionsWithControlStrip",
        "workflows",
        "workflowsWithControlStrip",
    ]

    static func isControlStripExplicitlyEmpty(
        fullCustomized: [Any]?,
        miniCustomized: [Any]?
    ) -> Bool {
        guard let fullCustomized, let miniCustomized else {
            return false
        }
        return fullCustomized.isEmpty && miniCustomized.isEmpty
    }

    static var isControlStripExplicitlyEmpty: Bool {
        let defaults = UserDefaults(suiteName: "com.apple.controlstrip")
        return isControlStripExplicitlyEmpty(
            fullCustomized: defaults?.array(forKey: "FullCustomized"),
            miniCustomized: defaults?.array(forKey: "MiniCustomized")
        )
    }

    static func allowsEmptyContent(presentationMode: String?) -> Bool {
        guard let presentationMode else { return false }
        return contextualPresentationModes.contains(presentationMode)
    }

    static var presentationMode: String? {
        UserDefaults(suiteName: "com.apple.touchbar.agent")?
            .string(forKey: "PresentationModeGlobal")
    }
}

/// Mirrors the IOSurface frames produced by the private Touch Bar display
/// stream. A single stream stays alive for the lifetime of the mirror; unlike
/// `screencapture -b`, this does not launch a process or allocate a screenshot
/// surface for every refresh.
final class TouchBarCapture: @unchecked Sendable {
    typealias FrameHandler = @Sendable (CGImage) -> Void
    typealias NoticeHandler = @Sendable (TouchBarCaptureNotice) -> Void
    typealias ErrorHandler = @Sendable (TouchBarCaptureError) -> Void

    static let minimumFramesPerSecond = 1
    static let maximumFramesPerSecond = 30
    static let defaultFramesPerSecond = 30
    private static let minimumBlankFrameCount = 2
    private static let minimumBlankFrameDuration: UInt64 = 500_000_000
    private static let streamStartupTimeout: DispatchTimeInterval = .seconds(5)
    private static let logger = Logger(
        subsystem: "com.toubarreplace.app",
        category: "TouchBarDisplayStream"
    )

    private let workerQueue = DispatchQueue(
        label: "com.toubarreplace.display-stream",
        qos: .userInteractive
    )
    private let imageContext = CIContext(options: [
        .cacheIntermediates: false,
    ])
    private let onFrame: FrameHandler
    private let onNotice: NoticeHandler
    private let onError: ErrorHandler
    private var frameIntervalNanoseconds: UInt64
    private var lastDeliveredAt: UInt64 = 0
    private var pendingFrame: CGImage?
    private var pendingFrameDeliveryScheduled = false
    private var pendingFrameDeliveryToken: UInt64 = 0
    private var stream: CGDisplayStream?
    private var stopped = true
    private var generation: UInt64 = 0
    private var initialTouchBarStatus: Int32?
    private var lastError: TouchBarCaptureError?
    private var lastNotice: TouchBarCaptureNotice?
    private var consecutiveBlackFrames = 0
    private var firstBlankFrameAt: UInt64?
    private var hasReceivedStreamActivity = false
    private var hasLoggedFirstFrame = false

    init(
        framesPerSecond: Int = TouchBarCapture.defaultFramesPerSecond,
        onFrame: @escaping FrameHandler,
        onNotice: @escaping NoticeHandler,
        onError: @escaping ErrorHandler
    ) {
        self.frameIntervalNanoseconds = Self.frameInterval(
            framesPerSecond: framesPerSecond
        )
        self.onFrame = onFrame
        self.onNotice = onNotice
        self.onError = onError
    }

    func start() {
        workerQueue.async { [weak self] in
            guard let self, self.stopped else { return }
            self.stopped = false
            self.generation &+= 1
            self.lastError = nil
            self.lastNotice = nil
            self.startStream(generation: self.generation)
        }
    }

    func stop() {
        workerQueue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.generation &+= 1
            self.stopStream(restoreTouchBarStatus: true)
        }
    }

    func restart() {
        workerQueue.async { [weak self] in
            guard let self else { return }
            self.stopped = false
            self.generation &+= 1
            self.stopStream(restoreTouchBarStatus: false)
            self.lastError = nil
            self.lastNotice = nil
            self.startStream(generation: self.generation)
        }
    }

    func updateFramesPerSecond(_ framesPerSecond: Int) {
        workerQueue.async { [weak self] in
            self?.frameIntervalNanoseconds = Self.frameInterval(
                framesPerSecond: framesPerSecond
            )
        }
    }

    private static func frameInterval(framesPerSecond: Int) -> UInt64 {
        let clamped = min(
            max(framesPerSecond, minimumFramesPerSecond),
            maximumFramesPerSecond
        )
        return 1_000_000_000 / UInt64(clamped)
    }

    private func startStream(generation: UInt64) {
        guard !stopped, generation == self.generation, stream == nil else {
            return
        }

        if initialTouchBarStatus == nil {
            let status = TBRGetTouchBarStatus()
            if status >= 0 {
                initialTouchBarStatus = status
                if status & 1 == 0 {
                    TBRSetTouchBarStatus(status | 1)
                }
            }
        }

        guard let newStreamHandle = TBRCreateTouchBarDisplayStream(
            workerQueue,
            { [weak self] status, _, surface, _ in
                self?.handleFrame(
                    status: status,
                    surface: surface,
                    generation: generation
                )
            }
        ) else {
            report(.streamUnavailable)
            scheduleRetry(generation: generation)
            return
        }
        let newStream = newStreamHandle.takeRetainedValue()

        stream = newStream
        let result = TBRStartDisplayStream(newStream)
        guard result == .success else {
            stream = nil
            report(.streamStartFailed(result.rawValue))
            scheduleRetry(generation: generation)
            return
        }
        scheduleStartupHealthCheck(generation: generation)
        debugTrace("display stream started")
    }

    private func handleFrame(
        status: CGDisplayStreamFrameStatus,
        surface: IOSurfaceRef?,
        generation: UInt64
    ) {
        guard !stopped, generation == self.generation else { return }

        switch status {
        case .frameComplete:
            hasReceivedStreamActivity = true
            guard let surface else {
                report(.invalidSurface)
                return
            }
            guard !isNearlyBlack(surface) else {
                handleBlankFrame()
                return
            }
            guard let image = makeImage(from: surface) else {
                report(.invalidSurface)
                return
            }

            consecutiveBlackFrames = 0
            firstBlankFrameAt = nil
            submitFrame(
                image,
                at: DispatchTime.now().uptimeNanoseconds,
                generation: generation
            )

        case .frameBlank:
            hasReceivedStreamActivity = true
            handleBlankFrame()

        case .stopped:
            stream = nil
            resetFrameDeliveryState()
            report(.streamStopped)
            scheduleRetry(generation: generation)

        case .frameIdle:
            hasReceivedStreamActivity = true
            break

        @unknown default:
            break
        }
    }

    private func handleBlankFrame() {
        pendingFrame = nil
        let timestamp = DispatchTime.now().uptimeNanoseconds
        consecutiveBlackFrames += 1
        if firstBlankFrameAt == nil {
            firstBlankFrameAt = timestamp
        }
        guard
            consecutiveBlackFrames >= Self.minimumBlankFrameCount,
            let firstBlankFrameAt,
            timestamp - firstBlankFrameAt >= Self.minimumBlankFrameDuration
        else {
            return
        }

        if TouchBarSystemState.allowsEmptyContent(
            presentationMode: TouchBarSystemState.presentationMode
        ) {
            reportNotice(.contextualContentUnavailable)
            return
        }

        report(
            TouchBarSystemState.isControlStripExplicitlyEmpty
                ? .controlStripEmpty
                : .blackFrame
        )
    }

    private func shouldDeliver(at timestamp: UInt64) -> Bool {
        guard lastDeliveredAt > 0, timestamp >= lastDeliveredAt else {
            return true
        }
        return timestamp - lastDeliveredAt >= frameIntervalNanoseconds
    }

    private func submitFrame(
        _ image: CGImage,
        at timestamp: UInt64,
        generation: UInt64
    ) {
        guard !shouldDeliver(at: timestamp) else {
            pendingFrame = nil
            deliverFrame(image, at: timestamp)
            return
        }

        // CGDisplayStream may send a short burst of transition frames and then
        // stay idle. Keep replacing the pending image so the final stable frame
        // is delivered instead of being discarded by the FPS limiter.
        pendingFrame = image
        guard !pendingFrameDeliveryScheduled else { return }
        pendingFrameDeliveryScheduled = true
        pendingFrameDeliveryToken &+= 1
        let deliveryToken = pendingFrameDeliveryToken

        let elapsed = timestamp - lastDeliveredAt
        let remaining = frameIntervalNanoseconds - elapsed
        workerQueue.asyncAfter(
            deadline: .now() + .nanoseconds(Int(remaining))
        ) { [weak self] in
            guard
                let self,
                !self.stopped,
                generation == self.generation,
                deliveryToken == self.pendingFrameDeliveryToken
            else {
                return
            }
            self.pendingFrameDeliveryScheduled = false
            guard let pendingFrame = self.pendingFrame else { return }
            self.pendingFrame = nil
            self.deliverFrame(
                pendingFrame,
                at: DispatchTime.now().uptimeNanoseconds
            )
        }
    }

    private func deliverFrame(_ image: CGImage, at timestamp: UInt64) {
        lastError = nil
        lastNotice = nil
        lastDeliveredAt = timestamp
        onFrame(image)
        if !hasLoggedFirstFrame {
            hasLoggedFirstFrame = true
            Self.logger.info(
                "Received Touch Bar frame: \(image.width)x\(image.height)"
            )
            debugTrace(
                "received Touch Bar frame \(image.width)x\(image.height)"
            )
        }
    }

    private func makeImage(from surface: IOSurfaceRef) -> CGImage? {
        autoreleasepool {
            let image = CIImage(ioSurface: surface)
            guard !image.extent.isEmpty, !image.extent.isInfinite else {
                return nil
            }
            return imageContext.createCGImage(image, from: image.extent)
        }
    }

    private func isNearlyBlack(_ surface: IOSurfaceRef) -> Bool {
        var seed: UInt32 = 0
        guard IOSurfaceLock(surface, .readOnly, &seed) == kIOReturnSuccess else {
            return false
        }
        defer {
            IOSurfaceUnlock(surface, .readOnly, &seed)
        }

        guard IOSurfaceGetWidth(surface) > 0, IOSurfaceGetHeight(surface) > 0 else {
            return false
        }

        let baseAddress = IOSurfaceGetBaseAddress(surface)
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let bytesPerRow = IOSurfaceGetBytesPerRow(surface)
        let bytesPerElement = max(IOSurfaceGetBytesPerElement(surface), 1)
        let colorBytes = min(bytesPerElement, 3)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let horizontalStep = max(width / 160, 1)
        let verticalStep = max(height / 8, 1)
        var visibleSamples = 0

        for y in stride(from: 0, to: height, by: verticalStep) {
            for x in stride(from: 0, to: width, by: horizontalStep) {
                let pixelOffset = y * bytesPerRow + x * bytesPerElement
                var brightest: UInt8 = 0
                for channel in 0..<colorBytes {
                    brightest = max(brightest, bytes[pixelOffset + channel])
                }
                if brightest > 32 {
                    visibleSamples += 1
                    if visibleSamples >= 2 {
                        return false
                    }
                }
            }
        }
        return true
    }

    private func stopStream(restoreTouchBarStatus: Bool) {
        if let stream {
            _ = TBRStopDisplayStream(stream)
            self.stream = nil
        }
        resetFrameDeliveryState()

        if restoreTouchBarStatus, let initialTouchBarStatus {
            TBRSetTouchBarStatus(initialTouchBarStatus)
            self.initialTouchBarStatus = nil
        }
    }

    private func resetFrameDeliveryState() {
        lastDeliveredAt = 0
        pendingFrame = nil
        pendingFrameDeliveryScheduled = false
        pendingFrameDeliveryToken &+= 1
        consecutiveBlackFrames = 0
        firstBlankFrameAt = nil
        hasReceivedStreamActivity = false
    }

    private func scheduleRetry(generation: UInt64) {
        guard !stopped, generation == self.generation else { return }
        workerQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startStream(generation: generation)
        }
    }

    private func scheduleStartupHealthCheck(generation: UInt64) {
        workerQueue.asyncAfter(
            deadline: .now() + Self.streamStartupTimeout
        ) { [weak self] in
            guard
                let self,
                !self.stopped,
                generation == self.generation,
                self.stream != nil,
                !self.hasReceivedStreamActivity
            else {
                return
            }
            self.stopStream(restoreTouchBarStatus: false)
            self.report(.streamStartupTimedOut)
            self.scheduleRetry(generation: generation)
        }
    }

    private func report(_ error: TouchBarCaptureError) {
        guard lastError != error else { return }
        lastError = error
        lastNotice = nil
        Self.logger.error("\(error.localizedDescription, privacy: .public)")
        debugTrace("error: \(error.localizedDescription)")
        onError(error)
    }

    private func reportNotice(_ notice: TouchBarCaptureNotice) {
        guard lastNotice != notice else { return }
        lastNotice = notice
        lastError = nil
        Self.logger.info("\(notice.description, privacy: .public)")
        debugTrace("notice: \(notice.description)")
        onNotice(notice)
    }

    private func debugTrace(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(
            Data("[ToubarReplace] \(message)\n".utf8)
        )
        #endif
    }
}
