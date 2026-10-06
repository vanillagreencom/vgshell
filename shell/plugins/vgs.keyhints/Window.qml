import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The Key Hints window: every shortcut an enabled plugin binds, grouped by
// plugin under its name, one BindField each. The rows are the manager's
// plugin rows, whose binds are the ones the Hyprland layer is written
// from, so this window adds no store, key editor or conflict rule: a key
// changed here goes through the manager's setKey to the plugin's
// `plugins[].keys` in shell.json, the same value the Settings page's Keys
// row writes, and the row's field draws the same conflict hint. The field
// then shows what the configuration holds, so a refused key leaves the old
// one in place and the manager's refusal, in the words the Settings page
// uses, reads over the rows until a later key is saved. The window asks to
// be `size.window.width` wide, or the room its screen leaves when that is
// less, and `size.window.heightShare` of the screen's height tall, as the
// Settings window does, so a short monitor shows all of it. The search
// field filters the rows by the plugin's name, what a shortcut does, its
// name and its key; a printable key typed while it does not have the focus
// goes into it. An Escape nothing here takes goes on to the window host,
// which closes the window.
//
// The payload is `{}` or empty; any other payload throws out of open(),
// which refuses the summon.
FocusScope {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    property string query: ""
    // The line over the rows after a key the manager refused, else "".
    property string notice: ""
    readonly property string title: shell === null ? "" : shell.manifest.name
    readonly property var screen: shell === null ? null : shell.screens.current
    // The key capture each row's field asks to press a combo.
    readonly property var capture: shell === null ? null : shell.shortcut.capture
    // One { id, name, binds } per enabled plugin with a bind the query
    // matches, in the manager's order, holding the binds it matches.
    readonly property var groups: {
        if (shell === null) return [];
        const wanted = query.trim().toLowerCase();
        const holds = texts => wanted === "" || texts.some(t => String(t).toLowerCase().indexOf(wanted) !== -1);
        return shell.manager.plugins.filter(p => p.enabled).map(p => ({
            id: p.id,
            name: p.name,
            binds: p.binds.map(displayBind).filter(b => holds([p.name, b.description, b.shortcut, b.key === null ? "" : b.key]))
        })).filter(g => g.binds.length > 0);
    }
    property Item initialFocus: search

    implicitWidth: Math.floor(Math.min(Theme.size.window.width, OverlayState.room(screen).width))
    implicitHeight: screen === null ? Theme.size.panel.maxHeight : Math.floor(Theme.size.window.heightShare * screen.height)
    focus: true

    function open(payloadJson) {
        const payload = JSON.parse(payloadJson === "" ? "{}" : payloadJson);
        if (payload === null || typeof payload !== "object" || Array.isArray(payload) || Object.keys(payload).length > 0)
            throw new Error("payload must be {}, got " + payloadJson);
    }

    function close() {}

    function displayBind(bind) {
        const keys = Array.isArray(bind.keys) ? bind.keys : (bind.key === null || bind.key === undefined ? [] : [bind.key]);
        return Object.assign({}, bind, { key: keys.length === 0 ? null : keys.join(", ") });
    }

    // Set the key of shortcut `shortcut` of plugin `id` through the
    // manager: a key string rebinds, null unbinds; answers its reply.
    function writeKey(id, shortcut, key) {
        const reply = shell.manager.setKey(id, shortcut, key);
        notice = Reply.line(reply);
        if (notice !== "") console.warn("keyhints: key " + id + ":" + shortcut + " " + reply);
        return reply;
    }

    Keys.onPressed: event => {
        const typed = KeyNavLogic.printable(event.text, event.modifiers);
        if (typed === "" || search.activeFocus) return;
        search.forceActiveFocus(Qt.ShortcutFocusReason);
        search.insert(search.cursorPosition, typed);
        event.accepted = true;
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"

        header: [
            Column {
                width: layout.contentWidth
                spacing: Theme.stack.group

                Label {
                    role: "windowTitle"
                    text: root.title
                    width: parent.width
                }
                Label {
                    role: "hint"
                    text: root.notice
                    visible: text !== ""
                    color: Theme.color.warning
                    width: parent.width
                    wrapMode: Text.Wrap
                }
                TextField {
                    id: search
                    width: parent.width
                    placeholderText: "Search shortcuts"
                    leadingIcon: "search"
                    focus: true
                    onTextChanged: root.query = text
                }
            }
        ]

        // The empty result: an icon, one line and a way back.
        EmptyState {
            visible: root.groups.length === 0
            width: layout.contentWidth
            iconName: "search-x"
            text: root.query.trim() === "" ? "No plugin adds a shortcut" : "No shortcut matches " + JSON.stringify(root.query.trim())
            actionText: root.query.trim() === "" ? "" : "Clear search"
            onActivated: {
                search.clear();
                search.forceActiveFocus();
            }
        }

        Repeater {
            model: ScriptModel {
                values: root.groups
                objectProp: "id"
            }

            Section {
                id: group
                required property var modelData
                width: layout.contentWidth
                title: modelData.name

                Repeater {
                    model: ScriptModel {
                        values: group.modelData.binds
                        objectProp: "shortcut"
                    }

                    BindField {
                        required property var modelData
                        width: group.width
                        pluginId: group.modelData.id
                        bind: modelData
                        capture: root.capture
                        onApplyKey: key => root.writeKey(pluginId, modelData.shortcut, key)
                    }
                }
            }
        }
    }
}
