import AppKit
import TouchBarPrivateAPI

/// Mirror-mode physical Touch Bar: a single grid button (placement 0).
///
/// Opening Settings makes the app frontmost, which can re-show the system-modal
/// close box. If the user taps it, the system dismisses the bar while
/// `isPresented` would otherwise stay true — we suppress the close box on
/// activation and re-present after unexpected detachment.
@MainActor
final class SwitcherTouchBarController: NSObject, NSTouchBarDelegate {
    private enum ItemIdentifier {
        static let switcher = NSTouchBarItem.Identifier(
            "com.toubarreplace.switcher"
        )
    }

    // Placement 0 tends to put the item toward the left of the app region and
    // keeps the system Control Strip available.
    private static let placement: Int64 = 0

    let touchBar = NSTouchBar()
    private let hostView = SwitcherTouchBarHostView()
    private var hasAttachedToTouchBarWindow = false
    private var isExplicitlyDismissing = false
    private var detachmentTask: Task<Void, Never>?
    private(set) var isPresented = false
    var onToggleWorkspace: (() -> Void)?
    /// System dismissed the bar (e.g. close box) without `dismiss()`.
    var onPresentationInterrupted: (() -> Void)?

    override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [ItemIdentifier.switcher]
        touchBar.customizationAllowedItemIdentifiers = []
        hostView.onToggle = { [weak self] in
            self?.onToggleWorkspace?()
        }
        hostView.onWindowAttachmentChanged = { [weak self] attached in
            self?.handleWindowAttachmentChanged(attached)
        }
    }

    func present() {
        guard !isPresented else {
            suppressCloseBox()
            return
        }
        guard TBRCanPresentSystemModalTouchBar() else { return }

        detachmentTask?.cancel()
        hasAttachedToTouchBarWindow = false
        isExplicitlyDismissing = false
        isPresented = true
        TBRSetSystemModalShowsCloseBoxWhenFrontMost(false)
        TBRPresentSystemModalTouchBar(touchBar, Self.placement)
        suppressCloseBox()
    }

    func dismiss() {
        guard isPresented else { return }
        isExplicitlyDismissing = true
        detachmentTask?.cancel()
        detachmentTask = nil
        TBRDismissSystemModalTouchBar(touchBar)
        TBRSetSystemModalShowsCloseBoxWhenFrontMost(true)
        hasAttachedToTouchBarWindow = false
        isPresented = false
        isExplicitlyDismissing = false
    }

    /// Re-apply close-box suppression after the app becomes frontmost
    /// (settings, help, open panels).
    func suppressCloseBox() {
        guard isPresented else { return }
        TBRSetSystemModalShowsCloseBoxWhenFrontMost(false)
        TBRHideSystemModalCloseButton()
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == ItemIdentifier.switcher else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "Workspace"
        item.view = hostView
        return item
    }

    private func handleWindowAttachmentChanged(_ attached: Bool) {
        detachmentTask?.cancel()
        detachmentTask = nil
        if attached {
            guard isPresented else { return }
            hasAttachedToTouchBarWindow = true
            suppressCloseBox()
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
            guard
                self.isPresented,
                self.hasAttachedToTouchBarWindow,
                !self.isExplicitlyDismissing,
                self.hostView.window == nil
            else {
                return
            }
            self.hasAttachedToTouchBarWindow = false
            self.isPresented = false
            TBRSetSystemModalShowsCloseBoxWhenFrontMost(true)
            self.onPresentationInterrupted?()
        }
    }
}

@MainActor
private final class SwitcherTouchBarHostView: NSView {
    var onWindowAttachmentChanged: ((Bool) -> Void)?
    var onToggle: (() -> Void)?

    private let button = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.image = NSImage(
            systemSymbolName: "square.grid.2x2",
            accessibilityDescription: "打开 Workspace"
        )
        button.contentTintColor = NSColor.white
        button.isBordered = false
        button.bezelStyle = .texturedRounded
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.toolTip = "点击打开 Workspace"
        button.setAccessibilityLabel("打开 Workspace")
        button.target = self
        button.action = #selector(toggle)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowAttachmentChanged?(window != nil)
    }

    @objc
    private func toggle() {
        onToggle?()
    }
}
