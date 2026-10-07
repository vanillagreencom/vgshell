import QtQuick

// Only the modal's interface is needed by the offscreen Displays footer
// test. This item creates no window. The nested Displays row builds the
// real host and tests its modality, position, focus and destruction.
Item {
    property bool shown: false
    property string title: ""
    property string message: ""
    property var actions: []
    property bool busy: false
    signal accepted()
    signal rejected()
}
