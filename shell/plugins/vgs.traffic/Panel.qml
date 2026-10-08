import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "TrafficLogic.js" as Logic

Item {
    id: root
    property var shell: null
    readonly property Item initialFocus: search
    readonly property var traffic: shell === null ? ({}) : shell.status.values.traffic || ({})
    readonly property var capture: shell === null ? ({}) : shell.status.values.capture || ({})
    readonly property bool footShown: traffic.bandwhich === true
    property string sortKey: "down"
    property bool ascending: false
    property int current: -1
    readonly property var rows: {
        const term = search.text.toLowerCase();
        const apps = (traffic.apps || []).filter(row => row.name.toLowerCase().includes(term)).slice();
        apps.sort((a, b) => {
            const value = sortKey === "name" ? a.name.localeCompare(b.name) : a[sortKey] - b[sortKey];
            return ascending ? value : -value;
        });
        if (traffic.state === "ready" && traffic.other !== undefined) apps.push({ name: "Other traffic", down: traffic.other.down, up: traffic.other.up, connections: null, other: true });
        return apps;
    }
    readonly property string emptyText: traffic.state === "unknown" ? "Traffic could not be read" : traffic.state === "measuring" || traffic.state === undefined ? "Measuring network traffic…" : search.text !== "" ? "No matching apps" : "No network activity"
    readonly property bool emptyShown: traffic.state !== "ready" || (search.text !== "" && rows.every(row => row.other))
    implicitWidth: Theme.size.window.width
    implicitHeight: layout.implicitHeight

    property bool leased: false
    function open(payloadJson) {
        search.text = ""; current = -1;
        if (shell !== null && !leased) leased = shell.ipc.call("lease", JSON.stringify({ id: String(root), open: true, kind: "panel" })) === "ok";
    }
    function close() {
        if (leased && shell !== null) shell.ipc.call("lease", JSON.stringify({ id: String(root), open: false }));
        leased = false;
    }
    Component.onDestruction: close()
    function sort(key) {
        ascending = sortKey === key ? !ascending : key === "name";
        sortKey = key;
    }
    function seeAll() {
        const reply = capture.action ? shell.status.act("capture") : shell.tui.run("bandwhich");
        if (reply !== "ok" && reply !== "refused: tui=bandwhich reason=busy") console.warn("traffic: see-all " + reply);
        return reply;
    }

    Surface { anchors.fill: parent }
    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        title: "Network Traffic"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight

        RowLayout {
            width: layout.contentWidth
            spacing: Theme.stack.section
            Column {
                spacing: Theme.row.lineGap
                Label { role: "hint"; text: "Download" }
                Label { role: "h3"; text: "↓ " + Logic.formatRate(root.traffic.down) }
            }
            Column {
                spacing: Theme.row.lineGap
                Label { role: "hint"; text: "Upload" }
                Label { role: "h3"; text: "↑ " + Logic.formatRate(root.traffic.up) }
            }
            Item { Layout.fillWidth: true }
            Label { role: "hint"; text: (root.traffic.apps || []).length + " apps" }
        }
        TextField {
            id: search
            width: Math.min(layout.contentWidth, Theme.size.panel.md)
            leadingIcon: "search"
            placeholderText: "Search apps"
            Keys.onEscapePressed: event => {
                if (text !== "") { text = ""; event.accepted = true; }
                else event.accepted = false;
            }
        }
        Column {
            id: table
            width: layout.contentWidth
            spacing: Theme.row.lineGap
            readonly property real rateWidth: Math.max(rateSize.width + Theme.stack.inline, downloadHeader.implicitWidth, uploadHeader.implicitWidth)
            readonly property real connectionsWidth: Math.max(connectionsSize.width + Theme.stack.inline, connectionsHeader.implicitWidth)
            TextMetrics { id: rateSize; font.family: Theme.text.itemCode.family; font.pixelSize: Theme.text.itemCode.size; text: "888.8 MB/s" }
            TextMetrics { id: connectionsSize; font.family: Theme.text.button.family; font.pixelSize: Theme.text.button.size; text: "CONNECTIONS" }
            RowLayout {
                x: Theme.listItem.paddingX
                width: parent.width - 2 * Theme.listItem.paddingX
                spacing: 0
                Button { Layout.fillWidth: true; text: "Application"; iconName: root.sortKey === "name" ? root.ascending ? "chevron-up" : "chevron-down" : ""; size: "sm"; variant: "ghost"; onClicked: root.sort("name") }
                Button { id: downloadHeader; Layout.preferredWidth: table.rateWidth; text: "Download"; iconName: root.sortKey === "down" ? root.ascending ? "chevron-up" : "chevron-down" : ""; size: "sm"; variant: "ghost"; onClicked: root.sort("down") }
                Button { id: uploadHeader; Layout.preferredWidth: table.rateWidth; text: "Upload"; iconName: root.sortKey === "up" ? root.ascending ? "chevron-up" : "chevron-down" : ""; size: "sm"; variant: "ghost"; onClicked: root.sort("up") }
                Button { id: connectionsHeader; Layout.preferredWidth: table.connectionsWidth; text: "Connections"; iconName: root.sortKey === "connections" ? root.ascending ? "chevron-up" : "chevron-down" : ""; size: "sm"; variant: "ghost"; onClicked: root.sort("connections") }
            }
            Divider { width: parent.width }
            FocusScope {
                id: appList
                width: parent.width
                implicitHeight: entries.implicitHeight
                visible: !root.emptyShown
                activeFocusOnTab: true
                // focus-indicator: the list's shared FocusRing
                FocusRing { target: appList }
                onActiveFocusChanged: if (activeFocus && root.current < 0 && root.rows.length > 0) root.current = 0
                Keys.onPressed: event => { if (navigation.handle(event)) event.accepted = true; }
                KeyNav {
                    id: navigation
                    count: root.rows.length
                    currentIndex: root.current
                    cursor: listCursor
                    onMoved: index => root.current = index
                }
                Column {
                    id: entries
                    width: parent.width
                    ListCursor { id: listCursor }
                    Repeater {
                        model: root.rows
                        ListItem {
                            id: entry
                            required property var modelData
                            required property int index
                            width: entries.width
                            text: modelData.name
                            cursor: listCursor
                            highlighted: root.current === index && appList.activeFocus
                            onPointed: root.current = index
                            onClicked: { root.current = index; appList.forceActiveFocus(Qt.MouseFocusReason); }
                            contentItem: RowLayout {
                                spacing: 0
                                Label { role: "item"; text: entry.modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { role: "itemCode"; text: Logic.formatRate(entry.modelData.down); horizontalAlignment: Text.AlignRight; Layout.preferredWidth: table.rateWidth }
                                Label { role: "itemCode"; text: Logic.formatRate(entry.modelData.up); horizontalAlignment: Text.AlignRight; Layout.preferredWidth: table.rateWidth }
                                Label { role: "itemCode"; text: entry.modelData.connections === null ? "--" : String(entry.modelData.connections); horizontalAlignment: Text.AlignRight; Layout.preferredWidth: table.connectionsWidth }
                            }
                        }
                    }
                }
            }
            Column {
                width: parent.width
                visible: root.emptyShown
                spacing: Theme.stack.group
                topPadding: Theme.stack.section
                bottomPadding: Theme.stack.section
                Spinner { anchors.horizontalCenter: parent.horizontalCenter; visible: root.traffic.state === "measuring" }
                Icon { anchors.horizontalCenter: parent.horizontalCenter; visible: root.traffic.state !== "measuring"; name: search.text !== "" ? "search" : "activity"; size: Theme.icon.size.lg; color: Theme.color.textMuted }
                Label { width: parent.width; text: root.emptyText; horizontalAlignment: Text.AlignHCenter; role: "body" }
            }
        }
        Label {
            width: layout.contentWidth
            role: "hint"
            wrapMode: Text.Wrap
            text: "Apps show their TCP traffic. Other traffic holds UDP, system services and other accounts."
        }
        footer: [
            Column {
                width: layout.contentWidth
                visible: root.footShown
                height: visible ? implicitHeight : 0
                spacing: Theme.stack.inline
                Label { width: parent.width; visible: !!root.capture.action; text: "See all needs traffic capture access"; role: "hint" }
                Button { width: parent.width; text: root.capture.action ? "Allow" : "See all"; enabled: root.capture.action || root.capture.tone === "ok"; variant: "tertiary"; iconName: root.capture.action ? "shield-check" : "external-link"; onClicked: root.seeAll() }
            }
        ]
    }
}
