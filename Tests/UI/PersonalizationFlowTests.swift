import XCTest

final class PersonalizationFlowTests: XCTestCase {
    func testAllExperienceSectionsCanBeTapped() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-farts"]
        app.launch()
        for title in ["Momente", "Liebe", "Duftpost", "Momente"] {
            let tab = app.buttons["experience-" + title]
            XCTAssertTrue(tab.waitForExistence(timeout: 12))
            tab.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: tab)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, title)
        }
        XCTAssertTrue(app.buttons["Moment hinzufügen"].firstMatch.isHittable)
        app.buttons["Moment hinzufügen"].firstMatch.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'Abbrechen'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "The actual system media picker opens without terminating the app")
        cancel.tap()
        XCTAssertTrue(app.buttons["experience-Momente"].waitForExistence(timeout: 10))
    }
    func testHomeTitleIsSavedOnServerAndRestoredAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ui-test-server"]
        app.launch()
        let customize = app.buttons["home-customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 12)); customize.tap()
        let title = app.textFields["home-edit-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap()
        let previous = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "Mein gemeinsames Wir\n")
        app.buttons["home-layout-save"].tap()
        let heading = app.staticTexts["rj-home-title"]
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Mein gemeinsames Wir"), object: heading)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed)
        app.terminate(); app.launch()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Mein gemeinsames Wir"), object: app.staticTexts["rj-home-title"])
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 15), .completed)
    }
    func testPhotoWishIsSentThroughTheRealAPI() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-instant-gallery", "--ui-test-server"]
        app.launch()
        let request = app.buttons["Ein Foto wünschen"]
        XCTAssertTrue(request.waitForExistence(timeout: 12)); request.tap()
        app.alerts.buttons["Wünschen"].tap()
        XCTAssertTrue(app.staticTexts["photo-request-sent"].waitForExistence(timeout: 15))
    }
    func testImmediateCameraFixtureUploadsAndCommitsTheReply() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-instant-gallery", "--preview-instant-camera", "--ui-test-server"]
        app.launch()
        let caption = app.staticTexts["instant-photo-caption"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 30), "The reply is shown only after the real binary upload and authenticated photo-request commit")
        XCTAssertEqual(caption.label, "Bitte lächeln · UI")
    }
}
