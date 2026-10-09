import QtQuick

// Stands in for Quickshell's Variants, whose plugin does not load outside
// the shell: one `delegate` instance per `model` entry, built with that
// entry as its required `modelData`. The installed Quickshell's
// quickshell-core.qmltypes declares `delegate` a Component and the default
// property, beside `model` and the read-only list `instances`. Every model
// change builds the instances again; the real type keeps the instance of
// an entry that stays in the model.
QtObject {
    id: variants

    default property Component delegate: null
    property var model: []
    property var instances: []

    function follow() {
        for (const instance of instances) instance.destroy();
        instances = delegate === null ? [] : Array.from(model || [], entry => delegate.createObject(variants, { modelData: entry }));
    }

    onModelChanged: follow()
    onDelegateChanged: follow()
}
