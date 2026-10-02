# Voxa for Windows

[中文](README.md) | [English](README.en.md) · [Project home](../README.en.md)

Native Windows dictation built with C#, .NET 8, WinForms and local `System.Speech` / SAPI recognition. No API key is needed. The macOS implementation is in the root `Sources/` folder.

This is the first Windows implementation. It has been cross-compiled on macOS and passed core logic checks. Live microphone recognition and cross-app insertion still require testing on Windows. CI builds the app and checks startup and silent installation / removal.

## Requirements

- Windows 10 / 11, x64. A supported Windows 11 release is recommended. Native ARM64 support is not claimed.
- A working default recording device, with desktop microphone access enabled in Windows privacy settings.
- A **desktop SAPI recognition engine supporting dictation**. Only engines returned by `SpeechRecognitionEngine.InstalledRecognizers()` are listed; Chinese and other languages are not assumed to be installed.
- Try installing Speech in Windows language options and restarting Voxa. Compatibility depends on the Windows version and installed language components. An empty list means dictation is unavailable in this version.
- Voice Access, Win + H, online dictation and text-to-speech packages do not establish SAPI compatibility. Windows 11 24H2 removed the legacy Windows Speech Recognition interface. A compatible legacy engine cannot be assumed; Voxa does not silently fall back to a cloud service.

## Install and uninstall

Download `Voxa-v1.2.0-Windows-Setup-x64.exe` from the [v1.2.0 Release](https://github.com/SergioTermann/Voxa/releases/tag/v1.2.0), run it and choose the Chinese or English wizard.

- The installer includes the .NET runtime. Users do not need a separate .NET installation or administrator permission.
- Installs to `%LOCALAPPDATA%\Programs\Voxa` with Start menu and desktop shortcuts.
- Exit Voxa from the tray before upgrading or uninstalling. Remove it through Windows Installed Apps.
- Uninstall preserves `%LOCALAPPDATA%\Voxa\settings.json`, which contains preferences only, without audio or transcript text.
- The installer is currently unsigned; Windows may show an unknown publisher prompt.
- For the portable ZIP, extract every file and run `Voxa.exe`, keeping all included runtime files together.

## Build

Install the [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0). Installer builds also require [NSIS 3](https://nsis.sourceforge.io/Download) with `makensis` on PATH.

From the repository root in PowerShell:

```powershell
./windows/build-installer.ps1
```

This runs core checks, publishes the self-contained application, and compiles the installer. Use `./windows/build.ps1` for the portable package only.

```text
build/windows/Voxa-v1.2.0-Windows-Setup-x64.exe
build/windows/Voxa-v1.2.0-Windows-x64.zip
build/windows/win-x64/Voxa.exe
```

macOS / Linux can cross-compile and package with NSIS, but cannot run the Windows app directly:

```sh
dotnet run --project windows/Voxa.Core.Tests -c Release
dotnet publish windows/Voxa.Windows/Voxa.Windows.csproj -c Release -r win-x64 --self-contained true -o build/windows/win-x64
mkdir -p build/windows/win-x64/windows build/windows/win-x64/Assets
cp README.md build/windows/win-x64/README.md
cp README.en.md build/windows/win-x64/README.en.md
cp windows/README.md build/windows/win-x64/windows/README.md
cp windows/README.en.md build/windows/win-x64/windows/README.en.md
cp Assets/Voxa-icon.png build/windows/win-x64/Assets/Voxa-icon.png
makensis windows/Voxa-Setup.nsi
```

The **Windows build and installer** GitHub workflow produces the installer and ZIP. On `v*` tags, **Release installers** uploads both platforms' packages to the matching GitHub Release.

## Usage

1. Launch Voxa, select an installed local recognition language, and optionally enable automatic completion after a pause.
2. Click an editable field in Notepad or another app.
3. Press **Ctrl + Alt + Space** to start. A preview that does not activate its window shows the recognized text.
4. Pause to finish automatically or press **Ctrl + Alt + Space** again. Auto-finish requires confirmed text, stable recognition and no speech activity for about 1.6 seconds; the engine's own segmentation adds delay.
5. **Ctrl + Alt + Esc** cancels. Sessions last approximately 55 seconds, with a further completion timeout of up to 5 seconds.
6. Closing settings hides the app to the tray. Reopen settings, copy the latest result or quit from the tray.

If a hotkey is already taken, settings shows registration failure. Close the conflicting app and restart Voxa. This version uses fixed shortcuts without the macOS Command double-tap or triple Space triggers. The Windows app interface is Chinese; the installer offers Chinese and English.

## Insertion behavior

- Starting recognition requires an external editable field. UI Automation checks editability, keyboard focus and password status. Controls that cannot be confirmed editable are rejected.
- You may switch fields while dictating. The target is captured **at completion**, and the window and control focus are checked again before sending input.
- `SendInput` sends Unicode keystrokes, preserving the target app's normal selection replacement behavior. It does not modify the clipboard or send Enter or Tab. Held shortcut modifiers cause a short wait and another focus check.
- Elevated applications, remote desktops, games, custom editors and web controls with limited UI Automation support may not accept input. Windows can block injection into higher-privilege windows.
- Focus changes, unavailable controls, recognition errors or injection failures preserve confirmed text for manual copying. Partial injection may already have inserted some text; inspect the field before copying to avoid duplicates.
- Accepted Windows input events do not prove that the app displayed the text. There is no clipboard-paste fallback.
- Hypotheses are previewed but never inserted as final results. Cancel discards the unfinished session and preserves the previous completed result.

## Privacy and preferences

Voxa uses the selected local SAPI engine and implements no cloud API calls. It does not save recordings or transcript logs. Text stays in memory and is cleared on exit. Copying places text on the system clipboard, subject to clipboard history and sync settings.

Only the recognizer ID and auto-finish preference are written to:

```text
%LOCALAPPDATA%\Voxa\settings.json
```

Global shortcuts use `RegisterHotKey`; other keyboard input is not logged. The app runs as a regular user without elevation.

## Validation

Cross-platform checks cover partial/final result replacement, multi-utterance merging, repeated phrases, Chinese spacing, auto-finish behavior, control-character cleaning and native `SendInput` layout. Windows CI also checks startup and silent installation / removal.

Before deployment, validate the following on the target device:

- Authorized / unauthorized microphones, missing default devices, and real Chinese / English engine recognition.
- Insertion and selection replacement in Notepad and browser fields, with rejection of unsupported controls.
- Automatic / manual completion, cancellation, held modifiers, session limits and repeated sessions.
- Focus changes during completion, password-field rejection, and elevated-window failures with text retained.
- Automatic insertion leaves the clipboard unchanged; closing settings keeps the tray active; quitting releases the microphone and hotkeys; a second launch does not create another instance.
- Missing compatible engines, hotkey conflicts, multiple displays and high DPI.
