import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "HyprlandState.js" as State
import "PluginLogic.js" as Logic

// Owns the reads behind the `hyprland` capability: Hyprland's input
// devices, its value of each option a manifest may map a setting to, the
// options the layer wrote that read back otherwise, the values the user's
// configuration gave them, the keys something other than the
// layer binds and where the user's configuration binds each, and the
// permission rules and options the user's configuration sets. It also runs
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

    // Whether anything needs the reads: the layer publisher or a plugin
    // holds `hyprland`, or key capture asked who holds a key.
    property bool active: false
    // HyprlandLayer.qml binds these from its render: the options written,
    // the applied groups' options written for the core, under id "",
    // option conflicts, and the descriptions of the binds written.
    property var written: []
    property var appearanceWritten: []
    property var optionConflicts: []
    property var layerBinds: []
    // The layer's permission state, HyprlandLayer.permissionLines' `state`,
    // which HyprlandLayer.qml binds; the declaring plugin reads its `state`.
    property var permissionState: null
    // State.userPermissions' reply: the permission rules and options the
    // user's configuration set as Hyprland last loaded it, which the layer
    // records (HyprlandLayer.USER_PERMISSIONS); null until the first read
    // answers. Read on activation and after each reload.
    property var userPermissions: null

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
    // State.optionValues' values, read with overriddenRows; null alike.
    property var optionValues: null
    readonly property var displayWake: Logic.frozenJson(State.displayWake(optionValues))
    property var foreignKeys: null
    // Only key and description from the same binds reply. Settings names the
    // user's action without copying its dispatcher or command into a hint.
    property var foreignBindRows: null
    // [{ id, path, value }] for each written option the user's
    // configuration gave another value, which the layer then replaced; null
    // while unread or after a failed read.
    property var userValueRows: null
    // The last binds read's keyed failure, "" once one succeeds.
    property string bindsFailure: ""
    // State.userBinds' binds, where the user's configuration binds each
    // key; null while unread or after a failed read.
    property var userBindRows: null
    // Whether a re-read of the binds reply (foreignKeys, foreignBindRows)
    // or of the user's binds (userBindRows) is out. A re-read keeps the
    // last answer readable, so an open window keeps naming the user's line
    // through a reload; the layer admits keys only from readings that are
    // not pending, so it never takes old user binds under a new keymap
    // revision.
    property bool bindsPending: false
    property bool userBindsPending: false
    // The bind line edit running, { done, said }, or null.
    property var bindEdit: null
    // The user's configuration directory and Hyprland directory, as
    // bin/vgshell names them.
    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") || "") + "/.config"
    readonly property string hyprDir: configDir + "/hypr"
    property var keyResolution: null
    property int keyRequestSerial: 0
    readonly property bool resolvingKeys: keyResolution !== null || keyResolver.running
    property int keymapRevision: 0

    onActiveChanged: {
        if (active) {
            readDevices();
            readOptions();
            readUserValues();
            readBinds();
            readPermissions();
            return;
        }
        const token = keyResolution === null ? null : keyResolution.token;
        const helperToken = keyResolver.requestToken;
        finishKeys(token, { ok: false, error: "refused: keymap=inactive" });
        if (keyResolver.requestToken === helperToken) keyResolver.running = false;
        devices = null;
        devicesFailure = "";
        overriddenRows = null;
        optionValues = null;
        userValueRows = null;
        foreignKeys = null;
        foreignBindRows = null;
        bindsFailure = "";
        userBindRows = null;
        bindsPending = false;
        userBindsPending = false;
        userPermissions = null;
    }

    // The capability for one instance; it holds nothing to release.
    function provider(ctx) {
        return Object.freeze({
            get overridden() { return root.overriddenFor(ctx.id); },
            get userValues() { return root.userValuesFor(ctx.id); },
            get values() { return root.optionValues === null ? null : Logic.frozenJson(State.unwrittenValues(ctx.manifest.hyprland === undefined ? undefined : ctx.manifest.hyprland.options, root.written, ctx.id, root.optionValues, root.appearanceWritten)); },
            get displayWake() { return root.displayWake; },
            get devices() { return root.devices === null ? null : Logic.frozenJson(root.devices); },
            get foreignBinds() { return root.foreignKeys === null ? null : Logic.frozenJson(root.foreignKeys); },
            get permissions() { return root.permissionState !== null && root.permissionState.id === ctx.id ? root.permissionState.state : null; },
            resolveKeys: (keys, done) => {
                if (!ctx.active) return;
                root.resolveKeys(keys, value => { if (ctx.active) done(State.pluginKeys(value)); });
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
            keyResolution === null ? null : keyResolution.token);
    }

    function resolveKeys(keys, done) {
        if (typeof done !== "function") throw new Error("refused: keymap=callback");
        if (!active || keyResolution !== null || keyResolver.running) { done({ ok: false, error: "refused: keymap=busy" }); return; }
        // The token crosses HyprctlReader's `var` signal argument, a QVariant,
        // which does not promise a plain object's reference identity. A
        // string never reused compares by value on every side of it.
        keyRequestSerial++;
        const token = "keys:" + keyRequestSerial;
        keyResolution = { token: token, keys: keys, done: done };
        readDevices();
    }

    function ownsKeys(token) {
        return token !== null && keyResolution !== null && keyResolution.token === token;
    }

    function finishKeys(token, value) {
        if (!ownsKeys(token)) return;
        const pending = keyResolution;
        keyResolution = null;
        pending.done(value);
    }

    Process {
        id: keyResolver
        property var completion: null
        property var requestToken: null
        property string requestText: ""
        command: ["python3", "-I", Quickshell.shellDir + "/../bin/lib/xkb-keys.py"]
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH") || "/usr/bin:/bin", LANG: "C.UTF-8" })
        stdinEnabled: true
        stdout: StdioCollector { id: keyOutput }
        onStarted: { write(requestText); stdinEnabled = false; }
        onExited: (code, status) => { completion = { token: requestToken, code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            const token = done === null ? requestToken : done.token;
            completion = null;
            if (requestToken === token) requestToken = null;
            if (!root.ownsKeys(token)) return;
            const value = done !== null && (done.code === 0 || done.code === 1)
                ? State.resolvedKeys(keyOutput.text, root.keyResolution.keys.length, true)
                : { ok: false, error: "refused: keymap=resolver-failed" };
            root.finishKeys(token, done !== null && done.code === 1 && value.ok
                ? { ok: false, error: "refused: keymap=resolver-failed" } : value);
        }
    }
    function readOptions() {
        if (!active) return;
        optionsReader.read(State.OPTIONS_REQUEST, written.concat(appearanceWritten));
    }

    function readUserValues() {
        if (!active) return;
        userValuesReader.read(State.USER_VALUES_REQUEST, written.concat(appearanceWritten));
    }

    function readBinds() {
        if (!active) return;
        // HyprctlReader drops an in-flight reply when a new read is queued,
        // so each reader's next answer is the one for this read.
        bindsPending = true;
        userBindsPending = true;
        bindsReader.read(State.BINDS_REQUEST, null);
        userBindsReader.read(State.USER_BINDS_REQUEST, null);
    }

    function readPermissions() {
        if (!active) return;
        userPermissionsReader.read(State.USER_PERMISSIONS_REQUEST, null);
    }

    // The user's binds of KEY, as hyprlandKey writes it: [{ file, line,
    // text, removable, place, config }], `place` the file as a notice names
    // it and `config` its path under the configuration directory, which
    // `vgshell edit` opens, or "" for a file outside it.
    function userBindsFor(key, identities) {
        const home = Quickshell.env("HOME") || "";
        return State.matchingUserBinds(root.userBindRows, key, identities)
            .map(row => ({ key: row.key, file: row.file, line: row.line, text: row.text, removable: row.removable, place: State.bindPlace(row.file, home),
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

    // A plugin's own rows and the core's, id "": the Appearance options
    // every holder may show.
    function overriddenFor(id) {
        if (root.overriddenRows === null && root.optionConflicts.length === 0) return null;
        const rows = (root.overriddenRows === null ? [] : root.overriddenRows).concat(root.optionConflicts);
        const paths = rows.filter(row => row.id === id || row.id === "").map(row => row.path);
        return Logic.frozenJson(paths.filter((path, i, all) => all.indexOf(path) === i));
    }

    function userValuesFor(id) {
        if (root.userValueRows === null) return null;
        return Logic.frozenJson(root.userValueRows.filter(row => row.id === id || row.id === "").map(row => ({ path: row.path, value: row.value })));
    }

    Connections {
        target: root.active ? Hyprland : null
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                // Hyprland 0.57 builds its bind map from the global input:kb_*
                // options at group 0 and rebuilds it only through
                // InputManager::setKeyboardLayout on a configuration refresh
                // (src/keybinds/Manager.cpp updateXKBTranslationState and
                // src/managers/input/InputManager.cpp, Hyprland 0aa6745).
                // A layout switch moves only a device's group, so only a
                // reload can change a resolved key identity.
                root.keymapRevision++;
                root.readDevices();
                root.readOptions();
                root.readUserValues();
                root.readBinds();
                root.readPermissions();
            } else if (event.name === "activelayout") {
                root.readDevices();
            }
        }
    }

    // Hyprland can omit activelayout after a keymap reload. Read after
    // VGS's successful queued switch even when that event is absent.
    Connections {
        target: Compositor
        function onKeyboardLayoutSwitched() { root.readDevices(); }
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
            // The reader's nonnull request is one opaque resolution token.
            // Expired key batches never enter the single-devices parser.
            const keysReply = request !== null;
            if (keysReply && !root.ownsKeys(request)) return;
            const facts = keysReply ? State.keyFacts(text, root.keyResolution.keys) : null;
            // A map policy refusal says nothing about device availability.
            // Read devices normally after completing that key request.
            const read = failure === "" ? facts !== null ? facts.ok ? facts : null : State.devicesState(text)
                : { ok: false, error: failure };
            if (read !== null && !read.ok) {
                root.devices = null;
                root.devicesFailure = read.error;
                console.error("hyprland: " + read.error);
            } else if (read !== null) {
                root.devicesFailure = "";
                if (!root.same(read.devices, root.devices)) root.devices = read.devices;
            }
            if (keysReply) {
                const keyFacts = failure === "" ? facts : { ok: false, error: failure };
                if (!keyFacts.ok) {
                    root.finishKeys(request, keyFacts);
                    Qt.callLater(root.readDevices);
                }
                else {
                    const wire = JSON.stringify(keyFacts.request) + "\n";
                    if (keyResolution.resolving) {
                        if (wire !== keyResolver.requestText) {
                            root.finishKeys(request, { ok: false, error: "refused: keymap=layout-changed" });
                            if (keyResolver.requestToken === request) keyResolver.running = false;
                        }
                    } else {
                        keyResolution = Object.assign({}, keyResolution, { resolving: true });
                        keyResolver.requestToken = request;
                        keyResolver.requestText = wire;
                        keyResolver.stdinEnabled = true;
                        // Process.started supplies stdin on the QML thread:
                        // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
                        // A wall timer here also times that thread's delivery
                        // and the scheduler, not just XKB work. The helper owns
                        // its CPU bound; retain this request until its answer.
                        keyResolver.running = true;
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
            const read = failure === "" ? State.optionValues(text) : { ok: false, error: failure };
            if (!read.ok) {
                root.overriddenRows = null;
                root.optionValues = null;
                console.error("hyprland: " + read.error);
            } else {
                for (const error of read.errors) console.error("hyprland: " + error);
                const overridden = State.overridden(asked, read.values);
                if (!root.same(overridden, root.overriddenRows)) root.overriddenRows = overridden;
                if (!root.same(read.values, root.optionValues)) root.optionValues = read.values;
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
            root.userBindsPending = false;
        }
    }

    // The layer's record of the user's permission rules is an error's text,
    // as the user values are.
    HyprctlReader {
        id: userPermissionsReader
        label: "user-permissions"
        onReadDone: (request, text, failure) => {
            if (!root.active) return;
            const read = State.userPermissions(text);
            if (!read.ok) console.error("hyprland: " + read.error + (failure === "" ? "" : " " + failure));
            if (!root.same(read, root.userPermissions)) root.userPermissions = read;
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
                root.foreignBindRows = null;
                root.bindsFailure = read.error;
                console.error("hyprland: " + read.error);
            } else {
                root.bindsFailure = "";
                if (!root.same(read.binds, root.foreignBindRows)) root.foreignBindRows = read.binds;
                if (!root.same(read.keys, root.foreignKeys)) root.foreignKeys = read.keys;
            }
            root.bindsPending = false;
        }
    }
}
