import XCTest

final class ResponsiveLayoutTests: XCTestCase {
    func testImportantContentFitsTheWindow() {
        let app = XCUIApplication()
        let screens: [(String?, String)] = [(nil,"rj-home-title"),("--preview-radio","rj-radio-title"),("--preview-setup","rj-setup-title"),("--preview-delivery","rj-delivery-title")]
        for accessibility in [false, true] {
            for (argument, identifier) in screens {
                app.launchArguments = ["--preview"] + (argument.map { [$0] } ?? []) + (accessibility ? ["--preview-accessibility"] : [])
                app.launch()
                let title = app.staticTexts[identifier]
                XCTAssertTrue(title.waitForExistence(timeout: 8), identifier)
                XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX, identifier)
                XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX + 1, identifier)
                XCTAssertTrue(title.isHittable, identifier)
                app.terminate()
            }
        }
        app.launchArguments = ["--preview","--preview-recorder","--preview-draft"]
        app.launch()
        let send = app.buttons["duftpost-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 8))
        XCTContext.runActivity(named: "Recorder footer before interaction") { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
        XCTAssertTrue(send.isEnabled, "A completed unnamed draft must be enabled")
        XCTAssertTrue(send.isHittable, "Send must remain visible even on the smallest supported screen")
        XCTAssertGreaterThanOrEqual(send.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(send.frame.maxX, app.frame.maxX + 1)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.frame.maxY)
    }
}
