param([switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'Voxa.Windows/Voxa.Windows.csproj'
$tests = Join-Path $PSScriptRoot 'Voxa.Core.Tests/Voxa.Core.Tests.csproj'
$output = Join-Path $PSScriptRoot '../build/windows/win-x64'
[xml]$projectXml = Get-Content $project
$version = [string]$projectXml.Project.PropertyGroup.Version
$archive = Join-Path $PSScriptRoot "../build/windows/Voxa-v$version-Windows-x64.zip"
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'Install the .NET 8 SDK from https://dotnet.microsoft.com/download/dotnet/8.0 first.'
}
if (-not $SkipTests) {
    dotnet run --project $tests -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
}
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -o $output --nologo
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
$windowsDocs = Join-Path $output 'windows'
$assets = Join-Path $output 'Assets'
New-Item -ItemType Directory -Force -Path $windowsDocs, $assets | Out-Null
Copy-Item (Join-Path $PSScriptRoot '../README.md') (Join-Path $output 'README.md') -Force
Copy-Item (Join-Path $PSScriptRoot '../README.en.md') (Join-Path $output 'README.en.md') -Force
Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $windowsDocs 'README.md') -Force
Copy-Item (Join-Path $PSScriptRoot 'README.en.md') (Join-Path $windowsDocs 'README.en.md') -Force
Copy-Item (Join-Path $PSScriptRoot '../Assets/Voxa-icon.png') (Join-Path $assets 'Voxa-icon.png') -Force
Compress-Archive -Path (Join-Path $output '*') -DestinationPath $archive -Force
Write-Host "Portable app: $output/Voxa.exe"
Write-Host "Archive: $archive"
