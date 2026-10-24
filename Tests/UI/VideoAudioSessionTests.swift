import XCTest
final class VideoAudioSessionTests:XCTestCase {
    func testVideoAudioSessionAndPageOwnership(){
        let app=XCUIApplication();app.launchArguments=["--preview","--verify-video-audio"];app.launch()
        // RootView's identifier is inherited by this single accessibility leaf.
        // Match the actual result label instead of the inherited identifier.
        let report=app.staticTexts.matching(NSPredicate(format:"label == %@ OR label BEGINSWITH %@","VIDEO_AUDIO_CHECKS_PASSED","FAIL:")).firstMatch
        guard report.waitForExistence(timeout:20) else{XCTFail(app.debugDescription);return}
        XCTAssertEqual(report.label,"VIDEO_AUDIO_CHECKS_PASSED")
    }
}
