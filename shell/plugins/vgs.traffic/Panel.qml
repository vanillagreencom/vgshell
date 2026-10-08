import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import QtQuick.Templates as T
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
    readonly property int kbDigits: shell === null ? 0 : shell.settings.kbDecimals
    readonly property int mbDigits: shell === null ? 1 : shell.settings.mbDecimals
    property string sortKey: "down"
    property bool ascending: false
    // The selected row by its key, so a sample that reorders the rows
    // keeps the selection on the same app.
    property string currentKey: ""
    readonly property int current: rows.findIndex(row => row.key === currentKey)
    // A status write of any plugin hands out a new copy of `traffic`, so
    // this list is a new array at least once a sample; the rows' keyed
    // model turns each one into changes of the rows that differ.
    readonly property var rows: {
        const term = search.text.toLowerCase();
        const apps = (traffic.apps || []).filter(row => row.name.toLowerCase().includes(term))
            .map(row => ({ key: "app:" + row.name, name: row.name, down: row.down, up: row.up, connections: row.connections, other: false }));
        apps.sort((a, b) => {
            const value = sortKey === "name" ? a.name.localeCompare(b.name) : a[sortKey] - b[sortKey];
            return ascending ? value : -value;
        });
        if (traffic.state === "ready" && traffic.other !== undefined) apps.push({ key: "other", name: "Other traffic", down: traffic.other.down, up: traffic.other.up, connections: null, other: true });
        return apps;
    }
    readonly property string emptyText: traffic.state === "unknown" ? "Traffic could not be read" : traffic.state === "measuring" || traffic.state === undefined ? "Measuring network traffic…" : search.text !== "" ? "No matching apps" : "No network activity"
    readonly property bool emptyShown: traffic.state !== "ready" || (search.text !== "" && rows.every(row => row.other))
    // The row whose actions are open: null, or `{ serial, key, name, mode,
    // byKey, app, next }`: `serial` new for each overlay, `mode` `menu`,
    // `inspect` or `kill`, `byKey` whether a key opened it, `app` the
    // service's inspect answer for an Inspect or a Kill, and `next` the mode
    // an action chose to open once this overlay closes. That row builds the
    // overlay and drops it when this moves on.
    property var acting: null
    property int actingSerial: 0
    // The app whose last kill request the service refused, for the note.
    property string refusedName: ""
    readonly property var ending: traffic.ending === undefined ? null : traffic.ending
    readonly property string endNote: refusedName !== "" ? "Could not kill " + refusedName + ". Try again."
        : ending === null || ending.state === "running" ? ""
        : ending.state === "sent" ? ending.name + " got a request to quit."
        : "Could not kill " + ending.name + "."
    implicitWidth: Theme.size.window.width
    implicitHeight: layout.implicitHeight

    function rate(value) { return Logic.formatRate(value, kbDigits, mbDigits); }

    property bool leased: false
    function open(payloadJson) {
        search.text = ""; currentKey = ""; acting = null; refusedName = "";
        if (shell !== null && !leased) leased = shell.ipc.call("lease", JSON.stringify({ id: String(root), open: true, kind: "panel" })) === "ok";
    }
    function close() {
        acting = null;
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

    // Open `mode` for `row`, answering whether it opened. Inspect and Kill
    // read the app's processes and connections from the service's newest
    // sample first.
    function act(row, mode, byKey) {
        if (row === undefined || row.other) return false;
        let app = null;
        if (mode !== "menu") {
            const reply = shell.ipc.call("inspect", JSON.stringify({ name: row.name }));
            if (!reply.startsWith("{")) { console.warn("traffic: inspect " + reply); return false; }
            app = JSON.parse(reply);
        }
        actingSerial++;
        acting = { serial: actingSerial, key: row.key, name: row.name, mode: mode, byKey: byKey, app: app, next: "" };
        return true;
    }
    // The overlay `request` opened closed: open the next one its action
    // chose, else hand the keyboard back to the list a key opened it from.
    // It runs a turn later, so the menu's grab ends before the dialog takes
    // its own, and no overlay is destroyed while it emits.
    function settle(request) {
        if (acting === null || acting.serial !== request.serial) return;
        if (request.next !== "" && act(request, request.next, request.byKey)) return;
        acting = null;
        if (request.byKey) appList.forceActiveFocus(Qt.TabFocusReason);
    }
    function overlayOf(mode) { return mode === "menu" ? actionMenu : mode === "inspect" ? inspectView : killView; }
    function kill(app) {
        const reply = shell.ipc.call("kill", JSON.stringify({ name: app.name, pids: app.pids }));
        refusedName = reply === "ok" ? "" : app.name;
        if (reply !== "ok") console.warn("traffic: kill " + reply);
        return reply;
    }
    onRowsChanged: if (acting !== null && !rows.some(row => row.key === acting.key)) acting = null

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
                Label { role: "h3"; text: "↓ " + root.rate(root.traffic.down) }
            }
            Column {
                spacing: Theme.row.lineGap
                Label { role: "hint"; text: "Upload" }
                Label { role: "h3"; text: "↑ " + root.rate(root.traffic.up) }
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
            TextMetrics { id: rateSize; font.family: Theme.text.itemCode.family; font.pixelSize: Theme.text.itemCode.size; text: Logic.rateSample(root.kbDigits, root.mbDigits) }
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
            T.Control {
                id: appList
                focusPolicy: Qt.StrongFocus
                Accessible.role: Accessible.List
                Accessible.name: "Network traffic applications"
                width: parent.width
                implicitHeight: entries.implicitHeight
                visible: !root.emptyShown
                activeFocusOnTab: true
                // focus-indicator: the list's shared FocusRing
                FocusRing { target: appList }
                onActiveFocusChanged: if (activeFocus && root.current < 0 && root.rows.length > 0) root.currentKey = root.rows[0].key
                Keys.onPressed: event => { if (navigation.handle(event)) event.accepted = true; }
                KeyNav {
                    id: navigation
                    focusTarget: appList
                    count: root.rows.length
                    currentIndex: root.current
                    cursor: listCursor
                    onMoved: index => root.currentKey = root.rows[index].key
                    // Enter and the menu key open the row's actions; Delete
                    // asks to kill its app.
                    onActivated: index => root.act(root.rows[index], "menu", true)
                    onMenuRequested: index => root.act(root.rows[index], "menu", true)
                    onRemoved: index => root.act(root.rows[index], "kill", true)
                }
                // The rows' cursor, beside their column: a positioner would
                // lay the plate out as a row and push every row down.
                ListCursor { id: listCursor }
                Column {
                    id: entries
                    width: parent.width
                    Repeater {
                        // Keyed by app, so a sample changes each row in place
                        // and a sort moves rows; a plain array rebuilds every
                        // row, and each rebuilt row enters again from
                        // nothing. https://quickshell.org/docs/v0.3.1/types/Quickshell/ScriptModel
                        model: ScriptModel { values: root.rows; objectProp: "key" }
                        ListItem {
                            id: entry
                            required property var modelData
                            required property int index
                            width: entries.width
                            text: modelData.name
                            cursor: listCursor
                            highlighted: root.current === index && appList.activeFocus
                            onPointed: root.currentKey = modelData.key
                            onClicked: {
                                root.currentKey = modelData.key;
                                appList.focusReason = Qt.MouseFocusReason;
                                root.act(modelData, "menu", false);
                            }
                            contentItem: RowLayout {
                                spacing: 0
                                Label { role: "item"; text: entry.modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { role: "itemCode"; text: root.rate(entry.modelData.down); horizontalAlignment: Text.AlignRight; Layout.preferredWidth: table.rateWidth }
                                Label { role: "itemCode"; text: root.rate(entry.modelData.up); horizontalAlignment: Text.AlignRight; Layout.preferredWidth: table.rateWidth }
                                Label { role: "itemCode"; text: entry.modelData.connections === null ? "--" : String(entry.modelData.connections); horizontalAlignment: Text.AlignRight; Layout.preferredWidth: table.connectionsWidth }
                            }
                            // The open overlay of this row, anchored under it,
                            // built with its request so no binding in it reads
                            // a request that moved on.
                            property var overlay: null
                            readonly property var request: root.acting !== null && root.acting.key === modelData.key ? root.acting : null
                            onRequestChanged: {
                                if (overlay !== null) overlay.destroy();
                                overlay = request === null ? null : root.overlayOf(request.mode).createObject(entry, { request: request });
                            }
                            Component.onDestruction: if (overlay !== null) overlay.destroy()
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
            visible: root.endNote !== ""
            role: "hint"
            wrapMode: Text.Wrap
            text: root.endNote
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

    // A trigger closes its menu, which settles the request into the mode
    // the trigger chose.
    Component {
        id: actionMenu
        Menu {
            required property var request
            Component.onCompleted: Qt.callLater(open)
            onOpenedChanged: if (!opened) Qt.callLater(root.settle, request)
            MenuItem { text: "Inspect"; iconName: "scan-search"; onTriggered: request.next = "inspect" }
            MenuItem { text: "Kill"; iconName: "octagon-x"; onTriggered: request.next = "kill" }
        }
    }

    // The one card of an Inspect or a Kill: the popover draws the frame,
    // and this its title, message, content and actions, flush right. The
    // popover focuses the first action as it opens, Tab moves between the
    // actions, and Escape or a press outside closes it.
    component ActionCard: Column {
        id: card
        property string title: ""
        property string message: ""
        property string cancelText: ""
        default property alias content: body.data
        signal cancelled()
        signal killed()
        width: parent.width
        spacing: Theme.dialog.gap
        Label { width: parent.width; role: Theme.dialog.titleRole; text: card.title; textFormat: Text.PlainText; wrapMode: Text.Wrap }
        Label { width: parent.width; role: Theme.dialog.bodyRole; text: card.message; textFormat: Text.PlainText; wrapMode: Text.Wrap }
        Column {
            id: body
            width: parent.width
            spacing: Theme.stack.row
            visible: children.length > 0
        }
        Item {
            width: parent.width
            implicitHeight: actions.implicitHeight
            Row {
                id: actions
                anchors.right: parent.right
                spacing: Theme.dialog.actionGap
                Button { text: card.cancelText; variant: "tertiary"; onClicked: card.cancelled() }
                Button { text: "Kill"; variant: "danger"; onClicked: card.killed() }
            }
        }
    }

    Component {
        id: inspectView
        Popover {
            id: pop
            required property var request
            readonly property var app: request.app
            width: OverlayState.widthFor(anchorItem, Theme.dialog.width)
            Component.onCompleted: Qt.callLater(() => open(request.byKey ? Qt.TabFocusReason : Qt.MouseFocusReason))
            onOpenedChanged: if (!opened) Qt.callLater(root.settle, request)
            ActionCard {
                title: pop.app.name
                message: (pop.app.pids.length === 1 ? "1 process" : pop.app.pids.length + " processes") + ", "
                    + (pop.app.connectionCount === 1 ? "1 connection" : pop.app.connectionCount + " connections")
                cancelText: "Close"
                onCancelled: pop.close()
                onKilled: {
                    pop.request.next = "kill";
                    pop.close();
                }
                Label { role: "label"; text: "Processes" }
                Repeater {
                    model: pop.app.pids.slice(0, Logic.INSPECT_ROWS)
                    RowLayout {
                        id: process
                        required property int modelData
                        property string line: ""
                        width: parent.width
                        spacing: Theme.stack.inline
                        Label { role: "itemCode"; text: String(process.modelData) }
                        Label { role: "hint"; text: process.line === "" ? "--" : process.line; textFormat: Text.PlainText; elide: Text.ElideRight; Layout.fillWidth: true }
                        // One read as Inspect opens; nothing watches the file.
                        FileView {
                            path: "/proc/" + process.modelData + "/cmdline"
                            blockLoading: false
                            onLoaded: process.line = Logic.commandLine(text())
                        }
                    }
                }
                Label {
                    visible: pop.app.pids.length > Logic.INSPECT_ROWS
                    role: "hint"
                    text: "And " + (pop.app.pids.length - Logic.INSPECT_ROWS) + " more"
                }
                Label { role: "label"; text: "Connections" }
                Repeater {
                    model: pop.app.connections
                    RowLayout {
                        required property var modelData
                        width: parent.width
                        spacing: Theme.stack.inline
                        Label { role: "itemCode"; text: modelData.peer; textFormat: Text.PlainText; elide: Text.ElideMiddle; Layout.fillWidth: true }
                        Label { role: "hint"; text: Logic.connectionState(modelData.state) }
                    }
                }
                Label {
                    visible: pop.app.connectionCount > pop.app.connections.length
                    role: "hint"
                    text: "And " + (pop.app.connectionCount - pop.app.connections.length) + " more"
                }
            }
        }
    }

    Component {
        id: killView
        Popover {
            id: pop
            required property var request
            readonly property var app: request.app
            width: OverlayState.widthFor(anchorItem, Theme.dialog.width)
            Component.onCompleted: Qt.callLater(() => open(request.byKey ? Qt.TabFocusReason : Qt.MouseFocusReason))
            onOpenedChanged: if (!opened) Qt.callLater(root.settle, request)
            ActionCard {
                title: "Kill " + pop.app.name + "?"
                message: pop.app.name + " gets a request to quit. Work it did not save can be lost."
                cancelText: "Cancel"
                onCancelled: pop.close()
                onKilled: {
                    root.kill(pop.app);
                    pop.close();
                }
                Label {
                    width: parent.width
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: (pop.app.pids.length === 1 ? "Process " : "Processes ") + pop.app.pids.slice(0, Logic.INSPECT_ROWS).join(", ")
                        + (pop.app.pids.length > Logic.INSPECT_ROWS ? " and " + (pop.app.pids.length - Logic.INSPECT_ROWS) + " more" : "")
                }
            }
        }
    }
}
