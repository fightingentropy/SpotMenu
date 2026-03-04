import SwiftUI

final class StatusItemConfigurator {
    static func configure(
        statusItem: NSStatusItem,
        statusItemModel: StatusItemModel,
        menuBarPreferencesModel: MenuBarPreferencesModel,
        musicPlayerPreferencesModel: MusicPlayerPreferencesModel,
        playBackModel: PlaybackModel,
        toggleAction: Selector,
        target: AnyObject
    ) {
        let view = StatusItemView(
            model: statusItemModel,
            menuBarPreferencesModel: menuBarPreferencesModel,
            musicPlayerPreferencesModel: musicPlayerPreferencesModel,
            playbackModel: playBackModel
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.layout()

        if let button = statusItem.button {
            button.image = NSImage()
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.centerXAnchor.constraint(
                    equalTo: button.centerXAnchor
                ),
                hostingView.centerYAnchor.constraint(
                    equalTo: button.centerYAnchor
                ),
            ])
            button.action = toggleAction
            button.target = target
        }
    }

    static func updateWidth(statusItem: NSStatusItem, maxWidth: CGFloat) {
        guard
            let hostingView = statusItem.button?.subviews.compactMap({
                $0 as? NSHostingView<StatusItemView>
            }).first
        else {
            return
        }

        let measuredWidth = hostingView.fittingSize.width > 0
            ? hostingView.fittingSize.width
            : hostingView.intrinsicContentSize.width
        let targetWidth = min(measuredWidth, maxWidth)

        if abs(statusItem.length - targetWidth) > 0.5 {
            statusItem.length = targetWidth
        }
    }
}
