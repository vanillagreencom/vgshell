import QtQuick
import QtTest
import qs.Commons
import qs.Unit
import "../../shell/plugins/vgs.launcher"

// The launcher's pointer flyout, ContextMenu.qml, with glass on: it hands
// the launcher card's fill and no radius, so drawn solid it is that fill
// opaque and lifted, at the glass corner. The test window is opaque, so
// every glass surface in it is solid, as the flyout is over the launcher's
// card (tst_glasssurface.qml holds what makes glass solid). Expected values
// are worked by hand from the launcher's Appearance.js and Glass.js: the
// card fill #151515 lifted by 0.05, 21 + 234 * 0.05 = 32.7, #212121; in
// light mode #efefef lifted by 0.1, 239 + 16 * 0.1 = 240.6, #f1f1f1; the
// glass corner 16. An entry's icon centres on its text's x-height within
// half a device pixel, on a whole device pixel, at 1x and at 2x. The
// search magnifier centres on the header line's x-height the same way,
// with the field empty and with a typed query.
Item {
    id: root
    width: 800
    height: 600

    Launcher {
        id: launcher
        anchors.fill: parent
    }

    FontMetrics { id: headerMetrics }

    Component {
        id: ledScene
        Window {
            width: 400
            height: 300
            color: "black"
            property alias menu: ledMenu
            property alias metrics: ledMetrics
            ContextMenu {
                id: ledMenu
                look: launcher.look
                motion: launcher.listMotion
            }
            FontMetrics { id: ledMetrics }
        }
    }

    TestCase {
        name: "launcherMenu"
        when: windowShown

        function init() {
            UnitTheme.reset();
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
        }

        function cleanup() {
            Theme.appearanceInput = "";
        }

        // The flyout among the launcher's children, and its glass surface.
        function flyout() {
            for (const child of launcher.children)
                if (typeof child.openAt === "function") return child;
            fail("the launcher holds no flyout");
        }
        function surfaceOf(menu) {
            for (const child of menu.children)
                if (child.glassSurface === true) return child;
            fail("the flyout holds no glass surface");
        }

        // The entries of MENU that draw an icon, each as its icon box and
        // its drawn text.
        function ledEntries(menu) {
            const found = [];
            const walk = item => {
                if (item.hasIcon === true) {
                    const box = item.children.find(child => child.width === menu.look.flyout.iconSize && child.children.length > 0);
                    const text = item.children.find(child => child.text === item.modelData.label && child.visible);
                    found.push({ box: box, text: text });
                }
                for (const child of item.children) walk(child);
            };
            walk(menu);
            return found;
        }

        function test_an_entry_icon_centres_on_its_text_data() {
            return [{ tag: "1x", scale: 1 }, { tag: "2x", scale: 2 }];
        }

        // The x-height centre is read from the drawn text's own baseline and
        // the font's x-height, not from a label's reading of it, in device
        // pixels; the same reading must reject the entry's centre the box
        // stood on before, and the capital centre.
        function test_an_entry_icon_centres_on_its_text(data) {
            const screen = Qt.application.screens[data.scale - 1];
            const scene = ledScene.createObject(null, { screen: screen, x: screen.virtualX + 10, y: screen.virtualY + 10 });
            scene.visible = true;
            const menu = scene.menu;
            menu.items = [{ id: "reveal", label: "Show in folder", glyph: "folder-open" }, { id: "copy", label: "Copy path", glyph: "copy" }];
            menu.openAt(40, 40);
            const surface = surfaceOf(menu);
            tryCompare(surface, "scale", 1);
            const entries = ledEntries(menu);
            const found = [scene.contentItem.Screen.devicePixelRatio, entries.length];
            for (const entry of entries) {
                const box = entry.box, text = entry.text, row = box.parent;
                scene.metrics.font = text.font;
                const ratio = found[0];
                const baseline = text.y + text.baselineOffset;
                const xCentre = baseline - scene.metrics.xHeight / 2;
                const capCentre = baseline - scene.metrics.capitalHeight / 2;
                const off = (top, centre) => Math.abs(top + box.height / 2 - centre) * ratio;
                const top = box.mapToItem(scene.contentItem, 0, 0).y;
                found.push([text.text, off(box.y, xCentre), Math.abs(top * ratio - Math.round(top * ratio)),
                    off((row.height - box.height) / 2, xCentre), off(Math.round((capCentre - box.height / 2) * ratio) / ratio, xCentre)]);
            }
            menu.close();
            scene.destroy();
            compare(found[0], data.scale, "the window draws at its screen's scale");
            compare(found[1], 2, "both entries draw an icon");
            for (const entry of found.slice(2)) {
                verify(entry[1] <= 0.5, entry[0] + ": the icon is " + entry[1] + " device px off the x-height centre");
                verify(entry[2] < 0.01, entry[0] + ": the icon's top is on a whole device pixel");
                // At 1x the entry's centre and its text's x-height centre
                // round to one pixel; at 2x they are a device pixel apart.
                if (data.scale === 2) verify(entry[3] > 0.5, entry[0] + ": control: the entry's centre reads as level");
                verify(entry[4] > 0.5, entry[0] + ": control: the capital centre reads as level");
            }
        }

        // The header row's search field, its drawn line and its magnifier.
        function headerParts() {
            let field = null;
            const walk = item => {
                if (field !== null) return;
                if (item.cursorRectangle !== undefined && item.selectionColor !== undefined) field = item;
                else for (const child of item.children) walk(child);
            };
            walk(launcher);
            verify(field !== null, "the launcher holds its search field");
            const row = field.parent;
            return {
                row: row,
                field: field,
                text: row.children.find(child => child.style === Text.Raised && child.elide === Text.ElideLeft),
                glyph: row.children.find(child => child.stroke !== undefined && child.look !== undefined)
            };
        }

        function test_the_search_glyph_centres_on_the_header_x_height_data() {
            return [{ tag: "empty", query: "" }, { tag: "typed", query: "Shut" }];
        }

        // The x-height centre is read from the header line's own baseline and
        // the font's x-height; the same reading must reject the header row's
        // centre the glyph stood on before.
        function test_the_search_glyph_centres_on_the_header_x_height(data) {
            launcher.filterText = data.query;
            const parts = headerParts();
            const text = parts.text, glyph = parts.glyph;
            verify(text !== undefined && glyph !== undefined, "the header holds its line and its magnifier");
            compare([parts.field.text, text.text === ""], [data.query, data.query !== ""], "the field shows the query and the line clears for it");
            headerMetrics.font = text.font;
            const xCentre = text.y + text.baselineOffset - headerMetrics.xHeight / 2;
            const off = top => Math.abs(top + glyph.height / 2 - xCentre);
            const found = [off(glyph.y), Math.abs(glyph.y - Math.round(glyph.y)), off((parts.row.height - glyph.height) / 2)];
            launcher.filterText = "";
            verify(found[0] <= 0.5, "the magnifier is " + found[0] + " px off the x-height centre");
            verify(found[1] < 0.01, "the magnifier's top is on a whole pixel");
            verify(found[2] > 0.5, "control: the header row's centre reads as level");
        }

        function test_the_flyout_draws_the_card_fill_solid_at_the_glass_corner() {
            const menu = flyout();
            menu.items = [{ id: "open", label: "Open" }, { id: "reveal", label: "Reveal" }, { id: "copy", label: "Copy path" }];
            menu.openAt(100, 100);
            const surface = surfaceOf(menu);
            compare([surface.on, surface.solid], [true, true]);
            const body = surface.children[1];
            // A Column sizes itself on its next polish.
            tryVerify(() => surface.height >= 32, 1000, "the flyout is taller than two glass corners");
            compare([String(body.color), body.radius], ["#212121", 16], "dark");
            compare(UnitTheme.override({ scheme: { mode: "light" } }), "ok");
            compare([String(body.color), body.radius], ["#f1f1f1", 16], "light");
            compare(UnitTheme.override({ radius: { md: 8 } }), "ok");
            compare(body.radius, 16, "a rounded theme leaves the launcher's own look");
            menu.close();
        }
    }
}
