import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "SetupGate.js" as Gate

// The user's Jarvis session as the Jarvis package's session command owns it
// (backend/session-control.js). This instance's build, at shell start or
// when the user enables Jarvis, makes the one automatic call: the package
// starts the session after the app's Off or, while Start Jarvis at boot is
// on, for a boot it has not handled, and answers the session as it is for
// any other; with Resume the last session, a record the package saved
// before a machine restart is resumed instead. The Start and Retry actions
// ask for a start, a changed account or home replaces a session that lives,
// and each opening of the Jarvis page reads the session again. A read
// starts nothing. turnedOff() is the user's Off: it stops the session in a
// process that outlives this service. Each answer is the Jarvis session row
// and the bar widget's reading (`jarvisSession`). While Start Jarvis at boot
// is off, that record is the Resume offer: the widget's click and the row's
// Resume ask for its resume, Do not resume asks the package to drop the
// record (`dismiss`), and the offer waits for either ask's answer and ends
// once the record is gone or its resume started
// (SetupGate.sessionResumeStarted). While a resume that started still runs
// with a pending step (SetupGate.sessionStepsPending), this instance reads
// the session again every stepPollMs, for at most stepPollLimitMs from the
// first such read; the widget then says when it last read the steps.
Item {
    id: root
    property var shell: null
    // The account and home the last call read, as JSON; "" before the build's.
    property string judged: ""
    // The home setting whose session the row shows. It follows the selected
    // home only once a call for that home is applied: a selection that
    // failed its check leaves the session, and so this, where it was.
    property string sessionHome: ""
    // The block of that failed selection, "" for none. A read of the
    // session that stays keeps it on the row.
    property string unapplied: ""
    // The helper's last answer, null before the first.
    property var result: null
    // The running call's verb and the home setting it is for.
    property var current: null
    // The calls that wait for the running one, oldest first.
    property var waiting: []
    property string output: ""
    property string errors: ""
    property int exitCode: 0
    // True from Do not resume's ask to its answer. The package drops the
    // record, so no later read offers it again; VGS keeps no mark of it.
    property bool dismissing: false
    // True once the package did not answer the last Do not resume: the
    // record and its offer stay, and the row says the choice was not saved.
    property bool dismissFailed: false
    // True from the Resume's ask to its answer: a second Resume before the
    // answer asks for nothing. The answer says whether the resume started.
    property bool resumed: false
    // When the first read of pending steps of a started resume came, 0
    // before; the reads stop for good once stepPollLimitMs have passed since.
    property real pollSince: 0
    property bool pollOver: false
    // The ISO time of the last answer of the session, "" before the first.
    property string lastRead: ""
    readonly property int stepPollMs: 2000
    readonly property int stepPollLimitMs: 600000
    readonly property bool stepsPending: Gate.sessionStepsPending(result)
    readonly property bool offered: shell !== null
        && Gate.sessionOffer(shell.settings.startAtBoot, result, resumed || dismissing)
    readonly property string program: String(Qt.resolvedUrl("backend/session-control.js")).replace(/^file:\/\//, "")
    readonly property bool wanted: shell !== null && shell.settings.startAtBoot
    onWantedChanged: publish()
    readonly property bool pageViewed: shell !== null && shell.status.viewed
    onPageViewedChanged: if (pageViewed && judged !== "") call("status", sessionHome, [sessionHome])
    onShellChanged: {
        if (shell === null) return;
        // A new `shell` is any changed setting, so only a change of what a
        // call reads makes one. The handler reads `shell`, not a binding of
        // it: Qt defines no order between a binding and this handler.
        const settings = shell.settings;
        const read = JSON.stringify({ account: settings.brain, home: settings.home });
        const mode = settings.bootSession === "new" ? "new" : "resume";
        if (judged === "") {
            // The TUI step behind the row's Start and Retry (tui/start-session.sh).
            shell.ipc.handle("start-session", () => {
                const now = root.shell.settings;
                root.call("start", now.home, [now.brain, now.home, now.bootSession === "new" ? "new" : "resume"]);
                return "ok";
            });
            // The widget's click and the row's Resume (tui/resume-session.sh),
            // and the widget's Do not resume.
            shell.ipc.handle("resume-session", () => root.resume());
            shell.ipc.handle("dismiss-resume", () => root.dismissResume());
            sessionHome = settings.home;
            call("build", settings.home, [settings.brain, settings.home, mode, settings.startAtBoot ? "on" : "off"]);
        } else if (read !== judged) call("change", settings.home, [sessionHome, settings.brain, settings.home, mode]);
        judged = read;
        publish();
    }

    function resume() {
        if (!offered) return "refused: resume=not-offered";
        resumed = true;
        pollSince = 0;
        pollOver = false;
        publish();
        call("resume", sessionHome, [sessionHome]);
        return "ok";
    }

    function dismissResume() {
        if (!offered) return "refused: resume=not-offered";
        dismissing = true;
        dismissFailed = false;
        publish();
        call("dismiss", sessionHome, [sessionHome]);
        return "ok";
    }

    // False when the status judge refuses the row, which then keeps its
    // last value.
    function publish() {
        if (shell === null) return true;
        const wanted = shell.settings.startAtBoot;
        const modes = shell.status.set("sessionModes", Gate.sessionModes(wanted));
        const value = Gate.sessionStart(wanted, result, offered, dismissFailed);
        // The extra status lines draw as badges, which do not draw links.
        if (value.lines !== undefined) value.lines = value.lines.map(PageReference.plain);
        const row = shell.status.set("sessionStart", value);
        const reading = shell.status.set("jarvisSession", Gate.sessionRecord(wanted, result, !offered, pollOver && lastRead !== "" ? lastRead : null));
        if (modes === "ok" && row === "ok" && reading === "ok") return true;
        console.warn("jarvis-session: status=refused modes=" + modes + " row=" + row + " reading=" + reading);
        return false;
    }

    function call(verb, home, args) {
        if (helper.running) {
            // A status read adds nothing behind a call that answers the session.
            if (verb !== "status" || waiting.length === 0) waiting = waiting.concat([{ verb: verb, home: home, args: args }]);
            return;
        }
        // A queued change names the session's home as it is when it runs.
        if (verb === "change") args = [sessionHome].concat(args.slice(1));
        current = { verb: verb, home: home };
        output = "";
        errors = "";
        helper.command = ["node", program, "--tree", Quickshell.shellDir + "/..", verb].concat(args);
        helper.running = true;
    }

    function answered() {
        let answer;
        try { answer = JSON.parse(output); }
        catch (error) {
            // The helper's keyed line goes to the log; the row says it failed.
            console.warn("jarvis-session: control=no-answer verb=" + current.verb + " exit=" + exitCode + " cause=" + errors.split("\n")[0].slice(0, 180));
            answer = { kind: "failed" };
        }
        if (current.verb === "dismiss") {
            dismissing = false;
            dismissFailed = answer.kind !== "answer";
            if (dismissFailed) {
                // The package kept the record: the offer and the session as
                // last read stay, and the row says the choice was not saved.
                console.warn("jarvis-session: dismiss=not-saved kind=" + answer.kind + (answer.block === undefined ? "" : " block=" + answer.block));
                publish();
                takeNext();
                return;
            }
        }
        let again = false;
        if (answer.kind === "answer" && answer.unapplied !== undefined) unapplied = answer.unapplied;
        else if (answer.kind !== "failed" && current.verb === "status" && unapplied !== "") {
            // A read of the session a refused selection left in place.
            if (answer.kind === "answer" && Gate.sessionLive(answer.state)) answer = Object.assign({}, answer, { unapplied: unapplied });
            else {
                // That session is gone: the row follows the selected home.
                unapplied = "";
                sessionHome = shell.settings.home;
                again = true;
            }
        } else if (answer.kind !== "failed") {
            // An applied call: the session, or none, is the selected home's.
            unapplied = "";
            sessionHome = current.home;
        }
        result = answer;
        if (current.verb === "resume") resumed = false;
        if (answer.kind === "answer") lastRead = new Date().toISOString();
        if (stepsPending && pollSince === 0) pollSince = Date.now();
        publish();
        if (again) call("status", sessionHome, [sessionHome]);
        takeNext();
    }

    // The oldest call that waits for the one that answered, if any.
    function takeNext() {
        if (waiting.length === 0) return;
        const next = waiting[0];
        waiting = waiting.slice(1);
        Qt.callLater(() => root.call(next.verb, next.home, next.args));
    }

    // The core calls this on the service when the user disables the plugin,
    // before it destroys the service; a reload and a shell exit do not. The
    // stop goes to the home the session lives in, which a refused selection
    // leaves behind the selected one. No home folder holds no session.
    function turnedOff() {
        pollOver = true;
        if (shell === null || sessionHome === "") return;
        const reply = shell.run.detached(["node", program, "--tree", Quickshell.shellDir + "/..", "stop", sessionHome, "app-off"]);
        if (reply !== "ok") console.warn("jarvis-session: stop " + reply);
    }

    // The one reader of a started resume's steps. A status read behind a
    // running call adds nothing (call), so a slow command queues no reads.
    Timer {
        interval: root.stepPollMs
        repeat: true
        running: root.stepsPending && root.pollSince > 0 && !root.pollOver
        onTriggered: {
            if (Date.now() - root.pollSince < root.stepPollLimitMs) {
                root.call("status", root.sessionHome, [root.sessionHome]);
                return;
            }
            // The widget's pending steps give way to when they were read.
            root.pollOver = true;
            root.publish();
        }
    }

    Process {
        id: helper
        // The package's command takes the shell's session environment, which
        // the helper passes on less the shell's own marks: the session is the
        // user's own program.
        stdout: StdioCollector { onStreamFinished: root.output = text }
        stderr: StdioCollector { onStreamFinished: root.errors = text }
        onExited: (code, status) => root.exitCode = code
        onRunningChanged: if (!running) root.answered()
    }
}
