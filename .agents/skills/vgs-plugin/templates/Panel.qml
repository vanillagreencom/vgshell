import QtQuick
import qs.Commons
import qs.Ui

// __NAME__ panel: a summoned surface drawn inside the core's panel host.
// The host calls open(payloadJson) and close(); the plugin never creates
// a window. A payload that does not parse throws out of open(), and the
// host answers the summon with `refused: open-failed=<id>`. The panel
// composes the components of qs.Ui; sizes come from Theme. To open another declared kind here,
// pass its source Item to shell.surfaces.summon(kind, payloadJson, item);
// the compositor places it relative to this window.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    property var payload: ({})

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
    }

    function close() {}

    implicitWidth: Theme.size.panel.sm
    implicitHeight: layout.implicitHeight

    Surface {
        anchors.fill: parent
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: "__NAME__"

        Label {
            width: layout.contentWidth
            role: "body"
            text: "Panel content"
        }
    }
}
