import Observation
import SwiftUI
import WebKit

struct YouTubeWebDestination: Identifiable { let id = UUID(); let url: URL }

/// First-party pages render inside the app. No Safari preview or shared cookies.
struct YouTubeWebBrowser: View {
    let url: URL
    let together: Bool
    var selected: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = YouTubePageState()
    var body: some View {
        NavigationStack {
            YouTubePage(url: url, state: page)
                .navigationTitle("YouTube").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button { page.webView?.goBack() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Zurück") }
                    ToolbarItem(placement: .bottomBar) {
                        Button(together ? "Dieses Video mit Schatzi schauen" : "Dieses Video abspielen",systemImage: "play.fill") {
                            guard let id = page.videoID else { return }
                            page.webView?.evaluateJavaScript("document.querySelectorAll('video').forEach(v=>v.pause())")
                            selected(id,page.title,together); dismiss()
                        }.disabled(page.videoID == nil)
                    }
                }
                .safeAreaInset(edge: .bottom) { if let error = page.error { Text(error).font(.caption).padding(10).background(.regularMaterial) } }
        }.onDisappear { Task { await NativeYouTubeService.shared.refreshCookies() } }
    }
}
@MainActor @Observable private final class YouTubePageState {
    var videoID: String?
    var title = "YouTube"
    var error: String?
    weak var webView: WKWebView?
}
private struct YouTubePage: UIViewRepresentable {
    let url: URL
    let state: YouTubePageState
    func makeCoordinator() -> Coordinator { Coordinator(state) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = NativeYouTubeService.shared.dataStore
        configuration.allowsInlineMediaPlayback = true; configuration.allowsAirPlayForMediaPlayback = true
        let view = WKWebView(frame: .zero,configuration: configuration)
        view.navigationDelegate = context.coordinator; view.allowsBackForwardNavigationGestures = true
        state.webView = view
        context.coordinator.observation = view.observe(\.url, options: [.new]) { web, _ in Task { @MainActor in state.videoID = web.url.flatMap { YouTubeLink.videoID($0.absoluteString) }; state.title = web.title ?? "YouTube" } }
        view.load(URLRequest(url: url)); return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let state: YouTubePageState
        var observation: NSKeyValueObservation?
        init(_ state: YouTubePageState) { self.state = state }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state.title = webView.title ?? "YouTube"; state.videoID = webView.url.flatMap { YouTubeLink.videoID($0.absoluteString) } }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, let host = url.host?.lowercased(), url.scheme == "https",
                  host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "google.com" || host.hasSuffix(".google.com") || host == "youtu.be" else { decisionHandler(.cancel); return }
            if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel); return }
            state.error = nil; decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { state.error = "YouTube konnte nicht geladen werden: " + error.localizedDescription } }
    }
}
