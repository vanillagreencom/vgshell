import QtQuick
import "PluginLogic.js" as Logic

// Text-only draft receivers. A descriptor's `kind` is "action" for a
// receiver whose manifest entry declares it, one that opens a task of its
// plugin, and "" for a message target. A null receiver withdraws the live offer and
// publishes its cause. Both registrations and unavailable reports belong
// to the offering instance; a descriptor never dispatches to a replacement.
Item {
    id: root
    property var manifests: ({})
    property var enabledIds: []
    property var records: ({})

    function provider(ctx) {
        return Object.freeze({
            offer: (name, accept, reason) => root.offer(ctx, name, accept, reason),
            get targets() { return ctx.active ? root.targets() : []; }
        });
    }

    function offer(ctx, name, accept, reason) {
        if (!ctx.active) throw new Error("refused: handoff=released");
        if (!Logic.hasOwn(ctx.manifest.handoffs, name)) throw new Error("refused: handoff=undeclared");
        if (accept !== null && typeof accept !== "function") throw new Error("refused: handoff=receiver");
        if (accept === null && !Logic.isPrintableLine(reason, Logic.STATUS_HINT_MAX))
            throw new Error("refused: handoff=reason");
        const key = "handoff:" + ctx.id + "/" + name;
        if (Logic.hasOwn(records, key)) throw new Error("refused: handoff=held");
        const record = { ctx: ctx, accept: accept, reason: accept === null ? reason : "" };
        records = Object.assign({}, records, { [key]: record });
        return ctx.onDispose(() => {
            if (root.records[key] !== record) return;
            const rest = Object.assign({}, root.records);
            delete rest[key];
            root.records = rest;
        });
    }

    function targets() {
        const out = [];
        for (const id of Object.keys(manifests).sort()) {
            const manifest = manifests[id];
            for (const name of Object.keys(manifest.handoffs || {})) {
                const key = "handoff:" + id + "/" + name;
                const record = records[key];
                const enabled = enabledIds.indexOf(id) !== -1;
                const current = enabled && record !== undefined && record.ctx.active
                    && record.ctx.manifest.__revision === manifest.__revision;
                const label = manifest.handoffs[name].label;
                const reason = !enabled ? label + " is turned off."
                    : !current ? label + " has not started."
                    : record.reason;
                const available = current && record.accept !== null;
                out.push(Object.freeze({
                    key: key, label: label, kind: manifest.handoffs[name].kind === "action" ? "action" : "", available: available, reason: reason,
                    open: text => root.open(key, record, text)
                }));
            }
        }
        return Object.freeze(out);
    }

    function open(key, record, text) {
        if (record === undefined || records[key] !== record || !record.ctx.active
                || enabledIds.indexOf(record.ctx.id) === -1
                || manifests[record.ctx.id]?.__revision !== record.ctx.manifest.__revision)
            // Any sender reads this, a fixed target's (D127) too, so it
            // names no step of one sender.
            return { ok: false, reason: "The receiver changed. Try again." };
        if (record.accept === null) return { ok: false, reason: record.reason };
        if (typeof text !== "string" || text.trim() === "") return { ok: false, reason: "The message is empty." };
        try {
            return record.accept(text);
        } catch (error) {
            console.error("handoff: receiver-failed key=" + key);
            return { ok: false, reason: "The message could not open because its receiver failed. Try again." };
        }
    }
}
