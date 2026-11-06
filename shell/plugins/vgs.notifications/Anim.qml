import QtQuick

// Callers supply motion-scaled durations so zero motion stills the animation.
NumberAnimation {
    required property var curve

    easing.type: Easing.BezierSpline
    easing.bezierCurve: [curve.x1, curve.y1, curve.x2, curve.y2, 1, 1]
}
