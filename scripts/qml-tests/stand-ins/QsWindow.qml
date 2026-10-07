pragma Singleton
import QtQuick

// Stands in for Quickshell's QsWindow attached object, whose plugin does
// not load outside the shell. Every item answers the one window a test
// names here, and none by default, as Quickshell answers for an item in a
// plain Qt window.
QtObject {
    property QtObject window: null
}
