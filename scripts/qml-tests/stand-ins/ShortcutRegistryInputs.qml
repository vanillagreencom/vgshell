pragma Singleton
import QtQml
import "HyprlandLayer.js" as Layer

// The enabled, judged sections, the manifests by id and the scan state that
// the real Registry supplies, and the problems the Hyprland layer hands it.
// Tests replace them to exercise the shipped provider and the layer without
// a compositor. A plugin is enabled while `manifests` holds it, and
// `changed` is the real Registry's signal that its plugin set changed,
// which PluginStatus prunes its records on.
QtObject {
    signal scanFinished()
    signal changed()
    property var hyprlandSections: []
    property var hyprlandBindPlan: Layer.resolveBinds(hyprlandSections)
    property var hyprlandKeyIdentities: null
    property var manifests: ({})
    property bool scanned: true
    property string monitorRuleOwnerId: ""
    property var hyprlandProblems: []
    function isEnabled(id) { return Object.prototype.hasOwnProperty.call(manifests, id); }
}
