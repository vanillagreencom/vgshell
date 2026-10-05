import QtQuick
import qs.Ui

// The row side of ListCursor, declared inside a row of `qs.Ui`: while
// `holds` is true it hands `cursor` the row it is declared in. A hover on
// an enabled row that the cursor lets through puts the plate on the row
// and emits `pointed`, for a pick list to make the row its selection; the
// cursor also emits it to hand the selection back when the pointer leaves
// the list. With no cursor it does nothing, and the row draws its own
// highlight.
HoverHandler {
    id: root

    // The list's ListCursor. Typed as Item: a copy of a component loaded
    // from its file path, as the smoke's popup copies are, registers this
    // module's types again, and a typed property refuses a cursor of the
    // other registration.
    property Item cursor: null
    property bool holds: false

    signal pointed()

    enabled: cursor !== null
    // Whether a hover on the row may take the plate: a disabled row takes
    // none.
    readonly property bool takes: cursor !== null && parent.enabled

    function claim() { if (cursor !== null) cursor.followRow(root, holds); }
    onHoldsChanged: claim()
    onCursorChanged: if (holds) claim()
    Component.onCompleted: if (holds) claim()

    onPointChanged: {
        if (!hovered || !takes || !cursor.hoverTakes(point.scenePosition)) return;
        cursor.hover(root);
        pointed();
    }
}
