import QtQuick
import qs.Commons
import qs.Ui

// UI pane: the corner radius of buttons, text fields and segmented
// controls over the theme, Set by theme until the user moves it, with a
// preview of the three. Bar items and checkboxes keep the theme's. The
// slider runs between the bounds the `appearance` capability lends.
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
        if (reply !== "ok") console.warn("ui: appearance " + reply);
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        SectionHeader {
            width: parent.width
            text: "Controls"
            description: "Set the corners of buttons and inputs."
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            ValueSourceRow {
                id: radiusRow
                width: parent.width
                label: "Corner radius"
                themeOffered: true
                source: root.appearance === null ? "theme" : root.appearance.sources.controlRadius
                themeValue: root.appearance === null ? 0 : root.appearance.theme.controlRadius
                userValue: root.appearance === null ? undefined : root.appearance.values.controlRadius
                formatValue: value => value + " px"
                onUseThemeValue: root.answer(root.shell.appearance.unset("controlRadius"))

                SavedSlider {
                    id: radius
                    width: parent.width
                    from: root.appearance === null ? 0 : root.appearance.keys.controlRadius.min
                    to: root.appearance === null ? 0 : root.appearance.keys.controlRadius.max
                    formatValue: value => Math.round(value) + " px"
                    shown: radiusRow.shownValue === undefined ? 0 : radiusRow.shownValue
                    onSaved: value => root.answer(root.shell.appearance.set("controlRadius", Math.round(value)))
                }
            }
        }

        SectionHeader {
            width: parent.width
            text: "Preview"
            description: "These controls use the corner radius above."
        }

        Row {
            id: preview
            spacing: Theme.stack.inline

            Button { text: "Button" }
            TextField { placeholderText: "Text field" }
            SegmentedControl { model: ["One", "Two"]; currentIndex: 0 }
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
