import QtQuick
import Quickshell
import Quickshell.Io
import "VpnLogic.js" as Logic

// The VPN service: the one owner of every `tailscale` process and of the
// poll (VpnLogic.js decides; this runs the effects). The widget, the
// flyout and the pane read what it publishes and start no process. They
// ask it through the plugin's own IPC, which `vgshell ipc call vgs.vpn
// invoke <name> <arg>` reaches too:
//   lease {"id","open"}   a view opens or closes; an open view makes the
//                         poll fast; answers `ok` or a refusal
//   action {"kind","id"}  connect, disconnect, exit-node, switch, login or
//                         cancel-login; answers `ok`, `busy` or a refusal
//   refresh               read Tailscale now; answers `ok`
//   open                  summon the flyout
//
// The poll runs `tailscale status --json` every `pollSeconds` while no
// view is open and every 3 s while one is, one run at a time. A run that
// has not ended 10 s after its start is killed, and a refresh never moves
// that deadline. It publishes `connection` and `setup`, the lines the
// Settings page draws, and `vpn`, the bounded snapshot the views draw.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    property bool registered: false
    property var leases: ({})
    readonly property int leaseCount: Object.keys(leases).length
    readonly property bool missing: commandMissing()
    readonly property int scans: shell === null ? 0 : shell.requirements.revision
    readonly property int pollInterval: Logic.pollInterval(leaseCount > 0, shell === null ? 30 : shell.settings.pollSeconds)
    readonly property var steps: shell === null ? ({}) : shell.system.state

    property var poll: Logic.pollIdle()
    // The polls started and the polls the watchdog killed, for the log
    // line of a kill and the smoke row's count of the stand-in's calls.
    property int pollsStarted: 0
    property int pollsKilled: 0
    property var snapshot: Logic.emptySnapshot("checking")
    property var accounts: []
    // Why the last accounts read gave no list, "" for one that did.
    property string accountsFault: ""
    // The command that runs now, "" for none.
    property string action: ""
    // `idle`, `waiting` for the sign-in page's address, or `opened`.
    property string login: "idle"
    // The lines the sign-in run printed that hold no address, which name
    // a failed run's cause.
    property string loginSaid: ""
    // The line the last failed command left, "" for none.
    property string problem: ""

    readonly property var connection: Logic.connection(missing, snapshot)
    readonly property var setup: Logic.setup({ missing: missing, state: snapshot.state,
        service: stepState("service-tailscaled"), operator: stepState("tailscale-operator") })
    readonly property var published: Logic.published(missing, snapshot, setup,
        { accounts: accounts, action: action, login: login, problem: problem })

    // Read from the source, since a change handler can run before the
    // bindings that read it (runtime-qml.md).
    function commandMissing() { return shell === null || shell.requirements.missing.indexOf("tailscale") !== -1; }

    function stepState(name) {
        const found = steps[name];
        return found === undefined ? "" : found.state;
    }

    function publish() {
        if (shell === null) return;
        const setupValue = { tone: setup.tone, text: setup.text };
        if (setup.action !== "") setupValue.action = setup.action;
        const writes = [["connection", { tone: connection.tone, text: connection.text }], ["setup", setupValue], ["vpn", published]];
        for (const write of writes) {
            const reply = shell.status.set(write[0], write[1]);
            if (reply !== "ok") console.warn("vpn: status " + write[0] + " " + reply);
        }
    }
    onPublishedChanged: publish()
    onSetupChanged: publish()

    onShellChanged: {
        if (shell === null) return;
        if (!registered) {
            registered = true;
            shell.ipc.handle("lease", arg => root.lease(arg));
            shell.ipc.handle("action", arg => root.act(arg));
            shell.ipc.handle("refresh", () => root.refresh());
            shell.ipc.handle("open", arg => shell.surfaces.summon("panel", arg || "{}"));
            refresh();
        }
        publish();
    }
    // A scan ends each requirement install, so the command may be new.
    onScansChanged: refresh()
    onMissingChanged: if (missing) snapshot = Logic.emptySnapshot("checking")

    function refresh() {
        if (!registered || commandMissing()) return "ok";
        runPoll("refresh");
        readAccounts();
        return "ok";
    }

    function lease(arg) {
        const request = JSON.parse(arg);
        if (typeof request.id !== "string" || request.id === "" || typeof request.open !== "boolean") return "refused: lease=value";
        const next = Object.assign({}, leases);
        if (request.open) next[request.id] = true;
        else delete next[request.id];
        leases = next;
        if (request.open) refresh();
        return "ok";
    }

    function runPoll(event) {
        const step = Logic.pollStep(poll, event);
        poll = step.state;
        for (const effect of step.effects) {
            switch (effect) {
            case "start":
                pollsStarted++;
                reader.completion = null;
                reader.running = true;
                break;
            case "arm":
                watchdog.restart();
                break;
            case "disarm":
                watchdog.stop();
                break;
            case "kill":
                pollsKilled++;
                console.warn("vpn: poll killed after " + Logic.WATCHDOG_MS + " ms kills=" + pollsKilled);
                reader.signal(9);
                break;
            default:
                throw new Error("vpn: poll effect " + JSON.stringify(effect) + " is not one of start, arm, disarm, kill");
            }
        }
    }

    Timer {
        interval: root.pollInterval
        repeat: true
        running: root.registered && !root.missing
        onTriggered: root.runPoll("tick")
    }

    Timer {
        id: watchdog
        interval: Logic.WATCHDOG_MS
        repeat: false
        onTriggered: root.runPoll("deadline")
    }

    // The exit code of a run that ended on its own, -1 for one a signal
    // ended or that never started (runtime-qml.md).
    function codeOf(completion) {
        return completion === null || completion.status !== 0 ? -1 : completion.code;
    }

    Process {
        id: reader
        property var completion: null
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector { id: statusText; waitForEnd: true }
        stderr: StdioCollector { id: statusErrors; waitForEnd: true }
        onExited: (code, status) => { reader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const code = root.codeOf(completion);
            const next = Logic.snapshot(code, statusText.text, statusErrors.text);
            // One line a change into the state, not one a poll.
            if (next.state === "unavailable" && root.snapshot.state !== "unavailable")
                console.info("vpn: status=unavailable code=" + code + " " + statusErrors.text.trim());
            root.snapshot = next;
            root.runPoll("exit");
        }
    }

    function readAccounts() {
        if (accountsReader.running) {
            accountsReader.again = true;
            return;
        }
        accountsReader.completion = null;
        accountsReader.running = true;
        accountsDeadline.restart();
    }

    Timer {
        id: accountsDeadline
        interval: Logic.WATCHDOG_MS
        repeat: false
        onTriggered: accountsReader.signal(9)
    }

    Process {
        id: accountsReader
        property var completion: null
        property bool again: false
        command: ["tailscale", "switch", "--list"]
        stdout: StdioCollector { id: accountsText; waitForEnd: true }
        stderr: StdioCollector { id: accountsErrors; waitForEnd: true }
        onExited: (code, status) => { accountsReader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            accountsDeadline.stop();
            const code = root.codeOf(completion);
            const read = Logic.accounts(code, accountsText.text);
            if (read.fault !== "" && read.fault !== root.accountsFault)
                console.info("vpn: accounts=" + read.fault + " code=" + code + " " + accountsErrors.text.trim());
            root.accountsFault = read.fault;
            root.accounts = read.rows;
            if (again) {
                again = false;
                root.readAccounts();
            }
        }
    }

    // One command that changes Tailscale at a time.
    function act(arg) {
        const request = JSON.parse(arg);
        if (request.kind === "cancel-login") {
            login = "idle";
            if (signIn.running) root.endLogin();
            return "ok";
        }
        if (commandMissing()) return "refused: action=" + request.kind + " state=missing";
        const plan = Logic.command(request, { state: snapshot.state, exitNodes: snapshot.exitNodes, accounts: accounts });
        if (plan.refusal !== undefined) return plan.refusal;
        if (request.kind === "login") return startLogin(plan.argv);
        if (actor.running) return "busy";
        action = request.kind;
        problem = "";
        actor.completion = null;
        actor.command = plan.argv;
        actor.running = true;
        actionDeadline.restart();
        return "ok";
    }

    Timer {
        id: actionDeadline
        interval: Logic.ACTION_MS
        repeat: false
        onTriggered: actor.signal(9)
    }

    Process {
        id: actor
        property var completion: null
        stderr: StdioCollector { id: actionErrors; waitForEnd: true }
        onExited: (code, status) => { actor.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            actionDeadline.stop();
            const code = root.codeOf(completion);
            if (code !== 0) {
                const kind = code === -1 ? "timeout" : Logic.failureKind(actionErrors.text);
                console.warn("vpn: " + root.action + " failed kind=" + kind + " " + actionErrors.text.trim());
                root.problem = Logic.failureText(kind);
            }
            root.action = "";
            root.refresh();
        }
    }

    // `tailscale login` prints the sign-in page's address and waits until
    // the user finishes there. The first address opens in the browser.
    function startLogin(argv) {
        if (signIn.running) return "busy";
        if (shell.requirements.missing.indexOf("xdg-open") !== -1) {
            shell.requirements.offer(["xdg-open"]);
            return "refused: login=missing-tool";
        }
        login = "waiting";
        problem = "";
        loginSaid = "";
        signIn.completion = null;
        signIn.ended = false;
        signIn.command = argv;
        signIn.running = true;
        loginDeadline.restart();
        return "ok";
    }

    // Ends the sign-in run as the service's own stop, which is no failure.
    function endLogin() {
        signIn.ended = true;
        signIn.running = false;
    }

    function loginLine(text) {
        const url = Logic.loginUrl(text);
        if (url === "") {
            if (loginSaid.length < Logic.LOGIN_SAID_MAX) loginSaid += text + "\n";
            return;
        }
        if (login !== "waiting") return;
        const reply = shell.run.detached(["xdg-open", url]);
        if (reply === "ok") {
            login = "opened";
            return;
        }
        console.warn("vpn: sign-in page " + reply);
        problem = "VGS could not open the sign-in page.";
        endLogin();
    }

    Timer {
        id: loginDeadline
        interval: Logic.LOGIN_MS
        repeat: false
        onTriggered: signIn.signal(9)
    }

    Process {
        id: signIn
        property var completion: null
        // Whether the service ended this run itself.
        property bool ended: false
        stdout: SplitParser { onRead: text => root.loginLine(text) }
        stderr: SplitParser { onRead: text => root.loginLine(text) }
        onExited: (code, status) => { signIn.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            loginDeadline.stop();
            const code = root.codeOf(completion);
            if (!ended && code !== 0) {
                const kind = code === -1 ? "timeout" : Logic.failureKind(root.loginSaid);
                console.warn("vpn: login failed kind=" + kind + " " + root.loginSaid.trim());
                root.problem = Logic.failureText(kind);
            } else if (!ended && root.login === "waiting") {
                root.problem = "Tailscale gave no sign-in page.";
            }
            root.login = "idle";
            root.refresh();
        }
    }
}
