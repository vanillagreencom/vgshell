import QtQuick

// Stay awake holds for scripts/smoke/rows/stay-awake.sh, which reads them
// through the core's lending record. IPC: `hold <seconds>` takes one more
// hold and answers `ok` or the core's refusal; `release` ends the newest
// hold, one the timer ended among them; `ends` counts the end calls the
// core made.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property var holds: []
    property int ends: 0

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
            const hold = root.holds[root.holds.length - 1];
            root.holds = root.holds.slice(0, -1);
            hold.end();
            return "ok";
        });
        shell.ipc.handle("ends", () => String(root.ends));
    }
}
