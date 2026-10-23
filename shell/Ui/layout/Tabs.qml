import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// A row of tabs: `model` lists the tab texts and `currentIndex` the open
// one. The template owns the index, the left and right keys and the click;
// this file draws each tab, its label centred `tabs.paddingX` in from each
// side, and the indicator under the open one. Hover lifts a closed tab's
// label, a press leaves its background transparent, and a disabled row fades. A view that
// draws the row on something other than a resting surface hands it
// `foreground`, `hover` and `active` label colours and the open tab's
// `indicatorColor`, and sets
// `hoverMark` where those colours are too near one another to tell
// apart: a closed tab under the pointer then draws a line in its
// label's colour, thinner than the open tab's, whose colour it can
// share, and the row draws no track, whose colour is a resting
// surface's border and would show as a stub between the tabs' own
// lines. While the row holds the keyboard, Ctrl+Tab,
// Ctrl+Shift+Tab, Ctrl+PageDown and Ctrl+PageUp step the open tab, round
// the ends.
T.TabBar {
    id: root

    property var model: []
    property var warningTabs: []
    property color foreground: Theme.tabs.foreground
    property color hover: Theme.tabs.hover
    property color active: Theme.tabs.active
    property color indicatorColor: Theme.tabs.indicatorColor
    property bool hoverMark: false

    implicitWidth: contentItem.implicitWidth
    implicitHeight: Theme.tabs.height
    spacing: Theme.tabs.gap
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : Theme.opacity.disabled
    Keys.onPressed: event => { event.accepted = nav.handle(event); }

    property KeyNav nav: KeyNav {
        focusTarget: root
        count: root.count
        currentIndex: root.currentIndex
        orientation: "horizontal"
        wrap: true
        stepsTabs: true
        onMoved: index => root.currentIndex = index
        onTabStepped: delta => moveBy(delta)
    }

    contentItem: ListView {
        id: strip
        model: root.contentModel
        currentIndex: root.currentIndex
        orientation: ListView.Horizontal
        spacing: root.spacing
        boundsBehavior: Flickable.StopAtBounds
        acceptedButtons: Qt.NoButton
        flickableDirection: Flickable.AutoFlickIfNeeded
        snapMode: ListView.SnapToItem
        highlightMoveDuration: Theme.motion.duration.fast
        highlightRangeMode: ListView.ApplyRange
        implicitWidth: contentWidth
        TouchpadScroll { view: strip }
    }

    background: Item {
        Rectangle {
            objectName: "track"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.border.thin
            color: Theme.tabs.border
            visible: !root.hoverMark
        }
    }

    Repeater {
        model: root.model
        // keyboard-path: the tab bar is one tab stop and its arrow keys choose tabs
        T.TabButton {
            id: tab
            required property var modelData
            readonly property bool selectedFocus: root.visualFocus && checked
            // The label and the hover mark read the row's values here,
            // never through `root`: they follow hover and the open tab,
            // which change while the row is destroyed, when `root` already
            // reads null.
            readonly property color foreground: root.foreground
            readonly property color hover: root.hover
            readonly property color active: root.active
            readonly property color indicatorColor: root.indicatorColor
            readonly property bool hoverMark: root.hoverMark
            readonly property bool warning: root.warningTabs.indexOf(String(modelData)) !== -1
            text: String(modelData)
            implicitWidth: implicitContentWidth + leftPadding + rightPadding
            implicitHeight: Theme.tabs.height
            leftPadding: Theme.tabs.paddingX
            rightPadding: Theme.tabs.paddingX
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            PointerCursor {}
            Accessible.name: warning ? text + ": setup needed" : text
            // A selection callback can open a dialog. Give this press
            // its pointer focus before the template changes the index.
            onPressed: { root.forceActiveFocus(Qt.MouseFocusReason); root.focusReason = Qt.MouseFocusReason; }

            contentItem: Item {
                implicitWidth: labelGroup.implicitWidth
                implicitHeight: labelGroup.implicitHeight
                // Control stretches its contentItem inside the padding.
                // Keep the Row at its natural size and centre that group.
                // https://doc.qt.io/qt-6/qml-qtquick-controls-control.html#contentItem-prop
                Row {
                    id: labelGroup
                    anchors.centerIn: parent
                    spacing: Theme.stack.inline
                    // Qt Row omits invisible children and their spacing.
                    // https://doc.qt.io/qt-6/qml-qtquick-row.html
                    Label {
                        objectName: "tabLabel"
                        role: "button"
                        text: tab.text
                        horizontalAlignment: Text.AlignHCenter
                        color: tab.checked ? tab.active : tab.hovered || tab.down ? tab.hover : tab.foreground
                        verticalAlignment: Text.AlignVCenter
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
                    }
                    Icon {
                        objectName: "tabWarning"
                        name: "triangle-alert"
                        color: Theme.color.warning
                        size: Theme.icon.size.sm
                        visible: tab.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            background: Rectangle {
                color: "transparent"
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Theme.tabs.indicator
                    objectName: "indicator"
                    color: tab.indicatorColor
                    visible: tab.checked
                }
                FocusRing { target: tab; visible: tab.selectedFocus }
                Rectangle {
                    objectName: "hoverMark"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Theme.tabs.hoverIndicator
                    color: tab.hover
                    visible: tab.hoverMark && !tab.checked && (tab.hovered || tab.down)
                }
            }
        }
    }
}
