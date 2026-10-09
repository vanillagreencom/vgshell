import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The bar's service: the global shortcut and the IPC function that hide or
// show the bar on every screen, and the one reader of the browser profiles
// the Open with setting offers. It draws nothing; each registration's
// disposer is the core's, so a bar that stops being the active one releases
// them.
//   shortcut vgs.bar:toggle                 SUPER+SHIFT+SPACE from the
//                                            manifest's `hyprland` binds;
//                                            the launcher's Style row runs
//                                            it too (README)
//   vgshell ipc call vgs.bar invoke toggle ''  the same toggle
// The toggle flips the `hidden` setting through `configure`, so it holds
// across a restart; Bar.qml reads it as `shown`, which the bar host follows.
//
// The profiles are read once when the service starts and again each time
// the Settings page opens the Open with select, never on a poll: the
// `Local State` of each Chromium-family browser whose command the last
// requirement scan found, published as the `browserProfiles` choices once
// every read has ended (DesktopLaunch.openWithChoices).
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The shell this service registered with, so a settings change that
    // hands over a new object registers nothing twice.
    property var registeredWith: null
    // A profile read is under way: browser id -> its `Local State` text
    // for each browser read so far, an unreadable one left out, and the ids
    // still being read. An open during a read reads again once it ends.
    property bool reading: false
    property bool readAgain: false
    property var texts: ({})
    property var pending: []
    // The choices last published, as JSON, so an unchanged read writes
    // nothing and an open list keeps its rows.
    property string published: ""

    onShellChanged: {
        if (shell === null || registeredWith !== null) return;
        registeredWith = shell;
        shell.shortcut.register("toggle", "Hide or show the top bar", () => root.toggle());
        shell.ipc.handle("toggle", () => root.toggle());
        const reply = shell.status.handleRefresh("browserProfiles", () => root.readProfiles());
        if (reply !== "ok") console.warn("vgs.bar: profiles refresh " + reply);
        readProfiles();
    }

    function readProfiles() {
        if (reading) {
            readAgain = true;
            return;
        }
        const missing = shell.requirements.missing;
        reading = true;
        texts = {};
        pending = DesktopLaunch.BROWSERS.filter(b => missing.indexOf(b.command) === -1).map(b => b.id);
        if (pending.length === 0) {
            publishProfiles();
            return;
        }
        for (const view of profileViews.instances)
            if (pending.indexOf(view.modelData.id) !== -1) Qt.callLater(() => view.read());
    }

    function profileRead(id, text) {
        if (!reading || pending.indexOf(id) === -1) return;
        const next = Object.assign({}, texts);
        if (text !== null) next[id] = text;
        texts = next;
        pending = pending.filter(p => p !== id);
        if (pending.length === 0) publishProfiles();
    }

    function publishProfiles() {
        const choices = DesktopLaunch.openWithChoices(texts);
        reading = false;
        const json = JSON.stringify(choices);
        if (json !== published) {
            const reply = shell.status.set("browserProfiles", choices);
            if (reply === "ok") published = json;
            else console.warn("vgs.bar: profiles publish " + reply);
        }
        if (readAgain) {
            readAgain = false;
            readProfiles();
        }
    }

    // With preload off, reload unloads and text starts the asynchronous
    // read; a reload from inside a view's own handler starts nothing, so
    // each read starts from Qt.callLater. 0.3.1:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView
    Variants {
        id: profileViews
        model: DesktopLaunch.BROWSERS
        FileView {
            required property var modelData
            function read() {
                reload();
                text();
            }
            path: Paths.configHome + "/" + modelData.config + "/Local State"
            preload: false
            blockLoading: false
            watchChanges: false
            printErrors: false
            onLoaded: root.profileRead(modelData.id, text())
            onLoadFailed: error => {
                if (error !== FileViewError.FileNotFound) console.warn("vgs.bar: profiles unreadable path=" + path + " error=" + FileViewError.toString(error));
                root.profileRead(modelData.id, null);
            }
        }
    }

    // The configure capability's reply: `ok`, or its refusal.
    function toggle() {
        const reply = shell.configure.set("hidden", shell.settings.hidden !== true);
        if (reply !== "ok") console.warn("vgs.bar: toggle " + reply);
        return reply;
    }
}
