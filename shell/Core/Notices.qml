pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "PluginLogic.js" as Logic

// The core notice state: requirement notices for missing commands, the
// restart notice for a shell whose own files changed under it, the reset
// question and the "VGS was reset" notice that offers the restore, and one
// consent slot for core-owned setup that must not run silently, which
// draws the first-start welcome around the Hyprland question.
// Requirement notices decide which plugins' missing commands the user is
// shown, in what order, on which screen, and the install the shown notice
// runs (requirement-notice.md). Six triggers raise a notice: the
// pluginInstalled IPC function `vgshell plugin add` calls, Plugins.setEnabled
// turning a plugin on, a plugin's own `requirements` capability, the
// `manager` capability's installRequirements and its act on a status
// action that installs, and the `doctor` capability asking for the core's
// or an enabled plugin's commands. A notice belongs
// to one owner, a plugin or the core, whose requirements and missing
// commands Registry holds.
// PluginLogic decides what each trigger asks for, whether it joins the
// queue, and what the shown notice lists and installs; NoticeHost draws
// it. The managers come from `bin/vgshell-pkg detect --json`, run when the
// first notice arrives and after each install. Install opens the core TUI
// `core/requirements-install`; once its run ends, one rescan follows, and
// a notice whose required commands the scan finds is closed. A notice a
// plugin's setup TUI raised in place of itself (TuiRunner.runFor) opens
// that TUI once it closes so, so one press of Set up ends set up (D061).
// The core never elevates: the package manager asks in the terminal (D034).
Singleton {
    id: root

    // The notices held, each { id, commands, required }, the first shown;
    // `id` is the owner's, a plugin id or PluginLogic.CORE_OWNER.
    // Replaced whole on every change.
    property var queue: []
    // Plugin id -> the end, in ms since the epoch, of the rest its own
    // offers take after the user answered its notice Not now.
    property var rest: ({})
    // detect's answer, or null before the first detection and after one
    // failed.
    property var managers: null
    // What the last detection left: `pending` from the first notice of a
    // showing until a detection ends, then `answered` or `failed`. The
    // notice waits while it is pending; a later detection keeps the last
    // state on screen while it runs.
    property string detection: "pending"
    property bool detectAgain: false
    // The id of the notice whose install runs, from Install until the scan
    // after its TUI ended, or "".
    property string installingId: ""
    // Why the shown notice's last install did not end with code 0, or "".
    property string failure: ""
    // Plugin id -> the name of its own TUI a press asked for while a
    // command it needs was missing: opened once that plugin's notice
    // closes with the commands found, dropped by Not now. Replaced whole.
    property var resumes: ({})
    property var screen: null
    // What the consent slot draws, or null: PluginLogic.consentSlotView,
    // the welcome or the Hyprland question, which HyprlandLayer binds.
    // NoticeHost draws it only when no requirement notice shows.
    property var consent: null
    property var consentState: null
    // The welcome-seen marker's state, one of PluginLogic.WELCOME_STATES.
    property string welcome: "reading"
    // Whether the restart notice is owed: the core changed on disk, or a
    // first build was refused because a restart is owed, from then until
    // the user answers it.
    property bool restart: false
    // What the restart notice draws, in the consent slot's form. Restart is
    // the click; the command it runs is only behind Show command (D061).
    readonly property var restartView: ({
        title: "Restart to update",
        message: "VGS changed on disk. Plugins keep running as they are. New plugin windows wait for the restart. Open windows stay open.",
        lines: [],
        disclosure: "vgshell restart",
        actions: [{ label: "Restart", role: "accept" }, { label: "Not now", role: "cancel" }],
        failure: "",
        busy: false
    })
    // Whether the reset question is owed: from the askReset IPC function,
    // which `vgshell reset` calls with no terminal and no --yes, or the
    // `manager` capability's reset, until the user answers it.
    property bool resetAsked: false
    // The commands the reset question's Reset and the "VGS was reset"
    // notice's Restore previous settings run, shown only behind Show
    // command (D061).
    readonly property string resetCommand: "vgshell reset --yes"
    readonly property string restoreCommand: "vgshell reset restore --yes " + resetBackup
    // What the reset question draws, in the consent slot's form. Cancel,
    // the action that cannot change anything, holds the keyboard first.
    readonly property var resetView: ({
        title: "Reset VGS?",
        message: "Your settings, installed plugins and themes move to a backup, and VGS restarts as on a fresh install. You can restore them afterwards.",
        lines: [],
        disclosure: resetCommand,
        actions: [{ label: "Cancel", role: "cancel", focused: true }, { label: "Reset", role: "accept", variant: "danger" }],
        failure: "",
        busy: false
    })
    // The backup folder the last reset made, which `vgshell reset` writes
    // to <stateDir>/reset-backup and this reads at start, or "" while no
    // such folder is owed. The "VGS was reset" notice shows while it is set.
    property string resetBackup: ""
    readonly property string resetMarker: Paths.stateDir + "/reset-backup"
    // What the "VGS was reset" notice draws, in the consent slot's form.
    // Keep these, which leaves the fresh state, holds the keyboard.
    readonly property var resetDoneView: ({
        title: "VGS was reset",
        message: "Your previous settings, plugins and themes are in a backup. Restore them, or keep this fresh start.",
        lines: [],
        disclosure: restoreCommand,
        actions: [{ label: "Restore previous settings", role: "accept" }, { label: "Keep these", role: "cancel", focused: true }],
        failure: "",
        busy: false
    })
    // Callbacks waiting for a scan that starts after they were asked for,
    // each { scan, fn }, `scan` the Registry.requirementsRevision at which
    // that scan has ended (Registry.rescan).
    property var afterScans: []

    readonly property var current: queue.length > 0 ? queue[0] : null
    // The restart notice shows behind every requirement notice, the reset
    // question behind it, the "VGS was reset" notice behind that, and the
    // consent slot last, so the welcome follows a reset's notice.
    readonly property bool showingRestart: current === null && restart
    readonly property bool showingResetAsk: current === null && !restart && resetAsked
    readonly property bool showingResetDone: current === null && !restart && !resetAsked && resetBackup !== ""
    readonly property bool showingConsent: current === null && !restart && !resetAsked && resetBackup === "" && consent !== null
    // What the shown notice draws, PluginLogic.noticeView with the owner's
    // id and name, or null while none shows, before the first detection
    // ended, or while its owner is gone before the scan that drops it.
    readonly property var view: {
        const notice = current;
        const owners = Registry.requirementOwners;
        const missing = Registry.ownerMissing;
        const found = managers;
        if (notice === null || detection === "pending" || !Logic.hasOwn(owners, notice.id)) return null;
        const shown = Logic.noticeView(owners[notice.id], Logic.hasOwn(missing, notice.id) ? missing[notice.id] : [], notice, found);
        shown.id = notice.id;
        shown.name = owners[notice.id].name;
        return shown;
    }
    readonly property bool installing: current !== null && installingId === current.id
    readonly property string shownId: current !== null ? current.id : restart ? "core-restart" : resetAsked ? "core-reset" : resetBackup !== "" ? "core-reset-done" : consent !== null ? "core-consent" : ""
    // The consent slot's answer, `connect`, `decline` or `close`, which
    // HyprlandLayer acts on.
    signal consentAnswered(string answer)

    onShownIdChanged: {
        failure = "";
        settleScreen(true);
    }

    Component.onCompleted: resetRead.running = true

    Connections {
        target: Quickshell
        function onScreensChanged() { root.settleScreen(false); }
    }

    // A scan drops every notice whose plugin went or whose required
    // commands it found, the installing one excepted, then runs the
    // callbacks it was due for; the install's callback settles that one.
    Connections {
        target: Registry
        function onCoreChangedChanged() {
            if (Registry.coreChanged) root.restartOwed();
        }

        function onScanFinished() {
            root.settle();
            const revision = Registry.requirementsRevision;
            const due = root.afterScans.filter(a => a.scan <= revision);
            root.afterScans = root.afterScans.filter(a => a.scan > revision);
            for (const a of due) a.fn();
        }
    }

    // The screen of the shown notice: the focused one when a notice comes
    // to the front (FRESH) and when its screen goes, none while no notice
    // shows.
    function settleScreen(fresh) {
        if (queue.length === 0 && consent === null && !restart && !resetAsked && resetBackup === "") screen = null;
        else if (fresh || screen === null || Quickshell.screens.indexOf(screen) === -1) screen = Compositor.focusedScreen();
    }

    function missingOf(id) {
        return Logic.hasOwn(Registry.ownerMissing, id) ? Registry.ownerMissing[id] : [];
    }

    function settle() {
        const kept = Logic.noticeSettle(queue, Registry.requirementOwners, Registry.ownerMissing, installingId);
        if (kept.length !== queue.length) queue = kept;
        resume();
    }

    // Each TUI a press asked for whose plugin's notice has closed: opened
    // when the scan finds every command it needs, so a notice closed with
    // one still missing opens nothing.
    function resume() {
        const due = Object.keys(resumes).filter(id => !queue.some(n => n.id === id));
        if (due.length === 0) return;
        const next = Object.assign({}, resumes);
        for (const id of due) delete next[id];
        const names = due.map(id => resumes[id]);
        resumes = next;
        due.forEach((id, i) => {
            const manifest = Registry.activeManifestOf(id);
            if (manifest === null || !Logic.hasOwn(manifest.tui, names[i])) return;
            if (Logic.tuiMissingRequirements(manifest, names[i], missingOf(id)).length > 0) return;
            const answer = Capabilities.tuis.runFor(id, names[i]);
            if (answer !== "ok") console.warn("notices: resume=" + id + "/" + names[i] + " " + answer);
        });
    }

    // Start one scan and call FN once a scan that started after this call
    // ended, the scan Registry.rescan names. A start that fails can end that
    // scan inside Registry.rescan, before its scanFinished could reach FN,
    // so FN then runs on the next turn. Answers Registry.rescan's
    // { answer, scan }.
    function afterScan(fn) {
        const request = Registry.rescan();
        if (request.scan <= Registry.requirementsRevision) Qt.callLater(fn);
        else afterScans = afterScans.concat([{ scan: request.scan, fn: fn }]);
        return request;
    }

    // Owner ID's notice for TRIGGER, one of PluginLogic.NOTICE_TRIGGERS,
    // and, for an offer or a request, COMMANDS: PluginLogic.noticeRequest's
    // answer, then noticeAdmit's.
    function raise(id, trigger, commands) {
        const owners = Registry.requirementOwners;
        if (!Logic.hasOwn(owners, id)) return "unknown: " + id;
        const request = Logic.noticeRequest(owners[id], missingOf(id), trigger, commands);
        if (request.answer !== "ok") return request.answer;
        const admitted = Logic.noticeAdmit(queue, rest, id, request, trigger, Date.now());
        if (admitted.queue !== queue) {
            // Before the queue moves, so the first notice never shows
            // without its packages.
            if (queue.length === 0) {
                detection = "pending";
                detect();
            }
            queue = admitted.queue;
        }
        return admitted.answer;
    }

    // The pluginInstalled IPC function: one scan, then the notice for ID
    // once that scan has read the new plugin. Answers as rescanPlugins
    // does, Registry.scanReply.
    function installed(id) {
        return Registry.scanReply(afterScan(() => {
            const answer = root.raise(id, "installed");
            if (answer !== "ok" && answer !== "satisfied") console.warn("notices: installed=" + id + " " + answer);
        }));
    }

    // Plugins.setEnabled turned plugin ID on.
    function enabled(id) {
        const answer = raise(id, "enabled");
        if (answer !== "ok" && answer !== "satisfied") console.warn("notices: enabled=" + id + " " + answer);
    }

    // The `requirements` capability's offer, for the instance CTX belongs to.
    function offer(ctx, commands) {
        return raise(ctx.id, "offered", commands);
    }

    // The `manager` capability's installRequirements: plugin ID's notice
    // with every missing command, the Settings window's Install all missing.
    // A plugin missing nothing raises no notice, so `satisfied` answers
    // `refused: requirements=<id> reason=satisfied` for the page to show.
    // TUI, when given, is the plugin's own TUI the press asked for, which
    // the notice opens once it closes with its commands found (resume).
    function requested(id, tui) {
        const answer = raise(id, "requested");
        if (answer === "ok" && tui !== undefined) resumes = Object.assign({}, resumes, { [id]: tui });
        return answer === "satisfied" ? "refused: requirements=" + id + " reason=satisfied" : answer;
    }

    // A user's choice of OWNER's COMMANDS, the core's or an enabled
    // plugin's: the `doctor` capability's, and the `manager` capability's
    // act on a status action that installs (D061). The owner and the
    // commands are judged at once; the notice is raised after a scan this
    // choice starts, since the value that offered it read PATH later than
    // the last scan did (a removal through mise rescans nothing, and a
    // plugin's own probe is its own), so a command that value lists missing
    // is judged missing or present by the same PATH. Answers `ok` once that
    // scan is asked for; the notice shows after it only while a command is
    // missing, and no offer's rest holds it back.
    function chosen(owner, commands) {
        const refusal = choiceRefusal(owner, commands);
        if (refusal !== "") return refusal;
        afterScan(() => {
            const late = root.choiceRefusal(owner, commands);
            const answer = late !== "" ? late : root.raise(owner, "chosen", commands);
            if (answer !== "ok" && answer !== "satisfied") console.warn("notices: chosen=" + owner + " " + answer);
        });
        return "ok";
    }

    // Why a `doctor` choice of OWNER's COMMANDS is refused, or "":
    // PluginLogic.noticeOwnerError, then noticeRequest's own refusals, which
    // read no missing command.
    function choiceRefusal(owner, commands) {
        const owners = Registry.requirementOwners;
        const refusal = Logic.noticeOwnerError(owner, owners, Object.keys(Registry.manifests).filter(id => Registry.isEnabled(id)));
        if (refusal !== "") return refusal;
        const answer = Logic.noticeRequest(owners[owner], [], "chosen", commands).answer;
        return answer.startsWith("refused: ") ? answer : "";
    }

    // Install: the shown notice's first installable group through the core
    // TUI. Answers the TUI's answer; a busy key focuses the live install.
    function accept() {
        const shown = view;
        if (shown === null || shown.install === null || installing) return "refused: install=none";
        const id = shown.id;
        failure = "";
        const answer = Capabilities.tuis.openCore("requirements-install", shown.install, result => root.installEnded(id, result));
        if (answer === "ok") installingId = id;
        else {
            failure = answer;
            console.error("notices: install=" + id + " " + answer);
        }
        return answer;
    }

    function installEnded(id, result) {
        if (result.code !== 0 && root.current !== null && root.current.id === id)
            failure = result.code === null ? "install=" + result.reason : "install exited " + result.code;
        detect();
        afterScan(() => {
            if (root.installingId !== id) return;
            root.installingId = "";
            root.settle();
        });
    }

    // The notice logs only when it changes from closed to owed, so Not now
    // can close it until the next refused first build raises it again.
    function restartOwed() {
        if (restart) return;
        restart = true;
        console.info("notices: restart=owed");
    }

    // Restart: `vgshell restart`, the one route that stops the runner and has
    // Hyprland start the next shell (runtime.md § Process). It runs
    // detached, since it must outlive the shell it stops, so a restart that
    // refuses reports nothing back and leaves this shell running.
    function restartShell() {
        if (!showingRestart) return;
        restart = false;
        console.info("notices: restart=started");
        Quickshell.execDetached([Quickshell.shellDir + "/../bin/vgshell", "restart"]);
    }

    // The reset question, from the askReset IPC function or the `manager`
    // capability's reset: it shows behind every requirement notice and the
    // restart notice. Answers `ok`.
    function askReset() {
        resetAsked = true;
        return "ok";
    }

    // Reset: `vgshell reset --yes`, which moves the files, stops this shell
    // and has Hyprland start the next one, so it runs detached as
    // restartShell runs restart, and a reset that refuses reports nothing
    // back.
    function resetVgs() {
        if (!showingResetAsk) return;
        resetAsked = false;
        console.info("notices: reset=started");
        Quickshell.execDetached([Quickshell.shellDir + "/../bin/vgshell", "reset", "--yes"]);
    }

    // Restore previous settings: `vgshell reset restore --yes <folder>`,
    // detached for the same reason.
    function restoreReset() {
        if (!showingResetDone) return;
        const folder = resetBackup;
        resetBackup = "";
        console.info("notices: restore=started backup=" + folder);
        Quickshell.execDetached([Quickshell.shellDir + "/../bin/vgshell", "reset", "restore", "--yes", folder]);
    }

    // Escape on the "VGS was reset" notice, which NoticeHost takes before
    // the dialog's own Escape: the notice goes for this run and the marker
    // stays, so the restore is offered again at the next start.
    function hideResetDone() {
        if (showingResetDone) resetBackup = "";
    }

    // Not now, Escape or Close: the shown notice goes, and its owner's own
    // offers rest; a `doctor` request, the user's press, never rests. The
    // restart notice goes until another refused first build raises it, and
    // the reset question until the next ask. Keep these on the "VGS was
    // reset" notice removes the marker, so the notice does not come back;
    // the backup folder stays for `vgshell reset restore`.
    function dismiss() {
        const notice = current;
        if (notice === null) {
            if (restart) restart = false;
            else if (resetAsked) resetAsked = false;
            else if (resetBackup !== "") {
                resetBackup = "";
                resetForget.running = true;
            } else if (consent !== null) answerConsent("cancel");
            return;
        }
        if (installing) return;
        const now = Date.now();
        const next = {};
        for (const id of Object.keys(rest)) if (rest[id] > now) next[id] = rest[id];
        next[notice.id] = now + Logic.NOTICE_OFFER_REST_MS;
        rest = next;
        if (Logic.hasOwn(resumes, notice.id)) {
            const kept = Object.assign({}, resumes);
            delete kept[notice.id];
            resumes = kept;
        }
        queue = queue.slice(1);
    }

    // The consent slot's action of ROLE answers, when the slot draws one.
    function answerConsent(role) {
        if (consent === null) return;
        const action = consent.actions.find(a => a.role === role);
        if (action === undefined) throw new Error("notices: the consent slot has no " + role + " action");
        consentAnswered(action.answer);
    }

    // One detection at a time; one asked for while one runs follows it.
    function detect() {
        if (detector.running) {
            detectAgain = true;
            return;
        }
        detector.completion = null;
        detector.running = true;
    }

    // The shown and waiting notices, the restart notice, the reset
    // question and the reset's backup, the consent slot and the welcome, the
    // resting plugins, the screen and the managers, for the lending record.
    function record() {
        const now = Date.now();
        return {
            shown: current === null ? null : { plugin: current.id, commands: current.commands, required: current.required, installing: installing, failure: failure },
            restart: restart,
            reset: { asked: resetAsked, backup: resetBackup === "" ? null : resetBackup },
            consent: consent === null ? null : { title: consent.title, command: consent.disclosure, failure: consent.failure },
            consentState: consentState === null ? null : { phase: consentState.phase, queued: consentState.queued || "", failure: consentState.failure || "" },
            welcome: { state: welcome, lines: consent !== null && consent.welcome ? consent.lines : null, actions: consent !== null && consent.welcome ? consent.actions.map(a => a.label) : null },
            waiting: queue.slice(1).map(n => n.id),
            resumes: resumes,
            resting: Object.keys(rest).filter(id => rest[id] > now).sort(),
            screen: screen === null ? null : screen.name,
            managers: managers,
            detection: detection,
            detecting: detector.running
        };
    }

    // The reset marker, read once at start: the folder it names while that
    // folder exists, else nothing. A read that cannot run offers no
    // restore, and the log names the failure.
    Process {
        id: resetRead
        property var completion: null
        command: ["bash", "-c", "[[ -e \"$1\" ]] || exit 0; IFS= read -r folder <\"$1\" || [[ -n $folder ]] || exit 0; [[ ! -d $folder ]] || printf '%s\\n' \"$folder\"", "vgs-reset", root.resetMarker]
        stdout: StdioCollector { id: resetReadOut }
        stderr: StdioCollector { id: resetReadErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null || done.code !== 0) {
                console.error("notices: reset-marker-read=failed path=" + root.resetMarker + (done === null ? " start=failed" : " status=" + done.code) + " stderr=" + JSON.stringify(resetReadErr.text.trim()));
                return;
            }
            root.resetBackup = resetReadOut.text.trim();
        }
    }

    // Keep these: the marker goes. A removal that fails offers the restore
    // again at the next start.
    Process {
        id: resetForget
        property var completion: null
        command: ["rm", "-f", "--", root.resetMarker]
        stderr: StdioCollector { id: resetForgetErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null || done.code !== 0) console.error("notices: reset-marker-remove=failed path=" + root.resetMarker + (done === null ? " start=failed" : " status=" + done.code) + " stderr=" + JSON.stringify(resetForgetErr.text.trim()));
        }
    }

    // A command that fails to start emits only runningChanged, so the end
    // is read there: no exit recorded is a failed start (runtime-qml.md).
    Process {
        id: detector
        property var completion: null
        command: [Quickshell.shellDir + "/../bin/vgshell-pkg", "detect", "--json"]
        stdout: StdioCollector { id: detected }
        stderr: StdioCollector { id: detectErrors }
        onExited: (code, status) => { detector.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const answer = Logic.noticeDetected(detector.completion, detected.text, detectErrors.text);
            root.managers = answer.ok ? answer.found : null;
            if (!answer.ok) console.error(answer.line);
            if (root.detectAgain) {
                root.detectAgain = false;
                root.detect();
                return;
            }
            root.detection = answer.ok ? "answered" : "failed";
        }
    }
}
