import QtQuick
import qs.Ui

// One row of a plugin's Keys section: the bind row of qs.Ui, which sends
// a pressed or typed key and the unbind, with the manifest's key under it,
// or none for a pad's key, and two buttons of its own, shown only where they
// change something. The reset button, for a key with a default, sends undefined, which removes the shell.json entry so the
// manifest's key applies. While a user Hyprland bind holds the key, Use my
// binding sends null, which unbinds the shortcut so the user's own bind
// keeps the key, in one click. The field then shows what the configuration
// holds again, so a refused key leaves the old one in place.
BindField {
    id: root

    readonly property bool userHolds: found !== null && found.user === true

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
