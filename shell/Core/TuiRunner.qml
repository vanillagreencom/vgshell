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
    // Each plugin script's key and each editor key, the core's
    // `core/edit` and a plugin's file action's `<id>/edit`, -> the
    // arguments of the latest run this shell started for it, so a request
    // for a live key with other arguments is told apart from a second press
    // of the same one (PluginLogic.tuiArgsShownAnswer). One entry per such
    // key, each replaced by the next start (recordStarted). Replaced whole.
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
            edit: (path, line, done) => root.edit(path, line, root.guarded(ctx, done, "tui=edit")),
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
    // tuiRun takes them, absent for none, for the `manager` capability's step runner
    // (Capabilities.managerStep): its act on a status action (D061), whose
    // row action hands the row's id as the one argument, and
    // its open of a listed setup screen, the Settings page's Setup button.
    // Judged by request, as run is, so a disabled plugin's or an undeclared
    // script, or arguments tuiArgsValid refuses, are refused and one that lacks a required command raises the
    // requirement notice for those commands, for both steps. Answers `ok`
    // when the request starts the TUI or focuses its live window of the same
    // arguments, and `reason=busy-other` when that window is another row's,
    // as PluginLogic.tuiArgsShownAnswer decides. The plugin reads the run's end
    // from its `state`.
    function runFor(id, name, args, ctx, done) {
        const answer = request(id, Registry.manifests[id], { name: name, args: args, ctx: done === undefined ? null : ctx, done: done, manager: true });
        if (done !== undefined && answer === Logic.tuiRefusal(name, "busy").answer) return "busy";
        return Logic.tuiArgsShownAnswer(Logic.tuiOwnKey(id, name), name, answer, args, startedArgs);
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
        recordStarted(launch, held.args);
        return answer;
    }

    // The one record of the arguments ARGS, absent for none, that LAUNCH
    // started with, read by tuiArgsShownAnswer; a launch refused records
    // nothing, so the live run's arguments stay.
    function recordStarted(launch, args) {
        if (launch.ok) startedArgs = Object.assign({}, startedArgs, { [launch.key]: args === undefined ? [] : args.slice() });
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
            ? request(id, held.manager === true ? Registry.manifests[id] : held.ctx.manifest, held)
            : request(id, Registry.manifests[id], { name: held.name, args: held.args, ctx: null, done: undefined });
        if (answer !== "ok") unstarted(held);
        return Logic.tuiArgsShownAnswer(Logic.tuiOwnKey(id, held.name), held.name, answer, held.args, startedArgs);
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
    // through openPath. `done`, when given, receives the answer the open
    // ends in, as openPath says, for a folder too.
    function edit(path, line, done) {
        return openPath(path, line, undefined, done);
    }

    // editFor: plugin ID's file action (PluginLogic.statusActionRequest),
    // PATH opened by edit's route, its editor run keyed as the plugin's
    // own, `<id>/edit`, so the plugin reads its end in its `state`
    // (PluginLogic.tuiStateNames) as it reads its own script's.
    function editFor(id, path) {
        return openPath(path, undefined, id, undefined);
    }

    // DONE, a plugin's callback, as a function that calls it only while
    // CTX, the instance that gave it, reads `active`, as a run's `done` is
    // dropped. OPERATION, `<capability>=<member>` the plugin called, names
    // the refusal of a DONE that is no function.
    function guarded(ctx, done, operation) {
        if (done === undefined) return undefined;
        if (typeof done !== "function") throw new Error("refused: " + operation + " done=not-a-function");
        return answer => { if (ctx.active) done(answer); };
    }

    // PATH at LINE as PluginLogic.editRoute decides: a folder through
    // openFolder, and a file once gio has read it (fileProbed), by its
    // content type: a text file through the core editor TUI, run for OWNER,
    // a plugin id, or for the core while OWNER is undefined
    // (PluginLogic.tuiCore), and any other file in its default application.
    // A second request for the same file raises the live editor and answers
    // `ok`; one for another file while that editor is open raises it and
    // answers `reason=busy-other`, as runFor does, so a caller that leaves
    // once its file opened stays. Answers `ok` once the read starts, or the
    // refusal of a path editRoute judged, which ends no DONE; the end of any
    // other open, `ok` or the refusal `refused: file=<path> reason=missing`
    // and its kin, goes to DONE, when given, else to the log when it is no
    // `ok`.
    function openPath(path, line, owner, done) {
        const route = Logic.editRoute(path, line, Paths.home, Paths.configHome);
        if (!route.ok) return route.answer;
        if (route.kind === "folder") return openFolder(route.path, done);
        const file = route.args[0];
        const probe = fileProbeComponent.createObject(root, { path: file.charAt(0) === "/" ? file : Paths.configHome + "/" + file });
        // Assigned after creation: createObject's initial properties turn
        // the route's `args` into a list tuiArgsValid does not read as an
        // array.
        probe.route = route;
        probe.owner = owner;
        probe.done = done === undefined ? null : done;
        probe.running = true;
        return "ok";
    }

    // The core editor on ROUTE's file, run for OWNER (openPath).
    function openEditor(route, owner) {
        const launch = Logic.tuiCore(Logic.CORE_TUIS, coreBin, runner(), "edit", route.args, owner);
        const answer = start(launch, null, undefined);
        recordStarted(launch, route.args);
        const named = Logic.tuiCoreNamed("edit", owner);
        return Logic.tuiArgsShownAnswer(named.key, named.label, answer, route.args, startedArgs);
    }

    // What `gio info` read of a file, COMPLETION its { code, status }, null
    // for a read that never started, OUTPUT its standard output, ERRORS its
    // standard error, in the C locale: `missing` for a path gio finds
    // nothing at, `unreadable` for a read that failed to start, to run or
    // to say, such as one the folder's permissions refuse, `not-a-file` for what is neither a file nor a
    // folder, `program` for a type that runs when opened, by the canonical
    // name gio reads, never an alias, such as a Windows or Linux
    // executable, a Windows shortcut or installer, or a Java or Flatpak bundle,
    // since a notification's sender chooses the path of a link on its
    // card and a default application would run it, `editor` for a
    // text type, every text/* type and the text formats the shared MIME
    // database files elsewhere, and `default` for the rest, which open in
    // their default application, a folder in the file manager. gio reads
    // the type from the content when the name says none, so a text file
    // with no extension is text.
    function fileKind(completion, output, errors) {
        if (completion === null) return "unreadable";
        if (completion.status !== 0 || completion.code !== 0)
            return /No such file or directory|Not a directory/.test(errors) ? "missing" : "unreadable";
        const kind = /^\s*standard::type: (\d+)$/m.exec(output);
        const type = /^\s*standard::content-type: (\S+)$/m.exec(output);
        if (kind === null || type === null) return "unreadable";
        if (kind[1] !== "1" && kind[1] !== "2") return "not-a-file";
        const programs = ["application/x-executable", "application/x-pie-executable", "application/x-sharedlib", "application/vnd.appimage",
            "application/x-ms-dos-executable", "application/x-msdos-program", "application/x-msdownload", "application/vnd.microsoft.portable-executable",
            "application/x-bat", "application/x-msi", "application/x-ms-shortcut", "application/java-archive", "application/x-java-archive", "application/x-java-jnlp-file",
            "application/vnd.flatpak", "application/vnd.flatpak.ref", "application/vnd.flatpak.repo"];
        if (programs.indexOf(type[1]) !== -1) return "program";
        const texts = ["application/json", "application/toml", "application/x-shellscript", "application/xml", "application/yaml", "application/x-yaml", "application/javascript", "application/x-desktop", "application/x-zerosize",
            "application/x-perl", "application/x-ruby", "application/x-php", "application/x-powershell", "application/sql"];
        return type[1].indexOf("text/") === 0 || texts.indexOf(type[1]) !== -1 ? "editor" : "default";
    }

    // The end of the read of PROBE's file, COMPLETION, OUTPUT and ERRORS as
    // fileKind takes them: the editor, the default application or a
    // refusal, whose answer goes to the probe's `done` or, without one,
    // to the log.
    function fileProbed(probe, completion, output, errors) {
        const kind = fileKind(completion, output, errors);
        let answer;
        if (kind === "editor") answer = openEditor(probe.route, probe.owner);
        else if (kind === "default") answer = Capabilities.runDetached(DesktopLaunch.open(probe.path));
        else answer = "refused: file=" + JSON.stringify(probe.path) + " reason=" + kind;
        if (probe.done !== null) probe.done(answer);
        else if (answer !== "ok") console.warn("tui: " + answer);
    }

    // Opens PATH, an absolute path editRoute read as a folder, in the
    // default file manager once `test -d` finds a folder there: gio drops a
    // trailing `/`, so a path naming a file would open that file in its
    // default application, and a notification's sender chooses the path of
    // a link on its card. Answers `ok` once the check starts, as
    // runDetached answers once gio starts; the check's end goes to DONE, when
    // given, else to the log (folderChecked).
    function openFolder(path, done) {
        const check = folderCheckComponent.createObject(root, { path: path });
        check.done = done === undefined ? null : done;
        check.running = true;
        return "ok";
    }

    // The end of the folder check of PATH, COMPLETION its { code, status },
    // null for a check that never started: exit 0 opens the folder, any
    // other end opens nothing and answers `refused: file=<path>
    // reason=not-a-folder`, or `reason=unreadable` for a check that never
    // started. The answer goes to DONE, when not null, else to the log when
    // it is no `ok`.
    function folderChecked(path, completion, done) {
        let answer;
        if (completion === null) answer = "refused: file=" + JSON.stringify(path) + " reason=unreadable";
        else if (completion.status !== 0 || completion.code !== 0) answer = "refused: file=" + JSON.stringify(path) + " reason=not-a-folder";
        else answer = Capabilities.runDetached(DesktopLaunch.open(path));
        if (done !== null) done(answer);
        else if (answer !== "ok") console.warn("tui: " + answer);
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
    // scripts' and its file actions' editor runs (PluginLogic.tuiStateNames),
    // a run live from its launch, before any record of it is listed.
    function stateOf(ctx) {
        return frozen(Logic.tuiState(recordStore.runs, ctx.id, Logic.tuiStateNames(ctx.manifest), pending.map(p => p.key)));
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

    // `test -d PATH`, PATH absolute, so never read as an option. Quickshell
    // 0.3.1 reports a failed start only through runningChanged, so the end
    // is judged there.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
    Component {
        id: folderCheckComponent
        Process {
            id: check
            property string path: ""
            property var done: null
            property var completion: null
            command: ["test", "-d", check.path]
            onExited: (code, status) => { check.completion = { code: code, status: status }; }
            onRunningChanged: {
                if (running) return;
                root.folderChecked(check.path, check.completion, check.done);
                check.destroy();
            }
        }
    }

    // `gio info` of PATH, absolute, for the type and kind fileKind reads. As
    // the folder check, it reports a failed start only through
    // runningChanged.
    Component {
        id: fileProbeComponent
        Process {
            id: probe
            property string path: ""
            property var route: null
            property var owner: undefined
            property var done: null
            property var completion: null
            command: ["gio", "info", "-a", "standard::type,standard::content-type", "--", probe.path]
            environment: ({ LC_ALL: "C" })
            stdout: StdioCollector { id: probeOutput }
            stderr: StdioCollector { id: probeErrors }
            onExited: (code, status) => { probe.completion = { code: code, status: status }; }
            onRunningChanged: {
                if (running) return;
                try {
                    root.fileProbed(probe, probe.completion, probeOutput.text, probeErrors.text);
                } finally {
                    probe.destroy();
                }
            }
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
