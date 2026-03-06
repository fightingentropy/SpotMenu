import AVFoundation
import AppKit
import CryptoKit
import Darwin
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
    private var playbackQueueURLs: [URL]?
    private var manualQueueURLs: [URL] = []
    private var cachedLibraryTracks: [LibraryTrack] = []
    private var metadataCache: [URL: TrackMetadata] = [:]
    private let metadataIndexingQueue = DispatchQueue(
        label: "spotmenu.musicFolder.metadata",
        qos: .userInitiated
    )
    private let trackMetadataDiskCache = TrackMetadataDiskCache()
    private var metadataBatchWorkItem: DispatchWorkItem?
    private var metadataIdleWorkItem: DispatchWorkItem?
    private var pendingMetadataURLs: [URL] = []
    private let metadataInitialBatchSize = 16
    private let metadataProcessingBatchSize = 16
    private var currentTrackIndex: Int?
    private var currentStreamURL: URL?
    private var currentStreamTitle: String?
    private var currentStreamArtist: String?
    private var currentStreamImage: NSImage?
    private var isShuffleEnabledState = false
    private var usesExplicitPlaybackOrder = false
    private var shuffleOrder: [Int] = []
    private var shufflePosition: Int?
    private var currentFolderURL: URL?
    private var isAccessingSecurityScope = false
    private var folderMonitorSource: DispatchSourceFileSystemObject?
    private var folderMonitorFileDescriptor: CInt = -1
    private var libraryNeedsRescan = false
    private var lastFolderScanDate = Date.distantPast
    private let minimumScanInterval: TimeInterval = 30

    private var activeTrackURLs: [URL] {
        playbackQueueURLs ?? trackURLs
    }

    init(preferences: MusicPlayerPreferencesModel) {
        self.preferences = preferences
        super.init()
        refreshLibraryIfNeeded(force: true)
    }

    deinit {
        metadataBatchWorkItem?.cancel()
        metadataIdleWorkItem?.cancel()
        stopFolderMonitor()
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
            activeTrackURLs.indices.contains(index)
        else {
            return nil
        }

        let url = activeTrackURLs[index]
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

    func requestMetadata(for trackIDs: [URL]) {
        queueMetadataIndexing(urls: trackIDs, prioritize: true)
    }

    func playTrack(_ trackID: URL) {
        stopStreamPlaybackIfNeeded()
        refreshLibraryIfNeeded()
        playbackQueueURLs = nil
        manualQueueURLs = []
        usesExplicitPlaybackOrder = false
        guard let index = activeTrackURLs.firstIndex(of: trackID) else { return }
        shuffleOrder = []
        shufflePosition = nil
        guard loadTrack(at: index) else { return }
        audioPlayer?.play()
    }

    func playTracks(_ trackIDs: [URL]) {
        stopStreamPlaybackIfNeeded()
        refreshLibraryIfNeeded()

        let librarySet = Set(trackURLs)
        let queue = trackIDs.filter { librarySet.contains($0) }
        guard !queue.isEmpty else { return }

        playbackQueueURLs = queue
        manualQueueURLs = []
        usesExplicitPlaybackOrder = false
        shuffleOrder = []
        shufflePosition = nil

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

    func enqueueTrack(_ trackID: URL) {
        guard streamPlayer == nil else { return }

        refreshLibraryIfNeeded()

        let librarySet = Set(trackURLs)
        guard librarySet.contains(trackID) else { return }
        guard materializePlaybackQueueForManualOrdering() else { return }
        guard var queue = playbackQueueURLs,
            let currentTrackIndex,
            queue.indices.contains(currentTrackIndex)
        else {
            return
        }

        removeFutureOccurrences(of: trackID, from: &queue, after: currentTrackIndex)

        manualQueueURLs.removeAll { $0 == trackID }

        let insertAfterIndex =
            manualQueueURLs.reversed().compactMap { queuedTrackID in
                queue.lastIndex(of: queuedTrackID)
            }.first
            ?? currentTrackIndex

        queue.insert(trackID, at: min(insertAfterIndex + 1, queue.count))
        playbackQueueURLs = queue
        manualQueueURLs.append(trackID)
    }

    func playStream(url: URL, title: String, artist: String, imageAssetName: String?) {
        audioPlayer?.stop()
        audioPlayer = nil
        currentTrackIndex = nil
        playbackQueueURLs = nil
        manualQueueURLs = []
        usesExplicitPlaybackOrder = false

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
        playbackQueueURLs = nil
        manualQueueURLs = []
        usesExplicitPlaybackOrder = false
        guard !activeTrackURLs.isEmpty else { return }

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

        guard !usesExplicitPlaybackOrder else {
            if !isShuffleEnabledState {
                shuffleOrder = []
                shufflePosition = nil
            }
            return
        }

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
            activeTrackURLs.indices.contains(currentTrackIndex)
        {
            return true
        }

        guard !activeTrackURLs.isEmpty else {
            audioPlayer = nil
            currentTrackIndex = nil
            return false
        }

        let initialIndex = currentTrackIndex ?? 0
        return loadTrack(at: initialIndex)
    }

    private func playAdjacentTrack(step: Int) {
        refreshLibraryIfNeeded()
        guard !activeTrackURLs.isEmpty else { return }

        if isShuffleEnabledState, !usesExplicitPlaybackOrder {
            playAdjacentShuffledTrack(step: step)
            return
        }

        let nextIndex: Int
        if let index = currentTrackIndex {
            nextIndex = (index + step + activeTrackURLs.count)
                % activeTrackURLs.count
        } else {
            nextIndex = step >= 0 ? 0 : activeTrackURLs.count - 1
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
        guard activeTrackURLs.indices.contains(index) else { return false }

        do {
            let player = try AVAudioPlayer(contentsOf: activeTrackURLs[index])
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            currentTrackIndex = index
            if usesExplicitPlaybackOrder {
                synchronizeManualQueue()
            } else if isShuffleEnabledState {
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
            || libraryNeedsRescan
            || trackURLs.isEmpty
            || now.timeIntervalSince(lastFolderScanDate) >= minimumScanInterval

        guard shouldRescan else { return }
        lastFolderScanDate = now
        libraryNeedsRescan = false

        updateFolderAccess(url: nextFolderURL)

        guard let folderURL = currentFolderURL else {
            clearPlaybackState()
            return
        }

        let previousCurrentURL = currentTrackIndex.flatMap {
            activeTrackURLs.indices.contains($0) ? activeTrackURLs[$0] : nil
        }

        let scannedTracks = scanTracks(in: folderURL)
        trackURLs = scannedTracks
        let scannedTrackSet = Set(scannedTracks)
        metadataCache = metadataCache.filter { scannedTrackSet.contains($0.key) }
        rebuildLibraryTrackCache()
        startMetadataIndexing(for: scannedTracks)

        if let queue = playbackQueueURLs {
            playbackQueueURLs = queue.filter { scannedTrackSet.contains($0) }
            if playbackQueueURLs?.isEmpty == true {
                playbackQueueURLs = nil
                usesExplicitPlaybackOrder = false
            }
        }
        manualQueueURLs = manualQueueURLs.filter { scannedTrackSet.contains($0) }

        if let previousCurrentURL,
            let preservedIndex = activeTrackURLs.firstIndex(of: previousCurrentURL)
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

        stopFolderMonitor()
        stopAccessingSecurityScope()
        currentFolderURL = url

        guard let url else {
            libraryNeedsRescan = true
            return
        }
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
        configureFolderMonitor(for: url)
    }

    private func stopAccessingSecurityScope() {
        guard isAccessingSecurityScope, let currentFolderURL else { return }
        currentFolderURL.stopAccessingSecurityScopedResource()
        isAccessingSecurityScope = false
    }

    private func configureFolderMonitor(for folderURL: URL) {
        stopFolderMonitor()

        let fd = open(folderURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        folderMonitorFileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.libraryNeedsRescan = true
            DispatchQueue.main.async { [weak self] in
                self?.refreshLibraryIfNeeded(force: true)
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.folderMonitorFileDescriptor >= 0 {
                close(self.folderMonitorFileDescriptor)
                self.folderMonitorFileDescriptor = -1
            }
        }

        folderMonitorSource = source
        source.resume()
    }

    private func stopFolderMonitor() {
        folderMonitorSource?.cancel()
        folderMonitorSource = nil
    }

    private func clearPlaybackState() {
        audioPlayer?.stop()
        audioPlayer = nil
        stopStreamPlaybackIfNeeded()
        metadataBatchWorkItem?.cancel()
        metadataBatchWorkItem = nil
        metadataIdleWorkItem?.cancel()
        metadataIdleWorkItem = nil
        pendingMetadataURLs = []
        trackURLs = []
        playbackQueueURLs = nil
        manualQueueURLs = []
        usesExplicitPlaybackOrder = false
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
        guard !activeTrackURLs.isEmpty else {
            shuffleOrder = []
            shufflePosition = nil
            return
        }

        var pool = Array(activeTrackURLs.indices)
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
        metadataBatchWorkItem?.cancel()
        metadataBatchWorkItem = nil
        metadataIdleWorkItem?.cancel()
        metadataIdleWorkItem = nil
        pendingMetadataURLs = []

        let urlsToIndex = trackURLs.filter { metadataCache[$0] == nil }
        guard !urlsToIndex.isEmpty else { return }

        let initial = Array(urlsToIndex.prefix(metadataInitialBatchSize))
        let deferred = Array(urlsToIndex.dropFirst(metadataInitialBatchSize))

        queueMetadataIndexing(urls: deferred, prioritize: false)
        queueMetadataIndexing(urls: initial, prioritize: true)
    }

    private func queueMetadataIndexing(urls: [URL], prioritize: Bool) {
        guard !urls.isEmpty else { return }

        var seen = Set(pendingMetadataURLs)
        if prioritize {
            for url in urls.reversed() {
                guard metadataCache[url] == nil else { continue }
                if seen.contains(url) {
                    pendingMetadataURLs.removeAll { $0 == url }
                }
                pendingMetadataURLs.insert(url, at: 0)
                seen.insert(url)
            }
            processNextMetadataBatch()
        } else {
            for url in urls {
                guard metadataCache[url] == nil, !seen.contains(url) else {
                    continue
                }
                pendingMetadataURLs.append(url)
                seen.insert(url)
            }
            scheduleMetadataIdleProcessing()
        }
    }

    private func processNextMetadataBatch() {
        guard metadataBatchWorkItem == nil else { return }
        guard !pendingMetadataURLs.isEmpty else { return }

        metadataIdleWorkItem?.cancel()
        metadataIdleWorkItem = nil

        let batchCount = min(metadataProcessingBatchSize, pendingMetadataURLs.count)
        let batchURLs = Array(pendingMetadataURLs.prefix(batchCount))
        pendingMetadataURLs.removeFirst(batchCount)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            var loadedMetadata: [URL: TrackMetadata] = [:]
            loadedMetadata.reserveCapacity(batchURLs.count)

            for url in batchURLs {
                if self.metadataBatchWorkItem?.isCancelled == true {
                    return
                }
                loadedMetadata[url] = self.computeMetadata(for: url)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.metadataBatchWorkItem = nil
                self.metadataCache.merge(loadedMetadata) { _, incoming in incoming }
                self.rebuildLibraryTrackCache()

                if !self.pendingMetadataURLs.isEmpty {
                    self.scheduleMetadataIdleProcessing()
                }
            }
        }

        metadataBatchWorkItem = workItem
        metadataIndexingQueue.async(execute: workItem)
    }

    private func scheduleMetadataIdleProcessing() {
        guard metadataBatchWorkItem == nil else { return }
        guard !pendingMetadataURLs.isEmpty else { return }

        metadataIdleWorkItem?.cancel()
        let idleWorkItem = DispatchWorkItem { [weak self] in
            self?.processNextMetadataBatch()
        }
        metadataIdleWorkItem = idleWorkItem
        metadataIndexingQueue.asyncAfter(
            deadline: .now() + 0.65,
            execute: idleWorkItem
        )
    }

    private func computeMetadata(for url: URL) -> TrackMetadata {
        if let cached = trackMetadataDiskCache.loadMetadata(for: url) {
            return TrackMetadata(
                title: cached.title,
                artist: cached.artist,
                album: cached.album,
                duration: cached.duration,
                image: cached.image
            )
        }

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

        let metadata = TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            image: image
        )
        trackMetadataDiskCache.store(
            CachedTrackMetadata(
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                image: image
            ),
            for: url
        )
        return metadata
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
        if let cached = trackMetadataDiskCache.loadMetadata(for: url) {
            return TrackMetadata(
                title: cached.title,
                artist: cached.artist,
                album: cached.album,
                duration: cached.duration,
                image: cached.image
            )
        }

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

    private func materializePlaybackQueueForManualOrdering() -> Bool {
        guard let snapshot = currentPlaybackQueueSnapshot() else { return false }

        playbackQueueURLs = snapshot.tracks
        currentTrackIndex = snapshot.currentIndex
        usesExplicitPlaybackOrder = true
        shuffleOrder = []
        shufflePosition = nil
        synchronizeManualQueue()
        return true
    }

    private func currentPlaybackQueueSnapshot() -> (tracks: [URL], currentIndex: Int)? {
        if usesExplicitPlaybackOrder, let playbackQueueURLs, let currentTrackIndex,
            playbackQueueURLs.indices.contains(currentTrackIndex)
        {
            return (playbackQueueURLs, currentTrackIndex)
        }

        guard let currentTrackIndex,
            activeTrackURLs.indices.contains(currentTrackIndex)
        else {
            return nil
        }

        if isShuffleEnabledState {
            if shuffleOrder.isEmpty {
                rebuildShuffleOrder(preservingCurrent: true)
            }

            guard !shuffleOrder.isEmpty else {
                return (activeTrackURLs, currentTrackIndex)
            }

            let playbackOrder = shuffleOrder.map { activeTrackURLs[$0] }
            let playbackIndex =
                shufflePosition
                ?? shuffleOrder.firstIndex(of: currentTrackIndex)
                ?? 0
            return (playbackOrder, playbackIndex)
        }

        return (activeTrackURLs, currentTrackIndex)
    }

    private func synchronizeManualQueue() {
        guard usesExplicitPlaybackOrder,
            let playbackQueueURLs,
            let currentTrackIndex,
            playbackQueueURLs.indices.contains(currentTrackIndex)
        else {
            manualQueueURLs = []
            return
        }

        let upcomingTracks = Set(playbackQueueURLs.suffix(from: currentTrackIndex + 1))
        manualQueueURLs = manualQueueURLs.filter { upcomingTracks.contains($0) }
    }

    private func removeFutureOccurrences(
        of trackID: URL,
        from queue: inout [URL],
        after currentIndex: Int
    ) {
        guard currentIndex + 1 < queue.count else { return }

        let removalIndices = queue.indices.reversed().filter { index in
            index > currentIndex && queue[index] == trackID
        }

        for index in removalIndices {
            queue.remove(at: index)
        }
    }
}

private struct CachedTrackMetadata {
    let title: String
    let artist: String
    let album: String?
    let duration: Double
    let image: NSImage?
}

private struct CachedTrackMetadataRecord: Codable {
    let title: String
    let artist: String
    let album: String?
    let duration: Double
    let artworkFileName: String?
}

private final class TrackMetadataDiskCache {
    private let metadataDirectoryURL: URL
    private let artworkDirectoryURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
            ?? FileManager.default.temporaryDirectory

        let baseDirectory = appSupport
            .appendingPathComponent("SpotMenu", isDirectory: true)
            .appendingPathComponent("TrackMetadataCache", isDirectory: true)
        metadataDirectoryURL = baseDirectory.appendingPathComponent(
            "metadata",
            isDirectory: true
        )
        artworkDirectoryURL = baseDirectory.appendingPathComponent(
            "artwork",
            isDirectory: true
        )

        try? FileManager.default.createDirectory(
            at: metadataDirectoryURL,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: artworkDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func loadMetadata(for trackURL: URL) -> CachedTrackMetadata? {
        let key = cacheKey(for: trackURL)
        let metadataFileURL = metadataDirectoryURL.appendingPathComponent(
            "\(key).json"
        )

        guard
            let data = try? Data(contentsOf: metadataFileURL),
            let record = try? JSONDecoder().decode(
                CachedTrackMetadataRecord.self,
                from: data
            )
        else {
            return nil
        }

        let image: NSImage?
        if let artworkFileName = record.artworkFileName {
            image = NSImage(
                contentsOf: artworkDirectoryURL.appendingPathComponent(
                    artworkFileName
                )
            )
        } else {
            image = nil
        }

        return CachedTrackMetadata(
            title: record.title,
            artist: record.artist,
            album: record.album,
            duration: record.duration,
            image: image
        )
    }

    func store(_ metadata: CachedTrackMetadata, for trackURL: URL) {
        let key = cacheKey(for: trackURL)
        let metadataFileURL = metadataDirectoryURL.appendingPathComponent(
            "\(key).json"
        )

        let artworkFileName: String?
        if let image = metadata.image, let data = image.tiffRepresentation {
            let fileName = "\(key).tiff"
            let artworkFileURL = artworkDirectoryURL.appendingPathComponent(
                fileName
            )
            try? data.write(to: artworkFileURL, options: .atomic)
            artworkFileName = fileName
        } else {
            artworkFileName = nil
        }

        let record = CachedTrackMetadataRecord(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            duration: metadata.duration,
            artworkFileName: artworkFileName
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: metadataFileURL, options: .atomic)
    }

    private func cacheKey(for trackURL: URL) -> String {
        let signature = fileSignature(for: trackURL)
        let source =
            "\(trackURL.path)|\(signature.size)|\(signature.modificationTime)"
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileSignature(for url: URL) -> (size: Int64, modificationTime: TimeInterval) {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
        ])

        let size = Int64(values?.fileSize ?? 0)
        let modificationTime = values?.contentModificationDate?.timeIntervalSince1970
            ?? 0
        return (size, modificationTime)
    }
}
