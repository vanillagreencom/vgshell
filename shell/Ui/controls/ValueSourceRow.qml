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
// The actions follow the message as its links, each a sentence of its
// own after it, "The theme sets 0 px. Use theme value" (owner, Slack
// 1795385366.653319): Use my Hyprland value, which stops VGS from writing
// the option, after the user's own configured value, and Use theme value,
// after a user's or Hyprland's value of a value the theme can set. An
// action's link goes once its edit lands, and the message keeps the keys
// on whatever link it then holds, or on none, so its activation first
// gives the focus back to the row's control.
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
    readonly property string configWords: "Hyprland config"
    readonly property string hyprlandWords: "Use my Hyprland value"
    readonly property string themeWords: "Use theme value"
    readonly property var actionWords: (offersHyprlandValue ? [hyprlandWords] : []).concat(offersThemeValue ? [themeWords] : [])

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

    // The item before FROM, the message, in the focus chain that the row's
    // control holds, and none in a row whose control takes no keys. It reads
    // where the item sits in the row, not its place: the message stands
    // under the control's ink and can overlap the row box.
    function focusControl(from) {
        for (let item = from.nextItemInFocusChain(false); item !== null && item !== from; item = item.nextItemInFocusChain(false)) {
            if (root.holdsControl(item)) {
                item.forceActiveFocus(from.focusReason);
                return;
            }
        }
    }

    // An action is only offered beside a message: every kind that offers
    // one names a source.
    warning: [messageText(messageKind)].concat(actionWords).join(". ")
    // The smaller role draws the message and its links as small text under
    // the control.
    warningRole: "tooltip"
    warningTone: messageKind === "config" || messageKind === "overridden" ? "warning" : "muted"
    warningLink: (messageKind === "config" || messageKind === "overridden" || messageKind === "hyprland" ? [configWords] : []).concat(actionWords)
    onWarningLinkActivated: words => {
        switch (words) {
        case root.configWords:
            root.openHyprlandConfig();
            return;
        case root.hyprlandWords:
            root.focusControl(root.messageItem);
            root.useHyprlandValue();
            return;
        case root.themeWords:
            root.focusControl(root.messageItem);
            root.useThemeValue();
            return;
        }
        console.error("ValueSourceRow: no link named " + JSON.stringify(words));
    }
}
