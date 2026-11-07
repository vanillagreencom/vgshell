import QtQuick
import qs.Commons

// The Agent Debug window, on one of two screens its payload names. `{}`:
// the recovery choice (RecoveryChoice.qml), a diagnosis whose saved
// message target could not open. `{"draft": true}`: a failure another
// plugin handed over (DiagnoseDraft.qml). The service holds both; each
// screen asks it through the plugin's IPC. The window shows one screen at
// a time, so a summon that turns it to the other screen, and its close,
// discard what the screen it leaves holds in the service.
FocusScope {
    id: root
    property var shell: null
    // The screen shown: "choice", "draft", or "" before the first open.
    property string mode: ""
    readonly property Item initialFocus: shown.item === null ? null : shown.item.initialFocus
    implicitWidth: Theme.size.panel.lg
    implicitHeight: shown.item === null ? 0 : shown.item.implicitHeight

    function open(payload) {
        const wanted = payload ? JSON.parse(payload) : {};
        const next = wanted.draft === true ? "draft" : "choice";
        if (mode !== "" && mode !== next) shown.item.discard();
        mode = next;
        shown.item.open();
    }
    function close() {
        if (shell === null || shown.item === null) return;
        shown.item.discard();
    }

    // A Loader builds its item when the component is set, before open()
    // reads it, and lets the item it replaces go on a later turn of the
    // event loop (QQuickLoaderPrivate::clear calls deleteLater), so a
    // screen whose call turned the window keeps running to its end.
    Loader {
        id: shown
        anchors.fill: parent
        focus: true
        sourceComponent: root.mode === "draft" ? draftPage : root.mode === "choice" ? choicePage : null
    }
    Component {
        id: choicePage
        RecoveryChoice { shell: root.shell }
    }
    Component {
        id: draftPage
        DiagnoseDraft { shell: root.shell }
    }
}
