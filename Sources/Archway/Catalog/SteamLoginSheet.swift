import SwiftUI
import WebKit

/// Steam's login page in a web view. Finishes once Steam has redirected away from the login page
/// and the session hands out a Web API token.
struct SteamLoginSheet: View {
    let onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Sign In to Steam", systemImage: "lock.fill").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            SteamLoginWebView(onSignedIn: onSignedIn)
        }
        .frame(width: 560, height: 720)
    }
}

private struct SteamLoginWebView: NSViewRepresentable {
    let onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn: onSignedIn) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = SteamSession.dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Steam's login page expects a regular browser.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: SteamSession.loginURL))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSignedIn: () -> Void
        private var didFinish = false

        init(onSignedIn: @escaping () -> Void) { self.onSignedIn = onSignedIn }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didFinish, let url = webView.url, url.host?.hasSuffix("steampowered.com") == true,
                  !url.path.hasPrefix("/login") else { return }
            Task {
                guard await SteamSession.accessToken() != nil, !didFinish else { return }
                didFinish = true
                onSignedIn()
            }
        }
    }
}
