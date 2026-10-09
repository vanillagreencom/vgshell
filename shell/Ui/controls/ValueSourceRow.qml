import QtQuick
import qs.Commons
import qs.Ui

// The one row for a value that maps to a Hyprland option (D057): a FormRow
// that states where its value comes from and offers the way back. `source`
// is `theme`, `user` or `hyprland`, Hyprland's own value while VGS writes
// none. `themeOffered` says the theme can set the value, so the row names
// it: Set by theme, the theme's value beside the user's, or Set by your
// Hyprland config. `hyprland` is what the `hyprland` capability lends,
// `values`, `userValues` and `overridden`, and `path` the option the row
// maps to, from which the row reads `hyprlandValue`, Hyprland's own value
// while VGS writes none, `hyprlandConfigValue`, the value the user's
// Hyprland configuration gave the option, which VGS replaced, and
// `overridden`, Hyprland reading the option back as another value than VGS
// wrote; each is undefined or false while unread. Each of the three reads
// its member of `hyprland` once: the capability builds a member's answer
// again on every read. The configured value and
// the override are a warning that links the Hyprland configuration and
// outranks the theme's line. `formatValue` writes a value
// as the row's message shows it. `shownValue` is what the row's control
// shows: the theme's value, the user's, or Hyprland's own, which before
// Hyprland is read is the theme's where the theme offers one, else the
// user's.
//
// The actions are RowActions: Use my Hyprland value, which stops VGS from
// writing the option, beside the user's own configured value, and Use
// theme value, beside a user's or Hyprland's value of a value the theme can
// set. An action hides once its edit lands, and a hidden item holds no
// focus, so its activation first gives the focus back to the row's control.
FormRow {
    id: root

    property string source: "user"
    property bool themeOffered: false
    property var themeValue
    property var userValue
    property var hyprland: null
    property string path: ""
    readonly property var hyprlandValue: {
        const values = hyprland === null ? null : hyprland.values;
        return values !== null && values !== undefined && Object.prototype.hasOwnProperty.call(values, path) ? values[path] : undefined;
    }
    readonly property var hyprlandConfigValue: {
        const rows = hyprland === null ? null : hyprland.userValues;
        const row = Array.isArray(rows) ? rows.find(entry => entry.path === path) : undefined;
        return row === undefined ? undefined : row.value;
    }
    readonly property bool overridden: {
        const paths = hyprland === null ? null : hyprland.overridden;
        return Array.isArray(paths) && paths.indexOf(path) !== -1;
    }
    property var formatValue: value => String(value)
    readonly property var shownValue: source === "theme" ? themeValue
        : source === "user" ? userValue
        : hyprlandValue !== undefined ? hyprlandValue
        : themeOffered ? themeValue : userValue
    // `config`, `overridden`, `theme`, `user`, `hyprland`, or "" for a
    // row with nothing to say.
    readonly property string messageKind: hyprlandConfigValue !== undefined ? "config"
        : overridden ? "overridden"
        : themeOffered ? source : ""
    readonly property bool offersHyprlandValue: messageKind === "config"
    readonly property bool offersThemeValue: themeOffered && source !== "theme" && messageKind !== "overridden"
    readonly property bool offersAction: offersHyprlandValue || offersThemeValue

    signal useHyprlandValue()
    signal useThemeValue()
    signal openHyprlandConfig()

    function messageText(kind) {
        switch (kind) {
        case "config": return "Hyprland config sets " + formatValue(hyprlandConfigValue);
        case "overridden": return "Overridden by your Hyprland config";
        case "theme": return "Set by theme";
        case "user": return "The theme sets " + formatValue(themeValue);
        case "hyprland": return "Set by your Hyprland config";
        case "": return "";
        }
        console.error("ValueSourceRow: no message named " + JSON.stringify(kind));
        return "";
    }

    // The item before FROM in the focus chain that sits in the row's box,
    // the row's control, past the message's link and the other actions.
    function focusControl(from) {
        for (let item = from.nextItemInFocusChain(false); item !== null && item !== from; item = item.nextItemInFocusChain(false)) {
            let at = item;
            while (at !== null && at !== root) at = at.parent;
            if (at === root && item.mapToItem(root, 0, 0).y < root.boxHeight) {
                item.forceActiveFocus(from.focusReason);
                return;
            }
        }
    }

    warning: messageText(messageKind)
    // Each message draws 1 px under `hint`, in the 12 px sans role, so the
    // line naming the user's own value fits beside its actions (VGS-1130).
    warningRole: "tooltip"
    warningTone: messageKind === "config" || messageKind === "overridden" ? "warning" : "muted"
    warningLink: messageKind === "config" || messageKind === "overridden" || messageKind === "hyprland" ? "Hyprland config" : ""
    onWarningLinkActivated: root.openHyprlandConfig()

    action: RowActions {
        visible: root.offersAction

        RowAction {
            id: hyprlandAction
            objectName: "useHyprlandValue"
            visible: root.offersHyprlandValue
            text: "Use my Hyprland value"
            onClicked: {
                root.focusControl(hyprlandAction);
                root.useHyprlandValue();
            }
        }

        RowAction {
            id: themeAction
            objectName: "useThemeValue"
            visible: root.offersThemeValue
            text: "Use theme value"
            onClicked: {
                root.focusControl(themeAction);
                root.useThemeValue();
            }
        }
    }
}
