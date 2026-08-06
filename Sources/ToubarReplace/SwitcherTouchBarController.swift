import AppKit
import TouchBarPrivateAPI

@MainActor
final class SwitcherTouchBarController: NSObject, NSTouchBarDelegate {
    private enum ItemIdentifier {
        static let switcher = NSTouchBarItem.Identifier(
            "com.toubarreplace.switcher"
        )
    }

    // Placement 0 tends to put the item toward the left of the app region.
    private static let placement: Int64 = 0

    let touchBar = NSTouchBar()
    private(set) var isPresented = false
    var onToggleWorkspace: (() -> Void)?

    override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [ItemIdentifier.switcher]
        touchBar.customizationAllowedItemIdentifiers = []
    }

    func present() {
        guard !isPresented else { return }
        guard TBRCanPresentSystemModalTouchBar() else { return }

        isPresented = true
        TBRSetSystemModalShowsCloseBoxWhenFrontMost(false)
        TBRPresentSystemModalTouchBar(touchBar, Self.placement)
        TBRHideSystemModalCloseButton()
    }

    func dismiss() {
        guard isPresented else { return }
        TBRDismissSystemModalTouchBar(touchBar)
        TBRSetSystemModalShowsCloseBoxWhenFrontMost(true)
        isPresented = false
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == ItemIdentifier.switcher else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "Workspace"
        item.view = createSwitchButton()
        return item
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
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        button.target = self
        button.action = #selector(toggleWorkspace)
        button.toolTip = "点击打开 Workspace"
        button.setAccessibilityLabel("打开 Workspace")
        return button
    }

    @objc
    private func toggleWorkspace() {
        onToggleWorkspace?()
    }
}
