import XCTest

final class ProfileNavigationTests:XCTestCase {
    func testServerPlaylistAdvancesAndSurvivesLeavingView() {
        let app=XCUIApplication();app.launchArguments=["--preview","--ui-test-server"];app.launch()
        let shortcut=app.buttons["shortcut-playlist"]
        XCTAssertTrue(shortcut.waitForExistence(timeout:15));shortcut.tap()
        let start=app.buttons["evening-start"]
        XCTAssertTrue(start.waitForExistence(timeout:15))
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:start)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:15),.completed);start.tap()
        let current=app.descendants(matching:.any)["evening-current-title"]
        XCTAssertTrue(current.waitForExistence(timeout:10))
        let advanced=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == 'UI-Abend 2' OR label == 'UI-Abend 3'"),object:current)
        XCTAssertEqual(XCTWaiter.wait(for:[advanced],timeout:30),.completed,"The server-only audio queue must advance automatically")
        let capture=XCTAttachment(screenshot:app.screenshot());capture.name="Server-Playlist";capture.lifetime = .keepAlways;add(capture)
        app.navigationBars["Euer Abend"].buttons.element(boundBy:0).tap()
        XCTAssertTrue(app.staticTexts["Euer Abend läuft"].waitForExistence(timeout:10))
        app.buttons["shortcut-playlist"].tap()
        XCTAssertTrue(app.descendants(matching:.any)["evening-current-title"].waitForExistence(timeout:10))
        app.buttons["Beenden"].tap()
    }
    func testProfileStatusCanOpenAndReturnTwice() {
        let app=XCUIApplication();app.launchArguments=["--preview"];app.launch()
        let profile=app.buttons["home-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout:15));profile.tap()
        let status=app.buttons["settings-status"]
        XCTAssertTrue(status.waitForExistence(timeout:10))
        for _ in 0..<2 {
            status.tap()
            XCTAssertTrue(app.descendants(matching:.any)["status-text"].waitForExistence(timeout:8))
            XCTAssertTrue(app.buttons["Status teilen"].exists)
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
