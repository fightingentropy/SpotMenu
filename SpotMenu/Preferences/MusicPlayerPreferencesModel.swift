import Combine
import Foundation

class MusicPlayerPreferencesModel: ObservableObject {
    @Published var likingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(
                likingEnabled,
                forKey: "musicPlayer.likingEnabled"
            )
        }
    }

    @Published var spotifyClientID: String? {
        didSet {
            UserDefaults.standard.set(
                spotifyClientID,
                forKey: "spotify.clientID"
            )
        }
    }

    @Published var longFormTitleStyle: LongFormTitleStyle {
        didSet {
            UserDefaults.standard.set(
                longFormTitleStyle.rawValue,
                forKey: "spotify.longFormTitleStyle"
            )
        }
    }

    @Published var musicFolderBookmarkData: Data? {
        didSet {
            UserDefaults.standard.set(
                musicFolderBookmarkData,
                forKey: "musicPlayer.musicFolderBookmarkData"
            )
        }
    }

    init() {
        let defaults = UserDefaults.standard

        likingEnabled =
            defaults.object(forKey: "musicPlayer.likingEnabled") as? Bool ?? true

        spotifyClientID = defaults.string(forKey: "spotify.clientID")

        if let storedRaw = defaults.string(
            forKey: "spotify.longFormTitleStyle"
        ), let storedStyle = LongFormTitleStyle(rawValue: storedRaw) {
            longFormTitleStyle = storedStyle
        } else if let legacyAppend =
            defaults.object(
                forKey: "spotify.showAudiobookChapterInTitle"
            ) as? Bool
        {
            longFormTitleStyle =
                legacyAppend ? .titleAndSegment : .titleOnly
        } else {
            longFormTitleStyle = .titleOnly
        }

        musicFolderBookmarkData = defaults.data(
            forKey: "musicPlayer.musicFolderBookmarkData"
        )
    }

    func setMusicFolderURL(_ url: URL) throws {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        musicFolderBookmarkData = bookmarkData
    }

    func clearMusicFolderSelection() {
        musicFolderBookmarkData = nil
    }

    func resolveMusicFolderURL() -> URL? {
        guard let bookmarkData = musicFolderBookmarkData else {
            return defaultMusicFolderURL
        }

        var isStale = false
        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                try setMusicFolderURL(resolvedURL)
            }

            return resolvedURL
        } catch {
            return defaultMusicFolderURL
        }
    }

    var resolvedMusicFolderPath: String {
        resolveMusicFolderURL()?.path ?? defaultMusicFolderURL.path
    }

    private var defaultMusicFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music", isDirectory: true)
    }
}
