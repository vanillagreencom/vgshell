import QtQuick
// Publishes the fixture's folder pairs as soon as it starts: one that needs
// the user and two that are up to date, each offering Remove.
//   invoke set <json>  publishes `pairs` as the list given; answers the reply
//   invoke clear       publishes `pairs` as an empty list; answers the reply
Item {
    id: root
    property var shell: null
    property bool registered: false
    readonly property var pairs: [
        { id: "documents", label: "Documents", secondary: "Drive/Documents ⇄ ~/Drive/Documents", state: { tone: "warning", text: "1 to review" }, actions: ["remove"] },
        { id: "uploads", label: "Agent uploads", secondary: "Drive/VGS/Uploads ⇄ ~/agents/uploads", state: { tone: "ok", text: "Up to date" }, actions: ["remove"] },
        { id: "taxes", label: "Taxes", secondary: "Drive/Finance/Taxes ⇄ ~/Documents/Taxes", state: { tone: "ok", text: "Up to date" }, actions: ["remove"] }
    ]

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.status.set("pairs", pairs);
        shell.ipc.handle("set", arg => root.shell.status.set("pairs", JSON.parse(arg)));
        shell.ipc.handle("clear", () => root.shell.status.set("pairs", []));
    }
}
