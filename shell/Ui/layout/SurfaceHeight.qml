import QtQuick
import QtQuick.Window
import qs.Commons

// A summoned surface's card, as the launcher draws its card: the card's
// height follows `target`, the height its content asks for, over
// `motion.surface.resize`, and its content lays out at the card's height,
// so a footer rides the card's bottom edge as it grows. The card clips only
// while it is shorter than its content, so at rest a child draws past its
// edge, as a shadow does. `surface` is the larger of `room` and `target`:
// the native height a popup host keeps while it shows, so the window stays
// one size while the content changes inside the room. A layer host covers
// its screen and reads no `surface`. While the card grows, `surfaceGrowing`
// tells a Pane inside that its body is short only for the moment, so it
// draws no scroll bar or footer divider for it. Until the window has drawn
// its first frame since it showed, the card takes each height at once, so
// it opens at its height rather than growing into it.
Item {
    id: root

    property real target: 1
    property real room: 0
    readonly property real surface: Math.max(room, target)
    readonly property bool surfaceGrowing: height < target
    property bool live: false

    width: parent ? parent.width : 0
    height: target
    clip: surfaceGrowing

    Behavior on height {
        enabled: root.live
        NumberAnimation {
            duration: Theme.motion.surface.resize.duration
            easing.type: Theme.motion.surface.resize.easing
        }
    }

    readonly property var window: Window.window
    readonly property bool shownWindow: window !== null && window.visible
    onShownWindowChanged: live = false
    // frameSwapped comes from the render thread, queued to this one.
    Connections {
        target: root.window
        enabled: root.shownWindow && !root.live
        function onFrameSwapped() { root.live = true; }
    }
}
