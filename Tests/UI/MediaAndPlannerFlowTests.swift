import XCTest
final class MediaAndPlannerFlowTests:XCTestCase {
    func testPhotoUsesTheRealBinaryUploadAndRecordCommit() {
        let app=XCUIApplication()
        app.launchArguments=["--preview","--preview-media-composer","--ui-test-server"]
        app.launch()
        let share=app.buttons["Teilen"]
        XCTAssertTrue(share.waitForExistence(timeout:12))
        XCTAssertTrue(share.isEnabled)
        share.tap()
        XCTAssertTrue(app.staticTexts["media-upload-complete"].waitForExistence(timeout:30),"Completion is shown only after the binary upload and authenticated moment commit")
    }
    private func tapSwitch(_ element:XCUIElement){
        let thumb=element.switches.firstMatch
        if thumb.exists {thumb.tap()} else {element.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()}
    }
    func testAnnualPlanCanBeCreatedWithoutForcingApplePermissions() {
        let app=XCUIApplication()
        app.launchArguments=["--preview","--preview-planner","--ui-test-server"]
        app.launch()
        let add=app.buttons["Gemeinsam etwas planen"]
        for _ in 0..<5 where !add.isHittable{app.swipeUp()}
        XCTAssertTrue(add.isHittable)
        add.tap()
        let title=app.textFields["Zum Beispiel: Unser Jahrestag"]
        XCTAssertTrue(title.waitForExistence(timeout:10));title.tap();title.typeText("Unser UI-Jahrestag\n")
        let yearly=app.switches["Jedes Jahr"]
        for _ in 0..<5 where !yearly.isHittable{app.swipeUp()}
        tapSwitch(yearly)
        XCTAssertEqual(yearly.value as? String,"1")
        for label in ["In Apple Kalender synchronisieren","In Apple Erinnerungen synchronisieren"] {
            let toggle=app.switches[label]
            for _ in 0..<5 where !toggle.isHittable{app.swipeUp()}
            if toggle.value as? String == "1"{tapSwitch(toggle)}
            XCTAssertEqual(toggle.value as? String,"0",label)
        }
        app.buttons["Speichern"].tap()
        XCTAssertTrue(app.staticTexts["Unser UI-Jahrestag"].waitForExistence(timeout:20))
    }
}
