import QtQuick
import Quickshell
import Quickshell.Hyprland

// The pads' one owner: it registers each pad's shortcut, `pad-<name>`, as
// the `pads` setting lists them, follows each pad's window from Hyprland's
// events, starts a pad's app, and publishes which pad each screen shows
// and the screens a pad may open on.
//
// The core's Hyprland layer maps a window of a pad's class hidden into the
// pad's special workspace, `shell.compositor.padWorkspace(name)`, and
// defines the toggle `shell.compositor.togglePad` sends, which shows or
// hides the pad in one Lua call and answers `vgs-pad=<key>` when it cannot
// (docs/architecture/hyprland.md). A press sends the toggle. A pad whose
// workspace holds no window then starts its app, and the service sends the
// toggle again once Hyprland reports the window, only while the user still
// wants the pad, so a press never shows an empty pad; presses meanwhile
// flip that wish. A start that maps no window within startMs ends in one
// toast. A pad the layer does not hold, as one whose window class another
// pad holds, starts nothing and says why in one toast.
Item {
    id: root

    property var shell: null

    // How long a pad's app may take to map its window: a terminal maps in
    // well under a second; a large app on a loaded machine in a few.
    readonly property int startMs: 15000

    readonly property var pads: shell === null ? [] : shell.settings.pads
    // Pad name -> { address, phase, wanted, deadline }: address "0x…" or ""
    // while the service knows no window of the pad; phase `idle`, `asking`
    // while the first toggle of a press without a known window waits for
    // Hyprland's answer, or `starting` while the app it started maps no
    // window. Plain data, read by no binding.
    property var tracked: ({})
    // Pad name -> the disposer of its shortcut.
    property var registered: ({})
    // Monitor name -> the name of the pad it shows.
    property var shownOn: ({})
    // Whether the service began, and whether it read Hyprland's windows
    // once with every reply in, which preloading waits for.
    property bool started: false
    property bool preloaded: false

    // The toplevels Quickshell holds, read once each carries Hyprland's
    // reply and they are as many as the workspaces' reply counts, so an
    // empty list before Quickshell's first reply reads as unread.
    readonly property var toplevels: Hyprland.toplevels.values.map(t => t.lastIpcObject)
    readonly property int listedWindows: Hyprland.workspaces.values.reduce((n, w) => n + (w.lastIpcObject !== null && typeof w.lastIpcObject.windows === "number" ? w.lastIpcObject.windows : 0), 0)
    readonly property bool toplevelsRead: toplevels.length >= listedWindows && toplevels.every(o => o !== null && typeof o === "object" && typeof o.address === "string")
    readonly property var screenNames: shell === null ? [] : shell.screens.all.map(screen => screen.name)

    // The first `shell` starts the service once the bindings on it hold its
    // values: a handler of `shell` runs before `pads` reads the new one.
    onShellChanged: if (shell !== null && !started) Qt.callLater(begin)

    function begin() {
        if (started || shell === null) return;
        started = true;
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
        sync();
        publishScreens();
        readShown();
        // Quickshell read the toplevels as it connected, so they may be
        // read already, and toplevelsRead then never changes.
        adopt();
    }
    onPadsChanged: sync()
    onToplevelsReadChanged: adopt()
    onScreenNamesChanged: publishScreens()

    function padOf(name) {
        return pads.find(pad => pad.name === name);
    }

    function stateOf(name) {
        if (tracked[name] === undefined) tracked[name] = { address: "", phase: "idle", wanted: false, deadline: 0 };
        return tracked[name];
    }

    // Register a shortcut for each listed pad and dispose of a removed
    // pad's, and start a new preloaded pad's app. The layer moves a removed
    // pad's window to the focused workspace as it loads.
    function sync() {
        if (shell === null || !started) return;
        const names = pads.map(pad => pad.name);
        for (const name of Object.keys(registered)) {
            if (names.indexOf(name) !== -1) continue;
            registered[name]();
            delete registered[name];
            delete tracked[name];
        }
        for (const pad of pads) {
            if (registered[pad.name] !== undefined) continue;
            const name = pad.name;
            registered[name] = shell.shortcut.register("pad-" + name, "Show or hide pad " + name, () => root.press(name));
            if (preloaded) preload(pad);
        }
        armDeadline();
    }

    // Each window Hyprland holds that the service does not track yet goes
    // to the pad of its class, or of the workspace it is in, on every read;
    // the first read with every reply in starts the preloaded pads.
    function adopt() {
        if (!toplevelsRead || !started) return;
        const known = Object.keys(tracked).map(name => tracked[name].address);
        for (const object of toplevels) {
            const address = object.address.toLowerCase();
            if (known.indexOf(address) !== -1) continue;
            const workspace = object.workspace === undefined ? "" : object.workspace.name;
            const pad = pads.find(p => p["class"] === object["class"]) || pads.find(p => shell.compositor.padWorkspace(p.name) === workspace);
            if (pad !== undefined) opened(address, workspace, pad);
        }
        if (preloaded) return;
        preloaded = true;
        for (const pad of pads) preload(pad);
    }

    function readShown() {
        const shown = {};
        for (const monitor of Hyprland.monitors.values) {
            const special = monitor.lastIpcObject.specialWorkspace;
            const name = special === undefined ? "" : padNameOf(special.name);
            if (name !== "") shown[monitor.name] = name;
        }
        shownOn = shown;
        publishShown();
    }

    function preload(pad) {
        const state = stateOf(pad.name);
        if (pad.preload === true && state.address === "" && state.phase === "idle") start(pad, false);
    }

    function press(name) {
        const pad = padOf(name);
        if (pad === undefined) return;
        const state = stateOf(name);
        switch (state.phase) {
        case "asking":
        case "starting":
            state.wanted = !state.wanted;
            return;
        case "idle":
            break;
        default:
            throw new Error("scratchpads: pad " + name + " phase " + JSON.stringify(state.phase) + " is not one of idle, asking, starting");
        }
        if (state.address === "") {
            state.phase = "asking";
            state.wanted = true;
        }
        toggle(pad, answer => root.answered(name, answer));
    }

    // Hyprland's answer to a press's toggle, by the layer's refusal key.
    function answered(name, answer) {
        const pad = padOf(name);
        if (pad === undefined) return;
        const state = stateOf(name);
        const asking = state.phase === "asking";
        if (asking) state.phase = "idle";
        const match = /vgs-pad=([a-z-]+)/.exec(answer);
        switch (answer === "ok" ? "ok" : match === null ? "failed" : match[1]) {
        case "ok":
            // A window the service did not know was in the pad: shown, and
            // hidden again when later presses took the wish back.
            if (asking && !state.wanted) toggle(pad, null);
            return;
        case "no-window":
            // A window moved out of the pad's workspace comes back into it;
            // with none, the app starts.
            if (state.address === "") {
                start(pad, asking ? state.wanted : true);
                return;
            }
            shell.compositor.moveWindowToWorkspace(state.address, shell.compositor.padWorkspace(name));
            toggle(pad, null);
            return;
        case "no-pad":
            shell.toasts.show({
                title: "Pad " + name + " cannot open",
                message: "Another pad uses its window class, " + pad["class"] + ". Give each pad its own window class in Plugins, and an app that opens its window with it.",
                tone: "warning"
            });
            return;
        default:
            console.warn("scratchpads: pad=" + name + " toggle answered " + JSON.stringify(answer));
        }
    }

    function start(pad, wanted) {
        const reply = shell.run.detached(["sh", "-c", pad.command]);
        if (reply !== "ok") {
            console.warn("scratchpads: pad=" + pad.name + " start " + reply);
            return;
        }
        const state = stateOf(pad.name);
        state.phase = "starting";
        state.wanted = wanted;
        state.deadline = Date.now() + startMs;
        armDeadline();
    }

    // A screen the pad names that no longer exists opens it on the focused
    // one, as `focused` does. DONE, or a log line when null, takes the
    // answer.
    function toggle(pad, done) {
        const screen = screenNames.indexOf(pad.screen) === -1 ? "" : pad.screen;
        const reply = shell.compositor.togglePad(pad.name, screen, answer => {
            if (done !== null) done(answer);
            else if (answer !== "ok") console.warn("scratchpads: pad=" + pad.name + " toggle answered " + JSON.stringify(answer));
        });
        if (reply === "ok") return;
        console.warn("scratchpads: pad=" + pad.name + " toggle " + reply);
        const state = stateOf(pad.name);
        if (state.phase === "asking") state.phase = "idle";
    }

    function padNameOf(workspace) {
        const prefix = shell.compositor.padWorkspace("");
        return workspace.indexOf(prefix) === 0 ? workspace.slice(prefix.length) : "";
    }

    // A window of PAD mapped or was found: the pad holds it. One that
    // mapped before the layer held the pad's rule, as a new pad's app
    // started before the layer was written again, is outside the pad's
    // workspace and moves into it. A start the user still wants shows it.
    function opened(address, workspace, pad) {
        const state = stateOf(pad.name);
        if (state.address !== "" && state.address !== address) return;
        state.address = address;
        const home = shell.compositor.padWorkspace(pad.name);
        if (workspace !== home) shell.compositor.moveWindowToWorkspace(address, home);
        if (state.phase !== "starting") return;
        state.phase = "idle";
        armDeadline();
        if (state.wanted) toggle(pad, null);
    }

    function closed(address) {
        for (const name of Object.keys(tracked))
            if (tracked[name].address === address) tracked[name].address = "";
    }

    function special(workspace, monitor) {
        const shown = Object.assign({}, shownOn);
        delete shown[monitor];
        const name = padNameOf(workspace);
        if (name !== "") shown[monitor] = name;
        shownOn = shown;
        publishShown();
    }

    function publishShown() {
        const reply = shell.status.set("shown", shownOn);
        if (reply !== "ok") console.warn("scratchpads: status shown " + reply);
    }

    function publishScreens() {
        if (shell === null) return;
        const choices = [{ label: "Focused screen", value: "focused" }].concat(screenNames.map(name => ({ label: name, value: name })));
        const reply = shell.status.set("screens", choices);
        if (reply !== "ok") console.warn("scratchpads: status screens " + reply);
    }

    // The deadline of the earliest start still waiting for its window.
    function armDeadline() {
        const waiting = Object.keys(tracked).filter(name => tracked[name].phase === "starting").map(name => tracked[name].deadline);
        if (waiting.length === 0) {
            deadline.stop();
            return;
        }
        deadline.interval = Math.max(1, Math.min.apply(null, waiting) - Date.now());
        deadline.restart();
    }

    function expire() {
        const now = Date.now();
        for (const name of Object.keys(tracked)) {
            const state = tracked[name];
            if (state.phase !== "starting" || state.deadline > now) continue;
            state.phase = "idle";
            state.wanted = false;
            const pad = padOf(name);
            shell.toasts.show({
                title: "Pad " + name + " did not open",
                message: "Its app showed no window of class " + (pad === undefined ? "" : pad["class"]) + ". Check the app and window class of the pad in Plugins.",
                tone: "warning"
            });
        }
        armDeadline();
    }

    Timer {
        id: deadline
        repeat: false
        onTriggered: root.expire()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.shell === null) return;
            const data = String(event.data);
            switch (event.name) {
            case "openwindow": {
                const parts = data.split(",");
                const pad = parts.length >= 3 ? root.pads.find(p => p["class"] === parts[2]) : undefined;
                if (pad !== undefined) root.opened("0x" + parts[0].toLowerCase(), parts[1], pad);
                // Quickshell holds no reply for a window that opens before
                // the start's read lands, so that read is asked again.
                if (!root.preloaded) Hyprland.refreshToplevels();
                break;
            }
            case "closewindow":
                root.closed("0x" + data.toLowerCase());
                break;
            case "activespecial": {
                const at = data.lastIndexOf(",");
                if (at !== -1) root.special(data.slice(0, at), data.slice(at + 1));
                break;
            }
            }
        }
    }
}
