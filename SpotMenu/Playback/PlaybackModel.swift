import Combine
import SwiftUI

extension Notification.Name {
    static let contentModelDidUpdate = Notification.Name(
        "PlaybackModelDidUpdate"
    )
    static let spotifyLikeStateDidUpdate = Notification.Name(
        "SpotifyLikeStateDidUpdate"
    )
}

enum PlayerType {
    case musicFolder
}

enum LongFormTitleStyle: String, CaseIterable, Identifiable {
    case titleOnly
    case segmentOnly
    case titleAndSegment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .titleOnly: return "Title Only"
        case .segmentOnly: return "Chapter/Episode Only"
        case .titleAndSegment: return "Title + Chapter/Episode"
        }
    }
}

enum LongFormKind {
    case audiobook
    case podcastEpisode
}

struct LongFormInfo {
    let kind: LongFormKind
    let title: String      // book or show title
    let authors: [String]  // authors or publisher
    let segmentTitle: String? // chapter or episode title
}

struct PlaybackInfo {
    let artist: String
    let title: String
    let isPlaying: Bool
    let imageURL: URL?
    let totalTime: Double
    let currentTime: Double
    let image: Image?
    let isLiked: Bool?
    let longFormInfo: LongFormInfo?
    let trackID: URL?

    init(
        artist: String,
        title: String,
        isPlaying: Bool,
        imageURL: URL?,
        totalTime: Double,
        currentTime: Double,
        image: Image?,
        isLiked: Bool?,
        longFormInfo: LongFormInfo?,
        trackID: URL? = nil
    ) {
        self.artist = artist
        self.title = title
        self.isPlaying = isPlaying
        self.imageURL = imageURL
        self.totalTime = totalTime
        self.currentTime = currentTime
        self.image = image
        self.isLiked = isLiked
        self.longFormInfo = longFormInfo
        self.trackID = trackID
    }
}

struct LibraryTrack: Identifiable, Equatable {
    let id: URL
    let title: String
    let artist: String
    let album: String?
    let duration: Double
    let image: Image?
}

struct StreamStation: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let artist: String
    let url: URL
    let iconAssetName: String?
}

enum LibraryPlaybackQueue: Equatable {
    case fullLibrary
    case filtered(query: String, count: Int)
}

protocol MusicPlayerController {
    func fetchNowPlayingInfo() -> PlaybackInfo?
    func togglePlayPause()
    func skipForward()
    func skipBack()
    func updatePlaybackPosition(to seconds: Double)
    func openApp()
    func toggleLiked()
    func likeTrack()
    func unlikeTrack()
    func libraryTracks() -> [LibraryTrack]
    func requestMetadata(for trackIDs: [URL])
    func playTrack(_ trackID: URL)
    func playTrack(_ trackID: URL, within playbackQueue: [URL])
    func playTracks(_ trackIDs: [URL])
    func enqueueTrack(_ trackID: URL)
    func playStream(url: URL, title: String, artist: String, imageAssetName: String?)
    func playAll()
    func toggleShuffle()
    func isShuffleEnabled() -> Bool
}

extension MusicPlayerController {
    func libraryTracks() -> [LibraryTrack] { [] }
    func requestMetadata(for trackIDs: [URL]) {}
    func playTrack(_ trackID: URL) {}
    func playTrack(_ trackID: URL, within playbackQueue: [URL]) {
        playTrack(trackID)
    }
    func playTracks(_ trackIDs: [URL]) {}
    func enqueueTrack(_ trackID: URL) {}
    func playStream(url: URL, title: String, artist: String, imageAssetName: String?) {}
    func playAll() {}
    func toggleShuffle() {}
    func isShuffleEnabled() -> Bool { false }
}

class PlaybackModel: ObservableObject {
    private enum LastPlaybackSource: String {
        case stream
        case libraryTrack
    }

    private struct LastPlaybackSnapshot {
        let source: LastPlaybackSource
        let trackID: URL
        let title: String
        let artist: String
        let currentTime: Double
        let imageAssetName: String?
    }

    private enum LastPlaybackStorageKey {
        static let source = "playback.last.source"
        static let trackID = "playback.last.trackID"
        static let title = "playback.last.title"
        static let artist = "playback.last.artist"
        static let currentTime = "playback.last.currentTime"
        static let imageAssetName = "playback.last.imageAssetName"
    }

    static let dromosStream = StreamStation(
        id: "dromos-fm",
        title: "Dromos FM",
        subtitle: "Live Radio",
        artist: "Live Stream",
        url: URL(string: "https://n39a-eu.rcs.revma.com/10q3enqxbfhvv")!,
        iconAssetName: "DromosIcon"
    )

    static let bloombergUSStream = StreamStation(
        id: "bloomberg-tv-us",
        title: "Bloomberg TV+ US",
        subtitle: "Live TV",
        artist: "Bloomberg",
        url: URL(
            string: "https://www.bloomberg.com/media-manifest/streams/phoenix-us.m3u8"
        )!,
        iconAssetName: nil
    )

    @Published var imageURL: URL?
    @Published var image: Image? = nil
    @Published var isPlaying: Bool = false
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var totalTime: Double = 1
    @Published var currentTime: Double = 0
    @Published var playerType: PlayerType
    @Published var isLiked: Bool? = nil
    @Published var longFormInfo: LongFormInfo? = nil
    @Published var libraryTracks: [LibraryTrack] = []
    @Published private(set) var libraryPlaybackQueue: LibraryPlaybackQueue =
        .fullLibrary
    @Published var currentTrackID: URL? = nil
    @Published var isShuffleEnabled: Bool = false
    @Published var librarySearchText: String = ""
    @Published var isLibrarySearchFocused: Bool = false

    private let preferences: MusicPlayerPreferencesModel
    private var controller: MusicPlayerController
    private var timer: Timer?
    private var libraryRefreshTimer: Timer?

    private var folderCancellable: AnyCancellable?
    private var spotifyLikeStateCancellable: AnyCancellable?
    private var librarySearchIndex: [URL: String] = [:]

    var playerIconName: String {
        return "SpotifyIcon"
    }

    var isLikingImplemented: Bool {
        return false
    }

    var supportsLibraryBrowser: Bool {
        return true
    }

    var streams: [StreamStation] {
        [Self.dromosStream, Self.bloombergUSStream]
    }

    var shouldOpenStreamsOnLaunch: Bool {
        guard preferences.resumeLastPlaybackOnLaunch else { return false }
        return loadLastPlaybackSnapshot()?.source == .stream
    }

    var canQueueLibraryTracks: Bool {
        currentTrackID?.isFileURL == true
    }

    init(preferences: MusicPlayerPreferencesModel) {
        self.preferences = preferences
        self.controller = MusicFolderController(preferences: preferences)
        self.playerType = .musicFolder
        self.isShuffleEnabled = controller.isShuffleEnabled()

        fetchInfo()
        refreshLibrary()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] _ in
            self?.fetchInfo()
        }
        libraryRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: 15,
            repeats: true
        ) { [weak self] _ in
            self?.refreshLibrary()
        }

        folderCancellable = preferences.$musicFolderBookmarkData
            .sink { [weak self] _ in
                guard let self = self, self.playerType == .musicFolder else {
                    return
                }
                self.refreshLibrary()
                self.fetchInfo()
            }

        spotifyLikeStateCancellable = NotificationCenter.default.publisher(
            for: .spotifyLikeStateDidUpdate
        )
        .sink { [weak self] _ in
            self?.fetchInfo()
        }
    }

    deinit {
        timer?.invalidate()
        libraryRefreshTimer?.invalidate()
        folderCancellable?.cancel()
        spotifyLikeStateCancellable?.cancel()
    }

    func fetchInfo() {
        guard let info = controller.fetchNowPlayingInfo() else {
            reset()
            return
        }

        let displayText = computeDisplayText(from: info)

        DispatchQueue.main.async {
            self.title = displayText.title
            self.artist = displayText.artist
            self.isPlaying = info.isPlaying
            self.imageURL = info.imageURL
            self.totalTime = info.totalTime
            self.currentTime = info.currentTime
            self.image = info.image
            self.isLiked = info.isLiked
            self.longFormInfo = info.longFormInfo
            self.currentTrackID = info.trackID
            self.isShuffleEnabled = self.controller.isShuffleEnabled()
            self.persistLastPlaybackSnapshot(from: info)

            NotificationCenter.default.post(
                name: .contentModelDidUpdate,
                object: nil
            )
        }
    }

    func togglePlayPause() {
        // Execute the command first
        controller.togglePlayPause()
        
        // Small delay to allow the music player to process, then update UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.isPlaying.toggle()
            self.notifyModelUpdate()
        }
        
        delayedFetch()
    }

    func skipForward() {
        controller.skipForward()
        delayedFetch()
    }

    func skipBack() {
        controller.skipBack()
        delayedFetch()
    }

    func toggleLiked() {
        let previousLikeStatus = self.isLiked

        // Immediately update like status for UI responsiveness
        if let previous = previousLikeStatus {
            isLiked = !previous
        }
        
        // Send notification to update status bar immediately
        notifyModelUpdate()

        controller.toggleLiked()
        delayedFetch()
    }

    func likeTrack() {
        // Immediately update like status for UI responsiveness
        isLiked = true
        
        // Send notification to update status bar immediately
        notifyModelUpdate()
        
        controller.likeTrack()
    }

    func unlikeTrack() {
        // Immediately update like status for UI responsiveness
        isLiked = false
        
        // Send notification to update status bar immediately
        notifyModelUpdate()
        
        controller.unlikeTrack()
    }

    func updatePlaybackPosition(to seconds: Double) {
        controller.updatePlaybackPosition(to: seconds)
        self.currentTime = seconds
    }

    func seek(by delta: Double) {
        let clampedTargetTime = min(
            max(currentTime + delta, 0),
            max(totalTime, 0)
        )
        updatePlaybackPosition(to: clampedTargetTime)
        notifyModelUpdate()
        delayedFetch()
    }

    func openMusicApp() {
        controller.openApp()
    }

    func toggleShuffle() {
        controller.toggleShuffle()
        isShuffleEnabled = controller.isShuffleEnabled()
        notifyModelUpdate()
    }

    func refreshLibrary() {
        if !supportsLibraryBrowser {
            if !libraryTracks.isEmpty {
                DispatchQueue.main.async {
                    self.libraryTracks = []
                    self.librarySearchIndex = [:]
                }
            }
            return
        }

        let tracks = controller.libraryTracks()
        DispatchQueue.main.async {
            if self.libraryTracks != tracks {
                self.libraryTracks = tracks
                self.rebuildLibrarySearchIndex(with: tracks)
            }
        }
    }

    func playLibraryTrack(
        _ track: LibraryTrack,
        within visibleTracks: [LibraryTrack],
        query: String
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            libraryPlaybackQueue = .fullLibrary
            controller.playTrack(track.id)
        } else {
            libraryPlaybackQueue = .filtered(
                query: trimmedQuery,
                count: visibleTracks.count
            )
            controller.playTrack(track.id, within: visibleTracks.map(\.id))
        }
        delayedFetch()
    }

    func playStream(
        url: URL,
        title: String,
        artist: String = "Live Stream",
        imageAssetName: String? = nil
    ) {
        controller.playStream(
            url: url,
            title: title,
            artist: artist,
            imageAssetName: imageAssetName
        )
        delayedFetch()
    }

    func playAllFromLibrary() {
        libraryPlaybackQueue = .fullLibrary
        controller.playAll()
        delayedFetch()
    }

    func playFilteredLibraryTracks(_ tracks: [LibraryTrack], query: String) {
        let trackIDs = tracks.map(\.id)
        guard !trackIDs.isEmpty else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            libraryPlaybackQueue = .fullLibrary
        } else {
            libraryPlaybackQueue = .filtered(
                query: trimmedQuery,
                count: tracks.count
            )
        }
        controller.playTracks(trackIDs)
        delayedFetch()
    }

    func enqueueLibraryTrack(_ track: LibraryTrack) {
        controller.enqueueTrack(track.id)
        let isShuffleEnabled = controller.isShuffleEnabled()
        guard self.isShuffleEnabled != isShuffleEnabled else { return }
        self.isShuffleEnabled = isShuffleEnabled
        notifyModelUpdate()
    }

    func requestMetadataForTracks(_ trackIDs: [URL]) {
        controller.requestMetadata(for: trackIDs)
    }

    func matchesLibraryTrack(_ track: LibraryTrack, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }
        guard let searchable = librarySearchIndex[track.id] else {
            return false
        }
        return searchable.contains(normalized)
    }

    func restoreLastPlaybackOnLaunchIfNeeded() {
        guard preferences.resumeLastPlaybackOnLaunch else { return }
        guard currentTrackID == nil else { return }
        guard let snapshot = loadLastPlaybackSnapshot() else { return }

        switch snapshot.source {
        case .stream:
            playStream(
                url: snapshot.trackID,
                title: snapshot.title,
                artist: snapshot.artist,
                imageAssetName: snapshot.imageAssetName
            )
        case .libraryTrack:
            controller.playTrack(snapshot.trackID)
            if snapshot.currentTime > 0 {
                controller.updatePlaybackPosition(to: snapshot.currentTime)
            }
            delayedFetch()
        }
    }

    private func delayedFetch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.fetchInfo()
        }
    }
    
    private func notifyModelUpdate() {
        NotificationCenter.default.post(
            name: .contentModelDidUpdate,
            object: nil
        )
    }

    private func reset() {
        DispatchQueue.main.async {
            self.title = ""
            self.artist = ""
            self.isPlaying = false
            self.imageURL = nil
            self.currentTime = 0
            self.totalTime = 1
            self.image = nil
            self.isLiked = nil
            self.longFormInfo = nil
            self.currentTrackID = nil
            self.notifyModelUpdate()
        }
    }

    private func rebuildLibrarySearchIndex(with tracks: [LibraryTrack]) {
        var nextIndex: [URL: String] = [:]
        nextIndex.reserveCapacity(tracks.count)

        for track in tracks {
            nextIndex[track.id] = [
                track.title,
                track.artist,
                track.album ?? "",
            ]
            .joined(separator: " ")
            .lowercased()
        }

        librarySearchIndex = nextIndex
    }

    private func persistLastPlaybackSnapshot(from info: PlaybackInfo) {
        guard let trackID = info.trackID else { return }

        let source: LastPlaybackSource = trackID.isFileURL
            ? .libraryTrack : .stream
        let imageAssetName = stream(for: trackID)?.iconAssetName

        let defaults = UserDefaults.standard
        defaults.set(source.rawValue, forKey: LastPlaybackStorageKey.source)
        defaults.set(trackID.absoluteString, forKey: LastPlaybackStorageKey.trackID)
        defaults.set(info.title, forKey: LastPlaybackStorageKey.title)
        defaults.set(info.artist, forKey: LastPlaybackStorageKey.artist)
        defaults.set(max(info.currentTime, 0), forKey: LastPlaybackStorageKey.currentTime)
        defaults.set(imageAssetName, forKey: LastPlaybackStorageKey.imageAssetName)
    }

    private func loadLastPlaybackSnapshot() -> LastPlaybackSnapshot? {
        let defaults = UserDefaults.standard

        guard
            let sourceRaw = defaults.string(forKey: LastPlaybackStorageKey.source),
            let source = LastPlaybackSource(rawValue: sourceRaw),
            let trackIDRaw = defaults.string(forKey: LastPlaybackStorageKey.trackID),
            let trackID = URL(string: trackIDRaw)
        else {
            return nil
        }

        let title = defaults.string(forKey: LastPlaybackStorageKey.title) ?? ""
        let artist = defaults.string(forKey: LastPlaybackStorageKey.artist) ?? "Live Stream"
        let currentTime = defaults.double(forKey: LastPlaybackStorageKey.currentTime)
        let imageAssetName = defaults.string(forKey: LastPlaybackStorageKey.imageAssetName)

        return LastPlaybackSnapshot(
            source: source,
            trackID: trackID,
            title: title.isEmpty ? "Live Stream" : title,
            artist: artist.isEmpty ? "Live Stream" : artist,
            currentTime: max(currentTime, 0),
            imageAssetName: imageAssetName
        )
    }

    private func stream(for url: URL) -> StreamStation? {
        streams.first { $0.url == url }
    }

    private func computeDisplayText(from info: PlaybackInfo)
        -> (artist: String, title: String)
    {
        guard let longFormInfo = info.longFormInfo else {
            return (info.artist, info.title)
        }

        let authorText = longFormInfo.authors.joined(separator: ", ")
        let baseTitle =
            longFormInfo.title.isEmpty ? info.title : longFormInfo.title
        let segmentTitle = longFormInfo.segmentTitle?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let titleText: String
        switch preferences.longFormTitleStyle {
        case .titleOnly:
            titleText = baseTitle
        case .segmentOnly:
            titleText = segmentTitle?.isEmpty == false ? segmentTitle!
                : baseTitle
        case .titleAndSegment:
            if let segment = segmentTitle,
                !segment.isEmpty,
                segment.caseInsensitiveCompare(baseTitle) != .orderedSame
            {
                titleText = "\(baseTitle) — \(segment)"
            } else {
                titleText = baseTitle
            }
        }

        let artistText = authorText.isEmpty ? info.artist : authorText

        return (artistText, titleText)
    }
}

func runAppleScript(_ script: String) -> String? {
    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: script) {
        let output = scriptObject.executeAndReturnError(&error)
        return output.stringValue
    }
    return nil
}

func openApp(bundleIdentifier: String) {
    guard
        let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
    else {
        print("App with bundle ID \(bundleIdentifier) not found.")
        return
    }

    let config = NSWorkspace.OpenConfiguration()
    NSWorkspace.shared.openApplication(at: url, configuration: config) {
        app,
        error in
        if let error = error {
            print("Failed to open app: \(error.localizedDescription)")
        }
    }
}
