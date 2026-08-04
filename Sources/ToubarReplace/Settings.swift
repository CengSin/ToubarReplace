import AppKit

enum TouchBarDisplayPosition: String, CaseIterable {
    case bottom
    case top
    case center

    var title: String {
        switch self {
        case .bottom:
            return "底部（默认）"
        case .top:
            return "顶部"
        case .center:
            return "屏幕中央"
        }
    }
}

enum TouchBarPreferences {
    private static let positionKey = "ToubarReplace.displayPosition"
    private static let widthPixelsKey = "ToubarReplace.widthPixels"
    private static let heightPixelsKey = "ToubarReplace.heightPixels"
    private static let displayFramesPerSecondKey =
        "ToubarReplace.displayFramesPerSecond"

    private static let legacyDefaultMirrorPixelSize = CGSize(
        width: 2_008,
        height: 60
    )
    static let defaultMirrorPixelSize = CGSize(width: 2_300, height: 70)

    static var displayPosition: TouchBarDisplayPosition {
        get {
            guard
                let rawValue = UserDefaults.standard.string(forKey: positionKey),
                let position = TouchBarDisplayPosition(rawValue: rawValue)
            else {
                return .bottom
            }
            return position
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: positionKey)
        }
    }

    static var mirrorPixelSize: CGSize {
        get {
            let width = UserDefaults.standard.double(forKey: widthPixelsKey)
            let height = UserDefaults.standard.double(forKey: heightPixelsKey)
            guard width > 0, height > 0 else {
                return defaultMirrorPixelSize
            }
            if width == legacyDefaultMirrorPixelSize.width,
                height == legacyDefaultMirrorPixelSize.height
            {
                return defaultMirrorPixelSize
            }
            return CGSize(width: width, height: height)
        }
        set {
            UserDefaults.standard.set(
                max(newValue.width.rounded(), 1),
                forKey: widthPixelsKey
            )
            UserDefaults.standard.set(
                max(newValue.height.rounded(), 1),
                forKey: heightPixelsKey
            )
        }
    }

    static var displayFramesPerSecond: Int {
        get {
            let stored = UserDefaults.standard.integer(
                forKey: displayFramesPerSecondKey
            )
            guard stored > 0 else {
                return TouchBarCapture.defaultFramesPerSecond
            }
            return min(
                max(stored, TouchBarCapture.minimumFramesPerSecond),
                TouchBarCapture.maximumFramesPerSecond
            )
        }
        set {
            UserDefaults.standard.set(
                min(
                    max(newValue, TouchBarCapture.minimumFramesPerSecond),
                    TouchBarCapture.maximumFramesPerSecond
                ),
                forKey: displayFramesPerSecondKey
            )
        }
    }
}

@MainActor
final class TouchBarSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let positionPopup: NSPopUpButton
    private let widthField: NSTextField
    private let heightField: NSTextField
    private let framesPerSecondField: NSTextField
    private let onPositionChanged: (TouchBarDisplayPosition) -> Void
    private let onPixelSizeChanged: (CGSize) -> Void
    private let onFramesPerSecondChanged: (Int) -> Void
    private let onWindowClosed: () -> Void

    init(
        currentPosition: TouchBarDisplayPosition,
        currentPixelSize: CGSize,
        currentFramesPerSecond: Int,
        onPositionChanged: @escaping (TouchBarDisplayPosition) -> Void,
        onPixelSizeChanged: @escaping (CGSize) -> Void,
        onFramesPerSecondChanged: @escaping (Int) -> Void,
        onWindowClosed: @escaping () -> Void
    ) {
        self.positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.widthField = NSTextField()
        self.heightField = NSTextField()
        self.framesPerSecondField = NSTextField()
        self.onPositionChanged = onPositionChanged
        self.onPixelSizeChanged = onPixelSizeChanged
        self.onFramesPerSecondChanged = onFramesPerSecondChanged
        self.onWindowClosed = onWindowClosed

        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 460, height: 280)
        )
        let titleLabel = NSTextField(
            labelWithString: "Touch Bar 镜像设置"
        )
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let positionLabel = NSTextField(labelWithString: "展示位置")
        positionPopup.addItems(
            withTitles: TouchBarDisplayPosition.allCases.map(\.title)
        )
        positionPopup.selectItem(at: TouchBarDisplayPosition.allCases.firstIndex(
            of: currentPosition
        ) ?? 0)

        let sizeLabel = NSTextField(labelWithString: "窗口像素")
        let multiplicationLabel = NSTextField(labelWithString: "×")
        let pixelsLabel = NSTextField(labelWithString: "px")
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 20_000
        widthField.formatter = formatter
        heightField.formatter = formatter
        widthField.alignment = .right
        heightField.alignment = .right
        widthField.integerValue = Int(currentPixelSize.width.rounded())
        heightField.integerValue = Int(currentPixelSize.height.rounded())

        let framesPerSecondLabel = NSTextField(labelWithString: "镜像帧率")
        let fpsLabel = NSTextField(labelWithString: "FPS")
        let framesPerSecondFormatter = NumberFormatter()
        framesPerSecondFormatter.allowsFloats = false
        framesPerSecondFormatter.minimum = NSNumber(
            value: TouchBarCapture.minimumFramesPerSecond
        )
        framesPerSecondFormatter.maximum = NSNumber(
            value: TouchBarCapture.maximumFramesPerSecond
        )
        framesPerSecondField.formatter = framesPerSecondFormatter
        framesPerSecondField.alignment = .right
        framesPerSecondField.integerValue = currentFramesPerSecond

        let hintLabel = NSTextField(
            labelWithString: "画面来自一个持续运行的 Touch Bar 显示流，不再重复启动截图进程。默认 30 FPS；窗口像素会自动保存。"
        )
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 2
        hintLabel.lineBreakMode = .byWordWrapping

        let positionRow = NSStackView(views: [positionLabel, positionPopup])
        positionRow.orientation = .horizontal
        positionRow.spacing = 12
        positionRow.alignment = .centerY
        positionPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        positionPopup.setContentCompressionResistancePriority(
            .defaultHigh,
            for: .horizontal
        )

        let sizeRow = NSStackView(
            views: [
                sizeLabel,
                widthField,
                multiplicationLabel,
                heightField,
                pixelsLabel,
            ]
        )
        sizeRow.orientation = .horizontal
        sizeRow.spacing = 8
        sizeRow.alignment = .centerY

        let framesPerSecondRow = NSStackView(
            views: [framesPerSecondLabel, framesPerSecondField, fpsLabel]
        )
        framesPerSecondRow.orientation = .horizontal
        framesPerSecondRow.spacing = 8
        framesPerSecondRow.alignment = .centerY

        let stack = NSStackView(
            views: [
                titleLabel,
                positionRow,
                sizeRow,
                framesPerSecondRow,
                hintLabel,
            ]
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            positionLabel.widthAnchor.constraint(equalToConstant: 72),
            sizeLabel.widthAnchor.constraint(equalToConstant: 72),
            framesPerSecondLabel.widthAnchor.constraint(equalToConstant: 72),
            positionPopup.widthAnchor.constraint(equalToConstant: 180),
            widthField.widthAnchor.constraint(equalToConstant: 90),
            heightField.widthAnchor.constraint(equalToConstant: 70),
            framesPerSecondField.widthAnchor.constraint(equalToConstant: 90),
            hintLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ToubarReplace 设置"
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        positionPopup.target = self
        positionPopup.action = #selector(positionChanged(_:))
        widthField.target = self
        widthField.action = #selector(pixelSizeChanged(_:))
        heightField.target = self
        heightField.action = #selector(pixelSizeChanged(_:))
        framesPerSecondField.target = self
        framesPerSecondField.action = #selector(framesPerSecondChanged(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed()
    }

    @objc
    private func positionChanged(_ sender: NSPopUpButton) {
        let itemIndex = sender.indexOfSelectedItem
        guard TouchBarDisplayPosition.allCases.indices.contains(itemIndex) else {
            return
        }
        let position = TouchBarDisplayPosition.allCases[itemIndex]
        onPositionChanged(position)
    }

    @objc
    private func pixelSizeChanged(_ sender: NSTextField) {
        let pixelSize = CGSize(
            width: max(widthField.doubleValue.rounded(), 1),
            height: max(heightField.doubleValue.rounded(), 1)
        )
        updatePixelSize(pixelSize)
        onPixelSizeChanged(pixelSize)
    }

    func updatePixelSize(_ pixelSize: CGSize) {
        widthField.integerValue = Int(pixelSize.width.rounded())
        heightField.integerValue = Int(pixelSize.height.rounded())
    }

    @objc
    private func framesPerSecondChanged(_ sender: NSTextField) {
        let framesPerSecond = min(
            max(
                sender.integerValue,
                TouchBarCapture.minimumFramesPerSecond
            ),
            TouchBarCapture.maximumFramesPerSecond
        )
        framesPerSecondField.integerValue = framesPerSecond
        onFramesPerSecondChanged(framesPerSecond)
    }
}
