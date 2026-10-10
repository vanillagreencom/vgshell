import QtQuick
import qs.Commons

// A wash over everything behind a modal surface: it fills its parent with
// `color.scrim`, takes the presses, the hover and the wheel that land on it,
// so nothing under it answers, and emits `clicked` for a click-away. The caller declares the
// modal surface after it, so the surface sits above the scrim.
Rectangle {
    id: root

    signal clicked()

    // Whether something its parent draws lies under the scrim: a child of
    // the parent painted before it, at a lower `z` or at the same `z` earlier
    // in `children` (Qt 6 Item.z reference), that is visible, has an opacity
    // above 0 and a width and a height. Only the parent's children are read:
    // a scrim fills its parent, so that is what it washes; a host above it
    // draws nothing, a VGS layer being transparent, and its input catchers,
    // such as SummonLayer's MouseArea, are not content. A GlassSurface over a
    // scrim that holds it draws no glass (GlassSurface.qml overContent).
    readonly property bool overContent: washesContent()
    // The marker GlassSurface reads to find a scrim among the items under it.
    readonly property bool scrim: true

    function washesContent() {
        if (parent === null) return false;
        const kids = parent.children;
        let index = 0;
        while (index < kids.length && kids[index] !== root) index++;
        for (let i = 0; i < kids.length; i++) {
            const other = kids[i];
            if (other === root || other.z > root.z || (other.z === root.z && i > index)) continue;
            if (other.visible && other.opacity > 0 && other.width > 0 && other.height > 0) return true;
        }
        return false;
    }

    anchors.fill: parent
    color: Theme.color.scrim

    // pointer-cursor-exempt: a press here is a click away from the modal surface, not a control
    // keyboard-path: the modal surface that owns the scrim closes on Escape
    MouseArea {
        anchors.fill: root
        // A MouseArea passes hover, and a wheel no handler accepts, to the
        // items under it.
        hoverEnabled: true
        onClicked: root.clicked()
        onWheel: wheel => { wheel.accepted = true; }
    }
}
