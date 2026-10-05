pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "PluginLogic.js" as Logic

// Shell configuration: the shipped defaults under config/ merged with the
// user's file. Both files are watched; a change re-derives `effective`
// once. Each file's state is one tagged value. A file that does not parse
// or fails PluginLogic.configError keeps the last good value and logs the
// error, so a typo never blanks the desktop; a user file in that state
// blocks writes until it passes again, so a manager edit never overwrites
// unread edits. Nothing is built before `ready`: the shipped file has
// loaded once and the user file has settled, so a bar never draws from the
// user file alone. Each file is a WatchedFile, so an edit that lands during
// a read is read again. An edit of the user file is on the disk before its
// write answers.
Singleton {
    id: root

    readonly property string shippedPath: Quickshell.shellDir + "/../config/shell.json"
    readonly property string userDir: Paths.configDir
    readonly property string userPath: userDir + "/shell.json"

    // null until the shipped file loaded once; a later failure keeps the
    // last good value.
    property var shipped: null
    property var user: null
    property var shippedText: null
    property var userText: null
    // "pending" until the first answer, then "loaded", "unparseable",
    // "unreadable" or "malformed" (parsed, refused by configError); the user
    // file may also be "absent". A file that was loaded once keeps its last
    // good value through a later failure.
    property string shippedState: "pending"
    property string userState: "pending"
    // What holds the configuration back, or "" once it is ready: the
    // shipped file's state while it has never loaded ("pending" until its
    // first answer, then the failure that stays until the file is fixed),
    // "pending" while the user file has not settled.
    readonly property string notReady: shipped === null ? shippedState : (userState === "pending" ? "pending" : "")
    readonly property bool ready: notReady === ""
    readonly property var effective: shipped === null ? ({}) : Logic.effectiveConfig(shipped, user)

    // Judge one file's text: { state, value } with `value` only when loaded.
    function judge(label, text) {
        let value;
        try {
            value = JSON.parse(text);
        } catch (e) {
            console.error("config: " + label + " does not parse: " + e.message);
            return { state: "unparseable" };
        }
        const bad = Logic.configError(value);
        if (bad !== "") {
            console.error("config: " + label + " malformed: " + bad);
            return { state: "malformed" };
        }
        return { state: "loaded", value: value };
    }

    WatchedFile {
        id: shippedView
        path: root.shippedPath
        onChanged: read()
        onLoaded: content => {
            if (root.shippedState === "loaded" && content === root.shippedText) return;
            const r = root.judge(path, content);
            if (r.state === "loaded") {
                if (content !== root.shippedText) root.shipped = r.value;
                root.shippedText = content;
            }
            root.shippedState = r.state;
        }
        onLoadFailed: error => {
            console.error("config: shipped defaults unreadable at " + path + ": " + error);
            root.shippedState = "unreadable";
        }
    }

    WatchedFile {
        id: userView
        path: root.userPath
        onChanged: read()
        onLoaded: content => {
            root.saveError = "";
            if (content === root.userText) {
                // The disk holds what it held: a write's own notification,
                // or a file readable again.
                root.userState = "loaded";
                return;
            }
            const r = root.judge(path, content);
            if (r.state === "loaded") {
                root.user = r.value;
                root.userText = content;
            }
            root.userState = r.state;
        }
        onLoadFailed: error => {
            root.saveError = "";
            if (error === FileViewError.FileNotFound) {
                root.user = null;
                root.userText = null;
                root.userState = "absent";
            } else {
                console.error("config: user file unreadable at " + path + ": " + error);
                root.userState = "unreadable";
            }
        }
        onSaveFailed: error => {
            console.error("config: user file not written at " + path + ": " + error);
            root.saveError = String(error);
            // FileView keeps the bytes of a failed write and skips a later
            // write of the same bytes, so the file is read again before
            // another write is taken.
            read();
        }
    }

    // The error of a write the disk refused, held until the file is read
    // again.
    property string saveError: ""

    // Replace the user file whole. Refused unless the file was read or is
    // absent, so an unparseable, malformed or unreadable file is never
    // overwritten unread, and after a write the disk refused until the file
    // is read again. `ok` means the file holds the value. Returns `ok` or
    // the keyed refusal.
    function writeUser(value) {
        if (userState !== "loaded" && userState !== "absent") return "refused: user-config=" + userState + " path=" + userPath;
        if (saveError !== "") return "refused: user-config=unwritable path=" + userPath + " error=" + saveError;
        const content = JSON.stringify(value, null, 2) + "\n";
        if (content === userText) return "ok";
        userView.write(content);
        if (saveError !== "") return "refused: user-config=unwritable path=" + userPath + " error=" + saveError;
        user = value;
        userText = content;
        userState = "loaded";
        return "ok";
    }

    function reload() {
        shippedView.read();
        userView.read();
    }
}
