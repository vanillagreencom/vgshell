import QtQuick

// Bottom shading and a top-left highlight make the toast dot read as glass.
Item {
    id: orb

    required property var look
    property real amount: 0
    property real radius: look.radius.full

    anchors.fill: parent
    visible: amount > 0
    opacity: amount
    readonly property real d: Math.min(width, height)

    Rectangle {
        anchors.fill: parent
        radius: orb.radius
        gradient: Gradient {
            GradientStop { position: orb.look.orb.shadeStop; color: orb.look.orb.clear }
            GradientStop { position: 1; color: orb.look.orb.shade }
        }
    }
    Rectangle {
        x: parent.width / 2 - parent.d * orb.look.orb.spotX
        y: parent.height / 2 - parent.d * orb.look.orb.spotY
        width: parent.d * orb.look.orb.spotWidth
        height: parent.d * orb.look.orb.spotHeight
        radius: orb.look.radius.full
        rotation: orb.look.orb.spotAngle
        gradient: Gradient {
            GradientStop { position: 0; color: orb.look.orb.spot }
            GradientStop { position: 1; color: orb.look.orb.spotEnd }
        }
    }
}
