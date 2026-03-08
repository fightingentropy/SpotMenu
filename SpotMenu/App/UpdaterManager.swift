import Foundation
#if !LOCAL_BUILD
import Sparkle
#endif

/// Shared Sparkle updater controller - must be a single instance app-wide
@MainActor
final class UpdaterManager {
    static let shared = UpdaterManager()

    private(set) var isConfigured = false

    #if !LOCAL_BUILD
    private let controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }
    #endif

    private init(bundle: Bundle = .main) {
        #if LOCAL_BUILD
        isConfigured = false
        #else
        let feedURL = Self.stringValue(for: "SUFeedURL", in: bundle)
        let publicKey = Self.stringValue(for: "SUPublicEDKey", in: bundle)
        let configured = feedURL != nil && publicKey != nil

        isConfigured = configured

        guard configured else {
            controller = nil
            return
        }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Enable automatic update checks by default on first launch
        // Menu bar apps don't reliably show Sparkle's permission prompt
        if !UserDefaults.standard.bool(forKey: "hasConfiguredSparkle") {
            controller?.updater.automaticallyChecksForUpdates = true
            UserDefaults.standard.set(true, forKey: "hasConfiguredSparkle")
        }
        #endif
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            #if !LOCAL_BUILD
            return updater?.automaticallyChecksForUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if !LOCAL_BUILD
            updater?.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get {
            #if !LOCAL_BUILD
            return updater?.automaticallyDownloadsUpdates ?? false
            #else
            return false
            #endif
        }
        set {
            #if !LOCAL_BUILD
            updater?.automaticallyDownloadsUpdates = newValue
            #endif
        }
    }

    var lastUpdateCheckDate: Date? {
        #if !LOCAL_BUILD
        return updater?.lastUpdateCheckDate
        #else
        return nil
        #endif
    }

    func checkForUpdates() {
        #if !LOCAL_BUILD
        updater?.checkForUpdates()
        #endif
    }

    private static func stringValue(for key: String, in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
