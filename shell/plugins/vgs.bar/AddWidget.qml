import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The existing window host owns the toplevel and Escape. Keep the manager
// join in this one binding, only for the lifetime of the summoned chooser.
// One ContentRow per widget, its one small button the row's action
// (`actionOf`): Remove takes a placed widget off the bar, Add puts an
// unplaced one at the clicked point, or turns a widget-only plugin back on,
// which places it in its default section, and Settings opens the page
// where a plugin with other kinds is turned on. The list holds the keys:
// arrows move to a row's button with keyboard focus, and Return or Space
// presses it. A click focuses the button with the mouse reason, so it
// draws no focus ring.
FocusScope {
    id: root

    property var shell: null
    property var payload: ({})
    readonly property var plugins: shell === null ? [] : shell.manager.plugins
    readonly property var widgets: plugins.filter(plugin => plugin.kinds.indexOf("bar-widget") !== -1)
    // The selected row: the one whose button holds the list's focus, -1
    // while none does. Opening clears it, so the list holds the keys and
    // Return presses no action that changes the bar. Derived from focus,
    // the index keys act on is always the row that draws the ring, also
    // after a click, a re-summon or a row's removal.
    readonly property int current: {
        for (let i = 0; i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (row !== null && row.actionButton.focus) return i;
        }
        return -1;
    }
    property string notice: ""
    readonly property Item initialFocus: root

    implicitWidth: Theme.size.window.width
    implicitHeight: layout.implicitHeight
    focus: true

    function open(payloadJson) {
        payload = JSON.parse(payloadJson);
        notice = "";
        // A re-summon finds the scope's focus on the button last focused,
        // such as one just clicked, and the host's focus on the scope would
        // hand it back.
        for (let i = 0; i < rows.count; i++) rows.itemAt(i).actionButton.focus = false;
    }
    function close() {}

    // The one owner of a row's action. A plugin whose only kind is
    // bar-widget is off while unplaced (PluginLogic.enablementRule
    // "widget"), so Add turns it back on; insertWidget refuses a disabled
    // plugin for every other caller.
    function actionOf(plugin) {
        if (plugin.enabled) return plugin.placed ? "remove" : "add";
        return plugin.enablement === "widget" ? "add" : "settings";
    }

    function addWidget(id) {
        const reply = shell.manager.insertWidget(id, payload.screen, payload.x);
        notice = Reply.line(reply);
        if (!Reply.isOk(reply)) console.warn("vgs.bar: insert widget " + reply);
        return reply;
    }

    function act(plugin) {
        const action = actionOf(plugin);
        if (action === "settings") {
            // The core logs a refused openPage itself.
            const reply = shell.surfaces.openPage(plugin.id, "Settings");
            notice = Reply.line(reply);
            return reply;
        }
        if (action === "add" && plugin.enabled) return addWidget(plugin.id);
        const reply = action === "remove" ? shell.manager.setPlaced(plugin.id, false) : shell.manager.setEnabled(plugin.id, true);
        notice = Reply.line(reply);
        if (!Reply.isOk(reply)) console.warn("vgs.bar: " + action + " widget " + reply);
        return reply;
    }

    function focusRow(index) {
        const row = rows.itemAt(index);
        if (row !== null) row.actionButton.forceActiveFocus(Qt.TabFocusReason);
    }
    Keys.onPressed: event => { event.accepted = nav.handle(event); }

    KeyNav {
        id: nav
        count: root.widgets.length
        currentIndex: root.current
        flickable: layout.scrollArea
        viewHeight: layout.scrollArea.height
        rowHeight: Theme.listItem.twoLineHeight
        itemAt: index => rows.itemAt(index)
        labelAt: index => root.widgets[index].name
        onMoved: index => root.focusRow(index)
        onActivated: index => root.act(root.widgets[index])
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        bodyRowHeight: Theme.listItem.twoLineHeight
        title: "Add widget"
        bodySpacing: 0
        subtitle: [
            Label {
                width: layout.contentWidth
                visible: root.notice !== ""
                role: "hint"
                text: root.notice
                color: Theme.color.warning
                wrapMode: Text.Wrap
            }
        ]
        EmptyState {
            width: layout.contentWidth
            visible: root.widgets.length === 0
            iconName: "puzzle"
            text: "No widgets available"
        }
        Repeater {
            id: rows
            model: ScriptModel {
                values: root.widgets
                objectProp: "id"
            }
            ContentRow {
                id: entry
                required property var modelData
                required property int index
                // `add`, `remove` or `settings`.
                readonly property string rowAction: root.actionOf(modelData)
                readonly property alias actionButton: button
                width: layout.contentWidth
                iconName: modelData.icon
                text: modelData.name
                secondary: rowAction === "settings" ? "Turn this plugin on to add its widget" : modelData.description
                trailing: [
                    Button {
                        id: button
                        anchors.verticalCenter: parent.verticalCenter
                        size: "sm"
                        variant: "secondary"
                        text: entry.rowAction === "remove" ? "Remove" : entry.rowAction === "add" ? "Add" : "Settings"
                        iconName: entry.rowAction === "remove" ? "minus" : entry.rowAction === "add" ? "plus" : "settings"
                        Accessible.name: text + " " + entry.modelData.name
                        // keyboard-path: the list's arrows reach every row's button; Tab enters at the selected row
                        // The focused button, or the first row while none is.
                        // Never `index` against `current`: a removed row above
                        // moves both, one at a time, and Qt refuses to clear
                        // this on the active focus item.
                        activeFocusOnTab: root.current === -1 ? entry.index === 0 : focus
                        Keys.onPressed: event => { event.accepted = nav.handle(event); }
                        onActiveFocusChanged: if (activeFocus) nav.reveal(entry.index)
                        onClicked: root.act(entry.modelData)
                    }
                ]
            }
        }
    }
}
