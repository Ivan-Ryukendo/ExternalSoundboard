#!/usr/bin/env bash
# ExternalSoundboard uninstaller (macOS and Linux).
# One line:
#   curl -fsSL https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main/uninstall.sh | bash
# Options (env vars): MODE=plugin|vencord|betterdiscord|all  INSTALL_DIR=<path>  BRANCH=stable,canary,ptb  DELETE_DATA=1  YES=1
#   DISCORD_RESOURCES=<dir>[:<dir>]  extra Discord 'resources' folders to check for BetterDiscord
# Untested on macOS and Linux.
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/Vencord-ExternalSoundboard}"
MODE="${MODE:-}"
case "$(uname)" in Darwin) cfg="$HOME/Library/Application Support";; *) cfg="${XDG_CONFIG_HOME:-$HOME/.config}";; esac

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$1" >&2; exit 1; }
yesno() { local a; read -r -p "  $1 [y/N] " a < /dev/tty || a=""; [[ "$a" =~ ^[Yy] ]]; }
is_vencord_src() { [ -f "$1/scripts/runInstaller.mjs" ] && grep -q '"name": "vencord"' "$1/package.json" 2>/dev/null; }
is_owned() { [ -e "$1/.externalsoundboard-owned" ] || [ "$(basename "$1")" = "Vencord-ExternalSoundboard" ]; }
removed=()

if [ -z "$MODE" ]; then
    echo "What do you want to remove?"
    echo "  1) The plugin only             (keeps Vencord / BetterDiscord)"
    echo "  2) The plugin + Vencord        (un-patches Discord, deletes the Vencord copy the installer made)"
    echo "  3) The plugin + BetterDiscord  (un-patches Discord)"
    echo "  4) Everything"
    read -r -p "  Your choice: " c < /dev/tty || c=""
    case "$c" in 1) MODE=plugin;; 2) MODE=vencord;; 3) MODE=betterdiscord;; 4) MODE=all;; *) echo "Nothing selected, nothing changed."; exit 0;; esac
fi
case "$MODE" in plugin|vencord|betterdiscord|all) ;; *) fail "MODE must be plugin, vencord, betterdiscord or all.";; esac
do_vencord=""; do_bd=""
{ [ "$MODE" = vencord ] || [ "$MODE" = all ]; } && do_vencord=1
{ [ "$MODE" = betterdiscord ] || [ "$MODE" = all ]; } && do_bd=1
pgrep -xi 'discord|discordcanary|discordptb' >/dev/null 2>&1 && fail "Quit Discord first, then run this again."
[ -n "${YES:-}" ] || yesno "Remove ($MODE)?" || { echo "Cancelled, nothing changed."; exit 0; }

checkouts=()
for c in "$INSTALL_DIR" "$HOME/Vencord" "$HOME/Documents/Vencord" "$HOME/Desktop/Vencord" "$HOME/Downloads/Vencord" "$HOME/dev/Vencord"; do
    is_vencord_src "$c" && [[ " ${checkouts[*]-} " != *" $c "* ]] && checkouts+=("$c")
done

# 1. un-patch Discord first: deleting Vencord's folder while Discord still loads it would break Discord
if [ -n "$do_vencord" ]; then
    step "Removing Vencord from Discord"
    [ "${#checkouts[@]}" -gt 0 ] || fail "No Vencord source folder found, so Discord can't be un-patched from here. Set INSTALL_DIR=<folder>."
    if [ -z "${BRANCH:-}" ]; then
        read -r -p "  Which Discord? stable, canary, ptb (comma separated): " BRANCH < /dev/tty || BRANCH=""
    fi
    for b in ${BRANCH//,/ }; do (cd "${checkouts[0]}" && node scripts/runInstaller.mjs -- -uninstall -branch "$b"); removed+=("Vencord patch ($b)"); done
fi

if [ -n "$do_bd" ]; then
    step "Removing BetterDiscord from Discord"
    # BetterDiscord adds resources/app/index.js and renames Discord's app.asar to betterdiscord.app.asar
    cands=()
    IFS=: read -r -a extra <<< "${DISCORD_RESOURCES:-}"
    cands+=("${extra[@]-}")
    for d in "/Applications/Discord.app" "/Applications/Discord Canary.app" "/Applications/Discord PTB.app"; do cands+=("$d/Contents/Resources"); done
    for d in /opt/discord /opt/discord-canary /opt/discord-ptb /usr/share/discord /usr/share/discord-canary /usr/share/discord-ptb /usr/lib/discord /usr/lib/discord-canary /usr/lib/discord-ptb              /var/lib/flatpak/app/com.discordapp.Discord/current/active/files/discord "$HOME/.local/share/flatpak/app/com.discordapp.Discord/current/active/files/discord" /snap/discord/current/usr/share/discord; do cands+=("$d/resources"); done
    for res in "${cands[@]}"; do
        [ -n "$res" ] && [ -f "$res/app/index.js" ] && [ -f "$res/betterdiscord.app.asar" ] && grep -q BetterDiscord "$res/app/index.js" || continue
        { rm -rf "$res/app" && { if [ -e "$res/app.asar" ]; then rm -f "$res/betterdiscord.app.asar"; else mv "$res/betterdiscord.app.asar" "$res/app.asar"; fi; }; }             && removed+=("BetterDiscord patch in $res") || echo "  Could not change $res (permission denied?). Run this again with sudo." >&2
    done
fi

# 2. the plugin
step "Removing the ExternalSoundboard plugin"
for c in "${checkouts[@]}"; do
    [ -d "$c/src/userplugins/externalSoundboard" ] && { rm -rf "$c/src/userplugins/externalSoundboard"; removed+=("plugin source in $c"); }
done
for f in ExternalSoundboard.plugin.js ExternalSoundboard.config.json; do
    p="$cfg/BetterDiscord/plugins/$f"; [ -e "$p" ] && { rm -f "$p"; removed+=("$p"); }
done
vs="$cfg/Vencord/settings/settings.json"
if [ -f "$vs" ] && command -v node >/dev/null; then
    node -e "const fs=require('fs'),f=process.argv[1],j=JSON.parse(fs.readFileSync(f,'utf8'));if(j.plugins&&j.plugins.ExternalSoundboard){delete j.plugins.ExternalSoundboard;fs.writeFileSync(f,JSON.stringify(j,null,4))}" "$vs" && removed+=("plugin settings in $vs")
fi

# 3. Vencord copies: delete ours, tell the user to rebuild the others
for c in "${checkouts[@]}"; do
    if [ -n "$do_vencord" ] && is_owned "$c"; then rm -rf "$c"; removed+=("Vencord copy $c")
    elif [ -f "$c/dist/patcher.js" ]; then echo "  Rebuild $c (pnpm build) so Vencord stops loading the plugin."; fi
done

if [ -n "$do_vencord" ] && [ -d "$cfg/Vencord" ]; then
    if [ -n "${DELETE_DATA:-}" ] || { [ -z "${YES:-}" ] && yesno "Also delete your Vencord settings and themes ($cfg/Vencord)?"; }; then rm -rf "$cfg/Vencord"; removed+=("$cfg/Vencord"); fi
fi
if [ -n "$do_bd" ] && [ -d "$cfg/BetterDiscord" ]; then
    if [ -n "${DELETE_DATA:-}" ] || { [ -z "${YES:-}" ] && yesno "Also delete BetterDiscord's folder, with your other plugins and themes ($cfg/BetterDiscord)?"; }; then rm -rf "$cfg/BetterDiscord"; removed+=("$cfg/BetterDiscord"); fi
fi

printf '\n\033[32mDone.\033[0m\n'
[ "${#removed[@]}" -gt 0 ] && printf '  removed: %s\n' "${removed[@]}" || echo "  Nothing to remove was found."
echo "  Start Discord again."
