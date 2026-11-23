/**
 * @name ExternalSoundboard
 * @author Ivan-Ryukendo
 * @description Plays soundboard sounds from other servers into your voice chat without Nitro, by routing them through a loopback input (Stereo Mix, BlackHole, VB-Cable, a Linux monitor).
 * @version 0.2.0
 * @source https://github.com/Ivan-Ryukendo/ExternalSoundboard
 */

const NAME = "ExternalSoundboard";
const NITRO_REQUIRED = 20015;
const TAIL_MS = 150;
// Stereo Mix (Windows), BlackHole / VB-Cable (macOS, Windows), "Monitor of ..." (Linux PulseAudio/PipeWire)
const LOOPBACK_NAME = /stereo mix|what u hear|loopback|blackhole|cable output|monitor of/i;
const DEFAULTS = { loopbackInput: "", micInput: "", playbackOutput: "", settleMs: 400, bypassVoiceProcessing: true };

const sleep = ms => new Promise(r => setTimeout(r, ms));
// BetterDiscord prints objects as [object Object], so stringify them
const fmt = a => a.map(x => typeof x === "string" ? x : x instanceof Error ? x.stack : JSON.stringify(x));
const log = (...a) => BdApi.Logger.info(NAME, ...fmt(a));
const warn = (...a) => BdApi.Logger.warn(NAME, ...fmt(a));

module.exports = class ExternalSoundboard {
    busy = false;
    relocked = new Set();
    unavailableIds = new Set();

    start() {
        const { Webpack, Patcher } = BdApi;
        this.settings = Object.assign({}, DEFAULTS, BdApi.Data.load(NAME, "settings"));
        this.Media = Webpack.getStore("MediaEngineStore");
        this.Users = Webpack.getStore("UserStore");
        this.Channels = Webpack.getStore("ChannelStore");
        // the dispatcher is an export of a larger module, so getByKeys misses it; _actionHandlers tells it apart from look-alikes
        this.Dispatcher = Webpack.getModule(m => m && typeof m.dispatch === "function" && typeof m.subscribe === "function" && "_actionHandlers" in m, { searchExports: true });
        const missing = Object.entries({ MediaEngineStore: this.Media, UserStore: this.Users, ChannelStore: this.Channels, FluxDispatcher: this.Dispatcher }).filter(([, v]) => !v).map(([k]) => k);
        if (missing.length) {
            warn("could not find", missing.join(", "));
            return BdApi.UI.showToast(`${NAME}: could not find ${missing.join(", ")}, Discord may have changed`, { type: "error" });
        }
        this.refreshOutputs();
        this.restoreVoice(); // repairs voice settings if Discord closed mid-sound last time

        // 1. make locked sounds clickable
        // Discord freezes this object, so Patcher can't touch it; swap the module export that holds it for an unlocked copy instead
        const premium = Webpack.getByKeys("canUseSoundboardEverywhere");
        const premMod = premium && Webpack.getModule(m => m === premium, { searchExports: true, raw: true });
        const premKey = premMod && Object.keys(premMod.exports).find(k => premMod.exports[k] === premium);
        if (premKey) {
            const original = Object.getOwnPropertyDescriptor(premMod.exports, premKey);
            // The picker also greys out other servers (lock icons, "Get Nitro" bar) via isPremium(user, TIER_2). That check is used all over
            // Discord, so only answer "yes" when the caller is the sound picker's own module (found by a string that only it contains).
            const pickerId = Webpack.getModule(Webpack.Filters.bySource("lockedCustomSoundCount"), { raw: true })?.id;
            const inPicker = () => pickerId != null && new Error().stack.includes(`${pickerId}.js`);
            const unlocked = {
                ...premium,
                canUseSoundboardEverywhere: () => true,
                isPremium: (user, tier, ...rest) => (tier === 2 && inPicker()) || premium.isPremium(user, tier, ...rest)
            };
            Object.defineProperty(premMod.exports, premKey, { ...original, get: () => unlocked });
            this.restorePremium = () => Object.defineProperty(premMod.exports, premKey, original);
        } else warn("canUseSoundboardEverywhere not found, locked sounds stay locked");

        // 1b. sounds past their server's boost slots are flagged unavailable (a lock "Requires higher Server Boost Level"), but the CDN still serves them
        const Sounds = Webpack.getStore("SoundboardStore");
        if (Sounds) {
            const unlock = s => { if (s && s.available === false && s.guildId !== "0") { s.available = true; this.relocked.add(s); this.unavailableIds.add(s.soundId); } };
            Patcher.after(NAME, Sounds, "getSoundById", (_, __, ret) => { unlock(ret); });
            Patcher.after(NAME, Sounds, "getSoundsForGuild", (_, __, ret) => { ret?.forEach?.(unlock); });
            Patcher.after(NAME, Sounds, "getSounds", (_, __, ret) => { ret?.forEach?.(list => list?.forEach?.(unlock)); });
            Sounds.getSounds().forEach(list => list.forEach(unlock));
            Sounds.emitChange?.();
        } else warn("SoundboardStore not found, boost-locked sounds stay locked");

        // 2. skip Discord's own play + request for sounds we handle (no double playback, no 403 wait)
        const [sendMod, sendKey] = Webpack.getWithKey(Webpack.Filters.byStrings("SEND_SOUNDBOARD_SOUND")) ?? [];
        if (sendMod) Patcher.instead(NAME, sendMod, sendKey, (_, args, orig) => this.intercept(args[0], args[1]) ? undefined : orig(...args));
        else warn("send-sound function not found, relying on the 403 fallback only");

        // 3. fallback: if the server still answers 403 / 20015, play it ourselves
        const http = Webpack.getByKeys("getXHR", "post");
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

        log("started", { nitroPatch: !!premKey, interceptPatch: !!sendMod, httpFallback: !!http });
    }

    stop() {
        BdApi.Patcher.unpatchAll(NAME);
        this.restoreVoice();
        this.restorePremium?.();
        this.restorePremium = null;
        this.relocked.forEach(s => { s.available = false; });
        this.relocked.clear();
        this.unavailableIds.clear();
        BdApi.Webpack.getStore("SoundboardStore")?.emitChange?.();
    }

    intercept(sound, channelId) {
        try {
            if (!sound?.soundId || typeof channelId !== "string") return false;
            const nitro = [1, 2].includes(this.Users.getCurrentUser().premiumType ?? 0);
            const own = sound.guildId === this.Channels.getChannel(channelId)?.guild_id;
            // a sound Discord flagged unavailable (server out of boost slots) is refused by the server even for its own members and Nitro users
            if (sound.guildId === "0" || (!this.unavailableIds.has(sound.soundId) && (nitro || own))) return false;
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

    // Krisp noise cancellation, echo cancellation, auto gain and the speech-detecting mic gate treat a sound effect as noise and
    // cut or stutter it. Apply a target set of voice settings, touching only what differs so the voice engine isn't restarted for nothing.
    setVoice(t) {
        const M = this.Media, d = a => this.Dispatcher.dispatch({ ...a, location: NAME });
        if (t.nc !== M.getNoiseCancellation()) d({ type: "AUDIO_SET_NOISE_CANCELLATION", enabled: t.nc });
        if (t.ns !== M.getNoiseSuppression()) d({ type: "AUDIO_SET_NOISE_SUPPRESSION", enabled: t.ns });
        if (t.ec !== M.getEchoCancellation()) d({ type: "AUDIO_SET_ECHO_CANCELLATION", enabled: t.ec });
        if (t.agc !== M.getAutomaticGainControl()) d({ type: "AUDIO_SET_AUTOMATIC_GAIN_CONTROL", enabled: t.agc });
        if (t.mode !== M.getMode() || JSON.stringify(t.options) !== JSON.stringify(M.getModeOptions())) {
            this.Dispatcher.dispatch({ type: "AUDIO_SET_MODE", context: "default", mode: t.mode, options: t.options });
        }
    }

    bypassVoice() {
        const M = this.Media;
        const saved = { nc: M.getNoiseCancellation(), ns: M.getNoiseSuppression(), ec: M.getEchoCancellation(), agc: M.getAutomaticGainControl(), mode: M.getMode(), options: M.getModeOptions() };
        // saved to disk first: if Discord dies mid-sound, start() puts the settings back
        BdApi.Data.save(NAME, "voiceBackup", saved);
        // voice activity with the gate wide open also lets sounds through when you normally use push-to-talk
        this.setVoice({ nc: false, ns: false, ec: false, agc: false, mode: "VOICE_ACTIVITY", options: { ...saved.options, autoThreshold: false, threshold: -100, vadUseKrisp: false } });
    }

    restoreVoice() {
        const saved = BdApi.Data.load(NAME, "voiceBackup");
        if (!saved) return;
        this.setVoice(saved);
        BdApi.Data.delete(NAME, "voiceBackup");
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

            if (this.settings.bypassVoiceProcessing) this.bypassVoice();
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
            this.restoreVoice();
            ctx.close();
            this.busy = false;
        }
    }

    outputNames = [];

    async refreshOutputs() {
        const devs = await navigator.mediaDevices.enumerateDevices();
        this.outputNames = devs.filter(d => d.kind === "audiooutput" && d.deviceId !== "default" && d.deviceId !== "communications").map(d => d.label);
        return this.outputNames;
    }

    getSettingsPanel() {
        const { React, UI, Data } = BdApi;
        const Panel = () => {
            const [outputs, setOutputs] = React.useState(this.outputNames);
            React.useEffect(() => { this.refreshOutputs().then(setOutputs).catch(() => { }); }, []);
            const inputs = Object.values(this.Media.getInputDevices()).map(d => d.name);
            const list = (auto, names) => [{ label: auto, value: "" }, ...names.map(n => ({ label: n, value: n }))];
            return UI.buildSettingsPanel({
                onChange: (_, id, value) => {
                    this.settings[id] = id === "settleMs" ? Math.max(0, Number(value) || DEFAULTS.settleMs) : value;
                    Data.save(NAME, "settings", this.settings);
                },
                settings: [
                    { type: "dropdown", id: "loopbackInput", name: "Loopback input", note: "The input that records your speakers (Stereo Mix, BlackHole, CABLE Output, Monitor of ...).", value: this.settings.loopbackInput, options: list("Auto-detect", inputs) },
                    { type: "dropdown", id: "micInput", name: "Your microphone", note: "Switched back to this after each sound.", value: this.settings.micInput, options: list("Whatever mic was active", inputs) },
                    { type: "dropdown", id: "playbackOutput", name: "Playback output", note: "The output the loopback input records. Keep Discord's own output on a different device, or friends hear an echo.", value: this.settings.playbackOutput, options: list("Auto-detect (matches loopback)", outputs) },
                    { type: "switch", id: "bypassVoiceProcessing", name: "Bypass voice processing while a sound plays", note: "Turns off noise cancellation, echo cancellation, auto gain and the mic gate for the length of the sound, then puts them back. Fixes cut-off and stuttering sounds.", value: this.settings.bypassVoiceProcessing },
                    { type: "number", id: "settleMs", name: "Settle time (ms)", note: "Wait after switching the input device.", value: this.settings.settleMs, min: 0, step: 50 }
                ]
            });
        };
        return React.createElement(Panel);
    }
};
