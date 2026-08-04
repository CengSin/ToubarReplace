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
    private let workspaceSidePopup: NSPopUpButton
    private let terminalAdapterPopup: NSPopUpButton
    private let widthField: NSTextField
    private let heightField: NSTextField
    private let framesPerSecondField: NSTextField
    private let workspaceFloatingSwitcherCheckbox: NSButton
    private let workspaceAutoCollapseCheckbox: NSButton
    private let onPositionChanged: (TouchBarDisplayPosition) -> Void
    private let onWorkspaceSideChanged: (WorkspaceSwitcherSide) -> Void
    private let onWorkspaceFloatingSwitcherChanged: (Bool) -> Void
    private let onWorkspaceAutoCollapseChanged: (Bool) -> Void
    private let terminalAdapters: [TerminalAdapter]
    private let onTerminalAdapterChanged: (TerminalAdapterID) -> Void
    private let onPixelSizeChanged: (CGSize) -> Void
    private let onFramesPerSecondChanged: (Int) -> Void
    private let onWindowClosed: () -> Void

    init(
        currentPosition: TouchBarDisplayPosition,
        currentPixelSize: CGSize,
        currentFramesPerSecond: Int,
        currentWorkspaceSide: WorkspaceSwitcherSide,
        currentWorkspaceSwitcherFloats: Bool,
        currentWorkspaceAutoCollapse: Bool,
        terminalAdapters: [TerminalAdapter],
        currentTerminalAdapterID: TerminalAdapterID,
        onPositionChanged: @escaping (TouchBarDisplayPosition) -> Void,
        onWorkspaceSideChanged: @escaping (WorkspaceSwitcherSide) -> Void,
        onWorkspaceFloatingSwitcherChanged: @escaping (Bool) -> Void,
        onWorkspaceAutoCollapseChanged: @escaping (Bool) -> Void,
        onTerminalAdapterChanged: @escaping (TerminalAdapterID) -> Void,
        onPixelSizeChanged: @escaping (CGSize) -> Void,
        onFramesPerSecondChanged: @escaping (Int) -> Void,
        onWindowClosed: @escaping () -> Void
    ) {
        self.positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.workspaceSidePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.terminalAdapterPopup = NSPopUpButton(
            frame: .zero,
            pullsDown: false
        )
        self.widthField = NSTextField()
        self.heightField = NSTextField()
        self.framesPerSecondField = NSTextField()
        self.workspaceFloatingSwitcherCheckbox = NSButton(
            checkboxWithTitle: "切换按钮使用独立浮窗",
            target: nil,
            action: nil
        )
        self.workspaceAutoCollapseCheckbox = NSButton(
            checkboxWithTitle: "启动 Agent 后自动返回镜像",
            target: nil,
            action: nil
        )
        self.onPositionChanged = onPositionChanged
        self.onWorkspaceSideChanged = onWorkspaceSideChanged
        self.onWorkspaceFloatingSwitcherChanged =
            onWorkspaceFloatingSwitcherChanged
        self.onWorkspaceAutoCollapseChanged = onWorkspaceAutoCollapseChanged
        self.terminalAdapters = terminalAdapters
        self.onTerminalAdapterChanged = onTerminalAdapterChanged
        self.onPixelSizeChanged = onPixelSizeChanged
        self.onFramesPerSecondChanged = onFramesPerSecondChanged
        self.onWindowClosed = onWindowClosed

        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 460, height: 475)
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

        let workspaceSideLabel = NSTextField(labelWithString: "Workspace 入口")
        workspaceSidePopup.addItems(
            withTitles: WorkspaceSwitcherSide.allCases.map(\.title)
        )
        workspaceSidePopup.selectItem(
            at: WorkspaceSwitcherSide.allCases.firstIndex(
                of: currentWorkspaceSide
            ) ?? 0
        )
        workspaceFloatingSwitcherCheckbox.state = currentWorkspaceSwitcherFloats
            ? .on
            : .off
        workspaceSidePopup.isEnabled = !currentWorkspaceSwitcherFloats
        workspaceAutoCollapseCheckbox.state = currentWorkspaceAutoCollapse
            ? .on
            : .off

        let terminalAdapterLabel = NSTextField(labelWithString: "Claude 终端")
        terminalAdapterPopup.addItems(
            withTitles: terminalAdapters.map(\.displayName)
        )
        terminalAdapterPopup.selectItem(
            at: terminalAdapters.firstIndex {
                $0.id == currentTerminalAdapterID
            } ?? 0
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

        let workspaceSideRow = NSStackView(
            views: [workspaceSideLabel, workspaceSidePopup]
        )
        workspaceSideRow.orientation = .horizontal
        workspaceSideRow.spacing = 12
        workspaceSideRow.alignment = .centerY
        workspaceSidePopup.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )

        let workspaceFloatingSwitcherRow = NSStackView(
            views: [
                NSTextField(labelWithString: ""),
                workspaceFloatingSwitcherCheckbox,
            ]
        )
        workspaceFloatingSwitcherRow.orientation = .horizontal
        workspaceFloatingSwitcherRow.spacing = 12
        workspaceFloatingSwitcherRow.alignment = .centerY

        let workspaceAutoCollapseRow = NSStackView(
            views: [
                NSTextField(labelWithString: ""),
                workspaceAutoCollapseCheckbox,
            ]
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
        terminalAdapterPopup.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )

        let stack = NSStackView(
            views: [
                titleLabel,
                positionRow,
                workspaceFloatingSwitcherRow,
                workspaceSideRow,
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
            workspaceFloatingSwitcherRow.arrangedSubviews[0].widthAnchor.constraint(
                equalToConstant: 72
            ),
            workspaceSideLabel.widthAnchor.constraint(equalToConstant: 72),
            workspaceAutoCollapseRow.arrangedSubviews[0].widthAnchor.constraint(
                equalToConstant: 72
            ),
            terminalAdapterLabel.widthAnchor.constraint(equalToConstant: 72),
            sizeLabel.widthAnchor.constraint(equalToConstant: 72),
            framesPerSecondLabel.widthAnchor.constraint(equalToConstant: 72),
            positionPopup.widthAnchor.constraint(equalToConstant: 180),
            workspaceSidePopup.widthAnchor.constraint(equalToConstant: 180),
            terminalAdapterPopup.widthAnchor.constraint(equalToConstant: 180),
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
        workspaceSidePopup.target = self
        workspaceSidePopup.action = #selector(workspaceSideChanged(_:))
        workspaceFloatingSwitcherCheckbox.target = self
        workspaceFloatingSwitcherCheckbox.action = #selector(
            workspaceFloatingSwitcherChanged(_:)
        )
        workspaceAutoCollapseCheckbox.target = self
        workspaceAutoCollapseCheckbox.action = #selector(
            workspaceAutoCollapseChanged(_:)
        )
        terminalAdapterPopup.target = self
        terminalAdapterPopup.action = #selector(terminalAdapterChanged(_:))
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
    private func workspaceSideChanged(_ sender: NSPopUpButton) {
        let itemIndex = sender.indexOfSelectedItem
        guard WorkspaceSwitcherSide.allCases.indices.contains(itemIndex) else {
            return
        }
        onWorkspaceSideChanged(WorkspaceSwitcherSide.allCases[itemIndex])
    }

    @objc
    private func workspaceFloatingSwitcherChanged(_ sender: NSButton) {
        let floats = sender.state == .on
        workspaceSidePopup.isEnabled = !floats
        onWorkspaceFloatingSwitcherChanged(floats)
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
