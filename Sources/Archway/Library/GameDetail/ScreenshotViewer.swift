import SwiftUI

struct ScreenshotViewer: View {
    let screenshots: [SteamStoreDetails.Screenshot]
    @State var current: SteamStoreDetails.Screenshot
    @Environment(\.dismiss) private var dismiss

    private var index: Int { screenshots.firstIndex { $0.id == current.id } ?? 0 }

    var body: some View {
        VStack(spacing: 12) {
            AsyncImage(url: current.pathFull) { phase in
                if let image = phase.image { image.resizable().scaledToFit() } else { ProgressView() }
            }
            .frame(width: 960, height: 540)
            HStack {
                Button { current = screenshots[index - 1] } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                Text("\(index + 1) of \(screenshots.count)").foregroundStyle(.secondary).frame(width: 90)
                Button { current = screenshots[index + 1] } label: { Image(systemName: "chevron.right") }
                    .disabled(index >= screenshots.count - 1)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }
}
