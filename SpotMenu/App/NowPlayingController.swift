import MediaPlayer

@MainActor
final class NowPlayingController {
    private weak var playbackModel: PlaybackModel?
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

    init(playbackModel: PlaybackModel) {
        self.playbackModel = playbackModel
        configureCommandHandlers()
    }

    func update(from playbackModel: PlaybackModel) {
        updateCommandAvailability(using: playbackModel)

        guard let trackID = playbackModel.currentTrackID else {
            nowPlayingInfoCenter.nowPlayingInfo = nil
            nowPlayingInfoCenter.playbackState = .stopped
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: playbackModel.title,
            MPMediaItemPropertyArtist: playbackModel.artist,
            MPNowPlayingInfoPropertyMediaType:
                MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime:
                max(playbackModel.currentTime, 0),
            MPNowPlayingInfoPropertyPlaybackRate:
                playbackModel.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyAssetURL: trackID,
        ]

        if trackID.isFileURL {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = max(
                playbackModel.totalTime,
                0
            )
        } else {
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        }

        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        nowPlayingInfoCenter.playbackState =
            playbackModel.isPlaying ? .playing : .paused
    }

    private func configureCommandHandlers() {
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handlePlayCommand() ?? .commandFailed
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handlePauseCommand() ?? .commandFailed
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleTogglePlayPauseCommand() ?? .commandFailed
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.handleNextTrackCommand() ?? .commandFailed
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.handlePreviousTrackCommand() ?? .commandFailed
        }
        commandCenter.changePlaybackPositionCommand.addTarget {
            [weak self] event in
            self?.handleChangePlaybackPositionCommand(event)
                ?? .commandFailed
        }
    }

    private func updateCommandAvailability(using playbackModel: PlaybackModel) {
        let hasPlaybackItem = playbackModel.currentTrackID != nil
        let canTogglePlayback =
            hasPlaybackItem || !playbackModel.libraryTracks.isEmpty
        let canSkipTracks = playbackModel.currentTrackID?.isFileURL == true
        let canChangePlaybackPosition =
            canSkipTracks && playbackModel.totalTime > 1

        commandCenter.playCommand.isEnabled =
            canTogglePlayback && !playbackModel.isPlaying
        commandCenter.pauseCommand.isEnabled =
            hasPlaybackItem && playbackModel.isPlaying
        commandCenter.togglePlayPauseCommand.isEnabled = canTogglePlayback
        commandCenter.nextTrackCommand.isEnabled = canSkipTracks
        commandCenter.previousTrackCommand.isEnabled = canSkipTracks
        commandCenter.changePlaybackPositionCommand.isEnabled =
            canChangePlaybackPosition
        commandCenter.stopCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false
        commandCenter.changeRepeatModeCommand.isEnabled = false
        commandCenter.changeShuffleModeCommand.isEnabled = false
        commandCenter.likeCommand.isEnabled = false
        commandCenter.dislikeCommand.isEnabled = false
        commandCenter.bookmarkCommand.isEnabled = false
    }

    private func handlePlayCommand() -> MPRemoteCommandHandlerStatus {
        guard let playbackModel else { return .commandFailed }
        guard playbackModel.currentTrackID != nil
            || !playbackModel.libraryTracks.isEmpty
        else {
            return .noSuchContent
        }

        if !playbackModel.isPlaying {
            playbackModel.togglePlayPause()
        }

        return .success
    }

    private func handlePauseCommand() -> MPRemoteCommandHandlerStatus {
        guard let playbackModel else { return .commandFailed }
        guard playbackModel.currentTrackID != nil else {
            return .noSuchContent
        }

        if playbackModel.isPlaying {
            playbackModel.togglePlayPause()
        }

        return .success
    }

    private func handleTogglePlayPauseCommand()
        -> MPRemoteCommandHandlerStatus
    {
        guard let playbackModel else { return .commandFailed }
        guard playbackModel.currentTrackID != nil
            || !playbackModel.libraryTracks.isEmpty
        else {
            return .noSuchContent
        }

        playbackModel.togglePlayPause()
        return .success
    }

    private func handleNextTrackCommand() -> MPRemoteCommandHandlerStatus {
        guard let playbackModel else { return .commandFailed }
        guard playbackModel.currentTrackID?.isFileURL == true else {
            return .noSuchContent
        }

        playbackModel.skipForward()
        return .success
    }

    private func handlePreviousTrackCommand() -> MPRemoteCommandHandlerStatus {
        guard let playbackModel else { return .commandFailed }
        guard playbackModel.currentTrackID?.isFileURL == true else {
            return .noSuchContent
        }

        playbackModel.skipBack()
        return .success
    }

    private func handleChangePlaybackPositionCommand(_ event: MPRemoteCommandEvent)
        -> MPRemoteCommandHandlerStatus
    {
        guard let playbackModel else { return .commandFailed }
        guard playbackModel.currentTrackID?.isFileURL == true else {
            return .noSuchContent
        }
        guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent
        else {
            return .commandFailed
        }

        playbackModel.updatePlaybackPosition(to: positionEvent.positionTime)
        playbackModel.fetchInfo()
        return .success
    }
}
