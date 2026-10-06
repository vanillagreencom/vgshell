import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// TitleButton: its text over an underline as wide as the text, a caret
// after it; a click and Down open its menu, which a second click closes;
// the text takes `titleButton.hover` while hovered or open, and the
// underline shows only with keyboard focus; given less width than it
// needs, the text elides and the caret stays inside.
Item {
    id: root
    width: 400
    height: 200

    TitleButton {
        id: title
        text: "Notifications"
        menu: menu
        Menu {
            id: menu
            MenuItem { text: "Bar" }
            MenuItem { text: "Notifications"; checked: true }
        }
    }
    TitleButton { id: narrow; y: 60; width: 60; text: "A title far wider than its button" }

    TestCase {
        name: "titlebutton"
        when: windowShown

        function init() { UnitTheme.reset(); menu.close(); }

        function label(button) { return button.contentItem.children[0]; }
        function underline(button) { return button.contentItem.children[1]; }
        function caret(button) { return button.contentItem.children[2]; }

        function test_the_title_draws_its_role_underline_and_caret() {
            compare(label(title).role, "h3");
            compare(label(title).text, "Notifications");
            compare(underline(title).width, label(title).width);
            compare(underline(title).height, Theme.titleButton.underline);
            compare(underline(title).y, label(title).height + Theme.titleButton.underlineGap);
            compare(caret(title).name, "chevron-down");
            compare(caret(title).x, label(title).width + Theme.titleButton.gap);
            compare(title.implicitWidth, label(title).implicitWidth + Theme.titleButton.gap + caret(title).width);
        }

        function test_a_click_and_down_open_the_menu() {
            mouseClick(title);
            compare(menu.opened, true);
            compare(title.menuOpen, true);
            compare(menu.currentIndex, 1, "the checked entry is highlighted on open");
            mouseClick(title);
            compare(menu.opened, false);
            root.Window.window.requestActivate();
            title.forceActiveFocus();
            tryCompare(title, "activeFocus", true);
            keyClick(Qt.Key_Down);
            compare(menu.opened, true);
            menu.close();
        }

        function test_hover_and_an_open_menu_take_the_hover_colour() {
            compare(String(label(title).color), String(Qt.color(Theme.titleButton.foreground)));
            menu.open();
            compare(String(label(title).color), String(Qt.color(Theme.titleButton.hover)));
            menu.close();
            mouseMove(title, 5, 5);
            tryCompare(title, "hovered", true);
            compare(String(label(title).color), String(Qt.color(Theme.titleButton.hover)));
            mouseMove(root, root.width - 1, root.height - 1);
        }

        // At rest the caret alone marks the menu. Hover and an open menu
        // change the colour alone; the underline shows only while the
        // button holds keyboard focus. The caret centres on the text's
        // capital centre on a whole pixel.
        function test_the_underline_marks_keyboard_focus_alone_and_the_caret_centres() {
            compare(underline(title).visible, false);
            menu.open();
            compare(title.menuOpen, true);
            compare(underline(title).visible, false, "an open menu draws no underline");
            menu.close();
            mouseMove(title, 5, 5);
            tryCompare(title, "hovered", true);
            compare(underline(title).visible, false, "hover draws no underline");
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(title, "hovered", false);
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            narrow.forceActiveFocus();
            tryCompare(narrow, "activeFocus", true);
            keyClick(Qt.Key_Backtab);
            tryCompare(title, "visualFocus", true);
            compare(underline(title).visible, true, "keyboard focus draws the underline");
            keyClick(Qt.Key_Tab);
            tryCompare(narrow, "activeFocus", true);
            compare(underline(title).visible, false);
            compare(caret(title).y, Math.round(caret(title).y));
            verify(Math.abs(caret(title).y + caret(title).height / 2 - label(title).capCentre) <= 0.5, "caret centre " + (caret(title).y + caret(title).height / 2) + ", capital centre " + label(title).capCentre);
        }

        // The button reports its title's capital centre from its own top,
        // so a header can put the text on its centre line.
        function test_the_button_reports_its_capital_centre() {
            compare(title.capCentre, title.topPadding + label(title).mapToItem(title, 0, 0).y - title.topPadding + label(title).capCentre);
            verify(title.capCentre > 0 && title.capCentre < label(title).height, "the capital centre lies inside the title's line");
        }

        function test_a_narrow_title_elides_and_keeps_its_caret_inside() {
            verify(label(narrow).implicitWidth > narrow.width, "the text is wider than the button");
            compare(label(narrow).width, narrow.width - Theme.titleButton.gap - caret(narrow).width);
            compare(caret(narrow).x + caret(narrow).width, narrow.width);
        }

        function test_a_theme_change_moves_the_title() {
            compare(UnitTheme.override({ titleButton: { gap: 9, underlineGap: 5 } }), "ok");
            compare(caret(title).x, label(title).width + 9);
            compare(underline(title).y, label(title).height + 5);
        }
    }
}
