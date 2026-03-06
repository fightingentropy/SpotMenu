import AppKit
import SwiftUI

class PopoverManager {
    private var window: PopoverWindow
    private weak var lastAnchorButton: NSStatusBarButton?
    var onVisibilityChanged: ((Bool) -> Void)?
    var onTextInputFocusChanged: ((Bool) -> Void)?

    var isVisible: Bool {
        window.isVisible
    }

    var isTextInputFocused: Bool {
        window.firstResponder is NSTextView
    }

    init<Content: View>(contentView: Content, size: CGSize) {
        self.window = PopoverWindow(rootView: contentView, size: size)
        self.window.onTextInputFocusChanged = { [weak self] isFocused in
            self?.onTextInputFocusChanged?(isFocused)
        }
    }

    func toggle(relativeTo button: NSStatusBarButton?) {
        guard let button = button else { return }
        lastAnchorButton = button

        if window.isVisible {
            dismiss()
        } else {
            show(relativeTo: button)
        }
    }

    func updateSize(_ size: CGSize) {
        window.updateSize(size)

        if window.isVisible, let button = lastAnchorButton {
            positionWindow(relativeTo: button)
        }
    }

    func setSeekHandlers(
        onSeekForward: @escaping () -> Void,
        onSeekBackward: @escaping () -> Void
    ) {
        window.onSeekForward = onSeekForward
        window.onSeekBackward = onSeekBackward
    }

    func setPlaybackHandlers(onPlayPause: @escaping () -> Void) {
        window.onPlayPause = onPlayPause
    }

    func clearFirstResponder() {
        guard window.isVisible else { return }
        window.makeFirstResponder(nil)
    }

    func focus() {
        guard window.isVisible else { return }
        if let button = lastAnchorButton {
            positionWindow(relativeTo: button)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func show(relativeTo button: NSStatusBarButton) {
        lastAnchorButton = button

        positionWindow(relativeTo: button)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        onVisibilityChanged?(true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 1
        }
    }

    private func positionWindow(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window,
            let screen = buttonWindow.screen
        else { return }

        let buttonFrame = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )

        let popoverSize = window.frame.size

        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let spacingBelowMenuBar: CGFloat = 0
        let totalOffset = menuBarHeight + spacingBelowMenuBar

        let popoverY = screen.frame.maxY - totalOffset - popoverSize.height
        let popoverX = buttonFrame.midX - popoverSize.width / 2

        window.setFrameOrigin(NSPoint(x: popoverX, y: popoverY))
    }

    func dismiss() {
        guard window.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            window.animator().alphaValue = 0
        } completionHandler: {
            self.window.orderOut(nil)
            self.window.alphaValue = 1
            self.onVisibilityChanged?(false)
        }
    }
}
