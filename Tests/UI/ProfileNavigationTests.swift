import XCTest

final class ProfileNavigationTests:XCTestCase {
    func testProfileStatusCanOpenAndReturnTwice() {
        let app=XCUIApplication();app.launchArguments=["--preview"];app.launch()
        let profile=app.buttons["home-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout:15));profile.tap()
        let status=app.buttons["settings-status"]
        XCTAssertTrue(status.waitForExistence(timeout:10))
        for _ in 0..<2 {
            status.tap()
            XCTAssertTrue(app.textFields["status-text"].waitForExistence(timeout:8))
            XCTAssertTrue(app.buttons["Status teilen"].isHittable)
            let bar=app.navigationBars["Mein Status"]
            XCTAssertTrue(bar.exists)
            let capture=XCTAttachment(screenshot:app.screenshot());capture.name="Status-Navigation";capture.lifetime = .keepAlways;add(capture)
            bar.buttons.element(boundBy:0).tap()
            XCTAssertTrue(status.waitForExistence(timeout:8));XCTAssertTrue(status.isHittable)
        }
        app.buttons["Fertig"].tap()
        XCTAssertTrue(profile.waitForExistence(timeout:8));XCTAssertTrue(profile.isHittable)
    }
}
