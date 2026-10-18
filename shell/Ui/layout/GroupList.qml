import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// A column of groups: each child is one group of lines, such as a key/value
// row with its hint, its action and its command, whose own lines sit
// `row.lineGap` apart. Groups sit `groupList.gap` apart with a hairline in
// `groupList.divider` in each gap, so the lines of one group read as one
// block and the next group starts clearly after it. The hairline is centred
// between what the eye sees: the lowest drawn pixel of the group above
// (Theme.inkBelow) and the highest of the group below (Theme.inkAbove),
// so a hint's leading, a label centred in a taller row or a button that
// fills its row moves it no closer to one group than to the other. A group
// that is a heading over a group list of its own, such as a Google Drive
// folder pair over its files, takes out of the gap above it how far its
// heading's ink starts below its rows' ink, so the heading stands as far
// from the group above as one row from the next. A child that is hidden or
// has no width or height takes no gap and no hairline, as a Column skips
// it. A group list inside another is one group of the outer one and
// divides its own groups the same way, so every group of a section is
// divided alike whatever holds it. `inkAbove()` and `inkBelow()` are where
// the first shown group's drawn content starts and the last one's ends, so
// an outer list and a section after the list measure from that ink.
Item {
    id: root

    default property alias groups: column.data

    function inkAbove() { return column.shown.length === 0 ? 0 : Theme.inkAbove(column.shown[0]); }
    function inkBelow() { return height - column.height + (column.shown.length === 0 ? 0 : Theme.inkBelow(column.shown[column.shown.length - 1])); }
    // How far a heading over a group list of its own starts its ink below
    // where its rows start theirs, in whole pixels; 0 for any other group.
    function headingLift(group) {
        if (!(group instanceof Column)) return 0;
        const rows = group.children.find(child => child instanceof GroupList && child.visible && child.width > 0 && child.height > 0);
        return rows === undefined ? 0 : Math.max(0, Math.round(Theme.inkAbove(group) - rows.inkAbove()));
    }
    // The y of each hairline, one per gap between two shown groups.
    readonly property var hairlines: column.shown.slice(1).map((child, i) => {
        const above = column.tops[i] + column.shown[i].height - Theme.inkBelow(column.shown[i]);
        return Math.round((above + column.tops[i + 1] + Theme.inkAbove(child) - Theme.divider.thickness) / 2);
    })

    // A Control sets its contentItem's width to its availableWidth, inside
    // its padding, each time its own size changes. Bound to the Control's
    // whole width, this list would hold a second width: its groups' heights
    // and so the Control's height follow the one, and the Control writes
    // the other while those bindings still run.
    // https://doc.qt.io/qt-6/qml-qtquick-controls-control.html#availableWidth-prop
    width: parent instanceof T.Control ? parent.availableWidth : parent ? parent.width : implicitWidth
    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    // The groups in order, as a Column lays out its children: only those
    // shown and sized, each gap set by the group under it.
    Item {
        id: column

        readonly property var shown: children.filter(child => child.visible && child.width > 0 && child.height > 0)
        readonly property var tops: {
            const out = [];
            let y = 0;
            shown.forEach((child, i) => {
                if (i > 0) y += Theme.groupList.gap - root.headingLift(child);
                out.push(y);
                y += child.height;
            });
            return out;
        }

        function place() { shown.forEach((child, i) => { child.y = tops[i]; }); }

        width: root.width
        implicitWidth: Math.max(0, ...shown.map(child => child.width))
        implicitHeight: shown.length === 0 ? 0 : tops[tops.length - 1] + shown[shown.length - 1].height
        onTopsChanged: place()
        Component.onCompleted: place()
    }

    Repeater {
        model: root.hairlines
        Divider {
            required property real modelData
            y: modelData
            width: root.width
            color: Theme.groupList.divider
        }
    }
}
