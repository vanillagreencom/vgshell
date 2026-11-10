pragma Singleton
import QtQuick
import "UnitEnv.js" as UnitEnv

// Stands in for the Quickshell singleton, whose plugin does not load
// outside the shell. env(NAME) answers the value scripts/qml-unit.sh sets
// in UnitEnv.js, the bundled font files Theme.qml loads, and "env:NAME" for
// every other variable, so a test reads which names a Process environment
// hands on and from where.
// It lists no screen; a test sets `screens` to the ones it needs.
QtObject {
    property string shellDir: "/stand-in/shell"
    property var screens: []

    function env(name) {
        return Object.prototype.hasOwnProperty.call(UnitEnv.VALUES, name) ? UnitEnv.VALUES[name] : "env:" + name;
    }
}
