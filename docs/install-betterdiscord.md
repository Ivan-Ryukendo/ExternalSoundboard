# Install with BetterDiscord

**Status: tested on Windows only.** The BetterDiscord version is a port of the Vencord plugin. It finds Discord's internals through BetterDiscord's webpack API instead of build-time patches, so a hook can come up missing after a Discord update. The plugin logs which hooks it attached and shows an error toast if the basics are missing.

1. Install [BetterDiscord](https://betterdiscord.app) (Windows, macOS and Linux desktop only).
2. Copy `betterdiscord/ExternalSoundboard.plugin.js` into the plugins folder:
   - Windows: `%AppData%\BetterDiscord\plugins`
   - macOS: `~/Library/Application Support/BetterDiscord/plugins`
   - Linux: `~/.config/BetterDiscord/plugins`
   (or in Discord: Settings > BetterDiscord > Plugins > *Open Plugins Folder*)
3. Enable **ExternalSoundboard** in Settings > BetterDiscord > Plugins.
4. Set up the loopback device ([audio-setup.md](audio-setup.md)) and open the plugin's settings to check the devices.

## Checking it works

Open DevTools (Ctrl+Shift+I, or Cmd+Option+I on macOS) > Console and filter for `ExternalSoundboard`. On enable you should see `started` with three flags:

- `nitroPatch`: locked sounds are clickable.
- `interceptPatch`: Discord's own play and request are skipped for sounds we handle.
- `httpFallback`: we catch a 403 / 20015 reply and play the sound ourselves.

`nitroPatch` must be true. `interceptPatch` or `httpFallback` must be true for sounds to be sent. If `interceptPatch` is false you may hear the sound twice; please open an issue with the console output.

Then join a call with a second account and click a sound from another server. The log shows `start`, `ready`, `finished`, with a `loopbackPeak` above 0 when the loopback device heard the sound.
