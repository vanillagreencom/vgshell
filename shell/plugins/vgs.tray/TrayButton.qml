import QtQuick
import qs.Commons
import qs.Ui
import "TrayLogic.js" as TrayLogic

// One app's tray icon: a BarItem that draws the app's own icon. A left
// click activates the app, or opens its menu when the app offers only a
// menu; a middle click is the app's secondary action, and the wheel
// scrolls it, as a volume icon turns its volume. A right click opens the
// app's menu under the icon (TrayMenu), built on the click and released
// once it closes. An app without a menu leaves the right click to the
// widget's frame menu.
BarItem {
    id: root

    property var trayItem: null
    property color tint: Theme.bar.foreground
    // An app that quits takes its item away before the bar drops its icon;
    // until then the icon draws nothing and takes no input.
    readonly property bool live: trayItem !== null && trayItem !== undefined
    readonly property bool menuOpen: menuUi.item !== null && menuUi.item.opened

    function openMenu() {
        if (!live || !trayItem.hasMenu) return;
        menuUi.active = true;
        menuUi.item.open();
    }

    enabled: live
    label: TrayLogic.labelOf(trayItem)
    tooltip: TrayLogic.tooltipOf(trayItem)
    onClicked: {
        if (trayItem.onlyMenu) openMenu();
        else trayItem.activate();
    }
    // Shift+F10 and the Menu key open the menu, as a right click does.
    Keys.onPressed: event => {
        if (KeyNavLogic.intent(event.key, event.modifiers, "horizontal", false) !== "menu") return;
        event.accepted = true;
        openMenu();
    }

    contentItem: TrayIcon {
        source: root.live ? root.trayItem.icon : ""
        size: Theme.bar.item.icon
        tint: root.tint
    }

    // keyboard-path: the bar takes no keyboard focus (design-system.md § Keyboard); a focused icon opens its menu on Shift+F10 or the Menu key, and the app's own window and keys carry its other actions
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.RightButton
        // The press of a right click on an app without a menu goes on to
        // the widget's frame menu. The area reads each press's button
        // itself: in the nested sandbox it was handed left presses too,
        // which belong to the BarItem's own click.
        onPressed: mouse => mouse.accepted = mouse.button === Qt.MiddleButton || (mouse.button === Qt.RightButton && root.trayItem.hasMenu)
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) root.trayItem.secondaryActivate();
            else if (mouse.button === Qt.RightButton) root.openMenu();
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y !== 0) root.trayItem.scroll(wheel.angleDelta.y, false);
            if (wheel.angleDelta.x !== 0) root.trayItem.scroll(wheel.angleDelta.x, true);
        }

        PointerCursor {}
    }

    Loader {
        id: menuUi
        anchors.fill: parent
        active: false
        sourceComponent: TrayMenu {
            trayItem: root.trayItem
            title: root.label
            onClosed: Qt.callLater(() => menuUi.active = false)
        }
    }
}
