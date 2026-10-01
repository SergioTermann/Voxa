import AppKit
import ApplicationServices

// Spaces are held briefly rather than deleting characters from the target editor.
// Three distinct presses within the interval consume the buffered spaces.
@MainActor
final class TripleSpaceTrigger {
    var onTrigger: (() -> Void)?
    var onAvailabilityChanged: ((Bool) -> Void)?
    var currentPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var replayForTesting: ((CGEvent) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: [CGEvent] = []
    private var counter = SpaceSequence()
    private var timer: Timer?
    private var swallowingRelease = false
    private var pendingPID: pid_t?
    private let marker: Int64 = 0x565243525350

    func start() {
        guard tap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                            options: .defaultTap, eventsOfInterest: mask,
                                            callback: { proxy, type, event, data in
            guard let data else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<TripleSpaceTrigger>.fromOpaque(data).takeUnretainedValue()
                return owner.handle(proxy: proxy, type: type, event: event)
            }
        }, userInfo: pointer) else {
            onAvailabilityChanged?(false)
            return
        }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        onAvailabilityChanged?(true)
    }

    func stop() {
        flush()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    func handle(proxy: CGEventTapProxy?, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == marker { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            flush(proxy: proxy)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let isSpace = event.getIntegerValueField(.keyboardEventKeycode) == 49
        if type == .keyUp && isSpace && swallowingRelease {
            if !pending.isEmpty, let copy = event.copy() { pending.append(copy) }
            swallowingRelease = false
            return nil
        }
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        let plain = event.flags.intersection(modifiers).isEmpty
        if type == .keyDown && isSpace && plain {
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                flush(proxy: proxy)
                swallowingRelease = false
                return Unmanaged.passUnretained(event)
            }
            let pid = currentPID()
            if pendingPID != nil && pendingPID != pid { discard() }
            pendingPID = pid
            if let copy = event.copy() { pending.append(copy) }
            swallowingRelease = true
            if counter.press(at: ProcessInfo.processInfo.systemUptime) {
                discard()
                DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
            } else {
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: SpaceSequence.maximumGap, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.flush() }
                }
                if let timer { RunLoop.main.add(timer, forMode: .common) }
            }
            return nil
        }
        if type == .keyDown || type == .flagsChanged || type == .leftMouseDown || type == .rightMouseDown {
            flush(proxy: proxy)
        }
        return Unmanaged.passUnretained(event)
    }

    private func flush(proxy: CGEventTapProxy? = nil) {
        let events = pending
        let originalPID = pendingPID
        discard()
        if !events.isEmpty { swallowingRelease = false }
        // Never replay buffered spaces into a different application.
        guard originalPID == currentPID() else { return }
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            if let replayForTesting { replayForTesting(event) }
            else if let proxy { event.tapPostEvent(proxy) }
            else { event.post(tap: .cgSessionEventTap) }
        }
    }

    private func discard() {
        timer?.invalidate()
        timer = nil
        pending.removeAll()
        counter.reset()
        pendingPID = nil
    }
}
