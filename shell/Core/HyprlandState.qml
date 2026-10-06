import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "HyprlandState.js" as State
import "PluginLogic.js" as Logic

// Owns the reads behind the `hyprland` capability: Hyprland's input
// devices, the options the layer wrote that read back otherwise, the values
// the user's configuration gave them, the keys something other than the
// layer binds and where the user's configuration binds each. It also runs
// the edit that takes such a bind line out of the user's file or puts it
// back, then reloads Hyprland. HyprlandState.js judges every
// reply; this runs the reads while `active` and holds the last answers.
// Hyprland posts `configreloaded` after each reload and `activelayout` when
// a keyboard comes, goes or switches layout, but nothing when a pointer
// comes or goes, so a change in /dev/input also reads the devices again.
// A failed read is logged
// and returns that member to null.
Scope {
    id: root

    // Whether anything needs the reads: a plugin holds `hyprland`, or the
    // key capture asked who else holds a key (KeyCapture.qml).
    property bool active: false
    // HyprlandLayer.qml binds these from its render: the options written,
    // option conflicts, and the descriptions of the binds written.
    property var written: []
    property var optionConflicts: []
    property var layerBinds: []

    // devicesState's devices, null until read while active.
    property var devices: null
    property string devicesFailure: ""
    // The touchpad names the layer writes a per-device option for, null
    // while the devices are unread.
    readonly property var touchpads: State.touchpads(devices)
    // [{ id, path }] for each written option Hyprland reads back otherwise,
    // and the keys bound by something other than the layer; null while
    // unread or after a failed read.
    property var overriddenRows: null
    property var foreignKeys: null
    // [{ id, path, value }] for each written option the user's
    // configuration gave another value, which the layer then replaced; null
    // while unread or after a failed read.
    property var userValueRows: null
    // The last binds read's keyed failure, "" once one succeeds.
    property string bindsFailure: ""
    // State.userBinds' binds, where the user's configuration binds each
    // key; null while unread or after a failed read.
    property var userBindRows: null
    // The bind line edit running, { done, said }, or null.
    property var bindEdit: null
    // The user's configuration directory and Hyprland directory, as
    // bin/vgshell names them.
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") || "") + "/.config"
    readonly property string hyprDir: configDir + "/hypr"
    property var keyResolution: null

    onActiveChanged: {
        if (active) {
            readDevices();
            readOptions();
            readUserValues();
            readBinds();
            return;
        }
        finishKeys({ ok: false, error: "refused: keymap=inactive" });
        keyResolver.running = false;
        devices = null;
        devicesFailure = "";
        overriddenRows = null;
        userValueRows = null;
        foreignKeys = null;
        bindsFailure = "";
        userBindRows = null;
    }

    // The capability for one instance; it holds nothing to release.
    function provider(ctx) {
        return Object.freeze({
            get overridden() { return root.overriddenFor(ctx.id); },
            get userValues() { return root.userValuesFor(ctx.id); },
            get devices() { return root.devices === null ? null : Logic.frozenJson(root.devices); },
            get foreignBinds() { return root.foreignKeys === null ? null : Logic.frozenJson(root.foreignKeys); },
            resolveKeys: (keys, done) => {
                if (!ctx.active) return;
                root.resolveKeys(keys, value => { if (ctx.active) done(value); });
            },
            switchKeyboardLayout: target => Compositor.switchLayout(target)
        });
    }

    function record() {
        return { active: root.active };
    }

    function readDevices() {
        if (!active) return;
        devicesReader.read(keyResolution === null ? State.DEVICES_REQUEST : State.KEYS_REQUEST,
            keyResolution === null ? null : "keys");
    }

    function resolveKeys(keys, done) {
        if (typeof done !== "function") throw new Error("refused: keymap=callback");
        if (!active || keyResolution !== null || keyResolver.running) { done({ ok: false, error: "refused: keymap=busy" }); return; }
        keyResolution = { keys: keys, done: done };
        keyDeadline.start();
        readDevices();
    }

    function finishKeys(value) {
        const pending = keyResolution;
        keyResolution = null;
        keyDeadline.stop();
        if (pending !== null) pending.done(value);
    }

    Process {
        id: keyResolver
        property var completion: null
        property string requestText: ""
        command: ["python3", "-I", Quickshell.shellDir + "/../bin/lib/xkb-keys.py"]
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH") || "/usr/bin:/bin", LANG: "C.UTF-8" })
        stdinEnabled: true
        stdout: StdioCollector { id: keyOutput }
        onStarted: { write(requestText); stdinEnabled = false; }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            keyDeadline.stop();
            const done = completion;
            completion = null;
            const value = done !== null && done.code === 0 && root.keyResolution !== null
                ? State.resolvedKeys(keyOutput.text, root.keyResolution.keys.length, true)
                : { ok: false, error: "refused: keymap=resolver-failed" };
            root.finishKeys(value);
        }
    }
    Timer {
        id: keyDeadline
        interval: 2000
        onTriggered: {
            root.finishKeys({ ok: false, error: "refused: keymap=timeout" });
            keyResolver.running = false;
        }
    }

    function readOptions() {
        if (!active) return;
        const argv = State.optionsRequest(written);
        if (argv === null) {
            overriddenRows = [];
            return;
        }
        optionsReader.read(argv, written);
    }

    function readUserValues() {
        if (!active) return;
        userValuesReader.read(State.USER_VALUES_REQUEST, written);
    }

    function readBinds() {
        if (!active) return;
        bindsReader.read(State.BINDS_REQUEST, null);
        userBindsReader.read(State.USER_BINDS_REQUEST, null);
    }

    // The user's binds of KEY, as hyprlandKey writes it: [{ file, line,
    // text, removable, place, config }], `place` the file as a notice names
    // it and `config` its path under the configuration directory, which
    // `vgshell edit` opens, or "" for a file outside it.
    function userBindsFor(key) {
        if (root.userBindRows === null) return [];
        const home = Quickshell.env("HOME") || "";
        return root.userBindRows.filter(row => row.key === key)
            .map(row => ({ file: row.file, line: row.line, text: row.text, removable: row.removable, place: State.bindPlace(row.file, home),
                config: row.file.indexOf(root.configDir + "/") === 0 ? row.file.slice(root.configDir.length + 1) : "" }));
    }

    // Run `vgshell hypr ARGS`, a bind line edit, then reload Hyprland, and
    // answer DONE with { ok: true, said } or { ok: false, error }; one edit
    // at a time.
    function editBinds(args, done) {
        if (bindEdit !== null) { done({ ok: false, error: "refused: user-bind=busy" }); return; }
        bindEdit = { done: done, said: "" };
        bindEditor.command = [Quickshell.shellDir + "/../bin/vgshell", "hypr"].concat(args);
        bindEditor.running = true;
    }

    function finishEdit(value) {
        const pending = bindEdit;
        bindEdit = null;
        if (pending !== null) pending.done(value);
    }

    // Each reading is replaced only when it changed, so a reload that
    // changes nothing renders dependents no further.
    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    function overriddenFor(id) {
        if (root.overriddenRows === null && root.optionConflicts.length === 0) return null;
        const rows = (root.overriddenRows === null ? [] : root.overriddenRows).concat(root.optionConflicts);
        const paths = rows.filter(row => row.id === id).map(row => row.path);
        return Logic.frozenJson(paths.filter((path, i, all) => all.indexOf(path) === i));
    }

    function userValuesFor(id) {
        if (root.userValueRows === null) return null;
        return Logic.frozenJson(root.userValueRows.filter(row => row.id === id).map(row => ({ path: row.path, value: row.value })));
    }

    Connections {
        target: root.active ? Hyprland : null
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                root.readDevices();
                root.readOptions();
                root.readUserValues();
                root.readBinds();
            } else if (event.name === "activelayout") {
                root.readDevices();
            }
        }
    }

    FolderListModel {
        folder: "file:///dev/input"
        showDirs: false
        nameFilters: ["event*"]
        onCountChanged: root.readDevices()
    }

    HyprctlReader {
        id: devicesReader
        label: "devices"
        onReadDone: (request, text, failure) => {
            if (!root.active) return;
            const facts = request === "keys" && root.keyResolution !== null
                ? State.keyFacts(text, root.keyResolution.keys) : null;
            const read = failure === "" ? facts !== null ? facts : State.devicesState(text)
                : { ok: false, error: failure };
            if (!read.ok) {
                root.devices = null;
                root.devicesFailure = read.error;
                console.error("hyprland: " + read.error);
            } else {
                root.devicesFailure = "";
                if (!root.same(read.devices, root.devices)) root.devices = read.devices;
            }
            if (root.keyResolution !== null) {
                const keyFacts = facts === null ? { ok: false, error: "refused: keymap=request" } : facts;
                if (!keyFacts.ok) root.finishKeys(keyFacts);
                else {
                    const wire = JSON.stringify(keyFacts.request) + "\n";
                    if (keyResolution.resolving) {
                        if (wire !== keyResolver.requestText) {
                            root.finishKeys({ ok: false, error: "refused: keymap=layout-changed" });
                            keyResolver.running = false;
                        }
                    } else {
                        keyResolution = Object.assign({}, keyResolution, { resolving: true });
                        keyResolver.requestText = wire;
                        keyResolver.stdinEnabled = true;
                        keyResolver.running = true;
                        keyDeadline.start();
                    }
                }
            }
        }
    }

    HyprctlReader {
        id: optionsReader
        label: "options"
        onReadDone: (asked, text, failure) => {
            if (!root.active) return;
            const read = failure === "" ? State.overridden(asked, text) : { ok: false, error: failure };
            if (!read.ok) {
                root.overriddenRows = null;
                console.error("hyprland: " + read.error);
            } else {
                for (const error of read.errors) console.error("hyprland: " + error);
                if (!root.same(read.overridden, root.overriddenRows)) root.overriddenRows = read.overridden;
            }
        }
    }

    // The layer's answer is an error's text, so hyprctl exits 7 with it:
    // the reply is judged whatever the exit, and the exit is named only
    // beside a reply that holds no answer.
    HyprctlReader {
        id: userValuesReader
        label: "user-values"
        onReadDone: (asked, text, failure) => {
            if (!root.active) return;
            const read = State.userValues(asked, text);
            if (!read.ok) {
                root.userValueRows = null;
                console.error("hyprland: " + read.error + (failure === "" ? "" : " " + failure));
            } else if (!root.same(read.values, root.userValueRows)) {
                root.userValueRows = read.values;
            }
        }
    }

    // The layer's record of the user's binds is an error's text, as the
    // user values are.
    HyprctlReader {
        id: userBindsReader
        label: "user-binds"
        onReadDone: (request, text, failure) => {
            if (!root.active) return;
            const read = State.userBinds(text, root.hyprDir);
            if (!read.ok) {
                root.userBindRows = null;
                console.error("hyprland: " + read.error + (failure === "" ? "" : " " + failure));
            } else if (!root.same(read.binds, root.userBindRows)) {
                root.userBindRows = read.binds;
            }
        }
    }

    Process {
        id: bindEditor
        property var completion: null
        stdout: StdioCollector { id: bindEditOut }
        stderr: StdioCollector { id: bindEditErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            const said = bindEditOut.text.trim();
            if (done === null || done.code !== 0) {
                const error = bindEditErr.text.trim().split("\n")[0].replace(/^vgshell: /, "");
                console.error("hyprland: user-bind edit " + (done === null ? "start=failed" : "status=" + done.code + " " + error));
                root.finishEdit({ ok: false, error: error === "" ? "refused: user-bind=edit-failed" : error });
                return;
            }
            root.bindEdit = Object.assign({}, root.bindEdit, { said: said });
            bindReloader.running = true;
        }
    }

    Process {
        id: bindReloader
        command: ["hyprctl", "reload", "config-only"]
        property var completion: null
        stdout: StdioCollector { id: bindReloadOut }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            const said = root.bindEdit === null ? "" : root.bindEdit.said;
            if (done === null || done.code !== 0 || bindReloadOut.text.trim() !== "ok")
                console.error("hyprland: user-bind reload=failed reply=" + JSON.stringify(bindReloadOut.text.trim()));
            root.finishEdit({ ok: true, said: said });
        }
    }

    HyprctlReader {
        id: bindsReader
        label: "binds"
        onReadDone: (request, text, failure) => {
            if (!root.active) return;
            const read = failure === "" ? State.foreignBinds(text, root.layerBinds) : { ok: false, error: failure };
            if (!read.ok) {
                root.foreignKeys = null;
                root.bindsFailure = read.error;
                console.error("hyprland: " + read.error);
            } else {
                root.bindsFailure = "";
                if (!root.same(read.keys, root.foreignKeys)) root.foreignKeys = read.keys;
            }
        }
    }
}
