import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// The space above a Settings section heading, read off the drawn page: from
// the lowest row of ink above the heading to its capitals' top row is
// `stack.heading` on the System monitor, Capture and Displays pages, built
// from their shipped manifests, whatever row ends the section above: a
// switch, a select, a segmented control, a slider or a help line, one
// with descenders or, planted, one without, and after a status hint with
// a link, whose glyphs end the ink at rest, since its underline draws on
// hover alone, and exactly under a row action's text or danger mark, not
// its box. The settings of no group draw no
// heading: they follow the
// Enabled switch at the space rows of one list leave. A
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
        function setEnabled() { return "ok"; }
        function installRequirements() { return "ok"; }
        function openTui() { return "ok"; }
        function act() { return "ok"; }
        function refreshChoices() {}
        function openLink() {}
        function openSurface() {}
        function openPlugin() { return "ok"; }
        function leave(next) { next(); }
        function replyOf() { return ""; }
        function tuiKey(name) { return "tui:" + name; }
        function headReplies() { return []; }
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

    // Two switch rows of one list, the second with an info mark, as the
    // Enabled row and Notifications' VGlass row draw: the space rows of a
    // list leave between them.
    Column {
        id: listRows
        x: 0
        y: 0
        width: 400
        spacing: Theme.stack.row
        visible: false
        Field { label: "Enabled"; inline: true; width: parent.width; Switch { size: "sm"; checked: true } }
        Field { label: "VGlass"; info: "Glass for every surface."; inline: true; width: parent.width; Switch { size: "sm" } }
    }

    // A row with a help line, then another row of the list: the group
    // space a hinted row leaves before the next (Theme.subTextRoom).
    Column {
        id: hintedRows
        x: 0
        y: 0
        width: 400
        spacing: Theme.stack.row
        visible: false
        Field { label: "Alpha"; inline: true; hint: "Alpha is ready to use"; width: parent.width; Switch { size: "sm"; checked: true } }
        Field { label: "Beta"; inline: true; width: parent.width; Switch { size: "sm" } }
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

    // A status section as a plugin page draws it: a GroupList of loaded
    // fields, the last ending in a hint of one line or of two, then the
    // next section.
    Component {
        id: statusThenSection
        Column {
            id: statusPage
            property string hint: ""
            property string hintLink: ""
            width: 400
            spacing: 0
            Section {
                title: "Status"
                GroupList {
                    Loader {
                        width: parent.width
                        sourceComponent: Field { label: "Setup"; inline: true; hint: statusPage.hint; hintLink: statusPage.hintLink; Label { role: "item"; text: "Ready" } }
                    }
                }
            }
            Section {
                title: "Setup"
                Field { label: "One"; inline: true; width: parent.width; Label { role: "item"; text: "Ready" } }
            }
        }
    }

    // A section ending in a row action, as a list setting's Add row and
    // Jarvis's key rows draw, then the next section. `holder` "flow" sets
    // it in a Flow, as a plugin page's More setup row does; "boxed" wraps
    // it in a plain Item, whose ink the spacing reads as its box.
    Component {
        id: actionThenSection
        Column {
            id: actionPage
            property string tone: "accent"
            property string label: "Add"
            // "plain", "flow", as a plugin page's More setup row holds its
            // actions, or "boxed".
            property string holder: "plain"
            width: 400
            spacing: 0
            Section {
                title: "Sources"
                Field {
                    label: "None yet"
                    inline: true
                    width: parent.width
                    RowAction { visible: actionPage.holder === "plain"; text: actionPage.label; tone: actionPage.tone }
                    Flow {
                        visible: actionPage.holder === "flow"
                        width: 200
                        spacing: Theme.rowAction.gap
                        Loader { sourceComponent: RowAction { text: actionPage.label; tone: actionPage.tone } }
                    }
                    Item {
                        visible: actionPage.holder === "boxed"
                        implicitWidth: boxedAction.implicitWidth
                        implicitHeight: boxedAction.implicitHeight
                        RowAction { id: boxedAction; text: actionPage.label; tone: actionPage.tone }
                    }
                }
            }
            Section {
                title: "Text"
                Field { label: "One"; inline: true; width: parent.width; Label { role: "item"; text: "Ready" } }
            }
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
                binds: [], requirements: [], errors: [], fieldRows: PluginLogic.validateManifest(m, "").manifest.fieldRows
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

        // The first and last rows of ink inside ITEM's box.
        function inkRows(img, item) {
            const at = item.mapToItem(root, 0, 0);
            const left = Math.floor(at.x);
            const right = Math.ceil(at.x + item.width);
            let top = Math.floor(at.y);
            let bottom = Math.ceil(at.y + item.height) - 1;
            while (top <= bottom && !rowInked(img, top, left, right)) top++;
            while (bottom >= top && !rowInked(img, bottom, left, right)) bottom--;
            verify(top <= bottom, "the row draws");
            return [top, bottom];
        }

        // The blank rows between the ink of two rows: the lowest of UPPER
        // and the highest of LOWER.
        function gapBetween(img, upper, lower) {
            return inkRows(img, lower)[0] - inkRows(img, upper)[1] - 1;
        }

        // Settings of no group follow the Enabled switch as rows of its
        // list do, `stack.row` apart. Drawn as a section of no title,
        // VGlass sat 66 blank rows under the Enabled switch at the default
        // theme, against 24 between two rows of a list (10 under the
        // switch's ink in its row box, `stack.row` 4, 10 above the next
        // row's ink): the section's padding filled `stack.heading`, 32,
        // from the switch's ink (10, `stack.page` 16, padding 6), then the
        // untitled heading kept its empty eyebrow line, 16, and
        // `sectionHeader.paddingBottom`, 8, and VGlass's row box 10 above
        // its ink: 32 + 16 + 8 + 10 = 66, read by this test under
        // scripts/qml-unit.sh on e041ebaa9.
        function test_ungrouped_settings_follow_the_enabled_row() {
            listRows.visible = true;
            verify(waitForRendering(listRows));
            const list = gapBetween(grabImage(root), listRows.children[0], listRows.children[1]);
            listRows.visible = false;
            // Set after creation, as a JS object, the row keeps its
            // schema's key order; a creation property goes through a
            // QVariantMap, whose keys are sorted.
            const page = createTemporaryObject(pageComponent, root);
            verify(page !== null);
            page.row = rowOf("vgs.notifications");
            const fields = descendants(page);
            const enabled = fields.find(item => item instanceof Field && item.label === "Enabled");
            const glass = fields.find(item => item instanceof SettingField && item.key === "glass");
            verify(enabled !== undefined && glass !== undefined, "the page draws Enabled and VGlass");
            tryVerify(() => glass.height > 0, 2000);
            verify(waitForRendering(page));
            const gap = gapBetween(grabImage(root), enabled, glass);
            verify(Math.abs(gap - list) <= root.tolerance, "VGlass sits " + gap + " px under the Enabled switch, not " + list + " as rows of a list");
        }

        // A field's stored key list whose line ends in a hint leaves the
        // group space before the next field, as a hinted row of a list
        // does: the line, its field's lines and the field each take the
        // room under their last sub-text (StatusLine.subText,
        // ChoiceField.subText).
        function test_a_hinted_key_line_keeps_the_group_space() {
            hintedRows.visible = true;
            verify(waitForRendering(hintedRows));
            const list = gapBetween(grabImage(root), hintedRows.children[0], hintedRows.children[1]);
            hintedRows.visible = false;
            const schema = { alpha: { type: "boolean", label: "Alpha" }, beta: { type: "boolean", label: "Beta" } };
            const status = { alphaKeys: { type: "presenceList", label: "Alpha keys", setting: "alpha", hint: "Alpha is ready to use" } };
            const row = rowOf("vgs.notifications");
            Object.assign(row, { schema: schema, settings: { alpha: true, beta: false }, status: PluginLogic.statusRows({ status: status, secrets: { service: "acme-unit", label: "Key" } }, { alphaKeys: [] }),
                fieldRows: PluginLogic.fieldRows(schema, status) });
            const page = createTemporaryObject(pageComponent, root);
            verify(page !== null);
            page.row = row;
            const own = () => descendants(page).find(item => item instanceof StatusLine && item.visible && item.hint === "Alpha is ready to use");
            const beta = () => descendants(page).find(item => item instanceof SettingField && item.key === "beta");
            tryVerify(() => own() !== undefined && beta() !== undefined && beta().height > 0, 2000, "the page draws Alpha's key line and Beta");
            verify(waitForRendering(page));
            const gap = gapBetween(grabImage(root), own(), beta());
            verify(Math.abs(gap - list) <= root.tolerance, "Beta sits " + gap + " px under Alpha's hinted key line, not " + list + " as under a hinted row of a list");
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

        function test_heading_space_after_a_status_hint_data() {
            return [
                { tag: "one line", hint: "Setup copies defaults.", lines: 1 },
                { tag: "two lines", hint: "Setup copies defaults and downloads the speech model the dictation needs.", lines: 2 }
            ];
        }

        function test_heading_space_after_a_status_hint(data) {
            const page = createTemporaryObject(statusThenSection, root, { hint: data.hint });
            verify(page !== null);
            tryVerify(() => headings(page).length === 2, 2000, "the page heads two groups");
            const hints = descendants(page).filter(child => child instanceof LinkText && child.text === data.hint);
            compare(hints.length, 1);
            compare(hints[0].lineCount, data.lines);
            verify(waitForRendering(page));
            const gap = gapAbove(grabImage(root), headings(page)[1]);
            verify(Math.abs(gap - Theme.stack.heading) <= root.tolerance, "the heading sits " + gap + " px under the hint, not " + Theme.stack.heading);
        }

        // At 40 px a link's underline room reaches 13 px under the glyphs
        // of a last line with no descender, past the reading's tolerance:
        // with LinkText.inkBelow() holding that room, "one line" and "last
        // of two" read 45 blank rows, not 32, under scripts/qml-unit.sh on
        // 2026-10-19. The underline draws on hover alone, so the heading
        // stands under the glyphs whichever line holds the link.
        function test_heading_space_after_an_underlined_link_data() {
            return [
                { tag: "one line", hint: "The manual", link: "manual", lines: 1 },
                { tag: "last of two", hint: "The manual, a manual", link: "manual", lines: 2 },
                { tag: "first of two", hint: "The manual, then the hint", link: "manual", lines: 2 }
            ];
        }

        function test_heading_space_after_an_underlined_link(data) {
            compare(UnitTheme.override({ text: { hint: { size: 40 } } }), "ok");
            const page = createTemporaryObject(statusThenSection, root, { hint: data.hint, hintLink: data.link });
            verify(page !== null);
            tryVerify(() => headings(page).length === 2, 2000, "the page heads two groups");
            const hints = descendants(page).filter(child => child instanceof LinkText && child.text === data.hint);
            compare(hints.length, 1);
            verify(hints[0].linked);
            compare(hints[0].lineCount, data.lines);
            verify(waitForRendering(page));
            const gap = gapAbove(grabImage(root), headings(page)[1]);
            verify(Math.abs(gap - Theme.stack.heading) <= root.tolerance, "the heading sits " + gap + " px under the link, not " + Theme.stack.heading);
        }

        // The space under a row action is read from its drawn ink, so it
        // holds exactly, not within the glyph tolerance. With the action
        // read as its box, as before RowAction.inkBelow(), or a Flow read
        // as its box, as before Theme.inkBelow read a Flow, the heading sat
        // 33 blank rows under its ink; "boxed" is that
        // control and must not read `stack.heading`.
        function test_heading_space_after_a_row_action_data() {
            return [
                { tag: "accent", tone: "accent", holder: "plain" },
                { tag: "danger", tone: "danger", holder: "plain" },
                { tag: "in a flow", tone: "accent", holder: "flow" },
                { tag: "boxed", tone: "accent", holder: "boxed" }
            ];
        }

        function test_heading_space_after_a_row_action(data) {
            const page = createTemporaryObject(actionThenSection, root, { tone: data.tone, holder: data.holder });
            verify(page !== null);
            tryVerify(() => headings(page).length === 2, 2000, "the page heads two groups");
            verify(waitForRendering(page));
            const gap = gapAbove(grabImage(root), headings(page)[1]);
            if (data.holder === "boxed") verify(gap !== Theme.stack.heading, "the reading tells an action's box from its ink: " + gap);
            else compare(gap, Theme.stack.heading, "the heading sits " + gap + " px under the action, not " + Theme.stack.heading);
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
