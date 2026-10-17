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

    readonly property string configText: JSON.stringify({ version: 2 }, null, 2) + "\n"
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

        function initTestCase() {
            finishConfigRead(Config.shippedPath);
            finishConfigRead(Config.userPath);
            compare(Config.ready, true);
            tryVerify(() => layer.rendered !== null, 1000, "the first render");
            layerFile().failRead(FileViewError.FileNotFound);
            finishWrite();
            running(layer.runner + " hypr state").finish(0, 0, "ok hypr=wired path=/stand-in");
            compare(layer.machine.phase, "idle");
            compare(layer.machine.failure, "");
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
    }
}
