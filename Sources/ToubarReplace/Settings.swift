import AppKit

enum TouchBarDisplayPosition: String, CaseIterable {
    case bottom
    case top
    case center
    /// Restore AppKit autosaved mirror frame origin on launch.
    case lastSaved
    /// Use explicit top-left coordinates from preferences.
    case custom

    var title: String {
        switch self {
        case .bottom:
            return "底部（默认）"
        case .top:
            return "顶部"
        case .center:
            return "屏幕中央"
        case .lastSaved:
            return "上次关闭时的位置"
        case .custom:
            return "自定义坐标"
        }
    }

    var usesCustomTopLeft: Bool {
        self == .custom
    }

    var restoresAutosavedFrame: Bool {
        self == .lastSaved
    }
}

enum TouchBarPreferences {
    private static let positionKey = "ToubarReplace.displayPosition"
    private static let widthPixelsKey = "ToubarReplace.widthPixels"
    private static let heightPixelsKey = "ToubarReplace.heightPixels"
    private static let displayFramesPerSecondKey =
        "ToubarReplace.displayFramesPerSecond"
    private static let customTopLeftXKey = "ToubarReplace.customTopLeftX"
    private static let customTopLeftYKey = "ToubarReplace.customTopLeftY"

    static let mirrorWindowAutosaveName = "ToubarReplaceMirrorWindow"

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

    /// Whether the user has explicitly saved a custom top-left origin.
    static var hasCustomTopLeft: Bool {
        UserDefaults.standard.object(forKey: customTopLeftXKey) != nil
            && UserDefaults.standard.object(forKey: customTopLeftYKey) != nil
    }

    /// Top-left of the mirror window in AppKit screen points
    /// (`y` increases upward).
    static var customTopLeft: CGPoint {
        get {
            CGPoint(
                x: UserDefaults.standard.double(forKey: customTopLeftXKey),
                y: UserDefaults.standard.double(forKey: customTopLeftYKey)
            )
        }
        set {
            UserDefaults.standard.set(newValue.x, forKey: customTopLeftXKey)
            UserDefaults.standard.set(newValue.y, forKey: customTopLeftYKey)
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
    private let originXField: NSTextField
    private let originYField: NSTextField
    private let switcherDisplayModePopup: NSPopUpButton
    private let terminalAdapterPopup: NSPopUpButton
    private let widthField: NSTextField
    private let heightField: NSTextField
    private let framesPerSecondField: NSTextField
    private let workspaceAutoCollapseCheckbox: NSButton
    private let onPositionChanged: (TouchBarDisplayPosition) -> Void
    private let onCustomTopLeftChanged: (CGPoint) -> Void
    private let onWorkspaceFloatingSwitcherChanged: (Bool) -> Void
    private let onWorkspaceAutoCollapseChanged: (Bool) -> Void
    private let terminalAdapters: [TerminalAdapter]
    private let onTerminalAdapterChanged: (TerminalAdapterID) -> Void
    private let onPixelSizeChanged: (CGSize) -> Void
    private let onFramesPerSecondChanged: (Int) -> Void
    private let onWindowClosed: () -> Void

    init(
        currentPosition: TouchBarDisplayPosition,
        currentCustomTopLeft: CGPoint,
        currentPixelSize: CGSize,
        currentFramesPerSecond: Int,
        currentWorkspaceSide: WorkspaceSwitcherSide,
        currentWorkspaceSwitcherFloats: Bool,
        currentWorkspaceAutoCollapse: Bool,
        terminalAdapters: [TerminalAdapter],
        currentTerminalAdapterID: TerminalAdapterID,
        onPositionChanged: @escaping (TouchBarDisplayPosition) -> Void,
        onCustomTopLeftChanged: @escaping (CGPoint) -> Void,
        onWorkspaceSideChanged: @escaping (WorkspaceSwitcherSide) -> Void,
        onWorkspaceFloatingSwitcherChanged: @escaping (Bool) -> Void,
        onWorkspaceAutoCollapseChanged: @escaping (Bool) -> Void,
        onTerminalAdapterChanged: @escaping (TerminalAdapterID) -> Void,
        onPixelSizeChanged: @escaping (CGSize) -> Void,
        onFramesPerSecondChanged: @escaping (Int) -> Void,
        onWindowClosed: @escaping () -> Void
    ) {
        self.positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.originXField = NSTextField()
        self.originYField = NSTextField()
        self.switcherDisplayModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.terminalAdapterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.widthField = NSTextField()
        self.heightField = NSTextField()
        self.framesPerSecondField = NSTextField()
        self.workspaceAutoCollapseCheckbox = NSButton(
            checkboxWithTitle: "启动 Agent 后自动返回镜像",
            target: nil,
            action: nil
        )
        self.onPositionChanged = onPositionChanged
        self.onCustomTopLeftChanged = onCustomTopLeftChanged
        self.onWorkspaceFloatingSwitcherChanged = onWorkspaceFloatingSwitcherChanged
        self.onWorkspaceAutoCollapseChanged = onWorkspaceAutoCollapseChanged
        self.terminalAdapters = terminalAdapters
        self.onTerminalAdapterChanged = onTerminalAdapterChanged
        self.onPixelSizeChanged = onPixelSizeChanged
        self.onFramesPerSecondChanged = onFramesPerSecondChanged
        self.onWindowClosed = onWindowClosed

        // Keep side callback for API compatibility (attached rail removed).
        _ = onWorkspaceSideChanged
        _ = currentWorkspaceSide

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 500))
        let titleLabel = NSTextField(labelWithString: "Touch Bar 镜像设置")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let positionLabel = NSTextField(labelWithString: "展示位置")
        positionPopup.addItems(withTitles: TouchBarDisplayPosition.allCases.map(\.title))
        positionPopup.selectItem(
            at: TouchBarDisplayPosition.allCases.firstIndex(of: currentPosition) ?? 0
        )

        let originLabel = NSTextField(labelWithString: "起始坐标")
        let originXCaption = NSTextField(labelWithString: "X")
        let originYCaption = NSTextField(labelWithString: "Y")
        let originUnitLabel = NSTextField(labelWithString: "pt（窗口左上角）")
        originUnitLabel.textColor = .secondaryLabelColor
        let originFormatter = NumberFormatter()
        originFormatter.allowsFloats = true
        originFormatter.minimumFractionDigits = 0
        originFormatter.maximumFractionDigits = 1
        originFormatter.minimum = -20_000
        originFormatter.maximum = 20_000
        originXField.formatter = originFormatter
        originYField.formatter = originFormatter
        originXField.alignment = .right
        originYField.alignment = .right
        originXField.doubleValue = currentCustomTopLeft.x
        originYField.doubleValue = currentCustomTopLeft.y

        let switcherModeLabel = NSTextField(labelWithString: "切换按钮")
        switcherDisplayModePopup.addItems(
            withTitles: WorkspaceSwitcherDisplayMode.allCases.map(\.title)
        )
        let currentMode: WorkspaceSwitcherDisplayMode =
            currentWorkspaceSwitcherFloats ? .floating : .touchBar
        switcherDisplayModePopup.selectItem(
            at: WorkspaceSwitcherDisplayMode.allCases.firstIndex(of: currentMode) ?? 0
        )

        workspaceAutoCollapseCheckbox.state = currentWorkspaceAutoCollapse ? .on : .off

        let terminalAdapterLabel = NSTextField(labelWithString: "Claude 终端")
        terminalAdapterPopup.addItems(withTitles: terminalAdapters.map(\.displayName))
        terminalAdapterPopup.selectItem(
            at: terminalAdapters.firstIndex { $0.id == currentTerminalAdapterID } ?? 0
        )

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
            labelWithString: """
            展示位置：固定锚点、上次关闭位置，或自定义窗口左上角（AppKit 坐标，Y 向上）。\
            切换按钮二选一：物理 Touch Bar 可触摸，或使用独立浮窗。
            """
        )
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 4
        hintLabel.lineBreakMode = .byWordWrapping

        let positionRow = NSStackView(views: [positionLabel, positionPopup])
        positionRow.orientation = .horizontal
        positionRow.spacing = 12
        positionRow.alignment = .centerY

        let originRow = NSStackView(
            views: [
                originLabel,
                originXCaption,
                originXField,
                originYCaption,
                originYField,
                originUnitLabel,
            ]
        )
        originRow.orientation = .horizontal
        originRow.spacing = 8
        originRow.alignment = .centerY

        let switcherModeRow = NSStackView(views: [switcherModeLabel, switcherDisplayModePopup])
        switcherModeRow.orientation = .horizontal
        switcherModeRow.spacing = 12
        switcherModeRow.alignment = .centerY

        let workspaceAutoCollapseRow = NSStackView(
            views: [NSTextField(labelWithString: ""), workspaceAutoCollapseCheckbox]
        )
        workspaceAutoCollapseRow.orientation = .horizontal
        workspaceAutoCollapseRow.spacing = 12
        workspaceAutoCollapseRow.alignment = .centerY

        let terminalAdapterRow = NSStackView(
            views: [terminalAdapterLabel, terminalAdapterPopup]
        )
        terminalAdapterRow.orientation = .horizontal
        terminalAdapterRow.spacing = 12
        terminalAdapterRow.alignment = .centerY

        let sizeRow = NSStackView(
            views: [sizeLabel, widthField, multiplicationLabel, heightField, pixelsLabel]
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
                originRow,
                switcherModeRow,
                workspaceAutoCollapseRow,
                terminalAdapterRow,
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
            originLabel.widthAnchor.constraint(equalToConstant: 72),
            switcherModeLabel.widthAnchor.constraint(equalToConstant: 72),
            workspaceAutoCollapseRow.arrangedSubviews[0].widthAnchor.constraint(
                equalToConstant: 72
            ),
            terminalAdapterLabel.widthAnchor.constraint(equalToConstant: 72),
            sizeLabel.widthAnchor.constraint(equalToConstant: 72),
            framesPerSecondLabel.widthAnchor.constraint(equalToConstant: 72),
            positionPopup.widthAnchor.constraint(equalToConstant: 180),
            switcherDisplayModePopup.widthAnchor.constraint(equalToConstant: 180),
            terminalAdapterPopup.widthAnchor.constraint(equalToConstant: 180),
            originXField.widthAnchor.constraint(equalToConstant: 70),
            originYField.widthAnchor.constraint(equalToConstant: 70),
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
        originXField.target = self
        originXField.action = #selector(customTopLeftChanged(_:))
        originYField.target = self
        originYField.action = #selector(customTopLeftChanged(_:))
        switcherDisplayModePopup.target = self
        switcherDisplayModePopup.action = #selector(switcherDisplayModeChanged(_:))
        workspaceAutoCollapseCheckbox.target = self
        workspaceAutoCollapseCheckbox.action = #selector(workspaceAutoCollapseChanged(_:))
        terminalAdapterPopup.target = self
        terminalAdapterPopup.action = #selector(terminalAdapterChanged(_:))
        widthField.target = self
        widthField.action = #selector(pixelSizeChanged(_:))
        heightField.target = self
        heightField.action = #selector(pixelSizeChanged(_:))
        framesPerSecondField.target = self
        framesPerSecondField.action = #selector(framesPerSecondChanged(_:))
        updateCustomOriginFieldsEnabled(for: currentPosition)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed()
    }

    func updateCustomTopLeft(_ topLeft: CGPoint) {
        originXField.doubleValue = topLeft.x
        originYField.doubleValue = topLeft.y
    }

    @objc
    private func positionChanged(_ sender: NSPopUpButton) {
        let itemIndex = sender.indexOfSelectedItem
        guard TouchBarDisplayPosition.allCases.indices.contains(itemIndex) else {
            return
        }
        let position = TouchBarDisplayPosition.allCases[itemIndex]
        updateCustomOriginFieldsEnabled(for: position)
        onPositionChanged(position)
    }

    @objc
    private func customTopLeftChanged(_ sender: NSTextField) {
        let topLeft = CGPoint(
            x: originXField.doubleValue,
            y: originYField.doubleValue
        )
        updateCustomTopLeft(topLeft)
        onCustomTopLeftChanged(topLeft)
    }

    @objc
    private func switcherDisplayModeChanged(_ sender: NSPopUpButton) {
        let itemIndex = sender.indexOfSelectedItem
        guard WorkspaceSwitcherDisplayMode.allCases.indices.contains(itemIndex) else {
            return
        }
        let mode = WorkspaceSwitcherDisplayMode.allCases[itemIndex]
        onWorkspaceFloatingSwitcherChanged(mode == .floating)
    }

    @objc
    private func workspaceAutoCollapseChanged(_ sender: NSButton) {
        onWorkspaceAutoCollapseChanged(sender.state == .on)
    }

    @objc
    private func terminalAdapterChanged(_ sender: NSPopUpButton) {
        let itemIndex = sender.indexOfSelectedItem
        guard terminalAdapters.indices.contains(itemIndex) else { return }
        onTerminalAdapterChanged(terminalAdapters[itemIndex].id)
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
            max(sender.integerValue, TouchBarCapture.minimumFramesPerSecond),
            TouchBarCapture.maximumFramesPerSecond
        )
        framesPerSecondField.integerValue = framesPerSecond
        onFramesPerSecondChanged(framesPerSecond)
    }

    private func updateCustomOriginFieldsEnabled(for position: TouchBarDisplayPosition) {
        let enabled = position.usesCustomTopLeft
        originXField.isEnabled = enabled
        originYField.isEnabled = enabled
        originXField.alphaValue = enabled ? 1 : 0.5
        originYField.alphaValue = enabled ? 1 : 0.5
    }
}
