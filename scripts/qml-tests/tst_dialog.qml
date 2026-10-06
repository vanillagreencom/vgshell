import QtQuick
import QtQuick.Window
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// Dialog: the card, the title and the message drawn from the `dialog`
// tokens; the accept action focused first with a ring, or the action
// marked `focused`; Enter and Return
// pressing the focused action or the accept action, Escape rejecting; Tab
// and Shift+Tab, in either form a keymap reports it, cycling the enabled
// actions with the ring and never leaving
// the dialog; a press answering with the action's role; the default
// variant per role and an unknown role read as cancel; actions with no
// cancel action logged, and with one, or no action at all, not; `busy` and a
// disabled action answering nothing and fading; content under the message;
// an initial focus field taking the focus and the typing, its Enter and
// Escape answering and Tab cycling through it; a Select listed in
// `tabItems` taking Tab and Backtab ahead of the field, and skipped while
// hidden; the card taking the press, the hover and the wheel from what lies
// under it, and passing the wheel on while not modal; actions too wide
// for one line wrapping in order, flush right, inside the text's edges and
// clear of a busy spinner; and a theme change reaching the card and the
// roles.
Item {
    id: root
    width: 800
    height: 600

    Button { id: outside; text: "Outside" }
    Dialog {
        id: dialog
        y: 40
        title: "Download wallpapers?"
        message: "Nord ships 12 wallpapers, 42 MB."
        actions: [{ label: "Not now", role: "cancel" }, { label: "Download", role: "accept" }]
        Label { id: extra; role: "code"; text: "vgs-themes/nord.tar.gz" }
        TextField { id: edit; placeholderText: "Filter wallpapers" }
    }
    Dialog {
        id: three
        y: 300
        title: "Remove acme.weather?"
        actions: [{ label: "Keep", role: "cancel" }, { label: "Later", role: "cancel", enabled: false }, { label: "Remove", role: "accept", variant: "danger" }]
    }
    Dialog {
        id: blocked
        y: 420
        title: "Install gum?"
        actions: [{ label: "Not now", role: "cancel" }, { label: "Install", role: "accept", enabled: false }]
    }
    Dialog {
        id: emptyBody
        x: 400
        y: 300
        title: "Download wallpaper?"
        message: "The file is ready."
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Download", role: "accept" }]
    }
    Dialog {
        id: hiddenBody
        x: 400
        y: 420
        title: "Apply theme?"
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Apply", role: "accept" }]
        Label { id: hiddenLabel; role: "body"; text: "Hidden"; visible: false }
    }
    Dialog {
        id: prompt
        x: 400
        y: 40
        title: "Authenticate"
        initialFocus: secret
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Authenticate", role: "accept" }]
        TextField { id: secret; width: parent.width; echoMode: TextInput.Password }
    }
    Dialog {
        id: chooser
        x: 400
        y: 180
        title: "Authenticate"
        initialFocus: chooserSecret
        tabItems: [who, chooserSecret]
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Authenticate", role: "accept" }]
        Select { id: who; width: parent.width; model: ["alice", "root"] }
        TextField { id: chooserSecret; width: parent.width; echoMode: TextInput.Password }
    }
    Dialog {
        id: disclosed
        x: 400
        y: 320
        title: "Needs one command"
        tabItems: [shown.toggle, shown.copyButton]
        actions: [{ label: "Install", role: "accept" }, { label: "Not now", role: "cancel" }]
        CommandDisclosure { id: shown; width: parent.width; command: "vgshell pkg run install acme" }
    }
    SignalSpy { id: disclosedAccepts; target: disclosed; signalName: "accepted" }
    SignalSpy { id: accepts; target: dialog; signalName: "accepted" }
    SignalSpy { id: promptAccepts; target: prompt; signalName: "accepted" }
    SignalSpy { id: promptRejects; target: prompt; signalName: "rejected" }
    SignalSpy { id: rejects; target: dialog; signalName: "rejected" }
    SignalSpy { id: threeAccepts; target: three; signalName: "accepted" }
    SignalSpy { id: threeRejects; target: three; signalName: "rejected" }
    SignalSpy { id: blockedAccepts; target: blocked; signalName: "accepted" }

    TestCase {
        name: "dialog"
        when: windowShown

        function init() {
            UnitTheme.reset();
            dialog.busy = false;
            for (const spy of [accepts, rejects, threeAccepts, threeRejects, blockedAccepts, promptAccepts, promptRejects]) spy.clear();
            secret.text = "";
            secret.enabled = true;
            who.visible = true;
            outside.forceActiveFocus();
        }

        function card(of) { return of.children[0]; }
        function pane(of) { return of.children[1]; }
        function headerColumn(of) { return pane(of).children[2].children[0]; }
        function titleLabel(of) { return headerColumn(of).children[0]; }
        function messageLabel(of) { return headerColumn(of).children[1]; }
        function footer(of) { return pane(of).children[4].children[0]; }
        function headerSlot(of) { return pane(of).children[2]; }
        function footerSlot(of) { return pane(of).children[4]; }
        function spinner(of) { return footer(of).children[0]; }
        function ring(button) { return button.background.children[button.background.children.length - 1]; }

        function test_draws_its_tokens() {
            compare(dialog.width, Theme.dialog.width);
            compare(String(card(dialog).color), String(Qt.color(Theme.dialog.background)));
            compare(String(card(dialog).border.color), String(Qt.color(Theme.dialog.border)));
            compare(card(dialog).radius, Theme.dialog.radius);
            compare(pane(dialog).contentInset, Theme.dialog.padding);
            compare(headerColumn(dialog).spacing, Theme.dialog.gap);
            compare(titleLabel(dialog).role, Theme.dialog.titleRole);
            compare(titleLabel(dialog).text, "Download wallpapers?");
            compare(messageLabel(dialog).role, Theme.dialog.bodyRole);
            compare(dialog.height, pane(dialog).implicitHeight);
            compare(pane(dialog).scrollArea.rightInset, pane(dialog).contentInset);
        }

        function test_accept_action_takes_the_focus_with_a_ring() {
            const [notNow, download] = dialog.buttons();
            dialog.forceActiveFocus();
            compare(download.activeFocus, true);
            // A click focuses its action; the next time the dialog takes
            // the focus, the accept action holds it again.
            mouseClick(notNow);
            compare(notNow.activeFocus, true);
            outside.forceActiveFocus();
            dialog.forceActiveFocus();
            compare(download.activeFocus, true);
            compare(notNow.activeFocus, false);
            compare(download.visualFocus, true);
            compare(ring(download).visible, true);
        }

        function test_enter_and_return_accept_and_escape_rejects() {
            dialog.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(accepts.count, 1);
            keyClick(Qt.Key_Enter);
            compare(accepts.count, 2);
            keyClick(Qt.Key_Escape);
            compare(rejects.count, 1);
            compare(accepts.count, 2);
        }

        function test_enter_presses_the_focused_action() {
            dialog.forceActiveFocus();
            dialog.buttons()[0].forceActiveFocus(Qt.TabFocusReason);
            compare(dialog.buttons()[0].activeFocus, true);
            keyClick(Qt.Key_Return);
            compare(rejects.count, 1);
            compare(accepts.count, 0);
        }

        function test_tab_cycles_the_actions_with_the_ring_and_stays_inside() {
            dialog.forceActiveFocus();
            const [notNow, download] = dialog.buttons();
            keyClick(Qt.Key_Tab);
            compare(edit.activeFocus, true);
            compare(outside.activeFocus, false);
            keyClick(Qt.Key_Tab);
            compare(notNow.activeFocus, true);
            compare(notNow.visualFocus, true);
            compare(ring(notNow).visible, true);
            keyClick(Qt.Key_Tab);
            compare(download.activeFocus, true);
            compare(ring(download).visible, true);
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(notNow.activeFocus, true);
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(edit.activeFocus, true);
            for (let i = 0; i < 5; i++) {
                keyClick(Qt.Key_Tab);
                compare(outside.activeFocus, false, "Tab " + i + " left the dialog");
            }
        }


        // A us keyboard reports Shift+Tab as Backtab with Shift held; a
        // keymap whose Tab key has one level, as wtype's, as Tab with Shift.
        function test_shift_tab_steps_back_in_either_form_data() {
            return [
                { tag: "Backtab with Shift", key: Qt.Key_Backtab },
                { tag: "Tab with Shift", key: Qt.Key_Tab }
            ];
        }

        function test_shift_tab_steps_back_in_either_form(data) {
            dialog.forceActiveFocus();
            const [notNow, download] = dialog.buttons();
            download.forceActiveFocus(Qt.TabFocusReason);
            keyClick(data.key, Qt.ShiftModifier);
            compare(notNow.activeFocus, true);
        }

        function test_an_initial_focus_field_takes_the_focus_and_answers() {
            const [cancel, authenticate] = prompt.buttons();
            prompt.forceActiveFocus();
            compare(secret.activeFocus, true);
            keyClick(Qt.Key_S);
            keyClick(Qt.Key_E);
            compare(secret.text, "se");
            compare(authenticate.activeFocus, false);
            keyClick(Qt.Key_Return);
            compare(promptAccepts.count, 1);
            compare(secret.activeFocus, true);
            keyClick(Qt.Key_Escape);
            compare(promptRejects.count, 1);
            // A click moves the focus to an action; the next showing gives it
            // back to the field.
            mouseClick(cancel);
            compare(cancel.activeFocus, true);
            outside.forceActiveFocus();
            prompt.forceActiveFocus();
            compare(secret.activeFocus, true);
        }

        function test_tab_reaches_a_listed_disclosure_and_return_opens_it() {
            disclosedAccepts.clear();
            shown.expanded = false;
            const [install, notNow] = disclosed.buttons();
            disclosed.forceActiveFocus();
            compare(install.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(notNow.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(shown.toggle.activeFocus, true, "Tab wraps to Show command");
            keyClick(Qt.Key_Tab);
            compare(install.activeFocus, true, "a closed disclosure's hidden Copy takes no Tab");
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(shown.toggle.activeFocus, true);
            keyClick(Qt.Key_Return);
            compare(shown.expanded, true, "Return presses the focused toggle");
            compare(disclosedAccepts.count, 0, "Return on the toggle does not accept");
            keyClick(Qt.Key_Tab);
            compare(shown.copyButton.activeFocus, true, "the open disclosure's Copy takes Tab");
            keyClick(Qt.Key_Tab);
            compare(install.activeFocus, true);
            keyClick(Qt.Key_Return);
            compare(disclosedAccepts.count, 1, "Return on the accept action still accepts");
        }

        function test_tab_cycles_through_the_initial_focus_field() {
            const [cancel, authenticate] = prompt.buttons();
            prompt.forceActiveFocus();
            keyClick(Qt.Key_Tab);
            compare(cancel.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(authenticate.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(secret.activeFocus, true);
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(authenticate.activeFocus, true);
        }

        function test_a_listed_select_takes_tab_ahead_of_the_field() {
            const [cancel, authenticate] = chooser.buttons();
            chooser.forceActiveFocus();
            compare(chooserSecret.activeFocus, true);
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(who.activeFocus, true, "Backtab from the field reaches the Select");
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(authenticate.activeFocus, true, "Backtab from the Select wraps to the last action");
            keyClick(Qt.Key_Tab);
            compare(who.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(chooserSecret.activeFocus, true, "Tab from the Select reaches the field");
            keyClick(Qt.Key_Tab);
            compare(cancel.activeFocus, true);
            compare(outside.activeFocus, false);
        }

        function test_a_hidden_listed_select_is_skipped() {
            who.visible = false;
            const [cancel, authenticate] = chooser.buttons();
            chooser.forceActiveFocus();
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(authenticate.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(chooserSecret.activeFocus, true);
        }

        function test_a_disabled_initial_focus_field_leaves_the_focus_to_the_accept_action() {
            secret.enabled = false;
            const [cancel, authenticate] = prompt.buttons();
            prompt.forceActiveFocus();
            compare(authenticate.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(cancel.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(authenticate.activeFocus, true);
        }


        function test_text_field_tab_stays_inside_modal_dialog() {
            dialog.forceActiveFocus();
            edit.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            compare(outside.activeFocus, false);
            compare(dialog.buttons()[0].activeFocus, true);
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(edit.activeFocus, true);
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
            compare(dialog.buttons()[1].activeFocus, true);
            compare(outside.activeFocus, false);
        }

        function test_non_modal_dialog_lets_tab_and_escape_pass() {
            const made = Qt.createQmlObject("import QtQuick\nimport qs.Ui\nItem { width: 360; height: 180; Button { id: before; text: \"Before\" } Dialog { id: d; y: 40; modal: false; actions: [{ label: \"Cancel\", role: \"cancel\" }, { label: \"OK\", role: \"accept\" }] } Button { id: after; y: 120; text: \"After\" } property alias dialog: d; property alias after: after }", root);
            const spy = Qt.createQmlObject("import QtTest\nSignalSpy { signalName: \"rejected\" }", root);
            spy.target = made.dialog;
            made.dialog.forceActiveFocus();
            made.dialog.buttons()[1].forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            compare(made.after.activeFocus, true);
            made.dialog.forceActiveFocus();
            keyClick(Qt.Key_Escape);
            compare(spy.count, 0);
            spy.destroy();
            made.destroy();
        }

        function test_tab_skips_a_disabled_action() {
            three.forceActiveFocus();
            const [keep, later, remove] = three.buttons();
            compare(remove.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(keep.activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(remove.activeFocus, true);
            compare(later.enabled, false);
        }

        function test_a_press_answers_with_the_action_role() {
            const [notNow, download] = dialog.buttons();
            mouseClick(download);
            compare(accepts.count, 1);
            mouseClick(notNow);
            compare(rejects.count, 1);
        }

        function test_variants_follow_the_role_or_the_action() {
            const [notNow, download] = dialog.buttons();
            compare(download.variant, "primary");
            compare(notNow.variant, "tertiary");
            tryCompare(notNow.background, "color", Qt.color(Theme.button.variant.tertiary.background));
            const remove = three.buttons()[2];
            compare(remove.variant, "danger");
            tryCompare(remove.background, "color", Qt.color(Theme.button.variant.danger.background));
        }

        // expected-log: Dialog: no action role named "confirm" -- the test names an unknown action role on purpose
        function test_unknown_role_is_read_as_cancel() {
            const odd = Qt.createQmlObject("import qs.Ui\nDialog { actions: [{ label: \"Go\", role: \"confirm\" }] }", root);
            const spy = Qt.createQmlObject("import QtTest\nSignalSpy { signalName: \"rejected\" }", root);
            spy.target = odd;
            compare(odd.acceptIndex, -1);
            odd.trigger(0);
            compare(spy.count, 1);
            spy.destroy();
            odd.destroy();
        }

        // A destructive accept action leaves the focus to the action marked
        // `focused`, so Enter and Return press that one.
        function test_the_action_marked_focused_takes_the_focus_and_enter() {
            const asks = Qt.createQmlObject("import qs.Ui\nDialog { actions: [{ label: \"Cancel\", role: \"cancel\", focused: true }, { label: \"Hide\", role: \"accept\", variant: \"danger\" }] }", root);
            const rejected = Qt.createQmlObject("import QtTest\nSignalSpy { signalName: \"rejected\" }", root);
            const accepted = Qt.createQmlObject("import QtTest\nSignalSpy { signalName: \"accepted\" }", root);
            rejected.target = asks;
            accepted.target = asks;
            asks.forceActiveFocus();
            const [cancel, hide] = asks.buttons();
            compare(cancel.activeFocus, true);
            compare(hide.activeFocus, false);
            keyClick(Qt.Key_Return);
            compare(rejected.count, 1);
            compare(accepted.count, 0);
            rejected.destroy();
            accepted.destroy();
            asks.destroy();
        }

        // New actions rebuild the buttons, so none holds the focus.
        function test_enter_rejects_once_the_actions_become_one_cancel_action() {
            const held = Qt.createQmlObject("import qs.Ui\nDialog { actions: [{ label: \"Decline\", role: \"cancel\" }, { label: \"Pair\", role: \"accept\" }] }", root);
            const spy = Qt.createQmlObject("import QtTest\nSignalSpy { signalName: \"rejected\" }", root);
            spy.target = held;
            held.forceActiveFocus();
            held.actions = [{ label: "OK", role: "cancel" }];
            compare(held.acceptIndex, -1);
            keyClick(Qt.Key_Return);
            compare(spy.count, 1);
            spy.destroy();
            held.destroy();
        }

        // expected-log: Dialog: no action of role cancel among ["Go"] -- the test builds a dialog with no cancel action on purpose
        function test_actions_without_a_cancel_action_are_logged() {
            const stuck = Qt.createQmlObject("import qs.Ui\nDialog { actions: [{ label: \"Go\", role: \"accept\" }] }", root);
            compare(stuck.entries.length, 1);
            compare(stuck.acceptIndex, 0);
            stuck.destroy();
        }

        // Any log fails the file, so these two build clean or not at all.
        function test_a_cancel_action_or_no_action_is_not_logged() {
            for (const actions of ["[{ label: \"Go\", role: \"accept\" }, { label: \"Close\", role: \"cancel\" }]", "[]"]) {
                const fine = Qt.createQmlObject("import qs.Ui\nDialog { actions: " + actions + " }", root);
                compare(fine.entries.length, actions === "[]" ? 0 : 2);
                fine.destroy();
            }
        }

        function test_busy_disables_the_actions_and_answers_nothing() {
            dialog.forceActiveFocus();
            dialog.busy = true;
            for (const button of dialog.buttons()) {
                compare(button.enabled, false);
                fuzzyCompare(button.opacity, Theme.opacity.disabled, 0.001);
            }
            compare(spinner(dialog).visible, true);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Escape);
            keyClick(Qt.Key_Tab);
            compare(outside.activeFocus, false);
            dialog.trigger(dialog.acceptIndex);
            compare(accepts.count, 0);
            compare(rejects.count, 0);
            dialog.busy = false;
            compare(spinner(dialog).visible, false);
            for (const button of dialog.buttons()) compare(button.opacity, 1);
            keyClick(Qt.Key_Return);
            compare(accepts.count, 1);
        }

        function test_a_disabled_accept_action_answers_nothing() {
            blocked.forceActiveFocus();
            const install = blocked.buttons()[1];
            fuzzyCompare(install.opacity, Theme.opacity.disabled, 0.001);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Enter);
            blocked.trigger(blocked.acceptIndex);
            compare(blockedAccepts.count, 0);
            // The dialog itself holds the focus, and Tab still stays inside.
            keyClick(Qt.Key_Tab);
            compare(blocked.buttons()[0].activeFocus, true);
            keyClick(Qt.Key_Tab);
            compare(blocked.buttons()[0].activeFocus, true);
        }

        function test_content_sits_between_the_message_and_the_actions() {
            compare(extra.visible, true);
            const top = extra.mapToItem(dialog, 0, 0).y;
            const message = messageLabel(dialog);
            verify(top >= message.y + message.height, "the content starts under the message");
            const actions = dialog.buttons()[0].mapToItem(dialog, 0, 0).y;
            verify(top + extra.height <= actions, "the content ends above the actions");
            compare(hiddenLabel.visible, false);
        }

        function test_actions_keep_one_gap_under_the_header_when_the_body_is_empty() {
            for (const ofDialog of [emptyBody, hiddenBody]) {
                const p = pane(ofDialog);
                compare(p.bodyContentHeight, 0);
                compare(footerSlot(ofDialog).y, headerSlot(ofDialog).y + headerSlot(ofDialog).height + p.gap);
                compare(ofDialog.implicitHeight, 2 * p.contentInset + p.headerHeight + p.gap + p.footerHeight);
            }
        }

        function test_tall_content_scrolls_under_the_maximum_height() {
            const tall = Qt.createQmlObject("import QtQuick\nimport qs.Ui\nDialog { width: 360; availableHeight: 200; title: \"Tall\"; Rectangle { width: parent.width; height: 400; color: \"transparent\" } }", root);
            tryCompare(tall, "implicitHeight", 160);
            const p = pane(tall);
            verify(p.scrollArea.overflowing, "the body scrolls when the fitted height is capped");
            tall.destroy();
        }

        function test_the_default_maximum_height_comes_from_the_screen() {
            const window = Qt.createQmlObject("import QtQuick\nimport QtQuick.Window\nimport qs.Ui\nWindow { width: 300; height: 300; visible: true; Dialog { id: d; objectName: \"dialog\"; width: 240; title: \"Screen\"; Rectangle { width: parent.width; height: 4000; color: \"transparent\" } } }", root);
            wait(0);
            const made = window.contentItem.children[0];
            const screenHeight = made.screenHeight();
            verify(screenHeight > 0, "the test window has a screen");
            tryCompare(made, "maximumHeight", screenHeight * Theme.dialog.maxHeightShare);
            window.destroy();
        }

        // A dialog over an area that takes every button, the hover and the
        // wheel, as a scrim does: a press of either button, the hover and
        // the wheel on the card's empty space, its top padding, reach
        // nothing under it, while a press beside the card reaches the area.
        function test_its_card_takes_the_pointer_from_what_lies_under_it() {
            const stage = Qt.createQmlObject("import QtQuick\nimport qs.Ui\nItem {\n"
                + "    width: 400; height: 500\n"
                + "    property int presses: 0\n"
                + "    property int wheels: 0\n"
                + "    property alias beneath: beneath\n"
                + "    property alias dialog: covering\n"
                + "    MouseArea { id: beneath; anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true; onPressed: parent.presses++; onWheel: wheel => parent.wheels++ }\n"
                + "    Dialog { id: covering; width: 360; title: \"Covering\"; actions: [{ label: \"Cancel\", role: \"cancel\" }] }\n"
                + "}", root);
            const x = stage.dialog.width / 2;
            tryVerify(() => stage.dialog.height > 0 && stage.dialog.height < stage.height - 10, 1000, "the dialog leaves room beside it");
            mouseMove(stage, x, 3);
            wait(50);
            verify(!stage.beneath.containsMouse, "the area under the card is hovered");
            mouseClick(stage, x, 3);
            mouseClick(stage, x, 3, Qt.RightButton);
            mouseWheel(stage, x, 3, 0, -120);
            wait(50);
            compare(stage.presses, 0, "a press on the card reaches the area");
            compare(stage.wheels, 0, "the wheel on the card reaches the area");
            mouseClick(stage, x, stage.height - 5);
            compare(stage.presses, 1, "a press beside the card reaches the area");
            stage.destroy();
        }

        // A dialog that is not modal sits inline in a page: the wheel on its
        // card reaches the area under it, which the page's scroll is, while
        // a press still stops at the card.
        function test_an_inline_card_passes_the_wheel_on() {
            const stage = Qt.createQmlObject("import QtQuick\nimport qs.Ui\nItem {\n"
                + "    width: 400; height: 500\n"
                + "    property int presses: 0\n"
                + "    property int wheels: 0\n"
                + "    property alias dialog: covering\n"
                + "    MouseArea { anchors.fill: parent; onPressed: parent.presses++; onWheel: wheel => parent.wheels++ }\n"
                + "    Dialog { id: covering; width: 360; modal: false; title: \"Inline\"; actions: [{ label: \"Cancel\", role: \"cancel\" }] }\n"
                + "}", root);
            const x = stage.dialog.width / 2;
            tryVerify(() => stage.dialog.height > 0, 1000, "the dialog is laid out");
            mouseWheel(stage, x, 3, 0, -120);
            tryCompare(stage, "wheels", 1);
            mouseClick(stage, x, 3);
            wait(50);
            compare(stage.presses, 0, "a press on the inline card reaches the area");
            stage.destroy();
        }

        function test_theme_change_reaches_the_card_and_the_roles() {
            const before = String(card(dialog).color);
            compare(UnitTheme.override({ palette: { background: "#ffffff", foreground: "#000000" }, dialog: { titleRole: "h2", bodyRole: "hint" } }), "ok");
            verify(String(card(dialog).color) !== before, "the palette moves the card");
            compare(String(card(dialog).color), String(Qt.color(Theme.dialog.background)));
            compare(titleLabel(dialog).role, "h2");
            compare(titleLabel(dialog).font.pixelSize, Theme.text.h2.size);
            compare(messageLabel(dialog).role, "hint");
        }

        function test_padding_changes_reach_the_pane_inset() {
            compare(UnitTheme.override({ dialog: { padding: 31 } }), "ok");
            compare(pane(emptyBody).contentInset, 31);
            compare(headerSlot(emptyBody).x, 31);
            compare(UnitTheme.override({ inset: { dialog: 27 } }), "ok");
            compare(Theme.dialog.padding, 27);
            compare(pane(emptyBody).contentInset, 27);
            compare(headerSlot(emptyBody).x, 27);
        }

        // Actions wider together than the text column, the reset notice's
        // pair among them, and one wider alone: every action stays between
        // the text's edges, in its order, in lines flush right, and clears
        // the spinner while the dialog is busy.
        function test_actions_too_wide_for_one_line_wrap_inside_the_text() {
            const crowded = Qt.createQmlObject("import QtQuick\nimport qs.Ui\nDialog {\n"
                + "    title: \"VGS was reset\"\n"
                + "    message: \"Your previous settings are in a backup.\"\n"
                + "    actions: [{ label: \"Restore previous settings\", role: \"accept\" }, { label: \"Keep these\", role: \"cancel\" },"
                + " { label: \"Restore every previous setting, plugin and theme from the backup\", role: \"cancel\" }]\n"
                + "}", root);
            const text = messageLabel(crowded);
            tryVerify(() => text.width > 0 && crowded.buttons().every(button => button.width > 0), 1000, "the dialog is laid out");
            const left = text.mapToItem(crowded, 0, 0).x;
            const right = left + text.width;
            const buttons = crowded.buttons();
            const gap = Theme.dialog.actionGap;
            verify(buttons[2].implicitWidth > text.width, "the long action is wider than the text column");

            function edges() {
                return buttons.map(button => {
                    const at = button.mapToItem(crowded, 0, 0);
                    return { left: at.x, right: at.x + button.width, top: at.y, bottom: at.y + button.height };
                });
            }

            const placed = edges();
            for (let i = 0; i < placed.length; i++) {
                verify(placed[i].left >= left - 0.5, "action " + i + " starts at " + placed[i].left + ", left of the text at " + left);
                verify(placed[i].right <= right + 0.5, "action " + i + " ends at " + placed[i].right + ", right of the text at " + right);
                if (i === 0) continue;
                const sameLine = Math.abs(placed[i].top - placed[i - 1].top) < 1;
                verify(sameLine ? placed[i].left >= placed[i - 1].right : placed[i].top >= placed[i - 1].bottom, "action " + i + " follows action " + (i - 1));
                if (!sameLine) fuzzyCompare(placed[i - 1].right, right, 0.5, "line before action " + i + " ends at the text's right edge");
            }
            fuzzyCompare(placed[placed.length - 1].right, right, 0.5, "the last line ends at the text's right edge");
            verify(placed[2].top > placed[0].top, "the actions wrap to a further line");
            const bottom = Math.max(...placed.map(edge => edge.bottom));
            verify(footer(crowded).mapToItem(crowded, 0, footer(crowded).height).y >= bottom - 0.5, "the footer holds every line");

            crowded.busy = true;
            const turning = spinner(crowded);
            const clear = turning.mapToItem(crowded, turning.width, 0).x + gap;
            for (const [i, edge] of edges().entries()) {
                verify(edge.left >= clear - 0.5, "busy action " + i + " starts at " + edge.left + ", over the spinner ending at " + clear);
                verify(edge.right <= right + 0.5, "busy action " + i + " ends right of the text");
            }
            crowded.destroy();
        }
    }
}
