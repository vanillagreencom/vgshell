import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// GlassSurface: with glass on it draws the shadow, the handed fill and
// radius, the sheen and the hairline, from Theme.glass and the elevation it
// is handed, and no shadow at the elevation `none`; with glass on over its window's own content, the same fill
// made opaque and lifted, at the same corner under the hairline; with glass
// off it draws the standard look it is handed, the raised surface's by
// default, and none of the glass. The surface's own choice decides until
// the user's `glass` Appearance value turns glass on or off everywhere, for
// the qs.Ui surfaces built on it too: a panel's Surface, a LevelOsd and a
// Dialog. Glass is drawn only over nothing its own window draws: a window
// whose colour is transparent, as every VGS layer and popup is, no
// GlassSurface around it, and none or a Scrim over content painted under
// it; the test window is made transparent before each test. The groups
// below y 300 stand for the shell's callers: an inline dialog over its page
// (clipboard, themes), a modal dialog in its own layer, a launcher card
// with a flyout over it, cards side by side, a scrim shown only while a
// dialog asks, the launcher's menu beside the Settings window's dialog, and
// a menu alone beside a menu over a glass card. `follow` lays it under
// another item. Expected values are worked by hand from Glass.js and
// Tokens.js, never read from Theme: the glass corner 16; the hairline
// #e8e8e8 at alpha 0.09, round(22.95) = 23 = 0x17; the tight shadow black
// at 0.45, round(114.75) = 115 = 0x73; the wide one at 0.55, round(140.25)
// = 140 = 0x8c; the raised surface neutral(0.075), #101010, under a #3a3a3b
// border; the default fill that surface at 0.8, 204 = 0xcc, and at 0.85 in
// light mode, round(216.75) = 217 = 0xd9; in light mode the hairline
// #2a2a2a at 0.1, round(25.5) = 26 = 0x1a. A solid fill is each channel c
// of the fill as round(c + (255 - c) * lift), opaque, the lift 0.05 and
// 0.1 in light mode: #101010 gives 27.95, #1c1c1c; `solids` holds the rest.
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
        fill: "#33405060"
        radius: 20
        elevation: "tight"
        Item { id: content; anchors.fill: parent }
    }

    GlassSurface {
        id: plain
        x: 10; y: 150; width: 200; height: 100
        fill: "#33405060"
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

    // The launcher's menu over its glass card, handing a fill of its own
    // and neither a radius nor a standard look, and the Settings window's
    // dialog: its page, a scrim and the dialog, which hands Theme.dialog and
    // no fill.
    Item {
        x: 0; y: 1650; width: 400; height: 200
        GlassSurface { id: menuCard; x: 0; y: 0; width: 180; height: 200; optIn: true }
        GlassSurface {
            id: menuOver
            x: 20; y: 20; width: 120; height: 80
            fill: "#c7202430"
        }
        Item {
            x: 200; y: 0; width: 200; height: 200
            Surface { anchors.fill: parent }
            Scrim {}
            GlassSurface {
                id: dialogOver
                x: 20; y: 20; width: 120; height: 80
                standard: Theme.dialog
            }
        }
    }

    // A menu's surface as Menu.qml hands it, over nothing its window draws,
    // and the same over a glass card.
    Item {
        x: 0; y: 1900; width: 400; height: 200
        GlassSurface { id: menuDrawn; x: 0; y: 0; width: 120; height: 80; standard: Theme.menu; elevation: "tight" }
        GlassSurface { id: menuUnder; x: 200; y: 0; width: 180; height: 200; optIn: true }
        GlassSurface { id: menuSolid; x: 220; y: 20; width: 120; height: 80; standard: Theme.menu; elevation: "tight" }
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

        // The solid form of each fixture's own fill: `chosen`, #405060,
        // 73.55, 88.75, 103.95; `menuOver`, #202430, 43.15, 46.95, 58.35
        // and in light mode 54.3, 57.9, 68.7.
        readonly property var solids: ({ chosen: "#4a5968", menu: { dark: "#2b2f3a", light: "#363a45" } })

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
            compare(String(body.color), "#33405060");
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
        // content draws its fill solid with no shadow: one inside another
        // GlassSurface, and every one in a window whose colour is not
        // transparent, at the radius it hands. Its `on` still answers the
        // user's and its own choice.
        function test_glass_is_drawn_only_over_a_transparent_window() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            compare([outer.on, outer.drawn], [true, true]);
            compare([inner.on, inner.drawn], [true, false]);
            verify(!shadowOf(inner).visible);
            compare(String(bodyOf(inner).color), "#1c1c1c");
            root.Window.window.color = "#ffffff";
            compare([chosen.on, chosen.drawn], [true, false]);
            verify(!shadowOf(chosen).visible);
            compare([String(bodyOf(chosen).color), bodyOf(chosen).radius, edgeOf(chosen).radius], [solids.chosen, 20, 20]);
            root.Window.window.color = "transparent";
            verify(chosen.drawn);
            compare([String(bodyOf(chosen).color), bodyOf(chosen).radius], ["#33405060", 20]);
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

        // What a surface draws: [fill, corner, hairline or border width,
        // its colour, its corner, shadow shown, sheen shown].
        function look(surface) {
            const edge = edgeOf(surface);
            return [String(bodyOf(surface).color), bodyOf(surface).radius, edge.border.width, String(edge.border.color), edge.radius, shadowOf(surface).visible, sheenOf(surface).visible];
        }

        // A menu over nothing its window draws and a menu over a glass card
        // draw one corner and one hue: the drawn one the theme's raised
        // surface, translucent under shadow and sheen, the solid one that
        // fill opaque and lifted, both at the menu's corner under the
        // hairline. Each row: [name, theme tokens, drawn fill, solid fill,
        // hairline]. A light theme's raised surface here is #e8e4d8, solid
        // 234.3, 230.7, 219.9; a dark one's #283038, solid 50.75, 58.35,
        // 65.95.
        function test_a_menu_draws_one_corner_and_one_hue_drawn_and_solid() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            const rows = [
                ["the shipped theme", {}, "#cc101010", "#1c1c1c", "#17e8e8e8"],
                ["a dark theme's raised surface", { color: { surfaceRaised: "#283038" } }, "#cc283038", "#333a42", "#17e8e8e8"],
                ["a light theme's raised surface", { scheme: { mode: "light" }, color: { surfaceRaised: "#e8e4d8" } }, "#d9e8e4d8", "#eae7dc", "#1a2a2a2a"]
            ];
            for (const [name, tokens, drawnFill, solidFill, hairline] of rows) {
                compare(UnitTheme.override(tokens), "ok", name);
                compare([menuDrawn.drawn, menuSolid.drawn, menuSolid.solid], [true, false, true], name);
                compare(look(menuDrawn), [drawnFill, 16, 1, hairline, 16, true, true], name + ": drawn");
                compare(look(menuSolid), [solidFill, 16, 1, hairline, 16, false, false], name + ": solid");
            }
            UnitTheme.reset();
            Theme.appearanceInput = JSON.stringify({ glass: "off" });
            for (const menu of [menuDrawn, menuSolid])
                compare(look(menu), ["#101010", 0, 1, "#3a3a3b", 0, false, false], "a menu without glass");
        }

        // Glass rounds a square role and overrides no rounding: with glass
        // on, a menu, an OSD and a dialog whose corner the theme leaves at
        // 0 take 16, a panel keeps the square edge, and a corner the theme
        // (radius.md 8) or the user's Corner radius (24, of which a flyout
        // takes 0.75, 18) sets stands as it does with glass off. Each row:
        // [name, theme tokens, the user's values, menu, OSD, dialog, panel].
        function test_glass_rounds_a_square_role_and_no_other() {
            const rows = [
                ["a square theme, glass on", {}, { glass: "on" }, 16, 16, 16, 0],
                ["a square theme, glass off", {}, { glass: "off" }, 0, 0, 0, 0],
                ["a square theme, glass unset", {}, {}, 0, 0, 0, 0],
                ["a rounded theme, glass on", { radius: { md: 8 } }, { glass: "on" }, 8, 8, 8, 8],
                ["a user's corner radius, glass on", {}, { glass: "on", windowRadius: 24 }, 18, 18, 18, 18],
                ["a user's corner radius, glass off", {}, { glass: "off", windowRadius: 24 }, 18, 18, 18, 18]
            ];
            for (const [name, tokens, user, menu, level, card, flyout] of rows) {
                compare(UnitTheme.override(tokens), "ok", name);
                Theme.appearanceInput = JSON.stringify(user);
                compare([bodyOf(menuDrawn).radius, bodyOf(menuSolid).radius], [menu, menu], name + ": menu, drawn and solid");
                compare([bodyOf(osd).radius, bodyOf(dialog.children[0]).radius, bodyOf(inlineDialog.children[0]).radius], [level, card, card], name + ": OSD, dialog, inline dialog");
                compare([bodyOf(panel).radius, bodyOf(inlinePage).radius], [flyout, flyout], name + ": panel");
            }
        }

        // Under glass on everywhere, the launcher's menu and the Settings
        // dialog each draw their own fill solid at the glass corner, in a
        // transparent window and in one whose colour is the glass fill, as
        // AppWindow.qml's is while window glass is on: the menu the fill it
        // hands, the dialog the theme's raised surface, neither the other's.
        // The menu hands no radius and no standard look, so its corner is
        // the glass corner whatever the theme's. With glass off both draw
        // the standard look. Each row: [window colour, theme tokens, menu
        // fill, dialog fill, hairline].
        function test_glass_over_content_draws_each_surface_its_own_fill() {
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            const light = { scheme: { mode: "light" }, color: { surfaceRaised: "#e8e4d8" } };
            const rows = [
                ["transparent", {}, solids.menu.dark, "#1c1c1c", "#17e8e8e8"],
                ["#cc101010", {}, solids.menu.dark, "#1c1c1c", "#17e8e8e8"],
                ["transparent", light, solids.menu.light, "#eae7dc", "#1a2a2a2a"],
                ["transparent", { radius: { md: 8 } }, solids.menu.dark, "#1c1c1c", "#17e8e8e8"]
            ];
            for (const [colour, tokens, menuFill, dialogFill, hairline] of rows) {
                root.Window.window.color = colour;
                compare(UnitTheme.override(tokens), "ok");
                const row = "window=" + colour + " theme=" + JSON.stringify(tokens);
                const dialogCorner = tokens.radius ? 8 : 16;
                compare([menuOver.drawn, dialogOver.drawn], [false, false], row);
                compare(look(menuOver), [menuFill, 16, 1, hairline, 16, false, false], "menu " + row);
                compare(look(dialogOver), [dialogFill, dialogCorner, 1, hairline, dialogCorner, false, false], "dialog " + row);
            }
            UnitTheme.reset();
            Theme.appearanceInput = JSON.stringify({ glass: "off" });
            // A dialog's border is borderControl, the raised surface halfway
            // to white: (16.125 + 255) / 2 = 135.6, 0x88.
            compare(look(menuOver), ["#101010", 0, 1, "#3a3a3b", 0, false, false], "a menu without glass");
            compare(look(dialogOver), ["#101010", 0, 1, "#888888", 0, false, false], "a dialog without glass");
        }

        function test_the_default_fill_and_elevation() {
            compare(String(bodyOf(unnamed).color), "#cc101010");
            compare([shadowOf(unnamed).blur, String(shadowOf(unnamed).color)], [90, "#8c000000"]);
        }

        // A plate on the wallpaper draws every layer of the glass but the
        // shadow, and names no group of the shadow table.
        function test_the_none_elevation_draws_no_shadow() {
            unnamed.elevation = "none";
            verify(unnamed.drawn);
            verify(!shadowOf(unnamed).visible);
            compare(String(bodyOf(unnamed).color), "#cc101010");
            verify(sheenOf(unnamed).visible);
            compare([edgeOf(unnamed).border.width, String(edgeOf(unnamed).border.color)], [1, "#17e8e8e8"]);
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
            compare(String(bodyOf(plain).color), "#33405060");
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
