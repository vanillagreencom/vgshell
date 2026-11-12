import QtQuick
import QtTest
import Quickshell.Io
import qs.Core
import "../../shell/plugins/vgs.updates" as Updates
import "../../shell/plugins/vgs.updates/UpdatesLogic.js" as Logic

// Drive the production service, window and each separately observed status
// write. Processes and startup reads finish only when the case answers them.
// inputs: shell/plugins/vgs.updates/* scripts/qml-tests/stand-ins/Process.qml scripts/qml-tests/stand-ins/FileView.qml
Item {
    id: root
    width: 900
    height: 900
    property var values: ({})
    property var handlers: ({})
    property var observed: []
    property string refuseKey: ""
    property var facade: ({
        settings: {}, screens: { current: null }, system: { state: {} }, tui: { state: {} },
        shortcut: { register: () => "ok" }, surfaces: { hide: () => "ok" },
        ipc: { handle: (name, run) => { root.handlers[name] = run; return "ok"; },
            call: (name, arg) => root.handlers[name] === undefined ? "unknown: " + name : root.handlers[name](arg) },
        status: { viewed: false, handleChoice: () => "ok", isOk: PluginLogic.statusReplyOk,
            get values() { return root.values; },
            set: (key, value) => {
                if (key === root.refuseKey) return "refused: status=test-unavailable";
                root.values = Object.assign({}, root.values, { [key]: value });
                root.observed = root.observed.concat([JSON.parse(JSON.stringify(root.values))]);
                return "ok";
            } }
    })
    Component { id: serviceComponent; Updates.Service {} }
    Component { id: windowComponent; Updates.Window {} }
    TestCase {
        id: tests
        name: "updates_refresh"
        property var service: null
        property var view: null
        function snapshot(count) {
            return JSON.stringify({ checkedAt: Date.now(), error: null,
                sources: [{ source: "pacman", label: "System", count: count, error: null,
                    packages: [{ name: "old-package", old: "1", new: "2" }], checkedAt: Date.now() }] });
        }
        function reader(path) {
            const found = Array.from(service.data).filter(row => row.path === path);
            compare(found.length, 1);
            return found[0];
        }
        function process(name) {
            const found = ProcessRegistry.processes.filter(row => row.running && row.command.some(arg => String(arg).endsWith(name)));
            compare(found.length, 1, name + " has one owner");
            return found[0];
        }
        function checks() {
            return ProcessRegistry.processes.filter(row => row.running && row.command[0].endsWith("bin/check"));
        }
        function admission(value) { process("connectivity.js").finish(0, 0, JSON.stringify({ connectivity: value }), ""); }
        function startup() {
            reader(service.statusPath).finishRead(snapshot(97));
            reader(service.bootPath).finishRead("btime 1\n");
        }
        function init() {
            ProcessRegistry.clear(); root.values = {}; root.observed = []; root.handlers = {}; root.refuseKey = "";
            service = createTemporaryObject(serviceComponent, root);
            service.shell = root.facade;
            view = createTemporaryObject(windowComponent, root, { shell: root.facade });
        }
        function cleanup() { view.destroy(); service.destroy(); wait(0); }
        function test_open_waits_for_startup_and_never_unmasks_a_mixed_result() {
            view.open("{}");
            compare(view.view.state, "checking", "the opening frame is masked before startup reads answer");
            compare(ProcessRegistry.processes.filter(row => row.running).length, 0);
            startup();
            compare(checks().length, 0, "admission precedes every check");
            admission(4);
            compare(service.requestCheck("ipc"), "queued", "open/manual requests join this refresh");
            const during = Logic.windowRows(root.values)[0];
            compare([during.spinning, during.badge, during.lines.length, during.detail, during.more, during.updatable], [true, "", 0, "", "", false]);
            compare(Logic.widgetView(root.values, false).badge, "");
            process("bin/check").finish(0, 0, snapshot(3), "");
            compare(service.checking, false);
            compare(root.values.pending, 3);
            compare(Logic.windowRows(root.values)[0].badge, "3");
            for (const values of root.observed) {
                if (values.checking === true) {
                    compare(Logic.widgetView(values, false).badge, "");
                    for (const row of Logic.windowRows(values))
                        compare([row.spinning, row.badge, row.lines.length, row.updatable], [true, "", 0, false]);
                } else if (values.admission === "online") {
                    compare(values.pending, 3, "no publication exposes an old total as the new answer");
                    compare(values.sources[0].count, 3);
                }
            }
            compare(checks().length, 0, "joining did not queue a duplicate");
        }
        function test_offline_and_unavailable_never_start_a_check_data() {
            return [{ tag: "none", value: 1, state: "offline" }, { tag: "portal", value: 2, state: "offline" },
                { tag: "limited", value: 3, state: "offline" }, { tag: "unknown", value: 0, state: "unavailable" },
                { tag: "unread", value: null, state: "unavailable" }];
        }
        function test_offline_and_unavailable_never_start_a_check(data) {
            startup(); view.open("{}"); admission(data.value);
            compare(root.values.admission, data.state);
            compare(service.checking, false); compare(checks().length, 0);
            compare(root.values.pending, 97);
            verify(Logic.lastKnown(root.values));
            compare(Logic.windowRows(root.values)[0].updatable, false);
            verify(Logic.updateDisabledReason(root.values) !== "");
            view.refresh(); admission(4);
            compare(checks().length, 1, "Refresh retries the same admission path");
        }
        // A TUI run ends: the service reads its outcome, and starts the
        // run's check unless the run asked it.
        function endRun(endedAt) {
            service.shell = Object.assign({}, root.facade, { tui: { state: { "vgs.updates/update": { running: false, endedAt: endedAt } } } });
        }
        function test_a_run_that_checked_starts_no_second_check() {
            startup(); view.open("{}"); admission(4);
            compare(root.facade.ipc.call("check", "run"), "queued", "the run's own check joins the open's refresh");
            process("bin/check").finish(0, 0, snapshot(3), "");
            compare(root.values.checking, true);
            compare(root.values.pending, 97, "a refresh the run's check joined is replaced, never published");
            admission(4); process("bin/check").finish(0, 0, snapshot(2), "");
            compare(root.values.pending, 2);
            endRun(1);
            compare(service.checking, false, "the run's end starts no third check");
            compare(checks().length, 0);
            reader(service.outcomePath).finishRead(JSON.stringify({ ended: "failed", text: "Flatpak failed." }));
            compare(root.values.lastRun, { ended: "failed", text: "Flatpak failed." }, "the run's outcome is published");
            endRun(2);
            admission(4);
            compare(checks().length, 1, "a run that asked no check gets one at its end");
        }
        // expected-log: updates: refused: status=test-unavailable -- planted publication failure
        function test_refused_publication_never_clears_the_mask() {
            startup(); view.open("{}"); admission(4);
            root.refuseKey = "sources";
            process("bin/check").finish(0, 0, snapshot(3), "");
            compare(root.values.checking, true); compare(service.checking, true);
            compare(Logic.windowRows(root.values)[0].badge, "");
        }
    }
}
