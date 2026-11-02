import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// A shared key hint reads its ground from the surface that holds it: a
// Surface, a GlassSurface or a Dialog publishes its fill, glass made
// opaque, to its descendants, and a hint inside none takes its window's
// colour. A hint over a surface it is not inside takes its ground from its
// caller. The read follows only the hint's ancestors, so moving or adding
// a sibling row re-evaluates no row's ground.
Item {
    id: root
    width: 640
    height: 560

    Surface {
        id: holder
        width: 300
        height: 60
        KeyHints { id: inside; y: 10; hints: [{ key: "Ctrl+K", text: "Open" }] }
    }

    Surface { id: beneath; y: 80; width: 300; height: 60 }
    KeyHints { id: over; y: 90; hints: [{ key: "Ctrl+K", text: "Open" }] }

    Surface {
        y: 160
        width: 300
        height: 60
        Kbd { id: lone; text: "S"; y: 10 }
        KeyCaps { id: chord; shortcut: "CTRL+S"; x: 60; y: 10 }
    }

    Dialog {
        id: dialog
        x: 320
        width: 300
        title: "Keys"
        KeyCaps { id: dialogChord; shortcut: "CTRL+S" }
    }

    // Rows of hints beside an earlier sibling surface, inside a list's
    // surface: the cost pin moves that sibling and adds a row.
    Surface {
        id: list
        y: 240
        width: 300
        height: 300
        Column {
            Surface { id: sibling; width: 300; height: 20 }
            Repeater {
                id: listRows
                model: ListModel { id: rowModel; ListElement { n: 0 } ListElement { n: 1 } ListElement { n: 2 } }
                KeyHints {
                    property int groundChanges: 0
                    hints: [{ key: "Ctrl+K", text: "Open" }]
                    onGroundChanged: groundChanges++
                }
            }
        }
    }

    TestCase {
        name: "hintGround"
        when: windowShown

        property color windowColor

        function initTestCase() { windowColor = root.Window.window.color; }
        function init() { UnitTheme.reset(); Theme.appearanceInput = ""; root.Window.window.color = windowColor; }
        function cleanup() { Theme.appearanceInput = ""; root.Window.window.color = windowColor; while (rowModel.count > 3) rowModel.remove(3); sibling.height = 20; }
        function opaqueGlass() { return Qt.color(Theme.glassSolid(Qt.color(Theme.glass.glass.fill))); }

        function composed(fill, base) {
            const f = Qt.color(fill), b = Qt.color(base);
            return Qt.rgba(b.r + (f.r - b.r) * f.a, b.g + (f.g - b.g) * f.a, b.b + (f.b - b.b) * f.a, 1);
        }
        function word(hints) { return hints.children[0].children[1]; }
        function capsOf(hints) { return hints.children[0].children[0].children.find(item => item.shortcut !== undefined); }
        function keys(chord) { return chord.children.filter(item => item.ink !== undefined); }
        function keyName(cap) { return cap.children[0]; }

        // With glass on, a hint inside a surface, a lone cap, a chord and a
        // dialog's content read on the glass made opaque, where the default
        // inks fall short.
        function test_hints_read_on_their_surfaces_glass() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            const glass = opaqueGlass();
            const capGround = composed(Theme.kbd.background, glass);
            verify(Theme.contrastRatio(Qt.color(Theme.kbd.foreground), capGround) < 4.5, "the default key ink fails opaque glass");
            verify(Qt.colorEqual(inside.ground.fill, glass), "the row takes its surface's opaque glass");
            verify(Theme.contrastRatio(word(inside).color, glass) >= 4.5, "a word reads " + Theme.contrastRatio(word(inside).color, glass));
            for (const cap of keys(capsOf(inside)).concat(keys(chord), [lone], keys(dialogChord)))
                verify(Theme.contrastRatio(keyName(cap).color, capGround) >= 4.5, "a key reads " + Theme.contrastRatio(keyName(cap).color, capGround));
            verify(Qt.colorEqual(dialogChord.ground.fill, dialog.hintGround), "a dialog's content takes the dialog card's ground");
        }

        // With glass off the surfaces publish resting fills, where the
        // default muted inks already hold, so the look is unchanged.
        function test_resting_surfaces_keep_the_muted_defaults() {
            compare(word(inside).color, Qt.color(Theme.text.keyHint.color));
            for (const cap of keys(capsOf(inside)).concat([lone]))
                compare(keyName(cap).color, Qt.color(Theme.kbd.foreground));
        }

        // Drawn glass, in a window that paints nothing, publishes its fill
        // made opaque, never the clear fill.
        function test_drawn_glass_publishes_its_glass_made_opaque() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            root.Window.window.color = "transparent";
            tryVerify(() => holder.drawn, 1000, "the surface draws its glass");
            verify(Qt.colorEqual(holder.hintGround, Theme.glassSolid(holder.fill)), "the published ground is the glass made opaque");
        }

        // A hint over a surface it is not inside reads no sibling: it takes
        // its window's colour unless its caller hands that surface's ground.
        function test_a_hint_over_a_surface_takes_its_callers_ground() {
            verify(!Qt.colorEqual(beneath.hintGround, windowColor), "the surface's ground differs from the window's");
            verify(over.ground !== null && Qt.colorEqual(over.ground.fill, windowColor), "the row takes the window's colour");
            over.backgroundContext = { fill: beneath.hintGround };
            verify(Qt.colorEqual(over.ground.fill, beneath.hintGround), "the caller's ground is taken");
            over.backgroundContext = null;
            root.Window.window.color = Theme.glass.glass.fill;
            verify(Qt.colorEqual(over.ground.fill, opaqueGlass()), "a window's glass reads opaque");
        }

        // The rows' grounds follow their ancestors alone: resizing an
        // earlier sibling surface, which moves every row, and adding a row
        // re-evaluate none of them.
        function test_moving_a_sibling_reevaluates_no_rows_ground() {
            const rows = [0, 1, 2].map(index => listRows.itemAt(index));
            for (const row of rows) {
                verify(row.ground !== null, "each row takes the list's ground");
                row.groundChanges = 0;
            }
            sibling.height = 40;
            rowModel.append({ n: 3 });
            tryVerify(() => listRows.count === 4, 1000);
            compare(rows.map(row => row.groundChanges), [0, 0, 0], "no row's ground re-evaluated");
        }
    }
}
