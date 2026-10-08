import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Motion pane: one motion choice over the theme, Motion, Style and Speed,
// each Set by theme until the user changes it, for the shell and for the
// windows Hyprland moves. Window animations is the one split (D054):
// Hyprland has a source the shell lacks, the user's own animations in
// their Hyprland config, which VGS keeps until the user turns it on. A
// slider saves on release, and only a value it moved to.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var appearance: shell === null ? null : shell.appearance
    readonly property var styles: ["smooth", "snappy"]
    readonly property var styleNames: ({ smooth: "Smooth", snappy: "Snappy", none: "None" })
    readonly property Item initialFocus: motionSwitch

    function open(payloadJson) {}
    function close() {}

    function answer(reply) {
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("motion: appearance " + reply);
    }

    function openHyprlandConfig() {
        const reply = shell.tui.edit("hypr/hyprland.lua");
        if (reply !== "ok") console.warn("motion: edit " + reply);
    }

    function speedText(value) {
        return Number(value).toFixed(2) + "×";
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    // Where Appearance value KEY comes from, the theme's value and the
    // user's, as the `appearance` capability lends them.
    function sourceOf(key) { return appearance === null ? "theme" : appearance.sources[key]; }
    function themeOf(key) { return appearance === null ? undefined : appearance.theme[key]; }
    function valueOf(key) { return appearance === null ? undefined : appearance.values[key]; }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        SectionHeader {
            width: parent.width
            text: "Motion"
            description: "Set how the shell and your windows move."
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            ValueSourceRow {
                id: motionRow
                width: parent.width
                label: "Motion"
                themeOffered: true
                source: root.sourceOf("motion")
                themeValue: root.themeOf("motion")
                userValue: root.valueOf("motion")
                onUseThemeValue: root.answer(root.shell.appearance.unset("motion"))
                formatValue: value => value === true ? "on" : "off"
                Switch {
                    id: motionSwitch
                    size: "sm"
                    Accessible.name: "Motion"
                    checked: motionRow.shownValue === true
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => motionRow.shownValue === true);
                        root.answer(root.shell.appearance.set("motion", wanted));
                    }
                }
            }

            ValueSourceRow {
                id: styleRow
                width: parent.width
                label: "Style"
                themeOffered: true
                source: root.sourceOf("motionStyle")
                themeValue: root.themeOf("motionStyle")
                userValue: root.valueOf("motionStyle")
                onUseThemeValue: root.answer(root.shell.appearance.unset("motionStyle"))
                formatValue: value => root.styleNames[value] || String(value)
                SegmentedControl {
                    model: root.styles.map(style => root.styleNames[style])
                    currentIndex: root.styles.indexOf(styleRow.shownValue)
                    onActivated: index => root.answer(root.shell.appearance.set("motionStyle", root.styles[index]))
                }
            }

            ValueSourceRow {
                id: speedRow
                width: parent.width
                label: "Speed"
                themeOffered: true
                source: root.sourceOf("motionSpeed")
                themeValue: root.themeOf("motionSpeed")
                userValue: root.valueOf("motionSpeed")
                onUseThemeValue: root.answer(root.shell.appearance.unset("motionSpeed"))
                formatValue: value => root.speedText(value)
                Item {
                    id: speedHolder
                    width: parent.width
                    implicitHeight: Math.max(speed.implicitHeight, speedValue.implicitHeight)

                    // The rebound slider holds the shown value within its
                    // range, as Slider clamps value, so a press that moved
                    // nothing saves nothing.
                    function commit() {
                        const wanted = speed.value;
                        speed.value = Qt.binding(() => speedRow.shownValue === undefined ? 1 : speedRow.shownValue);
                        if (wanted !== speed.value) root.answer(root.shell.appearance.set("motionSpeed", wanted));
                    }

                    Slider {
                        id: speed
                        width: parent.width - speedValue.width - Theme.field.labelGap
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0.5
                        to: 2
                        stepSize: 0.25
                        snapMode: T.Slider.SnapAlways
                        value: speedRow.shownValue === undefined ? 1 : speedRow.shownValue
                        onPressedChanged: if (!pressed) speedHolder.commit()
                        onMoved: if (!pressed) speedHolder.commit()
                    }

                    Label {
                        id: speedValue
                        role: "label"
                        text: root.speedText(speed.value)
                        width: Math.max(implicitWidth, Theme.size.control.md)
                        horizontalAlignment: Text.AlignRight
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            ValueSourceRow {
                id: windowsRow
                width: parent.width
                label: "Window animations"
                info: "On: Hyprland moves your windows with the motion above. Off: Hyprland keeps the window animations from your own Hyprland config."
                source: root.appearance === null ? "hyprland" : root.sourceOf("windowAnimations")
                userValue: true
                hyprland: root.shell === null ? null : root.shell.hyprland
                path: root.appearance === null ? "" : root.appearance.keys.windowAnimations.hyprland
                formatValue: value => value === true ? "on" : "off"
                onUseHyprlandValue: root.answer(root.shell.appearance.unset("windowAnimations"))
                onOpenHyprlandConfig: root.openHyprlandConfig()
                Switch {
                    size: "sm"
                    Accessible.name: "Use these settings for windows"
                    text: "Use these settings for windows"
                    checked: windowsRow.source === "user"
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => windowsRow.source === "user");
                        root.answer(wanted ? root.shell.appearance.set("windowAnimations", true) : root.shell.appearance.unset("windowAnimations"));
                    }
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
