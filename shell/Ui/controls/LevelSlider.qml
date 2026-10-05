import QtQuick
import qs.Commons
import qs.Ui

// One level a user sets, such as a device's volume or a display's
// brightness: an IconButton, a Slider from 0 to 1 that the arrows move by
// `stepSize`, and a LevelLabel readout, `stack.inline` apart, the slider
// taking the width the button and the readout leave. The button's glyph,
// not its box, sits on the row's start edge, so it lines up with the
// controls above and below it; the box draws no fill, so hover and press
// change only the icon's colour, and it keeps its click target and focus
// ring. The slider follows `value` whenever it is not held, so a change
// made elsewhere moves it, and a drag in progress is never pulled back.
// `text` reads `value` as a percentage unless the caller names it, such as
// Muted, and a value above 1 reads as it is while the slider stands at its
// end. The button's `buttonLabel` names its action, Mute unless the caller
// names another, as an icon button needs. `began` fires when a drag
// starts, so a caller can keep what the drag changes; `moved(value)` hands
// each new share from a drag, a click or a key, and `buttonClicked` a
// press on the button. The button and the slider are each a tab stop.
Item {
    id: root

    property string iconName: ""
    property string buttonLabel: "Mute"
    property real value: 0
    property real stepSize: 0
    property string text: Math.round(value * 100) + "%"
    readonly property Item slider: bar
    readonly property int spacing: Theme.stack.inline

    signal began()
    signal moved(real value)
    signal buttonClicked()

    implicitHeight: Math.max(button.implicitHeight, bar.implicitHeight, readout.height)

    IconButton {
        id: button
        // Whole pixels, so the icon draws where IconButton centres it.
        x: -Math.round(glyphStart)
        anchors.verticalCenter: parent.verticalCenter
        iconName: root.iconName
        label: root.buttonLabel
        onClicked: root.buttonClicked()
        background: Item {
            implicitHeight: button.controlHeight
            FocusRing { target: button }
        }
    }

    Slider {
        id: bar
        x: button.x + button.width + root.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: readout.x - root.spacing - x
        from: 0
        to: 1
        stepSize: root.stepSize
        onPressedChanged: if (pressed) root.began()
        onMoved: root.moved(value)
    }

    Binding {
        target: bar
        property: "value"
        value: root.value
        when: !bar.pressed
        restoreMode: Binding.RestoreNone
    }

    LevelLabel {
        id: readout
        x: root.width - width
        anchors.verticalCenter: parent.verticalCenter
        height: lineBox
        text: root.text
    }
}
