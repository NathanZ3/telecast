import SwiftUI
import CastCore

/// Compact cast status above the toolbar; tap to open the remote.
struct MiniPlayerBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.cast.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(CastModel.statusText(app.cast.snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if app.cast.snapshot?.phase.isActive == true {
                Button {
                    app.cast.togglePause()
                } label: {
                    Image(systemName: app.cast.snapshot?.phase == .paused ? "play.fill" : "pause.fill")
                }
            }
            Button {
                app.cast.stop()
            } label: {
                Image(systemName: "xmark")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .contentShape(Rectangle())
        .onTapGesture {
            app.sheet = .remote
        }
    }
}
