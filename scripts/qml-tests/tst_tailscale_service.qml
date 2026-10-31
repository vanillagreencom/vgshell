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
    readonly property var profileRows: [{ id: "saved", selected: true, account: "saved@example.test", tailnet: "example.test" }]
    readonly property string running: JSON.stringify({ BackendState: "Running", Self: { ID: "self", HostName: "desk", TailscaleIPs: ["100.64.0.1"] } })
    property var facade: ({
        settings: { pollSeconds: 30 },
        requirements: { missing: [], get outdated() { return root.oldTools ? ["tailscale"] : []; }, revision: 0, offer: commands => { root.offers = root.offers.concat([commands]); return "ok"; } },
        system: { state: { "service-tailscaled": { state: "ready" }, "tailscale-operator": { state: "ready" }, "tailscale-account-add": { state: "needed" } },
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
        function accounts(rows) { process("switch").finish(0, 0, JSON.stringify(rows === undefined ? root.profileRows : rows), ""); }
        function status() { process("status").finish(0, 0, root.running, ""); }
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
            root.facade.requirements.missing = [];
            service = createTemporaryObject(serviceComponent, root);
            service.shell = root.facade;
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
        function test_outdated_tool_uses_the_existing_upgrade_notice() {
            root.oldTools = true;
            service.refresh();
            compare(root.writes.setup.action, "tools");
            compare(root.writes.accountAdd.action, false);
            compare(act("add-account"), "refused: action=add-account state=outdated");
            compare(root.offers, [["tailscale"]]);
            compare(root.actionDone, null);
            compare(ProcessRegistry.runningWithVerb("login").length, 0);
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
        function test_auth_without_address_has_a_reason() {
            compare(act("sign-in", "saved"), "ok");
            process("switch").finish(0, 0, "", ""); accounts();
            process("up").finish(0, 0, "", "");
            compare(service.login, "idle");
            verify(service.problem !== "");
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
