import QtQuick
import qs.Commons
import qs.Ui

// The selected card's name under a browser's rail, the theme and the
// wallpaper view alike. An empty name keeps its line: QQuickText lays an
// empty text out one line high, so a card with no name, or a filter no card
// matches, moves nothing.
Label {
    role: "display"
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    color: Theme.carousel.hintActive
}
