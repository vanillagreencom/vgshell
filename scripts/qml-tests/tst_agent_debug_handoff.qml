import QtQuick
import QtTest
import "../../shell/plugins/vgs.agent-debug"

Item {
    id: root
    property var sent: []
    property var shown: []
    property var handed: []
    property var handlers: ({})
    // The receivers the service offered, by name.
    property var offered: ({})
    Service { id: service }
    Component { id: windowComponent; Recovery { width: 600; height: 600 } }
    TestCase {
        name: "agentDebugHandoff"
        function init() {
            root.sent = []; root.shown = []; root.handed = []; root.handlers = {}; root.offered = {};
            service.registeredWith = null;
            service.recoveryArgs = null;
            service.draft = null;
            service.shell = {
                manifest: { id: "acme.debug" },
                settings: { agent: "handoff:acme.receiver/compose", muted: [] },
                requirements: { missing: ["journalctl"] },
                handoff: { offer: (name, accept, reason) => { root.offered[name] = accept; return () => {}; }, targets: [{ key: "handoff:acme.receiver/compose", label: "Fixture receiver", available: true, reason: "",
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
        // Another plugin's failed sync job, handed as text, waits as a draft
        // in the window and reaches the Diagnose route only on Run; text of
        // another shape opens nothing.
        function test_sync_failure_handed_as_text_opens_diagnose() {
            const receive = root.offered.diagnose;
            verify(typeof receive === "function", "the service offers its Diagnose receiver");
            const facts = { kind: "sync", unit: "notes.service", name: "Notes", engine: "rsync", from: "/home/u/notes/", to: "/mnt/a/",
                error: "rsync error: error in file IO (code 11)", at: 1793742000123 };
            compare(receive(JSON.stringify(Object.assign({}, facts, { kind: "other" }))).ok, false, "text that is not a sync failure is refused");
            compare(root.shown.length, 0);
            compare(receive(JSON.stringify(facts)).ok, true);
            compare(JSON.stringify(root.shown), JSON.stringify([{ kind: "window", payload: { draft: true } }]), "the draft opens in the window");
            compare(root.handed.length + root.sent.length, 0, "a handed failure starts nothing before Run");
            compare(receive(JSON.stringify(facts)).ok, false, "a waiting draft is kept");
            compare(JSON.parse(root.handlers.draft("")).facts.unit, "notes.service");
            compare(root.handlers["draft-run"](""), "ok");
            compare(root.handed.length, 1);
            verify(root.handed[0].indexOf("- System job: notes.service") !== -1);
            verify(root.handed[0].indexOf("- Last error line: rsync error: error in file IO (code 11)\n") !== -1);
            compare(root.handlers["draft-run"](""), "refused: draft=none", "Run runs the draft once");
        }
        // The window over the real service: a summon opens it or hands it
        // the new payload, as the summon host does, and a hide closes it.
        function wired(open) {
            const original = service.shell;
            const refusing = Object.assign({}, original.handoff.targets[0], { open: text => ({ ok: false, reason: "The receiver already holds your draft." }) });
            let window = null;
            const windowShell = {
                ipc: { call: (name, arg) => String(root.handlers[name](arg)) },
                requirements: { missing: [] },
                surfaces: null
            };
            service.shell = Object.assign({}, original, {
                handoff: { offer: original.handoff.offer, targets: [open ? original.handoff.targets[0] : refusing] },
                surfaces: {
                    summon: (kind, payload) => {
                        root.shown.push({ kind: kind, payload: JSON.parse(payload) });
                        if (window === null) window = createTemporaryObject(windowComponent, root, { shell: windowShell });
                        window.open(payload);
                        return "ok";
                    },
                    hide: kind => { window.close(); window.destroy(); window = null; return "ok"; }
                }
            });
            windowShell.surfaces = service.shell.surfaces;
            return () => window;
        }
        function syncFacts() {
            return JSON.stringify({ kind: "sync", unit: "notes.service", name: "Notes", engine: "rsync", from: "/home/u/notes/", to: "/mnt/a/",
                error: "rsync error: error in file IO (code 11)", at: 1793742000123 });
        }
        // Run with a saved message target that refuses turns the draft
        // window to the one-off choice, which stays shown and holds the
        // diagnosis.
        function test_run_refused_by_the_target_keeps_the_recovery_choice() {
            const window = wired(false);
            compare(root.offered.diagnose(syncFacts()).ok, true);
            compare(window().mode, "draft");
            window().initialFocus.clicked();
            verify(window() !== null, "the window stays shown");
            compare([window().mode, window().reason], ["choice", "The receiver already holds your draft."]);
            verify(JSON.parse(root.handlers.recovery("")).waiting, "the recovery choice holds the diagnosis");
            compare(service.draft, null);
        }
        // Run that opens the agent closes the window; a draft the window
        // leaves for the recovery choice goes, so a later failure is taken.
        function test_window_turns_and_closes_by_the_service() {
            const window = wired(true);
            compare(root.offered.diagnose(syncFacts()).ok, true);
            window().initialFocus.clicked();
            compare(window(), null, "Run that opened the agent closes the window");
            compare(root.handed.length, 1);
            compare(root.offered.diagnose(syncFacts()).ok, true);
            service.shell.surfaces.summon("window", "{}");
            compare(window().mode, "choice");
            compare(service.draft, null, "the draft the window left goes");
            compare(root.offered.diagnose(syncFacts()).ok, true, "a later failure is taken");
            compare(window().mode, "draft");
            verify(!JSON.parse(root.handlers.recovery("")).waiting, "the choice the window left goes");
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
