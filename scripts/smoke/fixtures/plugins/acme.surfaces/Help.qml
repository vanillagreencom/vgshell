import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Read the shipped help route from whichever real host owns this fixture.
Item {
    id: root
    width: 280
    height: help.implicitHeight

    function openInfo() { help.openInfo(); }
    function closeInfo() { help.closeInfo(); }
    readonly property bool opened: help.infoOpen

    function descendants(item) {
        const out = [item];
        for (let i = 0; i < out.length; i++)
            for (const child of out[i].children || []) out.push(child);
        return out;
    }

    readonly property var evidence: {
        const modal = descendants(help).find(item => item.body !== undefined && item.shown !== undefined);
        const loader = modal === undefined ? null : modal.children.find(item => item instanceof Loader);
        const surface = loader === null || loader === undefined ? null : loader.item;
        const noHoverCopy = help.tooltip === undefined && !descendants(help).some(item => item.details !== undefined && item.anchorItem !== undefined);
        if (surface === null) return { loaded: false, noHoverCopy: noHoverCopy };
        const card = surface.contentItem.children.find(item => item.modal === true);
        if (card === undefined) return { loaded: true, card: false, noHoverCopy: noHoverCopy };
        const at = card.mapToItem(surface.contentItem, 0, 0);
        const output = surface.screen;
        const centred = output !== null && Math.abs(at.x + card.width / 2 - surface.contentItem.width / 2) <= 1
            && Math.abs(at.y + card.height / 2 - surface.contentItem.height / 2) <= 1;
        return { loaded: true, card: true, opened: help.infoOpen,
            screen: output === null ? "" : output.name,
            callerScreen: root.QsWindow.window === null ? "" : root.QsWindow.window.screen.name,
            centred: centred, box: [at.x, at.y, card.width, card.height],
            focused: card.activeFocus, mapped: surface.backingWindowVisible,
            scrim: surface.contentItem.children.some(item => item.scrim === true && item.visible),
            noHoverCopy: noHoverCopy, placement: surface.placement };
    }

    InfoButton {
        id: help
        width: parent.width
        title: "Surface help"
        info: "A useful condition for this control.\nSee [its settings](page:acme.surfaces/Settings)."
    }
}
