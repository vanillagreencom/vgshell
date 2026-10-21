import QtQuick

// Stands in for Quickshell's LazyLoader, whose plugin does not load outside
// the shell: `component` is built while `active` holds, once the loader's
// reload has run, and destroyed when it drops. Quickshell reloads a loader
// made after the shell loaded on the event loop's next turn and builds
// nothing before, so an `active` set in the turn that made the loader
// leaves `item` null until then (Quickshell 2b4501a, src/core/reload.cpp
// componentComplete and src/core/lazyloader.cpp incubateIfReady). The
// asynchronous `loading` and `activeAsync` are not stood in.
QtObject {
    id: loader

    default property Component component: null
    property bool active: false
    property QtObject item: null
    property bool reloaded: false

    readonly property Timer reload: Timer {
        interval: 0
        running: true
        onTriggered: {
            loader.reloaded = true;
            loader.follow();
        }
    }

    function follow() {
        if (active && item === null && reloaded) item = component.createObject(loader);
        else if (!active && item !== null) {
            item.destroy();
            item = null;
        }
    }

    onActiveChanged: follow()
}
