import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Read the shipped help route from whichever real host owns this fixture.
Item {
    id: root
    width: 280
    height: menuMode ? more.implicitHeight : help.implicitHeight
    // Probe.popupLoad injects the test-only reader, never a shipped API.
    property var reader
    property bool menuMode: false
    readonly property string helpTitle: "Surface help"
    readonly property string helpCopy: "A useful condition for this control.\nSee [its settings](page:acme.surfaces/Settings)."
    readonly property var activeHelp: {
        const labels = reader.semanticLabelItems(menuMode ? menuEntry : help, true)
            .filter(item => reader.displayedText(item) === helpTitle);
        return labels.length === 1 ? labels[0] : null;
    }

    property string openingScreen: ""
    function rememberScreen() {
        const window = root.QsWindow.window;
        openingScreen = window === null ? "" : window.screen.name;
    }
    function openMenu(byKey) { rememberScreen(); menu.open(byKey ? "key" : "pointer"); }
    readonly property bool menuOpened: menu.opened
    readonly property bool opened: activeHelp !== null && activeHelp.infoOpen

    readonly property var evidence: {
        const label = activeHelp;
        const opener = root.menuMode ? more : help;
        const common = { opened: root.opened, menuOpened: root.menuOpened, openerFocused: opener.activeFocus,
            openerVisual: opener.visualFocus, activationVisual: label !== null && label.returnWasVisual,
            callerScreen: root.openingScreen };
        if (label === null) return Object.assign(common, { loaded: false });
        const card = reader.helpDialog(label);
        const noHoverCopy = label.tooltip === undefined && !reader.descendants(label).some(item => item.details !== undefined && item.anchorItem !== undefined);
        if (card === null) return Object.assign(common, { loaded: false, noHoverCopy: noHoverCopy });
        const surface = card.QsWindow.window;
        if (surface === null) return Object.assign(common, { loaded: true, card: false, noHoverCopy: noHoverCopy });
        const at = card.mapToItem(surface.contentItem, 0, 0);
        const output = surface.screen;
        const centred = output !== null && Math.abs(at.x + card.width / 2 - surface.contentItem.width / 2) <= 1
            && Math.abs(at.y + card.height / 2 - surface.contentItem.height / 2) <= 1;
        return Object.assign(common, { loaded: true, card: true,
            screen: output === null ? "" : output.name,
            centred: centred, box: [at.x, at.y, card.width, card.height],
            focused: card.activeFocus, mapped: surface.backingWindowVisible,
            scrim: surface.contentItem.children.some(item => item.scrim === true && item.visible),
            noHoverCopy: noHoverCopy, placement: surface.placement });
    }

    InfoButton {
        id: help
        visible: !root.menuMode
        width: parent.width
        title: root.helpTitle
        info: root.helpCopy
    }

    Button {
        id: more
        visible: root.menuMode
        text: "More"
        onClicked: root.openMenu(visualFocus)
        Menu {
            id: menu
            MenuItem {
                id: menuEntry
                text: root.helpTitle
                info: root.helpCopy
                helpReturnFocus: more
            }
        }
    }
}
