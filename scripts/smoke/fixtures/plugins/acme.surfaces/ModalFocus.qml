import QtQuick
import qs.Commons
import qs.Ui

// Read the production modal's card, including its separate window.
Item {
    id: root
    property var reader

    function noDescription() { modal.message = ""; }

    readonly property var evidence: {
        const surface = reader.modalSurface(modal);
        if (surface === null) return { loaded: false };
        const card = reader.modalCard(modal);
        if (card === null) return { loaded: true, card: false };
        const pane = card.children.find(child => child.container === "dialog");
        const titles = reader.displayedTextItems(pane).filter(item => reader.displayedText(item) === modal.title);
        if (titles.length !== 1) return { loaded: true, card: true, title: false };
        const layout = reader.paneContentFacts(pane);
        return { loaded: true, card: true, focused: card.activeFocus,
            ring: card.buttons().some(button => button.visualFocus),
            gap: layout.footerTop - layout.titleBlockBottom,
            titleSpace: Theme.stack.titleSpace, description: card.message !== "" };
    }

    ModalDialog {
        id: modal
        shown: true
        title: "Keep this setting?"
        message: "This description stays with its title."
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Keep", role: "accept" }]
        onRejected: shown = false
    }
}
