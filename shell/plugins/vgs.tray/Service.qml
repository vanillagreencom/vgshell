import QtQuick
import Quickshell.Services.SystemTray
import "TrayLogic.js" as TrayLogic

// The tray's one writer. It publishes `items`, the tray icons the Settings
// page offers for the pinned and hidden lists, and owns the two IPC calls
// that edit those lists, `pin` and `hide`, each with a tray item's id: the
// manage popup calls them, and a call toggles the item as
// TrayLogic.toggle decides. The lists go through capability `configure`,
// which writes every entry the plugin reads, so the bar, the Settings page
// and the next start agree. Referencing SystemTray makes Quickshell host
// the tray on the session bus (its StatusNotifierWatcher and host); the
// widget draws from the same singleton.
Item {
    id: root

    property var shell: null
    property bool registered: false

    readonly property var entries: SystemTray.items.values.map(item => ({ id: item.id, title: item.title, tooltipTitle: item.tooltipTitle, passive: item.status === Status.Passive }))
    readonly property var offers: TrayLogic.choices(entries)

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("pin", id => root.edit("pin", id));
        shell.ipc.handle("hide", id => root.edit("hide", id));
        publish();
    }
    onOffersChanged: publish()

    function publish() {
        if (shell === null) return;
        const reply = shell.status.set("items", offers);
        if (reply !== "ok") console.error("tray: status items " + reply);
    }

    // Toggle tray item ID in the list KIND names, `pin` or `hide`. The list
    // an item leaves is written before the list it joins, so no reader sees
    // it in both.
    function edit(kind, id) {
        if (typeof id !== "string" || id === "") return "refused: item=" + id + " reason=empty";
        const settings = shell.settings;
        const firstOffer = offers.length > 0 ? offers[0].value : "";
        const next = TrayLogic.toggle(kind, id, settings.pinned, settings.hidden, firstOffer);
        const order = kind === "pin" ? ["hidden", "pinned"] : ["pinned", "hidden"];
        for (const key of order) {
            if (JSON.stringify(next[key]) === JSON.stringify(settings[key])) continue;
            const reply = shell.configure.set(key, next[key]);
            if (reply !== "ok") return reply;
        }
        return "ok";
    }
}
