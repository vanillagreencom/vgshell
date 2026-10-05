import QtQuick
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayLogic.js" as TrayLogic

// The tray in the bar: an arrow, the drawer of tray icons behind it and the
// pinned icons after it, in the buckets TrayLogic.buckets gives. The drawer
// opens while the pointer rests on the arrow or the drawer, and a click or
// Enter on the arrow holds it open until the next one; it slides open and
// shut over motion.duration.slow. The frame menu, a right click on the
// arrow or on an icon whose app has no menu, adds Manage tray icons, a
// popover that lists every icon with its Pin and Hide toggles. The toggles
// ask the service, the plugin's one writer, through its IPC calls; the
// widget only reads its settings. It shows nothing while no icon would.
BarWidget {
    id: widget

    readonly property var trayItems: SystemTray.items.values
    readonly property var entries: trayItems.map(item => ({ id: item.id, passive: item.status === Status.Passive }))
    readonly property var offers: shell === null ? [] : (shell.status.values.items || [])
    readonly property string firstOffer: offers.length > 0 ? offers[0].value : ""
    readonly property var pinnedIds: TrayLogic.ids(setting("pinned", []), firstOffer)
    readonly property var hiddenIds: TrayLogic.ids(setting("hidden", []), firstOffer)
    // Each bucket as a list of { id, index }, `index` into trayItems.
    readonly property var buckets: TrayLogic.buckets(entries, pinnedIds, hiddenIds)
    readonly property bool shown: buckets.pinned.length + buckets.drawer.length > 0

    // The drawer is held open by a click on the arrow, and stays open while
    // an icon's menu in it is open, so the menu keeps its anchor in view.
    property bool held: false
    readonly property bool expanded: drawerHover.hovered || held || drawerMenuOpen
    property bool drawerMenuOpen: false
    property real revealProgress: expanded && buckets.drawer.length > 0 ? 1 : 0
    // The drawer's full width, its gap from the arrow included, and the
    // width the reveal shows of it.
    readonly property real drawerExtent: buckets.drawer.length > 0 ? drawerRow.implicitWidth + Theme.bar.item.gap : 0
    readonly property real revealExtent: drawerExtent * revealProgress

    Behavior on revealProgress {
        NumberAnimation { duration: Theme.motion.duration.slow; easing.type: Theme.motion.easing.standard }
    }

    visible: shown
    implicitWidth: shown ? pinnedRow.x + pinnedRow.implicitWidth : 0
    implicitHeight: barSize
    frameActions: [{ label: "Manage tray icons", action: () => Qt.callLater(manage.open) }]

    function itemOf(row) { return widget.trayItems[row.index]; }

    // The arrow and the drawer: the pointer resting anywhere on them keeps
    // the drawer open.
    Item {
        id: drawerArea
        width: arrow.width + widget.revealExtent
        height: parent.height

        HoverHandler { id: drawerHover }

        BarItem {
            id: arrow
            anchors.verticalCenter: parent.verticalCenter
            label: "Tray icons"
            iconName: widget.expanded ? "chevron-right" : "chevron-left"
            tone: widget.bar ? widget.bar.foreground : Theme.bar.foreground
            active: widget.held
            onClicked: widget.held = !widget.held
        }

        Item {
            id: drawerClip
            x: arrow.width
            width: widget.revealExtent
            height: parent.height
            clip: true

            Row {
                id: drawerRow
                x: Theme.bar.item.gap + widget.revealExtent - widget.drawerExtent
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.bar.item.gap

                Repeater {
                    model: widget.buckets.drawer
                    TrayButton {
                        required property var modelData
                        trayItem: widget.itemOf(modelData)
                        tint: widget.bar ? widget.bar.foreground : Theme.bar.foreground
                        onMenuOpenChanged: widget.drawerMenuOpen = menuOpen
                        Component.onDestruction: if (menuOpen) widget.drawerMenuOpen = false
                    }
                }
            }
        }
    }

    Row {
        id: pinnedRow
        x: drawerArea.width + (widget.buckets.pinned.length > 0 ? Theme.bar.item.gap : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.bar.item.gap

        Repeater {
            model: widget.buckets.pinned
            TrayButton {
                required property var modelData
                trayItem: widget.itemOf(modelData)
                tint: widget.bar ? widget.bar.foreground : Theme.bar.foreground
            }
        }
    }

    Popover {
        id: manage
        width: Theme.size.panel.md

        SectionHeader {
            text: "Tray icons"
            description: "Pinned icons always show in the bar. Hidden icons never show."
        }
        Label {
            visible: widget.buckets.listed.length === 0
            text: "No app shows a tray icon."
            role: "hint"
        }
        Repeater {
            model: widget.buckets.listed
            ManageRow {
                required property var modelData
                readonly property var trayItem: widget.itemOf(modelData)
                width: parent.width
                title: TrayLogic.labelOf(trayItem)
                icon: trayItem.icon
                pinned: widget.pinnedIds.indexOf(modelData.id) !== -1
                hidden: widget.hiddenIds.indexOf(modelData.id) !== -1
                onPinToggled: widget.ask("pin", modelData.id)
                onHideToggled: widget.ask("hide", modelData.id)
            }
        }
    }

    // A toggle of the manage popup, handed to the service that writes.
    function ask(kind, id) {
        const reply = shell.ipc.call(kind, id);
        if (reply !== "ok") console.warn("tray: " + kind + " " + id + " " + reply);
    }
}
