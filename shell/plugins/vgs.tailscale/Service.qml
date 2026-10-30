import QtQuick
import Quickshell
import Quickshell.Io
import "TailscaleLogic.js" as Logic

// The Tailscale service: the one owner of every `tailscale` process and of the
// poll (TailscaleLogic.js decides; this runs the effects). The widget, the
// flyout and the pane read what it publishes and start no process. They
// ask it through the plugin's own IPC, which `vgshell ipc call vgs.tailscale
// invoke <name> <arg>` reaches too:
//   lease {"id","open"}   a view opens or closes; an open view makes the
//                         poll fast; answers `ok` or a refusal
//   action {"kind","id"}  connect, disconnect, exit-node, switch, add-account, sign-in,
//                         cancel-login, logout or admin-console; answers
//                         `ok`, `busy` or a refusal
//   refresh               read Tailscale now; answers `ok`
//   suggest               read the suggested exit node now; answers `ok`,
//                         `busy` while one read runs, or a refusal
//   open                  summon the flyout
//
// The poll runs `tailscale status --json` every `pollSeconds` while no
// view is open, and every 3 s while one is or Tailscale is starting, one
// run at a time. A refresh also reads the accounts, `tailscale switch
// --list --json`. `tailscale exit-node suggest` runs when the exit node
// chooser asks and when the state turns running, one at a time. Each of
// those reads is killed 10 s after its start, and a refresh never moves
// that deadline. It publishes `connection` and `setup`, the lines the
// Settings page draws, `tailscale`, the connection, account and this
// device the views draw, and `devices` and `exitNodes`, each within its
// byte budget (TailscaleLogic.statusWrites).
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    property bool registered: false
    property var leases: ({})
    readonly property int leaseCount: Object.keys(leases).length
    readonly property bool missing: commandMissing()
    // Below the manifest's floor only Add account and Sign in stop
    // (TailscaleLogic.FLOOR_KINDS); the reads and every other change run.
    readonly property bool outdated: shell !== null && shell.requirements.outdated.indexOf("tailscale") !== -1
    readonly property int scans: shell === null ? 0 : shell.requirements.revision
    readonly property int pollInterval: Logic.pollInterval(leaseCount > 0, snapshot.state, shell === null ? 30 : shell.settings.pollSeconds)
    readonly property var steps: shell === null ? ({}) : shell.system.state

    property var poll: Logic.pollIdle()
    // The polls started and the polls the watchdog killed, for the log
    // line of a kill and the smoke row's count of the stand-in's calls.
    property int pollsStarted: 0
    property int pollsKilled: 0
    property var snapshot: Logic.emptySnapshot("checking")
    property var accounts: []
    // Why the last accounts read gave no list, "" for one that did, and
    // `unread` before the first read ends.
    property string accountsFault: "unread"
    // The DNS name of the exit node the last suggestion read named, "" for
    // none, and why that read named none, "" for a read that did.
    property string suggestedName: ""
    property string suggestFault: ""
    // The suggestion reads started, for the smoke row's count of the
    // stand-in's calls.
    property int suggestsStarted: 0
    // The command that runs now, "" for none.
    property string action: ""
    // `idle`, `waiting` for the address, `opening` the page, or `opened`.
    property string login: "idle"
    // The lines the sign-in run printed that hold no address, which name
    // a failed run's cause.
    property string loginSaid: ""
    // The line the last failed command left, "" for none.
    property string problem: ""
    property bool setupPending: true
    property int setupRequest: 0
    property string pendingProfile: ""
    property int statusReads: 0
    property int accountReads: 0
    property int freshStatusAfter: 0
    property int freshAccountsAfter: 0
    readonly property bool checkingSetup: action !== "" || setupPending || statusReads < freshStatusAfter || accountReads < freshAccountsAfter

    readonly property var connection: Logic.connection(missing, snapshot)
    readonly property var setup: checkingSetup && !missing ? null : Logic.setup({ missing: missing, state: snapshot.state,
        service: stepState("service-tailscaled"), operator: stepState("tailscale-operator") })
    readonly property var published: Logic.published(missing, snapshot, setup,
        { accounts: accounts, accountsRead: accountsFault === "", outdated: outdated, action: action, login: login, problem: problem,
            suggestion: Logic.suggestion(suggestedName, snapshot),
            backendPresent: stepState("service-tailscaled") !== "absent" })

    // Read from the source, since a change handler can run before the
    // bindings that read it.
    function commandMissing() { return shell === null || shell.requirements.missing.indexOf("tailscale") !== -1; }

    function stepState(name) {
        const found = steps[name];
        return found === undefined ? "" : found.state;
    }

    function publish() {
        if (shell === null) return;
        const writes = Logic.statusWrites(connection, setup, published, snapshot.devices, snapshot.exitNodes)
            .concat([["accountAdd", { tone: "info", text: "Add account", action: !outdated && stepState("tailscale-account-add") === "needed" }]]);
        for (const write of writes) {
            const reply = shell.status.set(write[0], write[1]);
            if (reply !== "ok") console.warn("tailscale: status " + write[0] + " " + reply);
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
            shell.ipc.handle("suggest", () => root.suggest());
            shell.ipc.handle("open", arg => shell.surfaces.summon("panel", arg || "{}"));
            refresh();
        }
        publish();
    }
    // A scan ends each requirement install, so the command may be new.
    onScansChanged: refresh()
    onMissingChanged: if (missing) snapshot = Logic.emptySnapshot("checking")

    function refresh() {
        if (!registered) return "ok";
        const serial = ++setupRequest;
        setupPending = true;
        const readable = !commandMissing();
        freshStatusAfter = statusReads + (readable ? reader.running ? 2 : 1 : 0);
        freshAccountsAfter = accountReads + (readable ? accountsReader.running ? 2 : 1 : 0);
        const reply = shell.system.refresh(() => {
            if (serial === root.setupRequest) root.setupPending = false;
        });
        if (reply !== "ok") {
            console.warn("tailscale: setup " + reply);
            problem = "VGS could not check Tailscale access.";
        }
        if (!readable) return "ok";
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
                console.warn("tailscale: poll killed after " + Logic.WATCHDOG_MS + " ms kills=" + pollsKilled);
                reader.signal(9);
                break;
            default:
                throw new Error("tailscale: poll effect " + JSON.stringify(effect) + " is not one of start, arm, disarm, kill");
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
    // ended or that never started, which leaves `completion` null.
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
                console.info("tailscale: status=unavailable code=" + code + " " + statusErrors.text.trim());
            const was = root.snapshot.state;
            root.snapshot = next;
            root.statusReads++;
            if (next.state !== "running") root.suggestedName = "";
            else if (was !== "running") root.suggest();
            root.runPoll("exit");
        }
    }

    function readAccounts(profile) {
        if (profile !== undefined) accountsReader.nextProfile = profile;
        if (accountsReader.running) {
            accountsReader.again = true;
            return;
        }
        accountsReader.completion = null;
        accountsReader.verifying = accountsReader.nextProfile;
        accountsReader.nextProfile = "";
        accountsDeadline.restart();
        accountsReader.running = true;
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
        property string nextProfile: ""
        property string verifying: ""
        command: ["tailscale", "switch", "--list", "--json"]
        stdout: StdioCollector { id: accountsText; waitForEnd: true }
        stderr: StdioCollector { id: accountsErrors; waitForEnd: true }
        onExited: (code, status) => { accountsReader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            accountsDeadline.stop();
            const code = root.codeOf(completion);
            const read = Logic.accounts(code, accountsText.text);
            if (read.fault !== "" && read.fault !== root.accountsFault)
                console.info("tailscale: accounts=" + read.fault + " code=" + code + " " + accountsErrors.text.trim());
            root.accountsFault = read.fault;
            root.accounts = read.rows;
            root.accountReads++;
            if (verifying !== "") {
                const selected = read.fault === "" && read.rows.some(row => row.id === verifying && row.current);
                root.pendingProfile = "";
                if (!selected) {
                    root.problem = "Tailscale could not select this account.";
                    root.finishAction();
                } else if (root.action === "sign-in") {
                    // up authenticates the selected profile and refuses a
                    // preference reset: tailscale v1.104.1 cli/up.go.
                    root.startLogin(["tailscale", "up", "--timeout", "0"]);
                } else root.finishAction();
                verifying = "";
            }
            if (again) {
                again = false;
                root.readAccounts();
            }
        }
    }

    // One suggestion read at a time, only while Tailscale runs: the CLI
    // suggests from the nodes the running tailnet offers.
    function suggest() {
        if (!registered || commandMissing()) return "refused: suggest state=missing";
        if (snapshot.state !== "running") return "refused: suggest state=" + snapshot.state;
        if (suggester.running) return "busy";
        suggestsStarted++;
        suggester.completion = null;
        suggester.running = true;
        suggestDeadline.restart();
        return "ok";
    }

    Timer {
        id: suggestDeadline
        interval: Logic.WATCHDOG_MS
        repeat: false
        onTriggered: suggester.signal(9)
    }

    Process {
        id: suggester
        property var completion: null
        command: ["tailscale", "exit-node", "suggest"]
        stdout: StdioCollector { id: suggestText; waitForEnd: true }
        stderr: StdioCollector { id: suggestErrors; waitForEnd: true }
        onExited: (code, status) => { suggester.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            suggestDeadline.stop();
            const code = root.codeOf(completion);
            const read = Logic.suggested(code, suggestText.text);
            if (read.fault !== "" && read.fault !== root.suggestFault)
                console.info("tailscale: suggest=" + read.fault + " code=" + code + " " + suggestErrors.text.trim());
            root.suggestFault = read.fault;
            // A read that ends after Tailscale stopped running names nothing.
            root.suggestedName = root.snapshot.state === "running" ? read.name : "";
        }
    }

    // One command that changes Tailscale at a time. Opening the admin
    // console changes nothing and runs beside them.
    function act(arg) {
        const request = JSON.parse(arg);
        if (request.kind === "cancel-login") {
            if (login !== "idle") root.endLogin();
            return "ok";
        }
        if (request.kind === "admin-console") return openAdminConsole();
        if (action !== "") return "busy";
        if (commandMissing()) return "refused: action=" + request.kind + " state=missing";
        const plan = Logic.command(request, { state: snapshot.state, targets: snapshot.targets, accounts: accounts, outdated: outdated });
        if (plan.update === true) shell.requirements.offer(["tailscale"]);
        if (plan.refusal !== undefined) return plan.refusal;
        if (request.kind !== "add-account" && !published.writable) return "refused: action=" + request.kind + " access=unchecked";
        action = request.kind;
        setupPending = true;
        problem = "";
        if (request.kind === "add-account") {
            const reply = shell.status.act(plan.system, undefined, undefined, end => {
                if (end.code !== 0) root.problem = "The account was not added; review the result in the setup window.";
                root.finishAction();
            });
            if (reply !== "ok") {
                problem = reply === "busy" ? Logic.replyText(reply) : "VGS could not open the account setup window.";
                finishAction();
            }
            return reply;
        }
        pendingProfile = request.kind === "switch" || request.kind === "sign-in" ? request.id : "";
        actor.completion = null;
        actor.command = plan.argv;
        actionDeadline.restart();
        actor.running = true;
        return "ok";
    }

    function finishAction() {
        refresh();
        action = "";
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
            // A stopped profile can be selected even when switch exits
            // nonzero. Verify the stable selected ID before up or success.
            if (root.pendingProfile !== "") {
                // A view refresh can overlap switch. Only its completion
                // requests a new read that can verify the selected profile.
                root.readAccounts(root.pendingProfile);
                return;
            }
            if (code !== 0) {
                const kind = code === -1 ? "timeout" : Logic.failureKind(actionErrors.text);
                console.warn("tailscale: " + root.action + " failed kind=" + kind + " " + actionErrors.text.trim());
                root.problem = Logic.failureText(kind);
            }
            root.finishAction();
        }
    }

    function openAdminConsole() {
        if (shell.requirements.missing.indexOf("xdg-open") !== -1) {
            shell.requirements.offer(["xdg-open"]);
            return "refused: admin-console=missing-tool";
        }
        const reply = shell.run.detached(Logic.command({ kind: "admin-console" }, { state: snapshot.state, targets: {}, accounts: [] }).argv);
        if (reply !== "ok") console.warn("tailscale: admin console " + reply);
        return reply;
    }

    // `tailscale up` reconnects an authenticated profile directly, or
    // prints an address and waits for the user to finish in the browser.
    function startLogin(argv) {
        if (signIn.running || browser.running) return "busy";
        const missing = ["sh", "xdg-open"].filter(command => shell.requirements.missing.indexOf(command) !== -1);
        if (missing.length > 0) {
            shell.requirements.offer(missing);
            problem = "A browser tool is missing; use the installation notice to add it.";
            finishAction();
            return "refused: login=missing-tool";
        }
        login = "waiting";
        problem = "";
        loginSaid = "";
        signIn.completion = null;
        signIn.ended = false;
        signIn.command = argv;
        loginDeadline.restart();
        signIn.running = true;
        return "ok";
    }

    // Ends the sign-in run as the service's own stop, which is no failure.
    function endLogin() {
        if (signIn.ended) return;
        signIn.ended = true;
        loginDeadline.stop();
        browserDeadline.stop();
        loginCleanup.restart();
        browser.environment = ({});
        browser.running = false;
        signIn.running = false;
        finishLogin();
    }

    function finishLogin() {
        if (login === "idle" || signIn.running || browser.running) return;
        loginDeadline.stop();
        browserDeadline.stop();
        loginCleanup.stop();
        login = "idle";
        finishAction();
    }

    function loginLine(text) {
        if (signIn.ended || action !== "sign-in") return;
        const url = Logic.loginUrl(text);
        if (url === "") {
            if (loginSaid.length < Logic.LOGIN_SAID_MAX) loginSaid += text + "\n";
            return;
        }
        if (login !== "waiting") return;
        login = "opening";
        browser.completion = null;
        browser.environment = ({ VGSHELL_RUNNER_PID: null, VGS_TAILSCALE_AUTH_URL: url });
        browserDeadline.restart();
        browser.running = true;
    }

    Timer {
        id: browserDeadline
        objectName: "tailscale-browser-deadline"
        interval: Logic.WATCHDOG_MS
        repeat: false
        onTriggered: {
            if (signIn.ended) return;
            root.problem = "The browser tool did not answer; try signing in again.";
            root.endLogin();
        }
    }

    Timer {
        id: loginCleanup
        // The managed-child cleanup grace is runtime.md's five seconds.
        interval: 5000
        repeat: false
        onTriggered: {
            if (browser.running) browser.signal(9);
            if (signIn.running) signIn.signal(9);
        }
    }

    Process {
        id: browser
        property var completion: null
        // Process FailedToStart logs argv. Keep the address out of that
        // diagnostic and out of descendants' environment. Fixed shell
        // source reads data only; it never evaluates the private address.
        command: ["sh", "-c", "set -- \"$VGS_TAILSCALE_AUTH_URL\"; unset VGS_TAILSCALE_AUTH_URL; exec xdg-open \"$1\""]
        // Drain neither channel into a log or status: browser errors may
        // repeat the authentication address.
        onStarted: browser.environment = ({})
        onExited: (code, status) => { browser.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            browserDeadline.stop();
            browser.environment = ({});
            // v0.3.1 Process emits exited before runningChanged; failed
            // startup emits only runningChanged. Both owners must stop
            // before action release, so no old completion crosses a retry.
            // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/
            if (!signIn.ended && root.login === "opening") {
                if (root.codeOf(completion) === 0) root.login = "opened";
                else {
                    root.problem = completion === null ? "VGS could not start the browser tool." : "The browser tool could not open the sign-in page.";
                    root.endLogin();
                }
            }
            root.finishLogin();
        }
    }

    Timer {
        id: loginDeadline
        interval: Logic.LOGIN_MS
        repeat: false
        onTriggered: {
            if (signIn.ended) return;
            root.problem = Logic.failureText("timeout");
            root.endLogin();
        }
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
            const code = root.codeOf(completion);
            if (!ended && code !== 0) {
                const kind = code === -1 ? "timeout" : Logic.failureKind(root.loginSaid);
                console.warn("tailscale: login failed kind=" + kind + " " + root.loginSaid.trim());
                root.problem = Logic.failureText(kind);
                root.endLogin();
            }
            root.finishLogin();
        }
    }
}
