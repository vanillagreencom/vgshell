import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance

// Jarvis's particle orb decides to move only in a look with a clock of its
// own (thinking, acting, speaking, confirming) or while its driving level
// is above the look's floor; the looks a phase with no deadline shows
// (armed, idle, error, down, muting) stand still, and listening stands
// still in a silent room. Motion scale 0 stills every look, and the
// clocks reset when the orb goes inactive. The offscreen renderer draws no
// shader; the driver's frames on a real window are scripts/smoke/rows/jarvis-bubble.sh's.
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
            orb.capture = 0;
            orb.playback = 0;
            orb.active = true;
        }

        function test_only_a_bounded_phase_has_a_clock_data() {
            return [
                { tag: "armed", phase: "armed", moves: false },
                { tag: "idle", phase: "idle", moves: false },
                { tag: "error", phase: "error", moves: false },
                { tag: "down", phase: "down", moves: false },
                { tag: "muting", phase: "muting", moves: false },
                { tag: "listening in a silent room", phase: "listening", moves: false },
                { tag: "listening below the floor", phase: "listening", capture: 0.02, moves: false },
                { tag: "listening to a voice", phase: "listening", capture: 0.5, moves: true },
                { tag: "a level another look does not read", phase: "armed", capture: 0.5, playback: 0.5, moves: false },
                { tag: "thinking", phase: "thinking", moves: true },
                { tag: "acting", phase: "acting", moves: true },
                { tag: "speaking", phase: "speaking", moves: true },
                { tag: "confirming", phase: "confirming", moves: true },
                { tag: "thinking at motion scale 0", phase: "thinking", scale: 0, moves: false },
                { tag: "listening to a voice at motion scale 0", phase: "listening", capture: 0.5, scale: 0, moves: false }
            ];
        }

        function test_only_a_bounded_phase_has_a_clock(data) {
            if (data.scale !== undefined) compare(UnitTheme.override({ motion: { scale: data.scale } }), "ok");
            orb.phase = data.phase;
            orb.capture = data.capture || 0;
            orb.playback = data.playback || 0;
            compare(orb.moves, data.moves);
        }

        function test_an_inactive_orb_resets_its_clocks() {
            orb.phase = "speaking";
            let clock;
            for (let i = 0; i < orb.data.length; i++)
                if (orb.data[i].reset !== undefined && orb.data[i].flow !== undefined) clock = orb.data[i];
            verify(clock !== undefined, "the orb holds its clock");
            clock.flow = 12;
            clock.swirl = 1;
            clock.time = 30;
            orb.active = false;
            compare(clock.flow, 0);
            compare(clock.swirl, 0);
            compare(clock.time, 0);
        }
    }
}
