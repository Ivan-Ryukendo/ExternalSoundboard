# Audio setup (loopback device)

The plugin needs an **input** that records an **output**. In the plugin settings:

- **Loopback input**: the recording device (auto-detected for Stereo Mix, BlackHole, CABLE Output, "Monitor of ...").
- **Playback output**: the output that device records. Auto-detected on Windows and for BlackHole/VB-Cable; set it by hand on Linux and for macOS Multi-Output.
- **Your microphone**: restored after each sound.

Keep **Discord's own output** (User Settings > Voice & Video) on a *different* device than the playback output when using Stereo Mix, otherwise friends' voices are recorded and sent back to them.

## Windows

**Option A: Stereo Mix (no install, may be missing)**
1. Open Sound settings > More sound settings > **Recording** tab.
2. Right-click empty space > **Show Disabled Devices**.
3. Right-click **Stereo Mix** > **Enable**, and check its volume is not 0.
4. If it is not listed, your driver hides it; use option B.

**Option B: VB-Cable (free virtual cable)**
1. Install VB-Audio Virtual Cable from vb-audio.com and reboot.
2. Loopback input = `CABLE Output`; playback output = `CABLE Input` (auto-paired).
3. To also hear the sound yourself: Recording tab > `CABLE Output` > Properties > Listen > tick *Listen to this device* and pick your speakers.

## macOS (untested)

1. Install BlackHole 2ch (`brew install blackhole-2ch`) and restart.
2. Audio MIDI Setup > **+** > Create Multi-Output Device, tick your speakers/headphones and **BlackHole 2ch**.
3. In the plugin: loopback input = `BlackHole 2ch`, playback output = the Multi-Output Device you made. Leave Discord's own output on your normal device.
4. Allow microphone access for Discord when macOS asks.

## Linux (untested)

PulseAudio and PipeWire expose a "monitor" of each output as an input named **Monitor of ...**. A dedicated sink avoids echo:

```
pactl load-module module-null-sink sink_name=sb sink_properties=device.description=SB
pactl load-module module-loopback source=sb.monitor   # lets you hear it too
```

Then set loopback input = `Monitor of SB` and playback output = `SB`. Restart Discord so it sees the new devices. These commands do not survive a reboot; add them to your session startup to keep them.

## Android and iOS

Not supported. Neither Vencord nor BetterDiscord runs on the official mobile apps, and the mobile apps cannot be pointed at a loopback input.
