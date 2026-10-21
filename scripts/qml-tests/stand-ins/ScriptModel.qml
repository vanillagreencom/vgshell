import QtQuick

// Stands in for Quickshell's ScriptModel, whose plugin does not load
// outside the shell: one row per entry of `values`, under the role
// `modelData` a delegate requires. The plain-data update below follows
// src/core/scriptmodel.cpp, updateValuesUnique, at the packaged Quickshell
// pin 2b4501a282689792b62e94f3fb30d8f512324fe6 (0.3.2.r7): reconcile keys
// first, then refresh values. Keeping these passes separate preserves a
// keyed delegate even when every published row is a fresh object, and
// gives moved delegates their current modelData.
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
        let index = 0;
        let newIndex = 0;
        while (true) {
            if (newIndex === next.length) {
                if (index < rows.length) {
                    remove(index, rows.length - index);
                    rows.splice(index);
                }
                break;
            } else if (index === rows.length) {
                for (; newIndex < next.length; newIndex++) {
                    append({ modelData: next[newIndex] });
                    rows.push(next[newIndex]);
                }
                break;
            } else if (!matches(next[newIndex], rows[index])) {
                const at = rows.findIndex((value, place) => place >= index && matches(value, next[newIndex]));
                if (at !== -1) {
                    if (!next.some((value, place) => place >= newIndex && matches(value, rows[index]))) {
                        let end = index + 1;
                        while (end < rows.length && !next.some((value, place) => place >= newIndex && matches(value, rows[end]))) end++;
                        remove(index, end - index);
                        rows.splice(index, end - index);
                    } else {
                        let end = at + 1;
                        newIndex++;
                        while (end < rows.length && newIndex < next.length && matches(rows[end], next[newIndex])) {
                            end++;
                            newIndex++;
                        }
                        const length = end - at;
                        move(at, index, length);
                        rows.splice(index, 0, ...rows.splice(at, length));
                        index += length;
                    }
                } else {
                    const start = newIndex++;
                    while (newIndex < next.length && !rows.some((value, place) => place >= index && matches(value, next[newIndex]))) newIndex++;
                    const inserted = next.slice(start, newIndex);
                    for (let offset = 0; offset < inserted.length; offset++) insert(index + offset, { modelData: inserted[offset] });
                    rows.splice(index, 0, ...inserted);
                    index += inserted.length;
                }
            } else {
                index++;
                newIndex++;
            }
        }
        for (let index = 0; index < rows.length; index++) {
            if (rows[index] !== next[index]) {
                set(index, { modelData: next[index] });
                rows[index] = next[index];
            }
        }
        held = rows;
    }
}
