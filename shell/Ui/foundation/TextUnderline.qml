import QtQuick
import qs.Commons
import qs.Ui

// The underline of a one-line Label that acts as a link but is no
// LinkText, such as a word on the scrim that leaves the keyboard with its
// view: declared inside that label and handed it as `label`, it draws as
// a hovered link's does, its top Inset.underlineTop under the baseline,
// the font's line width thick, as wide as the text and in its
// colour. It draws only while
// its owner binds `visible` to the pointer being on the word, never at
// rest. Qt's own `font.underline` draws at the font's underline position,
// which a descender meets (Inset.underlineTop).
Rectangle {
    required property Label label

    visible: false
    y: label.baselineOffset + Inset.underlineTop(DescenderInk.depth(label.font), Screen.devicePixelRatio)
    width: label.contentWidth
    height: Inset.underlineWidth(metrics.lineWidth)
    color: label.color

    FontMetrics {
        id: metrics
        font: label.font
    }
}
