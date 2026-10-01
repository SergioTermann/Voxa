import AppKit

@MainActor
final class ModifierTapTrigger {
    var onTrigger: (() -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?
    private var monitor: Any?
    private var localMonitor: Any?
    private var sequence = ModifierTapSequence()
    private var lastPID: pid_t?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        onAvailabilityChanged?(monitor != nil)
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        monitor = nil
        localMonitor = nil
        sequence.reset()
        lastPID = nil
        onAvailabilityChanged?(false)
    }

    private func handle(_ event: NSEvent) {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if lastPID != pid { sequence.reset(); lastPID = pid }
        guard event.type == .flagsChanged, event.keyCode == 54,
              event.modifierFlags.rawValue & 0x08 == 0,
              event.modifierFlags.intersection([.control, .option, .shift]).isEmpty else {
            sequence.reset()
            return
        }
        // NX_DEVICERCMDKEYMASK distinguishes right Command from the left key.
        let down = event.modifierFlags.contains(.command)
        if sequence.change(isDown: down, at: event.timestamp) { onTrigger?() }
    }
}
