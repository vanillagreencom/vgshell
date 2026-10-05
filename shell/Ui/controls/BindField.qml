import QtQuick
import qs.Ui

// One plugin bind as an inline form row, from one bind the manager lists:
// the description the plugin registered (its shortcut name while it has
// registered none) beside a ShortcutField holding the key in effect.
// Pressing a combo, or typing one as `MOD+KEY`, emits `applyKey` with that
// key; an empty typed one and the field's unbind button emit null, which
// unbinds it. The field names the bind, so the line under it is the
// capture's conflict hint for the key, the same line wherever a bind is
// shown. `found` is the capture's `conflicts` answer the hint comes from,
// and `actions` are buttons a caller adds after the field's own.
Field {
    id: root

    property string pluginId: ""
    // { shortcut, key, default, description }; `key` is null while unbound.
    property var bind: ({})
    property bool editable: true
    // The `shortcut` capability's key capture member, or null.
    property var capture: null
    property alias actions: input.actions
    readonly property var found: input.found
    signal applyKey(var key)

    readonly property string shown: bind.key === null || bind.key === undefined ? "" : String(bind.key)

    label: bind.description ? String(bind.description) : String(bind.shortcut)
    inline: true

    ShortcutField {
        id: input
        width: parent.width
        key: root.shown
        capture: root.capture
        editable: root.editable
        pluginId: root.pluginId
        shortcut: String(root.bind.shortcut)
        onCommitted: key => root.applyKey(key)
        onTyped: text => root.applyKey(text === "" ? null : text)
        onCleared: root.applyKey(null)
    }
}
