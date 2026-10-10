import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// GlassSurface: with glass on it draws the shadow, the handed fill and
// radius, the sheen and the hairline, from Theme.glass and the elevation it
// is handed; with glass on over its window's own content, the same fill at
// full opacity, radius and hairline; with glass off it draws the standard
// look it is handed, the raised surface's by default, and none of the
// glass. The surface's own choice decides until the user's `glass`
// Appearance value turns glass on or off everywhere, for the qs.Ui surfaces
// built on it too: a panel's Surface, a LevelOsd and a Dialog. Glass is
// drawn only over nothing its own window draws: a window whose colour is
// transparent, as every VGS layer and popup is, no GlassSurface around it,
// and none or a Scrim over content painted under it; the test window is
// made transparent before each test. The groups below y 300 stand for the
// shell's callers: an inline dialog over its page (clipboard, themes), a
// modal dialog in its own layer, a launcher card with a flyout over it,
// cards side by side, a scrim shown only while a dialog asks, and a menu
// and a dialog of different standard looks over content. `follow` lays it
// under another item. Expected
// values are worked by hand from Glass.js and Tokens.js, never read from
// Theme: the hairline is #e8e8e8 at alpha 0.09,
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

    // A dialog over a scrim over its own page.
    Item {
        x: 0; y: 400; width: 400; height: 200
        Surface { id: inlinePage; anchors.fill: parent }
        Scrim { id: inlineScrim }
        Dialog { id: inlineDialog; anchors.centerIn: parent; width: 200; title: "Inline" }
    }

    // A dialog over a scrim first in its layer, after items that draw
    // nothing: hidden, transparent and of no size.
    Item {
        x: 0; y: 650; width: 400; height: 200
        Rectangle { anchors.fill: parent; visible: false }
        Rectangle { anchors.fill: parent; opacity: 0 }
        Item {}
        Scrim { id: modalScrim }
        Dialog { id: modalDialog; anchors.centerIn: parent; width: 200; title: "Modal" }
    }

    // A glass card after a click-away area, and a glass flyout over it.
    Item {
        x: 0; y: 900; width: 400; height: 200
        MouseArea { anchors.fill: parent }
        GlassSurface { id: card; x: 10; y: 10; width: 300; height: 180; optIn: true }
        GlassSurface { id: flyout; x: 100; y: 50; width: 120; height: 80; optIn: true }
    }

    // Two glass cards side by side.
    Item {
        x: 0; y: 1150; width: 400; height: 200
        GlassSurface { id: leftCard; x: 0; y: 0; width: 180; height: 100; optIn: true }
        GlassSurface { id: rightCard; x: 200; y: 0; width: 180; height: 100; optIn: true }
    }

    // A dialog over content and a scrim shown only while it asks.
    Item {
        x: 0; y: 1400; width: 400; height: 200
        Rectangle { anchors.fill: parent; color: "#808080" }
        Scrim { id: askingScrim; visible: false }
        Dialog { id: askingDialog; anchors.centerIn: parent; width: 200; title: "Asking" }
    }

    // A menu over a glass card, as the launcher's, and a dialog over a
    // scrim over its page, as Settings', handing the same fill and radius
    // and standard looks of other colours and corners.
    Item {
        x: 0; y: 1650; width: 400; height: 200
        GlassSurface { id: menuCard; x: 0; y: 0; width: 180; height: 200; optIn: true }
        GlassSurface {
            id: menuOver
            x: 20; y: 20; width: 120; height: 80
            fill: "#99d0c8b8"
            radius: 14
            standard: ({ background: "#edeadf", border: "#c0b8a8", radius: 0 })
        }
        Item {
            x: 200; y: 0; width: 200; height: 200
            Surface { anchors.fill: parent }
            Scrim {}
            GlassSurface {
                id: dialogOver
                x: 20; y: 20; width: 120; height: 80
                fill: "#99d0c8b8"
                radius: 14
                standard: ({ background: "#ebebe8", border: "#a0a0a0", radius: 6 })
            }
        }
    }

    TestCase {
        name: "glasssurface"
        when: windowShown

        function init() {
            root.Window.window.color = "transparent";
            UnitTheme.reset();
            Theme.appearanceInput = "";
            unnamed.elevation = "wide";
            askingScrim.visible = false;
            askingScrim.opacity = 1;
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
        // content draws its fill at full opacity with no shadow: one inside
        // another GlassSurface, its default #cc101010 as #101010, and every
        // one in a window whose colour is not transparent, #33445566 as
        // #445566. Its `on` still answers the user's and its own choice.
        function test_glass_is_drawn_only_over_a_transparent_window() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            compare([outer.on, outer.drawn], [true, true]);
            compare([inner.on, inner.drawn], [true, false]);
            verify(!shadowOf(inner).visible);
            compare(String(bodyOf(inner).color), "#101010");
            root.Window.window.color = "#ffffff";
            compare([chosen.on, chosen.drawn], [true, false]);
            verify(!shadowOf(chosen).visible);
            compare(String(bodyOf(chosen).color), "#445566");
            root.Window.window.color = "transparent";
            verify(chosen.drawn);
            compare(String(bodyOf(chosen).color), "#33445566");
        }

        // A sibling painted under a surface, or under one of its ancestors,
        // and overlapping it, keeps its glass from being drawn when it is a
        // visible GlassSurface or a Scrim over content. Each row: [name,
        // surface, on, drawn].
        function test_glass_is_drawn_only_over_nothing_its_window_draws() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            const rows = [
                ["the page under an inline dialog", inlinePage, true, true],
                ["an inline dialog over a scrim over its page", inlineDialog.children[0], true, false],
                ["a modal dialog over its own scrim", modalDialog.children[0], true, true],
                ["a card after a click-away area", card, true, true],
                ["a flyout over a glass card", flyout, true, false],
                ["the left of two cards side by side", leftCard, true, true],
                ["the right of two cards side by side", rightCard, true, true],
                ["a dialog over a hidden scrim", askingDialog.children[0], true, true]
            ];
            for (const [name, surface, on, drawn] of rows)
                compare([surface.on, surface.drawn], [on, drawn], name);
            compare([inlineScrim.overContent, modalScrim.overContent], [true, false], "a scrim is over content when its parent draws something under it");
        }

        // A scrim counts only while it is painted: visible, with an opacity
        // above 0.
        function test_a_scrim_counts_only_while_it_is_painted() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            const asking = askingDialog.children[0];
            verify(asking.drawn, "hidden");
            askingScrim.visible = true;
            verify(askingScrim.overContent);
            verify(!asking.drawn, "shown");
            askingScrim.opacity = 0;
            verify(asking.drawn, "transparent");
        }

        // Under glass on everywhere, a surface over its window's own
        // content draws one material whatever standard look it hands: the
        // handed fill at full opacity, #99d0c8b8 as #d0c8b8, at its own
        // radius under the hairline. With glass off the same two draw their
        // own standard looks, which differ from it and from each other, so
        // the comparison tells the glass from either look.
        function test_glass_over_content_draws_one_material_whatever_standard() {
            function look(surface) {
                const edge = edgeOf(surface);
                return [String(bodyOf(surface).color), bodyOf(surface).radius, edge.border.width, String(edge.border.color), edge.radius];
            }
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            for (const [name, surface] of [["menu", menuOver], ["dialog", dialogOver]]) {
                compare([surface.on, surface.drawn], [true, false], name);
                verify(!shadowOf(surface).visible, name + " shadow");
                verify(!sheenOf(surface).visible, name + " sheen");
                compare(look(surface), ["#d0c8b8", 14, 1, "#17e8e8e8", 14], name);
            }
            Theme.appearanceInput = JSON.stringify({ glass: "off" });
            compare(look(menuOver), ["#edeadf", 0, 1, "#c0b8a8", 0], "menu without glass");
            compare(look(dialogOver), ["#ebebe8", 6, 1, "#a0a0a0", 6], "dialog without glass");
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
