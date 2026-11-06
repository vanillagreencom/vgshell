import QtQuick
import QtTest
import "../../shell/plugins/vgs.agent-debug"

Item {
    id: root
    property var sent: []
    property var shown: []
    property var handed: []
    property var handlers: ({})
    Service { id: service }
    TestCase {
        name: "agentDebugHandoff"
        function init() {
            root.sent = []; root.shown = []; root.handed = []; root.handlers = {};
            service.registeredWith = null;
            service.recoveryArgs = null;
            service.shell = {
                manifest: { id: "acme.debug" },
                settings: { agent: "handoff:acme.receiver/compose", muted: [] },
                requirements: { missing: ["journalctl"] },
                handoff: { targets: [{ key: "handoff:acme.receiver/compose", label: "Fixture receiver", available: true, reason: "",
                    open: text => { root.handed.push(text); return { ok: true, reason: "" }; } }] },
                doctor: { installFailures: {} },
                ipc: { handle: (name, fn) => { root.handlers[name] = fn; } },
                status: { set: (key, value) => "ok", isOk: reply => reply === "ok" },
                surfaces: { summon: (kind, payload) => { root.shown.push({ kind: kind, payload: JSON.parse(payload) }); return "ok"; } },
                tui: { run: (name, args, done) => { root.sent.push({ name: name, args: args }); return "ok"; } }
            };
        }
        function cleanup() { service.shell = null; }
        function facts() {
            return { kind: "crash", entry: { program: "literal $(text)", pid: "4242", signal: "SIGSEGV", binary: "/usr/bin/example",
                time: 1793742000123 }, read: 1793742000123 };
        }
        function test_ready_route_hands_only_unsent_text() {
            service.diagnose(facts());
            compare(root.handed.length, 1);
            verify(root.handed[0].indexOf("- Program: literal $(text)\n") !== -1);
            verify(root.handed[0].indexOf("- Binary: /usr/bin/example\n") !== -1);
            compare(root.sent.length, 0);
            compare(root.shown.length, 0);
            compare(service.recoveryArgs, null);
        }
        function test_unavailable_keeps_selection_and_requires_explicit_one_off_terminal() {
            const original = service.shell;
            const unavailable = Object.assign({}, original.handoff.targets[0], { available: false, reason: "Fixture receiver is muted." });
            service.shell = Object.assign({}, original, { handoff: { targets: [unavailable] } });
            service.diagnose(facts());
            compare(root.handed.length, 0);
            compare(root.sent.length, 0, "Diagnose never silently chooses a terminal");
            compare(root.shown.length, 1);
            compare(root.shown[0].kind, "window");
            compare(service.agent, "handoff:acme.receiver/compose");
            const recovery = JSON.parse(root.handlers.recovery(""));
            verify(recovery.waiting);
            compare(recovery.reason, unavailable.reason);
            compare(root.handlers.recover("codex"), "ok");
            compare(root.sent.length, 1);
            compare(root.sent[0].name, "diagnose");
            compare(JSON.stringify(root.sent[0].args.slice(0, 5)), JSON.stringify(["codex", "crash", "literal $(text)", "4242", "SIGSEGV"]));
            compare(service.agent, "handoff:acme.receiver/compose", "the one-off terminal does not replace the saved choice");
            compare(service.recoveryArgs, null);
        }
        function test_occupied_console_refusal_enters_the_same_recovery_route() {
            const original = service.shell;
            const occupied = Object.assign({}, original.handoff.targets[0], {
                open: text => ({ ok: false, reason: "The receiver already holds your draft." })
            });
            service.shell = Object.assign({}, original, { handoff: { targets: [occupied] } });
            service.diagnose(facts());
            compare(root.sent.length, 0);
            compare(root.shown.length, 1);
            verify(JSON.parse(root.handlers.recovery("")).waiting);
            compare(root.handlers.recover("cancel"), "ok");
            verify(!JSON.parse(root.handlers.recovery("")).waiting);
            compare(service.recoveryArgs, null);
        }
    }
}
