import QtQuick
import qs.Ui

// One plugin bind as an inline form row, from one bind the manager lists:
// the description the plugin registered (its shortcut name while it has
// registered none), with its explanation on label hover and keyboard
// focus, beside a ShortcutField holding the keys in effect, one key or
// the alternatives of a list. Each edit changes one alternative and emits
// `applyKey(key)`: `key` is what the manager writes, one key, a list of two
// or more, or null once none is left, which unbinds the shortcut. While
// an edit's signal runs, `alternative` is the key the edit set, null for a
// removal; it is undefined for a key a caller sends itself.
// Pressing a combo, or typing one as `MOD+KEY`, sets the alternative
// edited; an empty typed one, the field's unbind button and Delete remove
// it, and `remove(index)` removes another. The field names the bind, so
// the line under it is the
// capture's conflict hint for the key, the same line wherever a bind is
// shown. `found` is the capture's `conflicts` answer the hint comes from,
// `actions` are buttons a caller adds after the field's own,
// `hintActions` controls it draws on a line under that hint, `hintLink`
// the hint's cited file, reported by `hintLinkActivated`, and
// `shortcutField` is the field itself, for a caller that reads or ends its
// text entry.
Field {
    id: root

    property string pluginId: ""
    // { shortcut, key, keys, default, description, info }; `key` is null
    // while unbound, `keys` every key in effect, absent for a bind that
    // holds one key at most, `info` "" or absent for a bind with no
    // explanation.
    property var bind: ({})
    property bool editable: true
    // The `shortcut` capability's key capture member, or null.
    property var capture: null
    property alias actions: input.actions
    property alias hintActions: input.hintActions
    property alias hintLink: input.hintLink
    readonly property var found: input.found
    readonly property alias shortcutField: input
    signal applyKey(var key)
    signal hintLinkActivated()

    property var alternative: undefined

    // `keys` can arrive as a list-like rather than an Array, as from a ListModel.
    readonly property var keys: bind.keys !== undefined && bind.keys !== null ? Array.from(bind.keys, String)
        : bind.key === null || bind.key === undefined ? [] : [String(bind.key)]

    // Send the keys with alternative INDEX set to KEY, or removed for null;
    // an INDEX past the last adds KEY, and a key twice counts once.
    function edit(index, key) {
        const next = keys.slice();
        if (key === null) next.splice(index, 1);
        else next[index] = key;
        const value = next.filter((each, i) => next.indexOf(each) === i);
        alternative = key;
        applyKey(value.length === 0 ? null : value.length === 1 ? value[0] : value);
        alternative = undefined;
    }

    function remove(index) {
        edit(index, null);
    }

    label: bind.description ? String(bind.description) : String(bind.shortcut)
    labelTooltip: bind.info ? String(bind.info) : ""
    inline: true

    ShortcutField {
        id: input
        width: parent.width
        keys: root.keys
        capture: root.capture
        editable: root.editable
        pluginId: root.pluginId
        shortcut: String(root.bind.shortcut)
        onCommitted: (key, index) => root.edit(index, key)
        onTyped: (text, index) => root.edit(index, text === "" ? null : text)
        onCleared: index => root.remove(index)
        onHintLinkActivated: root.hintLinkActivated()
    }
}
