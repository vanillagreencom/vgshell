import QtQuick
import QtQml.Models
import qs.Commons

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

    // Widgets mount before PluginSlot fills the bar. Give Row its height
    // before its first transition records the widgets' vertical position.
    implicitHeight: barSize

    // The host maps this screen's bar only while it is shown; the `hidden`
    // setting, which the service's toggle writes, hides it everywhere.
    readonly property bool shown: shell === null || shell.settings.hidden !== true

    readonly property Item leftSection: left
    readonly property Item centerSection: center
    readonly property Item rightSection: right

    // The held widget is parented directly to the bar. Use its existing
    // pointer grab to animate the gap; intrinsic size changes, such as the
    // tray drawer opening, must keep the right section's edge fixed.
    readonly property bool rearranging: children.some(item => item.frameDragging === true)

    readonly property var builtinLabels: ({ "left-workspaces": "Workspaces", "center-clock": "Clock" })
    readonly property var builtinNames: Object.keys(builtinLabels)
    property var widgetLayout: ({ left: [], center: [], right: [] })
    readonly property string builtinKey: JSON.stringify(
        ["left", "center", "right"].reduce((entries, section) => entries.concat(widgetLayout[section]), [])
            .filter(entry => shell !== null && entry.id.indexOf(shell.manifest.id + "/") === 0)
            .map(entry => shell === null ? "" : entry.id.slice(shell.manifest.id.length + 1))
            .filter(name => builtinNames.indexOf(name) !== -1))

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

    // Row's move transition animates children displaced by a gap or a
    // model move: https://doc.qt.io/qt-6/qml-qtquick-row.html#move-prop.
    Row {
        id: left
        move: Transition {
            NumberAnimation { properties: "x"; duration: bar.rearranging ? Theme.motion.duration.normal : 0; easing.type: Theme.motion.easing.standard }
        }
        add: Transition {
            NumberAnimation { properties: "x"; duration: bar.rearranging ? Theme.motion.duration.normal : 0; easing.type: Theme.motion.easing.standard }
        }
        spacing: Theme.bar.gap
        anchors { left: parent.left; leftMargin: Theme.bar.padding; top: parent.top; bottom: parent.bottom }
    }
    Row {
        id: center
        move: Transition {
            NumberAnimation { properties: "x"; duration: bar.rearranging ? Theme.motion.duration.normal : 0; easing.type: Theme.motion.easing.standard }
        }
        add: Transition {
            NumberAnimation { properties: "x"; duration: bar.rearranging ? Theme.motion.duration.normal : 0; easing.type: Theme.motion.easing.standard }
        }
        spacing: Theme.bar.gap
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom }
    }
    Row {
        id: right
        move: Transition {
            NumberAnimation { properties: "x"; duration: bar.rearranging ? Theme.motion.duration.normal : 0; easing.type: Theme.motion.easing.standard }
        }
        add: Transition {
            NumberAnimation { properties: "x"; duration: bar.rearranging ? Theme.motion.duration.normal : 0; easing.type: Theme.motion.easing.standard }
        }
        spacing: Theme.bar.gap
        anchors { right: parent.right; rightMargin: Theme.bar.padding; top: parent.top; bottom: parent.bottom }
    }
}
