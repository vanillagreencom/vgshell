pragma Singleton
import QtQml

// ShortcutRegistry's core registrations use this dependency at startup.
// The key-read tests exercise no name validation or native registration.
// `hyprland` and `monitors` hold the members the Hyprland layer reads and
// writes on the real providers.
QtObject {
    readonly property QtObject hyprland: QtObject {
        property int keymapRevision: 0
        property var foreignKeys: []
        property var userBindRows: []
        property bool bindsPending: false
        property bool userBindsPending: false
        property bool resolvingKeys: false
        property var pendingKeys: null
        property var devices: null
        function resolveKeys(keys, done) {
            pendingKeys = { keys: keys, done: done };
            resolvingKeys = true;
        }
        function finishKeys(answer) {
            const pending = pendingKeys;
            pendingKeys = null;
            resolvingKeys = false;
            pending.done(answer);
        }
        property var touchpads: null
        property string devicesFailure: ""
        property var written: []
        property var appearanceWritten: []
        property var optionConflicts: []
        property var layerBinds: []
        property var permissionState: null
        property var userPermissions: null
    }
    readonly property QtObject monitors: QtObject {
        property string ownerId: ""
        property var trialState: ({ phase: "idle", token: "", deadline: 0, failure: "" })
    }

    function checkName(kind, name) {}
    property int publisherHolds: 0
    function acquire(name, id) { publisherHolds++; }
    function release(name, id) { publisherHolds--; }
}
