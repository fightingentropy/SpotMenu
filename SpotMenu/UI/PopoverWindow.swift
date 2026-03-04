import Cocoa
import SwiftUI

class PopoverWindow: NSPanel {
    var onSeekForward: (() -> Void)?
    var onSeekBackward: (() -> Void)?

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

    override func sendEvent(_ event: NSEvent) {
        if handleSeekKeyEvent(event) {
            return
        }

        super.sendEvent(event)
    }

    private func handleSeekKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown || event.type == .keyUp else {
            return false
        }

        guard !(firstResponder is NSTextView) else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        if modifiers.contains(.command)
            || modifiers.contains(.option)
            || modifiers.contains(.control)
            || modifiers.contains(.function)
        {
            return false
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased(),
            key == "x" || key == "z"
        else {
            return false
        }

        if event.type == .keyDown {
            if key == "x" {
                onSeekForward?()
            } else {
                onSeekBackward?()
            }
        }

        return true
    }
}
