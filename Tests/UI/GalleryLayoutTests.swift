import XCTest
final class GalleryLayoutTests:XCTestCase {
    func testThreeSquareColumns(){
        let app=XCUIApplication();app.launchArguments=["--preview","--preview-gallery"];app.launch()
        let tiles=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'gallery-tile-'"))
        XCTAssertTrue(tiles.element(boundBy:2).waitForExistence(timeout:20))
        let a=tiles.element(boundBy:0).frame,b=tiles.element(boundBy:1).frame,c=tiles.element(boundBy:2).frame
        XCTAssertEqual(a.width,a.height,accuracy:1)
        XCTAssertEqual(b.width,b.height,accuracy:1)
        XCTAssertEqual(c.width,c.height,accuracy:1)
        XCTAssertEqual(a.minY,b.minY,accuracy:1);XCTAssertEqual(a.minY,c.minY,accuracy:1)
        XCTAssertLessThan(a.maxX,b.minX);XCTAssertLessThan(b.maxX,c.minX)
        let image=XCTAttachment(screenshot:app.screenshot());image.name="Three-square-columns";image.lifetime = .keepAlways;add(image)
    }
}
