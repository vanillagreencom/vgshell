import QtQuick
// configuration.sh reads this construction line to catch a split adopted
// after the registry publishes, when the default settings reach the build.
Item {
    property var shell: null
    property var screen: null
    property bool recorded: false
    // The scoped shell arrives after construction, as the plugin API and
    // configuration.sh's null-shell run show. Capture only its first value;
    // a later settings update is not another construction.
    onShellChanged: {
        if (shell === null || recorded) return;
        recorded = true;
        console.log("split-fixture: built format=" + shell.settings.format);
    }
}
