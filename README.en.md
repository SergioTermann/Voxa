# Voxa — voice input for macOS / Windows

[中文](README.md) | [English](README.en.md)

<img src="Assets/Voxa-icon.png" alt="Voxa app icon" width="112" />

**Your voice, right where you type.** Voxa runs in the menu bar or system tray. A global shortcut starts dictation, a floating preview shows the transcript, and completed text is inserted into the active field.

## Download and install

[Download v1.3.0](https://github.com/SergioTermann/Voxa/releases/tag/v1.3.0) · [All releases](https://github.com/SergioTermann/Voxa/releases)

| Platform | Download | Installation | Requirements |
| --- | --- | --- | --- |
| macOS | [`Voxa-v1.3.0-macOS-arm64.dmg`](https://github.com/SergioTermann/Voxa/releases/download/v1.3.0/Voxa-v1.3.0-macOS-arm64.dmg) | Open the DMG and drag **Voxa.app** to **Applications** | Apple Silicon, macOS 13+ |
| macOS ZIP | [`Voxa-v1.3.0-macOS-arm64.zip`](https://github.com/SergioTermann/Voxa/releases/download/v1.3.0/Voxa-v1.3.0-macOS-arm64.zip) | Extract and move **Voxa.app** to Applications | Same as above |
| Windows | [`Voxa-v1.3.0-Windows-Setup-x64.exe`](https://github.com/SergioTermann/Voxa/releases/download/v1.3.0/Voxa-v1.3.0-Windows-Setup-x64.exe) | Run the installer; Chinese / English setup, shortcuts and uninstaller included | Windows 10 / 11, x64, a compatible local SAPI dictation engine |
| Windows portable | [`Voxa-v1.3.0-Windows-x64.zip`](https://github.com/SergioTermann/Voxa/releases/download/v1.3.0/Voxa-v1.3.0-Windows-x64.zip) | Extract the entire archive and run **Voxa.exe** | Same as above |

The Windows package includes the .NET runtime. No separate .NET installation or administrator permission is required. It installs to `%LOCALAPPDATA%\Programs\Voxa`; uninstall through Windows Installed Apps. Exit Voxa from the tray before upgrading or uninstalling.

The macOS package is not Apple-notarized, and the Windows package is not code-signed. On first launch, macOS may require approval under System Settings → Privacy & Security; Windows may show an unknown publisher prompt. Download from this repository's Releases. These are direct-distribution packages rather than Mac App Store packages.

## macOS quick start

1. Launch Voxa from Applications.
2. Grant **Microphone**, **Speech Recognition**, and **Accessibility** permissions. Enable Voxa in System Settings → Privacy & Security → Accessibility.
3. Enable **Dictation** in System Settings → Keyboard → Dictation.
4. Click an editable field in a browser, chat app, document or editor.
5. **Tap and release Right Command twice**. Each press must be shorter than 0.5 seconds, with a gap of less than 0.65 seconds between taps.
6. Speak, then pause to finish and insert. You can also use the shortcut again or click **Finish & Insert** in the preview.

**Control + Option + Space** is the backup shortcut for Right Command and triple Space modes. **Control + Option + Esc** cancels. The menu bar provides start, finish, settings, copy and quit actions.

### macOS settings

- **Start / Finish Shortcut:** Right Command twice, Control + Option + V, Command + Shift + Space, Control + Option + Space, or triple Space. If a combination is taken, the previous setting is retained.
- **Dictation Language:** English (US), Mandarin (Simplified Chinese), Cantonese (Hong Kong), or Mandarin (Traditional Chinese). New installations default to English.
- **Offline only:** prevents Apple online recognition when local recognition is unavailable.
- **Automatically insert after a pause:** enabled by default; finishes after recognized text is stable and the microphone is quiet for about 1.6 seconds.

Right Command detection does not intercept keys or delay ordinary typing. Holding the key, using a Command shortcut, clicking the mouse or changing apps interrupts the sequence. Only triple Space buffers and intercepts spaces: each tap must be within 0.32 seconds, ordinary spaces can be delayed by that interval, and the three trigger spaces are consumed. Enable Input Monitoring and restart if needed.

The macOS interface is in English. Documentation is available in Chinese and English; the recognition language is chosen independently.

## Windows quick start

1. Launch Voxa and select an installed recognition language.
2. Allow desktop microphone access in Windows privacy settings and check the default recording device.
3. Click an editable field in Notepad or another app.
4. **Tap and release Right Ctrl twice** to start; the floating preview shows recognized text.
5. Pause to finish automatically, or **double-tap Right Ctrl** again to finish and insert.
6. **Ctrl + Alt + Esc** cancels. Closing settings leaves Voxa running in the tray; use the tray menu to quit.

The Windows app uses dark cards, a dedicated transcript area and a compact preview with microphone-level visualization. The app interface is Chinese; the installer supports Chinese and English. **Ctrl + Alt + Space** remains a backup shortcut. Each Right Ctrl press is under 0.5 seconds, with a gap under 0.65 seconds. Long holds, key combinations, mouse actions and window changes interrupt the sequence; ordinary keystrokes pass through.

Language components must expose a **SAPI dictation engine** to `System.Speech`; working Win + H or Voice Access does not establish compatibility. Dictation cannot start without a compatible engine. Windows 11 24H2 removed the legacy Speech Recognition interface, so a compatible engine cannot be assumed on every new PC.

Detailed compatibility, development and validation guidance: [Windows English guide](windows/README.en.md) · [Windows 中文说明](windows/README.md). Actual microphone recognition and insertion compatibility still require testing on the target Windows device.

## Recognition and privacy

- Neither platform requires an API key.
- macOS prefers Apple on-device recognition. If unavailable, audio may be sent to Apple's online speech service. **Offline only** prevents this fallback.
- Windows uses the selected local SAPI engine; no cloud API integration is implemented.
- Each session lasts approximately 55 seconds. Dictate longer content in separate sessions.
- Voxa does not save recordings or transcript logs. The latest result stays in memory and is cleared on exit.
- Windows stores only the recognizer ID and auto-finish preference in `%LOCALAPPDATA%\Voxa\settings.json`; macOS uses system preferences.
- Manual copying places text on the system clipboard, subject to the operating system's history and sync settings.
- Windows uses global keyboard and mouse hooks only to detect the Right Ctrl sequence; other keystrokes are not stored.

## Insertion behavior

You can switch fields while dictating; the target is selected **when dictation finishes**. A window or focus change during completion preserves the transcript for manual copying. Selected text is replaced according to the target app's normal behavior. Password fields and controls that cannot be confirmed editable are excluded.

macOS first inserts through Accessibility, with system paste as a fallback. The fallback temporarily uses the clipboard and restores it after about one second; newly copied clipboard content is preserved. Windows sends Unicode keyboard input without modifying the clipboard or sending Enter or Tab. Windows may block input into elevated apps. Accepted input events do not guarantee that a particular app displays the text; check the field before manually copying after a failure.

Custom editors, games, remote desktops and some web controls may be incompatible. macOS does not send Return; terminal paste behavior is controlled by the terminal.

## Troubleshooting

- **macOS “Siri and Dictation are disabled”:** enable system Dictation and accept its prompts. Check Screen Time or device management restrictions if the switch is unavailable.
- **Empty Windows language list:** try installing Speech in the language options and restart. Only compatible SAPI engines work; modern dictation packages may not expose one.
- **Text remains in the preview:** check auto-finish or use the start / finish shortcut again.
- **Text is not inserted:** keep the target field focused and check permissions and control compatibility. Copy the latest result manually if needed.
- **Windows hotkey registration fails:** close the conflicting app and restart Voxa.

## Build from source

### macOS

Requires Apple Silicon, macOS 13+, and Xcode command line tools:

```sh
bash scripts/build.sh
bash scripts/test.sh
bash scripts/package-macos.sh
```

Outputs `build/Voxa.app`, a DMG and a ZIP. Builds prefer a local Apple Development identity and otherwise use ad hoc signing. Set `VOICECURSOR_SIGN_IDENTITY` to select an identity. Packaging does not automatically notarize the app.

### Windows

Install the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0). Installer builds also require [NSIS 3](https://nsis.sourceforge.io/Download) with `makensis` on PATH:

```powershell
./windows/build-installer.ps1
```

Use `./windows/build.ps1` for the portable package only. Cross-platform packaging commands are in the Windows guide. GitHub Actions builds packages and runs basic checks; `v*` tags upload both platforms' artifacts to their GitHub Release.

## Validation scope

macOS checks cover shortcut sequences, ordinary-space replay, password-field policy, auto-finish, clipboard restoration and startup. Windows core checks cover partial/final transcript merging, Chinese spacing, repeated utterances, auto-finish, control-character cleaning and native input structure layout. CI checks Windows startup and silent installation / removal. These checks do not replace live microphone and cross-app insertion testing.
