import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: root
    property string title: ""
    property string iconName: ""
    property string reading: ""
    property var value: null
    property string tone: "accent"
    property string description: ""
    property var details: []
    spacing: Theme.stack.row

    Row {
        width: parent.width
        spacing: Theme.stack.inline
        Icon { name: root.iconName; size: Theme.icon.size.sm; anchors.verticalCenter: parent.verticalCenter }
        Label { role: "bodyStrong"; text: root.title; width: parent.width - x - readingLabel.implicitWidth - parent.spacing; elide: Text.ElideRight }
        Label { id: readingLabel; role: "value"; text: root.reading }
    }
    Label { visible: text !== ""; width: parent.width; role: "hint"; text: root.description; wrapMode: Text.WordWrap }
    ProgressBar { width: parent.width; from: 0; to: 100; value: typeof root.value === "number" ? root.value : 0; tone: root.tone }
    // The numeric model keeps each position's Label alive while a new
    // sample updates its text. The Qt unit identity check reaches this.
    Repeater {
        model: root.details.length
        Label {
            required property int index
            width: root.width
            role: "hint"
            text: root.details[index]
            wrapMode: Text.WordWrap
        }
    }
}
