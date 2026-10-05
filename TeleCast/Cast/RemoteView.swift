import SwiftUI
import CastCore

/// The remote control of the current cast.
struct RemoteView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var scrubPosition: Double?
    @State private var volume: Double = 20
    @State private var volumeEdited = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    status
                    progress
                    controls
                    volumeControl
                    if app.cast.variants.count > 1 {
                        qualityMenu
                    }
                    bottomButtons
                }
                .padding(24)
            }
            .navigationTitle("Télécommande")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink {
                        LogView()
                    } label: {
                        Label("Journal", systemImage: "doc.text")
                    }
                }
            }
            .onChange(of: app.cast.snapshot?.volume) { _, newValue in
                if let newValue, !volumeEdited { volume = Double(newValue) }
            }
        }
    }

    private var snapshot: CastSnapshot? { app.cast.snapshot }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(app.cast.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if !app.cast.tvName.isEmpty {
                Text("Sur \(app.cast.tvName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if case .failed(let message)? = snapshot?.phase {
            VStack(spacing: 8) {
                Label("Lecture impossible", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
        } else {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                }
                Text(CastModel.statusText(snapshot))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var isBusy: Bool {
        switch snapshot?.phase {
        case .preparing?, .trying?, .buffering?, .resuming?, .unreachable?:
            return true
        default:
            return app.cast.isStarting
        }
    }

    @ViewBuilder
    private var progress: some View {
        if snapshot?.isLive == true {
            Label("En direct", systemImage: "dot.radiowaves.left.and.right")
                .foregroundStyle(.red)
        } else if let duration = snapshot?.duration, duration > 0 {
            let position = scrubPosition ?? min(snapshot?.position ?? 0, duration)
            VStack(spacing: 4) {
                Slider(value: Binding(get: { position }, set: { scrubPosition = $0 }), in: 0...duration,
                       onEditingChanged: { editing in
                           if !editing, let target = scrubPosition {
                               app.cast.seek(to: target)
                               scrubPosition = nil
                           }
                       })
                HStack {
                    Text(Formatters.time(position))
                    Spacer()
                    Text("-" + Formatters.time(max(0, duration - position)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        } else if let position = snapshot?.position {
            Text(Formatters.time(position))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        let active = snapshot?.phase.isActive ?? false
        let paused = snapshot?.phase == .paused
        return HStack(spacing: 26) {
            Button { app.cast.skip(-30) } label: { Image(systemName: "gobackward.30") }
            Button { app.cast.skip(-10) } label: { Image(systemName: "gobackward.10") }
            Button { app.cast.togglePause() } label: {
                Image(systemName: paused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 64))
            }
            Button { app.cast.skip(10) } label: { Image(systemName: "goforward.10") }
            Button { app.cast.skip(30) } label: { Image(systemName: "goforward.30") }
        }
        .font(.system(size: 28))
        .disabled(!active)
    }

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
            Slider(value: $volume, in: 0...100, step: 1, onEditingChanged: { editing in
                volumeEdited = editing
                if !editing { app.cast.setVolume(Int(volume)) }
            })
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
        }
        .disabled(!(snapshot?.phase.isActive ?? false))
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(app.cast.variants, id: \.url) { variant in
                Button {
                    app.cast.changeQuality(variant)
                } label: {
                    if variant.url == app.cast.currentVariantURL {
                        Label(Formatters.variantLabel(variant), systemImage: "checkmark")
                    } else {
                        Text(Formatters.variantLabel(variant))
                    }
                }
            }
        } label: {
            Label("Qualité", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
    }

    private var bottomButtons: some View {
        HStack(spacing: 16) {
            Button(role: .destructive) {
                app.cast.stop()
                dismiss()
            } label: {
                Label("Arrêter", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            Button {
                app.cast.restart()
            } label: {
                Label("Relancer", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}
