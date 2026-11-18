import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit

// GlassSurface: a surface names its Glass page row and the one deciding
// place (Theme.glassFor) answers whether glass is on. With glass on it
// draws one pass, the body's tint, the rim and the edge light, in the
// material of its style (Theme.glass on a styled row, Theme.themeGlass on
// any other) and no standard border; over its window's own content, or in
// a window that is not transparent, the body made opaque and lifted; with
// glass off its standard look and no pass. Clear's faint body draws only in
// a material window while layer glass is ready. Expected values come from
// Glass.js's defaults under the shipped theme, never read from the
// component: the dark body #101010 at 0.8, 204 = 0xcc, its themed form the
// theme's raised #101010 at 0.8, lifted by 0.05 to 16 + 239 * 0.05 =
// 27.95, #1c1c1c; the light body #f2f2f2 at 0.85, 0xd9; Clear's black at
// 0.0784, 20 = 0x14, lifted by 0.05 to 12.75, #0d0d0d; the rim 1.25 px.
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

    // The launcher's row, styled, and a menu's, themed.
    GlassSurface {
        id: styled
        x: 10; y: 10; width: 200; height: 100
        surface: "launcher"
        radius: 20
        Item { id: content; anchors.fill: parent }
    }
    GlassSurface {
        id: themed
        x: 10; y: 150; width: 200; height: 100
        surface: "menus"
        radius: 20
    }
    GlassSurface {
        id: follower
        surface: "launcher"
        follow: target
    }
    GlassSurface {
        id: handed
        x: 220; y: 10; width: 100; height: 60
        surface: "dialogs"
        standard: ({ background: "#203040", border: "#506070", radius: 7 })
    }
    GlassSurface {
        id: control
        x: 220; y: 80; width: 60; height: 30
        surface: "controls"
    }
    GlassSurface {
        id: tooltip
        x: 290; y: 80; width: 60; height: 30
        surface: "tooltips"
    }
    GlassSurface {
        id: small
        x: 300; y: 150; width: 40; height: 4
        surface: "launcher"
    }
    GlassSurface {
        id: padded
        x: 300; y: 200; width: 80; height: 40
        surface: "launcher"
        padding: 10
    }
    GlassSurface {
        id: outer
        x: 330; y: 10; width: 60; height: 60
        surface: "launcher"
        GlassSurface { id: inner; anchors.fill: parent; surface: "launcher" }
    }

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
        GlassSurface { id: card; x: 10; y: 10; width: 300; height: 180; surface: "launcher" }
        GlassSurface { id: flyout; x: 100; y: 50; width: 120; height: 80; surface: "launcher" }
    }

    // Two glass cards side by side.
    Item {
        x: 0; y: 1150; width: 400; height: 200
        GlassSurface { id: leftCard; x: 0; y: 0; width: 180; height: 100; surface: "launcher" }
        GlassSurface { id: rightCard; x: 200; y: 0; width: 180; height: 100; surface: "launcher" }
    }

    // A dialog over content and a scrim shown only while it asks.
    Item {
        x: 0; y: 1400; width: 400; height: 200
        Rectangle { anchors.fill: parent; color: "#808080" }
        Scrim { id: askingScrim; visible: false }
        Dialog { id: askingDialog; anchors.centerIn: parent; width: 200; title: "Asking" }
    }

    // A window that marks itself material, as LayerHost's and SummonLayer's
    // do for a glass-material plugin.
    QtObject {
        id: materialHost
        property bool glassMaterial: true
        property var screen: ({ width: root.width, height: root.height })
    }

    UnitCase {
        name: "glasssurface"
        when: windowShown

        function init() {
            root.Window.window.color = "transparent";
            UnitTheme.reset();
            Theme.appearanceInput = "";
            Theme.layerGlassInput = false;
            QsWindow.window = null;
            askingScrim.visible = false;
            askingScrim.opacity = 1;
        }
        function cleanup() { QsWindow.window = null; }

        function bodyOf(glass) { return glass.children[0]; }
        function edgeOf(glass) { return glass.children[1]; }
        function holderOf(glass) { return glass.children[2]; }
        function passOf(glass) { return holderOf(glass).item; }
        function glassIn(values) { Theme.appearanceInput = JSON.stringify(values); }

        // Each row: [name, Appearance values, surface, on, drawn].
        function test_the_deciding_place_turns_glass_on_per_row_data() {
            return [
                { tag: "a default-on row", values: {}, surface: styled, on: true, drawn: true },
                { tag: "a default-off row", values: {}, surface: themed, on: false, drawn: false },
                { tag: "a row saved on", values: { glassSurfaces: { menus: "on" } }, surface: themed, on: true, drawn: true },
                { tag: "a row saved off", values: { glassSurfaces: { launcher: "off" } }, surface: styled, on: false, drawn: false },
                { tag: "the main switch off", values: { glassEnabled: false }, surface: styled, on: false, drawn: false },
                { tag: "a control follows its card", values: { glassSurfaces: { menus: "on" } }, surface: control, on: false, drawn: false },
                { tag: "a tooltip draws its glass solid", values: { glassSurfaces: { tooltips: "on" } }, surface: tooltip, on: true, drawn: false }
            ];
        }
        function test_the_deciding_place_turns_glass_on_per_row(data) {
            glassIn(data.values);
            compare([data.surface.on, data.surface.drawn, data.surface.solid], [data.on, data.drawn, data.on && !data.drawn]);
        }

        function test_drawn_glass_draws_one_pass_and_no_standard_border() {
            verify(styled.drawn);
            compare(String(bodyOf(styled).color), "#00000000", "the pass draws the body");
            verify(!edgeOf(styled).visible, "no standard border");
            verify(passOf(styled) !== null, "the pass is built");
            compare(String(passOf(styled).uTint), "#cc101010", "the dark body");
            compare(passOf(styled).uRim, 1.25, "the rim");
            compare(styled.corner, 20);
            verify(holderOf(styled).z < content.z, "the pass draws under the content");
        }

        function test_the_pass_paints_the_body_data() {
            return [{ tag: "launcher", surface: "launcher" }, { tag: "notifications", surface: "notifications" }];
        }

        function test_the_pass_paints_the_body(data) {
            glassIn({ glassStyle: "dark" });
            styled.surface = data.surface;
            styled.edgeShown = false;
            try {
                verify(styled.drawn);
                verify(renderedFrame(styled));
                const image = grabImage(styled);
                // Sample the plain body to the right of the overlapping
                // follower. Dark is #101010 at 0.8 alpha (Glass.js), so
                // it reads 16 with alpha or about 13 over black.
                const x = Math.floor(0.85 * image.width), y = Math.floor(image.height / 2);
                for (const channel of [image.red(x, y), image.green(x, y), image.blue(x, y)])
                    fuzzyCompare(channel, 16, 4, "the pass paints the dark body");
            } finally {
                styled.surface = "launcher";
                styled.edgeShown = true;
            }
        }

        // A styled row takes the page's style; any other the theme's mode
        // and its raised hue. Each row: [values, surface, tint].
        function test_the_body_follows_the_style_on_a_styled_row_data() {
            return [
                { tag: "Auto in a dark theme", values: {}, surface: styled, tint: "#cc101010" },
                { tag: "Light", values: { glassStyle: "light" }, surface: styled, tint: "#d9f2f2f2" },
                { tag: "Dark", values: { glassStyle: "dark" }, surface: styled, tint: "#cc101010" },
                { tag: "Light leaves a themed row", values: { glassStyle: "light", glassSurfaces: { menus: "on" } }, surface: themed, tint: "#cc101010" }
            ];
        }
        function test_the_body_follows_the_style_on_a_styled_row(data) {
            glassIn(data.values);
            compare(String(passOf(data.surface).uTint), data.tint);
        }

        // Clear's faint body draws only in a material window while layer
        // glass is ready; elsewhere it draws its opaque reading ground.
        function test_clear_draws_only_over_ready_layer_glass_in_a_material_window() {
            glassIn({ glassStyle: "clear" });
            compare([styled.on, styled.drawn, String(passOf(styled).uTint)], [true, false, "#0d0d0d"], "no material window, no layer glass");
            QsWindow.window = materialHost;
            compare(styled.drawn, false, "a material window without layer glass");
            Theme.layerGlassInput = true;
            compare([styled.drawn, String(passOf(styled).uTint)], [true, "#14000000"], "a material window over ready layer glass");
            QsWindow.window = null;
            compare(styled.drawn, false, "ready layer glass outside a material window");
        }

        function test_without_glass_the_standard_surface() {
            glassIn({ glassEnabled: false });
            compare(holderOf(styled).active, false, "no pass is built");
            verify(edgeOf(handed).visible);
            compare([String(bodyOf(handed).color), String(edgeOf(handed).border.color), bodyOf(handed).radius], ["#203040", "#506070", 7]);
            verify(Qt.colorEqual(bodyOf(themed).color, Theme.surface.level.raised.background));
            compare(bodyOf(themed).radius, Theme.surface.radius);
        }

        function test_glass_over_its_window_draws_solid() {
            compare([outer.drawn, inner.drawn, inner.solid], [true, false, true]);
            compare(String(passOf(inner).uTint), "#1c1c1c", "the body made opaque and lifted");
            root.Window.window.color = "#ffffff";
            compare([styled.on, styled.drawn], [true, false]);
            compare(String(passOf(styled).uTint), "#1c1c1c");
            compare(styled.hintGround, styled.effectiveFill, "a solid surface publishes its fill");
            root.Window.window.color = "transparent";
            verify(styled.drawn);
            compare(String(styled.hintGround), "#1c1c1c", "drawn glass publishes the body made opaque");
        }

        // A sibling painted under a surface, or under one of its ancestors,
        // and overlapping it, keeps its glass from being drawn when it is a
        // visible GlassSurface or a Scrim over content. Each row: [name,
        // surface, drawn].
        function test_glass_is_drawn_only_over_nothing_its_window_draws() {
            glassIn({ glassSurfaces: { flyouts: "on", dialogs: "on" } });
            const rows = [
                ["the page under an inline dialog", inlinePage, true],
                ["an inline dialog over a scrim over its page", inlineDialog.children[0], false],
                ["a modal dialog over its own scrim", modalDialog.children[0], true],
                ["a card after a click-away area", card, true],
                ["a flyout over a glass card", flyout, false],
                ["the left of two cards side by side", leftCard, true],
                ["the right of two cards side by side", rightCard, true],
                ["a dialog over a hidden scrim", askingDialog.children[0], true]
            ];
            for (const [name, surface, drawn] of rows)
                compare([surface.on, surface.drawn], [true, drawn], name);
            compare([inlineScrim.overContent, modalScrim.overContent], [true, false], "a scrim is over content when its parent draws something under it");
            const asking = askingDialog.children[0];
            askingScrim.visible = true;
            verify(!asking.drawn, "a shown scrim counts");
            askingScrim.opacity = 0;
            verify(asking.drawn, "a transparent scrim does not");
        }

        function test_the_rim_fits_the_surface_and_content_starts_inside_it() {
            compare(small.rim, 1, "a quarter of a 4 px side");
            compare(styled.contentInset, 1.25, "inside the rim");
            compare(padded.contentInset, 10, "the padding where it is wider");
            glassIn({ glassEnabled: false });
            compare([styled.rim, styled.contentInset], [0, 0], "no rim without glass");
        }

        // The edge light moves on drawn glass that shows, at every frame or
        // paced, and stands still at motion scale 0, while hidden and on
        // solid glass. `lit` blends it to the accent.
        function test_the_edge_light_runs_only_while_it_shows() {
            verify(styled.lightsRunning);
            compare(passOf(styled).uEdge.w, 1, "the lights show");
            styled.edgeShown = false;
            verify(!styled.lightsRunning);
            compare(passOf(styled).uEdge.w, 0);
            styled.edgeShown = true;
            verify(!inner.lightsRunning, "solid glass shows no light");
            UnitTheme.override({ motion: { scale: 0 } });
            verify(!styled.lightsRunning, "motion off stills the light");
            UnitTheme.reset();
            const before = styled.phase;
            styled.paced = true;
            tryVerify(() => styled.phase !== before, 1000, "a paced light still moves");
            styled.paced = false;

            UnitTheme.override({ motion: { scale: 0 } });
            try {
                styled.edgeShown = false;
                tryCompare(styled, "litShare", 0, 2000);
                const resting = grabImage(styled);
                styled.lit = true;
                tryCompare(styled, "litShare", 1, 2000);
                verify(grabImage(styled).equals(resting), "a lit card at rest keeps the same rim");
                styled.edgeShown = true;
                const lit = grabImage(styled);
                verify(!lit.equals(resting), "the edge lights paint when shown");
                styled.lit = false;
                tryCompare(styled, "litShare", 0, 2000);
                verify(!grabImage(styled).equals(lit), "the shown edge lights take the accent");
            } finally {
                styled.lit = false;
                styled.edgeShown = true;
            }
        }

        function test_follow_takes_the_items_geometry() {
            compare([follower.x, follower.y, follower.width, follower.height, follower.opacity, follower.scale, follower.transformOrigin],
                [target.x, target.y, target.width, target.height, target.opacity, target.scale, target.transformOrigin]);
        }
    }
}
