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
// theme in muted text with no action, offers Use theme value after a
// user's or Hyprland's value, and links the configuration after
// Hyprland's; a row the theme cannot set says nothing until Hyprland does;
// each action is a link that ends the row's message, in the link colour,
// and every message draws in the tooltip role; the control shows the
// source's value, the theme's while Hyprland is unread; the message is one
// Tab stop whose links the arrows select, and an action's link emits its
// signal from the keys or the pointer and hands the keys back to the row's
// control, never to another row's; the configuration's link opens the
// configuration; the row reads each member the capability lends once.
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

    // Two rows with sliders in a column of `stack.row` spacing: the lower
    // stands by ink under the upper, so its box starts above its own top.
    Column {
        id: spacedRows
        y: 260
        width: 600
        spacing: Theme.stack.row

        ValueSourceRow {
            id: upper
            width: parent.width
            label: "Border width"
            path: "general.border_size"
            source: "user"
            userValue: 2
            Slider { id: upperSlider; width: parent.width; from: 0; to: 10; value: 2 }
        }

        // A row whose control takes no keys, as Keyboard's Variants row.
        ValueSourceRow {
            id: lower
            width: parent.width
            label: "Inner gaps"
            path: "general.gaps_in"
            source: "user"
            userValue: 4
        }
    }

    SignalSpy { id: hyprlandUses; target: row; signalName: "useHyprlandValue" }
    SignalSpy { id: themeUses; target: row; signalName: "useThemeValue" }
    SignalSpy { id: opens; target: row; signalName: "openHyprlandConfig" }
    SignalSpy { id: lowerUses; target: lower; signalName: "useHyprlandValue" }

    UnitCase {
        name: "valuesourcerow"
        when: windowShown

        function init() {
            UnitTheme.reset();
            row.hyprland = null;
            row.source = "theme";
            row.themeOffered = true;
            plain.hyprland = null;
            upper.hyprland = null;
            lower.hyprland = null;
            hyprlandUses.clear();
            themeUses.clear();
            opens.clear();
            lowerUses.clear();
        }

        function messageOf(target) { return displayedTextItems(target, true).find(child => child instanceof LinkText && !(child instanceof InfoButton)); }
        // The signal each link of the row's message emits, in the order the
        // message draws them.
        function linkSignals() {
            const message = messageOf(row);
            const spies = [[opens, "openHyprlandConfig"], [hyprlandUses, "useHyprlandValue"], [themeUses, "useThemeValue"]];
            const emitted = [];
            for (let index = 0; index < message.links.length; index++) {
                const before = spies.map(([spy]) => spy.count);
                message.currentLink = index;
                message.clicked();
                emitted.push(spies.filter(([spy], at) => spy.count > before[at]).map(([, name]) => name).join(","));
            }
            opens.clear();
            hyprlandUses.clear();
            themeUses.clear();
            return emitted;
        }
        // The centre of the link at INDEX of the row's message, in it.
        function linkPoint(message, index) {
            const span = message.underlined.find(item => item.index === index);
            return Qt.point((span.left + span.right) / 2, span.line * message.linePitch + message.linePitch / 2);
        }

        function test_a_theme_value_is_set_by_theme_in_muted_text() {
            compare(row.messageKind, "theme");
            compare(row.warningTone, "muted");
            verify(row.warning !== "");
            compare(messageOf(row).linked, false, "the line offers nothing");
            compare(row.shownValue, 4);
        }

        function test_a_user_value_offers_the_theme_value() {
            row.source = "user";
            compare(row.messageKind, "user");
            compare(row.warningTone, "muted");
            verify(row.warning.indexOf(row.formatValue(4)) !== -1, "the line names the theme's value");
            compare(linkSignals(), ["useThemeValue"]);
            const message = messageOf(row);
            const link = message.links[0];
            compare(link.end, message.plain.length, "the action ends the line");
            verify(link.start > row.messageText("user").length && message.plain.indexOf(row.messageText("user")) === 0, "the action follows the theme's value");
            verify(Qt.colorEqual(message.linkColor, Theme.color.accent), "in the link colour");
            compare(message.role, "tooltip", "in the line's small text");
            compare(row.actionItem, null, "no action stands apart from the line");
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
            compare(linkSignals(), ["openHyprlandConfig", "useThemeValue"], "the line links the Hyprland configuration, then the theme's value");
        }

        function test_a_configured_value_warns_and_offers_both_ways_back() {
            row.source = "user";
            row.hyprland = lent({}, [{ path: "input.sensitivity", value: 1 }, { path: "decoration.rounding", value: 10 }], []);
            compare(row.hyprlandConfigValue, 10, "the row reads its own path's value");
            compare(row.messageKind, "config");
            compare(row.warningTone, "warning");
            compare(messageOf(row).role, "tooltip", "the line draws in the tooltip role, 1 px under hint");
            verify(row.warning.indexOf(row.formatValue(10)) !== -1, "the line names the configured value");
            compare(linkSignals(), ["openHyprlandConfig", "useHyprlandValue", "useThemeValue"]);
            row.source = "theme";
            compare(linkSignals(), ["openHyprlandConfig", "useHyprlandValue"], "over the theme's value only Use my Hyprland value");
        }

        function test_an_override_warns_without_an_action() {
            row.source = "user";
            row.hyprland = lent({}, [], ["decoration.rounding"]);
            compare(row.overridden, true);
            compare(row.messageKind, "overridden");
            compare(row.warningTone, "warning");
            compare(linkSignals(), ["openHyprlandConfig"], "the line links the configuration and offers no action");
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

        function test_each_action_link_takes_the_keys_and_hands_them_back() {
            row.source = "user";
            row.hyprland = lent({}, [{ path: "decoration.rounding", value: 10 }], []);
            const message = messageOf(row);
            compare(message.links.length, 3, "the configuration's link and two actions");
            control.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            compare(message.activeFocus, true, "Tab takes the keys from the control to the line");
            compare(message.currentLink, 0);
            keyClick(Qt.Key_Right);
            compare(message.currentLink, 1, "an arrow selects the next link");
            keyClick(Qt.Key_Space);
            compare(hyprlandUses.count, 1);
            compare(control.activeFocus, true, "the keys go back to the row's control");
            keyClick(Qt.Key_Tab);
            compare(message.activeFocus, true);
            keyClick(Qt.Key_End);
            compare(message.currentLink, 2);
            keyClick(Qt.Key_Return);
            compare(themeUses.count, 1);
            compare(control.activeFocus, true, "past the configuration's link");
            const point = linkPoint(message, 1);
            mouseClick(message, point.x, point.y);
            compare(hyprlandUses.count, 2, "a click on the action's words emits it");
            compare(control.activeFocus, true, "a click hands the keys to the control too");
            compare(opens.count, 0, "no action opens the configuration");
        }

        // Keyboard's Variants row draws no control of its own: its link
        // gives the keys to no other row's control.
        function test_an_action_of_a_row_with_no_control_hands_the_keys_to_no_other_row() {
            const configured = lent({}, [{ path: "general.border_size", value: 3 }, { path: "general.gaps_in", value: 6 }], []);
            upper.hyprland = configured;
            lower.hyprland = configured;
            const message = messageOf(lower);
            message.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_End);
            keyClick(Qt.Key_Space);
            compare(lowerUses.count, 1, "the row emits its action");
            compare(upperSlider.activeFocus, false, "the row above's slider takes no keys");
            compare(messageOf(upper).activeFocus, false, "nor the row above's line");
        }

        // The capability builds `values`, `userValues` and `overridden`
        // again on each read, so a row that reads one twice doubles the
        // work of every Hyprland reload. The engine may evaluate the three
        // bindings more than once for one capability, each as often as the
        // others, so the reads of `values` and `overridden` are compared
        // with those of `userValues`, one an evaluation.
        function test_each_lent_member_is_read_once() {
            const reads = { values: 0, userValues: 0, overridden: 0 };
            row.source = "hyprland";
            row.hyprland = {
                get values() { reads.values += 1; return { "decoration.rounding": 10 }; },
                get userValues() { reads.userValues += 1; return [{ path: "decoration.rounding", value: 10 }]; },
                get overridden() { reads.overridden += 1; return ["decoration.rounding"]; }
            };
            compare([row.hyprlandValue, row.hyprlandConfigValue, row.overridden], [10, 10, true]);
            const evaluations = reads.userValues;
            verify(evaluations >= 1, "the row read the capability");
            compare(reads.values, evaluations, "Hyprland's values are read once an evaluation");
            compare(reads.overridden, evaluations, "the overrides are read once an evaluation");
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
