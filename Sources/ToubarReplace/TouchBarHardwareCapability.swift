import Foundation
import TouchBarPrivateAPI

/// Runtime probe for a usable physical Touch Bar stack (stream + system modal).
///
/// Gate is **API availability only** — never CPU brand / `uname` / arm64.
/// Intel Macs with Touch Bar must keep `usesSoftwareWorkspace == false`.
enum TouchBarHardwareCapability {
    /// SkyLight exports the private DFR display-stream entry point.
    static var canCreateDisplayStream: Bool {
        TBRCanCreateTouchBarDisplayStream()
    }

    /// A stream object can be created (symbol alone is not enough on some builds).
    static var canInstantiateDisplayStream: Bool {
        TBRCanInstantiateTouchBarDisplayStream()
    }

    /// AppKit exposes system-modal present/dismiss selectors.
    static var canPresentSystemModal: Bool {
        TBRCanPresentSystemModalTouchBar()
    }

    /// No usable physical Touch Bar: drive Workspace on the desktop mirror instead.
    static var usesSoftwareWorkspace: Bool {
        softwareWorkspaceMode(
            canPresentSystemModal: canPresentSystemModal,
            canCreateDisplayStream: canCreateDisplayStream,
            canInstantiateDisplayStream: canInstantiateDisplayStream
        )
    }

    /// Pure policy for smoke tests (no private-API side effects).
    static func softwareWorkspaceMode(
        canPresentSystemModal: Bool,
        canCreateDisplayStream: Bool,
        canInstantiateDisplayStream: Bool
    ) -> Bool {
        !canPresentSystemModal
            || !canCreateDisplayStream
            || !canInstantiateDisplayStream
    }
}

/// When the mirror panel should ignore mouse events (click-through).
enum MirrorClickThroughPolicy {
    /// Interactive only while desktop Workspace fallback chrome is visible.
    /// Physical Workspace (system modal) keeps the mirror click-through.
    static func ignoresMouseEvents(
        usesSoftwareWorkspace: Bool,
        scene: BarScene,
        showsWorkspaceFallback: Bool
    ) -> Bool {
        _ = usesSoftwareWorkspace
        if scene == .workspace, showsWorkspaceFallback {
            return false
        }
        return true
    }
}

enum SoftwareWorkspaceLaunchPolicy {
    /// No physical bar → open Workspace immediately at launch.
    static func shouldEnterWorkspaceAtLaunch(usesSoftwareWorkspace: Bool) -> Bool {
        usesSoftwareWorkspace
    }

    /// Effective switcher placement: software mode always uses the floating window.
    static func effectiveSwitcherDisplayMode(
        usesSoftwareWorkspace: Bool,
        preferred: WorkspaceSwitcherDisplayMode
    ) -> WorkspaceSwitcherDisplayMode {
        usesSoftwareWorkspace ? .floating : preferred
    }
}

enum TouchBarResumeAction: Equatable {
    case restoreSoftwareWorkspace
    case restartHardwareCapture
}

enum TouchBarResumePolicy {
    static func action(usesSoftwareWorkspace: Bool) -> TouchBarResumeAction {
        usesSoftwareWorkspace ? .restoreSoftwareWorkspace : .restartHardwareCapture
    }
}
