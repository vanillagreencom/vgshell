import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The existing window host owns the toplevel and Escape. Keep the manager
// join in this one binding, only for the lifetime of the summoned chooser.
// One ContentRow per widget, its description under its name and one
// control at its end, the row's action (`actionOf`). A widget the user can
// place ends in a small Switch, on while the widget is on the bar: turning
// it off takes the widget off the bar, and turning it on puts it at the
// clicked point, or turns a widget-only plugin back on, which places it in
// its default section. A plugin that is off and has other kinds ends in an
// "Enable plugin" link, which turns it on in place, and turning it on puts
// its widget on the bar (PluginLogic.withEnabled); the row then ends in
// its Switch, on. Whichever control a change shows, made here or outside
// the window, takes the focus the other held. The list holds
// the keys: arrows move to a row's control with keyboard focus, and Return
// or Space presses it. A click focuses the control with the mouse reason,
// so it draws no focus ring.
FocusScope {
    id: root

    property var shell: null
    property var payload: ({})
    readonly property var plugins: shell === null ? [] : shell.manager.plugins
    readonly property var widgets: plugins.filter(plugin => plugin.kinds.indexOf("bar-widget") !== -1)
    // The selected row: the one whose control holds the list's focus, -1
    // while none does. Opening clears it, so the list holds the keys and
    // Return presses no action that changes the bar. Derived from focus,
    // it follows the focused control through a re-summon or a row's
    // removal.
    readonly property int current: {
        for (let i = 0; i < rows.count; i++) {
            const row = rows.itemAt(i);
            if (row !== null && row.control.focus) return i;
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
        // A re-summon finds the scope's focus on the control last focused,
        // such as one just clicked, and the host's focus on the scope would
        // hand it back.
        for (let i = 0; i < rows.count; i++) rows.itemAt(i).release();
    }
    function close() {}

    // The one owner of a row's action: `remove` for a placed widget, its
    // Switch on; `add` for an unplaced one, its Switch off; `enable` for a
    // plugin that is off and has other kinds, its link. A plugin whose only
    // kind is bar-widget is off while unplaced (PluginLogic.enablementRule
    // "widget"), so `add` turns it back on; insertWidget refuses a disabled
    // plugin for every other caller.
    function actionOf(plugin) {
        if (plugin.enabled) return plugin.placed ? "remove" : "add";
        return plugin.enablement === "widget" ? "add" : "enable";
    }

    function addWidget(id) {
        const reply = shell.manager.insertWidget(id, payload.screen, payload.x);
        notice = Reply.line(reply);
        if (!Reply.isOk(reply)) console.warn("vgs.bar: insert widget " + reply);
        return reply;
    }

    // One manager call per change, so one configuration write.
    function act(plugin) {
        const action = actionOf(plugin);
        if (action === "add" && plugin.enabled) return addWidget(plugin.id);
        const reply = action === "remove" ? shell.manager.setPlaced(plugin.id, false) : shell.manager.setEnabled(plugin.id, true);
        notice = Reply.line(reply);
        if (!Reply.isOk(reply)) console.warn("vgs.bar: " + action + " widget " + reply);
        return reply;
    }

    function focusRow(index) {
        const row = rows.itemAt(index);
        if (row !== null) row.control.forceActiveFocus(Qt.TabFocusReason);
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
        title: "Manage widgets"
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
                // `add`, `remove` or `enable`, from actionOf.
                readonly property string rowAction: root.actionOf(modelData)
                // The one control the row shows: the link while the plugin
                // must be turned on, else the Switch.
                readonly property Item control: rowAction === "enable" ? link : toggle
                width: layout.contentWidth
                iconName: modelData.icon
                text: modelData.name
                secondary: modelData.description

                // The keys follow the shown control. A hidden item keeps
                // its focus and takes the keys
                // (https://doc.qt.io/qt-6/qml-qtquick-item.html#visible-prop),
                // so when a change swaps the control, whether the link's
                // own action, which Config.writeUser publishes before it
                // returns (Config.qml publish), or one made in Settings or
                // the CLI, the control just hidden hands its focus to the
                // one shown, with its reason: after a click it draws no
                // ring, after a key it keeps it. It reads `focus`, not
                // `activeFocus`, so a change made while Settings holds the
                // keyboard moves the focus the window gives back too.
                onControlChanged: {
                    const hidden = control === link ? toggle : link;
                    if (!hidden.focus) return;
                    control.forceActiveFocus(hidden.focusReason);
                    hidden.focus = false;
                }
                // Gives up the row's focus, held by either control.
                function release() {
                    link.focus = false;
                    toggle.focus = false;
                }

                trailing: [
                    RowAction {
                        id: link
                        anchors.verticalCenter: parent.verticalCenter
                        visible: entry.rowAction === "enable"
                        text: "Enable plugin"
                        Accessible.name: text + " " + entry.modelData.name
                        // keyboard-path: the list's arrows reach every row's control; Tab enters at the selected row
                        // The focused control, or the first row while none
                        // is. Never `index` against `current`: a removed
                        // row above moves both, one at a time, and Qt
                        // refuses to clear this on the active focus item.
                        activeFocusOnTab: root.current === -1 ? entry.index === 0 : focus
                        Keys.onPressed: event => { event.accepted = nav.handle(event); }
                        onActiveFocusChanged: if (activeFocus) nav.reveal(entry.index)
                        onClicked: root.act(entry.modelData)
                    },
                    Switch {
                        id: toggle
                        anchors.verticalCenter: parent.verticalCenter
                        visible: entry.rowAction !== "enable"
                        size: "sm"
                        Accessible.name: entry.modelData.name
                        checked: entry.rowAction === "remove"
                        // keyboard-path: the list's arrows reach every row's control; Tab enters at the selected row
                        // The same Tab stop as the link's.
                        activeFocusOnTab: root.current === -1 ? entry.index === 0 : focus
                        // KeyNav takes Space first and presses the row, so
                        // the template does not toggle it a second time.
                        Keys.onPressed: event => { event.accepted = nav.handle(event); }
                        onActiveFocusChanged: if (activeFocus) nav.reveal(entry.index)
                        // The manager's answer sets the switch: a refused
                        // change leaves it where the bar is.
                        onToggled: {
                            checked = Qt.binding(() => entry.rowAction === "remove");
                            root.act(entry.modelData);
                        }
                    }
                ]
            }
        }
    }
}
