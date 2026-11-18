import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui

// Help belongs to the words it explains. LinkText owns their pointer,
// keyboard target, focus ring and wrapped underlines. The ModalDialog
// loader owns the screen-wide surface and releases it when help closes.
LinkText {
    id: root

    property string title: ""
    property string info: ""
    property Item returnFocus: root
    readonly property string label: title === "" ? "More information" : "About " + title
    readonly property bool infoOpen: dialog.shown
    signal infoPageActivated(string page, string tab)

    text: title
    link: info === "" ? "" : text
    role: "label"
    linkColor: color
    parseReferences: false
    dottedUnderline: true
    underlineAtRest: true
    Accessible.name: info === "" ? text : label

    property bool returnWasVisual: false
    function openInfo(byKey) {
        if (info === "") return;
        returnWasVisual = byKey === undefined ? visualFocus : byKey;
        dialog.shown = true;
    }
    function closeInfo() {
        if (!dialog.shown) return;
        dialog.shown = false;
        // Wait until the overlay releases its keyboard before restoring the
        // caller's window and the label's original focus indication.
        Qt.callLater(() => {
            if (root === null || dialog.shown || root.returnFocus === null) return;
            if (root.returnFocus.Window.window !== null) root.returnFocus.Window.window.requestActivate();
            root.returnFocus.forceActiveFocus(root.returnWasVisual ? Qt.TabFocusReason : Qt.MouseFocusReason);
        });
    }
    onActivated: openInfo()
    onInfoChanged: if (info === "") dialog.shown = false

    ModalDialog {
        id: dialog
        title: root.title
        screenOwner: root.returnFocus
        dismissOnOutside: true
        actions: [{ label: "Close", role: "cancel", focused: true }]
        onRejected: root.closeInfo()
        body: Column {
            spacing: Theme.space.md
            Repeater {
                model: root.info.split("\n")
                LinkText {
                    required property string modelData
                    width: parent.width
                    role: Theme.dialog.bodyRole
                    text: modelData
                    wrapMode: Text.Wrap
                    onPageActivated: (page, tab) => {
                        root.closeInfo();
                        root.infoPageActivated(page, tab);
                    }
                }
            }
        }
    }
}
