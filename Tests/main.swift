import Foundation
import AppKit

func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError("FAIL: \(name)") }
    print("PASS: \(name)")
}
expect(TextPolicy.clean(" \n你好，世界。\n ") == "你好，世界。", "trim surrounding whitespace")
expect(TextPolicy.clean("\n \t").isEmpty, "do not paste empty speech")
expect(TextPolicy.clean("第一行\n第二行") == "第一行\n第二行", "preserve paragraphs")
expect(TextPolicy.isSecure(role: "AXTextField", subrole: "AXSecureTextField"), "reject password subrole")
expect(TextPolicy.isSecure(role: "AXSecureTextField", subrole: nil), "reject password role")
expect(!TextPolicy.isSecure(role: "AXTextArea", subrole: nil), "allow ordinary editor")
expect(TextPolicy.canRestoreClipboard(ownedChangeCount: 42, currentChangeCount: 42), "restore owned clipboard")
expect(!TextPolicy.canRestoreClipboard(ownedChangeCount: 42, currentChangeCount: 43), "preserve newer user clipboard")
expect(SpeechFailurePolicy.isSystemDictationDisabled("Siri and Dictation are disabled"), "recognize disabled system dictation")
expect(SpeechFailurePolicy.isSystemDictationDisabled("SIRI AND DICTATION ARE DISABLED."), "disabled error is case insensitive")
expect(!SpeechFailurePolicy.isSystemDictationDisabled("The Internet connection appears to be offline."), "network errors do not request system dictation")
var sequence = SpaceSequence()
expect(!sequence.press(at: 1.0), "single space is ordinary typing")
expect(!sequence.press(at: 1.2), "double space does not trigger")
expect(sequence.press(at: 1.4), "three fast spaces trigger")
expect(!sequence.press(at: 2.0), "new sequence after trigger")
expect(!sequence.press(at: 3.0), "slow spaces reset sequence")
expect(!sequence.press(at: 3.2), "only two spaces after reset")
sequence.reset()
expect(!sequence.press(at: 3.3), "non-space interruption resets sequence")

var commandTaps = ModifierTapSequence()
expect(!commandTaps.change(isDown: true, at: 1.0), "press Command does not trigger")
expect(!commandTaps.change(isDown: false, at: 1.1), "one Command tap does not trigger")
expect(!commandTaps.change(isDown: true, at: 1.25), "second Command down does not trigger")
expect(commandTaps.change(isDown: false, at: 1.35), "two short Command taps trigger on release")
expect(!commandTaps.change(isDown: true, at: 2.0), "hold begins without trigger")
expect(!commandTaps.change(isDown: false, at: 2.8), "long Command hold never triggers")
expect(!commandTaps.change(isDown: true, at: 3.0), "fresh Command press")
expect(!commandTaps.change(isDown: false, at: 3.1), "fresh Command release")
commandTaps.reset()
expect(!commandTaps.change(isDown: true, at: 3.2), "shortcut interruption resets taps")
expect(!commandTaps.change(isDown: false, at: 3.3), "Command shortcut is not double tap")
expect(!commandTaps.change(isDown: true, at: 4.0), "slow second tap starts")
expect(!commandTaps.change(isDown: false, at: 4.1), "slow taps do not trigger")
expect(!AutoFinishPolicy.shouldFinish(now: 5, lastTextChange: 2, lastVoiceActivity: 2, hasText: false), "do not finish before any recognized text")
expect(!AutoFinishPolicy.shouldFinish(now: 5, lastTextChange: 4.5, lastVoiceActivity: 2, hasText: true), "wait for recognition to stabilize")
expect(!AutoFinishPolicy.shouldFinish(now: 5, lastTextChange: 2, lastVoiceActivity: 4.5, hasText: true), "do not finish while user is still speaking")
expect(AutoFinishPolicy.shouldFinish(now: 5, lastTextChange: 2, lastVoiceActivity: 2, hasText: true), "finish after quiet pause with recognized text")

MainActor.assumeIsolated {
    func key(_ code: CGKeyCode = 49, down: Bool = true, repeatKey: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = []
        if repeatKey { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return event
    }
    func pause(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
    let trigger = TripleSpaceTrigger()
    var pid: pid_t = 123
    var replayed: [CGEvent] = []
    var triggers = 0
    trigger.currentPID = { pid }
    trigger.replayForTesting = { replayed.append($0) }
    trigger.onTrigger = { triggers += 1 }

    for _ in 0..<3 {
        expect(trigger.handle(proxy: nil, type: .keyDown, event: key()) == nil, "buffer trigger space down")
        expect(trigger.handle(proxy: nil, type: .keyUp, event: key(down: false)) == nil, "consume trigger space up")
    }
    pause(0.02)
    expect(triggers == 1 && replayed.isEmpty, "triple space toggles once without inserting spaces")

    _ = trigger.handle(proxy: nil, type: .keyDown, event: key())
    _ = trigger.handle(proxy: nil, type: .keyUp, event: key(down: false))
    expect(trigger.handle(proxy: nil, type: .keyDown, event: key(0)) != nil, "letter after space passes through")
    expect(replayed.count == 2, "space before ordinary letter is replayed")

    replayed.removeAll()
    _ = trigger.handle(proxy: nil, type: .keyDown, event: key())
    pause(0.36)
    expect(replayed.count == 1, "held space down is replayed on timeout")
    expect(trigger.handle(proxy: nil, type: .keyUp, event: key(down: false)) != nil, "held space release is not swallowed after timeout")

    replayed.removeAll()
    _ = trigger.handle(proxy: nil, type: .keyDown, event: key())
    expect(trigger.handle(proxy: nil, type: .keyDown, event: key(repeatKey: true)) != nil, "auto-repeat space passes through")
    expect(replayed.count == 1, "auto-repeat flushes first space")
    expect(triggers == 1, "holding space never triggers listening")

    replayed.removeAll()
    _ = trigger.handle(proxy: nil, type: .keyDown, event: key())
    _ = trigger.handle(proxy: nil, type: .keyUp, event: key(down: false))
    pid = 456
    pause(0.36)
    expect(replayed.isEmpty, "do not replay buffered spaces into a different app")

    let modified = key()
    modified.flags = .maskCommand
    expect(trigger.handle(proxy: nil, type: .keyDown, event: modified) != nil, "Command-Space is unaffected")
    trigger.stop()
}
