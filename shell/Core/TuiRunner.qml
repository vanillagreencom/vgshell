import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "PluginLogic.js" as Logic

// Owns the `tui` capability's provider, the list of floating TUIs it
// publishes, the launcher state and every launch process it starts: one
// `bin/vgshell-tui launch` per accepted request and at most one
// `bin/vgshell-tui check` probe. TuiRecords owns the record listing, reaper and
// one `bin/vgshell-tui wait` process per live run. PluginLogic decides which
// TUI a request names, whether its plugin is enabled, the arguments, whether
// the key is busy or the launcher state refuses it, the launcher's argv, how
// each exit moves the state, what the records say, which waits run and what
// each `done` receives. The launcher forks the terminal into a session of its
// own and exits once the presenter wrote its record, so a terminal outlives
// the shell that opened it. Each run's `done` belongs to the lifetime of the
// instance that asked: a destroyed instance's callback is dropped and its
// run still ends. The core's own request, through openCore, holds its `done`
// for the shell's life.
Scope {
    id: root

    // Launchers still running, each a Process carrying its TUI's `key` and
    // `run`. Replaced whole on every change.
    property var launching: []
    // Launches whose run has no record yet and whose launcher did not fail,
    // each { key, run }: the key stays busy until the record appears.
    property var pending: []
    // Each plugin script's key, and each plugin's file action editor key,
    // -> the arguments of the latest run this shell started for it, so a
    // request for a live key with other arguments is told apart from a
    // second press of the same one (PluginLogic.tuiOwnShownAnswer). One
    // entry per such key, each replaced by the next start. Replaced whole.
    property var startedArgs: ({})
    // One of PluginLogic.TUI_LAUNCHER_STATES: the first probe answers it,
    // and every later probe and launch moves it.
    property string launcher: "unknown"
    property int launches: 0

    // The directory bin/vgshell-tui writes the records in. `bin/vgshell run`
    // creates it before the shell starts: FolderListModel lists the working
    // directory for a folder that is absent.
    readonly property string recordDir: Quickshell.env("XDG_RUNTIME_DIR") + "/vgshell/tui"
    // The core's bin/ beside the shell directory, where a core TUI's command
    // lives: the shell's PATH need not hold it.
    readonly property string coreBin: Quickshell.shellDir + "/../bin"

    // Whether any run is live: launching or running, as the busy keys
    // read. Notices holds the restart notice while it is, so the notice
    // never comes up in the middle of a setup flow.
    readonly property bool live: Logic.tuiBusyKeys(recordStore.runs, pending.map(p => p.key)).length > 0

    // Every listed TUI: the core's and every enabled plugin's, as
    // PluginLogic.tuiEntries returns them.
    readonly property var entries: Logic.tuiEntries(Registry.manifests, enabledIds(), Logic.CORE_TUIS)

    Component.onCompleted: {
        probe();
    }

    // Every enabled plugin id, read through Registry.isEnabled so a binding
    // on the result follows the configuration and the manifests.
    function enabledIds() {
        return Object.keys(Registry.manifests).filter(id => Registry.isEnabled(id));
    }

    function provider(ctx) {
        return {
            run: (name, args, done) => root.run(ctx, name, args, done),
            get entries() { return root.entries; },
            open: key => root.open(key),
            edit: (path, line) => root.edit(path, line),
            get state() { return root.stateOf(ctx); }
        };
    }

    // run: one of the calling plugin's own declared scripts, from the
    // snapshot of the revision its instance runs. `done`, when given,
    // receives { code, reason } once the run ends or its launcher fails.
    // Judged by request, as runFor is, so a script that lacks a command it
    // needs raises the requirement notice for those commands and starts,
    // with ARGS and `done`, once the notice closes with them found (resume).
    // Answers as start does: the caller maps a busy refusal itself.
    function run(ctx, name, args, done) {
        if (done !== undefined && typeof done !== "function")
            throw new Error("refused: tui=" + Logic.tuiLabel(name) + " done=not-a-function");
        return request(ctx.id, ctx.manifest, { name: name, args: args, ctx: ctx, done: done });
    }

    // runFor: plugin ID's own declared script NAME, with ARGS after it as
    // tuiRun takes them, absent for none, and no
    // `done`, for the `manager` capability's step runner
    // (Capabilities.managerStep): its act on a status action (D061), whose
    // row action hands the row's id as the one argument, and
    // its open of a listed setup screen, the Settings page's Setup button.
    // Judged by request, as run is, so a disabled plugin's or an undeclared
    // script, or arguments tuiArgsValid refuses, are refused and one that lacks a required command raises the
    // requirement notice for those commands, for both steps. Answers `ok`
    // when the request starts the TUI or focuses its live window of the same
    // arguments, and `reason=busy-other` when that window is another row's,
    // as PluginLogic.tuiOwnShownAnswer decides. The plugin reads the run's end
    // from its `state`.
    function runFor(id, name, args) {
        const answer = request(id, Registry.manifests[id], { name: name, args: args, ctx: null, done: undefined });
        return Logic.tuiOwnShownAnswer(id, name, answer, args, startedArgs);
    }

    // The one judge of a plugin's own script request, run's and runFor's:
    // PluginLogic.tuiRunFor against the plugin's missing commands. HELD is
    // { name, args, ctx, done }, ctx null and done undefined for a request
    // no instance made. A script that lacks a command it needs hands HELD
    // to the notice for the commands it lacks, which gives it back to
    // resume.
    function request(id, manifest, held) {
        const launch = Logic.tuiRunFor(manifest, Registry.isEnabled(id), Registry.sourceDir, runner(), held.name, Notices.missingOf(id), held.args);
        if (launch.kind === "install") return Notices.raiseHeld(id, launch.commands, held);
        const answer = start(launch, held.ctx, held.done);
        if (launch.ok) startedArgs = Object.assign({}, startedArgs, { [launch.key]: held.args === undefined ? [] : held.args.slice() });
        return answer;
    }

    // resume: plugin ID's HELD request, once its requirement notice closed
    // with the commands found (Notices.resume). The asking instance's
    // snapshot and `done` run while that instance lives; otherwise the
    // registered manifest runs the script with no instance. A request that
    // does not start ends its `done` with `unstarted`, judged on start's own
    // answer: a busy key focuses a window, but starts no run to end.
    function resume(id, held) {
        const live = held.ctx !== null && held.ctx.active;
        const answer = live
            ? request(id, held.ctx.manifest, held)
            : request(id, Registry.manifests[id], { name: held.name, args: held.args, ctx: null, done: undefined });
        if (answer !== "ok") unstarted(held);
        return Logic.tuiOwnShownAnswer(id, held.name, answer, held.args, startedArgs);
    }

    // The end a held request's `done` receives when it never starts, so a
    // `done` run answered `ok` always receives one while its instance lives.
    // It reaches `done` as every run's end does (TuiRecords.handOver).
    function unstarted(held) {
        if (held.done !== undefined && held.ctx !== null && held.ctx.active)
            recordStore.handOver(held.ctx.id, held.done, { code: null, reason: "unstarted" });
    }

    // open: any listed TUI by key, with no arguments; the `openTui` IPC
    // function answers `ok` when the request starts the TUI or focuses its
    // live window. A plugin script that lacks a command it needs raises
    // the requirement notice for those commands instead, as request does,
    // and the notice opens the script once they are found (resume).
    function open(key) {
        const launch = Logic.tuiOpen(Registry.manifests, enabledIds(), Registry.sourceDir, coreBin, runner(), Logic.CORE_TUIS, Registry.ownerMissing, key);
        if (launch.kind === "install") return Notices.raiseHeld(launch.id, launch.commands, { name: launch.name, args: [], ctx: null, done: undefined });
        return Logic.tuiShownAnswer(key, start(launch, null, undefined));
    }

    // openCore: the core's own TUI NAME, listed or not, with ARGS after its
    // argv, for a core component such as the requirement notice. `done`
    // receives { code, reason } as run's does, and belongs to the shell's
    // lifetime, since the core has no instance to drop it with.
    function openCore(name, args, done) {
        return start(Logic.tuiCore(Logic.CORE_TUIS, coreBin, runner(), name, args), null, done);
    }

    // edit: the one route that opens a cited file or folder, a file
    // reference's (PageReference), a notice's link or `shell.tui.edit`'s,
    // as PluginLogic.editRoute decides: a file through the core editor TUI,
    // answered as open answers, so a live editor is raised, and a folder in
    // the default file manager.
    function edit(path, line) {
        const route = Logic.editRoute(path, line, Paths.home, Paths.configHome);
        if (!route.ok) return route.answer;
        if (route.kind === "folder") return Capabilities.runDetached(DesktopLaunch.open(route.path));
        return Logic.tuiShownAnswer("core/edit", openCore("edit", route.args));
    }

    // editFor: plugin ID's file action (PluginLogic.statusActionRequest),
    // PATH opened by edit's route, its editor run keyed as the plugin's
    // own, `<id>/edit`, so the plugin reads its end in its `state`
    // (PluginLogic.tuiStateNames) as it reads its own script's. A second
    // press for the same file raises the live editor; one for another file
    // while it is open answers `reason=busy-other`, as runFor does.
    function editFor(id, path) {
        const route = Logic.editRoute(path, undefined, Paths.home, Paths.configHome);
        if (!route.ok) return route.answer;
        if (route.kind === "folder") return Capabilities.runDetached(DesktopLaunch.open(route.path));
        const launch = Logic.tuiCore(Logic.CORE_TUIS, coreBin, runner(), "edit", route.args, id);
        const answer = start(launch, null, undefined);
        if (launch.ok) startedArgs = Object.assign({}, startedArgs, { [launch.key]: route.args.slice() });
        return Logic.tuiOwnShownAnswer(id, Logic.STATUS_FILE_TUI, answer, route.args, startedArgs);
    }

    // The state a request is judged against, with the id a launch gets:
    // the time and a count, unique across the shell's restarts.
    function runner() {
        launches += 1;
        return {
            launcher: launcher,
            busy: Logic.tuiBusyKeys(recordStore.runs, pending.map(p => p.key)),
            run: Date.now() + "-" + launches
        };
    }

    // The run id of core TUI NAME's latest ended run, "" before one ended,
    // whoever opened it. Bindable: a core owner whose state a run changes
    // reads it again when this changes, a run the launcher opened included.
    function coreEnded(name) {
        const keys = recordStore.runs.keys;
        const key = "core/" + name;
        return Object.prototype.hasOwnProperty.call(keys, key) && keys[key].ended !== null ? keys[key].ended.run : "";
    }

    // The calling plugin's own TUIs' state, one frozen copy per read: its
    // scripts' and its file actions' editor runs (PluginLogic.tuiStateNames).
    function stateOf(ctx) {
        return frozen(Logic.tuiState(recordStore.runs, ctx.id, Logic.tuiStateNames(ctx.manifest)));
    }

    function start(launch, ctx, done) {
        if (!launch.ok) {
            switch (launch.action) {
            case "none":
                break;
            case "probe":
                probe();
                break;
            case "focus":
                focus(launch.key);
                break;
            default:
                throw new Error("tui: refusal action " + JSON.stringify(launch.action) + " is not one of " + Logic.TUI_ACTIONS.join(", "));
            }
            return launch.answer;
        }
        const process = launcherComponent.createObject(root);
        process.key = launch.key;
        process.run = launch.run;
        // Assigned after creation: a list handed to createObject crosses a
        // QVariant conversion.
        process.command = [root.coreBin + "/vgshell-tui"].concat(launch.argv);
        if (done !== undefined) wait(ctx, launch.run, done);
        pending = pending.concat([{ key: launch.key, run: launch.run }]);
        launching = launching.concat([process]);
        process.running = true;
        return "ok";
    }

    // A `done` waiting for RUN, dropped with the lifetime of CTX, the
    // instance that asked, or kept for the shell's life when CTX is null,
    // the core's own request.
    function wait(ctx, run, done) {
        let release = () => {};
        const waiter = recordStore.addWaiter(ctx === null ? "core" : ctx.id, run, result => {
            release();
            done(result);
        });
        if (ctx !== null) {
            release = ctx.onDispose(() => recordStore.releaseWaiter(waiter));
        }
    }

    function finish(process, stderr) {
        const line = Logic.tuiLaunchOutcome(process.key, process.completion, stderr);
        if (line !== "") console.error(line);
        launcher = Logic.tuiLauncherAfter(launcher, process.completion);
        launching = launching.filter(p => p !== process);
        const failed = Logic.tuiLaunchDone(process.completion);
        if (failed !== null) {
            pending = pending.filter(p => p.run !== process.run);
            recordStore.deliver(process.run, failed);
        } else {
            recordStore.launched(process.key, process.run);
        }
        process.destroy();
    }

    // Brings the window of KEY's live run into view. A key busy only because its
    // launcher still waits has no window yet. A live run with no window is
    // looked for among the dead once: a presenter killed outright leaves a
    // running record that only `vgshell-tui reap` ends. The windows come
    // from Hyprland's reply: Quickshell's Hyprland.toplevels can keep a
    // closed window.
    function focus(key) {
        const slot = Object.prototype.hasOwnProperty.call(recordStore.runs.keys, key) ? recordStore.runs.keys[key] : null;
        if (slot === null || slot.running === null) return;
        const window = slot.running.window;
        Compositor.readWindows(state => root.windowsRead(key, window, state));
    }

    function windowsRead(key, window, state) {
        if (!state.ok) {
            console.error("tui: focus=unread tui=" + key + " " + state.error);
            return;
        }
        const found = Logic.tuiWindow(windows(state.clients), window);
        switch (found.state) {
        case "found":
            Compositor.reveal([found.address], false);
            break;
        case "none":
            console.warn("tui: focus=none tui=" + key);
            recordStore.reap();
            break;
        case "ambiguous":
            console.warn("tui: focus=ambiguous tui=" + key + " windows=" + found.count);
            break;
        default:
            throw new Error("tui: window state " + JSON.stringify(found.state) + " is not one of found, none, ambiguous");
        }
    }

    // CLIENTS, Hyprland's `j/clients` reply, as tuiWindow reads windows.
    function windows(clients) {
        return clients.map(client => ({ address: String(client.address), appId: String(client["class"]), title: String(client.title) }));
    }

    // A launch whose run has a record is no longer pending. It reads the
    // record owner's runs, not a binding on them: this handler runs from
    // their change signal, before such a binding need have followed it.
    function recordsChanged() {
        pending = pending.filter(p => !Object.prototype.hasOwnProperty.call(recordStore.runs.runs, p.run));
    }

    // One probe at a time: a request refused while one runs starts none.
    function probe() {
        if (prober.running) return;
        prober.completion = null;
        prober.running = true;
    }

    function frozen(value) {
        if (value === null || typeof value !== "object") return value;
        for (const key of Object.keys(value)) frozen(value[key]);
        return Object.freeze(value);
    }

    // The launchers running, the launcher state, the runs and the waiting
    // callbacks, for the lending record.
    function record() {
        const recordState = recordStore.record();
        return {
            launching: launching.map(p => p.key),
            pending: pending.map(p => p.key),
            launcher: launcher,
            probing: prober.running,
            reaping: recordState.reaping,
            runs: recordState.runs,
            waiters: recordState.waiters,
            waits: recordState.waits
        };
    }

    TuiRecords {
        id: recordStore
        recordDir: root.recordDir
        coreBin: root.coreBin
        onRunsChanged: root.recordsChanged()
    }

    // A command that fails to start emits only runningChanged, so the end
    // is read there: no exit recorded is a failed start.
    Process {
        id: prober
        property var completion: null
        command: [root.coreBin + "/vgshell-tui", "check"]
        stderr: StdioCollector { id: probeErrors }
        onExited: (code, status) => { prober.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const line = Logic.tuiProbeOutcome(prober.completion, probeErrors.text);
            if (line !== "") console.error(line);
            root.launcher = Logic.tuiLauncherAfter(root.launcher, prober.completion);
        }
    }

    Component {
        id: launcherComponent
        Process {
            id: process
            property string key: ""
            property string run: ""
            property var completion: null
            stderr: StdioCollector { id: errors }
            onExited: (code, status) => { process.completion = { code: code, status: status }; }
            onRunningChanged: {
                if (running) return;
                root.finish(process, errors.text);
            }
        }
    }
}
