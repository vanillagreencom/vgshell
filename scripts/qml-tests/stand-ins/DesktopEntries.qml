pragma Singleton
import QtQuick

// Stands in for Quickshell's DesktopEntries, whose plugin does not load
// outside the shell: an empty application list a test may replace, which
// emits `valuesChanged` as the real list does on a rescan.
QtObject {
    readonly property QtObject applications: QtObject {
        property var values: []
    }
}
