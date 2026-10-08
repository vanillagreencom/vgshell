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
    Repeater { model: root.details; Label { required property string modelData; width: root.width; role: "hint"; text: modelData; wrapMode: Text.WordWrap } }
}
