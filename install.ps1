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
    # git and npm write progress to stderr; with ErrorActionPreference=Stop PowerShell 5.1 would treat that as a failure
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $exe @a; if ($LASTEXITCODE) { throw "'$exe $($a -join ' ')' failed (exit $LASTEXITCODE)" } } finally { $ErrorActionPreference = $prev; Pop-Location }
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

Step "Getting Vencord"
# A Vencord source checkout you already have is reused as is (never re-cloned or pulled). The ready-made
# Vencord from vencord.dev has no source, so a custom plugin can't be added to it: we need a checkout.
function IsVencordSource($d) {
    try { (Test-Path (Join-Path $d "scripts\runInstaller.mjs")) -and ((Get-Content (Join-Path $d "package.json") -Raw | ConvertFrom-Json).name -eq "vencord") } catch { $false }
}
if (-not $PSBoundParameters.ContainsKey("InstallDir") -and -not (Test-Path (Join-Path $InstallDir ".git"))) {
    $found = "Vencord", "Documents\Vencord", "Desktop\Vencord", "Downloads\Vencord", "source\repos\Vencord", "dev\Vencord" |
        ForEach-Object { Join-Path $HOME $_ } | Where-Object { IsVencordSource $_ } | Select-Object -First 1
    if ($found) { $InstallDir = $found; $reused = $true }
}
$changed = $false
if ($reused) {
    Write-Host "  Using your existing Vencord source: $InstallDir (not re-downloaded)"
} elseif (Test-Path (Join-Path $InstallDir ".git")) {
    $before = (& git -C $InstallDir rev-parse HEAD)
    try { Run git $InstallDir @("pull", "--ff-only") } catch { Write-Host "  could not update Vencord, building the version you have" -ForegroundColor Yellow }
    if ((& git -C $InstallDir rev-parse HEAD) -ne $before) { $changed = $true }
    Write-Host "  Vencord already downloaded, reusing it."
} else {
    Run git $HOME @("clone", "--depth", "1", "https://github.com/Vendicated/Vencord.git", $InstallDir)
    New-Item (Join-Path $InstallDir ".externalsoundboard-owned") -ItemType File -Force | Out-Null
    $changed = $true
}

Step "Adding the ExternalSoundboard plugin"
$dest = Join-Path $InstallDir "src\userplugins\externalSoundboard"
New-Item -ItemType Directory -Force $dest | Out-Null
$local = if ($PSScriptRoot) { Join-Path $PSScriptRoot "vencord\externalSoundboard" } else { "" }
foreach ($f in "index.tsx", "settings.tsx") {
    $target = Join-Path $dest $f
    $old = if (Test-Path $target) { (Get-FileHash $target).Hash } else { "" }
    if ($local -and (Test-Path (Join-Path $local $f))) { Copy-Item (Join-Path $local $f) $dest -Force }
    else { Invoke-WebRequest "$raw/vencord/externalSoundboard/$f" -OutFile $target -UseBasicParsing }
    if ((Get-FileHash $target).Hash -ne $old) { $changed = $true }
}

if (-not $changed -and (Test-Path (Join-Path $InstallDir "dist\patcher.js"))) {
    Write-Host "`nPlugin and Vencord are already up to date, no rebuild needed." -ForegroundColor Green
} else {
    Step "Building Vencord (a few minutes the first time)"
    # the repo pins its pnpm version. Install exactly that into a private folder and run its .mjs with node:
    # the npx/global launcher shims for pnpm 12 are broken on some Windows setups, the .mjs entry is not.
    $pnpmVer = ((Get-Content (Join-Path $InstallDir "package.json") -Raw | ConvertFrom-Json).packageManager) -replace '^pnpm@', '' -replace '\+.*$', ''
    $tool = Join-Path $InstallDir ".pnpm-tool"
    $pnpmMjs = Join-Path $tool "node_modules\pnpm\bin\pnpm.mjs"
    if (-not (Test-Path $pnpmMjs)) { Run npm $HOME @("install", "--prefix", $tool, "pnpm@$pnpmVer", "--no-audit", "--no-fund", "--loglevel=error") }
    Run node $InstallDir @($pnpmMjs, "install", "--frozen-lockfile")
    Run node $InstallDir @($pnpmMjs, "build")
}

# true when this Discord already loads the Vencord build in $InstallDir (its app.asar names our dist folder)
function AlreadyPatched($b) {
    $dir = @{ stable = "Discord"; canary = "DiscordCanary"; ptb = "DiscordPTB" }[$b]
    if (-not $dir) { return $false }
    $needle = (Join-Path $InstallDir "dist\patcher.js").Replace("\", "\\")
    Get-ChildItem (Join-Path $env:LOCALAPPDATA $dir) -Directory -Filter "app-*" -ErrorAction SilentlyContinue | ForEach-Object {
        $asar = Join-Path $_.FullName "resources\app.asar"
        if ((Test-Path $asar) -and ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($asar))).Contains($needle)) { return $true }
    } | Select-Object -First 1
}

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
    foreach ($b in $Branch -split ",") {
        if (AlreadyPatched $b) { Write-Host "`nDiscord $b already uses this Vencord, nothing to inject." -ForegroundColor Green; continue }
        Step "Injecting into Discord $b"; Run node $InstallDir @("scripts/runInstaller.mjs", "--", "-install", "-branch", $b)
    }
}

Write-Host "`nDone." -ForegroundColor Green
Write-Host "  1. Fully restart Discord."
Write-Host "  2. Settings > Vencord > Plugins > enable ExternalSoundboard."
Write-Host "  3. Set up your loopback device: https://github.com/Ivan-Ryukendo/ExternalSoundboard/blob/main/docs/audio-setup.md"
