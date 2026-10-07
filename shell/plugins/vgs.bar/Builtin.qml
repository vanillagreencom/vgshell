import QtQuick

// One built-in widget of the bar, chosen by name, and registered with the
// core as `<section>-<name>` so the build records list it under the bar's
// screen; the same built-in may sit in two sections. A name the bar
// does not draw is logged and shows nothing; `manager`, the plugin manager
// the Settings plugin replaced, is logged with the command that places
// that plugin's gear instead. The bar lists each name once
// per section, so the registration is never a repeat; the core's refusal
// of one would throw here and be logged by the engine.
Loader {
    id: root

    required property string name
    required property Item barItem
    required property string section
    property var release: null

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    sourceComponent: name === "clock" ? clock : name === "workspaces" ? workspaces : null

    Component { id: clock; Clock { bar: root.barItem } }
    Component { id: workspaces; Workspaces { bar: root.barItem } }

    Component.onCompleted: {
        if (sourceComponent !== null) return;
        if (name === "manager")
            console.error("bar: no built-in widget named \"manager\": the plugin manager moved to the Plugins plugin, vgs.settings; `vgshell plugin enable vgs.settings` places its plug in the bar");
        else
            console.error("bar: no built-in widget named " + JSON.stringify(name));
    }
    onLoaded: release = barItem.shell.builtins.register(section + "-" + name, item)
    Component.onDestruction: if (release !== null) release()
}
