import QtQuick

// Stay awake holds and one plain idle watch for
// scripts/smoke/rows/stay-awake.sh, which reads them through the core's
// lending record. IPC: `hold <seconds>` takes one more hold and answers
// `ok` or the core's refusal; `release` runs the oldest hold's disposer;
// `ends` counts the end calls the core made; `watch <seconds>` replaces
// the watch.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property var holds: []
    property int ends: 0
    property var watchDisposer: null

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("hold", arg => {
            try {
                root.holds = root.holds.concat([root.shell.idle.stayAwake(Number(arg), () => {
                    root.ends += 1;
                    console.info("stayawake: the timer ended a hold ends=" + root.ends);
                })]);
            } catch (e) {
                return e.message;
            }
            return "ok";
        });
        shell.ipc.handle("release", () => {
            if (root.holds.length === 0) return "none";
            const dispose = root.holds[0];
            root.holds = root.holds.slice(1);
            dispose();
            return "ok";
        });
        shell.ipc.handle("ends", () => String(root.ends));
        shell.ipc.handle("watch", arg => {
            if (root.watchDisposer !== null) root.watchDisposer();
            root.watchDisposer = root.shell.idle.watch(Number(arg), () => {});
            return "ok";
        });
    }
}
