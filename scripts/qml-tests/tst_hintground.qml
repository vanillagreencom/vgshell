import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// A shared key hint reads its ground from the surface it draws on: a
// Surface that holds it or lies under it publishes its fill, glass made
// opaque, and a hint with no surface under it takes its window's colour.
// The caller hands only what that surface does not draw.
Item {
    id: root
    width: 640
    height: 400

    Surface {
        width: 300
        height: 60
        KeyHints { id: inside; y: 10; hints: [{ key: "Ctrl+K", text: "Open" }] }
    }

    Surface { y: 80; width: 300; height: 60 }
    KeyHints { id: over; y: 90; hints: [{ key: "Ctrl+K", text: "Open" }] }

    Surface {
        y: 160
        width: 300
        height: 60
        Kbd { id: lone; text: "S"; y: 10 }
        KeyCaps { id: chord; shortcut: "CTRL+S"; x: 60; y: 10 }
    }

    Surface { id: hidden; y: 240; width: 300; height: 60; visible: false }
    KeyHints { id: bare; y: 250; hints: [{ key: "Ctrl+K", text: "Open" }] }

    TestCase {
        name: "hintGround"
        when: windowShown

        property color windowColor

        function initTestCase() { windowColor = root.Window.window.color; }
        function init() { UnitTheme.reset(); Theme.appearanceInput = ""; root.Window.window.color = windowColor; }
        function cleanup() { Theme.appearanceInput = ""; root.Window.window.color = windowColor; }
        function opaqueGlass() { return Qt.color(Theme.glassSolid(Qt.color(Theme.glass.glass.fill))); }

        function composed(fill, base) {
            const f = Qt.color(fill), b = Qt.color(base);
            return Qt.rgba(b.r + (f.r - b.r) * f.a, b.g + (f.g - b.g) * f.a, b.b + (f.b - b.b) * f.a, 1);
        }
        function word(hints) { return hints.children[0].children[1]; }
        function capsOf(hints) { return hints.children[0].children[0].children.find(item => item.shortcut !== undefined); }
        function keyName(cap) { return cap.children[0]; }

        // With glass on, every hint reads on the glass made opaque, where
        // the default inks fall short, whether the surface holds the hint
        // or lies under it, and a lone cap or chord does too.
        function test_hints_read_on_their_surfaces_glass() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            const glass = opaqueGlass();
            const capGround = composed(Theme.kbd.background, glass);
            verify(Theme.contrastRatio(Qt.color(Theme.kbd.foreground), capGround) < 4.5, "the default key ink fails opaque glass");
            for (const hints of [inside, over]) {
                verify(Qt.colorEqual(hints.ground.fill, glass), "the row takes its surface's opaque glass");
                verify(Theme.contrastRatio(word(hints).color, glass) >= 4.5, "a word reads " + Theme.contrastRatio(word(hints).color, glass));
                for (const cap of capsOf(hints).children.filter(item => item.ink !== undefined))
                    verify(Theme.contrastRatio(keyName(cap).color, capGround) >= 4.5, "a key reads " + Theme.contrastRatio(keyName(cap).color, capGround));
            }
            verify(Theme.contrastRatio(keyName(lone).color, capGround) >= 4.5, "a lone cap reads " + Theme.contrastRatio(keyName(lone).color, capGround));
            for (const cap of chord.children.filter(item => item.ink !== undefined))
                verify(Theme.contrastRatio(keyName(cap).color, capGround) >= 4.5, "a chord's key reads " + Theme.contrastRatio(keyName(cap).color, capGround));
        }

        // With glass off the surfaces publish resting fills, where the
        // default muted inks already hold, so the look is unchanged.
        function test_resting_surfaces_keep_the_muted_defaults() {
            for (const hints of [inside, over]) {
                compare(word(hints).color, Qt.color(Theme.text.keyHint.color));
                for (const cap of capsOf(hints).children.filter(item => item.ink !== undefined))
                    compare(keyName(cap).color, Qt.color(Theme.kbd.foreground));
            }
            compare(keyName(lone).color, Qt.color(Theme.kbd.foreground));
        }

        // A hint no surface lies under takes its window's colour, never a
        // hidden surface's, and a window's glass reads made opaque.
        function test_a_hint_without_a_surface_takes_its_window() {
            verify(!Qt.colorEqual(hidden.effectiveFill, windowColor), "the hidden fill " + hidden.effectiveFill + " differs from the window colour " + windowColor);
            verify(bare.ground !== null && Qt.colorEqual(bare.ground.fill, windowColor), "the row takes the window's colour");
            root.Window.window.color = Theme.glass.glass.fill;
            verify(Qt.colorEqual(bare.ground.fill, opaqueGlass()), "a window's glass reads opaque");
        }
    }
}
