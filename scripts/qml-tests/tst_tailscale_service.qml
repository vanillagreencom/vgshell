import QtQuick
import QtTest
import Quickshell.Io
import "../../shell/plugins/vgs.tailscale" as Tailscale

// Drives the production service and its Process boundaries. The elevated
// transaction's recovery itself is proved by test-vgshell-system.sh.
// inputs: shell/plugins/vgs.tailscale/Service.qml shell/plugins/vgs.tailscale/TailscaleLogic.js scripts/qml-tests/stand-ins/Process.qml scripts/qml-tests/stand-ins/ProcessRegistry.qml
Item {
    id: root
    property var setupDone: []
    property var actionDone: null
    property var writes: ({})
    property bool oldTools: false
    property var offers: []
    // The core's system step reading: none before its first probe, then
    // the operator step's state.
    property bool stepsRead: true
    property string operatorStep: "ready"
    readonly property var profileRows: [{ id: "saved", selected: true, account: "saved@example.test", tailnet: "example.test" }]
    readonly property string running: JSON.stringify({ BackendState: "Running", Self: { ID: "self", HostName: "desk", TailscaleIPs: ["100.64.0.1"] } })
    property var facade: ({
        settings: { pollSeconds: 30 },
        requirements: { missing: [], get outdated() { return root.oldTools ? ["tailscale"] : []; }, revision: 0, offer: commands => { root.offers = root.offers.concat([commands]); return "ok"; } },
        system: { get state() { return root.stepsRead ? { "service-tailscaled": { state: "ready" }, "tailscale-operator": { state: root.operatorStep }, "tailscale-account-add": { state: "needed" } } : {}; },
            refresh: done => { root.setupDone = root.setupDone.concat([done]); return "ok"; } },
        status: { set: (key, value) => { root.writes = Object.assign({}, root.writes, { [key]: value }); return "ok"; },
            act: (key, row, action, done) => { root.actionDone = done; return "ok"; } },
        ipc: { handle: () => "ok" },
        run: { detached: argv => "ok" }
    })
    Component { id: serviceComponent; Tailscale.Service {} }
    TestCase {
        name: "tailscale_service"
        property var service: null
        function process(verb) {
            const found = ProcessRegistry.runningWithVerb(verb);
            compare(found.length, 1, verb + " has one owner");
            return found[0];
        }
        function accounts(rows) {
            const found = ProcessRegistry.runningWithVerb("switch").filter(row => row.command.indexOf("--list") !== -1);
            compare(found.length, 1, "one accounts read owner");
            found[0].finish(0, 0, JSON.stringify(rows === undefined ? root.profileRows : rows), "");
        }
        function status() { process("status").finish(0, 0, root.running, ""); }
        function listReads() { return ProcessRegistry.runningWithVerb("switch").filter(row => row.command.indexOf("--list") !== -1); }
        function failAccounts() {
            const found = listReads();
            compare(found.length, 1, "one accounts read owner");
            found[0].finish(1, 0, "", "Access denied: profiles access denied");
        }
        // One status read that gives BACKEND, or fails with ERRORS.
        function statusAs(backend, errors) {
            if (backend === "") process("status").finish(1, 0, "", errors);
            else process("status").finish(0, 0, JSON.stringify({ BackendState: backend }), "");
        }
        function start() {
            service = createTemporaryObject(serviceComponent, root);
            service.shell = root.facade;
        }
        function setup() {
            const done = root.setupDone[root.setupDone.length - 1];
            done();
        }
        function fresh() { status(); accounts(); setup(); }
        function act(kind, id) { return service.act(JSON.stringify({ kind: kind, id: id === undefined ? "" : id })); }
        function signIn() {
            compare(act("sign-in", "saved"), "ok");
            process("switch").finish(0, 0, "", ""); accounts();
            return process("up");
        }
        function opener() {
            const found = ProcessRegistry.processes.filter(row => row.running && row.command[1] === "-c");
            compare(found.length, 1, "one tracked opener owns the browser result");
            return found[0];
        }
        function init() {
            ProcessRegistry.clear();
            root.setupDone = []; root.actionDone = null; root.writes = {}; root.oldTools = false; root.offers = [];
            root.stepsRead = true; root.operatorStep = "ready";
            root.facade.requirements.missing = [];
            start();
            fresh();
            compare(service.checkingSetup, false);
        }
        function cleanup() { service.destroy(); wait(0); }
        function test_add_serializes_until_scoped_failure_and_requests_fresh_reads() {
            compare(act("add-account"), "ok");
            compare(service.action, "add-account");
            compare(root.writes.setup, null);
            for (const kind of ["switch", "sign-in", "logout", "add-account"]) compare(act(kind, "saved"), "busy");
            service.lease(JSON.stringify({ id: "view", open: true }));
            fresh();
            verify(service.checkingSetup, "completed reads cannot publish setup while Add still owns the mutation");
            compare(service.setup, null);
            compare(root.writes.setup, null);
            compare(service.action, "add-account");
            root.actionDone({ code: 1, reason: "ended" });
            compare(service.action, "");
            verify(service.problem !== "");
            verify(service.checkingSetup);
            setup();
            verify(service.checkingSetup, "a fresh setup probe alone cannot bless old profile readings");
            status(); accounts();
            verify(!service.checkingSetup);
        }
        function test_open_during_reads_waits_for_subsequent_reads_even_if_unchanged() {
            service.refresh();
            service.lease(JSON.stringify({ id: "view", open: true }));
            status(); accounts(); setup();
            verify(service.checkingSetup);
            status(); accounts();
            verify(!service.checkingSetup);
        }
        // Below the floor the reads and the connection controls run; only
        // Add account and Sign in are refused, each with the update notice.
        function test_outdated_tool_stops_only_the_account_requests() {
            root.oldTools = true;
            service.refresh();
            fresh();
            compare(root.writes.tailscale.state, "running");
            compare(root.writes.tailscale.writable, true);
            compare(root.writes.tailscale.outdated, true);
            compare(root.writes.setup.tone, "ok", "the Tailscale service step stays Ready");
            compare(root.writes.accountAdd.action, false);
            compare(act("add-account"), "refused: action=add-account state=outdated");
            compare(act("sign-in", "saved"), "refused: action=sign-in state=outdated");
            compare(root.offers, [["tailscale"], ["tailscale"]]);
            compare(root.actionDone, null);
            compare(ProcessRegistry.runningWithVerb("switch").length, 0);
            compare(act("disconnect"), "ok");
            compare(process("down").command, ["tailscale", "down"]);
        }
        // A failed accounts read publishes no list read, so the views tell
        // it from no saved account.
        function test_failed_accounts_read_is_published_unread() {
            compare(root.writes.tailscale.accountsRead, true);
            service.refresh();
            status();
            const reads = ProcessRegistry.runningWithVerb("switch").filter(row => row.command.indexOf("--list") !== -1);
            compare(reads.length, 1, "one accounts read owner");
            reads[0].finish(1, 0, "", "Access denied: profiles access denied");
            setup();
            compare(root.writes.tailscale.accountsRead, false);
            compare(root.writes.tailscale.accounts, []);
        }
        // A setup step the core runs, such as Allow, never reaches the
        // service; the step's new state does, and reads the list again.
        function test_allow_reads_the_accounts_again() {
            root.operatorStep = "needed";
            service.refresh();
            status(); failAccounts(); setup();
            compare(root.writes.tailscale.accountsRead, false);
            compare(listReads().length, 0, "a failed read under the current access is not repeated");
            root.operatorStep = "ready";
            compare(listReads().length, 1, "the new access starts one read");
            verify(service.checkingSetup, "the stale fault is not shown while the read runs");
            compare(root.writes.tailscale.checkingSetup, true);
            accounts();
            compare(listReads().length, 0, "the read that gave a list is not repeated");
            verify(!service.checkingSetup);
            compare(root.writes.tailscale.accountsRead, true);
            compare(root.writes.tailscale.accounts.map(row => row.id), ["saved"]);
        }
        // A re-read that fails gives the same fault kind under its new
        // access, and its cause reaches the log under that access. The
        // engine locks `console`, so no case can observe the info line;
        // the reader's record of the access it logged under is set in the
        // line's branch and stands for it.
        function test_a_reread_fault_is_logged_under_its_access() {
            const reader = ProcessRegistry.processes.filter(row => row.command.indexOf("--list") !== -1)[0];
            root.operatorStep = "needed";
            service.refresh();
            status(); failAccounts(); setup();
            compare(reader.loggedAccess, "needed");
            root.operatorStep = "ready";
            listReads()[0].finish(1, 0, "", "another cause");
            compare(service.accountsFault, "failed");
            compare(reader.loggedAccess, "ready", "the re-read's fault is logged under its own access");
            service.refresh();
            status(); accounts(); setup();
            compare(reader.loggedAccess, "", "a list ends the logged fault");
        }
        // tailscaled that comes back is seen by the poll alone, which reads
        // no accounts. `before` fails a poll before the refresh's reads
        // start; `during` fails the refresh's own status read while its
        // accounts read runs.
        function test_daemon_that_answers_reads_the_accounts_again_data() {
            const rows = [];
            for (const down of [{ name: "service-off", errors: "failed to connect to local tailscaled; it doesn't appear to be running" },
                    { name: "unavailable", errors: "unexpected state" }])
                for (const when of ["before", "during"])
                    for (const backend of ["NeedsLogin", "Running"])
                        rows.push({ tag: down.name + "-" + when + "-then-" + backend, down: down, when: when, backend: backend });
            return rows;
        }
        function test_daemon_that_answers_reads_the_accounts_again(data) {
            if (data.when === "before") {
                service.runPoll("tick");
                statusAs("", data.down.errors);
            }
            service.refresh();
            if (data.when === "during") statusAs("", data.down.errors);
            failAccounts();
            if (data.when === "before") statusAs("", data.down.errors);
            setup();
            compare(service.snapshot.state, data.down.name);
            compare(root.writes.tailscale.accountsRead, false);
            compare(listReads().length, 0, "no read while tailscaled does not answer");
            service.runPoll("tick");
            statusAs(data.backend, "");
            compare(listReads().length, 1, "tailscaled that answers starts one read");
            verify(service.checkingSetup);
            accounts();
            compare(listReads().length, 0);
            compare(root.writes.tailscale.accountsRead, true);
        }
        // A read is repeated only for a new access: never for a read that
        // gave a list, and never for a fault under the access it ran under.
        function test_no_read_without_a_new_access() {
            for (const backend of ["Stopped", ""]) {
                service.runPoll("tick");
                statusAs(backend, "failed to connect to local tailscaled");
                compare(listReads().length, 0, "a read that gave a list is not repeated: " + backend);
            }
            service.runPoll("tick");
            status();
            compare(listReads().length, 0, "tailscaled that answers again repeats no list");
            service.refresh();
            status(); failAccounts(); setup();
            compare(listReads().length, 0, "a fault under the current access is not repeated");
            service.runPoll("tick");
            statusAs("", "failed to connect to local tailscaled");
            service.runPoll("tick");
            status();
            compare(listReads().length, 0, "the access the fault ran under is not a new access");
            compare(root.writes.tailscale.accountsRead, false);
        }
        // The registration read can end before the core's first step
        // probe and the first status poll, under no access at all.
        function test_startup_read_runs_again_once_the_access_lands_data() {
            return [{ tag: "after the read", whileRead: false }, { tag: "while the read runs", whileRead: true }];
        }
        function test_startup_read_runs_again_once_the_access_lands(data) {
            service.destroy(); wait(0);
            ProcessRegistry.clear();
            root.setupDone = []; root.writes = {};
            root.stepsRead = false;
            start();
            compare(service.accountsAccess, "");
            if (data.whileRead) { root.stepsRead = true; status(); }
            failAccounts();
            if (!data.whileRead) {
                compare(listReads().length, 0, "no read under no access");
                root.stepsRead = true;
                compare(listReads().length, 0, "no read before the poll lands");
                status();
            }
            setup();
            compare(listReads().length, 1, "the landed access starts one read");
            verify(service.checkingSetup);
            accounts();
            compare(listReads().length, 0);
            verify(!service.checkingSetup);
            compare(root.writes.tailscale.accountsRead, true);
        }
        function test_sign_in_selects_and_verifies_saved_id_before_up() {
            compare(act("sign-in", "saved"), "ok");
            compare(process("switch").command, ["tailscale", "switch", "saved"]);
            process("switch").finish(1, 0, "", "");
            compare(ProcessRegistry.runningWithVerb("up").length, 0);
            accounts();
            const auth = process("up");
            compare(auth.command, ["tailscale", "up", "--timeout", "0"]);
            auth.stderr.read("https://login.example.test/auth");
            const browser = opener();
            compare(browser.environment.VGS_TAILSCALE_AUTH_URL, "https://login.example.test/auth");
            verify(browser.command.join(" ").indexOf("https://") === -1, "startup diagnostics cannot print the private address");
            compare(service.login, "opening");
            browser.finish(0, 0, "", "");
            compare(service.login, "opened");
            compare(act("logout"), "busy");
            auth.finish(0, 0, "", "");
            verify(service.checkingSetup);
            fresh();
            compare(service.action, "");
        }
        function test_selection_mismatch_authenticates_nothing() {
            compare(act("sign-in", "saved"), "ok");
            process("switch").finish(0, 0, "", "");
            accounts([]);
            compare(ProcessRegistry.runningWithVerb("up").length, 0);
            verify(service.problem !== "");
            compare(service.action, "");
        }
        function test_profile_verification_waits_for_actor_data() {
            const rows = [];
            for (const kind of ["switch", "sign-in"])
                for (const earlySelected of [false, true])
                    for (const readHeld of [false, true])
                        rows.push({ tag: kind + "-early-" + earlySelected + "-held-" + readHeld, kind: kind, earlySelected: earlySelected, readHeld: readHeld });
            return rows;
        }
        function test_profile_verification_waits_for_actor(data) {
            compare(act(data.kind, "saved"), "ok");
            const actor = process("switch");
            service.lease(JSON.stringify({ id: "new-view", open: true }));
            accounts(data.earlySelected ? root.profileRows : []);
            compare(actor.running, true);
            compare(service.action, data.kind);
            compare(service.pendingProfile, "saved");
            compare(service.problem, "");
            compare(ProcessRegistry.runningWithVerb("up").length, 0);
            compare(act("add-account"), "busy");
            if (data.readHeld) service.refresh();
            actor.finish(0, 0, "", "");
            compare(service.action, data.kind);
            compare(ProcessRegistry.runningWithVerb("up").length, 0);
            if (data.readHeld) {
                accounts([]);
                compare(service.action, data.kind);
                compare(service.pendingProfile, "saved");
                compare(service.problem, "");
                compare(ProcessRegistry.runningWithVerb("up").length, 0);
            }
            accounts();
            compare(service.pendingProfile, "");
            compare(service.problem, "");
            if (data.kind === "sign-in") {
                compare(service.action, "sign-in");
                process("up").finish(0, 0, "", "");
                compare(service.login, "idle");
            }
            compare(service.action, "");
            verify(service.checkingSetup);
        }
        function test_authenticated_profile_reconnects_without_address() {
            compare(act("sign-in", "saved"), "ok");
            process("switch").finish(0, 0, "", ""); accounts();
            process("up").finish(0, 0, "", "");
            compare(service.login, "idle");
            compare(service.problem, "");
            compare(service.action, "");
            compare(ProcessRegistry.processes.filter(row => row.running && row.command[1] === "-c").length, 0);
            verify(service.checkingSetup);
        }
        function test_missing_opener_tool_data() {
            return [{ tag: "shell", missing: ["sh"] }, { tag: "opener", missing: ["xdg-open"] }, { tag: "both", missing: ["sh", "xdg-open"] }];
        }
        function test_missing_opener_tool(data) {
            root.facade.requirements.missing = data.missing;
            compare(act("sign-in", "saved"), "ok");
            process("switch").finish(0, 0, "", ""); accounts();
            compare(ProcessRegistry.runningWithVerb("up").length, 0);
            compare(root.offers, [data.missing]);
            compare(service.action, "");
            verify(service.problem !== "");
        }
        function test_opener_failure_data() {
            return [{ tag: "failed-start", ending: "start" }, { tag: "nonzero", ending: "exit" }, { tag: "deadline", ending: "deadline" }];
        }
        function test_opener_failure(data) {
            const auth = signIn();
            auth.stderr.read("https://login.example.test/private-auth");
            const browser = opener();
            compare(act("add-account"), "busy");
            if (data.ending === "start") browser.failStart();
            else if (data.ending === "exit") browser.finish(1, 0, "", "private output is not a cause");
            else findChild(service, "tailscale-browser-deadline").triggered();
            verify(service.problem !== "");
            verify(service.problem.indexOf("private") === -1);
            compare(service.login, "idle");
            compare(service.action, "");
            compare(ProcessRegistry.runningWithVerb("up").length, 0);
            verify(service.checkingSetup);
            auth.stderr.read("https://login.example.test/late-address");
            compare(ProcessRegistry.processes.filter(row => row.running && row.command[1] === "-c").length, 0);
            fresh();
            compare(act("add-account"), "ok");
            browser.exited(0, 0);
            compare(service.action, "add-account");
        }
        function test_cancel_stops_the_owned_opener_and_ignores_late_address() {
            const auth = signIn();
            auth.stderr.read("https://login.example.test/private-auth");
            const browser = opener();
            compare(act("cancel-login"), "ok");
            compare(browser.running, false);
            compare(auth.running, false);
            compare(service.action, "");
            compare(service.problem, "");
            auth.stderr.read("https://login.example.test/late-address");
            compare(browser.running, false);
        }
        function test_auth_completion_waits_for_the_opener_result() {
            const auth = signIn();
            auth.stderr.read("https://login.example.test/private-auth");
            const browser = opener();
            auth.finish(0, 0, "", "");
            compare(act("add-account"), "busy");
            browser.finish(1, 0, "", "");
            verify(service.problem !== "");
            compare(service.action, "");
        }
    }
}
