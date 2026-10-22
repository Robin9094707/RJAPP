import XCTest

final class DuftArchiveFlowTests: XCTestCase {
    func testCalendarYearMapAndSearchRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview","--preview-farts"]
        app.launch()
        XCTAssertTrue(app.staticTexts["duft-archive-title"].waitForExistence(timeout: 15))
        let calendar = app.segmentedControls["duft-room"].buttons["Kalender"]
        XCTAssertTrue(calendar.isHittable)
        calendar.tap()
        let heading = app.staticTexts["duft-calendar-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 8))
        let year = app.segmentedControls["duft-calendar-scale"].buttons["Jahr"]
        XCTAssertTrue(year.isHittable, "Calendar scale remains fixed above the scrolling archive")
        year.tap()
        XCTAssertTrue(heading.label.contains(String(Calendar.current.component(.year,from: .now))))
        let today = app.buttons["Heute anzeigen"]
        let scroll = app.scrollViews["duft-archive-scroll"]
        for _ in 0..<8 where !today.isHittable {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.75)).press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.35)))
        }
        XCTAssertTrue(today.isHittable)
        today.tap()
        let map = app.segmentedControls["duft-room"].buttons["Karte"]
        XCTAssertTrue(map.isHittable, "Rooms remain reachable after scrolling the calendar")
        map.tap()
        XCTAssertTrue(app.staticTexts["duft-map-title"].waitForExistence(timeout: 8))
        let collection = app.segmentedControls["duft-room"].buttons["Sammlung"]
        collection.tap()
        let search = app.searchFields.firstMatch
        for _ in 0..<4 where !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("XYZkeinLufttalent")
        let noHits = app.staticTexts["duft-results"]
        expectation(for: NSPredicate(format: "label == %@", "0 Treffer"), evaluatedWith: noHits)
        waitForExpectations(timeout: 8)
    }
    func testOldServerAndOldAppShowTheCorrectUpdateTarget() {
        let app = XCUIApplication()
        for kind in ["old","future"] {
            app.launchArguments = ["--preview","--preview-"+kind+"-server"]
            app.launch()
            let title = app.staticTexts[kind == "old" ? "Ein Update für euren Server." : "Zeit für die neue App."]
            XCTAssertTrue(title.waitForExistence(timeout: 12))
            app.terminate()
        }
    }
    func testRecorderHasASituationAndAnOfflineQuip() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview","--preview-recorder","--preview-empty-recorder"]
        app.launch()
        let quote = app.staticTexts["duft-quip"]
        XCTAssertTrue(quote.waitForExistence(timeout: 15))
        XCTAssertFalse(quote.label.isEmpty)
        let mic = app.buttons["Aufnahme starten"]
        XCTAssertTrue(mic.isHittable,"The record control stays outside the scroll content")
        let shuffle = app.buttons["Anderen Spruch zeigen"]
        for _ in 0..<3 where !shuffle.isHittable { app.swipeUp() }
        let previous = quote.label
        shuffle.tap()
        XCTAssertNotEqual(previous,quote.label)
    }
}
