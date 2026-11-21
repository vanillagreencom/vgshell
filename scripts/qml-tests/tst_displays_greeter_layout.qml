import QtQuick
import QtTest
import Quickshell.Io
import qs.Core
import qs.Unit
import "../../shell/Core/MonitorLogic.js" as Monitors
import "../../shell/plugins/vgs.displays" as Displays

// inputs: shell/plugins/vgs.displays/Service.qml shell/plugins/vgs.displays/DisplaysLogic.js shell/plugins/vgs.displays/manifest.json shell/Core/MonitorLogic.js shell/Core/MonitorState.qml shell/Core/HyprctlReader.qml shell/Core/PluginLogic.js
// The production service and confirmed configuration judge, and the
// production monitors capability where a row lends it, with Process
// completions supplied by the existing QML test boundary. No helper runs.
Item {
    id: root
    property var user: ({})
    property var steps: ({})
    property var trial: ({ phase: "idle", token: "", deadline: 0, failure: "" })
    // What Hyprland lists, null while MonitorState has no settled reading.
    property var outputs: []
    // A MonitorState's capability a row lends the service, else the stand-in.
    property var lent: null
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
        readonly property var monitors: root.lent !== null ? root.lent : ({
            outputs: root.outputs, trialState: root.trial,
            primaryOutputs: rules => Monitors.primaryOutputs(root.outputs || [], rules),
            layoutRules: saved => root.outputs === null ? null : Monitors.layoutRules(root.outputs, saved)
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
    Component { id: stateComponent; MonitorState { ownerId: "vgs.displays" } }

    TestCase {
        name: "displays_greeter_layout"
        when: windowShown

        function init() { root.user = {}; root.steps = {}; root.published = {}; root.outputs = []; root.lent = null; }
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
        // Home with nothing saved, as `hyprctl -j monitors all` prints it:
        // the Studio Display on DP-2 at STUDIO_TRANSFORM, then the Pro
        // Display XDR on DP-1.
        function homeReply(studioTransform) {
            const base = { description: "", make: "Apple Computer Inc", refreshRate: 60, vrr: false, disabled: false, currentFormat: "XRGB8888",
                mirrorOf: "none", colorManagementPreset: "srgb", sdrBrightness: 1, sdrSaturation: 1 };
            return JSON.stringify([
                Object.assign({ id: 0, name: "DP-2", model: "StudioDisplay", serial: "0x00001234", width: 5120, height: 2880, x: 0, y: 0, scale: 2,
                    transform: studioTransform, availableModes: ["5120x2880@60.00Hz"] }, base),
                Object.assign({ id: 1, name: "DP-1", model: "ProDisplayXDR", serial: "0x00005678", width: 6016, height: 3384, x: 1440, y: 620, scale: 2, transform: 0,
                    availableModes: ["6016x3384@60.00Hz"] }, base)
            ]);
        }
        function homeOutputs() {
            const read = Monitors.parseOutputs(homeReply(1));
            verify(read.ok);
            return read.outputs;
        }
        // An active MonitorState, its outputs read and trial directory
        // listing in flight, as a shell starts or reloads.
        function activeState() {
            const state = createTemporaryObject(stateComponent, root);
            verify(state !== null);
            state.active = true;
            const lister = ProcessRegistry.processes.find(process => process.command[3] === "vgs-display-guards");
            const reader = ProcessRegistry.processes.find(process => process.command[0] === "hyprctl" && process.command[2] === "monitors");
            verify(lister !== undefined && reader !== undefined);
            compare([lister.running, reader.running], [true, true]);
            return { state: state, monitors: state.provider({ id: "vgs.displays", onDispose: () => {} }), lister: lister, reader: reader };
        }
        function test_guard_token_at_activation_holds_the_copy() {
            const started = activeState();
            started.reader.finish(0, 0, homeReply(0));
            // An earlier shell's trial, its guard waking in ten seconds.
            started.lister.finish(0, 0, (Math.floor(Date.now() / 1000) - Monitors.TRIAL_SECONDS + 10) + "-3.token\n");
            compare(started.monitors.layoutRules({}), null, "a pending guard holds the copy");
            compare(started.monitors.trial({ "DP-2": { transform: 1 } }, {}), "refused: monitors-trial=settling");
        }
        function test_read_after_the_guard_is_the_copy() {
            const studio = "desc:Apple Computer Inc StudioDisplay 0x00001234";
            const xdr = "desc:Apple Computer Inc ProDisplayXDR 0x00005678";
            const started = activeState();
            root.lent = started.monitors;
            root.steps = { greeter: { state: "ready", reason: "" } };
            const instance = service();
            const process = copier();
            // The trial still shows, and its guard's claim stands.
            started.reader.finish(0, 0, homeReply(0));
            const made = Math.floor(Date.now() / 1000) - Monitors.TRIAL_SECONDS;
            started.lister.finish(0, 0, made + "-7.token.revert\n" + made + "-7.token.log\n");
            compare(started.monitors.layoutRules({}), null);
            compare([process.running, instance.layoutPending], [false, ""], "no copy while the guard restores");
            // The guard ends. The read after it is the copy, though it shows
            // neither the trial nor its restore.
            tryCompare(started.lister, "running", true, 5000);
            started.lister.finish(0, 0, made + "-7.token.log\n");
            tryCompare(started.reader, "running", true);
            started.reader.finish(0, 0, homeReply(3));
            compare(startCopy(process, instance), { outputs: {
                [studio]: { mode: { width: 5120, height: 2880, refresh: 60 }, position: { x: 0, y: 0 }, scale: 2, transform: 3 },
                [xdr]: { mode: { width: 6016, height: 3384, refresh: 60 }, position: { x: 1440, y: 620 }, scale: 2, transform: 0 }
            }, primaryOutput: "" });
            process.finish(0, 0, "layout=copied\n");
        }
        function test_running_layout_and_saved_rules() {
            const studio = "desc:Apple Computer Inc StudioDisplay 0x00001234";
            const xdr = "desc:Apple Computer Inc ProDisplayXDR 0x00005678";
            const studioRule = { mode: { width: 5120, height: 2880, refresh: 60 }, position: { x: 0, y: 0 }, scale: 2, transform: 1 };
            const xdrRule = { mode: { width: 6016, height: 3384, refresh: 60 }, position: { x: 1440, y: 620 }, scale: 2, transform: 0 };
            root.outputs = homeOutputs();
            root.steps = { greeter: { state: "ready", reason: "" } };
            const instance = service();
            const process = copier();
            compare(startCopy(process, instance), { outputs: { [studio]: studioRule, [xdr]: xdrRule }, primaryOutput: "" }, "nothing saved copies the running layout");
            process.finish(0, 0, "layout=copied\n");
            compare(facade.configure.set("outputs", { "DP-2": { transform: 3 } }), "ok");
            compare(startCopy(process, instance), { outputs: { "DP-2": { transform: 3 }, [xdr]: xdrRule }, primaryOutput: "" }, "a saved rule wins");
            process.finish(0, 0, "layout=copied\n");
            tryCompare(instance, "layoutActive", "");
            // No settled reading, during or after a trial: no copy, and the
            // last one stands.
            root.outputs = null;
            compare(facade.configure.set("primaryOutput", "DP-1"), "ok");
            compare(instance.layoutPending, "");
            compare(process.running, false);
            root.outputs = homeOutputs();
            compare(startCopy(process, instance), { outputs: { "DP-2": { transform: 3 }, [xdr]: xdrRule }, primaryOutput: "DP-1" });
            process.finish(0, 0, "layout=copied\n");
            compare(instance.layoutCopied, true);
        }
        // A trial that runs to its deadline with the greeter ready: from its
        // arming, no copy starts until the read after its guard.
        function test_trial_deadline_copies_nothing_until_the_settled_read() {
            const studio = "desc:Apple Computer Inc StudioDisplay 0x00001234";
            const xdr = "desc:Apple Computer Inc ProDisplayXDR 0x00005678";
            const started = activeState();
            root.lent = started.monitors;
            root.steps = { greeter: { state: "ready", reason: "" } };
            const instance = service();
            const process = copier();
            started.reader.finish(0, 0, homeReply(1));
            started.lister.finish(0, 0, "");
            tryCompare(started.reader, "running", true);
            started.reader.finish(0, 0, homeReply(1));
            startCopy(process, instance);
            process.finish(0, 0, "layout=copied\n");
            tryCompare(instance, "layoutActive", "");

            compare(started.monitors.trial({ "DP-2": { transform: 3 } }, {}), "ok");
            const arming = ProcessRegistry.processes.find(process => process.command[3] === "vgs-display-token");
            verify(arming !== undefined);
            arming.finish(0, 0);
            const token = started.monitors.trialState.token;
            compare(started.monitors.trialState.phase, "holding");
            Compositor.evals[Compositor.evals.length - 1].done("ok");
            tryCompare(started.reader, "running", true);
            started.reader.finish(0, 0, homeReply(3));
            // The deadline, as its Timer signals it when the interval ends.
            const deadline = Array.prototype.find.call(started.state.data, child => child.running === true && typeof child.restart === "function" && child.interval >= 1000);
            verify(deadline !== undefined);
            deadline.stop();
            deadline.triggered();
            compare(started.monitors.trialState.phase, "idle");
            compare([process.running, instance.layoutPending], [false, ""], "the ended trial opens no copy");
            // The guard holds its claim while it restores; the read beside it
            // still shows the trial.
            started.lister.finish(0, 0, token.split("/").pop() + ".revert\n");
            started.reader.finish(0, 0, homeReply(3));
            compare([process.running, instance.layoutPending], [false, ""], "no copy while the guard restores");
            tryCompare(started.lister, "running", true, 5000);
            started.lister.finish(0, 0, "");
            tryCompare(started.reader, "running", true);
            started.reader.finish(0, 0, homeReply(1));
            compare(startCopy(process, instance), { outputs: {
                [studio]: { mode: { width: 5120, height: 2880, refresh: 60 }, position: { x: 0, y: 0 }, scale: 2, transform: 1 },
                [xdr]: { mode: { width: 6016, height: 3384, refresh: 60 }, position: { x: 1440, y: 620 }, scale: 2, transform: 0 }
            }, primaryOutput: "" });
            process.finish(0, 0, "layout=copied\n");
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
