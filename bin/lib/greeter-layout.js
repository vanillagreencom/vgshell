// The displays service publishes its saved settings as
// { outputs: <MonitorLogic rules>, primaryOutput: <identifier or ""> } on stdin:
//   node bin/lib/greeter-layout.js copy
// The greeter compositor consumes `render`; the greeter host consumes `read`.
// Both read displays.json under the greeter's XDG_CONFIG_HOME/vgshell, beside
// its theme. The existing greeter step fixes that home at DIRECTORY's parent.
// No operation elevates or accepts an executable or copy destination in argv.
// copy prints layout=copied|unchanged; read prints one judged JSON object;
// render prints only Lua produced by MonitorLogic. Missing data means no saved
// layout; an unreadable or invalid file refuses without publishing anything.
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("./qml-library.js");
const { replaceFile } = require("./judge-files.js");

const monitors = load(path.join(__dirname, "../../shell/Core/MonitorLogic.js"));
const DIRECTORY = "/var/lib/vgshell/greeter/theme/vgshell";
const READ_DIRECTORY = path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "vgshell");
const FILE = "displays.json";
const EMPTY = { outputs: {}, primaryOutput: "" };
const { O_RDONLY, O_NOFOLLOW, O_DIRECTORY, O_NONBLOCK } = fs.constants;

function refused(key) {
    throw new Error("greeter-layout: refused: " + key);
}

function judge(text) {
    let data;
    try { data = JSON.parse(text); } catch (_) { refused("layout=json"); }
    if (!monitors.isPlainObject(data) ||
        Object.keys(data).some(key => key !== "outputs" && key !== "primaryOutput") ||
        typeof data.primaryOutput !== "string") refused("layout=shape");
    const result = monitors.rulesLines(data.outputs);
    if (!result.ok) refused("layout=rules detail=" + result.error);
    // Reuse the monitor judge's identifier grammar, never another parser.
    if (data.primaryOutput !== "") {
        try { monitors.luaString(data.primaryOutput); } catch (_) { refused("layout=primary"); }
    }
    return { data: { outputs: data.outputs, primaryOutput: data.primaryOutput }, lines: result.lines };
}

function openDirectory(directory, writing) {
    const fd = fs.openSync(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    const stat = fs.fstatSync(fd);
    if (writing && (stat.uid !== process.getuid() || (stat.mode & 0o022) !== 0)) {
        fs.closeSync(fd);
        refused("destination=ownership");
    }
    return fd;
}

function readFile(directoryFd, writing) {
    let fd;
    try {
        // A FIFO planted by the account owning the data must not hang login.
        // Node fs flags: nodejs/node v22.17.0 doc/api/fs.md.
        fd = fs.openSync("/proc/self/fd/" + directoryFd + "/" + FILE, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    } catch (error) {
        if (error.code === "ENOENT") return null;
        throw error;
    }
    try {
        const stat = fs.fstatSync(fd);
        if (!stat.isFile()) refused("layout=not-regular");
        if (writing && (stat.uid !== process.getuid() || (stat.mode & 0o022) !== 0)) refused("destination=ownership");
        return { text: fs.readFileSync(fd, "utf8"), mode: stat.mode & 0o777 };
    } finally { fs.closeSync(fd); }
}

function read(directory = READ_DIRECTORY) {
    let fd;
    try { fd = openDirectory(directory, false); } catch (error) {
        if (error.code === "ENOENT") return judge(JSON.stringify(EMPTY));
        throw error;
    }
    try {
        const file = readFile(fd, false);
        return judge(file === null ? JSON.stringify(EMPTY) : file.text);
    } finally { fs.closeSync(fd); }
}

function copy(text, directory = DIRECTORY) {
    if (process.getuid() === 0) refused("caller=root");
    const next = JSON.stringify(judge(text).data) + "\n";
    const fd = openDirectory(directory, true);
    try {
        const base = "/proc/self/fd/" + fd;
        const previous = readFile(fd, true);
        if (previous !== null && previous.text === next && previous.mode === 0o644) return "unchanged";
        replaceFile(base + "/" + FILE, next, "layout", 0o644);
        return "copied";
    } finally { fs.closeSync(fd); }
}

if (require.main === module) {
    try {
        if (process.argv.length !== 3) refused("arguments=count");
        switch (process.argv[2]) {
        case "copy":
            process.stdout.write("layout=" + copy(fs.readFileSync(0, "utf8")) + "\n");
            break;
        case "read":
            process.stdout.write(JSON.stringify(read().data) + "\n");
            break;
        case "render":
            process.stdout.write(read().lines.join("\n") + "\n");
            break;
        default: refused("operation=unknown");
        }
    } catch (error) {
        process.stderr.write((error.first ? "greeter-layout: refused: " + error.first : error.message.startsWith("greeter-layout:") ? error.message :
            "greeter-layout: refused: io=" + (error.code || "failed")) + "\n");
        process.exitCode = 1;
    }
}

module.exports = { judge, read, copy };
