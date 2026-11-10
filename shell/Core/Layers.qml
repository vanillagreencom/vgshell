pragma Singleton
import QtQuick
import Quickshell

// The passive layers plugins draw in. A plugin's `layers` capability calls
// `show` with a Component of its own; the layer host builds that component
// once per screen inside a core-owned surface that never takes keyboard
// focus, and destroys every copy when the plugin releases it or its
// instance goes. The plugin keeps its state; the component reads it
// through the ids of the file that declares it.
Singleton {
    id: root

    // One registration per `show`, in registration order: { serial,
    // pluginId, component, screens }. `screens` is the host's record of what
    // it built, screen name -> that screen's copy of the content; it changes
    // without replacing the list.
    property var entries: []
    property int serial: 0
    // The entries' serials, the host's model: Variants copies a JS object it
    // is handed, so it is keyed by a value and looks the entry up.
    readonly property var serials: entries.map(e => e.serial)
    // Completed bar frames, written only by BarHost. An observation names
    // the real widget's owner/revision, output, request key and drawn dot.
    property var barFrames: ({})

    // TABLE, a host-keyed table of row lists, with HOST's rows replaced by
    // ROWS, or TABLE itself when they are unchanged, so no binding hears an
    // equal table.
    function withHostRows(table, host, rows) {
        if (JSON.stringify(table[host] || []) === JSON.stringify(rows)) return table;
        const next = Object.assign({}, table);
        if (rows.length === 0) delete next[host];
        else next[host] = rows;
        return next;
    }
    // Every host's rows of TABLE in one list. QML's array API has no flat.
    function allRows(table) {
        return Object.values(table).reduce((all, hostRows) => all.concat(hostRows), []);
    }

    function setBarFrame(host, rows) { barFrames = withHostRows(barFrames, host, rows); }

    // The boxes bar widgets draw below their bar, written only by BarHost:
    // host key -> [{ output, x, width, top, bottom }]. `x` and `width` are
    // in the output's logical pixels; `top` and `bottom` count down from
    // the bar's bottom edge, where the passive layers on that output start
    // under the bar's exclusive zone.
    property var barCoverRows: ({})

    function setBarCovers(host, rows) { barCoverRows = withHostRows(barCoverRows, host, rows); }

    // Every bar's covers, whichever plugin draws them, so a passive layer
    // stands clear of them without reading that plugin.
    function barCovers(ctx) {
        if (!ctx.active) return Object.freeze([]);
        return Object.freeze(allRows(barCoverRows).map(row => Object.freeze(Object.assign({}, row))));
    }

    function barIndicators(ctx) {
        if (!ctx.active) return Object.freeze([]);
        return Object.freeze(allRows(barFrames).filter(row =>
            row.plugin === ctx.id && row.revision === ctx.manifest.__revision).map(row =>
                Object.freeze({ output: row.output, key: row.key, dot: row.dot })));
    }

    // Emitted with an entry's serial before it leaves `entries`, so the host
    // destroys its content while the plugin that declared the component
    // still exists.
    signal released(int serial)

    // Show `component` on every screen for the instance `ctx` belongs to;
    // answers the disposer. A component that cannot be built now is refused.
    function show(ctx, component) {
        if (component === null || typeof component !== "object" || typeof component.createObject !== "function")
            throw new Error("refused: layers=not-a-component");
        if (component.status !== Component.Ready)
            throw new Error("refused: layers=component-not-ready status=" + component.status);
        serial += 1;
        const entry = { serial: serial, pluginId: ctx.id, component: component, screens: {} };
        entries = entries.concat([entry]);
        return ctx.onDispose(() => root.remove(entry));
    }

    function entryOf(serial) {
        return entries.find(e => e.serial === serial) || null;
    }

    function remove(entry) {
        if (entries.indexOf(entry) === -1) return;
        released(entry.serial);
        entries = entries.filter(e => e !== entry);
    }

    // Every registration by plugin, with the screens it is built on.
    function record() {
        return entries.map(e => ({ plugin: e.pluginId, screens: Object.keys(e.screens).sort() }));
    }
}
