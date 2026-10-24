import XCTest
final class CinemaFlowTests: XCTestCase {
    func testPrivateMediaAndTVNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--preview", "--preview-cinema"]; app.launch()
        let selector = app.segmentedControls["cinema-section"]
        XCTAssertTrue(selector.waitForExistence(timeout: 20))
        selector.buttons["Plex"].tap()
        XCTAssertTrue(app.buttons["Mit Plex verbinden"].waitForExistence(timeout: 5))
        let plex = XCTAttachment(screenshot: app.screenshot()); plex.name = "Kino-Plex"; plex.lifetime = .keepAlways; add(plex)
        selector.buttons["AirPlay"].tap()
        XCTAssertTrue(app.staticTexts["Fernseher verbinden"].waitForExistence(timeout: 5))
        let tv = XCTAttachment(screenshot: app.screenshot()); tv.name = "Kino-AirPlay"; tv.lifetime = .keepAlways; add(tv)
        selector.buttons["YouTube"].tap()
        XCTAssertTrue(app.buttons["cinema-youtube-consent"].exists || app.textFields["cinema-youtube-query"].exists)
        let youtube = XCTAttachment(screenshot: app.screenshot()); youtube.name = "Kino-YouTube"; youtube.lifetime = .keepAlways; add(youtube)
    }
}
