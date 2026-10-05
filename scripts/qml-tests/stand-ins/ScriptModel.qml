import QtQuick

// Stands in for Quickshell's ScriptModel, whose plugin does not load
// outside the shell: one row per entry of `values`, under the role
// `modelData` a delegate requires, rebuilt whole on every change.
// `objectProp` is taken and not read, so a row is never kept across a
// change.
ListModel {
    property var values: []
    property string objectProp: ""

    dynamicRoles: true
    onValuesChanged: {
        clear();
        for (const value of values) append({ modelData: value });
    }
}
