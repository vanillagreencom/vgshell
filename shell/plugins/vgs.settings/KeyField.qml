import QtQuick
import qs.Ui

// One row of a plugin's Keys section, one per shortcut: the bind row of
// qs.Ui, which draws every alternative key of the shortcut in one field and
// sends a pressed or typed key and a removal, with the manifest's keys
// under it, or none for a pad's key, and buttons of its own, shown only
// where they change something. The add button edits a new alternative and
// listens for it. The reset button, shown while the keys in effect are
// not the manifest's, sends undefined, which removes the shell.json entry
// so the manifest's key or list of keys applies. While a user Hyprland
// bind holds one of the keys, the conflict line under the field names the
// file and line that bind sits on, as a link that opens that line in the
// user's editor, and three buttons under that line resolve it in one
// click: Remove my line asks the page to confirm, then the key capture
// takes that line out of the user's file and reloads Hyprland, so the
// plugin's bind keeps the key; Pick another key starts a capture for that
// key; Use my binding removes that key from the shortcut, unbinding it
// when it was the only one, so the user's own bind keeps the key. After a
// removal the line under the field says which line went, and Undo puts it
// back. The field then shows what the configuration holds again. The
// removal's undo record lives in the key capture until the undo; a field
// destroyed before it, such as by closing Plugins, releases the record, and
// a removal that answers after the field is gone releases its own.
//
// A key typed as text waits in the text entry until it is saved: `edited`
// says the entry holds a key other than the one in effect, `save()` sends
// it as Enter there does and `discard()` drops it. The page tells the row
// through `settle(key, accepted)` whether the manager accepted the value
// it sent, and a refused key returns to the text entry of the alternative
// edited, so it stays an unsaved edit the user corrects: the key an edit
// of the field set, or a one-key value a caller sent itself, such as the
// page's key IPC. A refused removal, and a list a caller sent, open no
// entry, since no one key was asked for. `edits` is the
// page's set of unsaved edits (EditSet), which the row joins while edited
// and tells of each typed key the manager accepted; a pressed key is no
// edit, so the set hears of none.
BindField {
    id: root

    property var edits: null
    readonly property bool edited: shortcutField.edited
    // The manifest's keys, from one key or a list.
    readonly property var defaultKeys: bind["default"] === null || bind["default"] === undefined ? []
        : typeof bind["default"] === "string" ? [bind["default"]] : Array.from(bind["default"])
    // The manifest's keys as the field's caps spell them, such as
    // `Right Alt or Right Ctrl`.
    readonly property string defaultLabel: defaultKeys.map(key => KeyNavLogic.keyCaps(key).join("+")).join(" or ")
    readonly property bool userHolds: found !== null && found.user === true
    // The one user line that binds the key as a whole `hl.bind` call, which
    // Remove my line takes out; null when there is none or more than one.
    readonly property var userLine: {
        const rows = found === null || !userHolds ? [] : (found.userBinds || []).filter(row => row.removable);
        return rows.length === 1 ? rows[0] : null;
    }
    // { token, place, line } of the line Remove my line took out, which
    // Undo puts back; null before a removal and after the undo. The
    // capture keeps the token's record until the undo or the field's
    // destruction releases it.
    property var removed: null
    // Plain state a removal's reply reads: set when the field is destroyed,
    // so a reply that comes later releases its record and touches no
    // property of the field.
    readonly property var life: ({ gone: false })
    property string problem: ""
    // The first user line holding the key, whose file and line the
    // conflict line cites as a link that opens it in the user's editor.
    readonly property var citedLine: found === null || !userHolds || !found.userBinds || found.userBinds.length === 0 ? null : found.userBinds[0]
    signal removalAsked(var row)
    signal lineAsked(var row)

    function save() { shortcutField.acceptTyped(); }
    function discard() { shortcutField.stopTyping(); }
    function settle(key, accepted) {
        sent.accepted = accepted;
        const asked = alternative === undefined ? key : alternative;
        if (!accepted && typeof asked === "string") shortcutField.startTyping(asked);
    }

    // Take ROW, the user line the page confirmed, out of its file.
    function removeLine(row) {
        problem = "";
        const keyCapture = capture;
        const life = root.life;
        keyCapture.removeUserBind(found.key, reply => {
            if (life.gone) {
                if (reply.ok) keyCapture.releaseUserBind(reply.token);
                return;
            }
            if (!reply.ok) {
                console.warn("settings: remove-bind " + reply.error);
                root.problem = "VGS could not remove that line.";
                return;
            }
            root.removed = { token: reply.token, place: row.place, line: reply.line };
        });
    }

    function undoRemoval() {
        const token = removed.token;
        problem = "";
        capture.restoreUserBind(token, reply => {
            if (!reply.ok) {
                console.warn("settings: restore-bind " + reply.error);
                root.problem = "VGS could not put that line back.";
                return;
            }
            root.removed = null;
        });
    }

    function pickAnotherKey() {
        shortcutField.forceActiveFocus(Qt.TabFocusReason);
        shortcutField.edit(keys.indexOf(found.key));
    }

    Component.onDestruction: {
        life.gone = true;
        if (removed !== null && capture !== null) capture.releaseUserBind(removed.token);
        if (edits !== null) edits.forget(root);
    }
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

    hint: removed !== null ? "Removed line " + removed.line + " of " + removed.place + "."
        : defaultKeys.length === 0 ? "No default shortcut." : "Default shortcut: " + defaultLabel + "."
    error: problem
    hintLink: citedLine === null || citedLine.config === "" ? "" : citedLine.place + " line " + citedLine.line
    onHintLinkActivated: if (citedLine !== null) lineAsked(citedLine)

    hintActions: [
        Button {
            objectName: "removeUserLine"
            text: "Remove my line"
            size: "sm"
            variant: "secondary"
            visible: root.editable && root.userLine !== null && root.removed === null
            onClicked: root.removalAsked(root.userLine)
        },
        Button {
            objectName: "pickAnotherKey"
            text: "Pick another key"
            size: "sm"
            variant: "secondary"
            visible: root.editable && root.userHolds && root.capture !== null
            onClicked: root.pickAnotherKey()
        },
        Button {
            objectName: "useMyBinding"
            text: "Use my binding"
            size: "sm"
            variant: "secondary"
            visible: root.editable && root.userHolds
            onClicked: root.remove(root.keys.indexOf(root.found.key))
        },
        Button {
            objectName: "undoUserLine"
            text: "Undo"
            size: "sm"
            variant: "secondary"
            visible: root.editable && root.removed !== null
            onClicked: root.undoRemoval()
        }
    ]

    actions: [
        IconButton {
            iconName: "rotate-ccw"
            label: "Reset to " + root.defaultLabel
            size: "sm"
            visible: root.editable && root.defaultKeys.length > 0 && JSON.stringify(root.keys) !== JSON.stringify(root.defaultKeys)
            onClicked: root.applyKey(undefined)
        },
        IconButton {
            iconName: "plus"
            label: "Add another key"
            size: "sm"
            visible: root.editable && root.capture !== null
            onClicked: root.shortcutField.add()
        }
    ]
}
