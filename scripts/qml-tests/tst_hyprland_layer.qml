import QtQuick
import QtTest
import Quickshell.Io
import qs.Commons
import qs.Core
import qs.Unit

// The Hyprland layer's writer against the stand-in FileView and Process,
// whose reads and commands the test finishes by hand: one theme change
// renders the layer once, and the bytes it writes are the render of the
// settled inputs; while a display trial runs it writes nothing, and the
// trial's end writes once, with an input moved in the same turn.
Item {
    id: root

    readonly property string configText: JSON.stringify({ version: 6 }, null, 2) + "\n"
    // A theme apply as a catalog theme makes it: one document that moves
    // several of the layer's inputs at once.
    readonly property var themeTokens: ({
        scheme: { mode: "light" },
        palette: { accent: "#b4637a", foreground: "#575279", background: "#faf4ed", warning: "#ea9d34" },
        font: { family: { mono: "Serif" } },
        radius: { md: 9 },
        bar: { height: 40 }
    })

    // Two more theme documents, each moving the layer's colours.
    readonly property var heldTokens: ({ palette: { accent: "#286983" } })
    readonly property var keptTokens: ({ palette: { accent: "#907aa9" } })
    readonly property var idleTrial: ({ phase: "idle", token: "", deadline: 0, failure: "" })

    HyprlandLayer { id: layer }
    // The `hyprland` capability's provider, which hands a plugin its
    // permission state; the stand-in Capabilities carries the layer's.
    HyprlandState { id: permissionReader }
    ShortcutRegistry { id: shortcuts }
    property var edges: []

    SignalSpy { id: renders; target: layer; signalName: "renderedChanged" }

    TestCase {
        name: "hyprland-layer"

        function watched(path) {
            for (let i = 0; i < Config.data.length; i++) {
                if (Config.data[i].path === path) return Config.data[i];
            }
            fail("no watched file path=" + path);
        }

        function finishConfigRead(path) {
            const file = watched(path);
            if (!file.busy) file.read();
            tryCompare(file.data[1], "live", "read");
            file.data[1].finishRead(root.configText);
        }

        function layerFile() {
            for (const child of layer.data) if (child.path === layer.path) return child;
            fail("no layer file view");
        }

        function running(command) {
            let found;
            tryVerify(() => (found = ProcessRegistry.processes.find(p => p.running && p.command.join(" ") === command)) !== undefined, 1000, command);
            return found;
        }

        // Finish the write cycle the last render started: mkdir, the
        // blocking write and the reload.
        function finishWrite() {
            running("mkdir -p -- " + layer.dir).finish(0, 0);
            tryVerify(() => layer.machine.phase === "reloading", 1000, "the write lands");
            running("hyprctl reload config-only").finish(0, 0, "ok");
        }

        // Return once the engine has been back to the event loop, so a
        // Qt.callLater the code under test queued before this call has run
        // (https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method). The
        // order is checked by a run: the mutation row "a failed key read is
        // read again on every release" goes red only behind this wait.
        function settleTurn(message) {
            let settled = false;
            Qt.callLater(() => settled = true);
            tryVerify(() => settled, 1000, message);
        }

        function initTestCase() {
            Registry.hyprlandSections = [{ id: "acme.initial", version: "1.0.0",
                binds: [{ shortcut: "talk", key: "SUPER+code:30" }],
                options: [], layerRules: [], appearance: {}, monitors: null, padRefusals: [], unknownKeys: [] }];
            finishConfigRead(Config.shippedPath);
            finishConfigRead(Config.userPath);
            compare(Config.ready, true);
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            tryVerify(() => layer.rendered !== null);
            compare(layer.rendered.plan.phase, "core");
            compare(Registry.hyprlandBindPlan.keys["acme.initial"].talk, null);
            Capabilities.hyprland.finishKeys({ ok: true, translation: [{ modifiers: ["SUPER"], keycode: 30 }] });
            tryVerify(() => layer.rendered !== null && layer.rendered.plan.phase === "admitted", 1000, "the first admitted render");
            layerFile().failRead(FileViewError.FileNotFound);
            finishWrite();
            running(layer.runner + " hypr state").finish(0, 0, "ok hypr=wired path=/stand-in");
            compare(layer.machine.phase, "idle");
            compare(layer.machine.failure, "");
            Registry.hyprlandSections = [];
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
        }

        function test_a_theme_change_renders_once() {
            const before = layer.rendered.text;
            renders.clear();
            compare(UnitTheme.override(root.themeTokens), "ok");
            tryVerify(() => layer.machine.phase !== "idle", 1000, "the theme change starts a write");
            compare(renders.count, 1);
            finishWrite();
            const written = layerFile().written;
            verify(written !== before, "the theme reaches the layer");
            compare(written, LayerLogic.render.apply(null, layer.renderInputs).text);
            compare(layer.machine.phase, "idle");
            compare(renders.count, 1);
        }

        function test_a_trial_holds_the_write_until_it_ends() {
            const before = layerFile().written;
            Capabilities.monitors.trialState = { phase: "holding", token: "t", deadline: 0, failure: "" };
            compare(layer.machine.trialHeld, true);
            renders.clear();
            compare(UnitTheme.override(root.heldTokens), "ok");
            tryVerify(() => renders.count === 1, 1000, "the theme change renders while the trial runs");
            compare(layer.machine.phase, "idle", "a render while the trial runs starts no write");
            compare(layerFile().written, before);
            // Keep: the trial ends and its outputs write moves an input in
            // the same turn; the one write carries that input.
            Capabilities.monitors.trialState = root.idleTrial;
            compare(UnitTheme.override(root.keptTokens), "ok");
            tryVerify(() => layer.machine.phase !== "idle", 1000, "the trial's end starts a write");
            finishWrite();
            compare(layerFile().written, LayerLogic.render.apply(null, layer.renderInputs).text);
            compare(layer.machine.phase, "idle");
            compare(layer.machine.trialHeld, false);
            compare(renders.count, 2);
        }

        function test_bind_publication_waits_for_one_global_resolution() {
            const before = layerFile().written;
            Registry.hyprlandSections = [{ id: "acme.mic", version: "1.0.0",
                binds: [{ shortcut: "mute", key: "SUPER+SHIFT+U" }, { shortcut: "mute", key: "SUPER+SHIFT+code:30" }],
                options: [], layerRules: [], appearance: {}, monitors: null, padRefusals: [], unknownKeys: [] }];
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            compare(Capabilities.publisherHolds, 1);
            compare(JSON.stringify(Registry.hyprlandBindPlan.keys), "{}", "pending keys do not replace the last admitted empty plan");
            compare(layerFile().written, before, "pending global facts write no guessed binds");
            Capabilities.hyprland.finishKeys({ ok: true, translation: [
                { modifiers: ["SUPER", "SHIFT"], keycode: 30 },
                { modifiers: ["SUPER", "SHIFT"], keycode: 30 }
            ] });
            tryVerify(() => layer.machine.phase === "preparing");
            compare(Registry.hyprlandBindPlan.keys["acme.mic"].mute, "SUPER+SHIFT+code:30");
            finishWrite();
            verify(!layerFile().written.includes('hl.bind("SUPER + SHIFT + U",'), "the symbolic duplicate is absent from every submap");
            compare(layerFile().written, LayerLogic.render.apply(null, layer.renderInputs).text);
            Registry.hyprlandSections = [];
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
        }

        function test_bind_change_without_a_merge_pair_writes_while_keys_resolve() {
            Registry.hyprlandSections = [{ id: "acme.mic", version: "1.0.0",
                binds: [{ shortcut: "talk", key: "SUPER+code:30" }],
                options: [], layerRules: [], appearance: {}, monitors: null, padRefusals: [], unknownKeys: [] }];
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            tryVerify(() => layer.machine.phase === "preparing", 1000, "a bind with no merge pair writes before its key facts");
            verify(Capabilities.hyprland.pendingKeys !== null, "the write did not wait for the reader");
            compare(Registry.hyprlandBindPlan.keys["acme.mic"].talk, "SUPER+code:30");
            finishWrite();
            verify(layerFile().written.includes('"acme.mic:talk"'), "the written layer binds the new action");
            Capabilities.hyprland.finishKeys({ ok: true, translation: [{ modifiers: ["SUPER"], keycode: 30 }] });
            tryVerify(() => layer.rendered.plan === layer.bindPlan);
            Registry.hyprlandSections = [];
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
        }

        function test_regrouped_merge_pair_reads_its_keys_again() {
            const section = binds => [{ id: "acme.mic", version: "1.0.0", binds: binds,
                options: [], layerRules: [], appearance: {}, monitors: null, padRefusals: [], unknownKeys: [] }];
            const facts = { ok: true, translation: [{ modifiers: ["SUPER"], keycode: 44 }, { modifiers: ["SUPER"], keycode: 44 }] };
            Registry.hyprlandSections = section([{ shortcut: "talk", key: "SUPER+J" }, { shortcut: "mute", key: "SUPER+code:44" }]);
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            Capabilities.hyprland.finishKeys(facts);
            tryVerify(() => layer.machine.phase === "preparing" && layer.rendered.plan === layer.bindPlan);
            finishWrite();
            const request = layer.bindRequest;
            Registry.hyprlandSections = section([{ shortcut: "talk", key: "SUPER+J" }, { shortcut: "talk", key: "SUPER+code:44" }]);
            compare(layer.bindRequest, request, "the regrouped section asks for the same keys");
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null, 1000, "a regrouped merge pair reads its keys again");
            Capabilities.hyprland.finishKeys(facts);
            tryVerify(() => layer.bindPlan !== null);
            compare(layer.bindPlan.keys["acme.mic"].talk, "SUPER+code:44");
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
            Registry.hyprlandSections = [];
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
        }

        // held: ShortcutLabels reads key names on the same devices change and
        // can take the shared resolver before the layer's retry runs.
        function test_failed_key_read_reads_again_on_a_devices_change_data() {
            return [{ tag: "resolver-free", held: false }, { tag: "resolver-held", held: true }];
        }

        // expected-log: hyprland: refused: keymap=timeout -- the failed read this case answers
        function test_failed_key_read_reads_again_on_a_devices_change(data) {
            const devicesBefore = Capabilities.hyprland.devices;
            Registry.hyprlandSections = [{ id: "acme.mic", version: "1.0.0", binds: [{ shortcut: "talk", key: "SUPER+code:30" }],
                options: [], layerRules: [], appearance: {}, monitors: null, padRefusals: [], unknownKeys: [] }];
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
            try {
                const failed = Capabilities.hyprland.pendingKeys.keys;
                Capabilities.hyprland.finishKeys({ ok: false, error: "refused: keymap=timeout" });
                compare(layer.bindSnapshot.read.kind, "failed");
                // The failed read's release queues resolveBindKeys for a
                // later turn, which must not read the same keys again.
                settleTurn("the turn after the failed read's release runs");
                compare(Capabilities.hyprland.pendingKeys, null, "a failed read waits for an existing event");
                if (data.held) Capabilities.hyprland.resolveKeys(["SUPER+code:44"], () => {});
                Capabilities.hyprland.devices = { mice: [], keyboards: [{ main: true, name: "fixture", layout: "us",
                    activeLayoutIndex: 0, activeKeymap: "English (US)" }] };
                if (data.held) {
                    settleTurn("the turn after the devices change runs");
                    compare(JSON.stringify(Capabilities.hyprland.pendingKeys.keys), '["SUPER+code:44"]',
                        "the other requester still holds the resolver");
                    Capabilities.hyprland.finishKeys({ ok: true, translation: [{ modifiers: ["SUPER"], keycode: 44 }] });
                }
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null, 1000, "a devices change reads the failed keys again");
                compare(JSON.stringify(Capabilities.hyprland.pendingKeys.keys), JSON.stringify(failed));
                Capabilities.hyprland.finishKeys({ ok: true, translation: [{ modifiers: ["SUPER"], keycode: 30 }] });
                tryVerify(() => layer.bindPlan !== null, 1000, "the read again admits the binds");
                compare(layer.bindPlan.keys["acme.mic"].talk, "SUPER+code:30");
            } finally {
                // A failed assertion leaves the next case no held resolver.
                if (Capabilities.hyprland.pendingKeys !== null)
                    Capabilities.hyprland.finishKeys({ ok: true, translation: [{ modifiers: ["SUPER"], keycode: 30 }] });
                Capabilities.hyprland.devices = devicesBefore;
                Registry.hyprlandSections = [];
                tryVerify(() => layer.machine.phase === "preparing");
                finishWrite();
            }
        }

        function test_a_layout_change_during_a_key_read_reads_the_keys_again_data() {
            return [{ tag: "first-read", retry: false }, { tag: "failed-read-retry", retry: true }];
        }

        // HyprlandState answers a read whose layout changed under it in this
        // order: the new devices, then the answer while the helper still
        // runs, then the helper's exit in a later turn (HyprlandState.qml's
        // devicesReader). The stand-in's finishKeys releases first, so the
        // case answers by hand.
        // expected-log: hyprland: refused: keymap=timeout -- the failed-read-retry row's first read fails before the retry it supersedes
        function test_a_layout_change_during_a_key_read_reads_the_keys_again(data) {
            const devicesBefore = Capabilities.hyprland.devices;
            const keyboard = (index, keymap) => ({ mice: [], keyboards: [{ main: true, name: "fixture", layout: "us,de",
                activeLayoutIndex: index, activeKeymap: keymap }] });
            Registry.hyprlandSections = [{ id: "acme.layout", version: "1.0.0", binds: [{ shortcut: "talk", key: "SUPER+code:30" }],
                options: [], layerRules: [], appearance: {}, monitors: null, padRefusals: [], unknownKeys: [] }];
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
            try {
                if (data.retry) {
                    Capabilities.hyprland.finishKeys({ ok: false, error: "refused: keymap=timeout" });
                    compare(layer.bindSnapshot.read.kind, "failed");
                    Capabilities.hyprland.devices = keyboard(0, "English (US)");
                    tryVerify(() => Capabilities.hyprland.pendingKeys !== null, 1000, "a devices change retries the failed read");
                }
                const asked = Capabilities.hyprland.pendingKeys;
                Capabilities.hyprland.devices = keyboard(1, "German");
                Capabilities.hyprland.pendingKeys = null;
                asked.done({ ok: false, error: "refused: keymap=layout-changed" });
                settleTurn("the turn after the answer runs");
                compare(Capabilities.hyprland.pendingKeys, null, "no read starts while the resolver is held");
                Capabilities.hyprland.resolvingKeys = false;
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null, 1000, "the superseded read is asked again");
                compare(JSON.stringify(Capabilities.hyprland.pendingKeys.keys), JSON.stringify(asked.keys));
                verify(layer.bindSnapshot === null || layer.bindSnapshot.read.kind !== "failed", "a superseded read records no failure");
                Capabilities.hyprland.finishKeys({ ok: true, translation: [{ modifiers: ["SUPER"], keycode: 30 }] });
                tryVerify(() => layer.bindPlan !== null, 1000, "the read again admits the binds");
            } finally {
                // A failed assertion leaves the next case no held resolver.
                if (Capabilities.hyprland.pendingKeys !== null)
                    Capabilities.hyprland.finishKeys({ ok: true, translation: [{ modifiers: ["SUPER"], keycode: 30 }] });
                Capabilities.hyprland.resolvingKeys = false;
                Capabilities.hyprland.devices = devicesBefore;
                Registry.hyprlandSections = [];
                tryVerify(() => layer.machine.phase === "preparing");
                finishWrite();
            }
        }

        function test_pending_keymap_retains_live_bind_readback_and_hold_data() {
            return [{ tag: "success", failed: false }, { tag: "operational-failure", failed: true }];
        }

        // expected-log: hyprland: refused: keymap=timeout -- the operational-failure row finishes the real callback with this refusal
        function test_pending_keymap_retains_live_bind_readback_and_hold(data) {
            Registry.hyprlandSections = [{ id: "acme.mic", version: "1.0.0",
                binds: [{ shortcut: "talk", key: "SUPER+code:30", hold: true }],
                options: [], layerRules: [], appearance: {}, monitors: null, padRefusals: [], unknownKeys: [] }];
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            const facts = { ok: true, translation: [{ modifiers: ["SUPER"], keycode: 30 }] };
            Capabilities.hyprland.finishKeys(facts);
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
            root.edges = [];
            const talk = shortcuts.registerHeldShortcut("acme.mic", "talk", "fixture",
                () => root.edges = root.edges.concat(["down"]),
                () => root.edges = root.edges.concat(["up"]));
            try {
                talk.pressed();
                compare(talk.stroke.kind, "held");
                const written = layerFile().written;
                Capabilities.hyprland.keymapRevision++;
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
                compare(layer.render(), "refused: hyprland=pending");
                const plan = Registry.hyprlandBindPlan;
                compare(JSON.stringify({ binds: Capabilities.hyprland.layerBinds,
                    key: plan === null ? null : plan.keys["acme.mic"].talk,
                    stroke: talk.stroke.kind, edges: root.edges }),
                    JSON.stringify({ binds: ["acme.mic:talk", "acme.mic:talk.release"],
                        key: "SUPER+code:30", stroke: "held", edges: ["down"] }),
                    "pending key facts preserve own-bind exclusions, effective key and unchanged hold");
                compare(layerFile().written, written);
                const admitted = layer.rendered;
                if (data.failed) {
                    Capabilities.hyprland.finishKeys({ ok: false, error: "refused: keymap=timeout" });
                    compare(layer.bindSnapshot.read.kind, "failed");
                    compare(layer.rendered, admitted, "failure retains the whole admitted object");
                    compare(layerFile().written, written);
                    compare(talk.stroke.kind, "held");
                    compare(Capabilities.hyprland.pendingKeys, null, "a failed request is not retried");
                    Capabilities.hyprland.keymapRevision++;
                    tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
                }
                Capabilities.hyprland.finishKeys(facts);
                tryVerify(() => layer.bindPlan !== null);
                compare(talk.stroke.kind, "held");
                talk.companion.released();
                compare(JSON.stringify(root.edges), '["down","up"]');
            } finally {
                shortcuts.releaseShortcut("acme.mic:talk", talk);
            }
            Registry.hyprlandSections = [];
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
        }

        // A plugin that declares permissions reads `pending-restart` through
        // the `hyprland` capability until Hyprland launches with its rules;
        // another plugin reads null.
        function test_permission_state_reaches_the_declaring_plugin() {
            Capabilities.hyprland.userPermissions = { ok: true, present: true, rules: [], options: [] };
            Registry.hyprlandSections = [{ id: "acme.remote", version: "1.0.0", binds: [], options: [], layerRules: [], appearance: {},
                monitors: null, padRefusals: [], unknownKeys: [], permissions: { deny: ["gliff-server"], enforce: true } }];
            tryVerify(() => layer.machine.phase === "preparing", 1000, "the declared block starts a write");
            verify(Capabilities.hyprland.permissionState !== null, "the layer hands the capability its permission state");
            permissionReader.permissionState = Capabilities.hyprland.permissionState;
            compare(permissionReader.provider({ id: "acme.remote", active: true, manifest: {} }).permissions, "pending-restart");
            compare(permissionReader.provider({ id: "acme.other", active: true, manifest: {} }).permissions, null);
            finishWrite();
            Registry.hyprlandSections = [];
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
            compare(Capabilities.hyprland.permissionState, null);
            permissionReader.permissionState = null;
            Capabilities.hyprland.userPermissions = null;
        }

        function test_foreign_inputs_publish_only_current_global_identities() {
            Capabilities.hyprland.foreignKeys = null;
            Capabilities.hyprland.userBindRows = null;
            Registry.hyprlandSections = [{ id: "acme.mic", version: "1.0.0",
                binds: [{ shortcut: "talk", key: "SUPER+code:44" }],
                options: [], layerRules: [], appearance: {}, monitors: null, padRefusals: [], unknownKeys: [] }];
            tryCompare(layer, "bindRequest", "");
            layer.resolveBindKeys();
            compare(Capabilities.hyprland.pendingKeys, null, "unread foreign inputs are not an empty known set");
            Capabilities.hyprland.foreignKeys = ["SUPER+J"];
            Capabilities.hyprland.userBindRows = [{ key: "SUPER+SHIFT+J" }];
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            compare(JSON.stringify(Capabilities.hyprland.pendingKeys.keys), '["SUPER+code:44","SUPER+J","SUPER+SHIFT+J"]',
                "one global request includes the plugin, foreign and user-row keys");
            const facts = { ok: true, translation: [
                { modifiers: ["SUPER"], keycode: 44 }, { modifiers: ["SUPER"], keycode: 44 },
                { modifiers: ["SUPER", "SHIFT"], keycode: 44 }
            ] };
            Capabilities.hyprland.finishKeys(facts);
            // A foreign key changes no merge pair, so the write may already
            // run from the last snapshot; wait for this reply's render.
            tryVerify(() => layer.machine.phase === "preparing" && layer.rendered.plan === layer.bindPlan);
            verify(Registry.hyprlandKeyIdentities !== null);
            compare(LayerLogic.sameKey("SUPER+code:44", "SUPER+J", Registry.hyprlandKeyIdentities), true);
            finishWrite();
            // A reload marks both readings pending while it reads them again;
            // their last answer asks no key read under the new revision.
            Capabilities.hyprland.bindsPending = true;
            Capabilities.hyprland.userBindsPending = true;
            Capabilities.hyprland.keymapRevision++;
            wait(0); // resolveBindKeys runs through Qt.callLater.
            compare(Capabilities.hyprland.pendingKeys, null, "readings a re-read replaces are not current");
            Capabilities.hyprland.bindsPending = false;
            Capabilities.hyprland.userBindsPending = false;
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            compare(Registry.hyprlandKeyIdentities, null, "pending layout facts cannot claim a current foreign identity");
            verify(Registry.hyprlandBindPlan !== null, "the live admitted bind plan remains available");
            Capabilities.hyprland.finishKeys(facts);
            tryVerify(() => Registry.hyprlandKeyIdentities !== null);
            Capabilities.hyprland.foreignKeys = [];
            Capabilities.hyprland.userBindRows = [];
            Registry.hyprlandSections = [];
            tryVerify(() => layer.machine.phase === "preparing");
            finishWrite();
        }

        // expected-log: hyprland: refused: keymap=timeout -- the replacement fails operationally before the existing reload event retries it
        function test_new_default_waits_for_missing_foreign_comparison() {
            const section = (id, binds, chosenKeys) => ({ id: id, version: "1.0.0", binds: binds,
                chosenKeys: chosenKeys, options: [], layerRules: [], appearance: {}, monitors: null,
                padRefusals: [], unknownKeys: [] });
            const prior = section("acme.prior", [{ shortcut: "talk", key: "SUPER+P" }], []);
            const capture = section("vgs.capture", [{ shortcut: "screenshot-area", key: "SUPER+SHIFT+S" }], []);
            // Enabling adds a section; resetting null adds a key to a section.
            for (const reset of [false, true]) {
                Capabilities.hyprland.foreignKeys = ["SUPER+SHIFT+code:39"];
                Capabilities.hyprland.userBindRows = [];
                Registry.hyprlandSections = reset
                    ? [prior, section("vgs.capture", [{ shortcut: "screenshot-area", key: null }], ["screenshot-area"])]
                    : [prior];
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
                compare(JSON.stringify(Capabilities.hyprland.pendingKeys.keys), '["SUPER+P","SUPER+SHIFT+code:39"]');
                Capabilities.hyprland.finishKeys({ ok: true, translation: [
                    { modifiers: ["SUPER"], keycode: 33 },
                    { modifiers: ["SUPER", "SHIFT"], keycode: 39 }
                ] });
                tryVerify(() => layer.machine.phase === "preparing" && layer.rendered.plan === layer.bindPlan);
                finishWrite();
                const admitted = layer.rendered;
                const written = layerFile().written;
                compare(admitted.plan.keys["acme.prior"].talk, "SUPER+P");
                verify(admitted.plan.identities["SUPER+SHIFT+S"] === undefined);

                Registry.hyprlandSections = [prior, capture];
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
                compare(JSON.stringify(Capabilities.hyprland.pendingKeys.keys),
                    '["SUPER+P","SUPER+SHIFT+S","SUPER+SHIFT+code:39"]');
                compare(layer.bindPlan, null, "an unread default comparison grants no admission");
                layer.renderLayer();
                compare(layer.rendered, admitted, "pending replacement retains the prior valid plan");
                compare(layer.machine.phase, "idle");
                compare(layerFile().written, written);
                compare(Registry.hyprlandBindPlan.keys["acme.prior"].talk, "SUPER+P");

                Capabilities.hyprland.finishKeys({ ok: false, error: "refused: keymap=timeout" });
                compare(layer.bindSnapshot.read.kind, "failed");
                layer.renderLayer();
                compare(layer.rendered, admitted, "failed replacement retains the prior valid plan");
                compare(layer.machine.phase, "idle");
                compare(layerFile().written, written);
                compare(Capabilities.hyprland.pendingKeys, null);
                compare(Registry.hyprlandBindPlan.keys["acme.prior"].talk, "SUPER+P");

                Capabilities.hyprland.keymapRevision++;
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
                Capabilities.hyprland.finishKeys({ ok: true, translation: [
                    { modifiers: ["SUPER"], keycode: 33 },
                    { modifiers: ["SUPER", "SHIFT"], keycode: 39 },
                    { modifiers: ["SUPER", "SHIFT"], keycode: 39 }
                ] });
                tryVerify(() => layer.machine.phase === "preparing" && layer.rendered.plan === layer.bindPlan);
                compare(Registry.hyprlandBindPlan.keys["vgs.capture"]["screenshot-area"], null);
                compare(Registry.hyprlandBindPlan.sections.find(row => row.section.id === "vgs.capture").binds[0].kind, "taken");
                compare(Registry.hyprlandBindPlan.keys["acme.prior"].talk, "SUPER+P");
                finishWrite();
                verify(!layerFile().written.includes('hl.bind("SUPER + SHIFT + S",'));
                Registry.hyprlandSections = [];
                Capabilities.hyprland.foreignKeys = [];
                tryVerify(() => layer.machine.phase === "preparing");
                finishWrite();
            }
        }
    }
}
