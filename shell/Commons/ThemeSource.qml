import QtQuick
import Quickshell
import Quickshell.Io
import "Tokens.js" as Tokens
import "ThemeLogic.js" as ThemeLogic

// The theme file and the last document it accepted. Theme holds the one
// instance; this file is absent from qmldir, so no plugin can name it. The
// file is read the way Config reads shell.json: an absent file is the
// expected case and publishes the defaults, so a file removed while the
// shell runs draws what a fresh start without it would. A file that is
// unreadable or that the judge refuses is logged and leaves the last
// accepted theme; nothing of a refused document is published. WatchedFile
// reads it, so an edit that lands during a read is read again.
//
// The user's Appearance values, `userText`, resolve over the accepted theme
// here and nowhere else (ThemeLogic.withAppearance, D103), so every surface
// and the Hyprland layer read one result. A member the judge refuses is
// logged and shows as Set by theme.
Scope {
    id: source

    readonly property string path: Paths.configDir + "/theme.json"
    readonly property var defaults: ThemeLogic.defaults(Tokens.TOKENS)

    // shell.json `appearance` as JSON text, "" for none.
    property string userText: ""
    // The last accepted theme document, as ThemeLogic.accept answers it.
    property var accepted: defaults
    // The accepted theme: its name and its resolved values under the
    // user's Appearance values, a tree in the table's shape, and
    // `appearance`, withAppearance's `appearance` with `input`, the
    // userText it read. `revision` rises after all three hold the new
    // result.
    property string name: defaults.name
    property var values: defaults.values
    property var appearance: ThemeLogic.published(Tokens.TOKENS, defaults, "").appearance
    property int revision: 0
    // The file: `pending` until its first read, then `loaded`, `absent`,
    // `refused` or `unreadable`.
    property string state: "pending"

    onUserTextChanged: publish(accepted)

    function publish(next) {
        const result = ThemeLogic.published(Tokens.TOKENS, next, userText);
        for (const line of result.logs) console.error(line);
        accepted = next;
        name = next.name;
        values = result.values;
        appearance = result.appearance;
        revision += 1;
    }

    WatchedFile {
        path: source.path
        onChanged: read()
        onLoaded: content => {
            const judged = ThemeLogic.accept(Tokens.TOKENS, content);
            if (!judged.ok) {
                console.error(ThemeLogic.refusalLine(judged) + " file=" + path);
                source.state = "refused";
                return;
            }
            source.publish(judged);
            source.state = "loaded";
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                if (source.accepted !== source.defaults) source.publish(source.defaults);
                source.state = "absent";
                return;
            }
            console.error("theme: " + path + " unreadable: " + error);
            source.state = "unreadable";
        }
    }
}
