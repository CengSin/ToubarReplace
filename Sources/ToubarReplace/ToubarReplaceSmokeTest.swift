import CoreGraphics
import Foundation

enum ToubarReplaceSmokeTest {
    static func failures() -> [String] {
        var failures: [String] = []

        expect(
            TouchBarWindowMetrics.defaultSize
                == CGSize(width: 1_150, height: 35),
            "default mirror size changed unexpectedly",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.minimumSize.width
                < TouchBarWindowMetrics.defaultSize.width,
            "minimum mirror width must be below the default width",
            failures: &failures
        )
        expect(
            TouchBarWindowMetrics.pixelSize(
                forPointSize: CGSize(width: 1_150, height: 35),
                backingScaleFactor: 2
            ) == CGSize(width: 2_300, height: 70),
            "point-to-pixel conversion changed unexpectedly",
            failures: &failures
        )
        expect(
            TouchBarCapture.minimumFramesPerSecond == 1
                && TouchBarCapture.defaultFramesPerSecond == 30
                && TouchBarCapture.maximumFramesPerSecond == 30,
            "capture frame-rate bounds changed unexpectedly",
            failures: &failures
        )
        expect(
            TouchBarIdleOpacity.active == 1
                && TouchBarIdleOpacity.idle == 0.3
                && TouchBarIdleOpacity.delay == .seconds(5),
            "idle-opacity defaults changed unexpectedly",
            failures: &failures
        )
        expect(
            TouchBarSystemState.isControlStripExplicitlyEmpty(
                fullCustomized: [],
                miniCustomized: []
            ),
            "empty Control Strip must be detected",
            failures: &failures
        )
        expect(
            !TouchBarSystemState.isControlStripExplicitlyEmpty(
                fullCustomized: ["com.apple.system.volume"],
                miniCustomized: []
            ),
            "non-empty Control Strip must not be reported as empty",
            failures: &failures
        )
        expect(
            !TouchBarSystemState.isControlStripExplicitlyEmpty(
                fullCustomized: nil,
                miniCustomized: []
            ),
            "missing Control Strip settings must not be reported as empty",
            failures: &failures
        )

        for presentationMode in [
            "app",
            "appWithControlStrip",
            "quickActions",
            "quickActionsWithControlStrip",
            "workflows",
            "workflowsWithControlStrip",
        ] {
            expect(
                TouchBarSystemState.allowsEmptyContent(
                    presentationMode: presentationMode
                ),
                "\(presentationMode) must allow empty content",
                failures: &failures
            )
        }
        for presentationMode in [
            "fullControlStrip",
            "functionKeys",
            "spaces",
            "spacesWithControlStrip",
        ] {
            expect(
                !TouchBarSystemState.allowsEmptyContent(
                    presentationMode: presentationMode
                ),
                "\(presentationMode) must not allow empty content",
                failures: &failures
            )
        }
        expect(
            !TouchBarSystemState.allowsEmptyContent(presentationMode: nil),
            "missing presentation mode must not allow empty content",
            failures: &failures
        )

        return failures
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        failures: inout [String]
    ) {
        if !condition() {
            failures.append(message)
        }
    }
}
