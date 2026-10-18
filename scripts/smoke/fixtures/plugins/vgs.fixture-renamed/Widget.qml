import QtQuick
import qs.Ui
// The configuration row reads this line: a build under the new id while
// the user file disables the former id.
BarWidget {
    implicitWidth: 20
    implicitHeight: barSize
    Component.onCompleted: console.log("renamed-fixture: built kind=bar-widget")
}
