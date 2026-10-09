import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// A slider whose value is saved on release, beside a reading of where it
// stands: a Slider from `from` to `to` that snaps to `stepSize`, and a
// Label `formatValue` writes. The slider follows `shown`, the saved value,
// while it is not held. A drag moves the slider and its reading alone; the
// release, a click on the track or a key emits `saved(value)` once, and
// only for a value other than the one shown. The rebound slider holds
// `shown` within its range, as Slider clamps value, so a press that moved
// nothing saves nothing, even over a saved value past the range. The
// slider ends `field.labelGap` before the reading, which is never narrower
// than `size.control.md`, so the sliders of a page end together. `slider`
// is the tab stop, for a page's initial focus.
Item {
    id: root

    // The inner slider keeps its field minimum beside the reading.
    readonly property real minimumWidth: bar.minimumWidth + Theme.field.labelGap + reading.width
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property real from: 0
    property real to: 1
    property real stepSize: 1
    property real shown: 0
    property var formatValue: value => String(value)
    readonly property Item slider: bar

    signal saved(real value)

    implicitWidth: minimumWidth
    implicitHeight: Math.max(bar.implicitHeight, reading.implicitHeight)

    function commit() {
        const wanted = bar.value;
        bar.value = Qt.binding(() => root.shown);
        if (wanted !== bar.value) root.saved(wanted);
    }

    Slider {
        id: bar
        width: reading.x - Theme.field.labelGap
        anchors.verticalCenter: parent.verticalCenter
        from: root.from
        to: root.to
        stepSize: root.stepSize
        snapMode: T.Slider.SnapAlways
        value: root.shown
        // Slider clamps a value to the range it holds when the value
        // arrives, so a range that arrives later, as a page's does with
        // its capability, takes the shown value again.
        onFromChanged: if (!pressed) value = Qt.binding(() => root.shown)
        onToChanged: if (!pressed) value = Qt.binding(() => root.shown)
        // Slider moves the value on its own keys with nothing held.
        onPressedChanged: if (!pressed) root.commit()
        onMoved: if (!pressed) root.commit()
    }

    Label {
        id: reading
        role: "label"
        text: root.formatValue(bar.value)
        width: Math.max(implicitWidth, Theme.size.control.md)
        horizontalAlignment: Text.AlignRight
        x: root.width - width
        anchors.verticalCenter: parent.verticalCenter
    }
}
