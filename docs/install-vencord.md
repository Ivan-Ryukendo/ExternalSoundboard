# Install with Vencord (manual)

The one-command installers in the [README](../README.md#vencord-one-command) do all of this for you. Use this page if you want to do it by hand.

Custom plugins need Vencord **built from source**; the prebuilt installer cannot load them. Works the same on Windows, macOS and Linux. You need [Git](https://git-scm.com), [Node.js](https://nodejs.org) 18+ and [pnpm](https://pnpm.io).

```
git clone https://github.com/Vendicated/Vencord.git
git clone https://github.com/Ivan-Ryukendo/ExternalSoundboard.git
cd Vencord
pnpm install --frozen-lockfile
```

1. Copy `ExternalSoundboard/vencord/externalSoundboard` into `Vencord/src/userplugins/` (create the folder if needed).
2. Build and inject, then pick your Discord install in the installer:
   ```
   pnpm build
   pnpm inject
   ```
3. Fully quit and restart Discord, then enable **ExternalSoundboard** in Settings > Vencord > Plugins.
4. Set up the loopback device ([audio-setup.md](audio-setup.md)) and check the plugin settings.

After changing or updating the plugin, run `pnpm build` again and restart Discord. To remove Vencord, run `pnpm uninject`.

Notes:
- **Vesktop:** point Vesktop's *Vencord location* setting at your built `dist` folder.
- **Browser extension / web:** untested. Build with `pnpm buildWeb`.
- The plugin was written and tested against the Vencord version current in November 2026. If a patch fails after an update, the Vencord console logs "Patch by ExternalSoundboard had no effect"; open an issue.
