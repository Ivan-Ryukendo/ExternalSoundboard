#!/usr/bin/env bash
# ExternalSoundboard uninstaller (macOS and Linux).
# One line:
#   curl -fsSL https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main/uninstall.sh | bash
# Options (env vars): MODE=plugin|vencord  INSTALL_DIR=<path>  BRANCH=stable,canary,ptb  DELETE_DATA=1  YES=1
# Untested on macOS and Linux. BetterDiscord itself is removed with BetterDiscord's own installer (Uninstall).
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
    read -r -p "  Your choice: " c < /dev/tty || c=""
    case "$c" in 1) MODE=plugin;; 2) MODE=vencord;; *) echo "Nothing selected, nothing changed."; exit 0;; esac
fi
[ "$MODE" = plugin ] || [ "$MODE" = vencord ] || fail "MODE must be plugin or vencord."
pgrep -xi 'discord|discordcanary|discordptb' >/dev/null 2>&1 && fail "Quit Discord first, then run this again."
[ -n "${YES:-}" ] || yesno "Remove ($MODE)?" || { echo "Cancelled, nothing changed."; exit 0; }

checkouts=()
for c in "$INSTALL_DIR" "$HOME/Vencord" "$HOME/Documents/Vencord" "$HOME/Desktop/Vencord" "$HOME/Downloads/Vencord" "$HOME/dev/Vencord"; do
    is_vencord_src "$c" && [[ " ${checkouts[*]-} " != *" $c "* ]] && checkouts+=("$c")
done

# 1. un-patch Discord first: deleting Vencord's folder while Discord still loads it would break Discord
if [ "$MODE" = vencord ]; then
    step "Removing Vencord from Discord"
    [ "${#checkouts[@]}" -gt 0 ] || fail "No Vencord source folder found, so Discord can't be un-patched from here. Set INSTALL_DIR=<folder>."
    if [ -z "${BRANCH:-}" ]; then
        read -r -p "  Which Discord? stable, canary, ptb (comma separated): " BRANCH < /dev/tty || BRANCH=""
    fi
    for b in ${BRANCH//,/ }; do (cd "${checkouts[0]}" && node scripts/runInstaller.mjs -- -uninstall -branch "$b"); removed+=("Vencord patch ($b)"); done
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
    if [ "$MODE" = vencord ] && is_owned "$c"; then rm -rf "$c"; removed+=("Vencord copy $c")
    elif [ -f "$c/dist/patcher.js" ]; then echo "  Rebuild $c (pnpm build) so Vencord stops loading the plugin."; fi
done

if [ "$MODE" = vencord ] && [ -d "$cfg/Vencord" ]; then
    if [ -n "${DELETE_DATA:-}" ] || { [ -z "${YES:-}" ] && yesno "Also delete your Vencord settings and themes ($cfg/Vencord)?"; }; then rm -rf "$cfg/Vencord"; removed+=("$cfg/Vencord"); fi
fi

printf '\n\033[32mDone.\033[0m\n'
[ "${#removed[@]}" -gt 0 ] && printf '  removed: %s\n' "${removed[@]}" || echo "  Nothing to remove was found."
echo "  To remove BetterDiscord itself, run BetterDiscord's installer and choose Uninstall."
echo "  Start Discord again."
