# Voxa for macOS

<img src="Assets/Voxa-icon.png" alt="Voxa app icon" width="112" />

**Your voice, right where you type.**

Voxa is a native menu bar dictation app. Click a text field, double-tap the right Command key, and speak. By default, Voxa finishes after a quiet pause and inserts your words at the cursor. It uses the field's Accessibility interface when supported, with system paste as a fallback.

## Download

[Download the latest release](https://github.com/SergioTermann/Voxa/releases/latest). Unzip `Voxa-v1.1.0-macOS-arm64.zip` and move `Voxa.app` to Applications.

Requires an **Apple Silicon Mac** running **macOS 13 or later**. Releases are ad hoc signed and are not notarized by Apple. macOS may require you to approve opening the app in **System Settings > Privacy & Security**. You can also build it from source.

## Get started

1. Open `Voxa.app`.
2. In Voxa, enable **Microphone**, **Speech Recognition**, and **Accessibility** permissions. For Accessibility, enable Voxa in **System Settings > Privacy & Security > Accessibility**.
3. Enable **Dictation** in **System Settings > Keyboard > Dictation**. Voxa provides an **Open Settings** button under **Dictation Settings > macOS Dictation**.
4. Click an editable text field in your browser, chat app, document, or editor.
5. Tap and release **Right Command twice** to start dictation. Each press must be shorter than 0.5 seconds, with a gap of less than 0.65 seconds between taps.
6. Speak, then pause. After recognized text is stable and the microphone is quiet for about **1.6 seconds**, Voxa finishes and inserts the transcript. You can also click **Finish & Insert** in the floating preview or use your shortcut again.

**Control + Option + Space** is the backup shortcut when using Right Command or triple Space. **Control + Option + Esc** cancels dictation without inserting text. The menu bar icon also provides start, finish, settings, copy, and quit actions.

Right Command detection does not intercept keys or delay ordinary typing. Holding the key, using a Command shortcut, clicking the mouse, or switching apps interrupts the double-tap sequence. Accessibility permission is required.

## Settings

- **Start / Finish Shortcut:** Right Command twice, Control + Option + V, Command + Shift + Space, Control + Option + Space, or triple Space. Changes apply immediately and are saved. If a combination is already in use, Voxa keeps your previous setting.
- **Dictation Language:** English (US), Mandarin (Simplified Chinese), Cantonese (Hong Kong), or Mandarin (Traditional Chinese). New installations default to English; existing preferences are preserved.
- **Offline only:** prevents fallback to Apple online recognition when on-device recognition is unavailable.
- **Automatically insert after a pause:** enabled by default. Turn it off if you prefer to finish manually.

Only the **triple Space** option intercepts spaces. Tap within 0.32 seconds of each previous tap. Ordinary spaces can be delayed by up to 0.32 seconds, while the three trigger spaces are consumed. If detection is unavailable, use the settings link to enable **Input Monitoring**, then restart Voxa.

The app interface, messages, and documentation are in English. Dictation can still produce text in any supported language. macOS permission dialogs and other apps' names follow your system language.

## Recognition and privacy

- No API key or third-party dependency is required.
- Voxa prefers Apple on-device speech recognition. Availability depends on your Mac, language, and installed speech resources.
- If on-device recognition is unavailable, Apple online recognition may be used. This requires an internet connection and sends audio to Apple's speech service. Enable **Offline only** to prevent this fallback.
- Each session lasts up to approximately 55 seconds. Dictate longer content in separate sessions.
- Voxa does not save recordings. The last transcript stays in memory, can be copied or cleared, and is removed when the app exits.
- Key events are inspected only to detect the selected trigger; other keystrokes are not logged.

## Insertion behavior

- The floating preview has **Finish & Insert** and **Cancel** buttons. Clicking them does not take keyboard focus away from your text field.
- You can click another field while dictating. Voxa uses the cursor location when dictation finishes.
- Selected text is replaced when the transcript is inserted.
- If the active app or focus changes while recognition is finishing, permission is revoked, or the target is a recognized password field, Voxa preserves the transcript for manual copying.
- Supported editors receive text directly through Accessibility, without using the clipboard.
- Paste fallback sends keystrokes to the selected app's process. The clipboard is temporarily used and restored after about one second. If you copy something new in the meantime, your new clipboard content is preserved.
- The cursor must be in an **editable field**. Buttons, images, protected input, some games, remote desktops, and unusual editors may not support insertion. Copy the last transcript from the menu bar if needed.
- Voxa does not send Return. Terminal paste behavior is controlled by your terminal.

## Troubleshooting

**“Siri and Dictation are disabled”**: enable Dictation under **System Settings > Keyboard**, accept any system prompt, and try again. If the switch is unavailable, check Screen Time restrictions or device management policies.

**Words remain in the preview**: click **Finish & Insert** or enable **Automatically insert after a pause**. Recognition preview is separate from insertion.

**Text is not inserted**: check Accessibility permission, place the cursor in an editable field, and keep that field focused while recognition finishes. Your transcript remains available under **Last Transcript**.

## Build from source

Requires Apple Silicon, macOS 13+, and Xcode command line tools.

```sh
git clone https://github.com/SergioTermann/Voxa.git
cd Voxa
bash scripts/build.sh
bash scripts/test.sh
open 'build/Voxa.app'
```

The build uses an existing local Apple Development signing identity if available, otherwise ad hoc signing. Set `VOICECURSOR_SIGN_IDENTITY` to choose an identity, or explicitly set it to `-` for ad hoc signing. macOS permissions depend on signing and installation location; run the app from a stable path.

Tests cover automatic finish conditions, Command double-taps, long presses, shortcut interruption, triple Space, replaying ordinary spaces, key releases, app changes, password-field policy, clipboard restoration, and app startup. Insertion has been verified in TextEdit on the development Mac. Live microphone recognition and compatibility with other apps require testing after the user's permissions are granted.
