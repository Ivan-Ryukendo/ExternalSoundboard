<#
  ExternalSoundboard installer for Vencord (Windows).
  One line, in PowerShell:
    irm https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main/install.ps1 | iex
  Re-run it any time to update Vencord and the plugin.
  Options (when running the file directly): -InstallDir <path>  -Branch stable|canary|ptb|auto  -SkipInject
#>
param(
    [string]$InstallDir = (Join-Path $HOME "Vencord-ExternalSoundboard"),
    [string]$Branch = "",
    [switch]$SkipInject
)
$ErrorActionPreference = "Stop"
$raw = "https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main"

function Fail($msg) { Write-Host "`n$msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Run($exe, $dir, [string[]]$a) {
    Push-Location $dir
    try { & $exe @a; if ($LASTEXITCODE) { throw "'$exe $($a -join ' ')' failed (exit $LASTEXITCODE)" } } finally { Pop-Location }
}

Step "Checking requirements"
$missing = @()
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $missing += "Git      -> winget install Git.Git   (or https://git-scm.com)" }
$nodeMajor = 0
if (Get-Command node -ErrorAction SilentlyContinue) { $nodeMajor = [int]((node --version) -replace '^v(\d+).*', '$1') }
if ($nodeMajor -lt 22) { $missing += "Node.js 22 or newer -> winget install OpenJS.NodeJS   (or https://nodejs.org)" }
if ($missing) {
    $missing | ForEach-Object { Write-Host "  missing: $_" -ForegroundColor Yellow }
    Fail "Install the above, open a NEW PowerShell window, and run this installer again."
}
Write-Host "  git and node $(node --version) found. pnpm is fetched automatically."

Step "Getting Vencord ($InstallDir)"
if (Test-Path (Join-Path $InstallDir ".git")) {
    try { Run git $InstallDir @("pull", "--ff-only") } catch { Write-Host "  could not update Vencord, building the version you have" -ForegroundColor Yellow }
} else {
    Run git $HOME @("clone", "--depth", "1", "https://github.com/Vendicated/Vencord.git", $InstallDir)
}

Step "Adding the ExternalSoundboard plugin"
$dest = Join-Path $InstallDir "src\userplugins\externalSoundboard"
New-Item -ItemType Directory -Force $dest | Out-Null
$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot "vencord\externalSoundboard" } else { "" }
foreach ($f in "index.tsx", "settings.tsx") {
    if ($local -and (Test-Path (Join-Path $local $f))) { Copy-Item (Join-Path $local $f) $dest -Force }
    else { Invoke-WebRequest "$raw/vencord/externalSoundboard/$f" -OutFile (Join-Path $dest $f) -UseBasicParsing }
}

Step "Building Vencord (a few minutes the first time)"
# the repo pins its pnpm version. Install exactly that into a private folder and run its .mjs with node:
# the npx/global launcher shims for pnpm 12 are broken on some Windows setups, the .mjs entry is not.
$pnpmVer = ((Get-Content (Join-Path $InstallDir "package.json") -Raw | ConvertFrom-Json).packageManager) -replace '^pnpm@', '' -replace '\+.*$', ''
$tool = Join-Path $InstallDir ".pnpm-tool"
$pnpmMjs = Join-Path $tool "node_modules\pnpm\bin\pnpm.mjs"
if (-not (Test-Path $pnpmMjs)) { Run npm $HOME @("install", "--prefix", $tool, "pnpm@$pnpmVer", "--no-audit", "--no-fund", "--loglevel=error") }
Run node $InstallDir @($pnpmMjs, "install", "--frozen-lockfile")
Run node $InstallDir @($pnpmMjs, "build")

if ($SkipInject) { Write-Host "`nBuilt. Skipped injecting into Discord (-SkipInject)." -ForegroundColor Green; exit 0 }

Step "Which Discord do you use?"
if (-not $Branch) {
    Write-Host "  1) Stable   2) Canary   3) PTB   4) Auto-detect"
    Write-Host "  Several? Type numbers separated by commas, e.g. 1,2.  Enter = skip (inject later)."
    $names = @{ "1" = "stable"; "2" = "canary"; "3" = "ptb"; "4" = "auto" }
    $Branch = (($(Read-Host "  Your choice") -split '[,\s]+' | Where-Object { $names[$_] } | ForEach-Object { $names[$_] }) -join ",")
}
if (-not $Branch) { Write-Host "  Skipped. Later, run:  node scripts/runInstaller.mjs -- -install -branch <stable|canary|ptb>  in $InstallDir" }
else {
    Write-Host "  Close Discord first (right-click its tray icon > Quit)." -ForegroundColor Yellow
    foreach ($b in $Branch -split ",") { Step "Injecting into Discord $b"; Run node $InstallDir @("scripts/runInstaller.mjs", "--", "-install", "-branch", $b) }
}

Write-Host "`nDone." -ForegroundColor Green
Write-Host "  1. Fully restart Discord."
Write-Host "  2. Settings > Vencord > Plugins > enable ExternalSoundboard."
Write-Host "  3. Set up your loopback device: https://github.com/Ivan-Ryukendo/ExternalSoundboard/blob/main/docs/audio-setup.md"
