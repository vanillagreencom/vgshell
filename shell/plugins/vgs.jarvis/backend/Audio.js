// One owner for capture, paced playback, heard-prefix reports and the sidecar feed.
// Speech consumers supply PCM sinks/sources. Audio never transcribes
// or changes a default device. Session admits half-duplex only.
// playbackSource(op) answers null or {readable, spoken}: spoken is true when
// the readable carries Jarvis's spoken words, which voice mute silences, and
// false for a conversation start/stop sound or a voice preview. A packet {pcm, tone: true} is
// a tone the engine pushes into a spoken source, the working sound, and
// stays audible; voice mute silences every other packet of a spoken source.
"use strict";
const cp = require("node:child_process");
const path = require("node:path");
const { Readable } = require("node:stream");

const PCM_RATE = 24000;
const SENTENCE_FRAMES = PCM_RATE * 30;
const BUFFER_BYTES = 64 * 1024;
const PLAYBACK_LEAD_MS = 60;
const NODE_LATENCY_MS = 20;
const PLAYBACK_QUEUE_BYTES = PCM_RATE * 2 * 30;
const TRANSCRIPT_BYTES = 64 * 1024;
const DISCOVERY_BYTES = 1024 * 1024;
const STREAM_PROPERTIES = JSON.stringify({ "node.dont-fallback": true, "node.dont-reconnect": true });

/**
 * The largest high-water mark a playback source may declare, in its own units:
 * bytes, or chunks in object mode. A Duplex shares the allowance across its two
 * queues. Producers that cannot pause their provider size their queue by it.
 */
function sourceLimit(objectMode, duplex) {
    const unit = objectMode ? BUFFER_BYTES : 1;
    return Math.floor((PLAYBACK_QUEUE_BYTES - (duplex ? 3 : 2) * BUFFER_BYTES) / unit / (duplex ? 2 : 1));
}

// The captured peak, of 32768, at or below which the microphone sent only
// silence: a muted or dead source sends zeros, and a live one's own noise
// passes it within seconds. A classification floor, about -60 dBFS, chosen
// by rule and not measured on a device.
const SILENT_PEAK = 32;
// A classification window, chosen in captured samples rather than elapsed
// time: a source that sends only digital silence for this window gets a hint.
const SILENT_FRAMES = PCM_RATE * 2;
// Cloud input uses a plain level rule, not a recognizer. The chosen floor
// aims to reject quiet room noise; 200 ms of captured hangover keeps endings.
// These are rule parameters, not measured noise or latency claims.
const CLOUD_SPEECH_PEAK = 512;
const CLOUD_HANGOVER_FRAMES = PCM_RATE / 5;
// Bound the gate's frame independently of pipe read coalescing under load.
const CLOUD_FRAME_BYTES = PCM_RATE * 2 / 50;

/** The largest sample magnitude of whole 16-bit little-endian PCM. */
function peak(pcm) {
    let most = 0;
    for (let i = 0; i + 1 < pcm.length; i += 2) most = Math.max(most, Math.abs(pcm.readInt16LE(i)));
    return most;
}

// What a monitor knows before a store names a default, and after the store
// is removed or replaced. UNSETTLED lists the groups a delta may have removed.
function noDefaults(id) {
    return { id, microphones: null, speakers: null, unsettled: [] };
}

function defaultStore(node) {
    return node.type === "PipeWire:Interface:Metadata" && Boolean(node.props) && node.props["metadata.name"] === "default";
}

// The defaults NODE, a default store, names: WirePlumber publishes the active
// ones on subject 0. pw-dump emits decoded JSON values.
// https://github.com/PipeWire/wireplumber/blob/master/src/scripts/default-nodes/apply-default-node.lua
function storeDefaults(node) {
    if (!Array.isArray(node.metadata) || node.metadata.length > 4096) throw new Error("discovery-default");
    const named = {};
    for (const entry of node.metadata) {
        if (entry.subject !== 0) continue;
        const group = entry.key === "default.audio.source" ? "microphones"
            : entry.key === "default.audio.sink" ? "speakers" : null;
        if (group === null) continue;
        const value = entry.value && entry.value.name;
        if (entry.type !== "Spa:String:JSON" || typeof value !== "string"
                || !/^[^\x00-\x1f\x7f]{1,200}$/.test(value))
            throw new Error("discovery-default");
        named[group] = value;
    }
    return named;
}

class Audio {
    constructor({ session, environment, clock, offers, level, fault, captureSink, playbackSource, input = () => {} }) {
        this.session = session;
        this.environment = {};
        for (const key of ["PATH", "HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME",
            "XDG_RUNTIME_DIR", "PIPEWIRE_RUNTIME_DIR", "PIPEWIRE_REMOTE", "LANG", "LC_ALL"])
            if (environment[key] !== undefined) this.environment[key] = environment[key];
        this.clock = clock;
        this.offers = offers;
        this.level = level;
        this.fault = fault;
        this.captureSink = captureSink;
        this.playbackSource = playbackSource;
        this.input = input;
        this.children = new Map();
        this.state = null;
        this.lifetime = { kind: "open" };
        this.devices = { microphones: [], speakers: [] };
        this.discovery = { kind: "idle", retries: 0 };
        this.nodes = new Map();
        // One record per full read in flight of what monitor deltas touched
        // during it: the object ids they named and whether the defaults moved.
        this.reads = new Set();
        this.defaults = noDefaults(null);
        this.capture = null;
        this.playback = null;
        this.feed = null;
        this.playbackFeed = null;
        this.lastPlayback = null;
        this.lastLevel = -Infinity;
        this.levels = { capture: 0, playback: 0 };
        this.release = Promise.resolve();
        this.capturePort = {
            open: (e, done, failed) => this.openCapture(e, done, failed),
            close: (e, done, failed) => {
                const capture = this.capture, feed = this.feed;
                const release = this.teardown("capture-close", ["capture"]);
                // The recorder stops independently of native turn completion.
                // This records audio sent/queued, never words recognized.
                let result = {};
                try {
                    if (capture?.gate !== null && capture?.gate !== undefined) {
                        this.finishCloudInput(capture, feed);
                        result = { speech: capture.gate.committed };
                    }
                } catch (error) { return release.then(() => failed(error)); }
                return release.then(() => done(result));
            }
        };
        this.playbackPort = {
            start: (e, done, failed) => this.startPlayback(e, done, failed),
            flush: (e, done) => {
                const release = this.teardown("interrupt", ["playback"]);
                const result = this.lastPlayback;
                return release.then(() => done(result !== null && result.gen === e.gen
                    && result.op === e.target ? result : null));
            }
        };
    }

    observe(state) { this.state = state; }

    allowed(kind) {
        const s = this.state;
        return this.lifetime.kind === "open" && s !== null
            && (kind === "playback" ? this.session.canPlayback(s) : this.session.canCapture(s));
    }

    async spawn(kind, command, args = []) {
        if (this.lifetime.kind === "closed" || (kind !== "discovery"
                && !this.allowed(kind === "playback" ? "playback" : "capture")))
            throw new Error("audio-start-refused");
        const child = cp.spawn("setpriv", ["--pdeathsig", "KILL", "--", "python3", "-I",
            path.join(__dirname, "audio-child.py"), "outer", String(process.pid), command, ...args], {
            env: this.environment, stdio: ["pipe", "pipe", "pipe", "pipe", "pipe"]
        });
        const owner = { child, kind, stopping: false, diagnostic: "", exit: null };
        this.children.set(child, owner);
        child.stdin.on("error", error => {
            if (!owner.stopping && error.code !== "EPIPE") this.fault("audio-write-" + error.code);
        });
        child.stdio[3].on("error", error => {
            if (!owner.stopping && error.code !== "EPIPE") this.fault("audio-lease-" + error.code);
        });
        child.stderr.on("data", data => {
            owner.diagnostic = (owner.diagnostic + data.toString("utf8")).slice(-4096);
        });
        // close includes pipe closure, not just the direct child's exit.
        const closed = new Promise(resolve => {
            child.once("error", error => { owner.diagnostic = "spawn-" + error.code; });
            child.once("close", (code, signal) => {
                owner.exit = { code, signal };
                this.children.delete(child);
                resolve();
            });
        });
        owner.closed = closed;
        child.stdio[3].write("S");
        const ready = new Promise((resolve, reject) => {
            child.stdio[4].once("error", reject);
            child.stdio[4].once("data", data => data.equals(Buffer.from("R"))
                ? resolve() : reject(new Error("audio-readiness")));
            closed.then(() => reject(new Error("audio-child: " + owner.diagnostic.trim())));
        });
        // A failed start stops only this child; its caller owns the rest.
        try { await ready; }
        catch (error) { await this.stop(owner); throw error; }
        if (owner.stopping || this.lifetime.kind === "closed") throw new Error("audio-ended");
        return owner;
    }

    // Read-only node discovery. node.name is the stable target accepted by
    // pw-cat; the transient object id is never saved as a setting.
    discover() {
        if (this.lifetime.kind === "closed") return Promise.reject(new Error("audio-start-refused"));
        const prior = this.discovery;
        switch (prior.kind) {
        case "starting":
        case "monitoring":
            return prior.ready;
        case "retiring":
            return prior.closed.then(() => this.discover());
        case "failed":
            return Promise.reject(prior.error);
        case "waiting":
            this.clock.clear(prior.timer);
            break;
        case "idle":
            break;
        default:
            throw new Error("discovery-state: " + prior.kind);
        }
        const discovery = { kind: "starting", retries: prior.retries, ready: null };
        this.discovery = discovery;
        discovery.ready = this.monitor(discovery);
        return discovery.ready;
    }

    retireDiscovery(discovery, error) {
        if (discovery.kind === "retiring" || this.discovery !== discovery || this.lifetime.kind === "closed") return;
        discovery.kind = "retiring";
        discovery.closed = this.teardown("discovery-failed", ["discovery"]).then(() => {
            if (this.lifetime.kind === "closed") return;
            // pw-dump's monitor ends when its PipeWire connection ends.
            // Bound reconnection over this Audio lifetime, including flapping.
            if (discovery.retries === 3) {
                const exhausted = new Error("discovery-recovery-exhausted: " + error.message);
                this.discovery = { kind: "failed", error: exhausted };
                this.fault(exhausted.message);
                return;
            }
            const waiting = { kind: "waiting", retries: discovery.retries + 1, timer: null };
            this.discovery = waiting;
            waiting.timer = this.clock.set(() => {
                if (this.lifetime.kind === "closed" || this.discovery !== waiting) return;
                void this.discover().catch(error => this.fault(error.message));
            }, 250 * Math.pow(2, discovery.retries));
        });
        this.devices = { microphones: [], speakers: [] };
        this.nodes.clear();
        this.defaults = noDefaults(null);
        this.offers(this.devices);
        this.failCapture("discovery-failed", error.message);
        this.fault(error.message);
    }

    async monitor(discovery) {
        let owner;
        try { owner = await this.spawn("discovery", "pw-dump", ["--monitor", "--no-colors"]); }
        catch (error) { this.retireDiscovery(discovery, error); throw error; }
        return new Promise((resolve, reject) => {
            let tail = "", size = 0, depth = 0, quoted = false, escaped = false, started = false;
            const { StringDecoder } = require("node:string_decoder");
            const decoder = new StringDecoder("utf8");
            const failed = error => {
                reject(error);
                this.retireDiscovery(discovery, error);
            };
            owner.child.stdout.on("data", data => {
                if (owner.stopping) return;
                try {
                    for (const char of decoder.write(data)) {
                        if (!started && /\s/.test(char)) continue;
                        if (!started && char !== "[") throw new Error("discovery-framing");
                        started = true;
                        tail += char;
                        size += Buffer.byteLength(char);
                        if (size > DISCOVERY_BYTES) throw new Error("discovery-overflow");
                        if (quoted) {
                            if (escaped) escaped = false;
                            else if (char === "\\") escaped = true;
                            else if (char === '"') quoted = false;
                        } else if (char === '"') quoted = true;
                        else if (char === "[" || char === "{") depth++;
                        else if (char === "]" || char === "}") depth--;
                        if (depth === 0 && !quoted) {
                            this.snapshot(JSON.parse(tail));
                            tail = "";
                            size = 0;
                            started = false;
                            discovery.kind = "monitoring";
                            resolve();
                        }
                    }
                } catch (error) { failed(error); }
            });
            // Only the lease end stops the monitor quietly. Any other end
            // retires discovery, so the next read starts a new monitor.
            owner.closed.then(() => {
                if (this.lifetime.kind === "closed") reject(new Error("discovery-ended"));
                else failed(new Error("discovery-exit: " + owner.diagnostic.trim()));
            });
        });
    }

    // OVERLAP is a full read's record of what monitor deltas touched while
    // it ran; null means none came.
    snapshot(snapshot, mode = "delta", overlap = null) {
        if (!Array.isArray(snapshot) || snapshot.length > 4096) throw new Error("discovery-shape");
        const held = { nodes: this.nodes, defaults: this.defaults };
        if (mode === "full") {
            this.nodes = new Map();
            this.defaults = noDefaults(null);
        }
        for (const node of snapshot) {
            if (!Number.isSafeInteger(node.id)) throw new Error("discovery-id");
            if (mode === "delta") for (const read of this.reads) read.ids.add(node.id);
            if (node.info === null) {
                this.nodes.delete(node.id);
                if (node.id === this.defaults.id) this.defaults = noDefaults(null);
            }
            // A store new to the monitor arrives whole. A later delta holds
            // only the entries that changed, and a removed entry is freed
            // unprinted (pw-dump.c metadata_property and metadata_dump), so
            // a delta, even `metadata: []`, may hide the removal of any
            // default it does not name. WirePlumber removes one when no node
            // is available, which can leave its node listed (rescan.lua,
            // apply-default-node.lua). settled() reads the store before use.
            // https://github.com/PipeWire/pipewire/blob/master/src/tools/pw-dump.c
            else if (defaultStore(node)) {
                const named = storeDefaults(node);
                const prior = node.id === this.defaults.id ? this.defaults : noDefaults(node.id);
                this.defaults = { ...prior, ...named, unsettled: prior === this.defaults
                    ? ["microphones", "speakers"].filter(group => !(group in named)) : [] };
            }
            else if (node.type === "PipeWire:Interface:Node") {
                const prior = this.nodes.get(node.id);
                const props = node.info && node.info.props;
                if (!props) continue;
                const group = props["media.class"] === undefined ? (prior && prior.group)
                    : props["media.class"] === "Audio/Source" ? "microphones"
                    : props["media.class"] === "Audio/Sink" ? "speakers" : null;
                if (!group) { this.nodes.delete(node.id); continue; }
                const value = props["node.name"] === undefined ? (prior && prior.value) : props["node.name"];
                const label = props["node.description"] || props["node.nick"] || (prior && prior.label) || value;
                if (typeof value !== "string" || !/^[^\x00-\x1f\x7f]{1,200}$/.test(value)
                        || typeof label !== "string" || !/^[^\x00-\x1f\x7f]+$/.test(label))
                    throw new Error("discovery-device");
                if (!this.nodes.has(node.id) && this.nodes.size >= 4096) throw new Error("discovery-nodes");
                // Retain only bounded offer data, never arbitrary properties
                // another client can add or remove indefinitely.
                this.nodes.set(node.id, { group, label: label.slice(0, 60), value });
            }
        }
        if (mode === "delta" && this.defaults !== held.defaults)
            for (const read of this.reads) read.defaults = true;
        // What a delta named during the read keeps the monitor's state. The
        // delta may be newer than the read, and the monitor prints any later
        // change to that object as a further delta: a removal at once, any
        // other change after its sync (pw-dump.c registry_event_global_remove,
        // on_core_done).
        if (overlap !== null) {
            for (const id of overlap.ids)
                if (held.nodes.has(id)) this.nodes.set(id, held.nodes.get(id));
                else this.nodes.delete(id);
            if (overlap.defaults) this.defaults = held.defaults;
        }
        const devices = { microphones: [], speakers: [] };
        for (const { group, label, value } of this.nodes.values()) {
            if (devices[group].some(item => item.value === value)) throw new Error("discovery-duplicate");
            devices[group].push({ label, value });
        }
        for (const group of Object.keys(devices)) {
            devices[group].sort((a, b) => a.value < b.value ? -1 : a.value > b.value ? 1 : 0);
            devices[group] = devices[group].slice(0, 32);
        }
        this.devices = devices;
        this.offers(devices);
        if (this.capture !== null && this.capture.target !== null
                && !devices.microphones.some(item => item.value === this.capture.target))
            this.failCapture(this.lost("microphones", this.capture), "");
        if (this.playback !== null && this.playback.target !== null
                && !devices.speakers.some(item => item.value === this.playback.target))
            this.failPlayback(this.lost("speakers", this.playback));
    }

    // GROUP's device under SETTING: the setting's, else the default, as
    // { target, from } with target null while no store names a default.
    choice(group, setting, settings, engine) {
        const configured = group === "microphones" && engine === "dictation" ? "" : settings[setting] || "";
        return configured === "" ? { target: this.defaults[group], from: "default" } : { target: configured, from: "setting" };
    }

    // The device of GROUP that ENGINE (a Session engine kind) uses under
    // SETTINGS: the one SETTING names, else the default, null before
    // discovery names it. A dictation engine's words are voxtype's, which
    // records the default source, so its captions, turn end and microphone check
    // hear that source too. The daemon's snapshot carries the microphone,
    // so Session keeps a microphone check's result with the source it heard.
    device(group, setting, settings, engine) {
        return this.choice(group, setting, settings, engine).target;
    }

    // The default of GROUP, read from the store when a delta may have
    // removed it. The read answers this use. It replaces the held defaults
    // only when no store delta came during it, which may be newer.
    async settled(group) {
        const before = this.defaults;
        if (!before.unsettled.includes(group)) return before[group];
        const stores = (await this.dump(["PipeWire:Interface:Metadata"])).filter(defaultStore);
        const store = stores.find(node => node.id === before.id) || stores[0];
        const read = store === undefined ? noDefaults(null) : { ...noDefaults(store.id), ...storeDefaults(store) };
        if (this.defaults !== before) return this.defaults.unsettled.includes(group) ? read[group] : this.defaults[group];
        if (read.id === before.id) {
            this.defaults = read;
            // The daemon's check source follows the default microphone.
            if (read.microphones !== before.microphones) this.offers(this.devices);
        }
        return read[group];
    }

    async selected(group, setting) {
        const choice = this.choice(group, setting, this.state.settings, this.state.engine.kind);
        if (choice.from === "default") choice.target = await this.settled(group);
        if (!this.devices[group].some(item => item.value === choice.target)) throw new Error(this.lost(group, choice));
        return choice;
    }

    // A device-lost reason: what was missing, where it came from, and what
    // the last read of GROUP held, bounded. JSON keeps a name control-free.
    lost(group, { target, from }) {
        const names = this.devices[group].slice(0, 3).map(item => item.value.slice(0, 60));
        return "device-lost target=" + JSON.stringify(target === null ? null : target.slice(0, 200)) + " from=" + from
            + " " + group + "=" + this.devices[group].length + JSON.stringify(names);
    }

    async openCapture(e, done, failed) {
        let capture = null;
        try {
            await this.release;
            if (!this.allowed("capture")) throw new Error("capture-refused");
            capture = { kind: "opening", owner: null, e, failed, target: null, from: null, sound: "waiting", frames: 0,
                gate: this.state.engine.kind === "duplex" ? { active: false, remaining: 0, committed: false } : null };
            this.capture = capture;
            await this.discover();
            if (!this.allowed("capture") || this.capture !== capture) return;
            const choice = await this.selected("microphones", "microphone");
            if (!this.allowed("capture") || this.capture !== capture) return;
            const target = choice.target;
            capture.target = target;
            capture.from = choice.from;
            if (this.captureSink === null) throw new Error("speech-unavailable");
            const feed = this.captureSink(e);
            this.feed = feed;
            if (feed === null) throw new Error("speech-unavailable");
            feed.on("error", error => {
                if (this.capture === capture) this.failCapture("provider-disconnected", error.message);
            });
            if (!this.allowed("capture") || this.capture !== capture) return;
            const owner = await this.spawn("capture", "pw-record", [
                "--raw", "--rate", String(PCM_RATE), "--channels", "1", "--format", "s16",
                "--target", target,
                "--properties", STREAM_PROPERTIES, "-"
            ]);
            if (this.capture !== capture) return;
            capture.owner = owner;
            capture.kind = "open";
            let tail = Buffer.alloc(0);
            let opened = false;
            owner.child.stdout.on("data", data => {
                if (owner.stopping || this.capture !== capture) return;
                const frame = Buffer.concat([tail, data]);
                tail = frame.subarray(frame.length - frame.length % 2);
                const pcm = frame.subarray(0, frame.length - frame.length % 2);
                if (!opened && pcm.length !== 0) {
                    opened = true;
                    if (this.allowed("capture")) done();
                }
                if (this.capture !== capture) return;
                if (pcm.length > BUFFER_BYTES || feed.writableLength + pcm.length > BUFFER_BYTES) {
                    this.failCapture("capture-overflow", "");
                    return;
                }
                const inputPeak = peak(pcm);
                if (capture.gate === null) {
                    if (!feed.write(pcm)) owner.child.stdout.pause();
                } else {
                    try { if (!this.feedCloudInput(capture, feed, pcm)) owner.child.stdout.pause(); }
                    catch (error) { this.failCapture("input-end", error.message); }
                }
                if (this.capture !== capture) return;
                this.reportLevel(e.gen, "capture", pcm);
                if (e.mode !== "check") {
                    capture.frames += pcm.length / 2;
                    if (inputPeak > SILENT_PEAK) {
                        if (capture.sound === "silent") this.input({ type: "input-sound", gen: e.gen, op: e.op, device: target });
                        capture.sound = "heard";
                    } else if (capture.sound === "waiting" && capture.frames >= SILENT_FRAMES) {
                        capture.sound = "silent";
                        this.input({ type: "input-silent", gen: e.gen, op: e.op, device: target });
                    }
                }
            });
            feed.on("drain", () => { if (!owner.stopping) owner.child.stdout.resume(); });
            owner.closed.then(() => {
                if (this.capture === capture && !owner.stopping) void this.captureExited(capture, owner);
            });
            if (!this.allowed("capture")) await this.teardown("capture-refused", ["capture"]);
        } catch (error) {
            if (capture !== null && this.capture !== capture) return;
            if (capture !== null) capture.kind = "failed";
            await this.teardown("capture-failed", ["capture"]);
            failed(error.message.startsWith("device-lost ") ? error.message : "audio-start: " + error.message);
        }
    }

    finishCloudInput(capture, feed) {
        const gate = capture.gate;
        if (!gate.active) return;
        gate.active = false;
        gate.remaining = 0;
        gate.committed = feed.endInput() || gate.committed;
    }

    feedCloudInput(capture, feed, pcm) {
        let ready = true;
        const gate = capture.gate;
        for (let offset = 0; offset < pcm.length; offset += CLOUD_FRAME_BYTES) {
            if (this.capture !== capture) return false;
            const frame = pcm.subarray(offset, offset + CLOUD_FRAME_BYTES);
            if (peak(frame) >= CLOUD_SPEECH_PEAK) {
                gate.active = true;
                gate.remaining = CLOUD_HANGOVER_FRAMES;
            } else gate.remaining = Math.max(0, gate.remaining - frame.length / 2);
            if (!gate.active) continue;
            ready = feed.write(frame) && ready;
            if (gate.remaining === 0) this.finishCloudInput(capture, feed);
        }
        return ready;
    }

    // A stream exit and a node-removal message arrive on separate pipes.
    // Read a fresh snapshot before deciding whether the selected device was
    // lost. This one-shot read belongs to the same discovery owner.
    async captureExited(capture, owner) {
        await this.teardown("capture-failed", ["capture"]);
        if (!this.session.live(this.state, capture.e, "capture", ["opening", "open"])) return;
        try {
            await this.refreshDevices();
            if (!this.session.live(this.state, capture.e, "capture", ["opening", "open"])) return;
            capture.failed(this.devices.microphones.some(item => item.value === capture.target)
                ? "capture-exit-" + (owner.exit.signal || owner.exit.code) : this.lost("microphones", capture));
        } catch (error) {
            // The monitor's list stands: a failed read stopped only its own child.
            this.fault("device-probe: " + error.message);
            if (this.session.live(this.state, capture.e, "capture", ["opening", "open"]))
                capture.failed("device-probe: " + error.message);
        }
    }

    // A full read replaces the held list except where a monitor delta came
    // during it; snapshot() keeps the monitor's state there.
    async refreshDevices() {
        const overlap = { ids: new Set(), defaults: false };
        this.reads.add(overlap);
        let read;
        try { read = await this.dump([]); }
        finally { this.reads.delete(overlap); }
        this.snapshot(read, "full", overlap);
    }

    // One pw-dump read of the objects ARGS match, a one-shot child of the
    // discovery owner. A failed read stops only this child.
    async dump(args) {
        const owner = await this.spawn("discovery", "pw-dump", args);
        const chunks = [];
        let bytes = 0, overflow = false;
        owner.child.stdout.on("data", data => {
            bytes += data.length;
            if (bytes > DISCOVERY_BYTES) {
                overflow = true;
                void this.stop(owner);
            } else chunks.push(data);
        });
        await owner.closed;
        if (overflow) throw new Error("discovery-overflow");
        if (owner.stopping) throw new Error("discovery-ended");
        if (owner.exit.code !== 0) throw new Error("discovery-exit: " + owner.diagnostic.trim());
        // pw-dump prints nothing when no object matches (pw-dump.c dump_objects).
        const text = Buffer.concat(chunks).toString("utf8");
        const read = text.trim() === "" ? [] : JSON.parse(text);
        if (!Array.isArray(read) || read.length > 4096) throw new Error("discovery-shape");
        return read;
    }

    failCapture(reason, diagnostic) {
        const capture = this.capture;
        if (capture === null || capture.kind === "failed" || (capture.owner !== null && capture.owner.stopping)) return;
        capture.kind = "failed";
        void this.teardown(reason, ["capture"]).then(() => capture.failed(reason));
        if (diagnostic !== "") this.fault(reason + ": " + diagnostic.slice(0, 200));
    }

    reportLevel(gen, channel, pcm) {
        if (pcm.length === 0) return;
        let square = 0;
        for (let i = 0; i < pcm.length; i += 2) square += (pcm.readInt16LE(i) / 32768) ** 2;
        this.levels[channel] = Math.min(1, Math.sqrt(square / (pcm.length / 2)));
        const at = this.clock.now();
        if (at - this.lastLevel >= 1000 / 30) {
            this.lastLevel = at;
            this.level(gen, { ...this.levels });
        }
    }

    /** Return a lower bound, never received PCM or an estimate of word timing. */
    playbackResult(playback) {
        const heardFrames = Math.max(0, playback.written - Math.ceil(
            PCM_RATE * (PLAYBACK_LEAD_MS + NODE_LATENCY_MS) / 1000));
        let end = 0;
        for (const word of playback.words) {
            if (word.frame > heardFrames) break;
            end = word.end;
        }
        return Object.freeze({ gen: playback.e.gen, op: playback.e.op, source: playback.e.source,
            writtenFrames: playback.written, heardFrames, heardText: playback.text.slice(0, end).trimEnd() });
    }

    // One waiter belongs to the playback operation, whether blocked on input,
    // the clock or pw-cat. Teardown wakes it and removes every listener/timer.
    waitPlayback(playback, stream, event, ms, submit) {
        return new Promise((resolve, reject) => {
            let timer = null;
            let finished = false;
            const finish = error => {
                if (finished) return;
                finished = true;
                if (timer !== null) this.clock.clear(timer);
                if (stream !== null) {
                    if (event !== null) stream.removeListener(event, ready);
                    stream.removeListener("close", ready);
                    stream.removeListener("end", ready);
                    stream.removeListener("error", finish);
                }
                playback.wake = null;
                if (error) reject(error); else resolve();
            };
            const ready = () => finish();
            playback.wake = ready;
            if (stream !== null) {
                if (event !== null) stream.once(event, ready);
                stream.once("close", ready);
                stream.once("end", ready);
                stream.once("error", finish);
            } else timer = this.clock.set(ready, ms);
            if (submit !== undefined) {
                try { submit(finish); }
                catch (error) { finish(error); }
            }
        });
    }

    playbackPacket(playback, packet) {
        const pcm = Buffer.isBuffer(packet) ? packet : packet && packet.pcm;
        if (!Buffer.isBuffer(pcm) || pcm.length > BUFFER_BYTES || pcm.length % 2 !== 0)
            throw new Error("playback-frame");
        const sentence = Buffer.isBuffer(packet) ? undefined : packet && packet.sentence;
        const tone = !Buffer.isBuffer(packet) && packet.tone === true;
        if (sentence !== undefined) {
            if (sentence === null || typeof sentence.text !== "string" || sentence.text.trim() === ""
                    || !Number.isSafeInteger(sentence.frames) || sentence.frames < pcm.length / 2
                    || sentence.frames > SENTENCE_FRAMES || playback.received < playback.sentenceEnd)
                throw new Error("playback-sentence");
            const separator = playback.text === "" ? "" : " ";
            if (Buffer.byteLength(playback.text + separator + sentence.text) > TRANSCRIPT_BYTES)
                throw new Error("playback-transcript-overflow");
            const base = playback.text.length + separator.length;
            const words = sentence.words === undefined
                ? [{ frame: sentence.frames, end: sentence.text.length }] : sentence.words;
            if (!Array.isArray(words) || words.length === 0 || playback.words.length + words.length > 4096)
                throw new Error("playback-words");
            let frame = 0, end = 0;
            for (const word of words) {
                // Providers supply actual alignment, not proportional guesses.
                // A missing alignment credits only the completed sentence.
                if (word === null || typeof word !== "object"
                        || !Number.isSafeInteger(word.frame) || word.frame <= frame || word.frame > sentence.frames
                        || !Number.isSafeInteger(word.end) || word.end <= end || word.end > sentence.text.length
                        || (word.end < sentence.text.length
                            && !/\s/u.test(sentence.text[word.end - 1]) && !/\s/u.test(sentence.text[word.end])))
                    throw new Error("playback-words");
                frame = word.frame;
                end = word.end;
                playback.words.push({ frame: playback.received + frame, end: base + end });
            }
            if (frame !== sentence.frames || end !== sentence.text.length) throw new Error("playback-words");
            playback.text += separator + sentence.text;
            playback.sentenceEnd = playback.received + sentence.frames;
        }
        playback.received += pcm.length / 2;
        return { pcm, tone };
    }

    async writePlayback(playback, owner, frame, spoken) {
        let offset = 0;
        while (offset < frame.length && this.playback === playback && !owner.stopping) {
            const now = this.clock.now();
            // Rebase after starvation or a stalled event loop. No catch-up burst.
            playback.frontier = Math.max(playback.frontier === null ? now : playback.frontier, now);
            const available = Math.floor((now + PLAYBACK_LEAD_MS - playback.frontier) * PCM_RATE / 1000);
            const needed = Math.min((frame.length - offset) / 2, PCM_RATE * NODE_LATENCY_MS / 1000);
            if (available < needed) {
                await this.waitPlayback(playback, null, null,
                    Math.max(1, Math.ceil(playback.frontier - now - PLAYBACK_LEAD_MS + needed * 1000 / PCM_RATE)));
                continue;
            }
            const bytes = needed * 2;
            const pcm = frame.subarray(offset, offset + bytes);
            // Voice mute writes silence of the same length for spoken words,
            // so pacing, the written count and the acknowledgement run as for
            // a heard reply, and the level below still reads the voice for
            // the speaking look.
            const out = spoken && this.state.voiceMute.kind === "on" ? Buffer.alloc(bytes) : pcm;
            // Node calls the write callback when this chunk is handled. Keep
            // only one paced chunk pending; Session owns a stalled player's
            // deadline. Flush also wakes this waiter before the late callback.
            // https://nodejs.org/api/stream.html#writablewritechunk-encoding-callback
            const written = this.waitPlayback(playback, owner.child.stdin, null, null,
                acknowledged => owner.child.stdin.write(out, acknowledged));
            playback.written += bytes / 2;
            playback.frontier += bytes * 1000 / (PCM_RATE * 2);
            offset += bytes;
            this.reportLevel(playback.e.gen, "playback", pcm);
            await written;
            if (this.playback !== playback || owner.stopping) return;
            if (owner.exit !== null || owner.child.stdin.destroyed)
                throw new Error("playback-pipe-closed");
        }
    }

    async startPlayback(e, done, failed) {
        if (this.playback !== null) { failed("playback-busy"); return; }
        // Install the operation before the first await. An immediate flush must
        // retire startup too, even before there is a source or audio child.
        const playback = { kind: "starting", e, failed, target: null, from: null, wake: null,
            written: 0, received: 0, frontier: null, text: "", words: [], sentenceEnd: 0 };
        this.playback = playback;
        try {
            await this.release;
            if (this.playback !== playback) return;
            if (!this.allowed("playback")) throw new Error("playback-refused");
            // A start earcon precedes the first capture, which otherwise
            // starts device discovery. Both paths share that one owner.
            await this.discover();
            if (this.playback !== playback) return;
            if (!this.allowed("playback")) throw new Error("playback-refused");
            if (this.playbackSource === null) throw new Error("playback-source-unavailable");
            const choice = await this.selected("speakers", "speaker");
            if (this.playback !== playback) return;
            const target = choice.target;
            playback.target = target;
            playback.from = choice.from;
            const handed = this.playbackSource(e.source);
            if (handed === null) throw new Error("playback-source-unavailable");
            const { readable: source, spoken } = handed;
            if (!(source instanceof Readable)) throw new Error("playback-source");
            this.playbackFeed = source;
            source.on("error", error => {
                if (this.playback === playback) this.failPlayback("playback-source: " + error.message);
            });
            if (this.playback !== playback) {
                await this.teardown("playback-retired", ["playback"]);
                return;
            }
            const unit = source.readableObjectMode ? BUFFER_BYTES : 1;
            const duplex = source.writableHighWaterMark !== undefined;
            const queueLimit = sourceLimit(source.readableObjectMode, duplex);
            // A compliant stream can cross its high-water mark by one chunk.
            const queueAllowance = queueLimit + BUFFER_BYTES / unit;
            if (!Number.isSafeInteger(source.readableHighWaterMark) || source.readableHighWaterMark > queueLimit
                    || (duplex && (!Number.isSafeInteger(source.writableHighWaterMark)
                        || source.writableHighWaterMark > queueLimit))
                    || source.readableEncoding !== null)
                throw new Error("playback-source-buffer");
            const owner = await this.spawn("playback", "pw-cat", [
                "--playback", "--raw", "--latency", String(NODE_LATENCY_MS) + "ms", "--rate", String(PCM_RATE),
                "--channels", "1", "--format", "s16", "--target", target,
                "--properties", STREAM_PROPERTIES, "-"
            ]);
            owner.child.stdout.resume();
            if (this.playback !== playback) return;
            if (!this.allowed("playback")) { await this.teardown("playback-refused", ["playback"]); return; }
            playback.kind = "feeding";
            owner.closed.then(() => {
                if (this.playback === playback && playback.kind === "feeding" && !owner.stopping)
                    this.failPlayback("playback-exit-" + (owner.exit.signal || owner.exit.code));
            });
            while (this.playback === playback && !owner.stopping) {
                if (source.readableLength > queueAllowance || (duplex && source.writableLength > queueAllowance))
                    throw new Error("playback-source-buffer");
                const packet = source.read(source.readableObjectMode ? undefined
                    : Math.min(BUFFER_BYTES, source.readableLength || BUFFER_BYTES));
                if (packet === null) {
                    if (source.readableEnded) break;
                    if (source.destroyed) throw new Error("playback-source-closed");
                    await this.waitPlayback(playback, source, "readable");
                    continue;
                }
                const { pcm, tone } = this.playbackPacket(playback, packet);
                await this.writePlayback(playback, owner, pcm, spoken && !tone);
            }
            if (this.playback !== playback || owner.stopping) return;
            if (playback.received < playback.sentenceEnd) throw new Error("playback-sentence-incomplete");
            playback.kind = "draining";
            owner.child.stdin.end();
            await owner.closed;
            if (!owner.stopping) {
                if (owner.exit.code !== 0) throw new Error("playback-exit-" + (owner.exit.signal || owner.exit.code));
                await this.teardown("playback-complete", ["playback"]);
                done(this.playbackResult(playback));
            }
        } catch (error) {
            if (this.playback !== playback) return;
            await this.teardown("playback-failed", ["playback"]);
            failed(error.message);
        }
    }

    failPlayback(reason) {
        const playback = this.playback;
        if (playback === null || playback.kind === "failed") return;
        playback.kind = "failed";
        void this.teardown("playback-failed", ["playback"]).then(() => playback.failed(reason));
    }

    // Mark an owner before closing its pipes so its callbacks cannot treat a
    // requested stop as a device failure or reopen capture.
    stop(owner) {
        owner.stopping = true;
        owner.child.stdio[3].end();
        owner.child.stdin.destroy();
        return owner.closed;
    }

    // The release path for every owner of KINDS and the state they feed.
    teardown(reason, kinds) {
        const owners = [...this.children.values()].filter(owner => kinds.includes(owner.kind));
        const feeds = [];
        for (const owner of owners) this.stop(owner);
        if (kinds.includes("capture")) {
            this.levels.capture = 0;
            if (this.capture !== null && this.capture.kind !== "failed") this.capture.kind = "retired";
            this.capture = null;
            if (this.feed !== null) {
                if (!this.feed.closed) feeds.push(new Promise(resolve => this.feed.once("close", resolve)));
                this.feed.destroy();
                this.feed = null;
            }
        }
        if (kinds.includes("playback")) {
            this.levels.playback = 0;
            if (this.playback !== null) {
                this.lastPlayback = this.playbackResult(this.playback);
                if (this.playback.kind !== "failed") this.playback.kind = "retired";
                if (this.playback.wake !== null) this.playback.wake();
            }
            this.playback = null;
            if (this.playbackFeed !== null) {
                if (!this.playbackFeed.closed) feeds.push(new Promise(resolve => this.playbackFeed.once("close", resolve)));
                this.playbackFeed.destroy();
                this.playbackFeed = null;
            }
        }
        const release = Promise.all(owners.map(owner => owner.closed).concat(feeds)).then(() => {});
        this.release = Promise.all([this.release, release]).then(() => {});
        return this.release;
    }

    close(reason) {
        this.lifetime = { kind: "closed" };
        if (this.discovery.kind === "waiting") this.clock.clear(this.discovery.timer);
        return this.teardown(reason, ["capture", "playback", "discovery"]);
    }
}

module.exports = { Audio, sourceLimit, peak, SILENT_PEAK, PCM_RATE, SENTENCE_FRAMES };
