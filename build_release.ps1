# SkyLink AI — Release Build Script
# Run from Developer PowerShell for VS 2022
# Produces a ready-to-zip release folder

param(
    [string]$Version = "1.0.0",
    [string]$OutputDir = "release",
    [string]$VcpkgRoot = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\vcpkg"
)

$ErrorActionPreference = "Stop"
$PluginDir = Join-Path $PSScriptRoot "SkyrimMCPPlugin"

# Use .NET directly so hashing does not depend on a loaded PowerShell module.
function Get-Sha256([string]$Path) {
    $Stream = [IO.File]::OpenRead($Path)
    $Sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($Sha.ComputeHash($Stream))).Replace("-", "") }
    finally { $Stream.Dispose(); $Sha.Dispose() }
}
$OutputDir = if ([IO.Path]::IsPathRooted($OutputDir)) { [IO.Path]::GetFullPath($OutputDir) } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $OutputDir)) }
$CMakeLists = Get-Content (Join-Path $PluginDir "CMakeLists.txt") -Raw
if ($CMakeLists -notmatch '(?ms)project\s*\(\s*SkyrimMCPPlugin\s+VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)') {
    throw "Could not read SkyrimMCPPlugin version from CMakeLists.txt."
}
if ($Version -ne $Matches[1]) {
    throw "Package version '$Version' does not match native CMake project version '$($Matches[1])'. Use -Version '$($Matches[1])'."
}
if (Test-Path $OutputDir) {
    throw "Output directory already exists: '$OutputDir'. Choose a fresh -OutputDir; existing output is never deleted."
}

$env:VCPKG_ROOT = $VcpkgRoot
$env:SKYRIM_FOLDER = $null
$env:SKYRIM_MODS_FOLDER = $null
$NativeTarget = Join-Path $PluginDir "build\Release\SkyrimMCPPlugin.dll"
$CanonicalDll = Join-Path $PluginDir "output\SkyrimMCPPlugin.dll"
$PackagePluginDir = Join-Path $OutputDir "Data\SKSE\Plugins"
$ServerOutputDir = Join-Path $PackagePluginDir "SkyLinkAI_Server"

Write-Host "=== Building SkyLink AI v$Version ===" -ForegroundColor Cyan
Write-Host "CommonLibVR source: $(Join-Path $PluginDir 'extern\CommonLibVR')"

Write-Host "`n--- Configuring SKSE Plugin (C++) ---" -ForegroundColor Yellow
Push-Location $PluginDir
try {
    cmake --preset default
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed with exit code $LASTEXITCODE." }
    cmake --build build --config Release
    if ($LASTEXITCODE -ne 0) { throw "CMake build failed with exit code $LASTEXITCODE." }
}
finally {
    Pop-Location
}

if (-not (Test-Path $NativeTarget -PathType Leaf)) {
    throw "Fresh native target DLL was not produced: '$NativeTarget'."
}
if (-not (Test-Path $CanonicalDll -PathType Leaf)) {
    throw "CMake canonical output DLL was not produced: '$CanonicalDll'."
}
$NativeHash = Get-Sha256 $NativeTarget
$CanonicalHash = Get-Sha256 $CanonicalDll
if ($NativeHash -ne $CanonicalHash) {
    throw "Fresh target and canonical DLL hashes differ; refusing to package."
}

Write-Host "`n--- Building MCP Server (C#) ---" -ForegroundColor Yellow
dotnet publish (Join-Path $PSScriptRoot "SkyrimMCP") -c Release -o $ServerOutputDir --no-self-contained
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE." }

Write-Host "`n--- Packaging ---" -ForegroundColor Yellow
Copy-Item $NativeTarget $PackagePluginDir
$PackageDll = Join-Path $PackagePluginDir "SkyrimMCPPlugin.dll"
$PackageHash = Get-Sha256 $PackageDll
if ($PackageHash -ne $NativeHash) {
    throw "Packaged DLL hash does not match the fresh native target; refusing to complete package."
}
New-Item -ItemType Directory -Path (Join-Path $OutputDir "licenses") | Out-Null
Copy-Item (Join-Path $PSScriptRoot "licenses\LICENSE-CommonLibVR.txt") (Join-Path $OutputDir "licenses")
Copy-Item (Join-Path $PSScriptRoot "licenses\LICENSE-ConsoleUtilSSE.txt") (Join-Path $OutputDir "licenses")
foreach ($Dependency in @("directxmath", "directxtk", "fmt", "nlohmann-json", "rapidcsv", "spdlog")) {
    $Notice = Join-Path $PluginDir "build\vcpkg_installed\x64-windows-static\share\$Dependency\copyright"
    Copy-Item $Notice (Join-Path $OutputDir "licenses\LICENSE-$Dependency.txt")
}
Copy-Item (Join-Path $PluginDir "extern\CommonLibVR\extern\openvr\LICENSE") (Join-Path $OutputDir "licenses\LICENSE-openvr.txt")

# Follow the published dependency graph, not a hand-maintained package list.
$Assets = Get-Content (Join-Path $PSScriptRoot "SkyrimMCP\obj\project.assets.json") -Raw | ConvertFrom-Json
$PublishedDeps = Get-Content (Join-Path $ServerOutputDir "SkyrimMCP.deps.json") -Raw | ConvertFrom-Json
$DotNetNotices = Join-Path $OutputDir "licenses\dotnet"
New-Item -ItemType Directory -Path $DotNetNotices | Out-Null
foreach ($Library in $PublishedDeps.libraries.PSObject.Properties | Where-Object { $_.Value.type -eq "package" }) {
    $Package = $Assets.libraries.PSObject.Properties[$Library.Name].Value
    if (-not $Package) { throw "Missing restored metadata for published dependency $($Library.Name)." }
    $PackageDir = $Assets.packageFolders.PSObject.Properties.Name |
        ForEach-Object { Join-Path $_ $Package.path } |
        Where-Object { Test-Path $_ -PathType Container } |
        Select-Object -First 1
    if (-not $PackageDir) { throw "Missing restored package $($Library.Name)." }
    $Nuspec = $Package.files | Where-Object { $_ -like "*.nuspec" } | Select-Object -First 1
    if (-not $Nuspec) { throw "Missing license metadata for $($Library.Name)." }
    $Metadata = ([xml](Get-Content (Join-Path $PackageDir $Nuspec) -Raw)).package.metadata
    if ($Metadata.license.type -ne "expression" -or $Metadata.license.InnerText -ne "MIT") {
        throw "Review the license for $($Library.Name) before packaging it."
    }
    $LicenseFile = $Package.files | Where-Object { $_ -match '(^|/)LICENSE(\.TXT)?$' } | Select-Object -First 1
    if ($LicenseFile) {
        $LicenseSource = Join-Path $PackageDir $LicenseFile
    } elseif ($Metadata.repository.url -eq "https://github.com/modelcontextprotocol/csharp-sdk") {
        $LicenseSource = Join-Path $PSScriptRoot "licenses\LICENSE-ModelContextProtocol.txt"
    } elseif ($Metadata.repository.url -eq "https://github.com/dotnet/extensions") {
        $LicenseSource = Join-Path $PSScriptRoot "licenses\LICENSE-dotnet-extensions.txt"
    } elseif ($Metadata.repository.url -eq "https://github.com/dotnet/dotnet") {
        $LicenseSource = Join-Path $PSScriptRoot "licenses\LICENSE-dotnet.txt"
    } else {
        throw "Missing upstream license text for $($Library.Name)."
    }
    $PackageName = $Library.Name.Replace("/", "-")
    Copy-Item $LicenseSource (Join-Path $DotNetNotices "$PackageName-LICENSE.txt")
    Copy-Item (Join-Path $PackageDir $Nuspec) (Join-Path $DotNetNotices "$PackageName.nuspec")
    if ($Metadata.repository.url -eq "https://github.com/dotnet/extensions") {
        Copy-Item (Join-Path $PSScriptRoot "licenses\THIRD-PARTY-NOTICES-dotnet-extensions.txt") (Join-Path $DotNetNotices "$PackageName-THIRD-PARTY-NOTICES.TXT")
    }
    foreach ($NoticeFile in $Package.files | Where-Object { $_ -match '(^|/)(THIRD[-_]PARTY[-_]NOTICES|NOTICE)(\..*)?$' }) {
        Copy-Item (Join-Path $PackageDir $NoticeFile) (Join-Path $DotNetNotices "$PackageName-$(Split-Path $NoticeFile -Leaf)")
    }
}

# Create example config
$config = @{
    mcpServers = @{
        skyrim = @{
            command = "dotnet"
            args = @("<SKYRIM_PATH>\Data\SKSE\Plugins\SkyLinkAI_Server\SkyrimMCP.dll")
        }
    }
}
$config | ConvertTo-Json -Depth 4 | Set-Content "$OutputDir\claude_desktop_config_example.json"

# Create README
@"
# SkyLink AI v$Version

An MCP server that lets AI assistants (Claude, etc.) interact directly
with Skyrim SE/AE's runtime engine via an SKSE plugin.

## Requirements
- Skyrim SE or AE
- SKSE64 (https://skse.silverlock.org/)
- Address Library for SKSE (https://www.nexusmods.com/skyrimspecialedition/mods/32444)
- .NET 10 Runtime (https://dotnet.microsoft.com/download/dotnet/10.0)
- Claude Desktop (https://claude.ai/desktop)

Required runtime acceptance passed on Skyrim SE/AE 1.7.104.0.
Supplemental basic smoke passed on 1.6.1170.0, not full-version certification.
VR, other patches and unexercised tools remain outside that acceptance claim.
These results apply to the tested candidate hashes recorded in the repository
README; compare installed/package hashes before transferring runtime evidence.

## Installation
1. Extract the Data folder into your Skyrim directory
   (or install via Mod Organizer 2 / Vortex)
2. Install .NET 10 Runtime if not already installed
3. Configure Claude Desktop (see below)

## Claude Desktop Configuration
Edit %APPDATA%\Claude\claude_desktop_config.json:

{
  "mcpServers": {
    "skyrim": {
      "command": "dotnet",
      "args": ["<SKYRIM_PATH>\\Data\\SKSE\\Plugins\\SkyLinkAI_Server\\SkyrimMCP.dll"]
    }
  }
}

Replace <SKYRIM_PATH> with your Skyrim installation path.

## Usage
1. Launch Skyrim via SKSE
2. Open Claude Desktop
3. Ask Claude to interact with your game!

## Features
- 87 MCP tools for reading and modifying game state
- Player stats, inventory, spells, perks, shouts, appearance
- Quest management, NPC interaction, follower management
- Weather control, world objects, containers, locks
- Combat analysis, threat assessment, damage stats
- Event system (combat, death, quest updates, location changes)
- Character blueprint export/import
- Papyrus VM bridge (call any mod's Papyrus functions)
- Form search engine (replaces console 'help' command)

## Credits

- Console execution adapted from the historical MIT ConsoleUtilSSE source at 0eb69c6c0d7366065f2408180216ec6cd8a40d5e (see licenses/LICENSE-ConsoleUtilSSE.txt); no newer GPL source imported.
- MinLL/CommonLibVR v4.39.5, pin 550cc4fb9114649dcf526d1f3d73d710c5d7003b (MIT; see licenses/LICENSE-CommonLibVR.txt).
- Packaged .NET dependencies: exact published package versions, MIT license texts, upstream metadata/copyright and available third-party notices are included in licenses/dotnet/.
"@ | Set-Content "$OutputDir\README.txt"

Write-Host "`n=== Local Candidate Package Complete ===" -ForegroundColor Green
Write-Host "Release folder: $OutputDir\"
Write-Host "  SKSE Plugin: $OutputDir\Data\SKSE\Plugins\SkyrimMCPPlugin.dll"
Write-Host "  MCP Server:  $OutputDir\Data\SKSE\Plugins\SkyLinkAI_Server\"
Write-Host "`nLocal package only; runtime acceptance applies to the tested hashes recorded in README.md."
