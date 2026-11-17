import AppKit

class WindowScrollObserver: NSView {
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) == true }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        resetScroll()
    }

    func resetScroll() {}

    func consumeScroll(_ event: NSEvent, at point: NSPoint) -> Bool { false }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, window.attachedSheet == nil,
              !isHiddenOrHasHiddenAncestor, event.momentumPhase.isEmpty else { return false }
        let point: NSPoint
        if event.windowNumber == window.windowNumber {
            point = event.locationInWindow
        } else if event.windowNumber == 0, window.isKeyWindow {
            point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        } else {
            return false
        }
        return consumeScroll(event, at: convert(point, from: nil))
    }
}
