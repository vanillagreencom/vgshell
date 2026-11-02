import QtQuick
import QtQuick.Effects

// The text shadow a look draws under a line: a line's `layer.effect`, a
// shadow with no offset in `shadow`, the look's `{ color, opacity, blur }`,
// with `blur` the blur's reach in pixels. Qt draws the line's layer again
// only when the line changes, so a still line redraws no blur. shadowBlur 1
// is the full blur blurMax allows
// (doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html).
MultiEffect {
    required property var shadow

    shadowEnabled: true
    shadowColor: shadow.color
    shadowOpacity: shadow.opacity
    blurMax: shadow.blur
    shadowBlur: 1
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 0
}
