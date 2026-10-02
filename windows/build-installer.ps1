param([switch]$SkipTests, [switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build.ps1') -SkipTests:$SkipTests }
$compiler = Get-Command makensis -ErrorAction SilentlyContinue
if (-not $compiler) { throw 'Install NSIS and add makensis to PATH: https://nsis.sourceforge.io/Download' }
[xml]$project = Get-Content (Join-Path $PSScriptRoot 'Voxa.Windows/Voxa.Windows.csproj')
$version = [string]$project.Project.PropertyGroup.Version
& $compiler.Source "/DVOXA_VERSION=$version" (Join-Path $PSScriptRoot 'Voxa-Setup.nsi')
if ($LASTEXITCODE -ne 0) { throw 'NSIS installer build failed.' }
Write-Host "Installer: build/windows/Voxa-v$version-Windows-Setup-x64.exe"
