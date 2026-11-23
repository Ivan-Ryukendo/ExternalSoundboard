<#
  ExternalSoundboard uninstaller (Windows).
  One line, in PowerShell:
    irm https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main/uninstall.ps1 | iex
  Options (when running the file directly):
    -Mode plugin|vencord|betterdiscord|all   skip the menu
    -InstallDir <path>                       the Vencord folder the installer made (default ~\Vencord-ExternalSoundboard)
    -DeleteData                              also delete %APPDATA%\Vencord and/or %APPDATA%\BetterDiscord
    -Yes                                     don't ask for confirmation
#>
param(
    [string]$Mode = "",
    [string]$InstallDir = (Join-Path $HOME "Vencord-ExternalSoundboard"),
    [switch]$DeleteData,
    [switch]$Yes
)
$ErrorActionPreference = "Stop"
$removed = New-Object System.Collections.ArrayList
$kept = New-Object System.Collections.ArrayList

function Fail($msg) { Write-Host "`n$msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Done($msg) { [void]$removed.Add($msg); Write-Host "  removed: $msg" }
function YesNo($q) { $a = Read-Host "  $q [y/N]"; $a -match '^(y|yes)$' }
function Run($exe, $dir, [string[]]$a) {
    Push-Location $dir
    $prev = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $exe @a; if ($LASTEXITCODE) { throw "'$exe $($a -join ' ')' failed (exit $LASTEXITCODE)" } } finally { $ErrorActionPreference = $prev; Pop-Location }
}
function IsVencordSource($d) {
    try { (Test-Path (Join-Path $d "scripts\runInstaller.mjs")) -and ((Get-Content (Join-Path $d "package.json") -Raw | ConvertFrom-Json).name -eq "vencord") } catch { $false }
}
# a folder the installer created (marker file, or the default folder name), never one the user brought along
function IsOwned($d) { (Test-Path (Join-Path $d ".externalsoundboard-owned")) -or ((Split-Path $d -Leaf) -eq "Vencord-ExternalSoundboard") }
function Rebuild($c) {
    $mjs = Join-Path $c ".pnpm-tool\node_modules\pnpm\bin\pnpm.mjs"
    if (Test-Path $mjs) { Run node $c @($mjs, "build") }
    elseif (Get-Command pnpm -ErrorAction SilentlyContinue) { Run pnpm $c @("build") }
    else { Write-Host "  Run 'pnpm build' in $c so Vencord stops loading the plugin." -ForegroundColor Yellow }
}

# ---- what to remove
if (-not $Mode) {
    Write-Host "What do you want to remove?"
    Write-Host "  1) The plugin only                  (keeps Vencord / BetterDiscord)"
    Write-Host "  2) The plugin + Vencord             (un-patches Discord, deletes the Vencord copy the installer made)"
    Write-Host "  3) The plugin + BetterDiscord       (un-patches Discord)"
    Write-Host "  4) Everything"
    $Mode = @{ "1" = "plugin"; "2" = "vencord"; "3" = "betterdiscord"; "4" = "all" }[(Read-Host "  Your choice")]
    if (-not $Mode) { Write-Host "Nothing selected, nothing changed."; exit 0 }
}
if ($Mode -notin "plugin", "vencord", "betterdiscord", "all") { Fail "-Mode must be plugin, vencord, betterdiscord or all." }
$doVencord = $Mode -in "vencord", "all"
$doBD = $Mode -in "betterdiscord", "all"

if (Get-Process Discord, DiscordCanary, DiscordPTB -ErrorAction SilentlyContinue) { Fail "Quit Discord first (right-click its tray icon > Quit), then run this again." }
if (-not $Yes -and -not (YesNo "Remove ($Mode)?")) { Write-Host "Cancelled, nothing changed."; exit 0 }

$resDirs = @(foreach ($d in "Discord", "DiscordCanary", "DiscordPTB") {
    $p = Join-Path $env:LOCALAPPDATA $d
    if (Test-Path $p) { Get-ChildItem $p -Directory -Filter "app-*" | ForEach-Object { Join-Path $_.FullName "resources" } }
})
$checkouts = @(@($InstallDir) + ("Vencord", "Documents\Vencord", "Desktop\Vencord", "Downloads\Vencord", "source\repos\Vencord", "dev\Vencord" | ForEach-Object { Join-Path $HOME $_ }) |
    Where-Object { IsVencordSource $_ } | Select-Object -Unique)

# ---- 1. un-patch Discord first. Deleting Vencord's folder while Discord still loads it would break Discord.
if ($doVencord) {
    Step "Removing Vencord from Discord"
    foreach ($res in $resDirs) {
        $a = Join-Path $res "app.asar"; $o = Join-Path $res "_app.asar"
        # Vencord's patch is a tiny app.asar that requires its patcher, next to the renamed original _app.asar
        if ((Test-Path $a) -and (Test-Path $o) -and ((Get-Item $a).Length -lt 4096) -and ([Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($a)) -match "patcher\.js")) {
            Remove-Item $a -Force; Move-Item $o $a; Done "Vencord patch in $res"
        }
    }
}
if ($doBD) {
    Step "Removing BetterDiscord from Discord"
    foreach ($res in $resDirs) {
        $idx = Join-Path $res "app\index.js"; $bd = Join-Path $res "betterdiscord.app.asar"; $a = Join-Path $res "app.asar"
        if ((Test-Path $idx) -and (Test-Path $bd) -and ((Get-Content $idx -Raw) -match "BetterDiscord")) {
            Remove-Item (Join-Path $res "app") -Recurse -Force
            if (Test-Path $a) { Remove-Item $bd -Force } else { Move-Item $bd $a }
            Done "BetterDiscord patch in $res"
        }
    }
}

# ---- 2. the plugin itself
Step "Removing the ExternalSoundboard plugin"
foreach ($c in $checkouts) {
    $pl = Join-Path $c "src\userplugins\externalSoundboard"
    if (Test-Path $pl) { Remove-Item $pl -Recurse -Force; Done "plugin source in $c" }
}
$bdPlugins = Join-Path $env:APPDATA "BetterDiscord\plugins"
foreach ($f in "ExternalSoundboard.plugin.js", "ExternalSoundboard.config.json") {
    $p = Join-Path $bdPlugins $f
    if (Test-Path $p) { Remove-Item $p -Force; Done $p }
}
$vcSettings = Join-Path $env:APPDATA "Vencord\settings\settings.json"
if ((Test-Path $vcSettings) -and (Get-Command node -ErrorAction SilentlyContinue)) {
    # drop only this plugin's saved settings, leave the rest of the file as is
    $js = "const fs=require('fs'),f=process.argv[1],j=JSON.parse(fs.readFileSync(f,'utf8'));if(j.plugins&&j.plugins.ExternalSoundboard){delete j.plugins.ExternalSoundboard;fs.writeFileSync(f,JSON.stringify(j,null,4));console.log('removed')}"
    if ((& node -e $js $vcSettings) -eq "removed") { Done "plugin settings in $vcSettings" }
}

# ---- 3. Vencord copies: delete ours, rebuild the others so they stop loading the plugin
foreach ($c in $checkouts) {
    if ($doVencord -and (IsOwned $c)) { Remove-Item $c -Recurse -Force; Done "Vencord copy $c" }
    elseif (Test-Path (Join-Path $c "dist\patcher.js")) { Step "Rebuilding Vencord in $c"; Rebuild $c }
    if ($doVencord -and -not (IsOwned $c)) { [void]$kept.Add("$c (your own Vencord folder)") }
}

# ---- 4. optional: settings, themes and your other plugins
if ($doVencord -and (Test-Path (Join-Path $env:APPDATA "Vencord"))) {
    if ($DeleteData -or (-not $Yes -and (YesNo "Also delete your Vencord settings and themes ($env:APPDATA\Vencord)?"))) { Remove-Item (Join-Path $env:APPDATA "Vencord") -Recurse -Force; Done "$env:APPDATA\Vencord" }
    else { [void]$kept.Add("$env:APPDATA\Vencord (settings, themes)") }
}
if ($doBD -and (Test-Path (Join-Path $env:APPDATA "BetterDiscord"))) {
    if ($DeleteData -or (-not $Yes -and (YesNo "Also delete BetterDiscord's folder, with your other plugins and themes ($env:APPDATA\BetterDiscord)?"))) { Remove-Item (Join-Path $env:APPDATA "BetterDiscord") -Recurse -Force; Done "$env:APPDATA\BetterDiscord" }
    else { [void]$kept.Add("$env:APPDATA\BetterDiscord (other plugins, themes)") }
}

Write-Host "`nDone." -ForegroundColor Green
if (-not $removed.Count) { Write-Host "  Nothing to remove was found." }
if ($kept.Count) { Write-Host "  Left in place:"; $kept | ForEach-Object { Write-Host "    $_" } }
Write-Host "  Start Discord again."
