pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "PluginLogic.js" as Logic
import "ConfigLogic.js" as ConfigLogic

// Shell configuration: the shipped defaults under config/ merged with the
// user's file. Both files are watched; a change re-derives `effective`
// once. Each file's state is one tagged value. `effective` and `notReady`
// are assigned by publish() alone; a read or a write commits `shipped`,
// `user`, the file's text and state first, visible at once, so a write
// made from a handler of either builds on them, and its own change is told
// after the one in flight.
// A file that does not parse or fails ConfigLogic.configError keeps the
// last good value and logs the error, so a typo never blanks the desktop;
// a user file in that state
// blocks writes until it passes again, so a manager edit never overwrites
// unread edits. Nothing is built before `ready`: the shipped file has
// loaded once and the user file has settled, so a bar never draws from the
// user file alone. Each file is a WatchedFile, so an edit that lands during
// a read is read again. An edit of the user file is on the disk before its
// write answers. A user file of the previous format version is rewritten as
// this one when it is read (ConfigLogic.migrateConfig), through the same
// judge, and written once; one the judge refuses is never overwritten.
// A plugin id an installed plugin declares as a former id is renamed in the
// user file the same way (ConfigLogic.renamePlugins), by the map the scan
// hands adoptRenames.
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
    // Each former plugin id an installed plugin declares, to that plugin's
    // id (PluginLogic.formerIdClaims), set by adoptRenames alone.
    property var renames: ({})
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
    readonly property string notReady: publishedNotReady
    readonly property bool ready: notReady === ""
    readonly property var effective: publishedEffective
    // The effective `appearance` as JSON text, "" before `ready` or when
    // the file sets none, which Theme resolves over the theme. Text, so an
    // edit of another key, which replaces `effective`, compares equal and
    // the theme does not resolve again.
    readonly property string appearanceText: ready && Logic.isPlainObject(effective.appearance) ? JSON.stringify(effective.appearance) : ""

    Binding { target: Theme; property: "appearanceInput"; value: root.appearanceText }

    // What readers see, assigned by publish() alone, and the shipped and
    // user values the merge was made from.
    property string publishedNotReady: "pending"
    property var publishedEffective: ({})
    property var mergedShipped: null
    property var mergedUser: null
    property bool publishing: false
    property bool republish: false
    // True from a publish that stopped at the bound until one settles, so
    // a writer that never settles is logged once, not on every turn.
    property bool unsettled: false
    // The call stack, outside this file, of the last publish asked during
    // one: a handler's write.
    property string nestedWriter: ""

    // Tell readers the committed state: `effective` when the shipped or the
    // user value changed, then `notReady`, so the configuration turns ready
    // with its merge in place. A reader's handler runs inside the
    // assignment that told it, while the bindings between are still
    // updating, and Qt refuses to update a binding again from there: it
    // logs "Binding loop detected" and keeps the value it had, as
    // tst_config_writes.qml showed under qmltestrunner 6.11.2 with
    // `effective` a binding over `user`. A publish asked meanwhile, by a
    // write from such a handler, is therefore marked and runs once the
    // assignment returns. Each of those writes blocks on the disk, so one
    // publish repeats at most 16 times, each repeat taking every write its
    // handlers make, and the rest is told on a later turn of the event
    // loop, where the shell has answered its events: shipped writers settle
    // in two or three, as the Updates service's clear takes two, and a
    // handler that writes a fresh value on every change never settles.
    // `user` already holds every write, so the later publish drops none.
    function publish() {
        if (publishing) {
            republish = true;
            // QV4's Error.stack holds one `name@url:line` frame a line,
            // this function's first, under qmltestrunner 6.11.2; the frames
            // of this file are dropped, which leaves the handler's.
            const frames = new Error().stack.split("\n");
            const here = frames[0].slice(frames[0].indexOf("@"), frames[0].lastIndexOf(":") + 1);
            nestedWriter = frames.filter(frame => !frame.includes(here)).join(" < ");
            return;
        }
        publishing = true;
        let repeats = 0;
        do {
            republish = false;
            if (mergedShipped !== shipped || mergedUser !== user) {
                mergedShipped = shipped;
                mergedUser = user;
                publishedEffective = shipped === null ? ({}) : ConfigLogic.effectiveConfig(shipped, user);
                if (republish) continue;
            }
            const notReadyNow = shipped === null ? shippedState : (userState === "pending" ? "pending" : "");
            if (publishedNotReady !== notReadyNow) publishedNotReady = notReadyNow;
        } while (republish && ++repeats < 16);
        publishing = false;
        if (!republish) {
            unsettled = false;
            return;
        }
        if (!unsettled) console.warn("config: publish did not settle: repeats=" + repeats + " file=" + userPath + " writer=" + nestedWriter);
        unsettled = true;
        Qt.callLater(publish);
    }

    // Judge one file's text: { state, value, migrated, renamed } with
    // `value` only when loaded. With `migrate`, the user file's case, the
    // parsed value is migrated first and `migrated` says whether the
    // migration changed it; a loaded value then takes `renames`, and
    // `renamed` says whether that changed it.
    function judge(label, text, migrate) {
        let value;
        try {
            value = JSON.parse(text);
        } catch (e) {
            console.error("config: " + label + " does not parse: " + e.message);
            return { state: "unparseable" };
        }
        const moved = migrate ? ConfigLogic.migrateConfig(value) : { config: value, migrated: false };
        const bad = ConfigLogic.configError(moved.config);
        if (bad !== "") {
            console.error("config: " + label + " malformed: " + bad);
            return { state: "malformed" };
        }
        const renamed = migrate ? ConfigLogic.renamePlugins(moved.config, renames) : { config: moved.config, renamed: false };
        return { state: "loaded", value: renamed.config, migrated: moved.migrated, renamed: renamed.renamed };
    }

    WatchedFile {
        id: shippedView
        path: root.shippedPath
        onChanged: read()
        onLoaded: content => {
            if (root.shippedState === "loaded" && content === root.shippedText) return;
            const r = root.judge(path, content, false);
            if (r.state === "loaded") {
                if (content !== root.shippedText) root.shipped = r.value;
                root.shippedText = content;
            }
            root.shippedState = r.state;
            root.publish();
        }
        onLoadFailed: error => {
            console.error("config: shipped defaults unreadable at " + path + ": " + error);
            root.shippedState = "unreadable";
            root.publish();
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
            const r = root.judge(path, content, true);
            if (r.state === "loaded") root.userText = content;
            root.userState = r.state;
            // Written once, so the next read finds this version's file, and
            // before it is published, which writeUser does, so a write
            // made during that publish is not overwritten.
            if (r.migrated || r.renamed) {
                const written = root.writeUser(r.value);
                if (written === "ok") {
                    if (r.migrated) console.info("config: user file migrated: file=" + path + " version=" + ConfigLogic.CONFIG_VERSION);
                    if (r.renamed) console.info("config: user file plugins renamed: file=" + path);
                    return;
                }
                if (r.migrated) console.error("config: user file migrated in memory, not written: file=" + path + " version=" + ConfigLogic.CONFIG_VERSION + " refusal=" + written);
                if (r.renamed) console.error("config: user file plugins renamed in memory, not written: file=" + path + " refusal=" + written);
            }
            if (r.state === "loaded") root.user = r.value;
            root.publish();
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
            root.publish();
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
    // is read again. `ok` means the file holds the value. A write from a
    // handler publish() runs is on the file before it answers, and its
    // change is told after the one in flight, or on a later turn of the
    // event loop past publish()'s bound. Returns `ok` or the keyed refusal.
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
        publish();
        return "ok";
    }

    // Take the scan's rename map, MAP, and rename the user value by it, so
    // the file names each renamed plugin by its new id. Registry calls it
    // before it publishes the manifests, so nothing built from them reads a
    // former id; a user file read later takes the map in judge(). A value
    // the disk refuses to hold is renamed in memory, as a refused migrated
    // write is.
    function adoptRenames(map) {
        renames = map;
        if (user === null) return;
        const r = ConfigLogic.renamePlugins(user, renames);
        if (!r.renamed) return;
        const written = writeUser(r.config);
        if (written === "ok") {
            console.info("config: user file plugins renamed: file=" + userPath);
            return;
        }
        console.error("config: user file plugins renamed in memory, not written: file=" + userPath + " refusal=" + written);
        user = r.config;
        publish();
    }

    function reload() {
        shippedView.read();
        userView.read();
    }
}
