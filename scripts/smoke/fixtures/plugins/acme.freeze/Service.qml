import QtQuick

// Holds the screen freeze through capability `screencopy`.
//   invoke freeze   holds it; the reply, and each `done` answer in `answers`
//   invoke thaw     ends the hold; the reply
Item {
    id: root

    property var shell: null
    property var answers: []
    property bool registered: false

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("freeze", () => root.shell.screencopy.freeze(answer => { root.answers = root.answers.concat([answer]); }));
        shell.ipc.handle("thaw", () => root.shell.screencopy.thaw());
    }
}
