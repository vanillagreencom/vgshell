import QtQuick
import QtTest
import Quickshell.Io
import qs.Core
import qs.Unit
import "../../shell/Core/MonitorLogic.js" as Monitors
import "../../shell/plugins/vgs.displays" as Displays

// inputs: shell/plugins/vgs.displays/Service.qml shell/plugins/vgs.displays/DisplaysLogic.js shell/plugins/vgs.displays/manifest.json shell/Core/MonitorLogic.js shell/Core/PluginLogic.js
// The production service and confirmed configuration judge, with Process
// completions supplied by the existing QML test boundary. No helper runs.
Item {
    id: root
    property var user: ({})
    property var steps: ({})
    property var trial: ({ phase: "idle", token: "", deadline: 0, failure: "" })
    property var published: ({})
    readonly property var manifest: {
        const request = new XMLHttpRequest();
        request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.displays/manifest.json"), false);
        request.send();
        return JSON.parse(request.responseText);
    }
    QtObject {
        id: facade
        readonly property var settings: PluginLogic.settingsFor(root.user, root.manifest)
        readonly property var system: ({ state: root.steps, revision: 0 })
        readonly property var monitors: ({
            outputs: [], trialState: root.trial,
            primaryOutputs: rules => Monitors.primaryOutputs([], rules)
        })
        readonly property var requirements: ({ missing: [], revision: 0 })
        readonly property var status: ({
            set: (key, value) => {
                const write = PluginLogic.statusWrite(root.manifest, root.published, key, value);
                if (!write.ok) return write.error;
                root.published = write.values;
                return "ok";
            },
            isOk: reply => reply === "ok"
        })
        readonly property var shortcut: ({ register: () => {} })
        readonly property var ipc: ({ handle: () => {} })
        readonly property var layers: ({ show: () => {} })
        readonly property var idle: ({ watch: () => () => {} })
        readonly property var configure: ({ set: (key, value) => {
            const refusal = PluginLogic.settingRefusal(root.manifest, key, value);
            if (refusal !== "") return refusal;
            root.user = PluginLogic.withSetting(root.user, root.manifest, key, value, {});
            return "ok";
        } })
    }
    Component { id: serviceComponent; Displays.Service { shell: facade } }

    TestCase {
        name: "displays_greeter_layout"
        when: windowShown

        function init() { root.user = {}; root.steps = {}; root.published = {}; }
        function copier() {
            const found = ProcessRegistry.processes.filter(process => process.command[0] === "/stand-in/shell/../bin/vgshell-greeter-layout");
            compare(found.length, 1, "one copier owner");
            return found[0];
        }
        function service() {
            const result = createTemporaryObject(serviceComponent, root);
            verify(result !== null);
            // End the unrelated startup brightness restore so destruction
            // owes no detached hardware work.
            const brightness = ProcessRegistry.processes.find(process => process.command[2] === "restore");
            verify(brightness !== undefined);
            brightness.finish(0, 0, '{"restored":[],"failed":[]}');
            return result;
        }
        function startCopy(process, instance) {
            tryCompare(process, "running", true);
            // The nested displays-modes row exercises real stdin and EOF.
            // This fixture reads the immutable payload owned by this run.
            return JSON.parse(instance.layoutActive);
        }
        function test_ready_saved_changes_and_coalescing() {
            const instance = service();
            const process = copier();
            compare(process.running, false, "no copy before the system step is ready");
            root.steps = { greeter: { state: "ready", reason: "" } };
            compare(startCopy(process, instance), { outputs: {}, primaryOutput: "" });
            compare(facade.configure.set("outputs", { "DP-2": { transform: 1, scale: 2, position: { x: 0, y: 0 } } }), "ok");
            compare(facade.configure.set("primaryOutput", "DP-1"), "ok");
            compare(facade.configure.set("primaryOutput", "DP-2"), "ok");
            compare(JSON.parse(instance.layoutPending).primaryOutput, "DP-2");
            process.finish(0, 0, "layout=copied\n");
            const saved = startCopy(process, instance);
            compare(saved.primaryOutput, "DP-2");
            compare(saved.outputs["DP-2"], { transform: 1, scale: 2, position: { x: 0, y: 0 } });
            process.finish(0, 0, "layout=unchanged\n");
            tryCompare(instance, "layoutActive", "");
            compare(process.running, false);
            compare(instance.layoutCopied, true);
        }
        function test_initial_ready_setup() {
            root.steps = { greeter: { state: "ready", reason: "" } };
            const instance = service();
            const process = copier();
            compare(startCopy(process, instance), { outputs: {}, primaryOutput: "" });
            process.finish(0, 0, "layout=unchanged\n");
            compare(instance.layoutCopied, true);
        }
        // expected-log: displays: greeter-layout start=failed -- a missing helper must not be reported as saved
        // expected-log: displays: greeter-layout exit=1 -- the helper's refusal is explicit
        function test_copy_failures_are_not_success() {
            const instance = service();
            const process = copier();
            root.steps = { greeter: { state: "ready", reason: "" } };
            tryCompare(process, "running", true);
            process.failStart();
            compare(instance.layoutCopied, false);
            compare(root.published.greeterLayout.tone, "danger");
            compare(facade.configure.set("primaryOutput", "DP-1"), "ok");
            startCopy(process, instance);
            process.finish(1, 0, "layout=copied\n", "greeter-layout: refused: io=EACCES");
            compare(instance.layoutCopied, false);
            compare(root.published.greeterLayout.tone, "danger");
        }
    }
}
