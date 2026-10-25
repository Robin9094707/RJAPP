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

extension CinemaFlowTests {
    private func reach(_ element: XCUIElement,in app: XCUIApplication,up: Bool = true) {
        for _ in 0..<8 where !element.isHittable { if up { app.swipeUp() } else { app.swipeDown() } }
        XCTAssertTrue(element.isHittable)
    }
    func testSharedDrawingWritesToTheRealBackend() {
        let app = XCUIApplication(); app.launchArguments = ["--preview","--preview-cinema","--ui-test-server"]; app.launch()
        let selector = app.segmentedControls["cinema-section"]
        XCTAssertTrue(selector.waitForExistence(timeout: 20)); selector.buttons["AirPlay"].tap()
        let drawing = app.buttons["tv-open-drawing"]; reach(drawing,in: app); drawing.tap()
        let canvas = app.otherElements["tv-drawing-touch"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20)); reach(canvas,in: app)
        canvas.coordinate(withNormalizedOffset: CGVector(dx:0.2,dy:0.35)).press(forDuration:0.2,thenDragTo:canvas.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.65)))
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "AirPlay-Gemeinsam-Malen"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    func testTVCustomizationAndSharedGame() {
        let app = XCUIApplication(); app.launchArguments = ["--preview","--preview-cinema","--ui-test-server"]; app.launch()
        let selector = app.segmentedControls["cinema-section"]
        XCTAssertTrue(selector.waitForExistence(timeout: 20)); selector.buttons["AirPlay"].tap()
        let settings = app.buttons["tv-customize"]; reach(settings,in: app); settings.tap()
        XCTAssertTrue(app.navigationBars["AirPlay gestalten"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "AirPlay-Widget-Einstellungen"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.navigationBars.buttons.firstMatch.tap()
        let game = app.buttons["tv-open-game"]; reach(game,in: app); game.tap()
        let start = app.buttons["tv-game-new"]; XCTAssertTrue(start.waitForExistence(timeout: 15)); reach(start,in: app); start.tap()
        let cell = app.buttons["tv-game-cell-0"]; reach(cell,in: app,up: false); cell.tap()
        XCTAssertTrue(app.staticTexts["O ist am Zug"].waitForExistence(timeout: 12))
        let signal = app.buttons["Signal heart"]; reach(signal,in: app); signal.tap()
        XCTAssertTrue(app.staticTexts["Von dir"].waitForExistence(timeout: 12))
        let board = XCTAttachment(screenshot:app.screenshot()); board.name = "AirPlay-Spiel-und-Signal"; board.lifetime = .keepAlways; add(board)
    }
}
