import QtQuick
import qs.Commons
import qs.Ui

// Read the production modal's card, including its separate window.
Item {
    id: root

    function noDescription() { modal.message = ""; }

    readonly property var evidence: {
        const surface = modal.children[0].item;
        if (surface === null) return { loaded: false };
        const card = surface.contentItem.children.find(child => child.modal !== undefined);
        if (card === undefined) return { loaded: true, card: false };
        const pane = card.children.find(child => child.container === "dialog");
        const title = pane.children[0];
        const footer = pane.children[4];
        return { loaded: true, card: true, focused: card.activeFocus,
            ring: card.buttons().some(button => button.visualFocus),
            gap: footer.y - title.y - title.height,
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
