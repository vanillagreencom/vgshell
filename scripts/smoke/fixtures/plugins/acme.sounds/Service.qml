import QtQuick

// Reads the `sounds` and `soundSettings` capabilities back for
// rows/sounds.sh: their member names, what each lends, a play of one of
// the manifest's events, and the page's choice and test, each answering
// the capability's reply.
Item {
    id: root
    property var shell: null
    readonly property string soundsMembers: shell === null ? "" : Object.keys(shell.sounds).sort().join(",")
    readonly property string settingsMembers: shell === null ? "" : Object.keys(shell.soundSettings).sort().join(",")
    readonly property var choices: shell === null ? null : shell.sounds.choices
    readonly property var events: shell === null ? null : shell.soundSettings.events
    readonly property var library: shell === null ? null : shell.soundSettings.library

    function play(event) {
        return shell.sounds.play(event);
    }

    // ARGS is `{ "id": ID, "event": EVENT, "value": VALUE }` as JSON.
    function choose(args) {
        const asked = JSON.parse(args);
        return shell.soundSettings.choose(asked.id, asked.event, asked.value);
    }

    function test(sound) {
        return shell.soundSettings.test(sound);
    }
}
