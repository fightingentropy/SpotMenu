import Combine
import KeyboardShortcuts
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private static let reopenPopoverNotification = Notification.Name(
        "com.github.kmikiy.SpotMenu.reopenPopover"
    )

    private struct StatusItemRenderSnapshot: Equatable {
        let artist: String
        let title: String
        let isPlaying: Bool
        let isLiked: Bool?
        let playerIconName: String
        let isLikingImplemented: Bool
        let likingEnabled: Bool
        let showArtist: Bool
        let showTitle: Bool
        let showIsLikedIcon: Bool
        let showAppIcon: Bool
        let compactView: Bool
        let hideArtistWhenPaused: Bool
        let hideTitleWhenPaused: Bool
        let fontWeightCompactTop: MenuBarFontWeight
        let fontWeightCompactBottom: MenuBarFontWeight
        let fontWeightNormal: MenuBarFontWeight
        let maxStatusItemWidth: CGFloat
    }

    var statusItem: NSStatusItem!
    var statusItemModel = StatusItemModel()
    var playbackAppearancePreferencesModel =
        PlaybackAppearancePreferencesModel()
    var musicPlayerPreferencesModel = MusicPlayerPreferencesModel()
    var playbackModel: PlaybackModel!
    var menuBarPreferencesModel = MenuBarPreferencesModel()
    var popoverManager: PopoverManager!
    var preferencesWindow: NSWindow?
    var eventMonitor: Any?
    var escapeKeyMonitor: Any?
    var playbackUpdateObserver: NSObjectProtocol?
    var menuBarPreferencesModelCancellable: AnyCancellable?
    var musicPlayerPreferencesModelCancellable: AnyCancellable?
    var playbackAppearanceCancellable: AnyCancellable?
    var isUsingCustomStatusView = false
    private var lastStatusItemRenderSnapshot: StatusItemRenderSnapshot?
    private var isStatusItemWidthUpdateScheduled = false
    private var shouldAbortLaunch = false
    private var reopenObserver: NSObjectProtocol?
    private var appToRefocusAfterEscape: NSRunningApplication?
    private var foregroundAppObserver: NSObjectProtocol?
    private var lastNonSpotMenuFrontmostApp: NSRunningApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if activateExistingInstanceIfNeeded() {
            shouldAbortLaunch = true
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !shouldAbortLaunch else { return }
        NSApp.setActivationPolicy(.accessory)

        playbackModel = PlaybackModel(preferences: musicPlayerPreferencesModel)

        // Configure status item and button
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        // Handle right-click menu
        NSEvent.addLocalMonitorForEvents(matching: [.rightMouseUp]) {
            [weak self] event in
            self?.handleRightClick(event: event)
            return nil
        }

        // Handle Escape reliably even in non-activating panel contexts.
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown])
        { [weak self] event in
            guard let self else { return event }
            guard self.popoverManager.isVisible else { return event }
            guard event.keyCode == 53 else { return event }  // Escape

            self.popoverManager.dismiss(triggeredByEscape: true)
            return nil
        }

        // Observe playback updates
        playbackUpdateObserver = NotificationCenter.default.addObserver(
            forName: .contentModelDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusItem()
        }

        // Set up popover manager
        let playbackView = PlaybackView(
            model: playbackModel,
            preferences: playbackAppearancePreferencesModel,
            musicPlayerPreferencesModel: musicPlayerPreferencesModel
        )
        popoverManager = PopoverManager(
            contentView: playbackView,
            size: playbackAppearancePreferencesModel.popoverSize
        )
        popoverManager.onVisibilityChanged = { [weak self] isVisible in
            self?.updatePlayPauseShortcutRegistration(isPopoverVisible: isVisible)
        }
        popoverManager.onEscapePressed = { [weak self] in
            self?.restoreFocusAfterEscapeDismiss()
        }
        popoverManager.setSeekHandlers(onSeekForward: { [weak self] in
            self?.playbackModel.seek(by: 10)
        }, onSeekBackward: { [weak self] in
            self?.playbackModel.seek(by: -10)
        })

        // Global event monitor to dismiss popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] _ in
            self?.popoverManager.dismiss()
        }

        StatusItemConfigurator.configure(
            statusItem: statusItem,
            statusItemModel: statusItemModel,
            menuBarPreferencesModel: menuBarPreferencesModel,
            musicPlayerPreferencesModel: musicPlayerPreferencesModel,
            playBackModel: playbackModel,
            toggleAction: #selector(togglePopover),
            target: self
        )

        configurePlaybackShortcutDefaults()
        setupKeyboardShortcuts()
        updatePlayPauseShortcutRegistration(isPopoverVisible: false)
        updateStatusItem()
        setupReopenObserver()
        setupForegroundAppTracking()

        menuBarPreferencesModelCancellable = menuBarPreferencesModel
            .objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }

        musicPlayerPreferencesModelCancellable = musicPlayerPreferencesModel
            .$likingEnabled
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }

        playbackAppearanceCancellable = playbackAppearancePreferencesModel
            .$showExpandedLibraryView
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.popoverManager.updateSize(
                    self.playbackAppearancePreferencesModel.popoverSize
                )
            }

        playbackModel.restoreLastPlaybackOnLaunchIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        SpotifyAuthManager.shared.handleRedirect(url: url)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showPopoverIfHidden()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
        }
        if let observer = playbackUpdateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let reopenObserver {
            DistributedNotificationCenter.default().removeObserver(reopenObserver)
        }
        if let foregroundAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                foregroundAppObserver
            )
        }
        menuBarPreferencesModelCancellable?.cancel()
        musicPlayerPreferencesModelCancellable?.cancel()
        playbackAppearanceCancellable?.cancel()
    }

    private func configurePlaybackShortcutDefaults() {
        let defaultPlayPauseShortcut = KeyboardShortcuts.Shortcut(
            .space,
            modifiers: []
        )
        let defaultNextTrackShortcut = KeyboardShortcuts.Shortcut(
            .rightArrow,
            modifiers: [.command]
        )
        let defaultPreviousTrackShortcut = KeyboardShortcuts.Shortcut(
            .leftArrow,
            modifiers: [.command]
        )
        let legacyNextTrackShortcut = KeyboardShortcuts.Shortcut(
            .x,
            modifiers: []
        )
        let legacyPreviousTrackShortcut = KeyboardShortcuts.Shortcut(
            .z,
            modifiers: []
        )

        if KeyboardShortcuts.getShortcut(for: .playPause) == nil {
            KeyboardShortcuts.setShortcut(
                defaultPlayPauseShortcut,
                for: .playPause
            )
        }

        if let currentNextShortcut = KeyboardShortcuts.getShortcut(
            for: .nextTrack
        ) {
            if currentNextShortcut == legacyNextTrackShortcut {
                KeyboardShortcuts.setShortcut(
                    defaultNextTrackShortcut,
                    for: .nextTrack
                )
            }
        } else {
            KeyboardShortcuts.setShortcut(
                defaultNextTrackShortcut,
                for: .nextTrack
            )
        }

        if let currentPreviousShortcut = KeyboardShortcuts.getShortcut(
            for: .previousTrack
        ) {
            if currentPreviousShortcut == legacyPreviousTrackShortcut {
                KeyboardShortcuts.setShortcut(
                    defaultPreviousTrackShortcut,
                    for: .previousTrack
                )
            }
        } else {
            KeyboardShortcuts.setShortcut(
                defaultPreviousTrackShortcut,
                for: .previousTrack
            )
        }
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .playPause) { [weak self] in
            guard let self, self.popoverManager.isVisible else { return }
            guard !self.popoverManager.isTextInputFocused else { return }
            self.popoverManager.clearFirstResponder()
            self.playbackModel.togglePlayPause()
            // Immediately update status item for keyboard shortcut feedback
            DispatchQueue.main.async {
                self.updateStatusItem()
            }
        }
        KeyboardShortcuts.onKeyDown(for: .nextTrack) { [weak self] in
            self?.popoverManager.clearFirstResponder()
            self?.playbackModel.skipForward()
            // Immediately update status item for keyboard shortcut feedback
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        KeyboardShortcuts.onKeyDown(for: .previousTrack) { [weak self] in
            self?.popoverManager.clearFirstResponder()
            self?.playbackModel.skipBack()
            // Immediately update status item for keyboard shortcut feedback
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleLike) { [weak self] in
            self?.popoverManager.clearFirstResponder()
            self?.playbackModel.toggleLiked()
            // Immediately update status item for keyboard shortcut feedback
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .likeTrack) { [weak self] in
            self?.popoverManager.clearFirstResponder()
            self?.playbackModel.likeTrack()
            // Immediately update status item for keyboard shortcut feedback
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .unlikeTrack) { [weak self] in
            self?.popoverManager.clearFirstResponder()
            self?.playbackModel.unlikeTrack()
            // Immediately update status item for keyboard shortcut feedback
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
    }

    private func updatePlayPauseShortcutRegistration(isPopoverVisible: Bool) {
        if isPopoverVisible {
            KeyboardShortcuts.enable(.playPause)
        } else {
            KeyboardShortcuts.disable(.playPause)
        }
    }

    func updateStatusItem() {
        let snapshot = StatusItemRenderSnapshot(
            artist: playbackModel.artist,
            title: playbackModel.title,
            isPlaying: playbackModel.isPlaying,
            isLiked: playbackModel.isLiked,
            playerIconName: playbackModel.playerIconName,
            isLikingImplemented: playbackModel.isLikingImplemented,
            likingEnabled: musicPlayerPreferencesModel.likingEnabled,
            showArtist: menuBarPreferencesModel.showArtist,
            showTitle: menuBarPreferencesModel.showTitle,
            showIsLikedIcon: menuBarPreferencesModel.showIsLikedIcon,
            showAppIcon: menuBarPreferencesModel.showAppIcon,
            compactView: menuBarPreferencesModel.compactView,
            hideArtistWhenPaused: menuBarPreferencesModel.hideArtistWhenPaused,
            hideTitleWhenPaused: menuBarPreferencesModel.hideTitleWhenPaused,
            fontWeightCompactTop: menuBarPreferencesModel.fontWeightCompactTop,
            fontWeightCompactBottom: menuBarPreferencesModel
                .fontWeightCompactBottom,
            fontWeightNormal: menuBarPreferencesModel.fontWeightNormal,
            maxStatusItemWidth: menuBarPreferencesModel.maxStatusItemWidth
        )

        guard snapshot != lastStatusItemRenderSnapshot else { return }
        lastStatusItemRenderSnapshot = snapshot

        if statusItemModel.artist != snapshot.artist {
            statusItemModel.artist = snapshot.artist
        }
        if statusItemModel.title != snapshot.title {
            statusItemModel.title = snapshot.title
        }
        if statusItemModel.isPlaying != snapshot.isPlaying {
            statusItemModel.isPlaying = snapshot.isPlaying
        }
        if statusItemModel.isLiked != snapshot.isLiked {
            statusItemModel.isLiked = snapshot.isLiked
        }
        if statusItemModel.playerIconName != snapshot.playerIconName {
            statusItemModel.playerIconName = snapshot.playerIconName
        }

        scheduleStatusItemWidthUpdate()
    }

    private func scheduleStatusItemWidthUpdate() {
        guard !isStatusItemWidthUpdateScheduled else { return }
        isStatusItemWidthUpdateScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isStatusItemWidthUpdateScheduled = false

            StatusItemConfigurator.updateWidth(
                statusItem: self.statusItem,
                maxWidth: self.menuBarPreferencesModel.maxStatusItemWidth
            )
        }
    }

    @objc func togglePopover() {
        popoverManager.toggle(relativeTo: statusItem.button)
    }

    private func showPopoverIfHidden() {
        guard let button = statusItem.button else { return }
        if popoverManager.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        captureAppToRefocusAfterEscape()
        popoverManager.toggle(relativeTo: button)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func captureAppToRefocusAfterEscape() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard
            let frontmost = NSWorkspace.shared.frontmostApplication,
            frontmost.processIdentifier != currentPID
        else {
            appToRefocusAfterEscape = lastNonSpotMenuFrontmostApp
            return
        }

        appToRefocusAfterEscape = frontmost
    }

    private func restoreFocusAfterEscapeDismiss() {
        defer { appToRefocusAfterEscape = nil }
        guard let app = appToRefocusAfterEscape else { return }
        guard !app.isTerminated else { return }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func handleRightClick(event: NSEvent) {
        guard let button = statusItem.button,
            button.frame.contains(
                button.convert(event.locationInWindow, from: nil)
            )
        else { return }

        popoverManager.dismiss()
        statusItem.menu = MenuBuilder.build(delegate: self)
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc func refreshAction() {
        playbackModel.fetchInfo()
    }

    @objc func preferencesAction() {
        if preferencesWindow == nil {
            let hostingController = NSHostingController(
                rootView: PreferencesView(
                    menuBarPreferencesModel: menuBarPreferencesModel,
                    playbackModel: playbackModel,
                    musicPlayerPreferencesModel: musicPlayerPreferencesModel,
                    playbackAppearancePreferencesModel:
                        playbackAppearancePreferencesModel
                )
            )

            let window = NSWindow(contentViewController: hostingController)
            window.title = "Settings"
            window.styleMask = [
                .titled, .closable, .miniaturizable, .resizable,
                .fullSizeContentView,
            ]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden

            // Configure toolbar for modern macOS look
            let toolbar = NSToolbar(identifier: "PreferencesToolbar")
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unified

            // Set window size
            window.setContentSize(NSSize(width: 700, height: 500))
            window.minSize = NSSize(width: 600, height: 400)
            window.center()
            window.isReleasedWhenClosed = false
            window.level = .normal

            // Modern rounded corners
            window.backgroundColor = .clear
            window.isOpaque = false

            preferencesWindow = window
        }

        preferencesWindow?.makeKeyAndOrderFront(nil)
        preferencesWindow?.makeMain()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    private func activateExistingInstanceIfNeeded() -> Bool {
        guard
            let bundleIdentifier = Bundle.main.bundleIdentifier
        else { return false }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let runningInstances = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        guard
            let existingInstance = runningInstances.first(where: {
                $0.processIdentifier != currentProcessIdentifier
            })
        else { return false }

        DistributedNotificationCenter.default().postNotificationName(
            Self.reopenPopoverNotification,
            object: bundleIdentifier,
            userInfo: nil,
            options: [.deliverImmediately]
        )
        existingInstance.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        return true
    }

    private func setupReopenObserver() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.reopenPopoverNotification,
            object: bundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            self?.showPopoverIfHidden()
        }
    }

    private func setupForegroundAppTracking() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
            frontmost.processIdentifier != currentPID
        {
            lastNonSpotMenuFrontmostApp = frontmost
        }

        foregroundAppObserver = NSWorkspace.shared.notificationCenter
            .addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                let currentPID = ProcessInfo.processInfo.processIdentifier
                guard
                    let app =
                        notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                    app.processIdentifier != currentPID
                else { return }

                self.lastNonSpotMenuFrontmostApp = app
            }
    }

}

func nsImage<Content: View>(
    from view: Content,
    size: CGSize,
    scale: CGFloat = 1.0
) -> NSImage? {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)

    let rep = hostingView.bitmapImageRepForCachingDisplay(
        in: hostingView.bounds
    )
    guard let imageRep = rep else { return nil }

    hostingView.cacheDisplay(in: hostingView.bounds, to: imageRep)

    let nsImage = NSImage(size: size)
    nsImage.addRepresentation(imageRep)

    return nsImage
}
