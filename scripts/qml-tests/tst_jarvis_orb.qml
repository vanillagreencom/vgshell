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
// continuous and rising from 0 to 1. A state that can show all day draws
// at most its look's frame rate and the others every frame. Motion scale 0
// stills every state, the clocks wrap at their turns, and they reset when
// the orb goes inactive. The offscreen renderer draws no shader, so a
// drawn frame here is a change of the shader's clock uniform, counted
// against this test's own FrameAnimation, one tick a frame; the frames a
// real window swaps are scripts/smoke/rows/jarvis-bubble.sh's.
Item {
    id: root
    width: 320
    height: 320

    ParticleOrb { id: orb; active: true; look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT) }
    FrameAnimation { id: frames }

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
        function shader() { return orb.data.find(item => item.fragmentShader !== undefined); }
        function clock() { return orb.data.find(item => item.reset !== undefined && item.flow !== undefined); }

        // The motion model's table (docs/architecture/jarvis.md § Overlay
        // motion): each state's base flow, in noise units a second, and its
        // quarter turn, in milliseconds at motion scale 1, and the most
        // frames a second it draws, 0 for every frame the screen draws.
        function test_each_state_moves_at_its_base_rate_data() {
            return [
                { tag: "armed", phase: "armed", flow: 0.05, quarterTurn: 9000, frameRate: 30 },
                { tag: "idle", phase: "idle", flow: 0.04, quarterTurn: 10000, frameRate: 30 },
                { tag: "muting", phase: "muting", flow: 0.03, quarterTurn: 10000, frameRate: 30 },
                { tag: "stopping", phase: "down", flow: 0.03, quarterTurn: 10000, frameRate: 0 },
                { tag: "listening", phase: "listening", flow: 0.08, quarterTurn: 8000, frameRate: 0 },
                { tag: "thinking", phase: "thinking", flow: 0.12, quarterTurn: 1750, frameRate: 0 },
                { tag: "acting", phase: "acting", flow: 0.2, quarterTurn: 1125, frameRate: 0 },
                { tag: "speaking", phase: "speaking", flow: 0.3, quarterTurn: 7500, frameRate: 0 },
                { tag: "confirming", phase: "confirming", flow: 0.1, quarterTurn: 7000, frameRate: 0 },
                { tag: "error", phase: "error", flow: 0.04, quarterTurn: 10000, frameRate: 30 }
            ];
        }

        function test_each_state_moves_at_its_base_rate(data) {
            orb.phase = data.phase;
            compare(orb.tone.flow, data.flow);
            compare(orb.tone.quarterTurn, data.quarterTurn);
            compare(orb.tone.frameRate, data.frameRate);
        }

        // The shader's clock uniform changes and the frames ticked over 1 s
        // of a settled look.
        function drawsOver(phase) {
            orb.phase = phase;
            wait(orb.look.orb.transition + 50);
            const target = shader();
            let draws = 0;
            let ticks = 0;
            const draw = () => draws++;
            const tick = () => ticks++;
            target.uTimeChanged.connect(draw);
            frames.triggered.connect(tick);
            frames.running = true;
            const start = Date.now();
            // The reading is a real 1 s of frames.
            wait(1000);
            const seconds = (Date.now() - start) / 1000;
            frames.running = false;
            frames.triggered.disconnect(tick);
            target.uTimeChanged.disconnect(draw);
            return { draws: draws, ticks: ticks, seconds: seconds };
        }

        // A state that can show all day draws at most its look's rate,
        // while the frames run faster than that; it still moves.
        function test_a_paced_state_draws_at_most_its_rate_data() {
            return ["armed", "idle", "muting", "error"].map(phase => ({ tag: phase, phase: phase }));
        }

        function test_a_paced_state_draws_at_most_its_rate(data) {
            const rate = orb.look.state[data.phase].frameRate;
            const read = drawsOver(data.phase);
            const detail = JSON.stringify(read) + " rate=" + rate;
            verify(read.draws >= 1, "the paced orb moves: " + detail);
            verify(read.draws <= Math.ceil(read.seconds * rate) + 1, "the paced orb draws at most its rate: " + detail);
            verify(read.ticks >= 1.5 * read.draws, "the frames run faster than the paced orb draws: " + detail);
        }

        // An active state draws on every frame.
        function test_an_active_state_draws_every_frame_data() {
            return ["listening", "thinking", "acting", "speaking", "confirming"].map(phase => ({ tag: phase, phase: phase }));
        }

        function test_an_active_state_draws_every_frame(data) {
            const read = drawsOver(data.phase);
            const detail = JSON.stringify(read);
            verify(read.ticks >= 20, "the frames run: " + detail);
            verify(Math.abs(read.draws - read.ticks) <= 2, "the orb draws on every frame: " + detail);
        }

        // In every state, silent or not, the clocks move at motion scale
        // above 0 and advance the field, and stop at 0.
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
            compare(orb.moving, data.runs);
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

        // A clock left running for days wraps where the drawn motion
        // repeats, so the shader's float32 uniforms keep their precision:
        // one just short of its turn passes it and starts again near 0.
        function test_a_long_running_clock_stays_within_its_turn_data() {
            return [{ tag: "the flow", clock: "flow", turn: "flowTurn" }, { tag: "the twinkle", clock: "time", turn: "twinkleTurn" }];
        }

        function test_a_long_running_clock_stays_within_its_turn(data) {
            orb.phase = "speaking";
            const held = clock();
            const turn = orb[data.turn];
            verify(turn > 1, "the turn is longer than a frame's step: " + turn);
            held[data.clock] = turn - 1e-4;
            tryVerify(() => held[data.clock] < 1, 1000, "the clock passes its turn and starts again: " + held[data.clock]);
            verify(held[data.clock] >= 0, "the clock stays at or above 0: " + held[data.clock]);
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
