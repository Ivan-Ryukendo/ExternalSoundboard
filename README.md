# ExternalSoundboard

Play soundboard sounds from **other servers** in a voice call **without Nitro**, and have everyone in the call actually hear them. Available as a **Vencord** userplugin and as a **BetterDiscord** plugin, with the same logic.

> **Risk:** this works around a paid Discord feature. Client mods already go against Discord's Terms of Service, and this goes a step further. Use it at your own risk; your account could be actioned.

## How it works

Discord's server rejects cross-server sounds without Nitro (HTTP 403, code 20015), so a client patch alone only unlocks the button and plays the sound on your side. Nobody else hears it. The plugin instead sends the sound out as microphone input:

1. Unlocks the button for locked sounds and intercepts the click.
2. Downloads the sound from Discord's public CDN into memory (nothing is written to disk).
3. Switches Discord's input to a **loopback device** that records your speakers.
4. Plays the sound to the matching output, so the loopback device picks it up and Discord sends it as your voice.
5. Switches the input back to your microphone (and re-mutes you if you were muted).

Because step 3 needs a loopback device, **you must set one up on your OS**. See [docs/audio-setup.md](docs/audio-setup.md).

## Platform support

| Platform | Vencord | BetterDiscord | Loopback device |
|---|---|---|---|
| Windows | **Tested** (Discord Canary, Stereo Mix) | Not tested | Stereo Mix or VB-Cable |
| macOS | Not tested | Not tested | BlackHole + Multi-Output Device |
| Linux | Not tested | Not tested | PulseAudio/PipeWire monitor |
| Android / iOS | Not supported | Not supported | n/a |

"Not tested" means the code is the same and should work, but nobody has confirmed it. Reports and fixes are welcome as issues.

## Install

1. Set up a loopback device: [docs/audio-setup.md](docs/audio-setup.md)
2. Install the plugin:
   - Vencord: [docs/install-vencord.md](docs/install-vencord.md)
   - BetterDiscord: [docs/install-betterdiscord.md](docs/install-betterdiscord.md)
3. Open the plugin settings and check that the loopback input, microphone, and playback output are right.

## Repository layout

```
ExternalSoundboard/
├── README.md
├── LICENSE                                   GPL-3.0
├── docs/
│   ├── audio-setup.md                        loopback device per OS
│   ├── install-vencord.md
│   └── install-betterdiscord.md
├── vencord/externalSoundboard/               copy into Vencord's src/userplugins
│   ├── index.tsx                             patches, download, device switching, playback
│   └── settings.tsx                          dropdown settings
└── betterdiscord/ExternalSoundboard.plugin.js   single-file BetterDiscord plugin
```

## Known limits

- Everything playing on the recorded output goes out as your voice. Keep Discord's own output on a different device, or friends hear themselves.
- Push-to-talk will not transmit the sound unless the key is held.
- Noise suppression may cut or dull the sound.
- One sound at a time; clicks during playback are ignored.
- You cannot play a sound while deafened.
- The patches depend on Discord's internals and can break when Discord updates.
