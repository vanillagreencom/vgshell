import QtQuick
// The configuration row reads this line: a build under the new id while
// the user file disables the former id.
Item {
    property var shell: null
    property var screen: null
    Component.onCompleted: console.log("renamed-fixture: built kind=background")
}
