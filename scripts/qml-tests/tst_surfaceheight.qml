import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// SurfaceHeight: the surface keeps one size while the content changes inside
// its room and follows the content only past it; the card's height takes a
// change at once until its window has drawn, then animates to it,
// continuing from the drawn height when a newer target arrives; the content
// lays out at the card's height, clipped only while the card grows; a Pane
// inside a growing card keeps its footer on the card's edge and shows no
// scroll bar or footer divider; a hidden window and motion.scale 0 take
// every change at once.
Item {
    id: root
    width: 300
    height: 700
    // Reading Theme builds it, which attaches UnitTheme before init runs.
    readonly property int resize: Theme.motion.surface.resize.duration

    SurfaceHeight {
        id: sized
        target: 100
        room: 400

        Rectangle { id: card; anchors.fill: parent; color: "black" }
    }

    // A fitted pane in a card, as a summoned panel draws: rows in its body
    // and a footer under them.
    Component {
        id: paneCard
        SurfaceHeight {
            id: holder
            property alias pane: inner
            width: 260
            target: inner.implicitHeight
            Pane {
                id: inner
                anchors.fill: parent
                container: "panel"
                fitToContent: true
                property int rowCount: 2
                Repeater { model: inner.rowCount; ListItem { required property int index; width: inner.contentWidth; text: "Row " + index } }
                footer: [ Item { width: 10; height: 30 } ]
            }
        }
    }

    TestCase {
        name: "surfaceheight"
        when: windowShown

        function init() {
            compare(UnitTheme.override({ motion: { surface: { resize: { duration: 400 } } } }), "ok");
            sized.live = false;
            sized.target = 100;
            sized.live = true;
        }
        function cleanupTestCase() { UnitTheme.reset(); }

        // Every value the surface takes while a test runs.
        function watch() {
            const seen = [];
            const record = () => seen.push(sized.surface);
            sized.surfaceChanged.connect(record);
            return { seen: seen, stop: () => sized.surfaceChanged.disconnect(record) };
        }

        function test_before_the_first_frame_a_change_lands_at_once() {
            sized.live = false;
            sized.target = 250;
            compare(sized.height, 250);
        }

        function test_a_grow_inside_the_room_keeps_the_surface() {
            const surfaces = watch();
            compare(sized.surface, 400);
            sized.target = 300;
            verify(sized.height < 300, "the card has not jumped");
            compare(card.height, sized.height, "the content lays out at the card's height");
            compare(sized.clip, true, "the card clips while it grows");
            tryCompare(sized, "height", 300, 2000);
            compare(sized.clip, false, "the card draws unclipped at rest");
            surfaces.stop();
            compare(surfaces.seen, []);
        }

        function test_a_shrink_inside_the_room_keeps_the_surface() {
            sized.target = 300;
            tryCompare(sized, "height", 300, 2000);
            const surfaces = watch();
            sized.target = 120;
            verify(sized.height > 120);
            compare(card.height, sized.height, "the content keeps the drawn height while the card shrinks");
            tryCompare(sized, "height", 120, 2000);
            surfaces.stop();
            compare(surfaces.seen, []);
        }

        function test_a_pane_in_a_growing_card_keeps_its_footer_and_no_bar() {
            const holder = createTemporaryObject(paneCard, root);
            const pane = holder.pane;
            const footer = pane.children[4];
            const footerDivider = pane.children[6];
            tryCompare(holder, "live", true, 2000);
            compare(UnitTheme.override({ motion: { surface: { resize: { duration: 2000 } } } }), "ok");
            pane.rowCount = 9;
            // The body's Column lays its rows out at the next polish.
            tryVerify(() => holder.height < holder.target - 40, 1000, "the card grows");
            verify(pane.scrollArea.overflowing, "the body is shorter than its rows while the card grows");
            compare(pane.scrollArea.bar.visible, false, "no scroll bar for the grow");
            compare(footerDivider.visible, false, "no footer divider for the grow");
            verify(footer.y + footer.height <= holder.height, "the footer stays on the card");
            tryCompare(holder, "height", holder.target, 5000);
            compare(pane.scrollArea.overflowing, false);
        }

        function test_content_past_the_room_takes_the_surface() {
            sized.target = 520;
            compare(sized.surface, 520);
            tryCompare(sized, "height", 520, 2000);
            sized.target = 200;
            compare(sized.surface, 400);
        }

        function test_a_newer_target_continues_from_the_drawn_height() {
            compare(UnitTheme.override({ motion: { surface: { resize: { duration: 2000 } } } }), "ok");
            sized.target = 300;
            tryVerify(() => sized.height > 150, 3000);
            const reached = sized.height;
            verify(reached < 250);
            sized.target = 50;
            verify(Math.abs(sized.height - reached) < 40);
            tryCompare(sized, "height", 50, 5000);
        }

        function test_a_hidden_window_takes_a_change_at_once() {
            const window = Qt.createQmlObject("import QtQuick\nimport QtQuick.Window\nimport qs.Ui\nWindow { width: 200; height: 200; visible: true; property alias sized: inner\n SurfaceHeight { id: inner; target: 100 } }", root);
            window.sized.live = true;
            window.visible = false;
            compare(window.sized.live, false);
            window.sized.target = 260;
            compare(window.sized.height, 260);
            window.destroy();
        }

        function test_motion_scale_zero_runs_no_animation() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            sized.target = 280;
            compare(sized.height, 280);
            sized.target = 90;
            compare(sized.height, 90);
        }
    }
}
