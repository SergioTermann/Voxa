import Foundation

enum TextPolicy {
    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSecure(role: String?, subrole: String?) -> Bool {
        role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    static func canRestoreClipboard(ownedChangeCount: Int, currentChangeCount: Int) -> Bool {
        ownedChangeCount == currentChangeCount
    }
}

enum SpeechFailurePolicy {
    static func isSystemDictationDisabled(_ description: String) -> Bool {
        let normalized = description.lowercased()
        return normalized.contains("siri and dictation are disabled")
    }
}

struct SpaceSequence {
    static let maximumGap: TimeInterval = 0.32
    private var lastPress: TimeInterval?
    private var count = 0

    mutating func press(at time: TimeInterval) -> Bool {
        if let lastPress, time - lastPress > Self.maximumGap { count = 0 }
        lastPress = time
        count += 1
        if count == 3 { reset(); return true }
        return false
    }

    mutating func reset() { lastPress = nil; count = 0 }
}

struct ModifierTapSequence {
    private var pressedAt: TimeInterval?
    private var releasedAt: TimeInterval?

    mutating func change(isDown: Bool, at time: TimeInterval) -> Bool {
        if isDown {
            if pressedAt == nil { pressedAt = time }
            return false
        }
        guard let pressedAt, time - pressedAt <= 0.5 else { reset(); return false }
        self.pressedAt = nil
        if let releasedAt, pressedAt - releasedAt <= 0.65 {
            reset()
            return true
        }
        releasedAt = time
        return false
    }

    mutating func reset() { pressedAt = nil; releasedAt = nil }
}

enum AutoFinishPolicy {
    static func shouldFinish(now: TimeInterval, lastTextChange: TimeInterval, lastVoiceActivity: TimeInterval, hasText: Bool) -> Bool {
        hasText && now - lastTextChange >= 1.6 && now - lastVoiceActivity >= 1.6
    }
}
