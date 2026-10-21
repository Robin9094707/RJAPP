import XCTest

final class RecorderFlowTests: XCTestCase {
    func testUnnamedTrimmedRecordingCanBeSent() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-recorder", "--preview-draft", "--ui-test-server"]
        app.launch()
        let slider = app.sliders["Schnittanfang"]
        for _ in 0..<4 where !slider.isHittable { app.swipeUp() }
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.15)
        let send = app.buttons["duftpost-send"]
        for _ in 0..<4 where !send.isHittable { app.swipeUp() }
        XCTAssertTrue(send.isEnabled, "An unnamed completed recording must be sendable")
        send.tap()
        let ready = app.staticTexts["Bühne frei."]
        for _ in 0..<4 where !ready.isHittable { app.swipeDown() }
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "Upload must finish and clear the draft")
        XCTAssertFalse(app.buttons["duftpost-send"].exists)
    }
}
