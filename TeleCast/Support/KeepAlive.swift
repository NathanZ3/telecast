import AVFoundation
import CastCore

/// Keeps the app (and its relay) running while the phone is locked during a cast,
/// by playing silence in a `.playback` audio session (UIBackgroundModes = audio).
@MainActor
final class KeepAlive {
    static let shared = KeepAlive()

    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?
    private(set) var isActive = false

    func start() {
        guard !isActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.silentWAV())
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
            self.player = player
            isActive = true
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                MainActor.assumeIsolated {
                    self?.resumeAfterInterruption()
                }
            }
            castLog("app", "Maintien en arrière-plan activé")
        } catch {
            castLog("app", "Maintien en arrière-plan impossible : \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isActive else { return }
        player?.stop()
        player = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
        castLog("app", "Maintien en arrière-plan désactivé")
    }

    private func resumeAfterInterruption() {
        guard isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        castLog("app", "Reprise après interruption audio")
    }

    /// One second of 16-bit mono silence as a WAV file.
    static func silentWAV(seconds: Int = 1, sampleRate: Int = 8000) -> Data {
        let dataSize = seconds * sampleRate * 2
        var data = Data()
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
