import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance

// Jarvis's orb moves in every state, at the state's own base rate, and the
// driving level adds to that rate through one input curve that is
// continuous and rising from 0 to 1. Motion scale 0 stills every state,
// and the clocks reset when the orb goes inactive. The offscreen renderer
// draws no shader; the driver's frames on a real window are
// scripts/smoke/rows/jarvis-bubble.sh's.
Item {
    id: root
    width: 320
    height: 320

    ParticleOrb { id: orb; active: true; look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT) }

    TestCase {
        name: "jarvis-orb"
        when: windowShown

        function init() {
            UnitTheme.reset();
            QsWindow.window = root.Window.window;
            orb.capture = 0;
            orb.playback = 0;
            orb.active = true;
        }
        function cleanup() { QsWindow.window = null; }
        function driver() { return orb.data.find(item => item.frameTime !== undefined && item.running !== undefined); }
        function clock() { return orb.data.find(item => item.reset !== undefined && item.flow !== undefined); }

        // The motion model's table (docs/architecture/jarvis.md § Motion
        // model): each state's base flow, in noise units a second, and its
        // quarter turn, in milliseconds at motion scale 1.
        function test_each_state_moves_at_its_base_rate_data() {
            return [
                { tag: "armed", phase: "armed", flow: 0.05, quarterTurn: 9000 },
                { tag: "idle", phase: "idle", flow: 0.04, quarterTurn: 10000 },
                { tag: "muting", phase: "muting", flow: 0.03, quarterTurn: 10000 },
                { tag: "stopping", phase: "down", flow: 0.03, quarterTurn: 10000 },
                { tag: "listening", phase: "listening", flow: 0.08, quarterTurn: 8000 },
                { tag: "thinking", phase: "thinking", flow: 0.12, quarterTurn: 1750 },
                { tag: "acting", phase: "acting", flow: 0.2, quarterTurn: 1125 },
                { tag: "speaking", phase: "speaking", flow: 0.3, quarterTurn: 7500 },
                { tag: "confirming", phase: "confirming", flow: 0.1, quarterTurn: 7000 },
                { tag: "error", phase: "error", flow: 0.04, quarterTurn: 10000 }
            ];
        }

        function test_each_state_moves_at_its_base_rate(data) {
            orb.phase = data.phase;
            compare(orb.tone.flow, data.flow);
            compare(orb.tone.quarterTurn, data.quarterTurn);
        }

        // In every state, silent or not, the driver runs at motion scale
        // above 0 and advances the field, and stops at 0.
        function test_every_state_runs_its_driver_data() {
            const out = [];
            for (const phase of ["armed", "idle", "muting", "down", "listening", "thinking", "acting", "speaking", "confirming", "error"]) {
                out.push({ tag: phase, phase: phase, scale: 1, runs: true });
                out.push({ tag: phase + " at motion scale 0", phase: phase, scale: 0, runs: false });
            }
            return out;
        }

        function test_every_state_runs_its_driver(data) {
            compare(UnitTheme.override({ motion: { scale: data.scale } }), "ok");
            orb.phase = data.phase;
            compare(driver().running, data.runs);
            if (!data.runs) return;
            const before = clock().flow;
            tryVerify(() => clock().flow > before, 1000, "the field moves");
        }

        // One input curve, the same for capture and playback: 0 at 0 and 1
        // at 1, rising, with no step between neighbouring levels. Quiet
        // speech moves the orb visibly and a loud voice clearly more.
        function test_the_input_curve_is_continuous_and_rising() {
            compare(orb.response(0), 0);
            compare(orb.response(1), 1);
            let previous = orb.response(0);
            for (let i = 1; i <= 1000; i++) {
                const value = orb.response(i / 1000);
                verify(value >= previous, "rising at level " + i / 1000);
                verify(value - previous <= 0.005, "no step at level " + i / 1000 + ": " + (value - previous));
                previous = value;
            }
            verify(orb.response(0.1) >= 0.2, "quiet speech moves the orb: " + orb.response(0.1));
            verify(orb.response(0.5) >= orb.response(0.1) + 0.4, "a loud voice moves it clearly more: " + orb.response(0.5));
        }

        // The level a look reads goes through the curve; a level the look
        // does not read adds nothing.
        function test_the_driving_level_goes_through_the_curve_data() {
            return [
                { tag: "listening to a voice", phase: "listening", capture: 0.3, target: 0.3 },
                { tag: "speaking", phase: "speaking", playback: 0.3, target: 0.3 },
                { tag: "a level the look does not read", phase: "armed", capture: 0.5, playback: 0.5, target: 0 }
            ];
        }

        function test_the_driving_level_goes_through_the_curve(data) {
            orb.phase = data.phase;
            orb.capture = data.capture || 0;
            orb.playback = data.playback || 0;
            compare(orb.target, data.target === 0 ? 0 : orb.response(data.target));
        }

        function test_an_inactive_orb_resets_its_clocks() {
            orb.phase = "speaking";
            const held = clock();
            verify(held !== undefined, "the orb holds its clock");
            held.flow = 12;
            held.swirl = 1;
            held.time = 30;
            orb.active = false;
            compare(held.flow, 0);
            compare(held.swirl, 0);
            compare(held.time, 0);
        }
    }
}
