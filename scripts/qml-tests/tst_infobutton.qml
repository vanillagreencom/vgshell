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
    SignalSpy { id: changes; target: toggle; signalName: "apply" }
    SignalSpy { id: pages; target: help; signalName: "infoPageActivated" }
    SignalSpy { id: topPages; target: top; signalName: "infoPageActivated" }

    UnitCase {
        name: "infobutton"
        when: windowShown

        function descendants(item) {
            const out = [item];
            for (let i = 0; i < out.length; i++)
                for (const child of out[i].children || []) out.push(child);
            return out;
        }
        function labelIn(item) { return descendants(item).find(child => child instanceof InfoButton && child.visible && child.info !== ""); }
        function modal(item) { return descendants(item).find(child => child.body !== undefined && child.shown !== undefined); }
        function body(item) {
            const content = createTemporaryObject(modal(item).body, root, { width: 420 });
            verify(content !== null);
            verify(waitForPolish(content));
            return content;
        }
        function init() {
            UnitTheme.reset();
            help.closeInfo();
            const label = labelIn(toggle);
            if (label !== undefined) label.closeInfo();
            const above = labelIn(top);
            if (above !== undefined) above.closeInfo();
            changes.clear(); pages.clear(); topPages.clear();
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
            compare(modal(help).dismissOnOutside, true);
            modal(help).rejected();
            compare(help.infoOpen, false);
            tryCompare(help, "activeFocus", true);
        }
        function test_plain_label_has_no_action() {
            compare(bare.linked, false);
            compare(bare.activeFocusOnTab, false);
            mouseClick(bare);
            compare(bare.infoOpen, false);
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
            const label = labelIn(toggle);
            verify(label !== undefined);
            if (data.key === 0) mouseClick(label);
            else { label.forceActiveFocus(Qt.TabFocusReason); keyClick(data.key); }
            compare(label.infoOpen, true);
            compare(changes.count, 0);
            compare(toggle.value, false);
        }
        function test_paragraphs_and_page_links_keep_their_route() {
            const content = body(help);
            const lines = descendants(content).filter(child => child instanceof LinkText);
            compare(lines.length, 2);
            compare(lines[1].y - lines[0].height - lines[0].y, Theme.space.md);
            help.openInfo();
            lines[1].clicked();
            compare(help.infoOpen, false);
            compare(pages.count, 1);
            compare(pages.signalArguments[0], ["acme.test", "Setup"]);
        }
        function test_above_label_forwards_the_page_route() {
            const label = labelIn(top);
            label.openInfo();
            const link = descendants(body(label)).find(child => child instanceof LinkText && child.linked);
            verify(link !== undefined);
            link.clicked();
            compare(label.infoOpen, false);
            compare(topPages.count, 1);
            compare(topPages.signalArguments[0], ["acme.test", "Details"]);
        }
        function test_removing_help_closes_it() {
            const original = help.info;
            help.openInfo();
            help.info = "";
            compare(help.infoOpen, false);
            compare(help.linked, false);
            help.info = original;
        }
    }
}
