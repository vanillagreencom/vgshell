import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// A multi-line text input. It uses the same outline, selection and
// typography tokens as TextField, while the caller owns its height, and
// draws `placeholderText` while it is empty.
// `minimumHeight` floors its implicit height, three large controls by
// default; 0 starts it at one line, and it grows with its text. Its
// frame is a FieldFrame. A `framed: false` area stands inside a box that
// holds more than its text, as a message box's text does beside its own
// choices and Send: that box draws the area's FieldFrame around it all,
// and the area draws none and spans the width its caller gives it,
// without the form width cap. A set
// `disabledReason` disables it as it disables a Button: it stays a Tab
// stop, is read-only, draws its text and frame faded and shows the reason
// on hover and keyboard focus (DisabledReason).
T.TextArea {
    id: root

    property bool framed: true
    property real minimumHeight: Theme.size.control.lg * 3
    property string disabledReason: ""
    readonly property DisabledReason lock: lockState
    readonly property real minimumWidth: framed ? Theme.field.minWidth : 0
    readonly property real maximumWidth: framed ? Theme.control.maxWidth : Infinity
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property bool error: false
    readonly property color outline: frame.outline

    implicitWidth: Theme.size.panel.sm
    implicitHeight: Math.max(minimumHeight, contentHeight + topPadding + bottomPadding)
    leftPadding: Theme.textField.paddingX
    rightPadding: Theme.textField.paddingX
    topPadding: Theme.textField.paddingX
    bottomPadding: Theme.textField.paddingX
    hoverEnabled: !lockState.locked
    readOnly: lockState.locked
    opacity: enabled ? 1 : Theme.opacity.disabled
    color: lockState.faded(Theme.color.text)
    placeholderTextColor: lockState.faded(Theme.textField.placeholder)
    selectionColor: Theme.textField.selection
    selectedTextColor: Theme.textField.selectedText
    font.family: Theme.text.body.family
    font.pixelSize: Theme.text.body.size
    font.weight: Theme.text.body.weight
    font.variableAxes: ({ wght: Theme.text.body.weight })
    wrapMode: TextEdit.Wrap
    Accessible.name: placeholderText

    background: FieldFrame { id: frame; target: root; visible: root.framed }

    // The template holds `placeholderText` and draws none; the area draws
    // it where its first line starts, in its own font, while it is empty.
    Label {
        visible: root.text === "" && root.preeditText === ""
        x: root.leftPadding
        y: root.topPadding
        width: Math.max(0, root.width - root.leftPadding - root.rightPadding)
        role: "body"
        text: root.placeholderText
        color: root.placeholderTextColor
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    DisabledReason { id: lockState; control: root }
}
