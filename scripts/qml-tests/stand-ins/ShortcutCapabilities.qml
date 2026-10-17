pragma Singleton
import QtQml

// ShortcutRegistry's core registrations use this dependency at startup.
// The key-read tests exercise no name validation or native registration.
// `hyprland` and `monitors` hold the members the Hyprland layer reads and
// writes on the real providers.
QtObject {
    readonly property QtObject hyprland: QtObject {
        property var touchpads: null
        property string devicesFailure: ""
        property var written: []
        property var appearanceWritten: []
        property var optionConflicts: []
        property var layerBinds: []
    }
    readonly property QtObject monitors: QtObject {
        property string ownerId: ""
        property var trialState: ({ phase: "idle", token: "", deadline: 0, failure: "" })
    }

    function checkName(kind, name) {}
}
