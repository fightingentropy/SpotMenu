import AVFoundation
import AppKit
import Foundation
import SwiftUI

final class MusicFolderController: NSObject, AVAudioPlayerDelegate,
    MusicPlayerController
{
    private struct TrackMetadata {
        let title: String
        let artist: String
        let album: String?
        let duration: Double
        let image: NSImage?
    }

    private struct FilenameMetadata {
        let title: String
        let artist: String?
    }

    private static let supportedExtensions: Set<String> = [
        "aac", "aif", "aiff", "alac", "caf", "flac", "m4a", "mp3", "wav",
    ]

    private let preferences: MusicPlayerPreferencesModel
    private var audioPlayer: AVAudioPlayer?
    private var streamPlayer: AVPlayer?
    private var trackURLs: [URL] = []
    private var cachedLibraryTracks: [LibraryTrack] = []
    private var metadataCache: [URL: TrackMetadata] = [:]
    private var metadataIndexingWorkItem: DispatchWorkItem?
    private let metadataIndexingQueue = DispatchQueue(
        label: "spotmenu.musicFolder.metadata",
        qos: .userInitiated
    )
    private var currentTrackIndex: Int?
    private var currentStreamURL: URL?
    private var currentStreamTitle: String?
    private var currentStreamArtist: String?
    private var currentStreamImage: NSImage?
    private var isShuffleEnabledState = false
    private var shuffleOrder: [Int] = []
    private var shufflePosition: Int?
    private var currentFolderURL: URL?
    private var isAccessingSecurityScope = false
    private var lastFolderScanDate = Date.distantPast
    private let minimumScanInterval: TimeInterval = 30

    init(preferences: MusicPlayerPreferencesModel) {
        self.preferences = preferences
        super.init()
        refreshLibraryIfNeeded(force: true)
    }

    deinit {
        metadataIndexingWorkItem?.cancel()
        stopAccessingSecurityScope()
    }

    func fetchNowPlayingInfo() -> PlaybackInfo? {
        if let streamURL = currentStreamURL,
            let streamTitle = currentStreamTitle,
            let streamArtist = currentStreamArtist,
            let streamPlayer
        {
            return PlaybackInfo(
                artist: streamArtist,
                title: streamTitle,
                isPlaying: streamPlayer.timeControlStatus == .playing,
                imageURL: nil,
                totalTime: 1,
                currentTime: 0,
                image: currentStreamImage.map { Image(nsImage: $0) },
                isLiked: nil,
                longFormInfo: nil,
                trackID: streamURL
            )
        }

        refreshLibraryIfNeeded()

        guard ensureTrackLoaded(),
            let index = currentTrackIndex,
            trackURLs.indices.contains(index)
        else {
            return nil
        }

        let url = trackURLs[index]
        let metadata = metadata(for: url)
        let totalDuration = max(audioPlayer?.duration ?? 1, 1)
        let elapsed = min(audioPlayer?.currentTime ?? 0, totalDuration)

        return PlaybackInfo(
            artist: metadata.artist,
            title: metadata.title,
            isPlaying: audioPlayer?.isPlaying ?? false,
            imageURL: nil,
            totalTime: totalDuration,
            currentTime: elapsed,
            image: metadata.image.map { Image(nsImage: $0) },
            isLiked: nil,
            longFormInfo: nil,
            trackID: url
        )
    }

    func togglePlayPause() {
        if let streamPlayer {
            if streamPlayer.timeControlStatus == .playing {
                streamPlayer.pause()
            } else {
                streamPlayer.play()
            }
            return
        }

        refreshLibraryIfNeeded()
        guard ensureTrackLoaded() else { return }

        if audioPlayer?.isPlaying == true {
            audioPlayer?.pause()
        } else {
            audioPlayer?.play()
        }
    }

    func skipForward() {
        guard streamPlayer == nil else { return }
        playAdjacentTrack(step: 1)
    }

    func skipBack() {
        guard streamPlayer == nil else { return }
        refreshLibraryIfNeeded()

        if let player = audioPlayer, player.currentTime > 3 {
            player.currentTime = 0
            return
        }

        playAdjacentTrack(step: -1)
    }

    func updatePlaybackPosition(to seconds: Double) {
        guard streamPlayer == nil else { return }
        guard let player = audioPlayer else { return }
        let clampedSeconds = min(max(seconds, 0), player.duration)
        player.currentTime = clampedSeconds
    }

    func libraryTracks() -> [LibraryTrack] {
        refreshLibraryIfNeeded()
        return cachedLibraryTracks
    }

    func playTrack(_ trackID: URL) {
        stopStreamPlaybackIfNeeded()
        refreshLibraryIfNeeded()
        guard let index = trackURLs.firstIndex(of: trackID) else { return }
        guard loadTrack(at: index) else { return }
        audioPlayer?.play()
    }

    func playStream(url: URL, title: String, artist: String, imageAssetName: String?) {
        audioPlayer?.stop()
        audioPlayer = nil
        currentTrackIndex = nil

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        streamPlayer = player
        currentStreamURL = url
        currentStreamTitle = title
        currentStreamArtist = artist
        currentStreamImage = imageAssetName.flatMap { NSImage(named: $0) }
        player.play()
    }

    func playAll() {
        stopStreamPlaybackIfNeeded()
        refreshLibraryIfNeeded()
        guard !trackURLs.isEmpty else { return }

        let startIndex: Int
        if isShuffleEnabledState {
            rebuildShuffleOrder(preservingCurrent: false)
            startIndex = shuffleOrder.first ?? 0
            shufflePosition = 0
        } else {
            startIndex = 0
        }

        guard loadTrack(at: startIndex) else { return }
        audioPlayer?.play()
    }

    func toggleShuffle() {
        isShuffleEnabledState.toggle()

        if isShuffleEnabledState {
            rebuildShuffleOrder(preservingCurrent: true)
        } else {
            shuffleOrder = []
            shufflePosition = nil
        }
    }

    func isShuffleEnabled() -> Bool {
        isShuffleEnabledState
    }

    func openApp() {
        refreshLibraryIfNeeded(force: true)
        guard let folderURL = currentFolderURL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
    }

    func toggleLiked() {}
    func likeTrack() {}
    func unlikeTrack() {}

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool)
    {
        guard flag else { return }
        playAdjacentTrack(step: 1)
    }

    private func ensureTrackLoaded() -> Bool {
        if audioPlayer != nil, let currentTrackIndex,
            trackURLs.indices.contains(currentTrackIndex)
        {
            return true
        }

        guard !trackURLs.isEmpty else {
            audioPlayer = nil
            currentTrackIndex = nil
            return false
        }

        let initialIndex = currentTrackIndex ?? 0
        return loadTrack(at: initialIndex)
    }

    private func playAdjacentTrack(step: Int) {
        refreshLibraryIfNeeded()
        guard !trackURLs.isEmpty else { return }

        if isShuffleEnabledState {
            playAdjacentShuffledTrack(step: step)
            return
        }

        let nextIndex: Int
        if let index = currentTrackIndex {
            nextIndex = (index + step + trackURLs.count) % trackURLs.count
        } else {
            nextIndex = step >= 0 ? 0 : trackURLs.count - 1
        }

        guard loadTrack(at: nextIndex) else { return }
        audioPlayer?.play()
    }

    private func playAdjacentShuffledTrack(step: Int) {
        if shuffleOrder.isEmpty {
            rebuildShuffleOrder(preservingCurrent: true)
        }

        guard !shuffleOrder.isEmpty else { return }

        let nextPosition: Int
        if let shufflePosition {
            nextPosition = (shufflePosition + step + shuffleOrder.count)
                % shuffleOrder.count
        } else if let currentTrackIndex,
            let currentPosition = shuffleOrder.firstIndex(of: currentTrackIndex)
        {
            nextPosition = (currentPosition + step + shuffleOrder.count)
                % shuffleOrder.count
        } else {
            nextPosition = step >= 0 ? 0 : shuffleOrder.count - 1
        }

        let nextIndex = shuffleOrder[nextPosition]
        guard loadTrack(at: nextIndex) else { return }
        shufflePosition = nextPosition
        audioPlayer?.play()
    }

    @discardableResult
    private func loadTrack(at index: Int) -> Bool {
        guard trackURLs.indices.contains(index) else { return false }

        do {
            let player = try AVAudioPlayer(contentsOf: trackURLs[index])
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            currentTrackIndex = index
            if isShuffleEnabledState {
                if shuffleOrder.isEmpty {
                    rebuildShuffleOrder(preservingCurrent: true)
                }
                shufflePosition = shuffleOrder.firstIndex(of: index)
            }
            return true
        } catch {
            print("Failed to load audio file: \(error.localizedDescription)")
            return false
        }
    }

    private func refreshLibraryIfNeeded(force: Bool = false) {
        let nextFolderURL = preferences.resolveMusicFolderURL()
        let previousFolderPath = currentFolderURL?.path
        let folderDidChange = previousFolderPath != nextFolderURL?.path

        let now = Date()
        let shouldRescan =
            force
            || folderDidChange
            || trackURLs.isEmpty
            || now.timeIntervalSince(lastFolderScanDate) >= minimumScanInterval

        guard shouldRescan else { return }
        lastFolderScanDate = now

        updateFolderAccess(url: nextFolderURL)

        guard let folderURL = currentFolderURL else {
            clearPlaybackState()
            return
        }

        let previousCurrentURL = currentTrackIndex.flatMap {
            trackURLs.indices.contains($0) ? trackURLs[$0] : nil
        }

        let scannedTracks = scanTracks(in: folderURL)
        trackURLs = scannedTracks
        let scannedTrackSet = Set(scannedTracks)
        metadataCache = metadataCache.filter { scannedTrackSet.contains($0.key) }
        rebuildLibraryTrackCache()
        startMetadataIndexing(for: scannedTracks)

        if let previousCurrentURL,
            let preservedIndex = scannedTracks.firstIndex(of: previousCurrentURL)
        {
            currentTrackIndex = preservedIndex
        } else {
            currentTrackIndex = nil
            if folderDidChange || previousCurrentURL != nil {
                audioPlayer?.stop()
                audioPlayer = nil
            }
        }

        synchronizeShuffleStateAfterLibraryRefresh()
    }

    private func scanTracks(in folderURL: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: nil
            )
        else {
            return []
        }

        var discoveredTracks: [URL] = []

        for case let fileURL as URL in enumerator {
            guard
                Self.supportedExtensions.contains(
                    fileURL.pathExtension.lowercased()
                )
            else {
                continue
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey
            ])

            if resourceValues?.isRegularFile == true {
                discoveredTracks.append(fileURL)
            }
        }

        return discoveredTracks.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare(
                $1.lastPathComponent
            ) == .orderedAscending
        }
    }

    private func updateFolderAccess(url: URL?) {
        guard currentFolderURL?.path != url?.path else { return }

        stopAccessingSecurityScope()
        currentFolderURL = url

        guard let url else { return }
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
    }

    private func stopAccessingSecurityScope() {
        guard isAccessingSecurityScope, let currentFolderURL else { return }
        currentFolderURL.stopAccessingSecurityScopedResource()
        isAccessingSecurityScope = false
    }

    private func clearPlaybackState() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopStreamPlaybackIfNeeded()
        trackURLs = []
        shuffleOrder = []
        shufflePosition = nil
        cachedLibraryTracks = []
        metadataCache = [:]
        currentTrackIndex = nil
    }

    private func synchronizeShuffleStateAfterLibraryRefresh() {
        guard isShuffleEnabledState else {
            shuffleOrder = []
            shufflePosition = nil
            return
        }

        rebuildShuffleOrder(preservingCurrent: true)
    }

    private func rebuildShuffleOrder(preservingCurrent: Bool) {
        guard !trackURLs.isEmpty else {
            shuffleOrder = []
            shufflePosition = nil
            return
        }

        var pool = Array(trackURLs.indices)
        let currentIndex = preservingCurrent ? currentTrackIndex : nil

        if let currentIndex,
            let currentPositionInPool = pool.firstIndex(of: currentIndex)
        {
            pool.remove(at: currentPositionInPool)
            pool.shuffle()
            shuffleOrder = [currentIndex] + pool
            shufflePosition = 0
            return
        }

        pool.shuffle()
        shuffleOrder = pool
        shufflePosition = 0
    }

    private func rebuildLibraryTrackCache() {
        cachedLibraryTracks = trackURLs.map { url in
            let metadata = metadataCache[url] ?? fallbackMetadata(for: url)
            return LibraryTrack(
                id: url,
                title: metadata.title,
                artist: metadata.artist,
                album: metadata.album,
                duration: metadata.duration,
                image: metadata.image.map { Image(nsImage: $0) }
            )
        }
    }

    private func metadata(for url: URL) -> TrackMetadata {
        if let cached = metadataCache[url] {
            return cached
        }

        let metadata = computeMetadata(for: url)
        metadataCache[url] = metadata
        updateCachedLibraryTrack(for: url, metadata: metadata)
        return metadata
    }

    private func updateCachedLibraryTrack(for url: URL, metadata: TrackMetadata) {
        guard let index = cachedLibraryTracks.firstIndex(where: { $0.id == url })
        else { return }

        cachedLibraryTracks[index] = LibraryTrack(
            id: url,
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            duration: metadata.duration,
            image: metadata.image.map { Image(nsImage: $0) }
        )
    }

    private func startMetadataIndexing(for trackURLs: [URL]) {
        metadataIndexingWorkItem?.cancel()

        let urlsToIndex = trackURLs.filter { metadataCache[$0] == nil }
        guard !urlsToIndex.isEmpty else { return }

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let workItem else { return }

            var loadedMetadata: [URL: TrackMetadata] = [:]
            loadedMetadata.reserveCapacity(urlsToIndex.count)

            for url in urlsToIndex {
                if workItem.isCancelled {
                    return
                }

                loadedMetadata[url] = self.computeMetadata(for: url)
            }

            if workItem.isCancelled {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.metadataIndexingWorkItem === workItem else { return }

                self.metadataCache.merge(loadedMetadata) { _, incoming in
                    incoming
                }
                self.rebuildLibraryTrackCache()
            }
        }

        metadataIndexingWorkItem = workItem
        if let workItem {
            metadataIndexingQueue.async(execute: workItem)
        }
    }

    private func computeMetadata(for url: URL) -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        let mergedMetadata = allMetadataItems(for: asset)
        let filenameMetadata = parseFilenameMetadata(from: url)

        let title =
            stringMetadata(
                in: mergedMetadata,
                identifiers: [.commonIdentifierTitle],
                commonKeys: [.commonKeyTitle],
                identifierContains: ["title", "songname", "displayname"],
                keyContains: ["tit2", "title", "name"]
            )
            ?? filenameMetadata.title

        let artist =
            stringMetadata(
                in: mergedMetadata,
                identifiers: [
                    .commonIdentifierArtist,
                    .iTunesMetadataArtist,
                    .id3MetadataLeadPerformer,
                ],
                commonKeys: [.commonKeyArtist],
                identifierContains: ["artist", "performer", "author"],
                keyContains: ["tpe1", "artist", "author"]
            )
            ?? stringMetadata(
                in: mergedMetadata,
                identifiers: [.commonIdentifierAlbumName],
                commonKeys: [.commonKeyAlbumName],
                identifierContains: ["album"],
                keyContains: ["talb", "album"]
            )
            ?? filenameMetadata.artist
            ?? "Music Folder"

        let album = stringMetadata(
            in: mergedMetadata,
            identifiers: [.commonIdentifierAlbumName],
            commonKeys: [.commonKeyAlbumName],
            identifierContains: ["album"],
            keyContains: ["talb", "album"]
        )

        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let duration = durationSeconds.isFinite && durationSeconds > 0
            ? durationSeconds : 0

        let image = artworkImage(from: mergedMetadata) ?? folderArtwork(for: url)

        return TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            image: image
        )
    }

    private func allMetadataItems(for asset: AVURLAsset) -> [AVMetadataItem] {
        var items = asset.commonMetadata

        for format in asset.availableMetadataFormats {
            items.append(contentsOf: asset.metadata(forFormat: format))
        }

        return items
    }

    private func parseFilenameMetadata(from url: URL) -> FilenameMetadata {
        let filename = url.deletingPathExtension().lastPathComponent
        let separators = [" - ", " – ", " — "]

        for separator in separators {
            let parts = filename.components(separatedBy: separator)
            if parts.count == 2 {
                let title = parts[0].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let artist = parts[1].trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                if !title.isEmpty {
                    return FilenameMetadata(
                        title: title,
                        artist: artist.isEmpty ? nil : artist
                    )
                }
            }
        }

        return FilenameMetadata(title: filename, artist: nil)
    }

    private func fallbackMetadata(for url: URL) -> TrackMetadata {
        let filenameMetadata = parseFilenameMetadata(from: url)
        return TrackMetadata(
            title: filenameMetadata.title,
            artist: filenameMetadata.artist ?? "Music Folder",
            album: nil,
            duration: 0,
            image: nil
        )
    }

    private func stringMetadata(
        in metadataItems: [AVMetadataItem],
        identifiers: [AVMetadataIdentifier],
        commonKeys: [AVMetadataKey],
        identifierContains: [String],
        keyContains: [String]
    ) -> String? {
        for identifier in identifiers {
            let candidates = AVMetadataItem.metadataItems(
                from: metadataItems,
                filteredByIdentifier: identifier
            )

            for item in candidates {
                if let value = normalizedStringValue(from: item) {
                    return value
                }
            }
        }

        let loweredIdentifierContains = identifierContains.map {
            $0.lowercased()
        }
        let loweredKeyContains = keyContains.map { $0.lowercased() }

        for item in metadataItems {
            if let commonKey = item.commonKey,
                commonKeys.contains(commonKey),
                let value = normalizedStringValue(from: item)
            {
                return value
            }

            let identifierMatches = containsAnySubstring(
                item.identifier?.rawValue.lowercased(),
                needles: loweredIdentifierContains
            )
            if identifierMatches,
                let value = normalizedStringValue(from: item)
            {
                return value
            }

            if containsAnySubstring(
                (item.key as? String)?.lowercased(),
                needles: loweredKeyContains
            ),
                let value = normalizedStringValue(from: item)
            {
                return value
            }
        }

        return nil
    }

    private func normalizedStringValue(from item: AVMetadataItem) -> String? {
        let rawValue: String?
        if let stringValue = item.stringValue {
            rawValue = stringValue
        } else if let value = item.value as? String {
            rawValue = value
        } else {
            rawValue = nil
        }

        guard let rawValue else { return nil }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func containsAnySubstring(_ value: String?, needles: [String]) -> Bool {
        guard let value else { return false }
        return needles.contains { value.contains($0) }
    }

    private func artworkImage(from metadataItems: [AVMetadataItem]) -> NSImage? {
        for item in metadataItems {
            guard isArtworkMetadata(item) else { continue }

            if let data = item.dataValue,
                !data.isEmpty,
                let image = NSImage(data: data)
            {
                return image
            }

            if let value = item.value as? Data,
                !value.isEmpty,
                let image = NSImage(data: value)
            {
                return image
            }

            if let dictionary = item.value as? [AnyHashable: Any],
                let data = dictionary["data"] as? Data,
                !data.isEmpty,
                let image = NSImage(data: data)
            {
                return image
            }

            if let image = item.value as? NSImage {
                return image
            }
        }

        return nil
    }

    private func isArtworkMetadata(_ item: AVMetadataItem) -> Bool {
        if item.commonKey == .commonKeyArtwork {
            return true
        }

        if item.identifier == .commonIdentifierArtwork
            || item.identifier == .id3MetadataAttachedPicture
            || item.identifier == .iTunesMetadataCoverArt
            || item.identifier == .quickTimeMetadataArtwork
        {
            return true
        }

        if let identifier = item.identifier?.rawValue.lowercased(),
            identifier.contains("artwork")
                || identifier.contains("covr")
                || identifier.contains("apic")
                || identifier.contains("picture")
        {
            return true
        }

        if let key = (item.key as? String)?.lowercased(),
            key.contains("artwork")
                || key.contains("covr")
                || key.contains("apic")
                || key.contains("picture")
        {
            return true
        }

        return false
    }

    private func folderArtwork(for trackURL: URL) -> NSImage? {
        let directoryURL = trackURL.deletingLastPathComponent()
        let candidates = [
            "cover.jpg", "cover.jpeg", "cover.png", "folder.jpg",
            "folder.jpeg", "folder.png", "front.jpg", "front.jpeg",
            "front.png",
        ]

        for candidate in candidates {
            let artworkURL = directoryURL.appendingPathComponent(candidate)
            if let image = NSImage(contentsOf: artworkURL) {
                return image
            }
        }

        return nil
    }

    private func stopStreamPlaybackIfNeeded() {
        streamPlayer?.pause()
        streamPlayer = nil
        currentStreamURL = nil
        currentStreamTitle = nil
        currentStreamArtist = nil
        currentStreamImage = nil
    }
}
