import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Unit

// The real publisher writes core bytes and asks consent while its actual
// resolver callback is withheld or fails. Every row owns a fresh publisher.
Item {
    id: root
    property var scene: null
    readonly property string configText: JSON.stringify({ version: 5,
        welcome: { keys: [{ id: "acme.core", shortcut: "talk", text: "Talk" }] } })

    Component {
        id: fixture
        Item {
            property alias loader: loader
            readonly property var publisher: loader.item
            LazyLoader { id: loader; active: true; HyprlandLayer {} }
            ShortcutRegistry {}
        }
    }

    TestCase {
        name: "hyprland-consent"

        function initTestCase() {
            for (const path of [Config.shippedPath, Config.userPath]) {
                let file;
                for (const child of Config.data) if (child.path === path) { file = child; break; }
                verify(file !== undefined);
                if (!file.busy) file.read();
                tryCompare(file.data[1], "live", "read");
                file.data[1].finishRead(root.configText);
            }
            compare(Config.ready, true);
        }

        function sections() {
            const pad = { "class": "org.acme.pad", width: 60, height: 50, position: "top", margin: 2, entry: "top", motion: "none" };
            const manifest = { schemaVersion: 1, id: "acme.core", name: "Core fixture", version: "1.0.0", author: "Smoke", description: "Core publication",
                kinds: ["service"], entryPoints: { service: "Service.qml" }, capabilities: ["shortcut", "hyprland"],
                settings: { speed: 0, touchpad: true, pads: [] }, schema: {
                    speed: { type: "number", label: "Speed", min: -1, max: 1 },
                    touchpad: { type: "boolean", label: "Touchpad" },
                    pads: { type: "list", label: "Pads", items: {
                        "class": { type: "string", label: "Class", presets: [{ value: "org.acme.pad" }], allowCustom: true },
                        width: { type: "number", label: "Width", min: 10, max: 100 }, height: { type: "number", label: "Height", min: 10, max: 100 },
                        position: { type: "enum", label: "Position", options: [{ value: "top", label: "Top" }] },
                        margin: { type: "number", label: "Margin", min: 0, max: 20 },
                        entry: { type: "enum", label: "Entry", options: [{ value: "top", label: "Top" }] },
                        motion: { type: "enum", label: "Motion", options: [{ value: "none", label: "None" }] }
                    }, defaults: pad }
                }, hyprland: { binds: [{ shortcut: "talk", key: ["SUPER+J", "SUPER+code:44"], hold: true }, { shortcut: "tap", key: "code:44", tap: true }],
                    options: { speed: "input.sensitivity", touchpad: "device.touchpad.enabled" },
                    layerRules: [{ namespace: "^vgs:core$", blur: true }], pads: "pads" } };
            const judged = PluginLogic.validateManifest(manifest, "/fixture");
            verify(judged.ok, judged.error || "the rich fixture is judged");
            Registry.manifests = { "acme.core": judged.manifest };
            return [PluginLogic.hyprlandSection({ plugins: [{ id: "acme.core", speed: 0.35, touchpad: false,
                pads: [Object.assign({ name: "one" }, pad)], keys: { "pad-one": "SUPER+ALT+P" } }] }, judged.manifest)];
        }

        function init() {
            Registry.scanned = false;
            Registry.hyprlandSections = sections();
            Capabilities.hyprland.foreignKeys = [];
            Capabilities.hyprland.userBindRows = [];
            Capabilities.hyprland.touchpads = null;
            Capabilities.hyprland.devicesFailure = "";
            Capabilities.hyprland.devices = null;
            Capabilities.hyprland.pendingKeys = null;
            Capabilities.hyprland.resolvingKeys = false;
            root.scene = fixture.createObject(root);
            verify(root.scene !== null);
            tryVerify(() => root.scene.publisher !== null);
        }

        function cleanup() {
            if (root.scene === null) return;
            root.scene.destroy();
            root.scene = null;
            tryCompare(Capabilities, "publisherHolds", 0);
            Capabilities.hyprland.pendingKeys = null;
            Capabilities.hyprland.resolvingKeys = false;
            Registry.hyprlandSections = [];
            Registry.manifests = {};
        }

        function running(predicate) {
            let process;
            tryVerify(() => (process = ProcessRegistry.processes.find(p => p.running && predicate(p.command))) !== undefined);
            return process;
        }

        function command(text) { return running(argv => argv.join(" ") === text); }
        function file(layer) {
            for (const child of layer.data) if (child.path === layer.path) return child;
            fail("the publisher has its actual FileView");
        }
        function mkdir(layer) { command("mkdir -p -- " + layer.dir).finish(0, 0); }
        function reload() { command("hyprctl reload config-only").finish(0, 0, "ok"); }
        function answer(layer, kind) {
            if (kind === "failure") Capabilities.hyprland.finishKeys({ ok: false, error: "refused: keymap=timeout" });
            else if (kind === "policy") Capabilities.hyprland.finishKeys({ ok: false, error: "refused: keymap=custom-file" });
            else Capabilities.hyprland.finishKeys({ ok: true, translation: Capabilities.hyprland.pendingKeys.keys.map(key => ({
                modifiers: key.indexOf("SUPER") === 0 ? key.indexOf("ALT") !== -1 ? ["SUPER", "ALT"] : ["SUPER"] : [],
                keycode: key.indexOf("ALT") !== -1 ? 33 : 44
            })) });
        }

        function checkCore(text) {
            for (const needle of ["hl.__vgs_key_passthrough", "enterAnyWindow", "vgs:passthrough-cancel", "allow_session_lock_restore = true", "vgs:freeze", "vgs:window", "vgs:tui", "hl.__vgs_pads", "acme.core:pad-one", "^vgs:core$", "sensitivity = 0.35"])
                verify(text.includes(needle), "core bytes retain " + needle);
            verify(!text.includes('hl.dsp.global("acme.core:'), "all section-derived binds stay withheld in every submap");
            verify(!text.includes("hl.__vgs_tap ="), "tap tracker stays withheld");
        }

        function readinessReader() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../smoke/Probe.qml"), false);
            request.send();
            const source = request.responseText;
            verify(source.length > 0, "the actual Probe source is readable");
            const start = "        function hyprlandReadiness(): string {";
            const end = "        function readInstance(hostKey: string, id: string, property: string): string {";
            compare(source.split(start).length, 2, "one readiness method");
            compare(source.split(end).length, 2, "one following reader delimiter");
            const from = source.indexOf(start);
            const to = source.indexOf(end, from);
            verify(to > from, "the existing following reader delimits the complete method");
            const method = source.slice(from, to);
            verify(method.replace(/\s+$/, "").endsWith("        }"), "the complete method closes before the delimiter");
            compare(method.split("function ").length, 2, "no second function is extracted");
            const reader = Qt.createQmlObject("import QtQuick\nimport Quickshell\nimport qs.Core\nQtObject { property var hyprland\n" + method + "\n}", root);
            verify(reader !== null, "the actual reader method instantiates");
            reader.hyprland = root.scene.loader;
            return reader;
        }

        function test_readiness_reports_current_admission() {
            const layer = root.scene.publisher;
            const reader = readinessReader();
            try {
                compare(JSON.parse(reader.hyprlandReadiness()).available, false, "unread devices are unavailable");
                Capabilities.hyprland.devices = { mice: [], keyboards: [{ main: true, name: "fixture", layout: "us,de", activeLayoutIndex: 0, activeKeymap: "English (US)" }] };
                Capabilities.hyprland.touchpads = ["fixture-touchpad"];
                Registry.scanned = true;
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null && layer.rendered !== null);
                let facts = JSON.parse(reader.hyprlandReadiness());
                compare(facts.available, true);
                compare(facts.admitted, false, "readiness does not admit a pending keymap");
                compare(facts.currentPlan, false);
                compare(facts.resolvingKeys, true);
                compare(facts.keyboards[0].layout, "us,de");
                compare(facts.keyboards[0].activeLayoutIndex, 0);
                running(argv => argv.indexOf("vgs-welcome") !== -1).finish(0, 0, "seen");
                file(layer).failRead(FileViewError.FileNotFound);
                mkdir(layer);
                reload();
                command(layer.runner + " hypr state").finish(0, 0, "ok hypr=wired path=/fixture");
                answer(layer, "success");
                tryVerify(() => layer.rendered.plan.phase === "admitted");
                mkdir(layer);
                reload();
                facts = JSON.parse(reader.hyprlandReadiness());
                compare(facts.admitted, true);
                compare(facts.currentPlan, true);
                compare(facts.writerPhase, "idle");
                compare(facts.resolvingKeys, false);
                const admitted = layer.rendered;
                Capabilities.hyprland.keymapRevision++;
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
                compare(layer.rendered, admitted);
                facts = JSON.parse(reader.hyprlandReadiness());
                compare(facts.admitted, false, "readiness does not admit a pending keymap");
                compare(facts.currentPlan, false);
                answer(layer, "success");
                tryVerify(() => JSON.parse(reader.hyprlandReadiness()).currentPlan);
                reader.hyprland = null;
                compare(JSON.parse(reader.hyprlandReadiness()).available, false, "missing loader is unavailable");
            } finally { reader.destroy(); }
        }

        function test_start_over_a_layer_on_disk_data() {
            return [{ tag: "admitted", kind: "success" }, { tag: "failed", kind: "failure" }];
        }

        // expected-log: hyprland: refused: keymap=timeout -- the failed row finishes the real resolver callback with an operational refusal
        function test_start_over_a_layer_on_disk(data) {
            const layer = root.scene.publisher;
            file(layer).finishRead("-- a layer an earlier run wrote\n");
            tryVerify(() => typeof layer.machine.onDisk === "string");
            Capabilities.hyprland.touchpads = ["fixture-touchpad"];
            Registry.scanned = true;
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            compare(layer.rendered, null, "a start over a layer on disk writes no core text before its keys");
            answer(layer, data.kind);
            if (data.kind === "failure") {
                compare(layer.bindSnapshot.read.kind, "failed");
                Capabilities.hyprland.devices = { mice: [], keyboards: [{ main: true, name: "fixture", layout: "us",
                    activeLayoutIndex: 0, activeKeymap: "English (US)" }] };
                tryVerify(() => Capabilities.hyprland.pendingKeys !== null, 1000, "a devices change reads the keys again");
                compare(layer.rendered, null, "a failed read keeps the layer on disk and writes nothing");
                answer(layer, "success");
            }
            tryVerify(() => layer.rendered !== null, 1000, "admission releases the first render");
            compare(layer.rendered.plan.phase, "admitted");
        }

        function test_core_and_consent_without_keys_data() {
            return [
                { tag: "never-connect", kind: "never", action: "connect", early: false },
                { tag: "never-decline", kind: "never", action: "decline", early: false },
                { tag: "failed-connect", kind: "failure", action: "connect", early: false },
                { tag: "failed-decline", kind: "failure", action: "decline", early: false },
                { tag: "success-after-welcome", kind: "success", action: "connect", early: false },
                { tag: "success-during-write", kind: "success", action: "connect", early: true },
                { tag: "policy-after-welcome", kind: "policy", action: "decline", early: false }
            ];
        }

        // expected-log: hyprland: refused: keymap=timeout -- failure rows finish the real resolver callback with an operational refusal
        function test_core_and_consent_without_keys(data) {
            const layer = root.scene.publisher;
            compare(layer.rendered, null, "scan readiness still gates the first render");
            Registry.scanned = true;
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            tryVerify(() => layer.rendered !== null, 1000, "core publication does not wait for key admission");
            compare(layer.rendered.plan.phase, "core");
            compare(layer.rendered.plan.sections.length, 1);
            compare(layer.rendered.plan.keys["acme.core"].talk, null);
            compare(Registry.hyprlandKeyIdentities, null);
            compare(layer.render(), "refused: hyprland=pending");
            checkCore(layer.rendered.text);
            verify(layer.rendered.text.includes("Hyprland's touchpads are not read yet"));
            Capabilities.hyprland.touchpads = ["fixture-touchpad"];
            tryVerify(() => layer.rendered.text.includes('hl.device({ name = "fixture-touchpad", enabled = false })'));
            running(argv => argv.indexOf("vgs-welcome") !== -1).finish(0, 0, "unseen");
            file(layer).failRead(FileViewError.FileNotFound);
            if (data.early) {
                answer(layer, "success");
                tryVerify(() => layer.rendered.plan.phase === "admitted");
            }
            mkdir(layer);
            reload();
            // An admission during the core write queues the admitted text
            // through the same writer, before the existing consent probe.
            if (data.early) { mkdir(layer); reload(); }
            command(layer.runner + " hypr state").finish(0, 0, "ok hypr=unwired path=/fixture");
            running(argv => argv.indexOf("vgs-hypr-consent") !== -1).finish(0, 0, "absent");
            compare(Notices.consentState.phase, "asking");
            verify(Notices.consent !== null && Notices.consent.welcome);
            compare(Notices.consent.busy, false);
            compare(JSON.stringify(Notices.consent.actions.map(row => row.answer)), '["connect","decline"]');
            if (!data.early) {
                compare(Notices.consent.keys.length, 0);
                checkCore(file(layer).written);
            }
            if (data.kind === "failure") {
                answer(layer, data.kind);
                compare(layer.bindSnapshot.read.kind, "failed");
                compare(layer.rendered.plan.phase, "core");
                compare(Capabilities.hyprland.pendingKeys, null, "a failed snapshot does not retry");
                verify(Registry.hyprlandProblems.some(row => row.error === "hyprland: refused: keymap=timeout"));
            } else if (data.kind !== "never" && !data.early) {
                answer(layer, data.kind);
                tryVerify(() => layer.rendered.plan.phase === "admitted");
                mkdir(layer);
                reload();
                compare(layer.rendered.plan.keys["acme.core"].talk, data.kind === "policy" ? "SUPER+J" : "SUPER+code:44");
                if (data.kind === "success") verify(!file(layer).written.includes('hl.bind("SUPER + J",'));
            }
            Notices.consentAnswered(data.action);
            if (data.action === "connect") {
                command(layer.runner + " hypr wire").finish(0, 0, "ok hypr=wired path=/fixture");
                reload();
                compare(Notices.consentState.phase, "wired");
            } else {
                running(argv => argv[0] === "bash" && argv.indexOf(layer.consentDir) !== -1 && argv.indexOf(layer.consentDeclined) !== -1).finish(0, 0);
                compare(Notices.consentState.phase, "declined");
            }
            if (data.kind === "never" || data.kind === "failure") {
                checkCore(file(layer).written);
                compare(layer.rendered.plan.keys["acme.core"].talk, null);
            }
            running(argv => argv.indexOf("vgs-welcome") !== -1).finish(0, 0);
        }
    }
}
