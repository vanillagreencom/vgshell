import QtQuick
import QtQml.Models
import qs.Commons
import qs.Ui

// The core orders registered built-ins and plugin widgets together.
// The bar owns its built-in model; visual section changes keep its delegates.
Item {
    id: bar

    property var shell: null
    property var screen: null

    readonly property color foreground: Theme.bar.foreground
    readonly property color background: Theme.bar.background
    readonly property string fontFamily: Theme.text.bar.family
    readonly property int barSize: Theme.bar.height

    // The host maps this screen's bar only while it is shown; the `hidden`
    // setting, which the service's toggle writes, hides it everywhere.
    readonly property bool shown: shell === null || shell.settings.hidden !== true

    readonly property Item leftSection: left
    readonly property Item centerSection: center
    readonly property Item rightSection: right

    readonly property var builtinLabels: ({ "left-workspaces": "Workspaces", "center-clock": "Clock" })
    readonly property var builtinNames: Object.keys(builtinLabels)
    // Gaps and separators the user adds from the bar's right-click menu:
    // one builtin per layout entry, `gap-<n>` or `separator-<n>`.
    readonly property var builtinFamilies: ["gap", "separator"]
    readonly property var familyLabels: ({ gap: "Gap", separator: "Separator" })
    // The family of registration `name`, or "" for a fixed builtin.
    function familyOf(name) {
        const match = /^([a-z]+)-[1-9][0-9]*$/.exec(name);
        return match !== null && builtinFamilies.indexOf(match[1]) !== -1 ? match[1] : "";
    }
    function builtinLabel(name) {
        const family = familyOf(name);
        return family !== "" ? familyLabels[family] : builtinLabels[name];
    }
    property var widgetLayout: ({ left: [], center: [], right: [] })
    readonly property string builtinKey: JSON.stringify(
        ["left", "center", "right"].reduce((entries, section) => entries.concat(widgetLayout[section]), [])
            .filter(entry => shell !== null && entry.id.indexOf(shell.manifest.id + "/") === 0)
            .map(entry => shell === null ? "" : entry.id.slice(shell.manifest.id.length + 1))
            .filter(name => builtinNames.indexOf(name) !== -1 || familyOf(name) !== ""))

    // ListModel.move keeps Repeater delegates alive across section changes:
    // https://doc.qt.io/qt-6/qml-qtqml-models-listmodel.html#move-method.
    function syncBuiltins(model, key) {
        const names = JSON.parse(key);
        for (let i = model.count - 1; i >= 0; --i)
            if (names.indexOf(model.get(i).name) === -1) model.remove(i);
        for (let i = 0; i < names.length; ++i) {
            let at = i;
            while (at < model.count && model.get(at).name !== names[i]) ++at;
            if (at === model.count) model.insert(i, { name: names[i] });
            else if (at !== i) model.move(at, i, 1);
        }
    }
    ListModel { id: builtinModel }
    onBuiltinKeyChanged: syncBuiltins(builtinModel, builtinKey)
    Component.onCompleted: syncBuiltins(builtinModel, builtinKey)
    Repeater { model: builtinModel; Builtin { barItem: bar } }

    readonly property bool spacerMenuOpen: spacerUi.item !== null && spacerUi.item.menuOpened
    // The texts of the open add menu's entries, in order; [] while closed.
    readonly property var spacerMenuEntries: spacerUi.item !== null ? spacerUi.item.menuEntries : []

    // Whether bar point (x, y) falls on a drawn widget, whose own frame
    // menu takes the right click.
    function overWidget(x, y) {
        return [left, center, right].some(section => section.children.some(item =>
            item.visible && item.width > 0 && item.contains(item.mapFromItem(bar, x, y))));
    }

    // The new entry lands where a widget dragged to the click would drop.
    function addSpacer(family, x) {
        const reply = shell.builtins.add(family, bar.mapToItem(null, x, 0).x);
        if (reply !== "ok") console.warn("vgs.bar: add " + family + " " + reply);
    }

    // TapHandler's default DragThreshold policy takes a passive grab, so
    // a widget's own frame handler sees the same right click; overWidget
    // leaves that click to it (Qt Quick TapHandler gesturePolicy reference).
    // pointer-cursor-exempt: it adds the right click to the empty bar, which shows no control
    // keyboard-path: none; adding a gap or a separator is a pointer arrangement of the bar, as a drag is
    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: bar.shell !== null
        onTapped: eventPoint => {
            const at = eventPoint.position;
            if (bar.overWidget(at.x, at.y)) return;
            spacerUi.active = true;
            spacerUi.item.openAt(at.x);
        }
    }

    // The add menu is built on the first right click on the empty bar and
    // released once closed, so a bar at rest holds none.
    Loader {
        id: spacerUi

        function release() {
            if (item !== null && !item.menuOpened) active = false;
        }

        active: false
        sourceComponent: Item {
            id: ui

            readonly property bool menuOpened: spacerMenu.opened
            readonly property var menuEntries: spacerMenu.opened ? spacerMenu.items().map(entry => entry.text) : []

            // The menu opens under the click, which is where its entry lands.
            function openAt(clickX) {
                x = clickX;
                spacerMenu.open();
            }

            // The menu opens at this rectangle's bottom-left corner; one
            // stroke wide keeps it non-empty.
            width: Theme.divider.thickness
            height: bar.height
            onMenuOpenedChanged: if (!menuOpened) Qt.callLater(spacerUi.release)

            Menu {
                id: spacerMenu

                MenuItem {
                    text: "Add separator"
                    iconName: "separator-vertical"
                    onTriggered: bar.addSpacer("separator", ui.x)
                }
                MenuItem {
                    text: "Add gap"
                    iconName: "space"
                    onTriggered: bar.addSpacer("gap", ui.x)
                }
            }
        }
    }

    // The core positions children and sizes these passive containers.
    // Qt 6.11 Row transitions write y even when their animation names x;
    // that write removes the core's vertical-centering binding.
    Item {
        id: left
        readonly property real spacing: Theme.bar.gap
        anchors { left: parent.left; leftMargin: Theme.bar.padding; top: parent.top; bottom: parent.bottom }
    }
    Item {
        id: center
        readonly property real spacing: Theme.bar.gap
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom }
    }
    Item {
        id: right
        readonly property real spacing: Theme.bar.gap
        anchors { right: parent.right; rightMargin: Theme.bar.padding; top: parent.top; bottom: parent.bottom }
    }
}
