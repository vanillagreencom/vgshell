import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// ValueSourceRow: the row reads Hyprland's own value, the user's configured
// value and an override for its path from what the `hyprland` capability
// lends; a configured value is a warning that links the Hyprland
// configuration and offers Use my Hyprland value, and outranks an override,
// which outranks the theme's line; a row the theme can set says Set by
// theme in muted text with no action, offers Use theme value beside a
// user's or Hyprland's value, and links the configuration beside
// Hyprland's; a row the theme cannot set says nothing until Hyprland does;
// two actions stand `rowAction.gap` apart; the control shows the source's
// value, the theme's while Hyprland is unread; an action emits its signal
// and hands the keys back to the row's control; the link opens the
// configuration.
Item {
    id: root
    width: 640
    height: 520

    // What the `hyprland` capability lends, as a plain object a row reads.
    function lent(values, userValues, overridden) {
        return { values: values, userValues: userValues, overridden: overridden };
    }

    Column {
        width: 600

        ValueSourceRow {
            id: row
            width: parent.width
            label: "Corner radius"
            path: "decoration.rounding"
            themeOffered: true
            source: "theme"
            themeValue: 4
            userValue: 12
            formatValue: value => value + " px"
            Switch { id: control; size: "sm" }
        }

        ValueSourceRow {
            id: plain
            width: parent.width
            label: "Pointer speed"
            path: "input.sensitivity"
            source: "user"
            userValue: 0.3
            Switch { size: "sm" }
        }
    }

    SignalSpy { id: hyprlandUses; target: row; signalName: "useHyprlandValue" }
    SignalSpy { id: themeUses; target: row; signalName: "useThemeValue" }
    SignalSpy { id: opens; target: row; signalName: "openHyprlandConfig" }

    TestCase {
        name: "valuesourcerow"
        when: windowShown

        function init() {
            UnitTheme.reset();
            row.hyprland = null;
            row.source = "theme";
            row.themeOffered = true;
            plain.hyprland = null;
            hyprlandUses.clear();
            themeUses.clear();
            opens.clear();
        }

        function action(name) {
            const found = [row];
            for (let i = 0; i < found.length; i++) {
                if (found[i].objectName === name) return found[i];
                for (const child of found[i].children) found.push(child);
            }
            return null;
        }
        function messageOf(target) { return target.children.find(child => child.role === "hint"); }
        function shownActions() { return ["useHyprlandValue", "useThemeValue"].filter(name => action(name).visible && row.actionItem !== null); }

        function test_a_theme_value_is_set_by_theme_in_muted_text() {
            compare(row.messageKind, "theme");
            compare(row.warningTone, "muted");
            compare(row.warningLink, "");
            verify(row.warning !== "");
            compare(shownActions(), []);
            compare(row.actionItem, null, "no action takes room");
            compare(row.shownValue, 4);
        }

        function test_a_user_value_offers_the_theme_value() {
            row.source = "user";
            compare(row.messageKind, "user");
            compare(row.warningTone, "muted");
            verify(row.warning.indexOf(row.formatValue(4)) !== -1, "the line names the theme's value");
            compare(shownActions(), ["useThemeValue"]);
            compare(row.shownValue, 12);
        }

        function test_hyprland_value_links_the_configuration_and_offers_the_theme_value() {
            row.source = "hyprland";
            compare(row.shownValue, 4, "before Hyprland is read the row shows the theme's value");
            row.hyprland = lent({ "decoration.rounding": 10 }, [], []);
            compare(row.hyprlandValue, 10);
            compare(row.shownValue, 10, "the row shows Hyprland's own value");
            compare(row.messageKind, "hyprland");
            compare(row.warningTone, "muted");
            verify(row.warningLink !== "" && row.warning.indexOf(row.warningLink) !== -1, "the line links the Hyprland configuration");
            compare(shownActions(), ["useThemeValue"]);
        }

        function test_a_configured_value_warns_and_offers_both_ways_back() {
            row.source = "user";
            row.hyprland = lent({}, [{ path: "input.sensitivity", value: 1 }, { path: "decoration.rounding", value: 10 }], []);
            compare(row.hyprlandConfigValue, 10, "the row reads its own path's value");
            compare(row.messageKind, "config");
            compare(row.warningTone, "warning");
            verify(row.warning.indexOf(row.formatValue(10)) !== -1, "the line names the configured value");
            verify(row.warningLink !== "" && row.warning.indexOf(row.warningLink) !== -1);
            compare(shownActions(), ["useHyprlandValue", "useThemeValue"]);
            const first = action("useHyprlandValue");
            const second = action("useThemeValue");
            // RowActions places its children at its next polish.
            tryVerify(() => second.mapToItem(row, 0, 0).x - first.mapToItem(row, first.width, 0).x === Theme.rowAction.gap, 2000, "two actions stand the row action gap apart");
            row.source = "theme";
            compare(shownActions(), ["useHyprlandValue"], "over the theme's value only Use my Hyprland value");
        }

        function test_an_override_warns_without_an_action() {
            row.source = "user";
            row.hyprland = lent({}, [], ["decoration.rounding"]);
            compare(row.overridden, true);
            compare(row.messageKind, "overridden");
            compare(row.warningTone, "warning");
            verify(row.warningLink !== "");
            compare(shownActions(), []);
            row.hyprland = lent({}, [{ path: "decoration.rounding", value: 10 }], ["decoration.rounding"]);
            compare(row.messageKind, "config", "a configured value outranks the override");
        }

        function test_a_row_the_theme_cannot_set_speaks_only_for_hyprland() {
            compare(plain.messageKind, "");
            compare(plain.warning, "");
            compare(messageOf(plain).visible, false);
            compare(plain.shownValue, 0.3);
            plain.hyprland = lent({}, [{ path: "input.sensitivity", value: -0.5 }], []);
            compare(plain.messageKind, "config");
            compare(plain.offersHyprlandValue, true);
            compare(plain.offersThemeValue, false);
            plain.hyprland = lent({}, [], ["input.sensitivity"]);
            compare(plain.messageKind, "overridden");
            plain.source = "hyprland";
            plain.hyprland = lent({ "input.sensitivity": 0.2 }, [], []);
            compare(plain.shownValue, 0.2, "Hyprland's value while VGS sets none");
            compare(plain.messageKind, "", "a row the theme cannot set names no source");
            plain.source = "user";
        }

        function test_an_action_emits_and_hands_the_keys_to_the_control() {
            row.source = "user";
            row.hyprland = lent({}, [{ path: "decoration.rounding", value: 10 }], []);
            const use = action("useHyprlandValue");
            use.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(hyprlandUses.count, 1);
            compare(control.activeFocus, true, "the keys go back to the row's control");
            const back = action("useThemeValue");
            back.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(themeUses.count, 1);
            compare(control.activeFocus, true, "past the link and the other action");
        }

        function test_the_link_opens_the_configuration() {
            row.source = "user";
            row.hyprland = lent({}, [{ path: "decoration.rounding", value: 10 }], []);
            const link = messageOf(row);
            link.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(opens.count, 1);
        }
    }
}
