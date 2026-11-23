#!/usr/bin/env bash
# ExternalSoundboard installer for Vencord (macOS and Linux).
# One line:
#   curl -fsSL https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main/install.sh | bash
# Re-run it any time to update Vencord and the plugin.
# Options (env vars): INSTALL_DIR=<path>  BRANCH=stable,canary,ptb,auto  SKIP_INJECT=1
set -euo pipefail

INSTALL_DIR_SET="${INSTALL_DIR:-}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Vencord-ExternalSoundboard}"
BRANCH="${BRANCH:-}"
RAW="https://raw.githubusercontent.com/Ivan-Ryukendo/ExternalSoundboard/main"

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

step "Checking requirements"
missing=""
command -v git >/dev/null || missing+="  missing: Git     -> macOS: brew install git | Debian/Ubuntu: sudo apt install git\n"
node_major=0
command -v node >/dev/null && node_major=$(node --version | sed -E 's/^v([0-9]+).*/\1/')
[ "$node_major" -ge 22 ] || missing+="  missing: Node.js 22 or newer -> https://nodejs.org (or brew install node, or your distro's NodeSource/nvm)\n"
[ -z "$missing" ] || { printf '\033[33m%b\033[0m' "$missing"; fail "Install the above, open a NEW terminal, and run this installer again."; }
echo "  git and node $(node --version) found. pnpm is fetched automatically."

step "Getting Vencord"
# A Vencord source checkout you already have is reused as is (never re-cloned or pulled). The ready-made
# Vencord from vencord.dev has no source, so a custom plugin can't be added to it: we need a checkout.
is_vencord_src() { [ -f "$1/scripts/runInstaller.mjs" ] && grep -q '"name": "vencord"' "$1/package.json" 2>/dev/null; }
reused=""
if [ -z "${INSTALL_DIR_SET:-}" ] && [ ! -d "$INSTALL_DIR/.git" ]; then
    for c in "$HOME/Vencord" "$HOME/Documents/Vencord" "$HOME/Desktop/Vencord" "$HOME/Downloads/Vencord" "$HOME/dev/Vencord"; do
        if is_vencord_src "$c"; then INSTALL_DIR="$c"; reused=1; break; fi
    done
fi
changed=""
if [ -n "$reused" ]; then
    echo "  Using your existing Vencord source: $INSTALL_DIR (not re-downloaded)"
elif [ -d "$INSTALL_DIR/.git" ]; then
    before=$(git -C "$INSTALL_DIR" rev-parse HEAD)
    git -C "$INSTALL_DIR" pull --ff-only || echo "  could not update Vencord, building the version you have"
    [ "$(git -C "$INSTALL_DIR" rev-parse HEAD)" = "$before" ] || changed=1
    echo "  Vencord already downloaded, reusing it."
else
    git clone --depth 1 https://github.com/Vendicated/Vencord.git "$INSTALL_DIR"; changed=1
fi

step "Adding the ExternalSoundboard plugin"
dest="$INSTALL_DIR/src/userplugins/externalSoundboard"
mkdir -p "$dest"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
for f in index.tsx settings.tsx; do
    tmp="$(mktemp)"
    if [ -n "$here" ] && [ -f "$here/vencord/externalSoundboard/$f" ]; then cp "$here/vencord/externalSoundboard/$f" "$tmp"
    else curl -fsSL "$RAW/vencord/externalSoundboard/$f" -o "$tmp"; fi
    cmp -s "$tmp" "$dest/$f" || { changed=1; mv "$tmp" "$dest/$f"; }
    rm -f "$tmp"
done

cd "$INSTALL_DIR"
if [ -z "$changed" ] && [ -f dist/patcher.js ]; then
    printf '
[32mPlugin and Vencord are already up to date, no rebuild needed.[0m
'
else
    step "Building Vencord (a few minutes the first time)"
    # the repo pins its pnpm version. Install exactly that into a private folder and run its .mjs with node,
    # so no global pnpm is needed and broken launcher shims are avoided.
    pnpm_ver=$(node -p "require('$INSTALL_DIR/package.json').packageManager.replace(/^pnpm@/, '').replace(/\+.*/, '')")
    tool="$INSTALL_DIR/.pnpm-tool"
    pnpm_mjs="$tool/node_modules/pnpm/bin/pnpm.mjs"
    [ -f "$pnpm_mjs" ] || npm install --prefix "$tool" "pnpm@$pnpm_ver" --no-audit --no-fund --loglevel=error
    node "$pnpm_mjs" install --frozen-lockfile
    node "$pnpm_mjs" build
fi

[ -z "${SKIP_INJECT:-}" ] || { printf '\n\033[32mBuilt. Skipped injecting into Discord (SKIP_INJECT).\033[0m\n'; exit 0; }

step "Which Discord do you use?"
if [ -z "$BRANCH" ]; then
    echo "  1) Stable   2) Canary   3) PTB   4) Auto-detect"
    echo "  Several? Type numbers separated by commas, e.g. 1,2.  Enter = skip (inject later)."
    # read from the terminal, because stdin is the pipe when run through curl | bash
    read -r -p "  Your choice: " choice < /dev/tty || choice=""
    for n in ${choice//,/ }; do
        case "$n" in 1) BRANCH+="stable,";; 2) BRANCH+="canary,";; 3) BRANCH+="ptb,";; 4) BRANCH+="auto,";; esac
    done
    BRANCH="${BRANCH%,}"
fi
if [ -z "$BRANCH" ]; then
    echo "  Skipped. Later, run:  node scripts/runInstaller.mjs -- -install -branch <stable|canary|ptb>  in $INSTALL_DIR"
else
    printf '\033[33m  Close Discord first.\033[0m\n'
    for b in ${BRANCH//,/ }; do step "Injecting into Discord $b"; node scripts/runInstaller.mjs -- -install -branch "$b"; done
fi

printf '\n\033[32mDone.\033[0m\n'
echo "  1. Fully restart Discord."
echo "  2. Settings > Vencord > Plugins > enable ExternalSoundboard."
echo "  3. Set up your loopback device: https://github.com/Ivan-Ryukendo/ExternalSoundboard/blob/main/docs/audio-setup.md"
