import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui

// A small info icon for one explanation. Hover or keyboard focus shows the
// explanation in the icon's tooltip; pointer, Space, Enter or Return opens
// it in a modal dialog centred over the icon's window. Close, Escape or a
// press outside the dialog closes it and returns focus to the icon. A page
// reference in `info` (LinkText) is a link in the dialog: activating it
// closes the dialog and emits `infoPageActivated` with the page and tab,
// for the owner to open.
IconButton {
    id: root

    property string title: ""
    property string info: ""
    property var popup: null
    readonly property bool infoOpen: popup !== null && popup.opened
    signal infoPageActivated(string page, string tab)

    iconName: "info"
    label: title === "" ? "More information" : "About " + title
    tooltip: info === "" ? label : info
    size: "sm"

    property bool returnWasVisual: false
    property bool returning: false

    function openInfo() {
        if (info === "") return;
        const made = ensurePopup();
        if (made === null) return;
        returnWasVisual = visualFocus;
        returning = true;
        made.open();
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

    onClicked: openInfo()
    onInfoChanged: if (info === "") destroyPopup()
    Component.onDestruction: destroyPopup()

    // The dialog draws the one frame. Its popup lies on the icon's window,
    // anchored at that window's top-left (PopupAnchor's default edges and
    // gravity, Quickshell 0.3.1 src/core/popupanchor.hpp) and as large, so
    // its scrim washes every row of the window and the dialog sits centred
    // in it, `dialog.margin` inside the window's edges.
    Component {
        id: infoComponent

        Item {
            id: host

            readonly property bool opened: window.visible
            readonly property Item covered: root.Window.window === null ? null : root.Window.window.contentItem
            readonly property AnchorTracker tracker: AnchorTracker { popup: window; anchor: root }

            visible: false

            function open() {
                window.visible = true;
                Qt.callLater(() => dialog.forceActiveFocus(Qt.OtherFocusReason));
            }
            function close() { window.visible = false; }

            // The dialog's share of OverlayState, taken as Popover takes its own.
            property bool counted: false
            function share(open) {
                if (open === counted) return;
                counted = open;
                if (open) OverlayState.opened(); else OverlayState.closed();
            }
            Component.onDestruction: share(false)

            PopupWindow {
                id: window

                anchor.item: host.covered
                // A slide or a flip would move the scrim off the window.
                anchor.adjustment: PopupAdjustment.None
                grabFocus: true
                visible: false
                color: "transparent"
                implicitWidth: Math.max(1, host.covered === null ? 0 : host.covered.width)
                implicitHeight: Math.max(1, host.covered === null ? 0 : host.covered.height)
                onVisibleChanged: {
                    host.share(visible);
                    if (!visible) root.infoClosed();
                }

                DismissScope {
                    popup: window
                    anchor: root

                    Scrim { onClicked: root.closeInfo() }

                    Dialog {
                        id: dialog
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 2 * Theme.dialog.margin)
                        availableHeight: parent.height - 2 * Theme.dialog.margin
                        focus: true
                        modal: true
                        title: root.title
                        Accessible.description: PageReference.plain(root.info)
                        actions: [{ label: "Close", role: "cancel", focused: true }]
                        onRejected: root.closeInfo()

                        // Separate LinkText items keep explicit lines while
                        // StyledText folds line feeds inside one item. Repeater
                        // inserts its items in the Column (Qt Quick Repeater).
                        Column {
                            width: parent.width
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
            }
        }
    }
}
