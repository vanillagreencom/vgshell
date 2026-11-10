pragma Singleton
import QtQuick
import Quickshell
import "PluginLogic.js" as Logic

// Plugin status: the runtime values each plugin publishes through its
// `status` capability, held once per plugin id so every instance of the
// plugin reads the same record, D037. A record lives while the plugin is
// enabled at the source revision that wrote it: disabling the plugin, or a
// rescan that gives it a new revision, drops the record, so a rebuilt
// service publishes again from nothing. PluginLogic.statusWrite judges every
// value; the manifest's `status` key declares what may be written.
Singleton {
    id: root

    // Plugin id -> the holder of its record, an object whose `record` is
    // { revision, serial, values, bytes }: the source revision that wrote
    // it, the serial of its last write, the published values and their
    // size. `values` never leaves this file: valuesOf hands out copies.
    // A write replaces one holder's `record`, so it re-runs only the
    // bindings that read that plugin's status; this map is replaced only
    // when a record is added or dropped. A binding records the holder's
    // property it reads through this map, as tst_plugin_status.qml runs it.
    // A map replaced on every write would re-run every status reader of
    // every plugin on each write: on px13 (VGS-2239 profile 2, qmlprofiler)
    // 37 of 40 animation gaps of 25 ms or more held such a write.
    // PluginStatus creates each holder and destroys it when its record drops.
    property var holders: ({})
    // Rises by one on every accepted value change, across plugins, so no
    // two changes share a serial and a dropped record's serial never returns.
    property int serial: 0

    readonly property var empty: Object.freeze({})

    // The plugin whose Settings page is shown and the tab that page shows,
    // as { id, tab }, "" for both while none is shown: the Settings window
    // reports both (the manager's viewPage, view), and each plugin reads
    // them as `shell.status.viewed` and `shell.status.viewedTab`
    // (viewedTabOf), so it reads what only its page, or one tab of it,
    // shows while it is open instead of on a poll. One value holds both, so
    // a bound reader never reads one page beside the tab another showed.
    property var viewing: ({ id: "", tab: "" })
    readonly property string viewed: viewing.id
    function view(id, tab) {
        viewing = { id: id, tab: tab };
    }
    // The tab plugin ID's page shows, "" while another page or none is
    // shown: no plugin reads another's tab.
    function viewedTabOf(id) {
        return viewing.id === id ? viewing.tab : "";
    }

    // Plugin id -> { choices status key -> handler }: what each plugin runs
    // when the Settings page opens the select that key feeds, so it reads
    // its choices on demand instead of on a poll. A handler lives with the
    // instance that registered it.
    property var refreshers: ({})

    // Register `handler` for the instance `ctx` belongs to as the one that
    // refreshes its `choices` entry `key`, released with the instance:
    // `ok`, `refused: status=<key> reason=undeclared` for a key the manifest
    // does not declare as `choices`, or `reason=held` while another
    // instance's handler holds it.
    function handleRefresh(ctx, key, handler) {
        if (typeof handler !== "function")
            throw new Error("refused: status=" + key + " handler=not-a-function");
        if (typeof key !== "string" || !Logic.hasOwn(ctx.manifest.status, key) || ctx.manifest.status[key].type !== "choices")
            return Logic.statusRefusal(key, "undeclared");
        return holdHandler("refreshers", ctx, key, handler);
    }

    // Put `handler` in the table the property NAME holds, `refreshers`,
    // `previewers` or `choosers`, under the instance `ctx` belongs to and `key`, until
    // the instance is disposed: `ok`, or `refused: status=<key>
    // reason=held` while another instance's handler holds that key.
    function holdHandler(name, ctx, key, handler) {
        if (Logic.hasOwn(root[name], ctx.id) && Logic.hasOwn(root[name][ctx.id], key))
            return Logic.statusRefusal(key, "held");
        const next = Object.assign({}, root[name]);
        next[ctx.id] = Object.assign({}, next[ctx.id] || {});
        next[ctx.id][key] = handler;
        root[name] = next;
        ctx.onDispose(() => {
            const rest = Object.assign({}, root[name]);
            const own = Object.assign({}, rest[ctx.id]);
            delete own[key];
            if (Object.keys(own).length === 0) delete rest[ctx.id];
            else rest[ctx.id] = own;
            root[name] = rest;
        });
        return "ok";
    }

    // Plugin id -> { schema key -> handler }: what each plugin runs when the
    // Settings page asks it to play an offer of a field that declares
    // `preview`, such as a voice. A handler lives with the instance that
    // registered it.
    property var previewers: ({})

    // Register `handler` for the instance `ctx` belongs to as the one that
    // plays an offer of its schema field `key`, released with the
    // instance: `ok`, `refused: status=<key> reason=undeclared` for a key
    // whose field declares no `preview`, or `reason=held` while another
    // instance's handler holds it. The handler takes the offer's value and
    // answers a keyed reply.
    function handlePreview(ctx, key, handler) {
        if (typeof handler !== "function")
            throw new Error("refused: status=" + key + " handler=not-a-function");
        if (typeof key !== "string" || !Logic.hasOwn(ctx.manifest.schema, key) || ctx.manifest.schema[key].preview !== true)
            return Logic.statusRefusal(key, "undeclared");
        return holdHandler("previewers", ctx, key, handler);
    }

    // Ask plugin `id`'s preview handler of field `key` to play VALUE: its
    // reply, or `refused: preview=<key> reason=none` when no instance
    // registered one, as while the plugin is off.
    function preview(id, key, value) {
        if (!Logic.hasOwn(previewers, id) || !Logic.hasOwn(previewers[id], key)) return "refused: preview=" + key + " reason=none";
        return String(previewers[id][key](value));
    }

    // Plugin id -> { schema key -> handler }: what each plugin runs after
    // the user chooses a value of one of its fields on its Settings page
    // (Capabilities.managerChoose), so a choice made on purpose can start
    // work, such as a download, that a config-file change, a reload or a
    // migration write must not. A handler lives with the instance that
    // registered it.
    property var choosers: ({})

    // Register `handler` for the instance `ctx` belongs to as the one told
    // of a user's choice of its schema field `key`, released with the
    // instance: `ok`, `refused: status=<key> reason=undeclared` for a key
    // the schema lacks, or `reason=held` while another instance's handler
    // holds it. The handler takes the chosen value and the value it
    // replaced; what it returns is not read.
    function handleChoice(ctx, key, handler) {
        if (typeof handler !== "function")
            throw new Error("refused: status=" + key + " handler=not-a-function");
        if (typeof key !== "string" || !Logic.hasOwn(ctx.manifest.schema, key))
            return Logic.statusRefusal(key, "undeclared");
        return holdHandler("choosers", ctx, key, handler);
    }

    // Tell plugin `id`'s choice handler of field `key` that the user chose
    // VALUE in place of PREVIOUS: `ok`, or `none` when no instance
    // registered one, as while the plugin is off.
    function chosen(id, key, value, previous) {
        if (!Logic.hasOwn(choosers, id) || !Logic.hasOwn(choosers[id], key)) return "none";
        choosers[id][key](value, previous);
        return "ok";
    }

    // Run plugin `id`'s handler for its choices entry `key`: `ok`, or
    // `none` when no instance registered one, as for most choices.
    function refresh(id, key) {
        if (!Logic.hasOwn(refreshers, id) || !Logic.hasOwn(refreshers[id], key)) return "none";
        refreshers[id][key]();
        return "ok";
    }

    // Publish `value` under `key` for the instance `ctx` belongs to. The
    // reply is one keyed line: `ok`, statusWrite's refusal, or
    // `refused: status=<key> reason=retired` from an instance whose plugin is
    // no longer enabled at its revision, which the core is about to
    // destroy, so its write cannot bring back a dropped record.
    function set(ctx, key, value) {
        const revision = ctx.manifest.__revision;
        if (!Registry.isEnabled(ctx.id) || Registry.manifests[ctx.id].__revision !== revision)
            return Logic.statusRefusal(key, "retired");
        // A record another revision wrote is the replaced revision's: a
        // rebuilt instance can write before the registry's change signal
        // prunes it, since the new slot keys rebuild inside the manifest
        // map's assignment.
        const held = recordOf(ctx.id);
        const current = held !== null && held.revision === revision ? held : null;
        const result = Logic.statusWrite(ctx.manifest, current === null ? {} : current.values, key, value);
        if (!result.ok) return result.error;
        // TUI record reads and requirement scans can repeat a service's
        // accepted values. Keep their serial and bindings unchanged.
        const hadKey = current !== null && Logic.hasOwn(current.values, key);
        const hasKey = Logic.hasOwn(result.values, key);
        if (current !== null && hadKey === hasKey && (!hasKey || JSON.stringify(current.values[key]) === JSON.stringify(result.values[key]))) return "ok";
        store(ctx.id, revision, result);
        return "ok";
    }

    // Plugin `id`'s record, or null while it has none. A binding that calls
    // this re-evaluates when that plugin's record is written, added or
    // dropped, and when another plugin's record is added or dropped.
    function recordOf(id) {
        return Logic.hasOwn(holders, id) ? holders[id].record : null;
    }

    // Hold WRITTEN, statusWrite's accepted { values, bytes }, as plugin
    // `id`'s record from source REVISION, under the next serial.
    function store(id, revision, written) {
        const next = serial + 1;
        const record = Object.freeze({ revision: revision, serial: next, values: written.values, bytes: written.bytes });
        if (Logic.hasOwn(holders, id)) {
            holders[id].record = record;
        } else {
            // createObject's initial properties reach a `var` property as a
            // map with its keys sorted (tst_plugin_status.qml runs it); an
            // assignment keeps the record as written.
            const holder = holderComponent.createObject(root);
            holder.record = record;
            const added = Object.assign({}, holders);
            added[id] = holder;
            holders = added;
        }
        serial = next;
    }

    // Drop the records of the plugin ids IDS that have one.
    function drop(ids) {
        const kept = Object.assign({}, holders);
        const gone = [];
        for (const id of ids) {
            if (!Logic.hasOwn(kept, id)) continue;
            gone.push(kept[id]);
            delete kept[id];
        }
        if (gone.length === 0) return;
        holders = kept;
        // destroy() is deferred to the event loop, so every binding the
        // map change re-ran has already read the new map.
        for (const holder of gone) holder.destroy();
    }

    // The values plugin `id` published, or an empty frozen object: a
    // deep-frozen copy made for this read, since the engine lets a frozen
    // array be written in place, so a reader that changes
    // an array changes only its own copy. A binding that calls this
    // re-evaluates as recordOf's does.
    function valuesOf(id) {
        const record = recordOf(id);
        return record === null ? empty : Logic.frozenJson(record.values);
    }

    // The serial of plugin `id`'s last write, 0 while it has none.
    function revisionOf(id) {
        const record = recordOf(id);
        return record === null ? 0 : record.serial;
    }

    // Drop every record whose plugin is gone, disabled, or at another source
    // revision than the one that wrote it.
    function prune() {
        drop(Object.keys(holders).filter(id => !Registry.isEnabled(id) || Registry.manifests[id].__revision !== holders[id].record.revision));
    }

    Connections {
        target: Registry
        function onChanged() { root.prune(); }
    }
    Connections {
        target: Config
        function onEffectiveChanged() { root.prune(); }
    }

    // Every record by plugin id, for the lending record: its keys, sorted,
    // the serial of its last write and its size in bytes.
    function record() {
        const out = {};
        for (const id of Object.keys(holders).sort()) {
            const held = holders[id].record;
            out[id] = { keys: Object.keys(held.values).sort(), revision: held.serial, bytes: held.bytes };
        }
        return out;
    }

    Component {
        id: holderComponent
        QtObject {
            property var record
        }
    }
}
