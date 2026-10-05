pragma Singleton
import QtQml

// The enabled, judged sections and the manifests by id that the real
// Registry supplies. Tests replace them to exercise the shipped provider
// without a compositor.
QtObject {
    property var hyprlandSections: []
    property var manifests: ({})
}
