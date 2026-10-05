import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ClipboardHistory.js" as History

// The clipboard history's service: the one owner of the watcher and the one
// writer of the history. `entries` is the history; the store file follows it
// and is read once, as the service is built. The overlay holds no history:
// it asks for its rows and for every change through the plugin's own IPC.
//   shortcut vgs.clipboard:toggle           SUPER+CTRL+V from the manifest
//   vgsh ipc call vgs.clipboard invoke toggle ''
//   vgsh ipc call vgs.clipboard invoke rows '<filter>'   { images, total, rows }
//   vgsh ipc call vgs.clipboard invoke paste|copy|pin|delete '<entry id>'
//   vgsh ipc call vgs.clipboard invoke clear ''
// Each change answers `ok` or a keyed `refused:` line, and a refusal shows
// a toast.
//
// One watcher, `wl-paste --watch`, runs the helper's `capture` for each
// copy, the first for the copy on the clipboard as it starts. setpriv ends
// it with the shell, however the shell ends, and a capture puts an image's
// file in place before it prints the entry's line. Every other run of the
// helper goes through one queue, one at a time and in order: a file is
// deleted only while no entry names it.
//
// A paste puts the entry on the clipboard, hides the overlay, asks the core
// which window has the keyboard and sends that window the paste key. No key
// goes out unless the core names a terminal or an application; the entry
// then stays on the clipboard and a toast says so.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The shell this service registered with, so a settings change that
    // hands over a new object registers nothing twice.
    property var registeredWith: null
    // The history, newest first.
    property var entries: []
    // `reading` until the store file is read, `sweeping` while the store's
    // directories are made and its unused images deleted, then `ready`, or
    // `failed` when the store could not be prepared: nothing is recorded.
    property string store: "reading"
    // Image files an entry named and may name no longer.
    property var unusedFiles: []
    // The helper runs that wait, each { name, plan, done }: `plan` answers
    // { args, input } as the run starts, or null to skip it.
    property var jobs: []
    // The run in progress: { name, input, done, code }, or null.
    property var job: null
    // The paste or copy in progress, { send }, or null.
    property var putting: null
    readonly property string storeDir: Paths.stateDir + "/clipboard"
    readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("helper/clipboard.py")).replace(/^file:\/\//, ""))
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property bool watching: shell !== null && store === "ready" && missing.indexOf("wl-paste") === -1
    // The core names the window a paste goes to from Quickshell's desktop
    // entries, whose index scan starts at their first read. Reading them
    // here starts it as the service is built, before the first paste.
    readonly property int desktopEntryCount: DesktopEntries.applications.values.length

    onShellChanged: {
        if (shell === null || registeredWith !== null) return;
        registeredWith = shell;
        shell.shortcut.register("toggle", "Open or close the clipboard history", () => root.toggle());
        shell.ipc.handle("toggle", () => root.toggle());
        shell.ipc.handle("rows", filter => JSON.stringify({ images: root.storeDir + "/images", total: root.entries.length, rows: History.rows(root.entries, filter) }));
        shell.ipc.handle("paste", id => root.put(id, true));
        shell.ipc.handle("copy", id => root.put(id, false));
        shell.ipc.handle("pin", id => root.change(id, History.repinned(root.entries, id)));
        shell.ipc.handle("delete", id => root.change(id, History.removed(root.entries, id)));
        shell.ipc.handle("clear", () => root.keep(History.cleared(root.entries)));
    }

    function toggle() {
        const reply = shell.surfaces.toggle("overlay", "{}");
        if (reply !== "ok") console.warn("clipboard: toggle " + reply);
        return reply;
    }

    // ------------------------------------------------------------ history

    function restore(text) {
        if (store !== "reading") return;
        entries = History.parse(text);
        store = "sweeping";
        run("sweep", () => ({ args: ["sweep"].concat(History.files(root.entries)), input: null }), code => {
            root.store = code === 0 ? "ready" : "failed";
            if (code !== 0) root.notice("Clipboard history is off", "The history folder cannot be used.");
        });
    }

    // Make NEXT the history, write it and delete the image files it left.
    function keep(next) {
        if (store !== "ready") return refused("store=" + store, "Clipboard history did not change", store === "failed" ? "The history folder cannot be used." : "The history is still loading.");
        unusedFiles = History.unused(unusedFiles.concat(History.files(entries)), next);
        entries = next;
        if (!jobs.some(waiting => waiting.name === "save"))
            run("save", () => ({ args: ["save"], input: History.serialize(root.entries) }), code => {
                if (code !== 0) root.notice("Clipboard history is not saved", "The history file cannot be written.");
            });
        if (unusedFiles.length > 0 && !jobs.some(waiting => waiting.name === "drop"))
            run("drop", () => {
                const names = History.unused(root.unusedFiles, root.entries);
                root.unusedFiles = [];
                return names.length === 0 ? null : { args: ["drop"].concat(names), input: null };
            }, null);
        return "ok";
    }

    function change(id, next) {
        return History.find(entries, id) === null ? unknownEntry() : keep(next);
    }

    // One line of the watcher: a copy to record. A line the judge refuses
    // is counted, never printed, since it may hold copied data.
    function captured(line) {
        const entry = History.captured(line);
        if (entry === null) console.warn("clipboard: capture line refused length=" + line.length);
        else keep(History.record(entries, entry));
    }

    // ------------------------------------------------------------ helper runs

    function run(name, plan, done) {
        jobs = jobs.concat([{ name: name, plan: plan, done: done }]);
        next();
    }

    function next() {
        while (job === null && jobs.length > 0) {
            const head = jobs[0];
            jobs = jobs.slice(1);
            const planned = head.plan();
            if (planned === null) continue;
            job = { name: head.name, input: planned.input, done: head.done, code: null };
            helper.stdinEnabled = planned.input !== null;
            helper.command = ["python3", helperPath, storeDir].concat(planned.args);
            helper.running = true;
        }
    }

    // ------------------------------------------------------------ paste

    // Put entry ID on the clipboard and, with SEND, paste it into the
    // window that has the keyboard.
    function put(id, send) {
        const entry = History.find(entries, id);
        if (entry === null) return unknownEntry();
        if (putting !== null) return refused("clipboard=busy", "Clipboard is busy", "An earlier entry is not pasted yet. Try again.");
        const needed = (send ? ["wl-copy", "wtype"] : ["wl-copy"]).filter(command => missing.indexOf(command) !== -1);
        if (needed.length > 0) {
            shell.requirements.offer(needed);
            return "refused: clipboard=missing " + needed.join(",");
        }
        putting = { send: send };
        run("copy", () => entry.type === "image" ? { args: ["copy", entry.mime, entry.id], input: null } : { args: ["copy", History.TEXT_MIME], input: entry.text }, code => root.copied(code));
        return "ok";
    }

    function copied(code) {
        if (code !== 0) {
            putting = null;
            notice("Copy failed", "The entry is not on the clipboard.");
            return;
        }
        const reply = shell.surfaces.hide("overlay");
        if (reply !== "ok") console.warn("clipboard: hide " + reply);
        if (putting.send) shell.compositor.observeInput(null, seen => root.observed(seen));
        else putting = null;
    }

    function observed(seen) {
        const kind = seen.ok ? seen.target.kind : "";
        if (kind !== "terminal" && kind !== "application") {
            unsent(seen.ok ? "target=" + kind : seen.error);
            return;
        }
        sender.code = null;
        sender.command = ["wtype"].concat(History.pasteChord(kind === "terminal"));
        sender.running = true;
    }

    function unsent(reason) {
        putting = null;
        console.warn("clipboard: paste key not sent: " + reason);
        notice("Paste failed", "The entry is on the clipboard. Paste it with the key of the application.");
    }

    function notice(title, message) {
        shell.toasts.show({ title: title, message: message, tone: "warning", icon: "clipboard-list" });
    }

    // A change the service refuses: the caller gets the keyed line, and a
    // toast says why, since the key that asked for the change shows
    // nothing else.
    function refused(key, title, message) {
        notice(title, message);
        return "refused: " + key;
    }

    function unknownEntry() {
        return refused("entry=unknown", "Entry not found", "The entry is not in the clipboard history.");
    }

    // ------------------------------------------------------------ owners

    // Reads the store once, when the service is built; a missing file and
    // one that holds no history both start empty.
    FileView {
        path: root.storeDir + "/history.json"
        printErrors: false
        onLoaded: root.restore(text())
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) console.warn("clipboard: history unreadable: " + error);
            root.restore("");
        }
    }

    Process {
        id: watcher
        running: root.watching && !retry.running
        command: ["setpriv", "--pdeathsig", "TERM", "--", "wl-paste", "--watch", "python3", root.helperPath, root.storeDir, "capture"]
        stdout: SplitParser { onRead: line => root.captured(line) }
        // The helper's refusals, one keyed line each; none holds copied data.
        stderr: SplitParser { onRead: line => console.warn("clipboard: watcher " + line) }
        // A watcher that ends takes the history with it while copying still
        // works, so it is started again. A failed start emits only this
        // signal (runtime-qml.md).
        onRunningChanged: {
            if (running || !root.watching) return;
            console.warn("clipboard: watcher ended, started again in " + retry.interval + " ms");
            retry.restart();
        }
    }

    // A watcher that ends at once, as under a compositor without the
    // data-control protocol, must not spin.
    Timer {
        id: retry
        interval: 5000
    }

    Process {
        id: helper
        stderr: StdioCollector { id: helperErrors }
        onStarted: {
            if (root.job.input === null) return;
            write(root.job.input);
            stdinEnabled = false;
        }
        onExited: code => { root.job.code = code; }
        // A run that failed to start emits only this signal, and its code
        // stays null (runtime-qml.md).
        onRunningChanged: {
            if (running || root.job === null) return;
            const ended = root.job;
            root.job = null;
            if (ended.code !== 0) console.warn("clipboard: " + ended.name + " failed exit=" + (ended.code === null ? "not-started" : ended.code) + " " + helperErrors.text.trim());
            if (ended.done !== null) ended.done(ended.code);
            root.next();
        }
    }

    Process {
        id: sender
        property var code: null
        onExited: exit => { code = exit; }
        onRunningChanged: {
            if (running || root.putting === null) return;
            if (code === 0) root.putting = null;
            else root.unsent("wtype exit=" + (code === null ? "not-started" : code));
        }
    }
}
