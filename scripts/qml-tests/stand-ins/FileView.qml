import QtQuick

// Stands in for Quickshell.Io's FileView, whose plugin does not load outside
// the shell. It arms an initial read and watcher when a path is assigned, so
// a test can create a view and then set its path as production QML does. It
// has the Quickshell 0.3.1 behaviours WatchedFile rests on: a reload while the view's read is
// outstanding, a result handler included, starts nothing; a reload of a
// watching view builds its watcher again; and a view that blocks on its
// writes takes the bytes, drops an outstanding read unreported and reports
// the write before setText returns, while one that does not returns with
// the write outstanding. Nothing touches a disk: the test finishes each
// read and plants a write's failure.
QtObject {
    id: view

    property string path
    property bool preload: true
    property bool watchChanges: false
    property bool printErrors: true
    // Taken and not read: the test finishes every read by hand.
    property bool blockLoading: false
    property bool atomicWrites: false
    property bool blockWrites: false
    // The error the next blocking write reports in place of `saved`, 0 for
    // none.
    property int failNextWrite: 0

    // What the test reads back: the operation outstanding (`read`, `write`
    // or ""), how many reads started, how many reloads were asked, how many
    // watchers were built and the last bytes a write took.
    property string live: ""
    property int reads: 0
    property int reloads: 0
    property int watchers: 0
    property string written: ""
    property string content: ""
    property string armedPath: ""

    signal loaded()
    signal loadFailed(int error)
    signal saved()
    signal saveFailed(int error)
    signal fileChanged()

    function text() { return content; }

    function start() {
        if (live !== "") return;
        live = "read";
        reads += 1;
    }

    function reload() {
        reloads += 1;
        if (preload) start();
        if (watchChanges) watchers += 1;
    }

    function setText(bytes) {
        written = bytes;
        if (!blockWrites) {
            live = "write";
            return;
        }
        live = "";
        content = bytes;
        const error = failNextWrite;
        failNextWrite = 0;
        if (error !== 0) saveFailed(error);
        else saved();
    }

    // The result of the outstanding read, reported while the view still
    // holds it; a read a handler asks for meanwhile starts nothing.
    function report(emitResult) {
        emitResult();
        live = "";
    }

    function finishRead(bytes) {
        content = bytes;
        report(() => loaded());
    }

    function failRead(error) { report(() => loadFailed(error)); }

    function change() { fileChanged(); }

    function armPath() {
        if (path === "") return;
        if (path === armedPath) return;
        armedPath = path;
        if (preload) start();
        if (watchChanges) watchers += 1;
    }

    onPathChanged: armPath()

    Component.onCompleted: {
        armPath();
    }
}
