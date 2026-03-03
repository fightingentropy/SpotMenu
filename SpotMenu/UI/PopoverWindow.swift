import Cocoa
import SwiftUI

class PopoverWindow: NSPanel {
    init<Content: View>(rootView: Content, size: CGSize) {
        let hostingView = NSHostingView(rootView: rootView)
        let contentRect = NSRect(origin: .zero, size: size)

        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )

        self.isReleasedWhenClosed = false
        self.level = .floating
        self.collectionBehavior = [.transient, .canJoinAllSpaces]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.ignoresMouseEvents = false
        self.becomesKeyOnlyIfNeeded = true
        hostingView.layer?.masksToBounds = true

        self.contentView = hostingView
    }

    func updateSize(_ size: CGSize) {
        setContentSize(size)
        var frame = self.frame
        frame.size = size
        setFrame(frame, display: true)
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }
}
