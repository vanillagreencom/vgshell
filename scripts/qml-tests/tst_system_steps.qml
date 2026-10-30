import QtQuick
import QtTest
import qs.Core
import Quickshell.Io
import "../../shell/Core/Lifetime.js" as Lifetime
import "../../shell/Core/PluginLogic.js" as Logic

// Drives the production probe owner; its refresh acknowledgement is
// independent of value changes and belongs to the requesting scope.
// inputs: shell/Core/SystemSteps.qml shell/Core/PluginLogic.js shell/Core/Lifetime.js scripts/qml-tests/stand-ins/Process.qml scripts/qml-tests/stand-ins/ShortcutRegistryInputs.qml
Item {
    id: root
    Component { id: owner; SystemSteps {} }
    TestCase {
        name: "system_steps"
        property var steps: null
        property var scope: null
        property var provider: null
        property int completions: 0
        function prober() { return ProcessRegistry.runningWithVerb("status")[0]; }
        function report() {
            const values = {};
            for (const name of Logic.SYSTEM_STEPS) values[name] = { state: "ready", reason: "granted" };
            return JSON.stringify({ steps: values });
        }
        function init() {
            ProcessRegistry.clear(); completions = 0;
            steps = createTemporaryObject(owner, root);
            scope = Lifetime.create(error => { throw error; });
            provider = steps.provider({ manifest: { systemSteps: ["apple-displays"] }, onDispose: scope.register, get active() { return scope.active; } });
        }
        function cleanup() { scope.drain(); steps.destroy(); wait(0); }
        function test_in_flight_request_waits_for_following_unchanged_probe() {
            compare(provider.refresh(() => completions++), "ok");
            compare(provider.refresh(() => completions++), "ok");
            compare(ProcessRegistry.runningWithVerb("status").length, 1);
            prober().finish(0, 0, report(), "");
            compare(completions, 1); compare(steps.revision, 1);
            prober().finish(0, 0, report(), "");
            compare(completions, 2); compare(steps.revision, 1);
            compare(scope.count, 0);
        }
        function test_disposal_releases_pending_completion() {
            provider.refresh(() => completions++);
            scope.drain();
            compare(steps.pending.length, 0);
            prober().finish(0, 0, report(), "");
            compare(completions, 0);
        }
        // expected-log: system: probe=unstarted -- Failed launch replaces an old Ready reading.
        function test_failed_start_acknowledges_unknown() {
            provider.refresh(); prober().finish(0, 0, report(), "");
            provider.refresh(() => completions++); prober().failStart();
            compare(provider.state["apple-displays"].state, "unknown");
            compare(completions, 1);
        }
        // expected-log: system: probe=malformed reason=json -- A malformed report completes as unknown.
        function test_malformed_report_acknowledges_unknown() {
            provider.refresh(() => completions++); prober().finish(0, 0, "{", "");
            compare(provider.state["apple-displays"].state, "unknown");
            compare(completions, 1);
        }
        // expected-log: system: probe=timeout -- Expiry cannot retain Ready or leave completion pending.
        function test_deadline_acknowledges_unknown() {
            provider.refresh(() => completions++);
            const deadline = steps.data.find(item => item.interval === 10000);
            verify(deadline !== undefined);
            deadline.triggered();
            compare(provider.state["apple-displays"].reason, "probe-timeout");
            compare(completions, 1);
        }
    }
}
