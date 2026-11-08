// The explicit setup window writes one native PipeWire drop-in. Audio reads
// this contract and judges its observed graph; installation never loads it.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const Core = require("./Core.js");
const { O_RDONLY, O_DIRECTORY, O_NOFOLLOW, O_NONBLOCK, O_WRONLY, O_CREAT, O_EXCL } = fs.constants;
const FILE = "60-jarvis-echo-cancel.conf";
const HEADER = "# VGS Jarvis native echo cancellation v1";
const NAMES = Object.freeze({ capture: "jarvis_ec_capture", source: "jarvis_ec_source",
    sink: "jarvis_ec_sink", playback: "jarvis_ec_playback" });

function targets(value) {
    if (value === null || typeof value !== "object" || Array.isArray(value)
            || Object.keys(value).sort().join(",") !== "microphone,speaker"
            || ![value.microphone, value.speaker].every(name => typeof name === "string"
                && /^[^\x00-\x1f\x7f]{1,200}$/.test(name) && !Object.values(NAMES).includes(name)))
        throw new Error("echo-cancel-targets");
    return { microphone: value.microphone, speaker: value.speaker };
}

function group(value) {
    return "jarvis-ec-" + crypto.createHash("sha256").update(JSON.stringify(targets(value))).digest("hex").slice(0, 16);
}

// Native keys and copied node.group/node.link-group:
// https://github.com/PipeWire/pipewire/blob/1.6.10/src/modules/module-echo-cancel.c
// WebRTC controls: spa/plugins/aec/aec-webrtc.cpp in that release. These are
// the owner's comparison candidate, not a measured acoustic improvement.
function argumentsText(value) {
    const chosen = targets(value);
    return `library.name = aec/libspa-aec-webrtc
            node.group = "${group(chosen)}"
            node.link-group = "${group(chosen)}"
            audio.rate = 48000
            audio.channels = 1
            audio.position = [ MONO ]
            monitor.mode = false
            aec.args = {
                webrtc.noise_suppression = false
                webrtc.gain_control = false
                webrtc.high_pass_filter = true
            }
            capture.props = {
                node.name = ${NAMES.capture}
                target.object = ${JSON.stringify(chosen.microphone)}
                node.dont-fallback = true
            }
            source.props = {
                node.name = ${NAMES.source}
                node.description = "Jarvis echo-canceled microphone"
            }
            sink.props = {
                node.name = ${NAMES.sink}
                node.description = "Jarvis echo-cancel playback"
            }
            playback.props = {
                node.name = ${NAMES.playback}
                target.object = ${JSON.stringify(chosen.speaker)}
                node.dont-fallback = true
            }
`.trim();
}

function render(value) {
    const chosen = targets(value);
    return HEADER + "\n# targets: " + JSON.stringify(chosen) + "\n" + `context.modules = [
    {
        name = libpipewire-module-echo-cancel
        flags = [ nofail ]
        args = {
            ${argumentsText(chosen)}
        }
    }
]
`;
}

function location(environment) {
    const root = environment.XDG_CONFIG_HOME || (environment.HOME ? path.join(environment.HOME, ".config") : "");
    if (!path.isAbsolute(root) || path.normalize(root) !== root || /[\x00-\x1f\x7f]/.test(root))
        throw new Error("echo-cancel-config-path");
    const file = path.join(root, "pipewire", "pipewire.conf.d", FILE);
    if (Buffer.byteLength(file) > 4096) throw new Error("echo-cancel-config-path");
    return file;
}

function readAt(parent) {
    let fd;
    try {
        fd = fs.openSync(Core.anchored().child(parent, FILE), O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
        const stat = fs.fstatSync(fd);
        if (!stat.isFile() || stat.uid !== process.getuid() || stat.size > 16384)
            return { state: "foreign", reason: "foreign-file" };
        const buffer = Buffer.alloc(16385);
        const size = fs.readSync(fd, buffer, 0, buffer.length, 0);
        if (size > 16384) return { state: "foreign", reason: "foreign-file" };
        const text = buffer.subarray(0, size).toString("utf8");
        if (!text.startsWith(HEADER + "\n# targets: ")) return { state: "foreign", reason: "foreign-file" };
        let chosen;
        try { chosen = targets(JSON.parse(text.split("\n")[1].slice("# targets: ".length))); }
        catch { return { state: "foreign", reason: "config-changed" }; }
        if (text !== render(chosen)) return { state: "foreign", reason: "config-changed" };
        return { state: "installed", reason: "", targets: chosen, stat, text };
    } catch (error) {
        if (error.code === "ENOENT") return { state: "absent", reason: "not-installed" };
        if (error.code === "ELOOP") return { state: "foreign", reason: "foreign-file" };
        return { state: "unavailable", reason: "config-unreadable" };
    } finally { if (fd !== undefined) fs.closeSync(fd); }
}

function read(environment) {
    let file;
    try { file = location(environment); }
    catch { return { state: "unavailable", path: "", reason: "config-path" }; }
    const held = Core.anchored().directory(path.dirname(file));
    if (held.kind === "absent") return { state: "absent", path: file, reason: "not-installed" };
    if (held.kind !== "directory") return { state: held.kind === "link" ? "foreign" : "unavailable",
        path: file, reason: held.kind === "link" ? "foreign-file" : "config-unreadable" };
    try { return { ...readAt(held.fd), path: file }; }
    finally { fs.closeSync(held.fd); }
}

// Reuse the anchored walk for existing parents. Only newly missing children
// are created here, while the already-open parent holds their destination.
function install(environment, value) {
    const text = render(value), file = location(environment), missing = [];
    let folder = path.dirname(file), held;
    for (;;) {
        held = Core.anchored().directory(folder);
        if (held.kind === "directory") break;
        if (held.kind !== "absent") throw new Error("echo-cancel-config-" + held.kind);
        missing.unshift(path.basename(folder));
        folder = path.dirname(folder);
    }
    let fd = held.fd;
    try {
        for (const name of missing) {
            const child = Core.anchored().child(fd, name);
            try { fs.mkdirSync(child, { mode: 0o700 }); }
            catch (error) { if (error.code !== "EEXIST") throw error; }
            const next = fs.openSync(child, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
            fs.closeSync(fd);
            fd = next;
        }
        const parent = fs.fstatSync(fd);
        if (parent.uid !== process.getuid() || (parent.mode & 0o022) !== 0)
            throw new Error("echo-cancel-config-ownership");
        const before = readAt(fd);
        if (before.state !== "absent" && before.state !== "installed")
            throw new Error("echo-cancel-" + before.reason);
        if (before.text === text) return { path: file, changed: false };
        const temporary = "." + FILE + "." + crypto.randomUUID();
        const scratch = Core.anchored().child(fd, temporary), destination = Core.anchored().child(fd, FILE);
        const output = fs.openSync(scratch, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600);
        try {
            try { fs.writeFileSync(output, text); fs.fsyncSync(output); }
            finally { fs.closeSync(output); }
            const current = readAt(fd);
            if (before.state === "absent") {
                if (current.state !== "absent") throw new Error("echo-cancel-config-changed");
                // link is an atomic no-replace publication of the complete file.
                fs.linkSync(scratch, destination);
            } else {
                if (current.state !== "installed" || current.stat.ino !== before.stat.ino
                        || current.stat.dev !== before.stat.dev || current.text !== before.text)
                    throw new Error("echo-cancel-config-changed");
                fs.renameSync(scratch, destination);
            }
            fs.fsyncSync(fd);
        } finally {
            try { fs.unlinkSync(scratch); }
            catch (error) { if (error.code !== "ENOENT") throw error; }
        }
        return { path: file, changed: true };
    } finally { fs.closeSync(fd); }
}

module.exports = { NAMES, targets, group, argumentsText, render, location, read, install };
