import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Base item for plugin widgets and registered builtin wrappers. The core
// assigns these properties to plugin widgets after it builds the widget:
// `shell` (the widget's own scoped object), `bar` (the bar API),
// `moduleName` (the plugin id), `settings` (the manifest defaults under
// the plugin's plugins[] row, as every kind receives them) and `frame`,
// what Hide, Settings and a drag
// read and call: `describe()` answers { name, page, readme, keys, stops,
// builtin, owner }, `hide()` takes the widget out of every bar section,
// `openReadme()` opens `readme`, `openSettings()` opens Plugins on
// `page`, `openPage(page, tab)` opens what a BarItem's
// `tooltipPageActivated` names, Plugins on a page and tab or a cited file
// in the core edit route (PageReference), `dragStart`, `dragMove` and
// `dragEnd` take the drag's points,
// and `dragCancel()` ends a remove
// question.
// `unplaced` marks an unplacedSection mount. Its frame is null, so it
// offers neither Hide nor drag for a position absent from saved layout.
//
// Every widget gets the same right-click menu, with no code in the plugin:
// Hide, then the entries the widget hands in `frameActions`, each
// { label, icon, action }, which a click or Enter runs, then Readme, then
// Settings. Readme opens a bundled plugin's README page on GitHub and is
// absent for an installed plugin. Settings
// opens Plugins on the owning plugin's page through the same link as a
// pane's gear; a builtin opens its bar's page. The entry is absent when
// the plugin has no Settings page. A builtin hides at once; its Settings >
// Bar switch restores it. A plugin widget asks first in a small dialog under the widget,
// which says how to bring the widget back, shows the shortcuts that keep
// working, and says when hiding also turns the plugin off. Cancel holds the
// focus, so Enter and Escape change nothing; a press outside closes it too.
// A drag shows one copy of the widget under the pointer, on the bar and
// off it, while the widget's place in the bar is the preview gap. A drag
// released far outside the bar puts the widget back where the drag found
// it and asks there, in the same dialog, whether to remove the widget from
// the bar, which is what Hide does; every other answer leaves it there.
// That dialog opens from the pointer, so Cancel holds the focus with no
// focus ring.
// The menu and the dialog are built on the first right click or that
// release and released once both are closed, so a widget at rest holds
// neither.
Item {
    id: root

    property var shell: null
    property QtObject bar: null
    property string moduleName: ""
    property var settings: ({})
    property var frame: null
    property bool unplaced: false
    // A saved widget can become unplaced without being destroyed. Close
    // its frame UI before any menu action can use the withdrawn locator.
    onFrameChanged: if (frame === null) frameUi.active = false
    // The widget's own menu entries after Hide, each { label, icon, action }.
    property var frameActions: []
    // The first entry's text and icon. It runs Hide; a builtin the user
    // added from the bar's own menu names it as a removal.
    property string frameHideText: "Hide"
    property string frameHideIcon: "eye-off"

    readonly property int barSize: bar ? bar.barSize : Theme.bar.height
    readonly property bool frameMenuOpen: frameUi.item !== null && frameUi.item.menuOpened
    readonly property bool frameDialogOpen: frameUi.item !== null && frameUi.item.dialogOpened
    readonly property bool frameDragging: dragHandler.active
    // The texts of the open menu's entries, in order; [] while it is closed.
    readonly property var frameMenuEntries: frameUi.item !== null ? frameUi.item.menuEntries : []

    // Whether the core holds this widget for a drag: it parents the held
    // widget to the bar until the drop, a cancel or a release that asks.
    readonly property bool dragHeld: frameDragging && bar !== null && parent === bar
    // The held widget draws nothing while its drag image shows.
    opacity: dragHeld && dragImage.item !== null && dragImage.item.visible ? 0 : 1

    // A held drag takes a share of OverlayState, as an open menu does, so
    // no tooltip opens over the widget the user moves or the slot it aims
    // at, and one already shown closes.
    property bool dragCounted: false
    function shareDrag(held) {
        if (held === dragCounted) return;
        dragCounted = held;
        if (held) OverlayState.opened(); else OverlayState.closed();
    }
    onFrameDraggingChanged: shareDrag(frameDragging)
    Component.onDestruction: shareDrag(false)

    // Behavior animates changes to this x property alone:
    // https://doc.qt.io/qt-6/qml-qtquick-behavior.html
    // The grabbed widget follows the pointer directly. At rest, intrinsic
    // size changes keep the right section's edge fixed without animation.
    Behavior on x {
        enabled: !root.frameDragging && root.bar !== null
            && root.bar.children.some(item => item.frameDragging === true)
        NumberAnimation { duration: Theme.motion.duration.normal; easing.type: Theme.motion.easing.standard }
    }

    // One setting with a fallback for a missing or null value.
    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    // pointer-cursor-exempt: it adds the right click to the widget, whose own controls show the hand
    // keyboard-path: Settings has placement switches for plugins and bar builtins
    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: root.frame !== null && typeof root.frame.hide === "function"
        onTapped: {
            frameUi.active = true;
            frameUi.item.openMenu();
        }
    }

    function dragPoint() {
        const centroid = dragHandler.centroid;
        return { x: centroid.scenePosition.x, y: centroid.scenePosition.y };
    }

    // Where the press holds the widget, from its top-left corner, read
    // when the drag starts. HandlerPoint.scenePressPosition keeps the
    // pickup offset when a drag activates after its threshold (Qt Quick
    // HandlerPoint reference).
    property point dragPickup: Qt.point(0, 0)

    // Qt Quick still hands a press a child button accepted to this parent
    // handler, which takes the grab from the button once the drag starts,
    // so the button emits no click (QQuickPointerHandler::
    // approveGrabTransition; QQuickAbstractButton sets no keepMouseGrab,
    // qtdeclarative 6.11).
    DragHandler {
        id: dragHandler
        target: null
        acceptedButtons: Qt.LeftButton
        enabled: root.frame !== null
        onActiveChanged: {
            if (active) {
                const at = root.mapToItem(null, 0, 0);
                const press = dragHandler.centroid.scenePressPosition;
                root.dragPickup = Qt.point(press.x - at.x, press.y - at.y);
                root.frame.dragStart(root.dragPoint());
            }
            // Release commits the last preview; displaced neighbours
            // must not select a new slot without pointer motion.
            else if (root.frame !== null && root.frame.dragEnd(root.dragPoint()) === "ask") {
                frameUi.active = true;
                frameUi.item.asking = true;
                Qt.callLater(frameUi.item.ask, "remove");
            }
        }
        onActiveTranslationChanged: if (active) root.frame.dragMove(root.dragPoint())
    }

    // The drag image: one copy of the widget, as it drew when the drag
    // started (Item.grabToImage, at the bar window's pixel ratio), with the
    // pointer where the press holds it. The widget is a child of the bar's
    // layer window, which draws nothing outside its box, so the copy is a
    // popup of that window (Quickshell 0.3.1 PopupWindow, an xdg_popup)
    // that follows the pointer on the bar and off it. grabFocus false makes
    // no grab and an empty mask takes no input, so the press stays with the
    // bar. LazyLoader destroys the popup when the drag ends.
    LazyLoader {
        id: dragImage
        active: root.dragHeld

        PopupWindow {
            id: image

            property var grab: null

            objectName: "frame-drag-image"
            anchor.window: root.QsWindow.window
            anchor.rect.x: Math.round(dragHandler.centroid.scenePosition.x - root.dragPickup.x)
            anchor.rect.y: Math.round(dragHandler.centroid.scenePosition.y - root.dragPickup.y)
            anchor.edges: Edges.Top | Edges.Left
            anchor.gravity: Edges.Bottom | Edges.Right
            anchor.adjustment: PopupAdjustment.None
            grabFocus: false
            mask: Region {}
            color: "transparent"
            implicitWidth: Math.max(1, Math.ceil(root.width))
            implicitHeight: Math.max(1, Math.ceil(root.height))
            visible: grab !== null

            Image {
                anchors.fill: parent
                source: image.grab !== null ? image.grab.url : ""
            }

            Component.onCompleted: {
                const ratio = root.QsWindow.window.devicePixelRatio;
                const size = Qt.size(Math.ceil(root.width * ratio), Math.ceil(root.height * ratio));
                if (!root.grabToImage(result => image.grab = result, size))
                    console.warn("bar widget: drag image of " + root.moduleName + " refused");
            }
        }
    }

    Loader {
        id: frameUi

        // Release the menu and the dialog once neither is open nor about
        // to open.
        function release() {
            if (item !== null && !item.asking && !item.menuOpened && !item.dialogOpened) active = false;
        }

        anchors.fill: parent
        active: false
        sourceComponent: Item {
            id: ui

            readonly property bool menuOpened: hideMenu.opened
            readonly property bool dialogOpened: dialogWindow.visible
            readonly property var menuEntries: hideMenu.opened ? hideMenu.items().filter(entry => entry.visible).map(entry => entry.text) : []
            // Hide or a far drop was chosen and the dialog has not opened yet.
            property bool asking: false
            // What the dialog asks: "hide" from the menu, "remove" from a drop.
            property string question: "hide"
            // What the open dialog says, read from `frame` when it opens.
            property var facts: ({ name: "", page: "", keys: [], stops: false, builtin: false, owner: "" })
            property string settingsPage: ""
            property string readme: ""

            function openMenu() {
                const facts = root.frame.describe();
                settingsPage = facts.page;
                readme = facts.readme;
                hideMenu.open("pointer");
            }

            function ask(kind) {
                asking = false;
                if (root.frame === null) return;
                question = kind;
                facts = root.frame.describe();
                dialogWindow.visible = true;
                Qt.callLater(() => dialog.forceActiveFocus(Qt.OtherFocusReason));
            }

            // The dialog's share of OverlayState, taken as Popover takes its own.
            property bool counted: false
            function share(open) {
                if (open === counted) return;
                counted = open;
                if (open) OverlayState.opened(); else OverlayState.closed();
            }
            Component.onDestruction: share(false)

            onMenuOpenedChanged: if (!menuOpened) Qt.callLater(frameUi.release)
            onDialogOpenedChanged: {
                if (dialogOpened) return;
                if (question === "remove" && root.frame !== null) root.frame.dragCancel();
                Qt.callLater(frameUi.release);
            }

            Menu {
                id: hideMenu

                MenuItem {
                    text: root.frameHideText
                    iconName: root.frameHideIcon
                    // The menu's grab ends before the dialog takes its own.
                    onTriggered: {
                        if (root.frame.describe().builtin) {
                            const reply = root.frame.hide();
                            if (reply !== "ok") console.warn("bar widget: hide " + root.moduleName + " " + reply);
                            return;
                        }
                        ui.asking = true;
                        Qt.callLater(ui.ask, "hide");
                    }
                }
                Repeater {
                    model: root.frameActions
                    MenuItem {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        iconName: modelData.icon
                        // Read from the list itself: a model entry is a copy
                        // that need not keep the function.
                        onTriggered: root.frameActions[index].action()
                    }
                }
                MenuItem {
                    text: "Readme"
                    iconName: "book"
                    visible: ui.readme !== ""
                    onTriggered: {
                        const reply = root.frame.openReadme();
                        if (reply !== "ok") console.warn("bar widget: readme of " + root.moduleName + " " + reply);
                    }
                }
                MenuItem {
                    text: "Settings"
                    iconName: "settings"
                    visible: ui.settingsPage !== ""
                    onTriggered: {
                        const reply = root.frame.openSettings();
                        if (reply !== "ok") console.warn("bar widget: settings of " + root.moduleName + " " + reply);
                    }
                }
            }

            PopupWindow {
                id: dialogWindow

                anchor.item: ui
                anchor.edges: Edges.Bottom | Edges.Left
                anchor.gravity: Edges.Bottom | Edges.Right
                anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
                anchor.margins.bottom: -Theme.popover.gap
                grabFocus: true
                visible: false
                color: "transparent"
                implicitWidth: Math.max(1, OverlayState.widthFor(ui, Theme.dialog.width))
                implicitHeight: Math.max(1, dialog.implicitHeight)
                onVisibleChanged: ui.share(visible)

                DismissScope {
                    popup: dialogWindow
                    anchor: ui

                    Dialog {
                        id: dialog
                        anchors.fill: parent
                        title: ui.question === "remove" ? "Remove " + ui.facts.name + " from the bar?" : "Hide " + ui.facts.name + "?"
                        // The words that name the page open it, as the
                        // menu's Settings entry does; with no manager
                        // window `page` is "" and they read as words.
                        message: ui.facts.name + " leaves the bar. To show it again, turn on "
                            + (ui.facts.builtin ? "Show on the bar under " + ui.facts.name + " on the " + ui.facts.owner : (ui.facts.stops ? "Enabled" : "Show in bar") + " on its")
                            + " [page in Plugins](page:" + ui.facts.page + ")." + (ui.facts.stops ? " Hiding it also turns it off." : "")
                        onMessagePageActivated: {
                            dialogWindow.visible = false;
                            const reply = root.frame.openSettings();
                            if (reply !== "ok") console.warn("bar widget: settings of " + root.moduleName + " " + reply);
                        }
                        actions: [{ label: "Cancel", role: "cancel", focused: true }, { label: ui.question === "remove" ? "Remove" : "Hide", role: "accept", variant: "danger" }]
                        onAccepted: {
                            dialogWindow.visible = false;
                            const reply = root.frame.hide();
                            if (reply !== "ok") console.warn("bar widget: hide " + root.moduleName + " " + reply);
                        }
                        onRejected: dialogWindow.visible = false

                        Label {
                            text: "Its shortcuts still work."
                            visible: ui.facts.keys.length > 0 && !ui.facts.stops
                        }
                        Repeater {
                            model: ui.facts.stops ? [] : ui.facts.keys
                            KeyCaps { shortcut: modelData }
                        }
                    }
                }
            }

            readonly property AnchorTracker tracker: AnchorTracker { popup: dialogWindow; anchor: ui }
        }
    }
}
