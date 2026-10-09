import QtQuick
import qs.Commons
import qs.Ui

// Windows pane: the corner radius and the border width over the theme, each
// Set by theme until the user moves it. The corner radius is one base:
// windows take it, flyouts three quarters of it and grouped window tabs
// half of it (ThemeLogic.APPEARANCE_RATIOS). Both map to a Hyprland option,
// so each row also offers the user's own Hyprland value. Each slider runs
// between the bounds the `appearance` capability lends for its value, the
// judge's own.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var appearance: shell === null ? null : shell.appearance
    readonly property Item initialFocus: radius.slider

    function open(payloadJson) {}
    function close() {}

    function answer(reply) {
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("windows: appearance " + reply);
    }

    function openHyprlandConfig() {
        const reply = shell.tui.edit("hypr/hyprland.lua");
        if (reply !== "ok") console.warn("windows: edit " + reply);
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    // Where Appearance value KEY comes from, the theme's value and the
    // user's, as the `appearance` capability lends them.
    function sourceOf(key) { return appearance === null ? "theme" : appearance.sources[key]; }
    function themeOf(key) { return appearance === null ? 0 : appearance.theme[key]; }
    function valueOf(key) { return appearance === null ? undefined : appearance.values[key]; }
    function pathOf(key) { return appearance === null ? "" : appearance.keys[key].hyprland; }
    function boundOf(key, bound) { return appearance === null ? 0 : appearance.keys[key][bound]; }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        SectionHeader {
            width: parent.width
            text: "Shape"
            description: "Set the corners and borders of windows."
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            ValueSourceRow {
                id: radiusRow
                width: parent.width
                label: "Corner radius"
                themeOffered: true
                source: root.sourceOf("windowRadius")
                themeValue: root.themeOf("windowRadius")
                userValue: root.valueOf("windowRadius")
                hyprland: root.shell === null ? null : root.shell.hyprland
                path: root.pathOf("windowRadius")
                formatValue: value => value + " px"
                onUseHyprlandValue: root.answer(root.shell.appearance.set("windowRadius", "hyprland"))
                onUseThemeValue: root.answer(root.shell.appearance.unset("windowRadius"))
                onOpenHyprlandConfig: root.openHyprlandConfig()
                info: "Windows use this radius. Flyouts use three quarters of it. Grouped window tabs use half of it."
                SavedSlider {
                    id: radius
                    width: parent.width
                    from: root.boundOf("windowRadius", "min")
                    to: root.boundOf("windowRadius", "max")
                    formatValue: value => Math.round(value) + " px"
                    shown: radiusRow.shownValue === undefined ? 0 : radiusRow.shownValue
                    onSaved: value => root.answer(root.shell.appearance.set("windowRadius", Math.round(value)))
                }
            }

            ValueSourceRow {
                id: borderRow
                width: parent.width
                label: "Border width"
                themeOffered: true
                source: root.sourceOf("borderWidth")
                themeValue: root.themeOf("borderWidth")
                userValue: root.valueOf("borderWidth")
                hyprland: root.shell === null ? null : root.shell.hyprland
                path: root.pathOf("borderWidth")
                formatValue: value => value + " px"
                onUseHyprlandValue: root.answer(root.shell.appearance.set("borderWidth", "hyprland"))
                onUseThemeValue: root.answer(root.shell.appearance.unset("borderWidth"))
                onOpenHyprlandConfig: root.openHyprlandConfig()
                info: "Use my Hyprland value also keeps the border colours from your Hyprland config."
                SavedSlider {
                    width: parent.width
                    from: root.boundOf("borderWidth", "min")
                    to: root.boundOf("borderWidth", "max")
                    formatValue: value => Math.round(value) + " px"
                    shown: borderRow.shownValue === undefined ? 0 : borderRow.shownValue
                    onSaved: value => root.answer(root.shell.appearance.set("borderWidth", Math.round(value)))
                }
            }
        }

        Label {
            visible: root.problem !== ""
            width: parent.width
            role: "hint"
            color: Theme.color.danger
            text: root.problem
            wrapMode: Text.Wrap
        }
    }
}
