pragma Singleton
import QtQml

// The enabled, judged sections, the manifests by id and the scan state that
// the real Registry supplies, and the problems the Hyprland layer hands it.
// Tests replace them to exercise the shipped provider and the layer without
// a compositor.
QtObject {
    signal scanFinished()
    property var hyprlandSections: []
    property var manifests: ({})
    property bool scanned: true
    property string monitorRuleOwnerId: ""
    property var hyprlandProblems: []
}
