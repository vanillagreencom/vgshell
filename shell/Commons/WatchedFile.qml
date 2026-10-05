import QtQuick
import Quickshell
import Quickshell.Io

// One file read again whenever it changes, and written through the same
// view. Two Quickshell FileView behaviours drop a change otherwise
// (docs/architecture/runtime-qml.md): a reload rebuilds the reloading
// view's own watcher after its read has started, so a change landing in
// between raises no notification; and a reload while a read is in flight
// starts nothing, so the read reports the file as it was. One view holds
// the watcher and is never read or reloaded; the other reads and writes and
// watches nothing. A change or a read() during a read marks that read
// stale: its result is dropped unreported and the file is read again once
// the handler returns, so `loaded` and `loadFailed` report only a read no
// change overtook. The first read starts when the view is built. The view
// reports a read's result while it still holds that read, and a reload
// asked from an owner's handler then starts nothing, so every read reaches
// the view once the handler returns.
//
// A write is on the disk, and reported, before write() returns: SIGTERM
// ends the shell with no handler run, so a write still waiting when the
// owner answered would be lost with the shell. The view therefore blocks on
// its writes. Such a write drops a read in flight unreported, so the file
// is read again after it.
Scope {
    id: file

    required property string path
    // The one operation on the file: `reading` from the first, which the
    // reading view starts when `path` is set; `stale` when a change or a
    // read() landed during the read; `writing` inside write(); `idle`.
    property string operation: "reading"
    readonly property bool busy: operation !== "idle"
    readonly property bool inRead: operation === "reading" || operation === "stale"

    signal loaded(string content)
    signal loadFailed(var error)
    signal saved()
    signal saveFailed(var error)
    // The file changed while no read was in flight.
    signal changed()

    // Read the file now, or again once the read in flight ends.
    function read() {
        switch (operation) {
        case "idle":
            readLater();
            return;
        case "reading":
        case "stale":
            operation = "stale";
            return;
        }
        console.error("watched-file: unknown operation=" + operation + " path=" + path);
    }

    // Replace the file with `content`: `saved` or `saveFailed` is emitted
    // before this returns. FileView skips a write of the bytes it last read
    // or wrote, and a skipped write reports nothing, so the owner writes only
    // bytes that differ from those.
    function write(content) {
        const overtaken = inRead;
        operation = "writing";
        view.setText(content);
        if (overtaken) readLater();
    }

    function readLater() {
        operation = "reading";
        Qt.callLater(reloadView);
    }

    function reloadView() {
        view.reload();
    }

    // The read's result, or false when it was stale and a read follows.
    function settle() {
        if (operation === "stale") {
            readLater();
            return false;
        }
        if (operation !== "reading") console.error("watched-file: read finished outside a read operation=" + operation + " path=" + path);
        operation = "idle";
        return true;
    }

    function wrote() {
        if (operation !== "writing") console.error("watched-file: write finished outside a write operation=" + operation + " path=" + path);
        operation = "idle";
    }

    FileView {
        preload: false
        path: file.path
        watchChanges: true
        printErrors: false
        onFileChanged: file.inRead ? file.read() : file.changed()
    }

    FileView {
        id: view
        path: file.path
        printErrors: false
        blockWrites: true
        onLoaded: if (file.settle()) file.loaded(text())
        onLoadFailed: error => { if (file.settle()) file.loadFailed(error); }
        onSaved: {
            file.wrote();
            file.saved();
        }
        onSaveFailed: error => {
            file.wrote();
            file.saveFailed(error);
        }
    }
}
