# Audio setup (loopback device)

The plugin sends a sound out as microphone input, so it needs an **input** that records an **output**. Pick one option for your OS.

## Which option should I use?

| Option | OS | Cost | Pros | Cons |
|---|---|---|---|---|
| **Stereo Mix** | Windows | Free, built in | Nothing to install. Quickest way to try the plugin. | Often hidden by the driver. **Records everything your speakers play**, so a video, music or other people's voices leak into what your friends hear. Discord's own output must be on a different device. |
| **VB-Cable** | Windows | Free ([donationware](https://vb-audio.com/Cable/)) | **Only the soundboard goes in, so no background leaks.** Works on every PC. Auto-detected by the plugin. | Needs a driver install and a reboot. You won't hear the sound yourself unless you enable *Listen to this device* (steps below). |
| **BlackHole 2ch** | macOS | Free, open source | Same isolation as VB-Cable: only the soundboard goes in. | Needs an install and a restart. You also have to create a Multi-Output Device so you can hear the sound. |
| **Monitor source** | Linux | Free, built in | No install. A dedicated null sink (below) isolates the sound. | Manual commands. They do not survive a reboot unless you add them to your audio config. |

**Recommendation:** use Stereo Mix to try it out, and move to VB-Cable (Windows) or BlackHole (macOS) if friends hear your video or music. macOS has no built-in Stereo Mix, so BlackHole is the way there. Rogue Amoeba's [Loopback](https://rogueamoeba.com/loopback/) is a paid alternative.

## In the plugin settings

- **Loopback input**: the recording device (auto-detected for Stereo Mix, BlackHole, CABLE Output, "Monitor of ...").
- **Playback output**: the output that device records. Auto-detected on Windows and for BlackHole/VB-Cable; set it by hand on Linux and for the macOS Multi-Output Device.
- **Your microphone**: restored after each sound.

## Windows

**Option A: Stereo Mix**
1. Open Sound settings > More sound settings > **Recording** tab.
2. Right-click empty space > **Show Disabled Devices**.
3. Right-click **Stereo Mix** > **Enable**, and check its volume is not 0.
4. If it is not listed, your driver hides it; use VB-Cable.
5. In Discord, keep *Output Device* (Settings > Voice & Video) on a different device than the one Stereo Mix records, or friends hear themselves.

**Option B: VB-Cable (recommended)**
1. Download VB-Audio Virtual Cable from [vb-audio.com/Cable](https://vb-audio.com/Cable/), extract it, run the setup as administrator, then reboot.
2. Loopback input = `CABLE Output`; playback output = `CABLE Input` (auto-paired).
3. To hear the sound yourself: Sound settings > More sound settings > **Recording** tab > `CABLE Output` > Properties > **Listen** > tick *Listen to this device* and pick your speakers or headphones.

## macOS (untested)

Based on the [BlackHole docs](https://github.com/ExistentialAudio/BlackHole/wiki/Multi-Output-Device).

1. Install BlackHole 2ch: `brew install blackhole-2ch`, or use the installer from the project page. Restart when asked.
2. Open **Audio MIDI Setup**, click **+** > **Create Multi-Output Device**, and tick your speakers or headphones **first** (it is the clock source), then **BlackHole 2ch**.
3. Tick **Drift Correction** for every device except the first one.
4. In the plugin: loopback input = `BlackHole 2ch`, playback output = the Multi-Output Device you made.
5. Leave your Mac's normal sound output on your usual device, not on the Multi-Output Device, or everything you play goes into your voice.
6. Allow microphone access for Discord when macOS asks.

## Linux (untested)

PulseAudio and PipeWire give every output a "monitor" input, shown as **Monitor of ...**. That works like Stereo Mix and has the same leak. A dedicated sink avoids it. These commands are built from the [PulseAudio module docs](https://wiki.freedesktop.org/Software/PulseAudio/Documentation/User/Modules/) and have not been run on a real machine yet:

```
pactl load-module module-null-sink sink_name=sb sink_properties=device.description=SB
pactl load-module module-loopback source=sb.monitor    # lets you hear it too
```

Then set loopback input = `Monitor of SB` and playback output = `SB`, and restart Discord so it sees the new devices. The commands do not survive a reboot. To keep them, add the same lines to your PulseAudio config (`default.pa`), or on PipeWire use a [loopback module config](https://docs.pipewire.org/page_module_loopback.html).

Not confirmed: whether Discord on your distro lists "Monitor of ..." devices in its input list. If it does not, tell us in an issue.

## Android and iOS

Not supported. Neither Vencord nor BetterDiscord runs on the official mobile apps, and the mobile apps cannot be pointed at a loopback input.
