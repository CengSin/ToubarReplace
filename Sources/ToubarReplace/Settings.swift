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
    private static let idleOpacityDelaySecondsKey =
        "ToubarReplace.idleOpacityDelaySeconds"
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

    static var idleOpacityDelaySeconds: Int {
        get {
            guard
                UserDefaults.standard.object(
                    forKey: idleOpacityDelaySecondsKey
                ) != nil
            else {
                return TouchBarIdleOpacity.defaultDelaySeconds
            }
            return TouchBarIdleOpacity.clampedDelaySeconds(
                UserDefaults.standard.integer(
                    forKey: idleOpacityDelaySecondsKey
                )
            )
        }
        set {
            UserDefaults.standard.set(
                TouchBarIdleOpacity.clampedDelaySeconds(newValue),
                forKey: idleOpacityDelaySecondsKey
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
    private let startupScenePopup: NSPopUpButton
    private let terminalAdapterPopup: NSPopUpButton
    private let widthField: NSTextField
    private let heightField: NSTextField
    private let framesPerSecondField: NSTextField
    private let idleOpacityDelayField: NSTextField
    private let workspaceAutoCollapseCheckbox: NSButton
    private let customAppsStack: NSStackView
    private let recentsStack: NSStackView
    private let onPositionChanged: (TouchBarDisplayPosition) -> Void
    private let onCustomTopLeftChanged: (CGPoint) -> Void
    private let onWorkspaceFloatingSwitcherChanged: (Bool) -> Void
    private let onWorkspaceStartupSceneChanged: (WorkspaceStartupScene) -> Void
    private let onWorkspaceAutoCollapseChanged: (Bool) -> Void
    private let onRecentsChanged: () -> Void
    private let terminalAdapters: [TerminalAdapter]
    private let onTerminalAdapterChanged: (TerminalAdapterID) -> Void
    private let onPixelSizeChanged: (CGSize) -> Void
    private let onFramesPerSecondChanged: (Int) -> Void
    private let onIdleOpacityDelayChanged: (Int) -> Void
    private let onPickApplication: (@escaping (URL?) -> Void) -> Void
    private let onCustomAppsChanged: () -> Void
    private let onWindowClosed: () -> Void

    init(
        currentPosition: TouchBarDisplayPosition,
        currentCustomTopLeft: CGPoint,
        currentPixelSize: CGSize,
        currentFramesPerSecond: Int,
        currentIdleOpacityDelaySeconds: Int,
        currentWorkspaceSwitcherFloats: Bool,
        currentWorkspaceStartupScene: WorkspaceStartupScene,
        currentWorkspaceAutoCollapse: Bool,
        terminalAdapters: [TerminalAdapter],
        currentTerminalAdapterID: TerminalAdapterID,
        onPositionChanged: @escaping (TouchBarDisplayPosition) -> Void,
        onCustomTopLeftChanged: @escaping (CGPoint) -> Void,
        onWorkspaceFloatingSwitcherChanged: @escaping (Bool) -> Void,
        onWorkspaceStartupSceneChanged: @escaping (WorkspaceStartupScene) -> Void,
        onWorkspaceAutoCollapseChanged: @escaping (Bool) -> Void,
        onRecentsChanged: @escaping () -> Void,
        onTerminalAdapterChanged: @escaping (TerminalAdapterID) -> Void,
        onPixelSizeChanged: @escaping (CGSize) -> Void,
        onFramesPerSecondChanged: @escaping (Int) -> Void,
        onIdleOpacityDelayChanged: @escaping (Int) -> Void,
        onPickApplication: @escaping (@escaping (URL?) -> Void) -> Void,
        onCustomAppsChanged: @escaping () -> Void,
        onWindowClosed: @escaping () -> Void
    ) {
        self.positionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.originXField = NSTextField()
        self.originYField = NSTextField()
        self.switcherDisplayModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.startupScenePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.terminalAdapterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        self.widthField = NSTextField()
        self.heightField = NSTextField()
        self.framesPerSecondField = NSTextField()
        self.idleOpacityDelayField = NSTextField()
        self.workspaceAutoCollapseCheckbox = NSButton(
            checkboxWithTitle: "启动 Agent 后自动返回镜像",
            target: nil,
            action: nil
        )
        self.customAppsStack = NSStackView()
        self.recentsStack = NSStackView()
        self.onPositionChanged = onPositionChanged
        self.onCustomTopLeftChanged = onCustomTopLeftChanged
        self.onWorkspaceFloatingSwitcherChanged = onWorkspaceFloatingSwitcherChanged
        self.onWorkspaceStartupSceneChanged = onWorkspaceStartupSceneChanged
        self.onWorkspaceAutoCollapseChanged = onWorkspaceAutoCollapseChanged
        self.onRecentsChanged = onRecentsChanged
        self.terminalAdapters = terminalAdapters
        self.onTerminalAdapterChanged = onTerminalAdapterChanged
        self.onPixelSizeChanged = onPixelSizeChanged
        self.onFramesPerSecondChanged = onFramesPerSecondChanged
        self.onIdleOpacityDelayChanged = onIdleOpacityDelayChanged
        self.onPickApplication = onPickApplication
        self.onCustomAppsChanged = onCustomAppsChanged
        self.onWindowClosed = onWindowClosed

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 825))
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
            TouchBarHardwareCapability.usesSoftwareWorkspace
            ? .floating
            : (currentWorkspaceSwitcherFloats ? .floating : .touchBar)
        switcherDisplayModePopup.selectItem(
            at: WorkspaceSwitcherDisplayMode.allCases.firstIndex(of: currentMode) ?? 0
        )
        // No physical bar: only the floating switcher is available.
        if TouchBarHardwareCapability.usesSoftwareWorkspace,
            let touchBarItem = switcherDisplayModePopup.item(
                at: WorkspaceSwitcherDisplayMode.allCases.firstIndex(of: .touchBar) ?? -1
            )
        {
            touchBarItem.isEnabled = false
        }

        let startupSceneLabel = NSTextField(labelWithString: "启动后进入")
        startupScenePopup.addItems(
            withTitles: WorkspaceStartupScene.allCases.map(\.title)
        )
        startupScenePopup.selectItem(
            at: WorkspaceStartupScene.allCases.firstIndex(
                of: currentWorkspaceStartupScene
            ) ?? 0
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

        let idleOpacityDelayLabel = NSTextField(labelWithString: "透明延迟")
        let secondsLabel = NSTextField(labelWithString: "秒（1–300）")
        let idleOpacityDelayFormatter = NumberFormatter()
        idleOpacityDelayFormatter.allowsFloats = false
        idleOpacityDelayFormatter.minimum = NSNumber(
            value: TouchBarIdleOpacity.minimumDelaySeconds
        )
        idleOpacityDelayFormatter.maximum = NSNumber(
            value: TouchBarIdleOpacity.maximumDelaySeconds
        )
        idleOpacityDelayField.formatter = idleOpacityDelayFormatter
        idleOpacityDelayField.alignment = .right
        idleOpacityDelayField.integerValue = currentIdleOpacityDelaySeconds

        let customAppsSectionLabel = NSTextField(labelWithString: "自定义 App")
        customAppsSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let customAppsHint = NSTextField(
            labelWithString: """
            Workspace 右侧最多 3 个常用应用；点图标打开，点齿轮打开本设置。\
            在此新增、替换或移除（不会自动挤掉已固定的应用）。
            """
        )
        customAppsHint.textColor = .secondaryLabelColor
        customAppsHint.maximumNumberOfLines = 3
        customAppsHint.lineBreakMode = .byWordWrapping

        customAppsStack.orientation = .vertical
        customAppsStack.alignment = .leading
        customAppsStack.spacing = 8
        customAppsStack.translatesAutoresizingMaskIntoConstraints = false

        let recentsSectionLabel = NSTextField(labelWithString: "最近项目")
        recentsSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let recentsHint = NSTextField(
            labelWithString: """
            Workspace 路径区点一下可选择最近用过的项目。\
            列表会自动记录；也可在此移除或清空。家目录不会出现在列表里。
            """
        )
        recentsHint.textColor = .secondaryLabelColor
        recentsHint.maximumNumberOfLines = 3
        recentsHint.lineBreakMode = .byWordWrapping
        recentsStack.orientation = .vertical
        recentsStack.alignment = .leading
        recentsStack.spacing = 8
        recentsStack.translatesAutoresizingMaskIntoConstraints = false

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

        let startupSceneRow = NSStackView(
            views: [startupSceneLabel, startupScenePopup]
        )
        startupSceneRow.orientation = .horizontal
        startupSceneRow.spacing = 12
        startupSceneRow.alignment = .centerY

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

        let idleOpacityDelayRow = NSStackView(
            views: [idleOpacityDelayLabel, idleOpacityDelayField, secondsLabel]
        )
        idleOpacityDelayRow.orientation = .horizontal
        idleOpacityDelayRow.spacing = 8
        idleOpacityDelayRow.alignment = .centerY

        let stack = NSStackView(
            views: [
                titleLabel,
                positionRow,
                originRow,
                switcherModeRow,
                startupSceneRow,
                workspaceAutoCollapseRow,
                terminalAdapterRow,
                sizeRow,
                framesPerSecondRow,
                idleOpacityDelayRow,
                customAppsSectionLabel,
                customAppsHint,
                customAppsStack,
                recentsSectionLabel,
                recentsHint,
                recentsStack,
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
            startupSceneLabel.widthAnchor.constraint(equalToConstant: 72),
            workspaceAutoCollapseRow.arrangedSubviews[0].widthAnchor.constraint(
                equalToConstant: 72
            ),
            terminalAdapterLabel.widthAnchor.constraint(equalToConstant: 72),
            sizeLabel.widthAnchor.constraint(equalToConstant: 72),
            framesPerSecondLabel.widthAnchor.constraint(equalToConstant: 72),
            idleOpacityDelayLabel.widthAnchor.constraint(equalToConstant: 72),
            positionPopup.widthAnchor.constraint(equalToConstant: 180),
            switcherDisplayModePopup.widthAnchor.constraint(equalToConstant: 180),
            startupScenePopup.widthAnchor.constraint(equalToConstant: 180),
            terminalAdapterPopup.widthAnchor.constraint(equalToConstant: 180),
            originXField.widthAnchor.constraint(equalToConstant: 70),
            originYField.widthAnchor.constraint(equalToConstant: 70),
            widthField.widthAnchor.constraint(equalToConstant: 90),
            heightField.widthAnchor.constraint(equalToConstant: 70),
            framesPerSecondField.widthAnchor.constraint(equalToConstant: 90),
            idleOpacityDelayField.widthAnchor.constraint(equalToConstant: 90),
            customAppsHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            customAppsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recentsHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recentsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
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
        startupScenePopup.target = self
        startupScenePopup.action = #selector(startupSceneChanged(_:))
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
        idleOpacityDelayField.target = self
        idleOpacityDelayField.action = #selector(idleOpacityDelayChanged(_:))
        updateCustomOriginFieldsEnabled(for: currentPosition)
        rebuildCustomAppsRows()
        rebuildRecentsRows()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed()
    }

    func reloadCustomAppsRows() {
        rebuildCustomAppsRows()
    }

    func reloadRecentsRows() {
        rebuildRecentsRows()
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
    private func startupSceneChanged(_ sender: NSPopUpButton) {
        let itemIndex = sender.indexOfSelectedItem
        guard WorkspaceStartupScene.allCases.indices.contains(itemIndex) else {
            return
        }
        onWorkspaceStartupSceneChanged(WorkspaceStartupScene.allCases[itemIndex])
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

    @objc
    private func idleOpacityDelayChanged(_ sender: NSTextField) {
        let seconds = TouchBarIdleOpacity.clampedDelaySeconds(
            sender.integerValue
        )
        idleOpacityDelayField.integerValue = seconds
        onIdleOpacityDelayChanged(seconds)
    }

    private func updateCustomOriginFieldsEnabled(for position: TouchBarDisplayPosition) {
        let enabled = position.usesCustomTopLeft
        originXField.isEnabled = enabled
        originYField.isEnabled = enabled
        originXField.alphaValue = enabled ? 1 : 0.5
        originYField.alphaValue = enabled ? 1 : 0.5
    }

    private func rebuildCustomAppsRows() {
        for view in customAppsStack.arrangedSubviews {
            customAppsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let apps = WorkspacePreferences.customApps
        for (index, app) in apps.enumerated() {
            customAppsStack.addArrangedSubview(
                makeCustomAppRow(app: app, index: index)
            )
        }

        if apps.count < CustomWorkspaceAppList.maxCount {
            let addButton = NSButton(
                title: "添加应用…",
                target: self,
                action: #selector(addCustomApp)
            )
            addButton.bezelStyle = .rounded
            customAppsStack.addArrangedSubview(addButton)
        } else {
            let fullHint = NSTextField(
                labelWithString:
                    "已满 \(CustomWorkspaceAppList.maxCount) 个，可替换或移除后再添加。"
            )
            fullHint.textColor = .secondaryLabelColor
            fullHint.font = .systemFont(ofSize: 11)
            customAppsStack.addArrangedSubview(fullHint)
        }

        if apps.isEmpty {
            let emptyHint = NSTextField(labelWithString: "尚未固定应用")
            emptyHint.textColor = .secondaryLabelColor
            emptyHint.font = .systemFont(ofSize: 12)
            customAppsStack.insertArrangedSubview(emptyHint, at: 0)
        }
    }

    private func makeCustomAppRow(app: CustomWorkspaceApp, index: Int) -> NSView {
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = WorkspaceTouchBarStyle.customAppIcon(for: app)
            ?? NSImage(
                systemSymbolName: "app.fill",
                accessibilityDescription: nil
            )
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: app.displayName)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let replaceButton = NSButton(
            title: "替换…",
            target: self,
            action: #selector(replaceCustomApp(_:))
        )
        replaceButton.bezelStyle = .rounded
        replaceButton.tag = index

        let removeButton = NSButton(
            title: "移除",
            target: self,
            action: #selector(removeCustomApp(_:))
        )
        removeButton.bezelStyle = .rounded
        removeButton.tag = index

        let row = NSStackView(views: [
            iconView,
            nameLabel,
            replaceButton,
            removeButton,
        ])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            nameLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        return row
    }

    @objc
    private func addCustomApp() {
        onPickApplication { [weak self] url in
            guard let self else { return }
            guard
                let url,
                let app = CustomWorkspaceApp.make(fromApplicationURL: url)
            else {
                return
            }
            guard
                let updated = CustomWorkspaceAppList.adding(
                    app,
                    to: WorkspacePreferences.customApps
                )
            else {
                self.presentCustomAppsFullAlert()
                return
            }
            WorkspacePreferences.customApps = updated
            self.rebuildCustomAppsRows()
            self.onCustomAppsChanged()
        }
    }

    @objc
    private func replaceCustomApp(_ sender: NSButton) {
        let index = sender.tag
        onPickApplication { [weak self] url in
            guard let self else { return }
            guard
                let url,
                let app = CustomWorkspaceApp.make(fromApplicationURL: url)
            else {
                return
            }
            guard
                let updated = CustomWorkspaceAppList.replacing(
                    at: index,
                    with: app,
                    in: WorkspacePreferences.customApps
                )
            else {
                return
            }
            WorkspacePreferences.customApps = updated
            self.rebuildCustomAppsRows()
            self.onCustomAppsChanged()
        }
    }

    @objc
    private func removeCustomApp(_ sender: NSButton) {
        let index = sender.tag
        guard
            let updated = CustomWorkspaceAppList.removing(
                at: index,
                from: WorkspacePreferences.customApps
            )
        else {
            return
        }
        WorkspacePreferences.customApps = updated
        rebuildCustomAppsRows()
        onCustomAppsChanged()
    }

    private func presentCustomAppsFullAlert() {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "自定义 App 已满"
        alert.informativeText =
            "最多固定 \(CustomWorkspaceAppList.maxCount) 个。请先移除或替换其中一个。"
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    private func rebuildRecentsRows() {
        for view in recentsStack.arrangedSubviews {
            recentsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let projects = WorkspacePreferences.recentProjects
        if projects.isEmpty {
            let emptyHint = NSTextField(labelWithString: "还没有最近项目")
            emptyHint.textColor = .secondaryLabelColor
            recentsStack.addArrangedSubview(emptyHint)
            return
        }

        for (index, project) in projects.enumerated() {
            recentsStack.addArrangedSubview(
                makeRecentProjectRow(project: project, index: index)
            )
        }
        let clearButton = NSButton(
            title: "清空最近项目",
            target: self,
            action: #selector(clearRecentProjects)
        )
        recentsStack.addArrangedSubview(clearButton)
    }

    private func makeRecentProjectRow(
        project: WorkspaceRecentProject,
        index: Int
    ) -> NSView {
        let nameLabel = NSTextField(labelWithString: project.url.lastPathComponent)
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.toolTip = project.path
        let pathLabel = NSTextField(labelWithString: project.path)
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        let labels = NSStackView(views: [nameLabel, pathLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let removeButton = NSButton(
            title: "移除",
            target: self,
            action: #selector(removeRecentProject(_:))
        )
        removeButton.tag = index
        let row = NSStackView(views: [labels, removeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            labels.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
        return row
    }

    @objc
    private func removeRecentProject(_ sender: NSButton) {
        let projects = WorkspacePreferences.recentProjects
        guard projects.indices.contains(sender.tag) else { return }
        WorkspacePreferences.recentProjects = WorkspaceRecentProjectList.removing(
            path: projects[sender.tag].path,
            from: projects
        )
        rebuildRecentsRows()
        onRecentsChanged()
    }

    @objc
    private func clearRecentProjects() {
        WorkspacePreferences.recentProjects = []
        rebuildRecentsRows()
        onRecentsChanged()
    }
}
