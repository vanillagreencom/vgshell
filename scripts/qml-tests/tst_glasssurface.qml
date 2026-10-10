import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// GlassSurface: with glass on it draws the shadow, the handed fill and
// radius, the sheen and the hairline, from Theme.glass and the elevation it
// is handed; with glass off it draws the standard look it is handed, the
// raised surface's by default, and none of the glass. The surface's own
// choice decides until the user's `glass` Appearance value turns glass on or
// off everywhere, for the qs.Ui surfaces built on it too: a panel's Surface,
// a LevelOsd and a Dialog. Glass is drawn only where the surface is its
// window's backdrop: a window whose colour is transparent, as every VGS
// layer and popup is, and no GlassSurface around it; the test window is
// made transparent for the rest. `follow` lays it under another item. Expected values are worked by hand from Glass.js and
// Tokens.js, never read from Theme: the hairline is #e8e8e8 at alpha 0.09,
// round(22.95) = 23 = 0x17; the tight shadow black at 0.45, round(114.75) =
// 115 = 0x73; the wide one at 0.55, round(140.25) = 140 = 0x8c; the default
// fill #101010 at 0.8, 204 = 0xcc; the raised surface neutral(0.075),
// #101010, under a #3a3a3b border; in light mode the hairline #2a2a2a at
// 0.1, round(25.5) = 26 = 0x1a.
Item {
    id: root
    width: 400
    height: 300

    Item {
        id: target
        x: 30; y: 40; width: 120; height: 60
        opacity: 0.5
        scale: 0.8
        transformOrigin: Item.TopLeft
    }

    GlassSurface {
        id: chosen
        x: 10; y: 10; width: 200; height: 100
        optIn: true
        fill: "#33445566"
        radius: 20
        elevation: "tight"
        Item { id: content; anchors.fill: parent }
    }

    GlassSurface {
        id: plain
        x: 10; y: 150; width: 200; height: 100
        fill: "#33445566"
        radius: 20
    }

    GlassSurface {
        id: follower
        optIn: true
        follow: target
    }

    GlassSurface {
        id: unnamed
        optIn: true
    }

    GlassSurface {
        id: handed
        x: 220; y: 10; width: 100; height: 60
        standard: ({ background: "#203040", border: "#506070", radius: 7 })
    }

    GlassSurface {
        id: outer
        x: 330; y: 10; width: 60; height: 60
        optIn: true
        GlassSurface { id: inner; anchors.fill: parent; optIn: true }
    }

    Surface { id: panel; x: 220; y: 80; width: 100; height: 60 }
    LevelOsd { id: osd; x: 220; y: 150; level: 0.5 }
    Dialog { id: dialog; x: 10; y: 260; width: 200; title: "Glass" }

    TestCase {
        name: "glasssurface"
        when: windowShown

        function initTestCase() {
            root.Window.window.color = "transparent";
        }

        function init() {
            UnitTheme.reset();
            Theme.appearanceInput = "";
            unnamed.elevation = "wide";
        }

        function shadowOf(glass) { return glass.children[0]; }
        function bodyOf(glass) { return glass.children[1]; }
        function sheenOf(glass) { return bodyOf(glass).children[0]; }
        function edgeOf(glass) { return glass.children[2]; }

        function test_glass_draws_every_layer_with_the_handed_values() {
            verify(chosen.on);
            const shadow = shadowOf(chosen);
            verify(shadow.visible);
            compare([shadow.blur, shadow.spread, shadow.offset.y, String(shadow.color)], [30, -4, 10, "#73000000"]);
            compare(shadow.radius, 20);
            const body = bodyOf(chosen);
            compare(String(body.color), "#33445566");
            compare(body.radius, 20);
            verify(body.clip);
            verify(sheenOf(chosen).visible);
            compare(String(sheenOf(chosen).gradient.stops[0].color), "#0be8e8e8");
            const edge = edgeOf(chosen);
            compare([edge.border.width, String(edge.border.color), edge.radius], [1, "#17e8e8e8", 20]);
        }

        function test_children_sit_in_the_clipped_body_under_the_hairline() {
            compare(content.parent, bodyOf(chosen));
            verify(sheenOf(chosen).z < content.z);
            compare(chosen.children[chosen.children.length - 1], edgeOf(chosen));
        }

        function test_without_glass_the_standard_surface() {
            verify(!plain.on);
            verify(!shadowOf(plain).visible);
            verify(!sheenOf(plain).visible);
            compare(String(bodyOf(plain).color), "#101010");
            compare(bodyOf(plain).radius, 0);
            const edge = edgeOf(plain);
            compare([edge.border.width, String(edge.border.color)], [1, "#3a3a3b"]);
            compare(UnitTheme.override({ surface: { radius: 6 } }), "ok");
            compare([bodyOf(plain).radius, edgeOf(plain).radius], [6, 6]);
        }

        function test_without_glass_the_handed_standard_look() {
            verify(!handed.on);
            compare([String(bodyOf(handed).color), bodyOf(handed).radius], ["#203040", 7]);
            compare([edgeOf(handed).border.width, String(edgeOf(handed).border.color), edgeOf(handed).radius], [1, "#506070", 7]);
            // The glass takes the standard look's corner unless handed one.
            compare(handed.radius, 7);
        }

        // Each qs.Ui surface built on GlassSurface asks the user's value
        // with its own choice, none: unset keeps its look, `on` turns it to
        // the default glass fill, `off` keeps it solid.
        function test_the_user_glass_reaches_every_surface() {
            const surfaces = [["panel", panel], ["osd", osd], ["dialog", dialog.children[0]]];
            const rows = [["", false], [JSON.stringify({ glass: "on" }), true], [JSON.stringify({ glass: "off" }), false]];
            for (const [input, on] of rows) {
                Theme.appearanceInput = input;
                for (const [name, surface] of surfaces) {
                    compare(surface.on, on, name + " glass=" + input);
                    compare(shadowOf(surface).visible, on, name + " shadow glass=" + input);
                    if (on) compare(String(bodyOf(surface).color), "#cc101010", name + " fill");
                    else verify(String(bodyOf(surface).color) !== "#cc101010", name + " stays solid");
                }
            }
        }

        // Under glass on everywhere, a surface over its window's own
        // content keeps its standard look: one inside another GlassSurface,
        // and every one in a window whose colour is not transparent. Its
        // `on` still answers the user's and its own choice.
        function test_glass_is_drawn_only_as_its_window_backdrop() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            compare([outer.on, outer.backdrop, outer.drawn], [true, true, true]);
            compare([inner.on, inner.backdrop, inner.drawn], [true, false, false]);
            verify(!shadowOf(inner).visible);
            compare(String(bodyOf(inner).color), "#101010");
            root.Window.window.color = "#ffffff";
            compare([chosen.on, chosen.backdrop, chosen.drawn], [true, false, false]);
            compare(String(bodyOf(chosen).color), "#101010");
            root.Window.window.color = "transparent";
            verify(chosen.drawn);
            compare(String(bodyOf(chosen).color), "#33445566");
        }

        function test_the_default_fill_and_elevation() {
            compare(String(bodyOf(unnamed).color), "#cc101010");
            compare([shadowOf(unnamed).blur, String(shadowOf(unnamed).color)], [90, "#8c000000"]);
        }

        // expected-log: GlassSurface: no elevation named "flat" -- the test names an unknown elevation on purpose
        function test_an_unknown_elevation_draws_wide() {
            unnamed.elevation = "flat";
            compare(shadowOf(unnamed).blur, 90);
        }

        function test_glass_on_everywhere_overrides_the_surface_choice() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            verify(plain.on);
            verify(shadowOf(plain).visible);
            compare(String(bodyOf(plain).color), "#33445566");
            compare(bodyOf(plain).radius, 20);
        }

        function test_glass_off_everywhere_overrides_the_surface_choice() {
            Theme.appearanceInput = JSON.stringify({ glass: "off" });
            verify(!chosen.on);
            verify(!shadowOf(chosen).visible);
            verify(!sheenOf(chosen).visible);
            compare(String(bodyOf(chosen).color), "#101010");
            Theme.appearanceInput = "";
            verify(chosen.on);
        }

        function test_light_mode_takes_the_light_glass() {
            compare(UnitTheme.override({ scheme: { mode: "light" } }), "ok");
            compare(String(edgeOf(chosen).border.color), "#1a2a2a2a");
            compare(String(shadowOf(chosen).color), "#29000000");
        }

        function test_follow_takes_the_item_geometry() {
            compare([follower.x, follower.y, follower.width, follower.height], [30, 40, 120, 60]);
            compare([follower.opacity, follower.scale, follower.transformOrigin], [0.5, 0.8, Item.TopLeft]);
            target.width = 140;
            compare(follower.width, 140);
            target.width = 120;
        }

        // A pill radius larger than a side rounds the shadow to the side.
        function test_a_pill_radius_rounds_the_shadow_to_its_side() {
            chosen.radius = 4096;
            compare(shadowOf(chosen).radius, 50);
            chosen.radius = 20;
        }
    }
}
