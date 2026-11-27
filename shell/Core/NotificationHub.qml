import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// The notification role exists while lent. Subscriptions belong to plugin
// instances and cannot outlive their instance lifetime.
Scope {
    id: root
    required property bool active
    property var subscribers: []
    readonly property var server: notificationLoader.item
    // Whether this process ever built the server. Quickshell 0.3.1 keeps
    // one static server per process that registers
    // org.freedesktop.Notifications on first use and is never destroyed
    // (src/services/notifications/server.cpp, NotificationServer::instance),
    // so from then on this shell holds the name, answering every Notify,
    // while nothing here is active to draw. Never reset.
    property bool holdsName: false
    onServerChanged: if (server !== null) holdsName = true

    function provider(ctx) {
        // Lifetime drains newest first (Lifetime.js), so the wrapper is
        // still here to read the process-wide model before the role ends.
        ctx.onDispose(() => {
            const tracked = root.server ? root.server.trackedNotifications : null;
            if (tracked !== null && tracked.values.length > 0) Qt.callLater(root.dismissReleased, tracked);
        });
        return {
            subscribe: fn => root.subscribe(ctx, fn),
            get tracked() { return root.server ? root.server.trackedNotifications : null; }
        };
    }

    function ownerOf(notification) {
        const tagged = /^vgs-notification:([^:]+):/.exec(notification.objectName);
        return tagged === null ? "" : tagged[1];
    }

    // A rescan re-lends within the turn. If an unrelated plugin still
    // holds the capability, close only notifications of a removed owner.
    // Qt skips this callLater on engine reload (Qt 6.12 QQmlDelayedCallQueue).
    function dismissReleased(tracked) {
        for (const n of Array.from(tracked.values)) {
            const owner = ownerOf(n);
            if (!active || (owner !== "" && !Registry.isEnabled(owner))) n.dismiss();
        }
    }

    // notifications: the one server, fanned out to every subscriber in
    // subscription order. A subscriber sets `tracked` on a notification it
    // keeps; one nobody tracks is discarded by the server.
    function subscribe(ctx, fn) {
        if (typeof fn !== "function")
            throw new Error("refused: notifications=subscribe handler=not-a-function");
        const entry = { id: ctx.id, fn: fn };
        subscribers = subscribers.concat([entry]);
        return ctx.onDispose(() => {
            root.subscribers = root.subscribers.filter(s => s !== entry);
        });
    }

    function fanOut(notification) {
        // Quickshell 0.3.1 resets tracking and re-emits the same object
        // synchronously during switchGeneration (src/services/notifications/server.cpp).
        // Keep an enabled owner's object while that owner's service reads
        // its store, even if another plugin is already subscribed.
        if (notification.lastGeneration) {
            const owner = ownerOf(notification);
            if (owner !== "") {
                if (!Registry.isEnabled(owner)) return;
                notification.tracked = true;
            }
        }
        for (const s of subscribers) {
            try {
                s.fn(notification);
            } catch (e) {
                console.error("capabilities: notification subscriber of " + s.id + " threw: " + e.message);
            }
        }
    }

    LazyLoader {
        id: notificationLoader
        active: root.active
        NotificationServer {
            keepOnReload: true
            bodySupported: true
            bodyMarkupSupported: true
            actionsSupported: true
            imageSupported: true
            persistenceSupported: true
            onNotification: n => root.fanOut(n)
        }
    }

}
