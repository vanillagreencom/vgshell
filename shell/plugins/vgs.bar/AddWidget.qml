import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The existing window host owns the toplevel and Escape. Keep the manager
// join in this one binding, only for the lifetime of the summoned chooser.
FocusScope {
    id: root

    property var shell: null
    property var payload: ({})
    readonly property var plugins: shell === null ? [] : shell.manager.plugins
    readonly property var widgets: plugins.filter(plugin => plugin.kinds.indexOf("bar-widget") !== -1)
    property int current: 0
    property string notice: ""
    readonly property Item initialFocus: rows.itemAt(current) !== null ? rows.itemAt(current).nameLink : root

    implicitWidth: Theme.size.window.width
    implicitHeight: Math.min(layout.uncappedHeight, Theme.size.panel.maxHeight)
    focus: true

    function open(payloadJson) {
        payload = JSON.parse(payloadJson);
        notice = "";
        plate.disarm();
    }
    function close() {}

    function addWidget(id) {
        const reply = shell.manager.insertWidget(id, payload.screen, payload.x);
        notice = Reply.line(reply);
        if (!Reply.isOk(reply)) console.warn("vgs.bar: insert widget " + reply);
        return reply;
    }

    function openSettings(id) {
        const reply = shell.surfaces.openPage(id, "Settings");
        notice = Reply.line(reply);
        return reply;
    }

    function focusRow(index) {
        current = index;
        const row = rows.itemAt(index);
        if (row !== null) row.nameLink.forceActiveFocus(Qt.TabFocusReason);
    }
    onWidgetsChanged: {
        plate.rebuilt();
        current = Math.max(0, Math.min(current, widgets.length - 1));
    }
    Keys.onPressed: event => { event.accepted = nav.handle(event); }

    ListCursor {
        id: plate
        parent: layout.scrollArea.contentItem
    }
    KeyNav {
        id: nav
        count: root.widgets.length
        currentIndex: root.current
        crossAxis: true
        cursor: plate
        flickable: layout.scrollArea
        viewHeight: layout.scrollArea.height
        rowHeight: Theme.listItem.twoLineHeight
        itemAt: index => rows.itemAt(index)
        labelAt: index => root.widgets[index].name
        onMoved: index => root.focusRow(index)
        onActivated: index => root.openSettings(root.widgets[index].id)
        onCrossed: delta => {
            const row = rows.itemAt(root.current);
            if (row !== null)
                (delta > 0 && row.addButton.visible ? row.addButton : row.nameLink).forceActiveFocus(Qt.TabFocusReason);
        }
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        title: "Add widget"
        bodySpacing: 0
        subtitle: [
            Label {
                width: layout.contentWidth
                role: "hint"
                text: "Choose a widget. Select its name to open Settings."
                visible: root.widgets.length > 0
                wrapMode: Text.Wrap
            },
            Label {
                width: layout.contentWidth
                visible: root.notice !== ""
                role: "hint"
                text: root.notice
                color: Theme.color.warning
                wrapMode: Text.Wrap
            }
        ]
        EmptyState {
            width: layout.contentWidth
            visible: root.widgets.length === 0
            iconName: "puzzle"
            text: "No widgets available"
        }
        Repeater {
            id: rows
            model: ScriptModel {
                values: root.widgets
                objectProp: "id"
            }
            ListItem {
                id: entry
                required property var modelData
                required property int index
                readonly property bool pluginOff: !modelData.enabled
                readonly property alias nameLink: name
                readonly property alias addButton: add
                width: layout.contentWidth
                text: modelData.name
                secondary: pluginOff ? `Enable in [Settings](page:${modelData.id}/Settings) to add this widget` : modelData.description
                clickable: pluginOff
                cursor: plate
                highlighted: index === root.current && entry.activeFocus
                onClicked: root.openSettings(modelData.id)

                contentItem: Item {
                    implicitHeight: Math.max(lines.implicitHeight, actions.height, leading.height)
                    Icon {
                        id: leading
                        name: entry.modelData.icon
                        size: Theme.icon.size.md
                        color: Theme.color.textMuted
                        anchors.verticalCenter: lines.verticalCenter
                    }
                    Column {
                        id: lines
                        x: leading.width + Theme.listItem.iconGap
                        width: Math.max(0, parent.width - x - actions.width - Theme.listItem.gap)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.row.lineGap
                        LinkText {
                            id: name
                            width: Math.min(implicitWidth, parent.width)
                            role: "item"
                            text: entry.modelData.name
                            link: text
                            linkColor: entry.pluginOff ? Theme.color.textMuted : Theme.color.accent
                            activeFocusOnTab: entry.index === root.current
                            Keys.onPressed: event => { event.accepted = nav.handle(event); }
                            onActiveFocusChanged: if (activeFocus) {
                                root.current = entry.index;
                                nav.reveal(entry.index);
                            }
                            onActivated: root.openSettings(entry.modelData.id)
                        }
                        LinkText {
                            width: parent.width
                            role: "itemHint"
                            text: entry.secondary
                            color: entry.pluginOff ? Theme.color.textMuted : Theme.text.itemHint.color
                            wrapMode: Text.Wrap
                            // keyboard-path: the selected row's Return opens the same Settings page
                            activeFocusOnTab: false
                            onActiveFocusChanged: if (activeFocus) root.current = entry.index
                            onPageActivated: (page, tab) => {
                                root.notice = Reply.line(root.shell.surfaces.openPage(page, tab));
                            }
                        }
                    }
                    Row {
                        id: actions
                        x: parent.width - width
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.listItem.gap
                        Button {
                            id: add
                            visible: !entry.pluginOff && !entry.modelData.placed
                            text: "Add"
                            iconName: "plus"
                            variant: "secondary"
                            // keyboard-path: Right from the selected name; Left returns to it
                            activeFocusOnTab: false
                            onActiveFocusChanged: if (activeFocus) root.current = entry.index
                            onClicked: {
                                root.addWidget(entry.modelData.id);
                                name.forceActiveFocus(Qt.TabFocusReason);
                            }
                        }
                        Badge {
                            visible: !entry.pluginOff && entry.modelData.placed
                            text: "On bar"
                            iconName: "check"
                            tone: "neutral"
                        }
                        Badge {
                            visible: entry.pluginOff
                            text: "Plugin disabled"
                            tone: "neutral"
                        }
                    }
                }
            }
        }
    }
}
