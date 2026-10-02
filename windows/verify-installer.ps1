param([Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference = 'Stop'
$installDirectory = Join-Path $env:LOCALAPPDATA 'Programs/Voxa'
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Voxa'
if (Test-Path $installDirectory) { throw 'Installer check needs a clean test account without an existing Voxa installation.' }
$setup = Start-Process -FilePath (Resolve-Path $Installer).Path -ArgumentList '/S' -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "Installer returned $($setup.ExitCode)." }
if (-not (Test-Path (Join-Path $installDirectory 'Voxa.exe'))) { throw 'Application missing after installation.' }
if (-not (Test-Path (Join-Path $installDirectory 'Uninstall.exe'))) { throw 'Uninstaller missing.' }
if (-not (Test-Path $registryPath)) { throw 'Installed Apps registration missing.' }
$app = Start-Process -FilePath (Join-Path $installDirectory 'Voxa.exe') -PassThru
try {
    Start-Sleep -Seconds 5
    $app.Refresh()
    if ($app.HasExited) { throw "Installed application exited unexpectedly: $($app.ExitCode)" }
} finally {
    if (-not $app.HasExited) { Stop-Process -Id $app.Id; $app.WaitForExit() }
}
$remove = Start-Process -FilePath (Join-Path $installDirectory 'Uninstall.exe') -ArgumentList '/S' -Wait -PassThru
if ($remove.ExitCode -ne 0) { throw "Uninstaller returned $($remove.ExitCode)." }
for ($attempt = 0; $attempt -lt 30 -and (Test-Path $installDirectory); $attempt++) { Start-Sleep -Milliseconds 500 }
if (Test-Path $installDirectory) { throw 'Installation directory remains after uninstall.' }
if (Test-Path $registryPath) { throw 'Installed Apps registration remains after uninstall.' }
Write-Host 'Silent install, installed app startup, and uninstall checks passed.'
