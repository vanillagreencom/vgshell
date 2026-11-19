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
    property bool returningFocus: false
    readonly property var returnWindow: returnFocus === null ? null : returnFocus.Window.window
    onReturnWindowChanged: if (returningFocus) returnRequest.restart()
    function openInfo(byKey) {
        if (info === "") return;
        returningFocus = false;
        returnWasVisual = byKey === undefined ? visualFocus : byKey;
        dialog.shown = true;
    }
    function finishReturnFocus() {
        if (!returningFocus) return;
        if (dialog.shown || returnFocus === null) { returningFocus = false; return; }
        if (returnWindow === null || !returnWindow.active) return;
        returningFocus = false;
        const target = returnFocus;
        const reason = returnWasVisual ? Qt.TabFocusReason : Qt.MouseFocusReason;
        target.forceActiveFocus(reason);
        // Re-focusing an already active Control can retain its previous
        // reason, as KeyNavLogic.focusNavigation also accounts for.
        if (target.activeFocus && "focusReason" in target) target.focusReason = reason;
    }
    function requestReturnFocus() {
        if (!returningFocus) return;
        if (dialog.shown || returnFocus === null) { returningFocus = false; return; }
        if (returnWindow === null || !returnWindow.visible) return;
        returnWindow.requestActivate();
        finishReturnFocus();
    }
    function closeInfo() {
        if (!dialog.shown) return;
        dialog.shown = false;
        // Wait until the overlay releases its keyboard before restoring the
        // caller. Native activation is asynchronous; apply the input reason
        // after that acknowledgement, not before a FocusIn can replace it.
        // https://doc.qt.io/qt-6/qwindow.html#requestActivate
        returningFocus = true;
        returnRequest.restart();
    }
    Connections {
        target: root.returningFocus ? root.returnWindow : null
        function onActiveChanged() { returnFinish.restart(); }
        function onVisibleChanged() { returnRequest.restart(); }
    }
    // The next event turn, as Qt.callLater, but owned by this label: a
    // help link whose page replaces the caller destroys these with it, so
    // no deferred return runs in a destroyed context.
    Timer { id: returnRequest; interval: 0; onTriggered: root.requestReturnFocus() }
    Timer { id: returnFinish; interval: 0; onTriggered: root.finishReturnFocus() }
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
