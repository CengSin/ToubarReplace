import CoreGraphics
import Foundation
@testable import ToubarReplace

// Kept framework-free because this Command Line Tools installation does not
// expose XCTest or Swift Testing to macOS test targets. SwiftPM still compiles
// the assertions together with the test target.
func toubarReplaceGeometrySmokeTest() {
    precondition(
        TouchBarWindowMetrics.defaultSize == CGSize(width: 1_150, height: 35)
    )
    precondition(
        TouchBarWindowMetrics.minimumSize.width
            < TouchBarWindowMetrics.defaultSize.width
    )
    precondition(
        TouchBarWindowMetrics.pixelSize(
            forPointSize: CGSize(width: 1_150, height: 35),
            backingScaleFactor: 2
        ) == CGSize(width: 2_300, height: 70)
    )
    precondition(TouchBarCapture.minimumFramesPerSecond == 1)
    precondition(TouchBarCapture.defaultFramesPerSecond == 12)
    precondition(TouchBarCapture.maximumFramesPerSecond == 30)
    precondition(TouchBarIdleOpacity.active == 1)
    precondition(TouchBarIdleOpacity.idle == 0.3)
    precondition(TouchBarIdleOpacity.delay == .seconds(5))
    precondition(
        TouchBarSystemState.isControlStripExplicitlyEmpty(
            fullCustomized: [],
            miniCustomized: []
        )
    )
    precondition(
        !TouchBarSystemState.isControlStripExplicitlyEmpty(
            fullCustomized: ["com.apple.system.volume"],
            miniCustomized: []
        )
    )
    precondition(
        !TouchBarSystemState.isControlStripExplicitlyEmpty(
            fullCustomized: nil,
            miniCustomized: []
        )
    )
    for contextualMode in [
        "app",
        "appWithControlStrip",
        "quickActions",
        "quickActionsWithControlStrip",
        "workflows",
        "workflowsWithControlStrip",
    ] {
        precondition(
            TouchBarSystemState.allowsEmptyContent(
                presentationMode: contextualMode
            )
        )
    }
    for fixedMode in [
        "fullControlStrip",
        "functionKeys",
        "spaces",
        "spacesWithControlStrip",
    ] {
        precondition(
            !TouchBarSystemState.allowsEmptyContent(
                presentationMode: fixedMode
            )
        )
    }
    precondition(
        !TouchBarSystemState.allowsEmptyContent(presentationMode: nil)
    )
}
