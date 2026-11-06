import QtQuick
// A sender without the `notifications` capability, so with it alone
// enabled no plugin keeps the core's notification server up:
// notify <json options> answers the reply of shell.notify.send.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property string action: "pending"
    property string delivery: "pending"
    property int completed: 0
    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("notify", arg => root.shell.notify.send(JSON.parse(arg)));
        shell.ipc.handle("notify-actions", arg => {
            root.action = "pending";
            root.delivery = "pending";
            return root.shell.notify.send(JSON.parse(arg), (action, delivery) => {
                root.action = action;
                root.delivery = delivery;
                root.completed += 1;
            });
        });
    }
}
