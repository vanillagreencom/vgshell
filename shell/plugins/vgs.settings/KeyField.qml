import QtQuick
import qs.Ui

// One row of a plugin's Keys section: the bind row of qs.Ui, which sends
// a pressed or typed key and the unbind, with the manifest's key under it,
// or none for a pad's key, and two buttons of its own, shown only where they
// change something. The reset button, for a key with a default, sends undefined, which removes the shell.json entry so the
// manifest's key applies. While a user Hyprland bind holds the key, Use my
// binding sends null, which unbinds the shortcut so the user's own bind
// keeps the key, in one click. The field then shows what the configuration
// holds again.
//
// A key typed as text waits in the text entry until it is saved: `edited`
// says the entry holds a key other than the one in effect, `save()` sends
// it as Enter there does and `discard()` drops it. The page tells the row
// through `settle` whether the manager accepted each key it sent, and a
// refused key returns to the text entry, so it stays an unsaved edit the
// user corrects. `edits` is the page's set of unsaved edits (EditSet),
// which the row joins while edited and tells of each typed key the
// manager accepted; a pressed key is no edit, so the set hears of none.
BindField {
    id: root

    property var edits: null
    readonly property bool edited: shortcutField.edited
    readonly property bool userHolds: found !== null && found.user === true

    function save() { shortcutField.acceptTyped(); }
    function discard() { shortcutField.stopTyping(); }
    function settle(key, accepted) {
        sent.accepted = accepted;
        if (!accepted && typeof key === "string") shortcutField.startTyping(key);
    }

    Component.onDestruction: if (edits !== null) edits.forget(root)
    onEditedChanged: if (edits !== null) edits.track(root)
    onEditableChanged: if (!editable) discard()

    QtObject {
        id: sent
        // Whether the manager accepted the key the row sent last.
        property bool accepted: false
    }

    // BindField's own handler of `typed` is connected first, so the typed
    // key is sent and settled before this one runs.
    Connections {
        target: root.shortcutField
        function onTyped() { if (root.edits !== null && sent.accepted) root.edits.wrote(); }
    }

    hint: bind["default"] === null ? "No default shortcut." : "Default shortcut: " + bind["default"] + "."

    actions: [
        Button {
            text: "Use my binding"
            size: "sm"
            variant: "secondary"
            visible: root.editable && root.userHolds
            onClicked: root.applyKey(null)
        },
        IconButton {
            iconName: "rotate-ccw"
            label: "Reset to " + root.bind["default"]
            size: "sm"
            visible: root.editable && root.bind["default"] !== null && root.bind.key !== root.bind["default"]
            onClicked: root.applyKey(undefined)
        }
    ]
}
