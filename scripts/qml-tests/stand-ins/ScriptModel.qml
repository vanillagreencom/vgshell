import QtQuick

// Stands in for Quickshell's ScriptModel, whose plugin does not load
// outside the shell: one row per entry of `values`, under the role
// `modelData` a delegate requires. As Quickshell 0.3.1's does
// (src/core/scriptmodel.cpp, `updateValuesUnique`), a change compares a
// value by its `objectProp` property where it has one, else whole, both
// structurally, and reaches the new list by removals, moves and inserts,
// so a Repeater keeps the delegate of every value that stays. A value that
// stays in its place takes the new value; one that moves keeps the value
// it had, as Quickshell's does, so its delegate's `modelData` is the old
// one.
ListModel {
    property var values: []
    property string objectProp: ""
    // The values the rows hold, in their order.
    property var held: []

    dynamicRoles: true

    function same(a, b) {
        if (a === b) return true;
        if (a === null || b === null || typeof a !== "object" || typeof b !== "object" || Array.isArray(a) !== Array.isArray(b)) return false;
        const names = Object.keys(a);
        return names.length === Object.keys(b).length && names.every(name => Object.prototype.hasOwnProperty.call(b, name) && same(a[name], b[name]));
    }
    function compared(value) {
        return objectProp !== "" && value !== null && typeof value === "object" && objectProp in value ? value[objectProp] : value;
    }
    function matches(a, b) { return a === b || same(compared(a), compared(b)); }

    onValuesChanged: {
        const next = Array.from(values);
        const rows = held.slice();
        for (let index = rows.length - 1; index >= 0; index--) {
            if (next.some(value => matches(value, rows[index]))) continue;
            remove(index);
            rows.splice(index, 1);
        }
        for (let index = 0; index < next.length; index++) {
            const at = rows.findIndex((value, place) => place >= index && matches(next[index], value));
            if (at === -1) {
                insert(index, { modelData: next[index] });
                rows.splice(index, 0, next[index]);
            } else if (at !== index) {
                move(at, index, 1);
                rows.splice(index, 0, rows.splice(at, 1)[0]);
            } else if (rows[index] !== next[index]) {
                set(index, { modelData: next[index] });
                rows[index] = next[index];
            }
        }
        held = rows;
    }
}
