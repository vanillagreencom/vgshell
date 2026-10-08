import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Windows pane: the corner radius and the border width over the theme, each
// Set by theme until the user moves it. The corner radius is one base:
// windows take it, flyouts three quarters of it and grouped window tabs
// half of it (ThemeLogic.APPEARANCE_RATIOS). Both map to a Hyprland option,
// so each row also offers the user's own Hyprland value. A slider saves on
// release, and only a value it moved to.
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

    // A slider that saves on release, and only a value it moved to: the
    // rebound slider holds the shown value within its range, as Slider
    // clamps value, so a press that moved nothing saves nothing.
    component SavedSlider: Item {
        id: holder

        property real from: 0
        property real to: 1
        property real stepSize: 1
        property real shown: 0
        readonly property alias slider: control
        signal saved(real value)

        width: parent.width
        implicitHeight: Math.max(control.implicitHeight, reading.implicitHeight)

        function commit() {
            const wanted = control.value;
            control.value = Qt.binding(() => holder.shown);
            if (wanted !== control.value) holder.saved(wanted);
        }

        Slider {
            id: control
            width: parent.width - reading.width - Theme.field.labelGap
            anchors.verticalCenter: parent.verticalCenter
            from: holder.from
            to: holder.to
            stepSize: holder.stepSize
            snapMode: T.Slider.SnapAlways
            value: holder.shown
            onPressedChanged: if (!pressed) holder.commit()
            onMoved: if (!pressed) holder.commit()
        }

        Label {
            id: reading
            role: "label"
            text: Math.round(control.value) + " px"
            width: Math.max(implicitWidth, Theme.size.control.md)
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }
    }

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
                    from: 0
                    to: 32
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
                    from: 0
                    to: 20
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
