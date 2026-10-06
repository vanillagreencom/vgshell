import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui

// A square button with one icon and no text. `label` is what a screen
// reader and a tooltip say for it; a button without one is logged, since
// an icon alone names nothing. The ghost variant is the default, so a row
// of icon buttons draws no fills until one is hovered. A ghost button's
// icon rests in `color.textMuted` and takes the variant's foreground on
// hover, focus, press or checked; a filled variant's icon keeps its
// foreground, which its fill is chosen to carry. The rest colour is
// opaque, not a faded foreground: an icon's stroke overlaps itself at its
// joins, so an icon drawn translucent shows each overlap brighter. A
// disabled button fades once on the whole control. The icon is
// the size's own, `button.size.<size>.icon`, centred on whole pixels.
// `glyphStart` and `glyphEnd` are the distances from the box's edges to
// the glyph's painted ink: a header that puts a glyph, not a box, on its
// content edge shifts the button by them (design-layout.md § Headers).
// When `info` is set, the button opens an anchored dialog explaining that
// row. Close, Escape or a press outside closes it and returns focus to the
// button.
Button {
    id: root

    property string label: ""
    property string infoTitle: ""
    property string info: ""
    readonly property real glyphStart: leftPadding + contentItem.painted[0]
    readonly property real glyphEnd: rightPadding + contentItem.size - contentItem.painted[2]
    property var infoWindow: null
    readonly property bool infoOpen: infoWindow !== null && infoWindow.tracker.popup.visible
    property bool infoReturnWasVisual: false
    property bool infoReturning: false

    function openInfo(reason) {
        const popup = ensureInfoWindow();
        if (popup === null) return;
        infoReturnWasVisual = root.visualFocus;
        infoReturning = true;
        popup.open(reason === undefined ? Qt.TabFocusReason : reason);
    }

    function closeInfo() {
        if (infoWindow !== null) infoWindow.close();
    }

    function infoClosed() {
        if (!infoReturning) return;
        const reason = infoReturnWasVisual ? Qt.TabFocusReason : Qt.MouseFocusReason;
        const closed = infoWindow;
        infoWindow = null;
        Qt.callLater(() => {
            if (Window.window !== null) Window.window.requestActivate();
            forceActiveFocus(reason);
            infoReturning = false;
            if (closed !== null) closed.destroy();
        });
    }

    function ensureInfoWindow() {
        if (info === "") return null;
        if (infoWindow !== null) return infoWindow;
        const popover = Qt.createComponent(Qt.resolvedUrl("../overlay/Popover.qml"));
        if (popover.status !== Component.Ready) {
            console.error("IconButton: info dialog failed to build: " + popover.errorString());
            return null;
        }
        // A Window child has a top-level lifetime even while hidden, so the
        // popover is built only for buttons that show an explanation.
        infoWindow = popover.createObject(root);
        if (infoWindow === null) console.error("IconButton: info dialog failed to build");
        const dialogComponent = Qt.createComponent(Qt.resolvedUrl("../feedback/Dialog.qml"));
        if (dialogComponent.status !== Component.Ready) {
            console.error("IconButton: info dialog content failed to build: " + dialogComponent.errorString());
            destroyInfoWindow();
            return null;
        }
        const dialog = dialogComponent.createObject(infoWindow);
        if (dialog === null) {
            console.error("IconButton: info dialog content failed to build");
            destroyInfoWindow();
            return null;
        }
        const popup = infoWindow;
        dialog.width = Qt.binding(() => popup.width);
        dialog.modal = true;
        dialog.availableHeight = Qt.binding(() => popup.availableHeight);
        dialog.title = Qt.binding(() => root.infoTitle !== "" ? root.infoTitle : root.label);
        dialog.message = Qt.binding(() => root.info);
        dialog.actions = [{ label: "Close", role: "cancel", focused: true }];
        dialog.rejected.connect(root.closeInfo);
        infoWindow.content = [dialog];
        infoWindow.width = Qt.binding(() => OverlayState.widthFor(root, Theme.dialog.width));
        infoWindow.openedChanged.connect(() => Qt.callLater(() => { if (popup.opened === false) root.infoClosed(); }));
        return infoWindow;
    }

    function destroyInfoWindow() {
        if (infoWindow === null) return;
        const old = infoWindow;
        infoWindow = null;
        old.destroy();
    }

    variant: "ghost"
    leftPadding: Math.floor((controlHeight - sizeTokens.icon) / 2)
    rightPadding: leftPadding
    topPadding: leftPadding
    bottomPadding: leftPadding
    implicitWidth: controlHeight
    Accessible.name: label

    Component.onCompleted: if (label === "") console.error("IconButton: label is required, icon=" + JSON.stringify(iconName))
    Component.onDestruction: destroyInfoWindow()
    onInfoChanged: if (info === "") destroyInfoWindow()
    onClicked: if (info !== "") openInfo(visualFocus ? Qt.ShortcutFocusReason : Qt.MouseFocusReason)

    contentItem: Icon {
        name: root.iconName
        size: root.sizeTokens.icon
        color: root.variant === "ghost" && root.enabled && !(root.hovered || root.visualFocus || root.down || root.checked) ? Theme.color.textMuted : root.foreground
        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
    }

    Tooltip {
        text: root.label
    }
}
