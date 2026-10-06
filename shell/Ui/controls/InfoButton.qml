import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui

// A small info icon that opens one explanation in a dialog. Pointer,
// Space, Enter or Return opens it. Close, Escape or a press outside closes
// it and returns focus to the icon.
IconButton {
    id: root

    property string title: ""
    property string info: ""
    property var popup: null
    readonly property bool infoOpen: popup !== null && popup.opened

    iconName: "info"
    label: title === "" ? "More information" : "About " + title
    size: "sm"

    property bool returnWasVisual: false
    property bool returning: false

    function openInfo(reason) {
        if (info === "") return;
        const made = ensurePopup();
        if (made === null) return;
        returnWasVisual = visualFocus;
        returning = true;
        made.open(reason === undefined ? Qt.TabFocusReason : reason);
    }

    function closeInfo() {
        if (popup !== null) popup.close();
    }

    function infoClosed() {
        if (!returning) return;
        const reason = returnWasVisual ? Qt.TabFocusReason : Qt.MouseFocusReason;
        const closed = popup;
        popup = null;
        Qt.callLater(() => {
            if (Window.window !== null) Window.window.requestActivate();
            forceActiveFocus(reason);
            returning = false;
            if (closed !== null) closed.destroy();
        });
    }

    function ensurePopup() {
        if (popup !== null) return popup;
        popup = infoComponent.createObject(root);
        if (popup === null) console.error("InfoButton: dialog failed to build");
        return popup;
    }

    function destroyPopup() {
        if (popup === null) return;
        const old = popup;
        popup = null;
        old.destroy();
    }

    onClicked: openInfo(visualFocus ? Qt.ShortcutFocusReason : Qt.MouseFocusReason)
    onInfoChanged: if (info === "") destroyPopup()
    Component.onDestruction: destroyPopup()

    Component {
        id: infoComponent

        Popover {
            id: pop

            width: OverlayState.widthFor(root, Theme.dialog.width)
            onOpenedChanged: if (!opened) root.infoClosed()

            Dialog {
                width: pop.width
                modal: true
                availableHeight: pop.availableHeight
                title: root.title
                message: root.info
                actions: [{ label: "Close", role: "cancel", focused: true }]
                onRejected: root.closeInfo()
            }
        }
    }
}
