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
    property bool sound: true
    property bool soundChosen: false
    property bool silenced: false
    property var rows: []
    ListModel { id: panelModel }
    property var measuredRows: ({})
    property var measuredLook: null
    RowMeasure {
        id: rowMeasure
        visible: false
        measureOnly: true
        // Resource readiness does not discard actual row heights. The
        // visible card reports its real geometry; an unbuilt row keeps
        // its initial estimate until its first real card is constructed.
        rowCard: ({ look: root.look, pad: root.look.card.pad, summary: "", title: "", singleLine: true,
            showsBadge: false, enrichment: null, workspace: "", workspaceIcon: "", bodySegments: [] })
    }
    onLookChanged: if (opened) reconcileRows(rows)
    function rowHeight(entry, payload) {
        if (measuredLook !== look) { measuredRows = ({}); measuredLook = look; }
        let cached = measuredRows[entry.key];
        if (cached === undefined || cached.payload !== payload) {
            const height = rowMeasure.measure(entry, look, listScroll.textColumn) + look.card.gap;
            cached = { payload: payload, height: height, estimate: height, collapsed: null };
            measuredRows[entry.key] = cached;
        }
        return cached.height;
    }
    function setRowExtent(key, height) {
        const index = indexOfKey(key);
        if (index === -1) return;
        const old = panelModel.get(index).extent;
        if (old === height) return;
        const slot = rowRepeater.itemAt(index);
        const view = listScroll.flickable;
        const before = view.contentY;
        const above = slot !== null && slot.viewY + slot.height <= 0;
        panelModel.setProperty(index, "extent", height);
        // Finish the column and its enclosing grid in this update. An
        // already passed row must not move the content under the pointer.
        list.forceLayout();
        listScroll.cards.ensurePolished();
        if (above) view.contentY = before + height - old;
    }
    function actualRowHeight(key, height, resting) {
        const cached = measuredRows[key];
        if (indexOfKey(key) === -1 || cached === undefined) return;
        // The estimate belongs only to an unbuilt row. A live card is the
        // authority, including its collapsed height after a tray fades.
        // Unloading performs no height write and keeps this actual value.
        if (resting) cached.collapsed = height;
        if (cached.height === height) return;
        cached.height = height;
        setRowExtent(key, height);
        if (key === selectedKey) Qt.callLater(() => {
            const slot = rowRepeater.itemAt(indexOfKey(key));
            // Growth reveals a card already in view. A user's scroll past
            // the selected card must keep its new viewport position.
            if (opened && key === selectedKey && slot !== null
                && slot.viewY < listScroll.flickable.height && slot.viewY + slot.height > 0)
                revealRow(currentIndex);
        });
    }

    // Qt ListModel moves retain delegates (Qt 6 ListModel.move). Keep the
    // notification key's card when a snapshot changes its place or data.
    function reconcileRows(next) {
        for (let i = 0; i < next.length; ++i) {
            const payload = JSON.stringify(next[i]);
            const extent = rowHeight(next[i], payload);
            let at = i;
            while (at < panelModel.count && panelModel.get(at).key !== next[i].key) ++at;
            if (at === panelModel.count) panelModel.insert(i, { key: next[i].key, payload: payload, extent: extent });
            else {
                if (at !== i) panelModel.move(at, i, 1);
                if (panelModel.get(i).payload !== payload) panelModel.setProperty(i, "payload", payload);
                if (panelModel.get(i).extent !== extent) panelModel.setProperty(i, "extent", extent);
            }
        }
        if (panelModel.count > next.length) panelModel.remove(next.length, panelModel.count - next.length);
        // Keep unread/history heights while this panel lives, but do not
        // keep removed notification keys beyond the store's row limit.
        const keys = Object.keys(measuredRows);
        let excess = keys.length - Logic.HISTORY_MAX - Logic.LIVE_MAX;
        for (const key of keys) {
            if (excess <= 0) break;
            if (indexOfKey(key) === -1) { delete measuredRows[key]; --excess; }
        }
        rowMeasure.trimImages(next);
    }
    readonly property int rowCount: rows.length
    property int currentIndex: 0
    property int actionIndex: -1
    property string selectedKey: ""
    property string selectedHoverKey: ""
    property bool opened: false
    // The host applies this panel's requested size after constructing it.
    // Build the visible faces after that turn, rather than build a face
    // for the temporary small viewport and immediately destroy it.
    property bool initialLayoutReady: false
    Component.onCompleted: Qt.callLater(() => initialLayoutReady = true)
    property bool refreshing: false
    property int refreshQueuedFor: -1
    property Item initialFocus: list
    // InboxHeader owns this panel's Settings gear.
    readonly property Item settingsHost: parent

    // As wide as the column: the cards with their side room, where the
    // scroll bar sits, wider than the header they sit under.
    implicitWidth: Math.max(header.implicitWidth, listScroll.implicitWidth) + 2 * column.contentInset
    readonly property real panelMaxHeight: column.contentInset + look.header.height + listScroll.topGutter + look.panel.rowCap * (look.card.maxHeight + look.card.gap) + look.stack.tail
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
            sound = state.sound === true;
            soundChosen = state.soundChosen === true;
            silenced = state.silenced === true;
            refreshing = true;
            rows = Array.isArray(state.rows) ? state.rows : [];
            reconcileRows(rows);
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
            panelModel.clear();
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
    property bool revealing: false
    function revealRow(index) {
        if (revealing) return;
        revealing = true;
        try {
            list.forceLayout();
            // Qt 6.11 QQuickItem.ensurePolished publishes the GridLayout's
            // pending implicit height before the scroll travel is read.
            listScroll.cards.ensurePolished();
            const slot = rowRepeater.itemAt(index);
            if (slot === null) return;
            const view = listScroll.flickable;
            const top = slot.mapToItem(view.contentItem, 0, 0).y;
            const fromBottom = Math.max(view.contentY, top + slot.height - view.height + listScroll.fadeExtent);
            const place = Math.min(fromBottom, top - listScroll.fadeExtent);
            view.contentY = Math.max(0, Math.min(place, view.contentHeight - view.height));
        } finally { revealing = false; }
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
        reconcileRows(rows);
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

    // The Pane keeps the header; the list lies outside the
    // Pane's body, whose clip stops at the ring room above it, so the list's
    // view starts at the header's bottom edge and its cards fade out as
    // they pass behind the header.
    Pane {
        id: column
        anchors.fill: parent
        container: "panel"
        padding: 0
        cornerRadius: 0
        gap: 0

        header: [
            InboxHeader {
                id: header
                look: root.look
                settingsHost: root.settingsHost
                mode: root.mode
                subtitle: root.subtitle
                sound: root.sound
                soundChosen: root.soundChosen
                dnd: root.silenced
                textColumn: listScroll.textColumn
                glassChoice: root.glassChoice
                shown: true
                width: implicitWidth
                x: (parent.width - width) / 2
                onSoundRequested: on => {
                    root.call("sound", on ? "on" : "off");
                    root.refresh();
                }
                onDndRequested: on => {
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
            // The first card stands the card gap under the header, as each
            // card stands it under the one before.
            topGutter: root.look.card.gap

            Label {
                Layout.preferredWidth: root.look.card.width
                role: "hint"
                visible: root.rows.length === 0
                text: root.mode === "history" ? "No saved notifications" : "No unread notifications"
                horizontalAlignment: Text.AlignHCenter
            }

            // focus-indicator: the selected notification card shows its edge light and its actions
            Column {
                id: list
                Layout.preferredWidth: root.look.card.width
                width: root.look.card.width
                onPositioningComplete: {
                    for (let i = 0; i < rowRepeater.count; ++i) {
                        const slot = rowRepeater.itemAt(i);
                        if (slot !== null) slot.positioned = true;
                    }
                }
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
                    model: panelModel

                    // The slot, the card and the gap below it, is the card's
                    // hover area: the slots tile the list with no gap and
                    // no overlap, so the pointer is on exactly one, and the
                    // card's lift under the pointer moves no edge of it.
                    // Only the pointer lifts a card: the selection lifts
                    // none, so the open list keeps every gap even.
                    Item {
                        id: slot
                        required property string payload
                        required property real extent
                        readonly property var entry: JSON.parse(payload)
                        required property int index
                        readonly property bool selected: root.currentIndex === index
                        readonly property real hover: selected || pointer.hovered ? 1 : 0
                        width: root.look.card.width
                        height: extent
                        property bool positioned: false
                        // Keep an existing face until its tray fade finishes.
                        // Loader.active must not read Loader.item: creating or
                        // destroying that item would change its own binding.
                        property bool holdsTray: false
                        function updateTrayRetention() {
                            if (faceLoader.item !== null && holdsTray && faceLoader.item.card.trayReserve === 0) {
                                reportHeight();
                            }
                            holdsTray = faceLoader.item !== null && faceLoader.item.card.trayReserve > 0;
                        }
                        readonly property real viewY: list.y + y + listScroll.topGutter - listScroll.flickable.contentY
                        function reportHeight() {
                            if (faceLoader.item !== null) {
                                faceLoader.item.card.settleHeight();
                                if (faceLoader.item.height > 0)
                                    root.actualRowHeight(entry.key, faceLoader.item.height + root.look.card.gap,
                                        faceLoader.item.card.trayReserve === 0);
                            }
                        }

                        onSelectedChanged: if (selected) root.updateSelectionHover()

                        HoverHandler { id: pointer }

                        Connections {
                            target: faceLoader.item === null ? null : faceLoader.item.card
                            function onTrayReserveChanged() {
                                Qt.callLater(slot.reportHeight);
                                Qt.callLater(slot.updateTrayRetention);
                            }
                        }

                        Loader {
                            id: faceLoader
                            active: slot.positioned && root.initialLayoutReady && root.opened && listScroll.flickable.height > 0
                                && ((slot.viewY + y < listScroll.flickable.height
                                    && slot.viewY + y + slot.height - root.look.card.gap > 0)
                                    || slot.holdsTray)
                            width: parent.width
                            y: pointer.hovered ? -root.look.card.lift : 0
                            onItemChanged: {
                                Qt.callLater(slot.reportHeight);
                                Qt.callLater(slot.updateTrayRetention);
                            }
                            // An unloaded slot keeps its last real height. Its
                            // extent must not return to the initial estimate.
                            sourceComponent: Component {
                                CardFace {
                                    id: face
                                    look: root.look
                                    key: slot.entry.key || ""
                                    textColumn: listScroll.textColumn
                                    hovered: pointer.hovered
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: card.fullWidth
                                    height: card.fullHeight
                                    onHeightChanged: Qt.callLater(slot.reportHeight)
                                    app: slot.entry.app || ""
                                    appIcon: slot.entry.appIcon || ""
                                    summary: slot.entry.summary || ""
                                    body: slot.entry.body || ""
                                    image: slot.entry.image || ""
                                    desktopEntry: slot.entry.desktopEntry || ""
                                    urgency: slot.entry.urgency === undefined ? Logic.URGENCY.normal : slot.entry.urgency
                                    hintAvatar: slot.entry.hintAvatar || ""
                                    hintIcon: slot.entry.hintIcon || ""
                                    hintTone: slot.entry.hintTone || ""
                                    hintPage: slot.entry.hintPage || ""
                                    workspace: slot.entry.workspace || ""
                                    workspaceIcon: slot.entry.workspaceIcon || ""
                                    faceImages: slot.entry.faceImages || []
                                    emoji: slot.entry.emoji || null
                                    actions: slot.entry.actions || []
                                    showActions: (slot.selected || hovered) && actions.length > 0
                                    actionIndex: slot.selected ? root.actionIndex : -1
                                    keyboardActions: true
                                    glassChoice: root.glassChoice
                                    edgeVisible: slot.hover > 0
                                    edgeBoost: 1 + root.look.edge.hoverBoost * slot.hover
                                    onHoverRequested: (key, on) => root.setHover(key, on)
                                    onActionTriggered: id => root.choose(slot.entry.key, id)
                                    onCloseRequested: root.choose(slot.entry.key, "dismiss")
                                    onCardClicked: root.choose(slot.entry.key, "open")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
