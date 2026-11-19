import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// The offscreen modal is an interface stand-in. These cases prove the
// label's independent input, help body and page routing. The nested
// surfaces row proves the real ModalDialog's screen, close and lifetime.
Item {
    id: root
    width: 600
    height: 420

    InfoButton {
        id: help
        title: "Help label"
        info: "One useful condition.\nSee [another page](page:acme.test/Setup)."
        x: 20
        y: 20
    }
    InfoButton { id: bare; title: "Plain label"; x: 20; y: 70 }
    SettingField {
        id: toggle
        x: 20
        y: 130
        width: 520
        key: "switch"
        spec: ({ type: "boolean", label: "Toggle help", info: "A condition for this setting." })
        value: false
    }
    Field {
        id: top
        x: 20
        y: 220
        width: 520
        inline: false
        label: "Above"
        info: "See [another page](page:acme.test/Details)."
        Label { text: "Value" }
    }
    Field {
        id: beside
        x: 20
        y: 300
        width: 520
        inline: true
        label: "Beside"
        info: "See [another page](page:acme.test/Keys)."
        Label { text: "Value" }
    }
    SignalSpy { id: changes; target: toggle; signalName: "apply" }
    SignalSpy { id: pages; target: help; signalName: "infoPageActivated" }
    SignalSpy { id: topPages; target: top; signalName: "infoPageActivated" }
    SignalSpy { id: besidePages; target: beside; signalName: "infoPageActivated" }
    Component {
        id: readerFixture
        Column {
            InfoButton { title: "Current"; info: "A condition."; role: "eyebrow" }
            Label { role: "label"; text: "Old label" }
            Text { text: "Plain text" }
            LinkText { text: "See [Settings](page:acme.test/Settings)." }
            Item { property string text: "Metadata, not drawn words" }
            Item { visible: false; Label { text: "Hidden" } }
        }
    }
    Component {
        id: returnFixture
        Item {
            width: 300
            height: 100
            property alias opener: returnButton
            property alias help: returnedHelp
            Button { id: returnButton; text: "More" }
            InfoButton {
                id: returnedHelp
                y: 50
                title: "Entry help"
                info: "A condition."
                returnFocus: returnButton
            }
        }
    }

    UnitCase {
        name: "infobutton"
        when: windowShown

        function descendants(item) {
            const out = [item];
            for (let i = 0; i < out.length; i++)
                for (const child of out[i].children || []) out.push(child);
            return out;
        }
        function init() {
            UnitTheme.reset();
            help.closeInfo();
            for (const field of [toggle, top, beside]) {
                const label = semanticLabelItems(field).find(child => child.info !== "");
                if (label !== undefined) label.closeInfo();
            }
            changes.clear(); pages.clear(); topPages.clear(); besidePages.clear();
        }

        function test_shared_readers_keep_owners_once_and_refuse_old_labels() {
            const fixture = createTemporaryObject(readerFixture, root);
            verify(fixture !== null);
            const words = displayedTextItems(fixture);
            compare(words.map(item => displayedText(item)), ["Current", "Old label", "Plain text", "See Settings."]);
            const labels = semanticLabelItems(fixture);
            compare(labels.length, 1, "the visible old Label and plain Text are not semantic labels");
            compare(semanticLabelText(fixture), "Current");
            compare(labels[0], words[0]);
            compare(displayedTextRenderer(labels[0]), labels[0].labelItem);
            compare(labels[0].label, "About Current", "the accessible name is not an extra displayed word");
        }

        function test_pointer_and_keyboard_open_help_data() {
            return [{ tag: "pointer", key: 0 }, { tag: "Enter", key: Qt.Key_Enter }, { tag: "Return", key: Qt.Key_Return }, { tag: "Space", key: Qt.Key_Space }];
        }
        function test_pointer_and_keyboard_open_help(data) {
            if (data.key === 0) mouseClick(help);
            else {
                help.forceActiveFocus(Qt.TabFocusReason);
                keyClick(data.key);
            }
            compare(help.infoOpen, true);
            compare(helpDialog(help).dismissOnOutside, true);
            helpDialog(help).rejected();
            compare(help.infoOpen, false);
            tryCompare(help, "activeFocus", true);
        }
        function test_plain_label_has_no_action() {
            compare(bare.linked, false);
            compare(bare.activeFocusOnTab, false);
            mouseClick(bare);
            compare(bare.infoOpen, false);
        }
        function test_close_restores_the_reason_on_an_already_focused_opener_data() {
            return [{ tag: "key", visual: true }, { tag: "pointer", visual: false }];
        }
        function test_close_restores_the_reason_on_an_already_focused_opener(data) {
            const fixture = createTemporaryObject(returnFixture, root);
            verify(fixture !== null);
            const opener = fixture.opener;
            const previous = data.visual ? Qt.MouseFocusReason : Qt.TabFocusReason;
            opener.forceActiveFocus(previous);
            opener.focusReason = previous;
            tryCompare(opener, "activeFocus", true);
            compare(opener.visualFocus, !data.visual);
            fixture.help.openInfo(data.visual);
            fixture.help.closeInfo();
            tryCompare(opener, "activeFocus", true);
            tryCompare(opener, "visualFocus", data.visual);
        }
        function test_hover_has_no_help_copy() {
            mouseMove(help, help.width / 2, help.height / 2);
            verify(!descendants(help).some(child => child.details !== undefined && child.anchorItem !== undefined), "help owns no tooltip");
            compare(help.infoOpen, false);
        }
        function test_help_draws_dots_beneath_its_words() {
            verify(help.linked);
            verify(help.activeFocusOnTab);
            verify(help.underlineAtRest);
            verify(help.dottedUnderline);
            verify(help.underlined.length > 0);
            renderedFrame(root);
            const image = grabImage(root);
            const at = help.mapToItem(root, 0, 0);
            const span = help.underlined[0];
            const y = Math.floor(at.y + help.labelItem.baselineOffset + help.underlineOffset);
            const from = Math.ceil(at.x + span.left);
            const to = Math.floor(at.x + span.right);
            let changes = 0;
            for (let x = from + 1; x < to; x++) {
                if (!Qt.colorEqual(image.pixel(x, y), image.pixel(x - 1, y))) changes++;
            }
            verify(changes >= 6, "the underline has repeated gaps, rather than a solid rule");
        }
        function test_toggle_help_never_changes_the_setting_data() {
            return [{ tag: "pointer", key: 0 }, { tag: "Enter", key: Qt.Key_Enter }];
        }
        function test_toggle_help_never_changes_the_setting(data) {
            const label = semanticLabelItems(toggle).find(child => child.info !== "");
            verify(label !== undefined);
            if (data.key === 0) mouseClick(label);
            else { label.forceActiveFocus(Qt.TabFocusReason); keyClick(data.key); }
            compare(label.infoOpen, true);
            compare(changes.count, 0);
            compare(toggle.value, false);
        }
        function test_paragraphs_and_page_links_keep_their_route() {
            const lines = helpParagraphs(help, root);
            compare(lines.length, 2);
            compare(lines[1].y - lines[0].height - lines[0].y, Theme.space.md);
            help.openInfo();
            lines[1].clicked();
            compare(help.infoOpen, false);
            compare(pages.count, 1);
            compare(Array.from(pages.signalArguments[0]), ["acme.test", "Setup"]);
        }
        function test_fields_forward_the_page_route_data() {
            return [
                { tag: "above", field: top, spy: topPages, tab: "Details" },
                { tag: "inline", field: beside, spy: besidePages, tab: "Keys" }
            ];
        }
        function test_fields_forward_the_page_route(data) {
            const label = semanticLabelItems(data.field).find(child => child.info !== "");
            verify(label !== undefined);
            label.openInfo();
            const link = helpParagraphs(label, root).find(child => child.linked);
            verify(link !== undefined);
            link.clicked();
            compare(label.infoOpen, false);
            compare(data.spy.count, 1);
            compare(Array.from(data.spy.signalArguments[0]), ["acme.test", data.tab]);
        }
        function test_removing_help_closes_it() {
            const original = help.info;
            help.forceActiveFocus(Qt.TabFocusReason);
            help.openInfo();
            help.info = "";
            compare(help.infoOpen, false);
            compare(help.linked, false);
            compare(help.activeFocus, false);
            compare(help.activeFocusOnTab, false);
            help.info = original;
        }
    }
}
