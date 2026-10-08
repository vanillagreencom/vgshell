import QtQuick

// Reads the `appearance` capability back for rows/appearance.sh: its member
// names, what it lends and its two writes, each answering the
// capability's reply.
Item {
    id: root
    property var shell: null
    readonly property string members: shell === null ? "" : Object.keys(shell.appearance).sort().join(",")
    readonly property var values: shell === null ? null : shell.appearance.values
    readonly property var sources: shell === null ? null : shell.appearance.sources
    readonly property var theme: shell === null ? null : shell.appearance.theme
    readonly property var keys: shell === null ? null : shell.appearance.keys

    // ARGS is `{ "key": KEY, "value": VALUE }` as JSON.
    function set(args) {
        const asked = JSON.parse(args);
        return shell.appearance.set(asked.key, asked.value);
    }

    function unset(key) {
        return shell.appearance.unset(key);
    }
}
