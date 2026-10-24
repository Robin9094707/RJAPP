import XCTest
final class VideoAudioSessionTests:XCTestCase {
    func testVideoAudioSessionAndPageOwnership(){
        let app=XCUIApplication();app.launchArguments=["--preview","--verify-video-audio"];app.launch()
        let report=app.staticTexts["video-audio-result"]
        XCTAssertTrue(report.waitForExistence(timeout:20))
        let passed=NSPredicate(format:"label == %@","VIDEO_AUDIO_CHECKS_PASSED")
        expectation(for:passed,evaluatedWith:report);waitForExpectations(timeout:20)
    }
}
