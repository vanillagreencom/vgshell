import QtQuick

// Holds the screen freeze through capability `screencopy`.
//   invoke freeze        holds it; the reply, and each `done` answer in `answers`
//   invoke freeze-cursor the same with the pointer in the sole held view
//   invoke crop <JSON>   {geometry:{x,y,width,height},path}; answers in `crops`
//   invoke crop-early <JSON> starts that crop, then thaws before its grab
//   invoke refuse <form> a hold with malformed options of FORM: options,
//                        cursor or unknown; the refusal
//   invoke thaw          ends the hold; the reply
Item {
    id: root

    property var shell: null
    property var answers: []
    property var crops: []
    property bool registered: false

    function done(answer) {
        root.answers = root.answers.concat([answer]);
    }

    function cropped(answer) {
        root.crops = root.crops.concat([answer]);
    }

    function crop(arg, early) {
        const request = JSON.parse(arg);
        const reply = shell.screencopy.crop(request.geometry, request.path, root.cropped);
        if (early && reply === "ok") shell.screencopy.thaw();
        return reply;
    }

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("freeze", () => root.shell.screencopy.freeze(root.done));
        shell.ipc.handle("freeze-cursor", () => root.shell.screencopy.freeze(root.done, { cursor: true }));
        shell.ipc.handle("crop", arg => root.crop(arg, false));
        shell.ipc.handle("crop-early", arg => root.crop(arg, true));
        shell.ipc.handle("refuse", form => {
            const forms = { options: "frames", cursor: { cursor: "yes" }, unknown: { unsupported: true } };
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
