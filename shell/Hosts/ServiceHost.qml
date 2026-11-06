import QtQuick
import Quickshell
import qs.Core

// Keep each service's slot across unrelated enablement changes.
// ServiceGate delays builds for the first bar frames (D047); it also
// releases when no bar needs a frame or its presentation deadline ends.
Scope {
    id: host

    readonly property var ids: ServiceGate.release !== "" ? Registry.enabledOfKind("service") : []

    Variants {
        model: host.ids

        PluginSlot {
            required property string modelData
            listed: host.ids.indexOf(modelData) !== -1
            kind: "service"
            pluginId: modelData
            hostKey: "service"
        }
    }
}
