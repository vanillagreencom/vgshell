import QtQuick
// configuration.sh reads this construction line to catch a split adopted
// after the registry publishes, when the default settings reach the build.
Item {
    property var shell: null
    property var screen: null
    Component.onCompleted: console.log("split-fixture: built format=" + shell.settings.format)
}
