import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// The space above a Settings section heading, read off the drawn page: from
// the lowest row of ink above the heading to its capitals' top row is
// `stack.heading` on the System monitor, Capture and Displays pages, built
// from their shipped manifests, whatever row ends the section above: a
// switch, a select, a segmented control, a slider or a help line, one
// with descenders or, planted, one without. A
// section spaced by its box, as before `stack.heading`, is the control the
// reading must refuse.
Item {
    id: root
    width: 520
    height: 1800

    // The layout reads a glyph's ink from the font's tight box; its
    // antialiased edge differs from it by up to a pixel.
    readonly property int tolerance: 1
    readonly property var pages: ["vgs.sysmon", "vgs.capture", "vgs.displays"]

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.color.surface
    }

    Item {
        id: fakePanel
        property var shell: null
        property var plugins: []
        property var capture: null
        function writeKey() { return "ok"; }
        function writeSetting() { return "ok"; }
        function writePlacement() { return "ok"; }
        function toggle() { return "ok"; }
        function refreshChoices() {}
        function openLink() {}
        function openSurface() {}
        function openPlugin() { return "ok"; }
        function leave(next) { next(); }
        function replyOf() { return ""; }
    }

    Component {
        id: pageComponent
        PluginPage {
            width: root.width
            height: root.height
            panel: fakePanel
        }
    }

    // A box-spaced section after a drawn row: the gap the reading must
    // not take for the token.
    Column {
        id: boxSpaced
        x: 0
        y: 0
        width: 400
        spacing: Theme.stack.page
        visible: false
        Field { label: "Shown"; inline: true; width: parent.width; Switch { size: "sm"; checked: true } }
        Section {
            title: "Planted"
            topPadding: Theme.stack.section - Theme.stack.page
            Field { label: "One"; inline: true; width: parent.width; Label { role: "item"; text: "Ready" } }
        }
    }

    // A help line whose letters have no descender: its ink ends at the
    // baseline, not the font's descent.
    Column {
        id: flatHint
        x: 0
        y: 0
        width: 400
        // No spacing, so the section's own padding holds the whole space.
        spacing: 0
        visible: false
        Section {
            title: "Recording"
            Field { label: "Trim"; inline: true; hint: "Removes the first tenth"; width: parent.width; Switch { size: "sm" } }
        }
        Section {
            title: "Text"
            Field { label: "One"; inline: true; width: parent.width; Label { role: "item"; text: "Ready" } }
        }
    }

    TestCase {
        name: "sectionSpacing"
        when: windowShown

        function init() { UnitTheme.reset(); }

        function manifest(id) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/" + id + "/manifest.json"), false);
            request.send();
            return JSON.parse(request.responseText);
        }

        function rowOf(id) {
            const m = manifest(id);
            const settings = {};
            // A bounded number with no default draws its slider at its minimum.
            for (const key of Object.keys(m.schema)) settings[key] = m.schema[key].default !== undefined ? m.schema[key].default : m.schema[key].min;
            return {
                id: id, name: m.name, version: m.version, description: m.description, author: m.author,
                license: "", icon: m.icon, source: "bundled", enabled: true, alwaysOn: false, placed: true,
                builtins: [], kinds: m.kinds, capabilities: m.capabilities, schema: m.schema, settings: settings,
                settingChoices: ({}), status: [], secretLabel: "", tuis: [], opens: "", paneHolder: "",
                binds: [], requirements: [], errors: []
            };
        }

        function descendants(item) {
            let out = [];
            for (const child of item.children) out = out.concat([child], descendants(child));
            return out;
        }

        // The shown headings under `item`, as their eyebrow labels.
        function headings(item) {
            return descendants(item).filter(child => child instanceof SectionHeader && child.visible && child.text !== "")
                .map(header => header.children[0].children[0]);
        }

        function inked(img, x, y) {
            const bg = Qt.color(Theme.color.surface);
            return Math.abs(img.red(x, y) - Math.round(bg.r * 255)) > 8 || Math.abs(img.green(x, y) - Math.round(bg.g * 255)) > 8
                || Math.abs(img.blue(x, y) - Math.round(bg.b * 255)) > 8;
        }

        function rowInked(img, y, left, right) {
            for (let x = Math.max(0, left); x < Math.min(img.width, right); x++) if (inked(img, x, y)) return true;
            return false;
        }

        // The blank rows between the ink above `label` and its first row of
        // ink, -1 when nothing above it draws.
        function gapAbove(img, label) {
            const at = label.mapToItem(root, 0, 0);
            let top = Math.floor(at.y);
            while (top < at.y + label.height && !rowInked(img, top, Math.floor(at.x), Math.ceil(at.x + label.width))) top++;
            verify(top < at.y + label.height, "\"" + label.text + "\" draws");
            for (let y = top - 1; y >= 0; y--) if (rowInked(img, y, 0, img.width)) return top - y - 1;
            return -1;
        }

        function test_heading_space_on_plugin_pages_data() {
            return root.pages.map(id => ({ tag: id, id: id }));
        }

        function test_heading_space_on_plugin_pages(data) {
            const page = createTemporaryObject(pageComponent, root, { row: rowOf(data.id) });
            verify(page !== null);
            tryVerify(() => headings(page).length >= 2, 2000, "the page heads two groups or more");
            verify(waitForRendering(page));
            const img = grabImage(root);
            const shown = headings(page);
            for (const label of shown) {
                const gap = gapAbove(img, label);
                verify(gap >= 0, "something draws above \"" + label.text + "\"");
                verify(Math.abs(gap - Theme.stack.heading) <= root.tolerance,
                    data.id + ": \"" + label.text + "\" sits " + gap + " px under the ink above, not " + Theme.stack.heading);
            }
        }

        function test_the_token_moves_the_space() {
            compare(UnitTheme.override({ stack: { heading: 44 } }), "ok");
            const page = createTemporaryObject(pageComponent, root, { row: rowOf("vgs.sysmon") });
            tryVerify(() => headings(page).length >= 2, 2000);
            verify(waitForRendering(page));
            const img = grabImage(root);
            for (const label of headings(page)) verify(Math.abs(gapAbove(img, label) - 44) <= root.tolerance, "\"" + label.text + "\" follows the token");
        }

        // At 40 px the font's descent lies 8 px or more under the baseline,
        // past the reading's tolerance.
        function test_a_help_line_without_descenders() {
            compare(UnitTheme.override({ text: { hint: { size: 40 } } }), "ok");
            flatHint.visible = true;
            verify(waitForRendering(flatHint));
            const img = grabImage(root);
            const gap = gapAbove(img, headings(flatHint)[1]);
            flatHint.visible = false;
            verify(Math.abs(gap - Theme.stack.heading) <= root.tolerance, "the heading sits " + gap + " px under the help line, not " + Theme.stack.heading);
        }

        // The control: a section spaced by its box under a switch row.
        function test_box_spacing_is_refused() {
            boxSpaced.visible = true;
            verify(waitForRendering(boxSpaced));
            const img = grabImage(root);
            const planted = headings(boxSpaced);
            compare(planted.length, 1);
            const gap = gapAbove(img, planted[0]);
            boxSpaced.visible = false;
            verify(gap >= 0);
            verify(Math.abs(gap - Theme.stack.heading) > root.tolerance, "the reading tells a box-spaced heading from the token: " + gap);
        }
    }
}
