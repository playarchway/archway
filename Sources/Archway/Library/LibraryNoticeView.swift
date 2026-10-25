import SwiftUI

/// A full-page notice in the style of the start page, for when the library can't be shown.
struct LibraryNoticeView: View {
    let error: SteamCatalogError
    let onRetry: () -> Void
    let onLinkSteam: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Label(eyebrow, systemImage: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 40, weight: .bold))
                Text(detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 14)

            HStack(spacing: 12) {
                if error == .notSignedIn {
                    Button("Link Steam…", action: onLinkSteam)
                        .buttonStyle(.borderedProminent)
                    Button("Try Again", action: onRetry)
                } else {
                    Button("Try Again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.15), value: hasAppeared)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: hasAppeared)
        .onAppear { hasAppeared = true }
    }

    private var symbol: String {
        switch error {
        case .notSignedIn: "link"
        case .network: "wifi.slash"
        case .unexpectedResponse: "exclamationmark.triangle"
        }
    }

    private var eyebrow: String {
        switch error {
        case .notSignedIn: String(localized: "The Steam link has expired.")
        case .network: String(localized: "Steam can’t be reached.")
        case .unexpectedResponse: String(localized: "Steam answered unexpectedly.")
        }
    }

    private var title: String {
        error == .notSignedIn ? String(localized: "Link Steam Again") : String(localized: "Library Unavailable")
    }

    private var detail: String {
        switch error {
        case .notSignedIn:
            String(localized: "Archway shows your games again once Steam confirms the link. Installed games and saves stay where they are.")
        case .network:
            String(localized: "Check your internet connection, then try again.")
        case .unexpectedResponse:
            String(localized: "This is usually temporary. Try again in a moment.")
        }
    }
}
