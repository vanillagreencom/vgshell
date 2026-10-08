import QtQuick
Item {
    property var shell: null
    property string output: ""
    readonly property bool hasContent: preview.item !== null && preview.item.hasContent
    function open(payloadJson) { output = JSON.parse(payloadJson).output; }
    function close() {}
    implicitWidth: 320
    implicitHeight: 180
    Loader {
        id: preview
        anchors.fill: parent
        sourceComponent: parent.shell === null ? null : parent.shell.screencopy.preview
        onLoaded: item.output = Qt.binding(() => parent.output)
    }
}
