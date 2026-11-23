/**
 * @name ExternalSoundboard
 * @author Ivan-Ryukendo
 * @description Plays soundboard sounds from other servers into your voice chat without Nitro, by routing them through a loopback input (Stereo Mix, BlackHole, VB-Cable, a Linux monitor).
 * @version 0.1.0
 * @source https://github.com/Ivan-Ryukendo/ExternalSoundboard
 */

const NAME = "ExternalSoundboard";
const NITRO_REQUIRED = 20015;
const TAIL_MS = 150;
// Stereo Mix (Windows), BlackHole / VB-Cable (macOS, Windows), "Monitor of ..." (Linux PulseAudio/PipeWire)
const LOOPBACK_NAME = /stereo mix|what u hear|loopback|blackhole|cable output|monitor of/i;
const DEFAULTS = { loopbackInput: "", micInput: "", playbackOutput: "", settleMs: 400 };

const sleep = ms => new Promise(r => setTimeout(r, ms));
const log = (...a) => BdApi.Logger.info(NAME, ...a);
const warn = (...a) => BdApi.Logger.warn(NAME, ...a);

module.exports = class ExternalSoundboard {
    busy = false;

    start() {
        const { Webpack, Patcher } = BdApi;
        this.settings = Object.assign({}, DEFAULTS, BdApi.Data.load(NAME, "settings"));
        this.Media = Webpack.getStore("MediaEngineStore");
        this.Users = Webpack.getStore("UserStore");
        this.Channels = Webpack.getStore("ChannelStore");
        this.Dispatcher = Webpack.getByKeys("dispatch", "subscribe", "unsubscribe");
        if (!this.Media || !this.Users || !this.Channels || !this.Dispatcher) {
            return BdApi.UI.showToast(`${NAME}: could not find Discord's internals, Discord may have changed`, { type: "error" });
        }

        // 1. make locked sounds clickable
        const premium = Webpack.getByKeys("canUseSoundboardEverywhere");
        if (premium) Patcher.instead(NAME, premium, "canUseSoundboardEverywhere", () => true);
        else warn("canUseSoundboardEverywhere not found, locked sounds stay locked");

        // 2. skip Discord's own play + request for sounds we handle (no double playback, no 403 wait)
        const [sendMod, sendKey] = Webpack.getWithKey(Webpack.Filters.byStrings("SEND_SOUNDBOARD_SOUND")) ?? [];
        if (sendMod) Patcher.instead(NAME, sendMod, sendKey, (_, args, orig) => this.intercept(args[0], args[1]) ? undefined : orig(...args));
        else warn("send-sound function not found, relying on the 403 fallback only");

        // 3. fallback: if the server still answers 403 / 20015, play it ourselves
        const http = Webpack.getByKeys("getAPIBaseURL", "post");
        if (http) {
            Patcher.instead(NAME, http, "post", (_, args, orig) => {
                const p = orig(...args);
                const req = args[0];
                if (typeof req?.url === "string" && req.url.includes("send-soundboard-sound") && p?.catch) {
                    p.catch(err => {
                        warn("send failed:", err?.status, JSON.stringify(err?.body ?? err?.message ?? err));
                        if (err?.body?.code === NITRO_REQUIRED) this.play(req.body?.sound_id);
                    });
                }
                return p;
            });
        } else warn("HTTP module not found, 403 fallback disabled");

        log("started", { nitroPatch: !!premium, interceptPatch: !!sendMod, httpFallback: !!http });
    }

    stop() {
        BdApi.Patcher.unpatchAll(NAME);
    }

    intercept(sound, channelId) {
        try {
            if (!sound?.soundId || typeof channelId !== "string") return false;
            const nitro = [1, 2].includes(this.Users.getCurrentUser().premiumType ?? 0);
            if (nitro || sound.guildId === "0" || sound.guildId === this.Channels.getChannel(channelId)?.guild_id) return false;
            this.play(sound.soundId);
            return true;
        } catch {
            return false;
        }
    }

    setInput(id) {
        this.Dispatcher.dispatch({ type: "AUDIO_SET_INPUT_DEVICE", id, oldId: this.Media.getInputDeviceId() });
    }

    toggleMute() {
        this.Dispatcher.dispatch({ type: "AUDIO_TOGGLE_SELF_MUTE", context: "default", syncRemote: true, playSoundEffect: false });
    }

    // Diagnostic: records the loopback device while the sound plays and reports its peak level (0 = it hears nothing)
    async probeLevel(label) {
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

    async play(soundId) {
        if (!soundId || this.busy) return;
        // a deafened user can't be un-muted without un-deafening, and the real soundboard refuses then too
        if (this.Media.isSelfDeaf()) return warn("skipped: you are deafened");
        this.busy = true;
        const activeInput = this.Media.getInputDeviceId();
        const wasMuted = this.Media.isSelfMute();
        let unmuted = false;
        const ctx = new AudioContext();
        try {
            const { loopbackInput, micInput, playbackOutput, settleMs } = this.settings;
            const inputs = Object.values(this.Media.getInputDevices());
            const loopback = inputs.find(d => loopbackInput ? d.name === loopbackInput : LOOPBACK_NAME.test(d.name));
            const mic = micInput ? inputs.find(d => d.name === micInput)?.id ?? activeInput : activeInput;

            const outputs = (await navigator.mediaDevices.enumerateDevices())
                .filter(d => d.kind === "audiooutput" && d.deviceId !== "default" && d.deviceId !== "communications");
            // Windows: pair "Stereo Mix (Realtek)" with "Speakers (Realtek)" by the "(driver)" suffix
            const suffix = loopback?.name.includes("(") ? loopback.name.slice(loopback.name.indexOf("(")) : null;
            // same name = BlackHole, "CABLE Output" -> "CABLE Input" = VB-Cable; Linux and multi-output setups pick the output by hand
            const output = playbackOutput
                ? outputs.find(d => d.label === playbackOutput)
                : outputs.find(d => loopback && d.label === loopback.name)
                ?? outputs.find(d => loopback && d.label.startsWith(loopback.name.replace(/output/i, "Input")))
                ?? outputs.find(d => d.label.includes("Speakers") && suffix && d.label.endsWith(suffix))
                ?? outputs.find(d => suffix && d.label.endsWith(suffix))
                ?? outputs.find(d => d.label.includes("Speakers"));
            log("start", { soundId, wasMuted, loopback: loopback?.name, output: output?.label, mic });
            if (!loopback || !output) return warn("device not found", { loopback: loopback?.name, output: output?.label });

            // no-store keeps the sound out of Chromium's disk cache; it only ever lives in memory
            const res = await fetch(`https://cdn.discordapp.com/soundboard-sounds/${soundId}`, { cache: "no-store" });
            if (!res.ok) return warn("download failed", res.status);
            const src = ctx.createBufferSource();
            src.buffer = await ctx.decodeAudioData(await res.arrayBuffer());
            src.connect(ctx.destination);
            await ctx.setSinkId(output.deviceId);
            await ctx.resume();
            log("ready", { seconds: src.buffer.duration, ctx: ctx.state, sink: ctx.sinkId });

            this.setInput(loopback.id);
            await sleep(settleMs);
            const stopProbe = await this.probeLevel(loopback.name).catch(e => (warn("probe failed", e), null));
            if (wasMuted) { this.toggleMute(); unmuted = true; }
            // the timeout keeps a stuck context from leaving you on the loopback input or unmuted forever
            let endedNormally = false;
            const ended = Promise.race([new Promise(r => src.onended = () => { endedNormally = true; r(); }), sleep(src.buffer.duration * 1000 + 3000)]);
            src.start();
            await ended;
            log("finished", { endedNormally, ctxTime: ctx.currentTime, ctx: ctx.state, loopbackPeak: stopProbe?.() });
            await sleep(TAIL_MS);
            if (unmuted) { this.toggleMute(); unmuted = false; }
            await sleep(settleMs);
            this.setInput(mic);
        } catch (e) {
            warn("playback failed", e);
            this.setInput(activeInput);
        } finally {
            if (unmuted) this.toggleMute();
            ctx.close();
            this.busy = false;
        }
    }

    getSettingsPanel() {
        const root = document.createElement("div");
        root.style.cssText = "display:flex;flex-direction:column;gap:16px;color:var(--text-default,#dbdee1)";
        const save = (key, value) => {
            this.settings[key] = value;
            BdApi.Data.save(NAME, "settings", this.settings);
        };
        const field = (title, note, control) => {
            const box = document.createElement("div");
            box.innerHTML = `<div style="font-weight:600"></div><div style="opacity:.7;margin:2px 0 6px"></div>`;
            box.children[0].textContent = title;
            box.children[1].textContent = note;
            box.append(control);
            root.append(box);
            return control;
        };
        const style = "width:100%;padding:8px;border-radius:4px;border:0;background:var(--input-background-default,#1e1f22);color:inherit";
        const select = (key, autoLabel, names) => {
            const el = document.createElement("select");
            el.style.cssText = style;
            for (const [label, value] of [[autoLabel, ""], ...names.map(n => [n, n])]) el.add(new Option(label, value, false, value === this.settings[key]));
            el.onchange = () => save(key, el.value);
            return el;
        };
        const inputs = Object.values(this.Media.getInputDevices()).map(d => d.name);
        field("Loopback input", "The input that records your speakers (Stereo Mix, BlackHole, CABLE Output, Monitor of ...).", select("loopbackInput", "Auto-detect", inputs));
        field("Your microphone", "Switched back to this after each sound.", select("micInput", "Whatever mic was active", inputs));
        const out = field("Playback output", "The output the loopback input records. Keep Discord's own output on a different device, or friends hear an echo.", select("playbackOutput", "Auto-detect (matches loopback)", []));
        navigator.mediaDevices.enumerateDevices().then(devs => {
            for (const d of devs) if (d.kind === "audiooutput" && d.deviceId !== "default" && d.deviceId !== "communications") out.add(new Option(d.label, d.label, false, d.label === this.settings.playbackOutput));
        });
        const settle = field("Settle time (ms)", "Wait after switching the input device.", Object.assign(document.createElement("input"), { type: "number", value: this.settings.settleMs, min: 0 }));
        settle.style.cssText = style;
        settle.onchange = () => save("settleMs", Math.max(0, Number(settle.value) || DEFAULTS.settleMs));
        return root;
    }
};
