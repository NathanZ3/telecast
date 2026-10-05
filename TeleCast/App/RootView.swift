import SwiftUI
import CastCore
import CastNet

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tv")
                .font(.system(size: 56))
            Text("TéléCast")
                .font(.largeTitle.bold())
            Text("CastNet \(CastNet.version) · \(MediaKind.hls.rawValue)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
