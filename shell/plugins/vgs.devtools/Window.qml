import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Appearance.js" as Appearance
import "ViewLogic.js" as ViewLogic

// Dev Tools is an application window. The service publishes the catalog;
// this window only draws it and opens declared TUI entries for changes.
Item {
    id: root

    property var shell: null
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property var screen: shell === null ? null : shell.screens.current
    readonly property var catalog: shell === null || shell.status.values.catalog === undefined ? null : shell.status.values.catalog
    readonly property bool writeLaunchers: shell !== null && shell.settings.writeLaunchers === true
    readonly property bool showInLauncher: shell !== null && shell.settings.showInLauncher !== false
    readonly property var tuiState: shell === null ? ({}) : shell.tui.state
    readonly property string updateKey: shell === null ? "" : ViewLogic.updateEntry(shell.tui.entries)
    readonly property var drawn: ViewLogic.sections(catalog, updateKey, writeLaunchers)
    readonly property var filtered: ViewLogic.filteredSections(drawn, search.text, filter.model[filter.currentIndex])
    readonly property int updateAllCount: ViewLogic.updateAllCount(catalog)
    property string problem: ""
    property string targetRow: ""
    property Item initialFocus: targetRow === "" ? search : null
    // Emitted by every open(), so a summon for the row already targeted
    // focuses it again although targetRow does not change.
    signal summoned()

    function open(payloadJson) {
        if (look === null) throw new Error("devtools: refused: appearance");
        const payload = payloadJson ? JSON.parse(payloadJson) : {};
        const keys = Object.keys(payload);
        if (keys.length === 0) {
            targetRow = "";
        } else if (keys.length === 1 && typeof payload.row === "string") {
            targetRow = payload.row;
        } else {
            throw new Error("devtools: refused: payload");
        }
        tabs.currentIndex = 0;
        problem = "";
        if (targetRow === "") Qt.callLater(() => search.forceActiveFocus(Qt.ShortcutFocusReason));
        summoned();
    }
    function close() {}

    function runVerb(row, action, channel) {
        if (action.verb === "install" || action.verb === "update" || action.verb === "remove")
            return shell.tui.run(action.verb, ViewLogic.verbArgs(action.verb, row, channel));
        return shell.tui.run(action.verb, [action.verb, row.id]);
    }

    function act(row, action, channel) {
        let reply;
        switch (action.kind) {
        case "verb":
            reply = runVerb(row, action, channel);
            break;
        case "doctor":
            reply = shell.doctor.offer(row.requirement.owner, [row.requirement.name]);
            break;
        case "entry":
            reply = shell.tui.open(action.verb);
            break;
        default:
            throw new Error("devtools: action kind " + JSON.stringify(action.kind) + " is not one of verb, doctor, entry");
        }
        problem = ViewLogic.replyLine(reply);
        if (problem !== "") console.warn("devtools window: " + reply);
        return reply;
    }

    implicitWidth: screen === null ? look.window.width : Math.floor(Math.min(look.window.width, screen.width - 2 * look.window.gutter))
    implicitHeight: screen === null ? look.window.maxHeight : Math.floor(Math.min(look.window.maxHeight, screen.height - 2 * look.window.gutter))

    Pane {
        id: pane
        anchors.fill: parent
        container: "window"
        padding: root.look.window.padding
        cornerRadius: root.look.window.radius
        gap: root.look.window.gap
        bodySpacing: root.look.window.sectionGap
        Component.onCompleted: scrollArea.keyboardScroll = true

        header: Column {
            width: pane.contentWidth
            spacing: root.look.row.lineGap

            Label { role: "windowTitle"; text: "Dev Tools" }
            Label { width: parent.width; role: "hint"; text: ViewLogic.summary(root.catalog); elide: Text.ElideRight }
            Repeater {
                model: ViewLogic.runningLines(root.tuiState)
                Row {
                    required property string modelData
                    spacing: root.look.row.gap
                    Spinner { anchors.verticalCenter: parent.verticalCenter }
                    Label { anchors.verticalCenter: parent.verticalCenter; role: "hint"; text: parent.modelData }
                }
            }
            Label { width: parent.width; role: "hint"; visible: text !== ""; text: root.problem; wrapMode: Text.Wrap }
        }

        TabPages {
            id: tabs
            width: pane.contentWidth
            model: ["Catalog", "Settings", "Info"]

            Column {
                id: catalogPage
                width: tabs.width
                spacing: root.look.window.sectionGap

                Row {
                    width: parent.width
                    spacing: root.look.row.gap
                    TextField {
                        id: search
                        width: Math.max(1, parent.width - filter.width - root.look.row.gap)
                        leadingIcon: "search"
                        placeholderText: "Search tools"
                        escapeReverts: false
                    }
                    SegmentedControl {
                        id: filter
                        model: ["All", "Installed", "Updates", "Not installed"]
                    }
                }

                Row {
                    width: parent.width
                    spacing: root.look.row.gap
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        role: "hint"
                        text: root.updateAllCount === 1 ? "Update 1 tool" : "Update " + root.updateAllCount + " tools"
                    }
                    Button {
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: root.updateAllCount > 0
                        text: root.updateAllCount === 1 ? "Update 1 tool" : "Update " + root.updateAllCount + " tools"
                        onClicked: {
                            const reply = root.shell.tui.run("update-all", ["update-all"]);
                            root.problem = ViewLogic.replyLine(reply);
                        }
                    }
                }

                Repeater {
                    model: ScriptModel { values: root.filtered; objectProp: "key" }
                    Section {
                        id: section
                        required property var modelData
                        width: catalogPage.width
                        title: section.modelData.title
                        description: section.modelData.description
                        rowSpacing: root.look.row.spacing
                        Repeater {
                            model: section.modelData.lines
                            Label { required property string modelData; width: section.width; role: "hint"; text: modelData; wrapMode: Text.Wrap }
                        }
                        Repeater {
                            model: ScriptModel { values: section.modelData.rows; objectProp: "key" }
                            ToolRow {
                                id: toolRow
                                required property var modelData
                                width: section.width
                                row: modelData
                                look: root.look
                                function focusIfTarget() {
                                    if (root.targetRow !== modelData.key) return;
                                    Qt.callLater(() => {
                                        pane.scrollArea.reveal(toolRow);
                                        toolRow.forceActiveFocus(Qt.ShortcutFocusReason);
                                    });
                                }
                                Component.onCompleted: focusIfTarget()
                                Connections {
                                    target: root
                                    function onSummoned() { toolRow.focusIfTarget(); }
                                }
                                onActed: (action, channel) => root.act(modelData, action, channel)
                            }
                        }
                    }
                }
            }

            Column {
                width: tabs.width
                spacing: root.look.window.sectionGap
                Field {
                    width: parent.width
                    label: "Show full catalog in launcher"
                    hint: "Show each Dev Tools catalog row in launcher search."
                    inline: true
                    Switch {
                        size: "sm"
                        checked: root.showInLauncher
                        onToggled: {
                            const wanted = checked;
                            checked = Qt.binding(() => root.showInLauncher);
                            const reply = root.shell.configure.set("showInLauncher", wanted);
                            root.problem = ViewLogic.replyLine(reply, "setting");
                            if (root.problem !== "") console.warn("devtools window: configure " + JSON.stringify(reply));
                        }
                    }
                }
                Field {
                    width: parent.width
                    label: "Add tool commands to the terminal"
                    hint: "Write commands into ~/.local/bin and install a tool the first time you run one."
                    inline: true
                    Switch {
                        size: "sm"
                        checked: root.writeLaunchers
                        onToggled: {
                            const wanted = checked;
                            checked = Qt.binding(() => root.writeLaunchers);
                            const reply = root.shell.configure.set("writeLaunchers", wanted);
                            root.problem = ViewLogic.replyLine(reply, "setting");
                            if (root.problem !== "") console.warn("devtools window: configure " + JSON.stringify(reply));
                        }
                    }
                }
                Label { width: parent.width; role: "hint"; text: ViewLogic.writeReportLine(root.catalog); visible: text !== ""; wrapMode: Text.Wrap }
            }

            Column {
                width: tabs.width
                spacing: root.look.window.sectionGap
                Repeater {
                    model: root.drawn.length === 0 ? [] : [root.drawn[0]]
                    Section {
                        id: infoSection
                        required property var modelData
                        width: tabs.width
                        title: infoSection.modelData.title
                        description: infoSection.modelData.description
                        rowSpacing: root.look.row.spacing
                        Repeater {
                            model: ScriptModel { values: infoSection.modelData.rows; objectProp: "key" }
                            ToolRow {
                                required property var modelData
                                width: infoSection.width
                                row: modelData
                                look: root.look
                                onActed: (action, channel) => root.act(modelData, action, channel)
                            }
                        }
                    }
                }
                Label { width: parent.width; role: "hint"; text: ViewLogic.summary(root.catalog); wrapMode: Text.Wrap }
            }
        }
    }
}
