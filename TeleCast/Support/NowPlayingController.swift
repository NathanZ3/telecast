import MediaPlayer
import CastCore

/// Lock screen / Control Center controls for the current cast.
@MainActor
final class NowPlayingController {
    private weak var cast: CastModel?
    private var targets: [(MPRemoteCommand, Any)] = []

    func activate(cast: CastModel) {
        self.cast = cast
        guard targets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        register(center.playCommand) { $0.togglePause() }
        register(center.pauseCommand) { $0.togglePause() }
        register(center.togglePlayPauseCommand) { $0.togglePause() }
        register(center.skipForwardCommand) { $0.skip(10) }
        register(center.skipBackwardCommand) { $0.skip(-10) }
        let positionCommand = center.changePlaybackPositionCommand
        let positionTarget = positionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated {
                self?.cast?.seek(to: position)
            }
            return .success
        }
        targets.append((positionCommand, positionTarget))
    }

    private func register(_ command: MPRemoteCommand, _ action: @escaping (CastModel) -> Void) {
        let target = command.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                if let cast = self?.cast { action(cast) }
            }
            return .success
        }
        targets.append((command, target))
    }

    func update(title: String, snapshot: CastSnapshot) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "TéléCast",
            MPNowPlayingInfoPropertyIsLiveStream: snapshot.isLive,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.phase == .playing ? 1.0 : 0.0,
        ]
        if let duration = snapshot.duration, !snapshot.isLive {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let position = snapshot.position {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func deactivate() {
        for (command, target) in targets {
            command.removeTarget(target)
        }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
