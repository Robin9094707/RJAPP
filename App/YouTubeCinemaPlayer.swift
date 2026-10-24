import SwiftUI
import WebKit

/// A single official player is reparented between phone and external scene.
/// No stream extraction, hidden background player or overlays over the video.
@MainActor final class YouTubeCinemaPlayer: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    var stateChanged: ((Bool, Double) -> Void)?
    var failed: ((String) -> Void)?
    var intentChanged: ((Bool, Double) -> Void)?
    private var ready = false
    private var video = ""
    private var target: (Double, Bool)?
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(WeakYouTubeHandler(self), name: "cinema")
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
    }
    func load(_ id: String) {
        ready = false; video = id; target = nil
        let origin = "https://" + (Bundle.main.bundleIdentifier ?? "eu.rjuhas.rjlove").lowercased()
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="strict-origin-when-cross-origin"><style>html,body{margin:0;width:100%;height:100%;background:#000}#player{width:100%;height:100%}</style></head><body><div id="player"></div><script>
        let player,ready=false;
        function send(v){window.webkit.messageHandlers.cinema.postMessage(v)}
        function onYouTubeIframeAPIReady(){player=new YT.Player('player',{videoId:'\(id)',playerVars:{playsinline:1,origin:'\(origin)'},events:{onReady:()=>{ready=true;send({ready:true})},onStateChange:e=>send({playing:e.data===1,position:player.getCurrentTime(),intent:e.data===1||e.data===2}),onError:e=>send({error:e.data})}})}
        function sync(position,playing){if(!ready)return;if(Math.abs(player.getCurrentTime()-position)>2.5)player.seekTo(position,true);if(playing){if(player.getPlayerState()!==1)player.playVideo()}else if(player.getPlayerState()===1)player.pauseVideo()}
        setInterval(()=>{if(ready)send({playing:player.getPlayerState()===1,position:player.getCurrentTime()})},1000);
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: origin))
    }
    func sync(position: Double, playing: Bool) {
        target = (position, playing)
        guard ready, position.isFinite else { return }
        webView.evaluateJavaScript("sync(\(max(0, position)),\(playing ? "true" : "false"))", completionHandler: nil)
    }
    func pause() { target = nil; webView.evaluateJavaScript("if(ready)player.pauseVideo()", completionHandler: nil) }
    func stop() { pause(); webView.loadHTMLString("<html style='background:black'></html>", baseURL: nil); ready = false; video = ""; target = nil }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? [String: Any] else { return }
        if value["ready"] as? Bool == true { ready = true; if let target { sync(position: target.0, playing: target.1) } }
        if let code = value["error"] as? Int { failed?("YouTube-Player: Fehler \(code). Das Video kann eingebettete Wiedergabe sperren. Bei Fehler 153 die App unverändert mit derselben Bundle-ID signieren.") }
        if let playing = value["playing"] as? Bool, let position = value["position"] as? Double { stateChanged?(playing, position); if value["intent"] as? Bool == true { intentChanged?(playing, position) } }
    }
}
@MainActor private final class WeakYouTubeHandler: NSObject, WKScriptMessageHandler {
    weak var target: YouTubeCinemaPlayer?
    init(_ target: YouTubeCinemaPlayer) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { target?.userContentController(userContentController, didReceive: message) }
}
struct CinemaYouTubeSurface: UIViewRepresentable {
    let engine: YouTubeCinemaPlayer
    func makeUIView(context: Context) -> UIView {
        let host = UIView(); host.backgroundColor = .black
        return host
    }
    func updateUIView(_ host: UIView, context: Context) {
        let video = engine.webView
        if video.superview !== host {
            video.removeFromSuperview(); host.addSubview(video)
            video.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([video.leadingAnchor.constraint(equalTo: host.leadingAnchor), video.trailingAnchor.constraint(equalTo: host.trailingAnchor), video.topAnchor.constraint(equalTo: host.topAnchor), video.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        }
    }
}
