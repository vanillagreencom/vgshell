import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Read the shipped help route from whichever real host owns this fixture.
Item {
    id: root
    width: 280
    height: menuMode ? more.implicitHeight : help.implicitHeight
    property bool menuMode: false
    readonly property string helpTitle: "Surface help"
    readonly property string helpCopy: "A useful condition for this control.\nSee [its settings](page:acme.surfaces/Settings)."
    readonly property var activeHelp: menuMode ? descendants(menuEntry).find(item => item instanceof InfoButton) || null : help

    function openInfo() { if (activeHelp !== null) activeHelp.openInfo(); }
    function closeInfo() { if (activeHelp !== null) activeHelp.closeInfo(); }
    function openMenu(byKey) { menu.open(byKey ? "key" : "pointer"); }
    readonly property bool menuOpened: menu.opened
    readonly property bool opened: activeHelp !== null && activeHelp.infoOpen

    function descendants(item) {
        const out = [item];
        for (let i = 0; i < out.length; i++)
            for (const child of out[i].children || []) out.push(child);
        return out;
    }

    readonly property var evidence: {
        const label = activeHelp;
        const common = { opened: root.opened, menuOpened: root.menuOpened, openerFocused: more.activeFocus,
            openerVisual: more.visualFocus, callerScreen: root.QsWindow.window === null ? "" : root.QsWindow.window.screen.name };
        if (label === null) return Object.assign(common, { loaded: false });
        const modal = descendants(label).find(item => item.body !== undefined && item.shown !== undefined);
        const loader = modal === undefined ? null : modal.children.find(item => item instanceof Loader);
        const surface = loader === null || loader === undefined ? null : loader.item;
        const noHoverCopy = label.tooltip === undefined && !descendants(label).some(item => item.details !== undefined && item.anchorItem !== undefined);
        if (surface === null) return Object.assign(common, { loaded: false, noHoverCopy: noHoverCopy });
        const card = surface.contentItem.children.find(item => item.modal === true);
        if (card === undefined) return Object.assign(common, { loaded: true, card: false, noHoverCopy: noHoverCopy });
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
        onClicked: menu.open(visualFocus ? "key" : "pointer")
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
