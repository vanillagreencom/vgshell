import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// UI pane: the corner radius of buttons, text fields and segmented
// controls over the theme, Set by theme until the user moves it, with a
// preview of the three. Bar items and checkboxes keep the theme's. The
// slider saves on release, and only a value it moved to.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var appearance: shell === null ? null : shell.appearance
    readonly property Item initialFocus: radius

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

                Item {
                    id: radiusHolder
                    width: parent.width
                    implicitHeight: Math.max(radius.implicitHeight, radiusValue.implicitHeight)

                    // The rebound slider holds the shown value within its
                    // range, as Slider clamps value, so a press that moved
                    // nothing saves nothing.
                    function commit() {
                        const wanted = radius.value;
                        radius.value = Qt.binding(() => radiusRow.shownValue === undefined ? 0 : radiusRow.shownValue);
                        if (wanted !== radius.value) root.answer(root.shell.appearance.set("controlRadius", Math.round(wanted)));
                    }

                    Slider {
                        id: radius
                        width: parent.width - radiusValue.width - Theme.field.labelGap
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: 16
                        stepSize: 1
                        snapMode: T.Slider.SnapAlways
                        value: radiusRow.shownValue === undefined ? 0 : radiusRow.shownValue
                        onPressedChanged: if (!pressed) radiusHolder.commit()
                        onMoved: if (!pressed) radiusHolder.commit()
                    }

                    Label {
                        id: radiusValue
                        role: "label"
                        text: Math.round(radius.value) + " px"
                        width: Math.max(implicitWidth, Theme.size.control.md)
                        horizontalAlignment: Text.AlignRight
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
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
