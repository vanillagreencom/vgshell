import QtQuick

// Holds the screen freeze through capability `screencopy`.
//   invoke freeze        holds it; the reply, and each `done` answer in `answers`
//   invoke freeze-still  holds it with the still; each still answer in `stills`
//   invoke freeze-cursor the same with the pointer in the written frames
//   invoke freeze-early  holds it with the still and thaws at its `done`,
//                        before any frame can be written
//   invoke refuse <form> a hold with malformed options of FORM: options,
//                        still, cursor or lone-cursor; the refusal
//   invoke thaw          ends the hold; the reply
Item {
    id: root

    property var shell: null
    property var answers: []
    property var stills: []
    property bool registered: false

    function done(answer) {
        root.answers = root.answers.concat([answer]);
    }

    function still(answer) {
        root.stills = root.stills.concat([answer]);
    }

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("freeze", () => root.shell.screencopy.freeze(root.done));
        shell.ipc.handle("freeze-still", () => root.shell.screencopy.freeze(root.done, { still: root.still }));
        shell.ipc.handle("freeze-cursor", () => root.shell.screencopy.freeze(root.done, { still: root.still, cursor: true }));
        // The thaw comes at the end of the turn that answered `done`, so
        // before the next frame renders any band.
        shell.ipc.handle("freeze-early", () => root.shell.screencopy.freeze(answer => {
            root.done(answer);
            Qt.callLater(() => root.shell.screencopy.thaw());
        }, { still: root.still }));
        shell.ipc.handle("refuse", form => {
            const forms = { options: "frames", still: { still: "frames" }, cursor: { still: root.still, cursor: "yes" }, "lone-cursor": { cursor: true } };
            if (!(form in forms)) return "refused: form";
            try {
                return root.shell.screencopy.freeze(root.done, forms[form]);
            } catch (e) {
                return e.message;
            }
        });
        shell.ipc.handle("thaw", () => root.shell.screencopy.thaw());
    }
}
