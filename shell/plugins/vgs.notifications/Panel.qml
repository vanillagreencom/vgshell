import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Appearance.js" as Appearance
import "NotificationLogic.js" as Logic

// The keyboard inbox and history panel. The service remains the only owner
// of notification state; this summoned panel reads snapshots and sends
// choices back through the plugin's IPC handlers.
FocusScope {
    id: root

    property var shell: null
    readonly property int statusRevision: shell === null ? 0 : shell.status.revision
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    // The notifications' own VGlass choice, the `glass` setting, which the
    // header and every card hand their glass.
    readonly property bool glassChoice: shell !== null && shell.settings.glass === true
    property string mode: "inbox"
    property string subtitle: ""
    property bool silenced: false
    property var rows: []
    readonly property int rowCount: rows.length
    property int currentIndex: 0
    property int actionIndex: -1
    property string selectedKey: ""
    property string selectedHoverKey: ""
    property bool opened: false
    property bool refreshing: false
    property int refreshQueuedFor: -1
    property Item initialFocus: list
    // InboxHeader owns this panel's Settings gear.
    readonly property Item settingsHost: parent

    // As wide as the column: the cards with their side room, where the
    // scroll bar sits, wider than the header they sit under.
    implicitWidth: Math.max(header.implicitWidth, listScroll.implicitWidth) + 2 * column.contentInset
    readonly property real panelMaxHeight: column.contentInset + look.header.height + Math.max(column.headerBodyGap, column.stickyGap) + look.panel.rowCap * (look.card.maxHeight + look.card.gap) + look.stack.tail
    implicitHeight: Math.min(column.contentInset + column.headerHeight + listScroll.implicitHeight, panelMaxHeight)

    onCurrentIndexChanged: {
        if (refreshing) return;
        const row = rowAt(currentIndex);
        const key = row === null ? "" : row.key;
        if (selectedKey !== key) {
            selectedKey = key;
            actionIndex = -1;
        }
        actionIndex = -1;
        updateSelectionHover();
        revealRow(currentIndex);
    }

    onStatusRevisionChanged: {
        if (opened) scheduleRefresh();
    }

    function scheduleRefresh() {
        if (refreshQueuedFor === statusRevision) return;
        refreshQueuedFor = statusRevision;
        Qt.callLater(() => {
            const queued = refreshQueuedFor;
            refreshQueuedFor = -1;
            if (opened && statusRevision === queued) refresh();
        });
    }

    // A window that takes the keyboard closes the panel; a layer that takes
    // it, such as a capture's selector, closes nothing. Hyprland posts
    // activewindowv2 when a window takes the keyboard, the held one again
    // included, but not when a layer does (FocusState::rawSurfaceFocus,
    // Hyprland v0.56.2). Two activewindowv2 events are no window taking it
    // from the panel: the repost right after a title change's windowtitlev2
    // (CWindow::onUpdateMeta), and the last window getting the keyboard
    // back right after a layer of another program closes
    // (CLayerSurface::onUnmap, refocusLastWindow). The event socket keeps
    // that order; activewindow and the submap event the layer's own close
    // posts come between and explain nothing. The close still waits for
    // the panel's own focus loss, so a window event that comes first closes
    // nothing yet. rawEvent: Quickshell 0.3.1 HyprlandEvent,
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/HyprlandEvent
    property bool windowTook: false
    property var previousEvent: null

    onActiveFocusChanged: {
        root.call("panel-focused", activeFocus ? "on" : "off");
        if (activeFocus) windowTook = false;
        closeForWindow();
    }

    function closeForWindow() {
        if (opened && !activeFocus && windowTook) root.call("close", "");
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindow" || event.name === "submap") return;
            if (event.name !== "activewindowv2") {
                root.previousEvent = { name: event.name, data: event.data };
                return;
            }
            const before = root.previousEvent;
            root.previousEvent = null;
            if (before !== null && before.name === "windowtitlev2" && before.data.split(",")[0] === event.data) return;
            if (before !== null && before.name === "closelayer" && !before.data.startsWith("vgs:")) return;
            root.windowTook = true;
            root.closeForWindow();
        }
    }

    function open(payloadJson) {
        const payload = parsePayload(payloadJson);
        // The service summons an open panel again after each choice, and the
        // user stays on the row that took the chosen one's place.
        const reopen = opened && mode === payload.mode;
        mode = payload.mode;
        if (!opened) windowTook = false;
        opened = true;
        actionIndex = -1;
        call("panel-opened", mode);
        refresh();
        Qt.callLater(() => {
            if (!reopen) selectIndex(rows.length > 0 ? 0 : -1);
            call("panel-focused", root.activeFocus ? "on" : "off");
        });
    }

    function close() {
        opened = false;
        call("panel-focused", "off");
        clearSelectionHover();
        call("panel-closed", "");
    }

    function parsePayload(payloadJson) {
        try {
            const payload = JSON.parse(String(payloadJson || "{}"));
            return { mode: payload.mode === "history" ? "history" : "inbox" };
        } catch (e) {
            return { mode: "inbox" };
        }
    }

    function call(name, arg) {
        if (shell === null) return "unknown: shell";
        return shell.ipc.call(name, arg === undefined ? "" : String(arg));
    }

    function refresh() {
        if (shell === null) return;
        const raw = call("panel-state", "");
        // The core answers `unknown: panel-state` while the service holds no
        // handler (PluginLogic.ipcAnswer). The service registers its
        // handlers once its store has read the state file, and a rescan
        // that rebuilds the plugin under an open inbox opens the new panel
        // before that. The service writes panelRevision in the turn it
        // registers, which refreshes this panel with the state (read in the
        // notifications smoke row, where the inbox stays open over a rescan).
        if (raw === "unknown: panel-state") return;
        try {
            const state = JSON.parse(raw);
            const previousKey = selectedKey;
            const previousIndex = currentIndex;
            const previousRows = rows;
            mode = state.mode === "history" ? "history" : "inbox";
            subtitle = String(state.subtitle || "");
            silenced = state.silenced === true;
            refreshing = true;
            rows = Array.isArray(state.rows) ? state.rows : [];
            const kept = indexOfKey(previousKey);
            if (rows.length === 0) currentIndex = -1;
            else if (kept !== -1) currentIndex = kept;
            else currentIndex = successorIndex(previousRows, previousIndex, previousKey);
            const row = rowAt(currentIndex);
            selectedKey = row === null ? "" : row.key;
            if (selectedKey !== previousKey || actionIndex >= actionsOf(currentIndex).length) actionIndex = -1;
            refreshing = false;
            updateSelectionHover();
            revealRow(currentIndex);
        } catch (e) {
            console.warn("notifications panel: state " + e.message);
            refreshing = true;
            rows = [];
            currentIndex = -1;
            selectedKey = "";
            actionIndex = -1;
            refreshing = false;
            updateSelectionHover();
        }
    }

    // Where the selection goes once its row left: the nearest row of the
    // previous list still listed, the one that took its place first, since
    // a row that arrived meanwhile may now stand at the old index.
    function successorIndex(previousRows, previousIndex, previousKey) {
        if (previousKey !== "") {
            for (let i = previousIndex + 1; i < previousRows.length; i++) {
                const at = indexOfKey(previousRows[i].key);
                if (at !== -1) return at;
            }
            for (let i = Math.min(previousIndex, previousRows.length) - 1; i >= 0; i--) {
                const at = indexOfKey(previousRows[i].key);
                if (at !== -1) return at;
            }
        }
        return Math.max(0, Math.min(previousIndex, rows.length - 1));
    }

    function indexOfKey(key) {
        if (key === "") return -1;
        for (let i = 0; i < rows.length; i++)
            if (rows[i].key === key) return i;
        return -1;
    }

    function selectIndex(index) {
        refreshing = true;
        currentIndex = index;
        const row = rowAt(index);
        const key = row === null ? "" : row.key;
        if (selectedKey !== key) {
            selectedKey = key;
            actionIndex = -1;
        }
        refreshing = false;
        updateSelectionHover();
        revealRow(currentIndex);
    }

    // Scroll the list so the row at `index` stands clear of both fades:
    // its slot's top at or below the top band, its bottom at or above the
    // bottom band, the top first when the row is taller than the room
    // between them, inside the scroll's travel. A band has no strength at
    // the end the view rests at, so the first and last rows stand clear
    // there. Nothing lifts the fade from a selected card, so a reveal into
    // the view alone, as KeyNav's, would leave it faded at an edge.
    function revealRow(index) {
        const slot = rowRepeater.itemAt(index);
        if (slot === null) return;
        const view = listScroll.flickable;
        const top = slot.mapToItem(view.contentItem, 0, 0).y;
        const fromBottom = Math.max(view.contentY, top + slot.height - view.height + listScroll.fadeExtent);
        const place = Math.min(fromBottom, top - listScroll.fadeExtent);
        view.contentY = Math.max(0, Math.min(place, view.contentHeight - view.height));
    }

    function rowAt(index) {
        return index >= 0 && index < rows.length ? rows[index] : null;
    }

    function actionsOf(index) {
        const row = rowAt(index);
        return row !== null && Array.isArray(row.actions) ? row.actions : [];
    }

    function choose(key, choice) {
        const reply = call("choose", JSON.stringify({ key: key, choice: choice }));
        if (reply !== "left" && reply !== "kept" && reply !== "held") console.warn("notifications panel: choose " + reply);
        refresh();
        if (reply === "left") dropLocal(key);
        if (opened) Qt.callLater(() => {
            if (!opened) return;
            refresh();
            if (reply === "left") dropLocal(key);
            list.forceActiveFocus(Qt.TabFocusReason);
        });
        return reply;
    }

    function dropLocal(key) {
        const at = indexOfKey(key);
        if (at === -1) return;
        const next = rows.slice();
        next.splice(at, 1);
        rows = next;
        selectIndex(rows.length === 0 ? -1 : Math.min(at, rows.length - 1));
    }

    function openSelected() {
        const row = rowAt(currentIndex);
        if (row === null) return false;
        choose(row.key, "open");
        return true;
    }

    function dismissSelected() {
        const row = rowAt(currentIndex);
        if (row === null) return false;
        choose(row.key, "dismiss");
        return true;
    }

    function pressAction() {
        const row = rowAt(currentIndex);
        const actions = actionsOf(currentIndex);
        if (row === null || actionIndex < 0 || actionIndex >= actions.length) return false;
        choose(row.key, actions[actionIndex].id);
        return true;
    }

    function moveAction(delta) {
        const actions = actionsOf(currentIndex);
        if (actions.length === 0) return false;
        if (actionIndex < 0) actionIndex = delta > 0 ? 0 : actions.length - 1;
        else actionIndex = (actionIndex + delta + actions.length) % actions.length;
        return true;
    }

    function setHover(key, on) {
        if (key === "") return;
        call("hover", JSON.stringify({ key: key, on: on === true }));
    }

    function clearSelectionHover() {
        if (selectedHoverKey !== "") setHover(selectedHoverKey, false);
        selectedHoverKey = "";
    }

    function updateSelectionHover() {
        const row = rowAt(currentIndex);
        const key = row === null ? "" : row.key;
        if (selectedHoverKey === key) return;
        clearSelectionHover();
        selectedHoverKey = key;
        if (selectedHoverKey !== "") setHover(selectedHoverKey, true);
    }

    // The Pane keeps the header and its gutter; the list lies outside the
    // Pane's body, whose clip stops at the ring room above it, so the list's
    // view starts at the header's bottom edge and its cards fade out as
    // they pass behind the header.
    Pane {
        id: column
        anchors.fill: parent
        container: "panel"
        padding: 0
        cornerRadius: 0
        // The gutter under the header is the shared sticky header region,
        // `bodyGap`, which the list's first card starts below.
        gap: 0

        header: [
            InboxHeader {
                id: header
                look: root.look
                settingsHost: root.settingsHost
                mode: root.mode
                subtitle: root.subtitle
                silenced: root.silenced
                textColumn: listScroll.textColumn
                glassChoice: root.glassChoice
                shown: true
                width: implicitWidth
                x: (parent.width - width) / 2
                onSilenceRequested: on => {
                    root.call("silence", on ? "on" : "off");
                    root.refresh();
                }
                onClearRequested: {
                    root.call("clear-history", "");
                    root.refresh();
                }
                onMarkReadRequested: root.call("mark-read", "")
                onModeRequested: nextMode => {
                    root.call("panel-opened", nextMode);
                    root.refresh();
                }
            }
        ]
    }

    // Declared after the Pane, so Tab reaches the list after the header.
    Item {
        id: listFrame
        width: listScroll.implicitWidth
        x: column.contentInset + (column.contentWidth - width) / 2
        y: column.contentInset + column.headerHeight
        height: Math.max(0, Math.min(listScroll.implicitHeight, root.height - y))

        CardScroll {
            id: listScroll
            anchors.fill: parent
            scrollObjectName: "notificationPanelScrollBar"
            look: root.look
            maxHeight: root.panelMaxHeight - column.contentInset - column.headerHeight
            topGutter: column.bodyGap

            Label {
                Layout.preferredWidth: root.look.card.width
                role: "hint"
                visible: root.rows.length === 0
                text: root.mode === "history" ? "No saved notifications" : "No unread notifications"
                horizontalAlignment: Text.AlignHCenter
            }

            // focus-indicator: the selected notification card lifts and shows its actions
            Column {
                id: list
                Layout.preferredWidth: root.look.card.width
                width: root.look.card.width
                activeFocusOnTab: true
                focusPolicy: Qt.StrongFocus
                focus: true
                Accessible.name: "Notifications list"
                Keys.onPressed: event => event.accepted = nav.handle(event)

                KeyNav {
                    id: nav
                    count: root.rows.length
                    currentIndex: root.currentIndex
                    wrap: false
                    crossAxis: true
                    viewHeight: listScroll.flickable.height
                    rowHeight: root.look.card.maxHeight + root.look.card.gap
                    // The view shrinks when the room does under the
                    // open panel, and a Flickable keeps its place then,
                    // which leaves a selected card near the list's end
                    // past the view's bottom edge (read in the
                    // notifications-keys smoke row, on a copy without
                    // this handler); reveal it again whenever the
                    // view's height changes. A move reveals through
                    // onMoved.
                    onViewHeightChanged: root.revealRow(root.currentIndex)
                    labelAt: index => {
                        const row = root.rowAt(index);
                        return row === null ? "" : row.summary;
                    }
                    onMoved: index => root.selectIndex(index)
                    onActivated: index => root.actionIndex >= 0 ? root.pressAction() : root.openSelected()
                    onRemoved: index => root.dismissSelected()
                    onCrossed: delta => root.moveAction(delta)
                }

                Repeater {
                    id: rowRepeater
                    model: root.rows

                    // The slot, the gap above its card and the card, is the
                    // card's hover area: the slots tile the list with no
                    // gap and no overlap, so the pointer is on exactly one,
                    // and the card's lift under the pointer moves no edge
                    // of it.
                    Item {
                        id: slot
                        required property var modelData
                        required property int index
                        readonly property bool selected: root.currentIndex === index
                        readonly property real hover: selected || face.hovered ? 1 : 0
                        width: root.look.card.width
                        height: face.height + root.look.card.gap

                        onSelectedChanged: if (selected) root.updateSelectionHover()

                        HoverHandler { id: pointer }

                        CardFace {
                            id: face
                            look: root.look
                            key: slot.modelData.key || ""
                            textColumn: listScroll.textColumn
                            hovered: pointer.hovered
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: root.look.card.gap - root.look.card.lift * slot.hover
                            width: card.fullWidth
                            height: card.fullHeight
                            app: slot.modelData.app || ""
                            appIcon: slot.modelData.appIcon || ""
                            summary: slot.modelData.summary || ""
                            body: slot.modelData.body || ""
                            image: slot.modelData.image || ""
                            desktopEntry: slot.modelData.desktopEntry || ""
                            urgency: slot.modelData.urgency === undefined ? Logic.URGENCY.normal : slot.modelData.urgency
                            hintIcon: slot.modelData.hintIcon || ""
                            hintTone: slot.modelData.hintTone || ""
                            workspace: slot.modelData.workspace || ""
                            workspaceIcon: slot.modelData.workspaceIcon || ""
                            faceImages: slot.modelData.faceImages || []
                            emoji: slot.modelData.emoji || null
                            actions: slot.modelData.actions || []
                            showActions: (slot.selected || hovered) && actions.length > 0
                            actionIndex: slot.selected ? root.actionIndex : -1
                            keyboardActions: true
                            glassChoice: root.glassChoice
                            edgeVisible: slot.hover > 0
                            edgeBoost: 1 + root.look.edge.hoverBoost * slot.hover
                            onHoverRequested: (key, on) => root.setHover(key, on)
                            onActionTriggered: id => root.choose(slot.modelData.key, id)
                            onCloseRequested: root.choose(slot.modelData.key, "dismiss")
                            onCardClicked: root.choose(slot.modelData.key, "open")
                        }
                    }
                }
            }
        }
    }
}
