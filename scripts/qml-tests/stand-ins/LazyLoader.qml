import QtQuick

// Stands in for Quickshell's LazyLoader, whose plugin does not load outside
// the shell: `component` is built while `active` holds and destroyed when
// it drops. The asynchronous `loading` and `activeAsync` are not stood in.
QtObject {
    id: loader

    default property Component component: null
    property bool active: false
    property QtObject item: null

    function follow() {
        if (active && item === null) item = component.createObject(loader);
        else if (!active && item !== null) {
            item.destroy();
            item = null;
        }
    }

    onActiveChanged: follow()
    Component.onCompleted: follow()
}
