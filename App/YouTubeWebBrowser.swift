import SafariServices
import SwiftUI

struct YouTubeWebDestination: Identifiable {
    let id = UUID()
    let url: URL
}
/// The real YouTube website handles sign-in, subscriptions and Premium itself.
/// Only a video URL explicitly shared by the user crosses into RJ Love.
struct YouTubeWebBrowser: UIViewControllerRepresentable {
    let url: URL
    let together: Bool
    var selected: (String, String, Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(together: together, selected: selected) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let browser = SFSafariViewController(url: url,configuration: configuration)
        browser.delegate = context.coordinator
        browser.preferredControlTintColor = .systemPink
        browser.dismissButtonStyle = .done
        return browser
    }
    func updateUIViewController(_ browser: SFSafariViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let together: Bool
        let selected: (String, String, Bool) -> Void
        init(together: Bool,selected: @escaping (String,String,Bool) -> Void) { self.together = together; self.selected = selected }
        func safariViewController(_ controller: SFSafariViewController,activityItemsFor URL: URL,title: String?) -> [UIActivity] {
            guard let id = YouTubeLink.videoID(URL.absoluteString) else { return [] }
            return [YouTubeWatchActivity(id: id,title: title ?? "YouTube",together: together) { [weak self,weak controller] id,title,together in
                self?.selected(id,title,together)
                controller?.dismiss(animated: true)
            }]
        }
    }
}
@MainActor private final class YouTubeWatchActivity: UIActivity {
    let id: String
    let videoTitle: String
    let together: Bool
    let selected: (String,String,Bool) -> Void
    init(id: String,title: String,together: Bool,selected: @escaping (String,String,Bool)->Void) { self.id = id; videoTitle = title; self.together = together; self.selected = selected }
    override var activityType: UIActivity.ActivityType? { .init("eu.rjuhas.rjlove.watch") }
    override var activityTitle: String? { together ? "Mit Schatzi schauen" : "In RJ Love abspielen" }
    override var activityImage: UIImage? { UIImage(systemName: "play.tv.fill") }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }
    override func perform() { selected(id,videoTitle,together); activityDidFinish(true) }
}
