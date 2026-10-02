Unicode true
!include "MUI2.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!ifndef VOXA_VERSION
  !define VOXA_VERSION "1.2.0"
!endif

Name "Voxa ${VOXA_VERSION}"
OutFile "../build/windows/Voxa-v${VOXA_VERSION}-Windows-Setup-x64.exe"
InstallDir "$LOCALAPPDATA\Programs\Voxa"
RequestExecutionLevel user
SetCompressor /SOLID lzma
VIProductVersion "${VOXA_VERSION}.0"
VIAddVersionKey "ProductName" "Voxa"
VIAddVersionKey "FileDescription" "Voxa Windows Installer"
VIAddVersionKey "FileVersion" "${VOXA_VERSION}"
VIAddVersionKey "ProductVersion" "${VOXA_VERSION}"
VIAddVersionKey "LegalCopyright" "Voxa contributors"

!define MUI_ICON "Voxa.Windows/Voxa.ico"
!define MUI_UNICON "Voxa.Windows/Voxa.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\Voxa.exe"
!define MUI_LANGDLL_REGISTRY_ROOT HKCU
!define MUI_LANGDLL_REGISTRY_KEY "Software\Voxa\Installer"
!define MUI_LANGDLL_REGISTRY_VALUENAME "Language"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

LangString UnsupportedOS ${LANG_ENGLISH} "Voxa requires Windows 10 or later on an x64-compatible PC."
LangString UnsupportedOS ${LANG_SIMPCHINESE} "Voxa 需要 Windows 10 或更高版本及兼容 x64 的电脑。"
LangString CloseVoxa ${LANG_ENGLISH} "Please exit Voxa from the system tray before installing or uninstalling."
LangString CloseVoxa ${LANG_SIMPCHINESE} "请先通过系统托盘退出 Voxa，再安装或卸载。"
LangString InstallSection ${LANG_ENGLISH} "Install Voxa"
LangString InstallSection ${LANG_SIMPCHINESE} "安装 Voxa"

Function CheckRunning
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\Voxa.Windows") p.r0'
  ${If} $0 != 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(CloseVoxa)" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
FunctionEnd

Function .onInit
  SetShellVarContext current
  SetRegView 64
  !insertmacro MUI_LANGDLL_DISPLAY
  ${IfNot} ${AtLeastWin10}
    MessageBox MB_OK|MB_ICONSTOP "$(UnsupportedOS)" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "$(UnsupportedOS)" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  Call CheckRunning
FunctionEnd

Section "$(InstallSection)"
  SetOutPath "$INSTDIR"
  File /r "..\build\windows\win-x64\*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Voxa"
  CreateShortcut "$SMPROGRAMS\Voxa\Voxa.lnk" "$INSTDIR\Voxa.exe"
  CreateShortcut "$SMPROGRAMS\Voxa\Uninstall Voxa.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\Voxa.lnk" "$INSTDIR\Voxa.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa" "DisplayName" "Voxa"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa" "DisplayVersion" "${VOXA_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa" "DisplayIcon" "$INSTDIR\Voxa.exe"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa" "NoRepair" 1
SectionEnd

Function un.onInit
  SetShellVarContext current
  SetRegView 64
  !insertmacro MUI_UNGETLANGUAGE
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\Voxa.Windows") p.r0'
  ${If} $0 != 0
    System::Call 'kernel32::CloseHandle(p r0)'
    MessageBox MB_OK|MB_ICONEXCLAMATION "$(CloseVoxa)" /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
FunctionEnd

Section "Uninstall"
  Delete "$DESKTOP\Voxa.lnk"
  RMDir /r "$SMPROGRAMS\Voxa"
  ; This is the dedicated installation directory, never the separate user settings folder.
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa"
  DeleteRegKey HKCU "Software\Voxa\Installer"
SectionEnd
