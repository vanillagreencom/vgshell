import QtQuick
import QtQml.Models
import qs.Commons

// The bar: three sections across the surface. Each section shows the bar's
// own built-in widgets first, in the order its `left`, `center` and `right`
// settings list them, then the plugin widgets the core mounts into the
// same container. The core owns every plugin widget; this file owns the
// geometry and the built-ins. `shell` and `screen` are assigned by the
// core after creation.
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

    // The held widget is parented directly to the bar. Use its existing
    // pointer grab to animate the gap; intrinsic size changes, such as the
    // tray drawer opening, must keep the right section's edge fixed.
    readonly property bool rearranging: children.some(item => item.frameDragging === true)

    // The built-in names one section lists, as text: a settings change
    // that leaves the list alone produces the same string, so the section
    // keeps its built-ins instead of rebuilding them. A name listed twice
    // in one section is drawn once, since each registers with the core
    // under `<section>-<name>`; the repeat is logged.
    function builtinsKey(section) {
        if (shell === null) return "[]";
        const names = shell.settings[section];
        if (!Array.isArray(names)) {
            console.warn("vgs.bar: setting " + section + " is not a list of built-in names: " + JSON.stringify(names));
            return "[]";
        }
        const once = names.filter((name, i) => names.indexOf(name) === i);
        if (once.length !== names.length)
            console.warn("vgs.bar: setting " + section + " lists a built-in twice, drawn once: " + JSON.stringify(names));
        return JSON.stringify(once);
    }
    readonly property string leftKey: builtinsKey("left")
    readonly property string centerKey: builtinsKey("center")
    readonly property string rightKey: builtinsKey("right")

    // ListModel.move keeps the Repeater's existing delegates (Qt ListModel
    // and Repeater references); only an added or removed name changes lifetime.
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
    ListModel { id: leftModel }
    ListModel { id: centerModel }
    ListModel { id: rightModel }
    onLeftKeyChanged: syncBuiltins(leftModel, leftKey)
    onCenterKeyChanged: syncBuiltins(centerModel, centerKey)
    onRightKeyChanged: syncBuiltins(rightModel, rightKey)
    Component.onCompleted: {
        syncBuiltins(leftModel, leftKey);
        syncBuiltins(centerModel, centerKey);
        syncBuiltins(rightModel, rightKey);
    }

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
        Repeater { model: leftModel; Builtin { barItem: bar; section: "left" } }
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
        Repeater { model: centerModel; Builtin { barItem: bar; section: "center" } }
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
        Repeater { model: rightModel; Builtin { barItem: bar; section: "right" } }
    }
}
