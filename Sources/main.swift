import AppKit
import SwiftUI
import Speech
import AVFoundation
import Carbon
import ApplicationServices

enum ListeningPhase { case idle, authorizing, listening, finishing }

enum TriggerShortcut: String, CaseIterable {
    case doubleRightCommand, controlOptionV, commandShiftSpace, controlOptionSpace, tripleSpace

    var label: String {
        switch self {
        case .doubleRightCommand: return "Right ⌘ × 2"
        case .controlOptionV: return "⌃⌥ V"
        case .commandShiftSpace: return "⌘⇧ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        case .tripleSpace: return "Space × 3"
        }
    }
    var instruction: String {
        switch self {
        case .doubleRightCommand: return "double-tap Right ⌘"
        case .tripleSpace: return "tap Space three times quickly"
        default: return "press \(label)"
        }
    }
    var keyCode: UInt32 { self == .controlOptionV ? UInt32(kVK_ANSI_V) : UInt32(kVK_Space) }
    var modifiers: UInt32 { self == .commandShiftSpace ? UInt32(cmdKey | shiftKey) : UInt32(controlKey | optionKey) }
}

struct InsertionTarget {
    let app: NSRunningApplication
    let element: AXUIElement?
    let secure: Bool
}

@MainActor
final class VoiceController: NSObject, ObservableObject {
    @Published var phase: ListeningPhase = .idle
    @Published var transcript = ""
    @Published var lastResult = ""
    @Published var message = "Click a text field, then use your shortcut to start dictation."
    @Published private(set) var shortcut: TriggerShortcut = TriggerShortcut(rawValue: UserDefaults.standard.string(forKey: "triggerPreset") ?? "") ?? .doubleRightCommand
    @Published var speechPermission = false
    @Published var microphonePermission = false
    @Published var accessibilityPermission = false
    @Published var language: String = UserDefaults.standard.string(forKey: "language") ?? "en-US" {
        didSet { UserDefaults.standard.set(language, forKey: "language"); refreshPermissions() }
    }
    @Published var localOnly: Bool = UserDefaults.standard.object(forKey: "localOnly") as? Bool ?? false {
        didSet { UserDefaults.standard.set(localOnly, forKey: "localOnly") }
    }
    @Published var tripleSpaceAvailable = false
    @Published var modifierTapAvailable = false
    @Published var shortcutAvailable = true
    @Published var onDeviceAvailable = false
    @Published var recognitionMode = ""
    @Published var systemDictationDisabled = false
    @Published var autoFinish: Bool = UserDefaults.standard.object(forKey: "autoFinish") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoFinish, forKey: "autoFinish") }
    }
    var stateChanged: (() -> Void)?
    var showSettings: (() -> Void)?
    var hideSettings: (() -> Void)?
    var showHUD: (() -> Void)?
    var hideHUD: (() -> Void)?
    var permissionsChanged: (() -> Void)?
    var configureShortcut: ((TriggerShortcut) -> Bool)?
    var lastExternalApp: NSRunningApplication?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var tapInstalled = false
    private var target: InsertionTarget?
    private var finishingTimer: Timer?
    private var maximumTimer: Timer?
    private var autoFinishTimer: Timer?
    private var lastTextChange: TimeInterval = 0
    private var lastVoiceActivity: TimeInterval = 0
    private var permissionTimer: Timer?
    private var sessionID = UUID()
    private var diagnosticTarget: AXUIElement?

    override init() {
        super.init()
        message = "Click a text field, then \(shortcut.instruction) to start dictation."
        rememberExternalApp()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    @objc private func activated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApp = app
    }

    private func rememberExternalApp() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = app
        }
    }

    func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        let ax = AXIsProcessTrusted()
        let local = SFSpeechRecognizer(locale: Locale(identifier: language))?.supportsOnDeviceRecognition ?? false
        if microphonePermission != mic { microphonePermission = mic }
        if speechPermission != speech { speechPermission = speech }
        if accessibilityPermission != ax { accessibilityPermission = ax }
        if onDeviceAvailable != local { onDeviceAvailable = local }
        permissionsChanged?()
    }

    func authorizeMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func selectShortcut(_ choice: TriggerShortcut) {
        guard phase == .idle, choice != shortcut else { return }
        guard configureShortcut?(choice) == true else {
            message = "\(choice.label) is already in use. Keeping \(shortcut.label); choose another shortcut."
            stateChanged?()
            return
        }
        shortcut = choice
        UserDefaults.standard.set(choice.rawValue, forKey: "triggerPreset")
        message = "Shortcut changed to \(choice.label). Use it to start and finish dictation."
        permissionsChanged?()
        stateChanged?()
    }

    func authorizeSpeech() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func authorizeAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
    }

    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openDictationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation") {
            NSWorkspace.shared.open(url)
        }
    }

    func toggle(fromSettings: Bool = false) {
        switch phase {
        case .listening: stop()
        case .authorizing, .finishing: return
        case .idle:
            if fromSettings {
                guard let app = lastExternalApp, !app.isTerminated else {
                    message = "Click a text field in another app, then \(shortcut.instruction)."
                    return
                }
                hideSettings?()
                app.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.start() }
            } else { start() }
        }
    }

    private func start() {
        guard phase == .idle else { return }
        refreshPermissions()
        guard microphonePermission, speechPermission, accessibilityPermission else {
            message = "Enable the permissions below, return to your text field, then \(shortcut.instruction)."
            showSettings?()
            return
        }
        rememberExternalApp()
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            message = "Place your cursor in a text field in the target app first."
            showSettings?()
            return
        }
        let initialTarget = captureTarget(app: front)
        guard !initialTarget.secure else {
            message = "This is a password field. Choose a regular text field."
            stateChanged?()
            return
        }
        guard let speech = SFSpeechRecognizer(locale: Locale(identifier: language)), speech.isAvailable else {
            message = "Speech recognition is unavailable. Check your connection or choose another dictation language."
            showSettings?()
            return
        }
        guard !localOnly || speech.supportsOnDeviceRecognition else {
            message = "On-device recognition is unavailable for this language. Choose another language or turn off Offline only."
            showSettings?()
            return
        }
        let id = UUID()
        sessionID = id
        lastTextChange = ProcessInfo.processInfo.systemUptime
        lastVoiceActivity = lastTextChange
        transcript = ""
        target = nil
        recognizer = speech
        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.shouldReportPartialResults = true
        audioRequest.requiresOnDeviceRecognition = speech.supportsOnDeviceRecognition
        if #available(macOS 13.0, *) { audioRequest.addsPunctuation = true }
        request = audioRequest
        recognitionMode = audioRequest.requiresOnDeviceRecognition ? "On-device recognition" : "Apple online recognition"
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("No microphone is available. Check the input device in System Settings > Sound.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            audioRequest.append(buffer)
            if let samples = buffer.floatChannelData?.pointee, buffer.frameLength > 0 {
                var squares: Float = 0
                var count: Float = 0
                for index in stride(from: 0, to: Int(buffer.frameLength), by: 4) {
                    squares += samples[index] * samples[index]
                    count += 1
                }
                if squares / max(count, 1) > 0.0001 {
                    let time = ProcessInfo.processInfo.systemUptime
                    Task { @MainActor [weak self] in
                        guard let self, self.sessionID == id else { return }
                        self.lastVoiceActivity = time
                    }
                }
            }
        }
        tapInstalled = true
        task = speech.recognitionTask(with: audioRequest) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorText = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                if let words, !words.isEmpty, self.transcript != words {
                    self.transcript = words
                    self.lastTextChange = ProcessInfo.processInfo.systemUptime
                }
                if let errorText, SpeechFailurePolicy.isSystemDictationDisabled(errorText) {
                    self.systemDictationDisabled = true
                    let retained = self.transcript.isEmpty ? "" : " Your transcript is saved for copying."
                    self.fail("macOS Dictation is turned off. Click Open Dictation Settings, enable Dictation under Keyboard, then try again." + retained)
                    return
                }
                if let words, !words.isEmpty { self.systemDictationDisabled = false }
                if self.phase == .finishing {
                    if isFinal || errorText != nil { self.complete() }
                } else if self.phase == .listening {
                    if let errorText {
                        let retained = self.transcript.isEmpty ? "" : " Your transcript is saved for copying."
                        self.fail("Recognition was interrupted: \(errorText)." + retained)
                    } else if isFinal {
                        self.stop()
                        self.complete()
                    }
                }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            phase = .listening
            message = "Listening. \(shortcut.instruction.capitalized) again to finish and insert."
            showHUD?()
            stateChanged?()
            maximumTimer = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
            if let maximumTimer { RunLoop.main.add(maximumTimer, forMode: .common) }
            autoFinishTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.phase == .listening, self.autoFinish else { return }
                    if AutoFinishPolicy.shouldFinish(now: ProcessInfo.processInfo.systemUptime,
                                                     lastTextChange: self.lastTextChange,
                                                     lastVoiceActivity: self.lastVoiceActivity,
                                                     hasText: !self.transcript.isEmpty) { self.stop() }
                }
            }
            if let autoFinishTimer { RunLoop.main.add(autoFinishTimer, forMode: .common) }
        } catch {
            fail("Could not start the microphone: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard phase == .listening else { return }
        // Capture the location at STOP: users may click another field while dictating.
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            target = captureTarget(app: app)
        } else if let app = lastExternalApp, !app.isTerminated {
            target = captureTarget(app: app)
            hideSettings?()
            app.activate()
        } else { target = nil }
        phase = .finishing
        message = "Finishing…"
        maximumTimer?.invalidate()
        autoFinishTimer?.invalidate()
        stopAudio()
        request?.endAudio()
        stateChanged?()
        finishingTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.complete() }
        }
        if let finishingTimer { RunLoop.main.add(finishingTimer, forMode: .common) }
    }

    func cancel() {
        guard phase != .idle else { return }
        lastResult = TextPolicy.clean(transcript)
        cleanup()
        message = "Dictation canceled. Your transcript is available in Settings for copying."
        stateChanged?()
    }

    func runInsertionDiagnostic(_ text: String, targetBundle: String? = nil) {
        guard AXIsProcessTrusted() else {
            message = "INSERTION_FAIL: accessibility permission is not authorized"
            return
        }
        let selectedApp = targetBundle.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first } ?? lastExternalApp
        guard let app = selectedApp, !app.isTerminated else {
            message = "INSERTION_FAIL: no external target application"
            return
        }
        lastExternalApp = app
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: app) }
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.transcript = text
            self.phase = .listening
            self.stop()
            self.diagnosticTarget = self.target?.element
        }
    }

    func verifyDiagnosticInsertion(_ text: String) -> Bool {
        guard let element = diagnosticTarget else { return false }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let contents = value as? String else { return false }
        return contents.contains(text)
    }

    private func complete() {
        guard phase == .finishing else { return }
        let text = TextPolicy.clean(transcript)
        let destination = target
        cleanup()
        guard !text.isEmpty else {
            message = "No speech was recognized. Check your microphone and try again."
            stateChanged?()
            return
        }
        lastResult = text
        guard let destination, !destination.secure else {
            message = "No text field is available. Open Settings to copy your transcript."
            stateChanged?()
            return
        }
        guard AXIsProcessTrusted(), !destination.app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.app.processIdentifier else {
            message = "The active window changed. Your transcript is available in Settings for copying."
            stateChanged?()
            return
        }
        let current = captureTarget(app: destination.app)
        guard !current.secure else {
            message = "This is a password field. Your transcript was saved but not inserted."
            stateChanged?()
            return
        }
        if let expected = destination.element, let actual = current.element, !CFEqual(expected, actual) {
            message = "The cursor moved. Your transcript is available in Settings for copying."
            stateChanged?()
            return
        }
        guard paste(text, to: destination) else {
            message = "Could not send the paste shortcut. Copy your transcript from Settings."
            stateChanged?()
            return
        }
        message = "Inserting into \(destination.app.localizedName ?? "the target app")…"
        stateChanged?()
    }

    private func captureTarget(app: NSRunningApplication) -> InsertionTarget {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        var element: AXUIElement?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            element = (focused as! AXUIElement)
        }
        func attribute(_ key: String) -> String? {
            guard let element else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
            return value as? String
        }
        return InsertionTarget(app: app, element: element,
                               secure: TextPolicy.isSecure(role: attribute(kAXRoleAttribute), subrole: attribute(kAXSubroleAttribute)))
    }

    private func paste(_ text: String, to destination: InsertionTarget) -> Bool {
        if let element = destination.element {
            var settable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
               settable.boolValue,
               AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.message = "Inserted into \(destination.app.localizedName ?? "the target app"). Use \(self.shortcut.label) to dictate again."
                    self.stateChanged?()
                }
                return true
            }
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        let board = NSPasteboard.general
        let previousItems = board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        board.clearContents()
        guard board.setString(text, forType: .string) else { return false }
        let ownedCount = board.changeCount
        // Let the hotkey modifiers physically release before posting Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier == destination.app.processIdentifier,
                  AXIsProcessTrusted() else {
                self?.restoreClipboard(previousItems, ownedCount: ownedCount)
                self?.message = "The active window changed. Your transcript is available in Settings for copying."
                self?.stateChanged?()
                return
            }
            let current = self.captureTarget(app: app)
            let focusChanged: Bool
            if let expected = destination.element, let actual = current.element {
                focusChanged = !CFEqual(expected, actual)
            } else { focusChanged = false }
            guard !current.secure, !focusChanged else {
                self.restoreClipboard(previousItems, ownedCount: ownedCount)
                self.message = "The input location changed. Copy your transcript from Settings."
                self.stateChanged?()
                return
            }
            guard board.changeCount == ownedCount else {
                self.message = "The clipboard changed. Copy your transcript from Settings."
                self.stateChanged?()
                return
            }
            down.flags = .maskCommand
            up.flags = []
            down.postToPid(destination.app.processIdentifier)
            up.postToPid(destination.app.processIdentifier)
            self.message = "Text sent to \(app.localizedName ?? "the target app"). Use \(self.shortcut.label) to dictate again."
            self.stateChanged?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.restoreClipboard(previousItems, ownedCount: ownedCount)
            }
        }
        return true
    }

    private func restoreClipboard(_ items: [NSPasteboardItem], ownedCount: Int) {
        let board = NSPasteboard.general
        guard TextPolicy.canRestoreClipboard(ownedChangeCount: ownedCount, currentChangeCount: board.changeCount) else { return }
        board.clearContents()
        if !items.isEmpty { board.writeObjects(items) }
    }

    func copyResult() {
        guard !lastResult.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastResult, forType: .string)
        message = "Transcript copied."
        stateChanged?()
    }

    func clearResult() {
        guard phase == .idle else { return }
        transcript = ""
        lastResult = ""
        message = "Transcript cleared."
        stateChanged?()
    }

    private func stopAudio() {
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    }

    private func cleanup() {
        sessionID = UUID()
        stopAudio()
        finishingTimer?.invalidate()
        maximumTimer?.invalidate()
        autoFinishTimer?.invalidate()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        target = nil
        phase = .idle
        hideHUD?()
    }

    private func fail(_ text: String) {
        if !transcript.isEmpty { lastResult = TextPolicy.clean(transcript) }
        cleanup()
        message = text
        stateChanged?()
        showSettings?()
    }
}

struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? Color.green : Color.orange).font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "Allowed" : "Enable", action: action).disabled(granted)
        }.padding(.vertical, 5)
    }
}

struct SettingsView: View {
    @ObservedObject var model: VoiceController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Voxa").font(.system(size: 27, weight: .bold))
                        Text("Your voice, right where you type.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.shortcut.label).font(.system(.body, design: .monospaced)).padding(10)
                        .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.phase == .listening ? "Listening" : model.phase == .finishing ? "Finishing" : model.systemDictationDisabled ? "Enable macOS Dictation" : "Ready", systemImage: model.phase == .listening ? "mic.fill" : "keyboard")
                        .font(.headline).foregroundStyle(.teal)
                    Text(model.message).font(.callout).textSelection(.enabled)
                    if model.systemDictationDisabled {
                        Button("Open Dictation Settings") { model.openDictationSettings() }
                    }
                    HStack {
                        Button(model.phase == .listening ? "Finish & Insert" : "Start Dictation") { model.toggle(fromSettings: true) }
                            .buttonStyle(.borderedProminent).tint(.teal)
                            .disabled(model.phase == .finishing)
                        if model.phase == .listening || model.phase == .finishing {
                            Button("Cancel") { model.cancel() }
                        }
                        Spacer()
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                GroupBox("System Permissions") {
                    VStack(spacing: 0) {
                        PermissionRow(title: "Microphone", detail: "Capture your voice", granted: model.microphonePermission) {
                            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { model.authorizeMicrophone() }
                            else { model.openPrivacy("Microphone") }
                        }
                        Divider()
                        PermissionRow(title: "Speech Recognition", detail: "Convert speech to text", granted: model.speechPermission) {
                            if SFSpeechRecognizer.authorizationStatus() == .notDetermined { model.authorizeSpeech() }
                            else { model.openPrivacy("SpeechRecognition") }
                        }
                        Divider()
                        PermissionRow(title: "Accessibility", detail: "Insert text into the active field", granted: model.accessibilityPermission) { model.authorizeAccessibility() }
                        if model.shortcut == .tripleSpace && model.accessibilityPermission && !model.tripleSpaceAvailable {
                            Divider()
                            PermissionRow(title: "Global Space Detection", detail: "If triple Space does not work, allow Voxa in Input Monitoring and restart it.", granted: false) { model.openPrivacy("ListenEvent") }
                        }
                    }.padding(8)
                }
                GroupBox("Dictation Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("macOS Dictation").fontWeight(.medium)
                                Text("Apple speech services require macOS Dictation to be enabled.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open Settings") { model.openDictationSettings() }
                        }
                        Divider()
                        Picker("Start / Finish Shortcut", selection: Binding(get: { model.shortcut }, set: { model.selectShortcut($0) })) {
                            ForEach(TriggerShortcut.allCases, id: \.self) { choice in
                                Text(choice.label).tag(choice)
                            }
                        }.disabled(model.phase != .idle)
                        Picker("Dictation Language", selection: $model.language) {
                            Text("Mandarin (Simplified Chinese)").tag("zh-CN")
                            Text("English (US)").tag("en-US")
                            Text("Cantonese (Hong Kong)").tag("zh-HK")
                            Text("Mandarin (Traditional Chinese)").tag("zh-TW")
                        }.disabled(model.phase != .idle)
                        Toggle("Offline only", isOn: $model.localOnly).disabled(model.phase != .idle)
                        Toggle("Automatically insert after a pause", isOn: $model.autoFinish)
                        Text("After speech is recognized, a quiet pause of about 1.6 seconds finishes dictation and inserts the text. You can also click Finish & Insert or use your shortcut again.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.onDeviceAvailable ? "On-device recognition is available for this language. Audio will be processed locally." : "On-device recognition is unavailable for this language. Apple online recognition requires an internet connection.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("No API key required. Each session lasts up to 55 seconds. Transcripts stay in memory only.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last Transcript").font(.headline)
                        Spacer()
                        Button("Copy") { model.copyResult() }.disabled(model.lastResult.isEmpty)
                        Button("Clear") { model.clearResult() }.disabled(model.phase != .idle || model.lastResult.isEmpty)
                    }
                    Text(model.lastResult.isEmpty ? "Your latest transcript will appear here." : model.lastResult)
                        .foregroundStyle(model.lastResult.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                        .padding(12).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
                Text("Click a text field → \(model.shortcut.instruction) → speak → pause or use the shortcut again.\nCancel: ⌃⌥ Esc. The cursor must be in an editable field.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.shortcut == .tripleSpace {
                    Text("Triple Space: tap within 0.32 seconds of each previous tap. Ordinary spaces may be delayed by up to 0.32 seconds. Backup: ⌃⌥ Space.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.shortcut == .doubleRightCommand {
                    Text("Tap and release Right ⌘ twice within 0.65 seconds. Holding it or using a key combination does not trigger dictation. Backup: ⌃⌥ Space.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.accessibilityPermission && !model.modifierTapAvailable {
                        Text("Right ⌘ detection is unavailable. Restart Voxa or use the backup shortcut.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if !model.shortcutAvailable {
                    Text("This shortcut is already in use. Choose another one above, or use the menu bar to start and finish.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }.padding(26)
        }.frame(minWidth: 600, minHeight: 650)
    }
}

struct HUDView: View {
    @ObservedObject var model: VoiceController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: model.phase == .finishing ? "ellipsis" : "waveform").foregroundStyle(.teal)
                Text(model.phase == .finishing ? "Finishing…" : "Voxa · Listening").fontWeight(.semibold)
                Spacer()
                Text("\(model.shortcut.label) to finish").font(.caption).foregroundStyle(.secondary)
            }
            Text(model.transcript.isEmpty ? "Start speaking…" : model.transcript)
                .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
            Text(model.recognitionMode).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Text(model.autoFinish ? "Pause to insert" : "Finish to insert")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancel() }.buttonStyle(.borderless)
                    .disabled(model.phase != .listening)
                Button("Finish & Insert") { model.stop() }.buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(model.phase != .listening)
            }
        }.padding(18).frame(width: 400, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

final class ListeningPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = VoiceController()
    private var status: NSStatusItem!
    private var window: NSWindow!
    private var hud: NSPanel!
    private var hotKey: EventHotKeyRef?
    private var escapeHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let tripleSpace = TripleSpaceTrigger()
    private let modifierTap = ModifierTapTrigger()
    private var registeredShortcut: TriggerShortcut?
    private var diagnosticRecognizer: SFSpeechRecognizer?
    private var diagnosticTask: SFSpeechRecognitionTask?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = menuIcon()
        status.button?.toolTip = "Voxa · \(controller.shortcut.label) Start / Finish"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Voxa"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: controller))
        window.center()
        hud = ListeningPanel(contentRect: NSRect(x: 0, y: 0, width: 436, height: 214), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hud.level = .floating
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.hasShadow = true
        hud.ignoresMouseEvents = false
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hud.contentView = NSHostingView(rootView: HUDView(model: controller))
        controller.showSettings = { [weak self] in self?.openSettings() }
        controller.hideSettings = { [weak self] in self?.window.orderOut(nil) }
        controller.showHUD = { [weak self] in self?.displayHUD() }
        controller.hideHUD = { [weak self] in self?.hud.orderOut(nil) }
        controller.stateChanged = { [weak self] in self?.updateStatus() }
        tripleSpace.onTrigger = { [weak self] in
            guard let self else { return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
            self.controller.toggle()
        }
        tripleSpace.onAvailabilityChanged = { [weak self] available in self?.controller.tripleSpaceAvailable = available }
        modifierTap.onTrigger = { [weak self] in
            guard let self else { return }
            if self.controller.phase == .idle,
               NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
            self.controller.toggle()
        }
        modifierTap.onAvailabilityChanged = { [weak self] available in self?.controller.modifierTapAvailable = available }
        controller.permissionsChanged = { [weak self] in
            guard let self else { return }
            if self.controller.shortcut == .tripleSpace && self.controller.accessibilityPermission { self.tripleSpace.start() }
            else if self.controller.tripleSpaceAvailable { self.tripleSpace.stop(); self.controller.tripleSpaceAvailable = false }
            if self.controller.shortcut == .doubleRightCommand && self.controller.accessibilityPermission { self.modifierTap.start() }
            else if self.controller.modifierTapAvailable { self.modifierTap.stop() }
        }
        controller.configureShortcut = { [weak self] choice in self?.bindShortcut(choice) ?? false }
        registerShortcut()
        controller.refreshPermissions()
        updateStatus()
        if let index = CommandLine.arguments.firstIndex(of: "--insertion-test"), CommandLine.arguments.count > index + 2 {
            let diagnosticText = CommandLine.arguments[index + 1]
            let bundle = CommandLine.arguments.count > index + 3 ? CommandLine.arguments[index + 3] : nil
            controller.runInsertionDiagnostic(diagnosticText, targetBundle: bundle)
            let reportPath = CommandLine.arguments[index + 2]
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                let report: [String: Any] = ["message": controller.message,
                                           "accessibility": AXIsProcessTrusted(),
                                           "verifiedInTarget": controller.verifyDiagnosticInsertion(diagnosticText),
                                           "frontmostApp": NSWorkspace.shared.frontmostApplication?.localizedName ?? "none",
                                           "idle": controller.phase == .idle]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: reportPath))
                }
                NSApp.terminate(nil)
            }
        } else if let index = CommandLine.arguments.firstIndex(of: "--ui-preview"), CommandLine.arguments.count > index + 1 {
            let directory = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                do {
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    try exportPreview(window: window, size: NSSize(width: 640, height: 1200), path: directory + "/settings.png")
                    controller.phase = .listening
                    controller.transcript = "Your voice, right where you type. This is a longer transcript to check that the preview stays readable and that the Finish & Insert button remains visible."
                    controller.recognitionMode = "On-device recognition"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                        do {
                            try exportPreview(window: hud, size: NSSize(width: 436, height: 214), path: directory + "/listening.png")
                            print("PREVIEW_OK")
                        } catch { print("PREVIEW_FAIL: \(error)") }
                        NSApp.terminate(nil)
                    }
                } catch { print("PREVIEW_FAIL: \(error)"); NSApp.terminate(nil) }
            }
        } else if let index = CommandLine.arguments.firstIndex(of: "--recognition-test"), CommandLine.arguments.count > index + 1 {
            runRecognitionDiagnostic(path: CommandLine.arguments[index + 1])
        } else if CommandLine.arguments.contains("--smoke-test") {
            print("SMOKE_OK: menu, settings, HUD initialized; shortcut=\(controller.shortcut.rawValue); registered=\(controller.shortcutAvailable)")
            NSApp.terminate(nil)
        } else { openSettings() }
    }

    private func exportPreview(window: NSWindow, size: NSSize, path: String) throws {
        window.setContentSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "VoxaPreview", code: 1)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "VoxaPreview", code: 2)
        }
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func runRecognitionDiagnostic(path: String) {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            print("RECOGNITION_FAIL: speech recognition permission is not authorized")
            exit(1)
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            print("RECOGNITION_FAIL: Chinese on-device recognizer unavailable")
            exit(1)
        }
        diagnosticRecognizer = recognizer
        let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
        request.requiresOnDeviceRecognition = true
        diagnosticTask = recognizer.recognitionTask(with: request) { result, error in
            if let result, result.isFinal {
                let text = result.bestTranscription.formattedString
                print("RECOGNITION_\(text.isEmpty ? "FAIL" : "OK"): \(text)")
                exit(text.isEmpty ? 1 : 0)
            }
            if let error { print("RECOGNITION_FAIL: \(error.localizedDescription)"); exit(1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            print("RECOGNITION_FAIL: timeout")
            exit(1)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.cancel()
        tripleSpace.stop()
        modifierTap.stop()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let escapeHotKey { UnregisterEventHotKey(escapeHotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func registerShortcut() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            if id.id == 1 { delegate.controller.toggle() }
            else if id.id == 2 { delegate.controller.cancel() }
            return noErr
        }, 1, &eventSpec, pointer, &eventHandler)
        controller.shortcutAvailable = bindShortcut(controller.shortcut)
    }

    private func bindShortcut(_ choice: TriggerShortcut) -> Bool {
        if let previous = registeredShortcut, hotKey != nil,
           previous.keyCode == choice.keyCode, previous.modifiers == choice.modifiers {
            registeredShortcut = choice
            controller.shortcutAvailable = true
            return true
        }
        var candidate: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: 0x56524352, id: 1)
        let result = RegisterEventHotKey(choice.keyCode, choice.modifiers, identifier, GetApplicationEventTarget(), 0, &candidate)
        guard result == noErr, let candidate else { return false }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = candidate
        registeredShortcut = choice
        controller.shortcutAvailable = true
        return true
    }

    private func updateStatus() {
        let busy = controller.phase == .listening || controller.phase == .finishing
        status.button?.image = menuIcon()
        status.button?.contentTintColor = busy ? .systemRed : nil
        status.button?.toolTip = controller.message
        if busy && escapeHotKey == nil {
            let identifier = EventHotKeyID(signature: 0x56524352, id: 2)
            RegisterEventHotKey(UInt32(kVK_Escape), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), 0, &escapeHotKey)
        } else if !busy, let key = escapeHotKey {
            UnregisterEventHotKey(key)
            escapeHotKey = nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let label = NSMenuItem(title: controller.message, action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: controller.phase == .listening ? "Finish & Insert" : "Start Dictation", action: #selector(toggleListening), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = controller.phase == .idle || controller.phase == .listening
        menu.addItem(toggle)
        if controller.phase != .idle {
            let cancel = NSMenuItem(title: "Cancel Dictation    ⌃⌥ Esc", action: #selector(cancelListening), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }
        let copy = NSMenuItem(title: "Copy Last Transcript", action: #selector(copyResult), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = !controller.lastResult.isEmpty
        menu.addItem(copy)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings & Permissions…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Voxa", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleListening() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.controller.toggle(fromSettings: NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier)
        }
    }
    @objc private func cancelListening() { controller.cancel() }
    @objc private func copyResult() { controller.copyResult() }
    @objc func openSettings() {
        controller.refreshPermissions()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    private func menuIcon() -> NSImage? {
        guard let path = Bundle.main.path(forResource: "MenuIcon", ofType: "png"),
              let image = NSImage(contentsOfFile: path) else {
            return NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voxa")
        }
        image.size = NSSize(width: 28, height: 28)
        image.isTemplate = true
        return image
    }
    private func displayHUD() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            hud.setFrameOrigin(NSPoint(x: frame.maxX - hud.frame.width - 24, y: frame.minY + 24))
        }
        hud.orderFrontRegardless()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
