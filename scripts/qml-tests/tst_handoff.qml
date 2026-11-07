import QtQuick
import QtTest
import qs.Core as Core
import "../smoke/fixtures/plugins/acme.handoff" as Receiver
import "../smoke/fixtures/plugins/acme.handoff-sender" as Sender
import "../../shell/plugins/vgs.agent-debug/Debug.js" as Debug

Item {
    id: root
    property var receiverContext: null
    property var senderContext: null
    property var cleanups: []
    function context(id, manifest) {
        const ctx = { id: id, manifest: manifest, active: true };
        ctx.onDispose = fn => {
            let live = true;
            const dispose = () => { if (live) { live = false; fn(); } };
            root.cleanups.push(dispose);
            return dispose;
        };
        return ctx;
    }
    Core.HandoffRegistry { id: registry }
    Receiver.Window { id: window }
    Receiver.Service { id: receiver }
    Sender.Service { id: sender }
    TestCase {
        name: "textHandoff"
        function init() {
            root.cleanups = [];
            window.draft = "";
            receiver.received = 0;
            receiver.ready = true;
            const manifest = { __revision: "one", handoffs: { compose: { label: "Fixture text receiver" } } };
            registry.manifests = { receiver: manifest };
            registry.enabledIds = ["receiver"];
            root.receiverContext = root.context("receiver", manifest);
            root.senderContext = root.context("sender", { handoffs: {} });
            receiver.shell = {
                handoff: registry.provider(root.receiverContext),
                surfaces: { summon: (kind, payload) => {
                    try { window.open(payload); return "ok"; } catch (error) { return "refused"; }
                } }
            };
            sender.shell = { handoff: registry.provider(root.senderContext) };
        }
        function cleanup() {
            root.receiverContext.active = false;
            root.senderContext.active = false;
            for (const dispose of root.cleanups) dispose();
            receiver.shell = null;
            sender.shell = null;
        }
        function test_discovery_draft_withdrawal_and_disposal() {
            compare(sender.targets.length, 1);
            verify(sender.targets[0].available);
            const offered = sender.targets[0];
            verify(sender.hand("facts as text; $(not-a-command)\nsecond line").ok);
            compare(window.draft, "facts as text; $(not-a-command)\nsecond line");
            verify(!sender.hand("do not replace").ok);
            compare(window.draft, "facts as text; $(not-a-command)\nsecond line");
            compare(receiver.received, 1);
            receiver.ready = false;
            window.draft = "";
            verify(!sender.targets[0].available);
            verify(!offered.open("stale").ok);
            verify(!sender.targets[0].open("unavailable").ok);
            receiver.ready = true;
            verify(sender.targets[0].available);
            verify(!offered.open("still stale").ok);
            root.receiverContext.active = false;
            for (const dispose of root.cleanups) dispose();
            verify(!registry.targets()[0].available);
            compare(receiver.received, 1);
        }
        function test_disabled_and_revised_owner_cannot_receive() {
            const offered = sender.targets[0];
            registry.enabledIds = [];
            verify(!sender.targets[0].available);
            verify(!offered.open("disabled").ok);
            registry.enabledIds = ["receiver"];
            registry.manifests = { receiver: { __revision: "two", handoffs: { compose: { label: "Rebuilt" } } } };
            verify(!sender.targets[0].available);
            verify(!offered.open("old source").ok);
            compare(receiver.received, 0);
        }
        // A receiver its manifest marks `kind: "action"` opens a task, so
        // Agent Debug's agent choices hold only the message target.
        function test_action_receiver_is_no_agent() {
            registry.manifests = { receiver: { __revision: "one", handoffs: {
                compose: { label: "Fixture text receiver" }, task: { label: "Fixture action", kind: "action" } } } };
            const targets = registry.targets();
            compare(JSON.stringify(targets.map(t => [t.key, t.kind])), JSON.stringify([["handoff:receiver/compose", ""], ["handoff:receiver/task", "action"]]));
            compare(JSON.stringify(Debug.choices(["claude", "codex", "copilot", "pi", "opencode"], targets, "").map(row => row.value)),
                JSON.stringify(["handoff:receiver/compose"]));
        }
        // expected-log: handoff: receiver-failed key=handoff:receiver/compose -- A failed receiver returns an explicit recovery result without logging message bytes.
        function test_receiver_exception_returns_a_failure() {
            receiver.release();
            registry.offer(root.receiverContext, "compose", text => { throw new Error("private message bytes"); });
            const result = registry.targets()[0].open("text");
            verify(!result.ok);
            compare(receiver.received, 0);
            compare(window.draft, "");
        }
    }
}
