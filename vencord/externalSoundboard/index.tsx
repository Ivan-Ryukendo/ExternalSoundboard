import definePlugin from "@utils/types";
import { ChannelStore, FluxDispatcher, MediaEngineStore, UserStore } from "@webpack/common";

import { settings } from "./settings";

const NITRO_REQUIRED = 20015;
// Stereo Mix (Windows), BlackHole / VB-Cable (macOS, Windows), "Monitor of ..." (Linux PulseAudio/PipeWire)
const LOOPBACK_NAME = /stereo mix|what u hear|loopback|blackhole|cable output|monitor of/i;
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const setInput = (id: string) => FluxDispatcher.dispatch({ type: "AUDIO_SET_INPUT_DEVICE", id, oldId: MediaEngineStore.getInputDeviceId() } as any);

const TAIL_MS = 150;
const toggleMute = () => FluxDispatcher.dispatch({ type: "AUDIO_TOGGLE_SELF_MUTE", context: "default", syncRemote: true, playSoundEffect: false } as any);

// Diagnostic: records the loopback device while the sound plays and reports its peak level (0 = it hears nothing)
async function probeLevel(label: string) {
    const dev = (await navigator.mediaDevices.enumerateDevices()).find(d => d.kind === "audioinput" && d.label === label);
    if (!dev) return null;
    const stream = await navigator.mediaDevices.getUserMedia({ audio: { deviceId: { exact: dev.deviceId }, echoCancellation: false, noiseSuppression: false, autoGainControl: false } });
    const actx = new AudioContext();
    const analyser = actx.createAnalyser();
    actx.createMediaStreamSource(stream).connect(analyser);
    const buf = new Float32Array(analyser.fftSize);
    let peak = 0;
    const timer = setInterval(() => {
        analyser.getFloatTimeDomainData(buf);
        for (const v of buf) peak = Math.max(peak, Math.abs(v));
    }, 40);
    return () => {
        clearInterval(timer);
        stream.getTracks().forEach(t => t.stop());
        actx.close();
        return peak;
    };
}

let busy = false;

export default definePlugin({
    name: "ExternalSoundboard",
    description: "Plays other-server soundboard sounds into your voice chat via Stereo Mix when Discord refuses without Nitro",
    authors: [{ name: "Ivan-Ryukendo", id: 0n }],
    settings,

    intercept(sound: { soundId: string; guildId: string; }, channelId: string) {
        try {
            const nitro = [1, 2].includes(UserStore.getCurrentUser().premiumType ?? 0);
            if (nitro || sound.guildId === "0" || sound.guildId === ChannelStore.getChannel(channelId)?.guild_id) return false;
            this.playViaLoopback(sound.soundId);
            return true;
        } catch {
            return false;
        }
    },

    onSendFail(err: any, body: { sound_id: string; }) {
        console.warn("[ExternalSoundboard] send failed:", err?.status, JSON.stringify(err?.body ?? err?.message ?? err));
        if (err?.body?.code === NITRO_REQUIRED) this.playViaLoopback(body.sound_id);
    },

    async playViaLoopback(soundId: string) {
        if (busy) return;
        // a deafened user can't be un-muted without un-deafening, and real soundboard refuses then too
        if (MediaEngineStore.isSelfDeaf()) return console.warn("[ExternalSoundboard] skipped: you are deafened");
        busy = true;
        const activeInput = MediaEngineStore.getInputDeviceId();
        const wasMuted = MediaEngineStore.isSelfMute();
        let unmuted = false;
        const ctx = new AudioContext();
        try {
            const { loopbackInput, micInput, playbackOutput, settleMs } = settings.store;
            const inputs = Object.values(MediaEngineStore.getInputDevices());
            const loopback = inputs.find(d => loopbackInput ? d.name === loopbackInput : LOOPBACK_NAME.test(d.name));
            const mic = micInput ? inputs.find(d => d.name === micInput)?.id ?? activeInput : activeInput;

            const outputs = (await navigator.mediaDevices.enumerateDevices())
                .filter(d => d.kind === "audiooutput" && d.deviceId !== "default" && d.deviceId !== "communications");
            // shortcut: pairs devices by the "(driver)" suffix in the name, upgrade if a driver names them differently
            const suffix = loopback?.name.includes("(") ? loopback.name.slice(loopback.name.indexOf("(")) : null;
            // same name = BlackHole, "CABLE Output" -> "CABLE Input" = VB-Cable; Linux and multi-output setups pick the output by hand
            const output = playbackOutput
                ? outputs.find(d => d.label === playbackOutput)
                : outputs.find(d => loopback && d.label === loopback.name)
                ?? outputs.find(d => loopback && d.label.startsWith(loopback.name.replace(/output/i, "Input")))
                ?? outputs.find(d => d.label.includes("Speakers") && suffix && d.label.endsWith(suffix))
                ?? outputs.find(d => suffix && d.label.endsWith(suffix))
                ?? outputs.find(d => d.label.includes("Speakers"));
            console.log("[ExternalSoundboard] start", JSON.stringify({ soundId, wasMuted, loopback: loopback?.name, output: output?.label, mic }));
            if (!loopback || !output) return console.warn("[ExternalSoundboard] device not found", { loopback: loopback?.name, output: output?.label });

            // no-store keeps the sound out of Chromium's disk cache; it only ever lives in memory
            const res = await fetch(`https://cdn.discordapp.com/soundboard-sounds/${soundId}`, { cache: "no-store" });
            if (!res.ok) return console.warn("[ExternalSoundboard] download failed", res.status);
            const src = ctx.createBufferSource();
            src.buffer = await ctx.decodeAudioData(await res.arrayBuffer());
            src.connect(ctx.destination);
            await (ctx as any).setSinkId(output.deviceId);
            await ctx.resume();
            console.log("[ExternalSoundboard] ready", JSON.stringify({ seconds: src.buffer.duration, ctx: ctx.state, sink: (ctx as any).sinkId }));

            setInput(loopback.id);
            await sleep(settleMs);
            const stopProbe = await probeLevel(loopback.name).catch(e => (console.warn("[ExternalSoundboard] probe failed", e), null));
            if (wasMuted) { toggleMute(); unmuted = true; }
            // the timeout keeps a stuck context from leaving you on Stereo Mix or muted-off forever
            let endedNormally = false;
            const ended = Promise.race([new Promise(r => src.onended = () => { endedNormally = true; r(null); }), sleep(src.buffer.duration * 1000 + 3000)]);
            src.start();
            await ended;
            console.log("[ExternalSoundboard] finished", JSON.stringify({ endedNormally, ctxTime: ctx.currentTime, ctx: ctx.state, loopbackPeak: stopProbe?.() }));
            await sleep(TAIL_MS);
            if (unmuted) { toggleMute(); unmuted = false; }
            await sleep(settleMs);
            setInput(mic);
        } catch (e) {
            console.warn("[ExternalSoundboard] playback failed", e);
            setInput(activeInput);
        } finally {
            if (unmuted) toggleMute();
            ctx.close();
            busy = false;
        }
    },

    patches: [
        {
            find: "canUseCustomStickersEverywhere:",
            replacement: {
                match: /canUseSoundboardEverywhere:/,
                replace: "$&()=>true,_$&"
            }
        },
        {
            find: "SEND_SOUNDBOARD_SOUND(",
            replacement: [
                // Skip Discord's own play and request for sounds we handle ourselves (no double playback, no 403 wait)
                {
                    match: /(function \i\((\i),(\i),\i,\i\)\{)(?=\(0,\i\.\i\)\(\3,\2\),function\(\i,\i,\i,\i,\i\)\{let \i=null!=\i\.emojiId)/,
                    replace: "$1if($self.intercept($2,$3))return;"
                },
                // Fallback if the server still refuses
                {
                    match: /(SEND_SOUNDBOARD_SOUND\(\i\),body:(\i).{0,150}?\.then\(\i\.\i,)\(\)=>\{/,
                    replace: "$1__err=>{$self.onSendFail(__err,$2);"
                }
            ]
        }
    ]
});
