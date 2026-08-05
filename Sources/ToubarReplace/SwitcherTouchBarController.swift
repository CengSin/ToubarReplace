import AppKit

@MainActor
final class SwitcherTouchBarController: NSObject, NSTouchBarDelegate {
    let touchBar = NSTouchBar()
    var onToggleWorkspace: (() -> Void)?

    override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            NSTouchBarItem.Identifier(rawValue: "com.toubarreplace.switcher")
        ]
        touchBar.customizationAllowedItemIdentifiers = []
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        if identifier.rawValue == "com.toubarreplace.switcher" {
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.customizationLabel = "Workspace"
            item.view = createSwitchButton()
            return item
        }
        return nil
    }

    private func createSwitchButton() -> NSView {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: "打开 Workspace"
        )
        button.contentTintColor = NSColor.white
        button.isBordered = false
        button.bezelStyle = .texturedRounded
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.widthAnchor.constraint(equalToConstant: 64).isActive = true
        button.heightAnchor.constraint(equalToConstant: 64).isActive = true
        button.target = self
        button.action = #selector(toggleWorkspace)
        button.toolTip = "点击切换 Workspace 模式"
        return button
    }

    @objc private func toggleWorkspace() {
        onToggleWorkspace?()
    }
}
