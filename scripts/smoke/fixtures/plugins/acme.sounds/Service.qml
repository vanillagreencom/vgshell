import QtQuick

// Reads the `sounds` and `soundSettings` capabilities back for
// rows/sounds.sh: their member names, what each lends, a play of one of
// the manifest's events, and the page's choice, test and refresh, each
// answering the capability's reply. For the manifest's held event, `relay`,
// it is the holder on request: it counts each read the core asks for,
// keeps each value the page's choice hands it, answers that choice with
// `relayReply`, and states the value the row gives it.
Item {
    id: root
    property var shell: null
    readonly property string soundsMembers: shell === null ? "" : Object.keys(shell.sounds).sort().join(",")
    readonly property string settingsMembers: shell === null ? "" : Object.keys(shell.soundSettings).sort().join(",")
    readonly property var choices: shell === null ? null : shell.sounds.choices
    readonly property var events: shell === null ? null : shell.soundSettings.events
    property int relayReads: 0
    property var relayAsked: []
    property string relayReply: "ok"

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

    function refresh() {
        shell.soundSettings.refresh();
        return "ok";
    }

    function hold(event) {
        return shell.sounds.hold(event, {
            read: () => { root.relayReads += 1; },
            choose: value => {
                root.relayAsked = root.relayAsked.concat([value]);
                return root.relayReply;
            }
        });
    }

    // ARGS is `{ "event": EVENT, "value": VALUE, "problem": PROBLEM }` as
    // JSON.
    function report(args) {
        const stated = JSON.parse(args);
        return shell.sounds.report(stated.event, stated.value, stated.problem);
    }

    function answer(reply) {
        relayReply = reply;
        return "ok";
    }
}
