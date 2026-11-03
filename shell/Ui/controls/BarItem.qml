import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// One item of the bar: a workspace pill or a widget's button. It is
// `bar.item.height` tall and its content, `bar.item.paddingX` in from each
// side, is an optional icon `bar.item.icon` wide at full opacity or a
// spinner in its place, or a short `caption` word there instead, an
// optional `text`, and an optional second reading, `detail`, drawn in the
// `bar` role in `tone`, the same way in every widget. A state the widget
// holds, such as Stay awake, draws as `leadingIconName`, one more glyph
// before the icon or caption in the item's foreground, never a level
// colour, and it takes room in the row. A value at
// `textLevel` or `detailLevel` "warning" or "danger" draws in that state
// colour, and the icon or caption draws in the most severe level of the
// values shown and the count, so it turns red exactly when a value beside
// it or the count does. A `separator` draws flush between text and detail
// in `bar.item.separator`, never a state colour; without one the two keep
// the item gap. A reading that changes, `text` with `textSample` or
// `detail` with `detailSample`, is a `Reading` whose sample is the widest
// form it takes. The content holds the width it lays out to with every
// reading at its sample and draws right aligned in it, so spare room sits
// before the icon, the icon stays beside its number, and the item keeps
// its width as the reading changes. A reading without a sample holds no
// room. `stacked`, with both text and detail shown, draws the text over
// the detail on two short lines, `bar.stacked.size` text in
// `bar.stacked.lineHeight` boxes, in mixed case, since a reading carries a
// unit such as "MB/s" an uppercase role would change, and with no
// separator. With an icon, each line draws its own in place of the item's
// one icon: `iconName` before the text and `detailIconName` before the
// detail, `bar.stacked.icon` wide at the `bar.stacked.iconStroke` line, in
// that line's own level colour, `bar.item.gap` from its reading; a line
// whose icon name is empty draws none. With a caption, each line draws
// its own label in that place instead, `caption` before the text and
// `detailCaption` before the detail, at the stacked size in that line's
// own level colour, in one column as wide as the wider label, so both
// readings start at one edge. A spinner stays left of the two lines, which
// then draw neither. The lines left align in a block, and the held
// width is the wider line at its sample, so the room sits before the
// block and both lines fit inside the item. The item is as wide as its
// padding and what it draws, and reserves no room after it. The item is
// never narrower than it is tall, and an item that draws an icon alone is
// square, its icon centred.
//
// `count`, a whole number as text, is the one way a bar item shows a
// number count: Badge's unread count at its `corner` size, at the item's
// top-right corner, over the icon's corner, which reads "9+" above 9 and
// takes its fill from `countLevel` (Badge.qml). It takes no room in the
// row, so an item that draws an icon alone stays square and keeps its
// width as the count comes and goes; "" draws no badge. The tooltip and
// the item's accessible name leave the count out: a widget with a count
// names it in its `label` and `tooltip`.
//
// The tooltip reads `tooltip` as its title and
// `tooltipDetails` as its quieter detail lines. A page or file reference
// in either (PageReference) draws as a link, which the pointer and the keyboard reach (Tooltip.qml),
// and activating it emits `tooltipPageActivated` with its page and tab,
// which a bar widget hands to `frame.openPage`. `active` fills it with
// `bar.active`, as the focused workspace; otherwise a press fills it with
// `bar.item.pressed`, and hover draws no fill, so the bar stays still
// under a passing pointer. The template owns the click, hover and focus,
// and the ring shows for keyboard focus.
T.AbstractButton {
    id: root

    // A bar reading that changes: `sample` is the widest form it takes.
    // It draws at its own width; `room` is how much wider the sample lays
    // out in its own font, the room the row it sits in holds before its
    // start, so the reading's glyphs stay beside what precedes them. An
    // empty sample, or a hidden reading, holds nothing. An unshown Text
    // measures the sample, not TextMetrics: a Text's width counts a last
    // glyph's ink past its advance, which TextMetrics.advanceWidth leaves
    // out ("100%" in the bar role lays out 33.56 px wide against an advance
    // of 32.56 px, read under scripts/qml-unit.sh on 2026-10-08), so an
    // advance would hold a pixel less than the sample shown takes. A
    // `stacked` reading is one of two lines in the item: the bar role at
    // `bar.stacked.size`, centred in a box `bar.stacked.lineHeight` tall.
    // The box sets the line, not the Text's own height: a Text one line
    // tall is never shorter than its font's line box, 14 px for the 10 px
    // text in a 12 px line, read under scripts/qml-unit.sh on 2026-10-09.
    component Reading: Label {
        id: reading
        property string sample: ""
        property bool stacked: false
        readonly property real room: visible ? Math.max(0, sampleSize.implicitWidth - implicitWidth) : 0
        // The stacked size and line, null for one line.
        readonly property var stackedLine: stacked ? Theme.bar.stacked : null
        readonly property real size: stackedLine !== null ? stackedLine.size : typography.size
        role: "bar"
        font.pixelSize: size
        font.letterSpacing: typography.letterSpacing * size
        height: stackedLine !== null ? stackedLine.lineHeight : implicitHeight
        verticalAlignment: Text.AlignVCenter

        Text {
            id: sampleSize
            visible: false
            font: reading.font
            text: reading.sample
        }
    }

    // A stacked line's icon, centred in the line's box. A Row lays out
    // only visible children, so a hidden icon leaves no gap before its
    // value (tst_baritem.qml test_stacked_lines_draw_their_own_icons,
    // detail-without-icon, under scripts/qml-unit.sh on 2026-10-09).
    component LineIcon: Icon {
        size: Theme.bar.stacked.icon
        stroke: Theme.bar.stacked.iconStroke
        anchors.verticalCenter: parent.verticalCenter
    }

    readonly property real minimumWidth: Theme.control.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property string iconName: ""
    // A glyph of its own before the icon or caption, for a state the
    // widget holds, such as Stay awake: `bar.item.icon` wide, in the
    // item's foreground whatever level its values draw in, `iconGap` from
    // what follows. It takes room in the row; "" draws none.
    property string leadingIconName: ""
    // The detail line's icon in the stacked layout.
    property string detailIconName: ""
    // The second reading, beside the text or under it when stacked.
    property string detail: ""
    // The corner badge's whole number, "" for none.
    property string count: ""
    // The widest form of `text` and of `detail`, held by their Readings.
    property string textSample: ""
    property string detailSample: ""
    property string caption: ""
    // The detail line's label in the stacked layout.
    property string detailCaption: ""
    property string separator: ""
    // Draw text and detail on two lines; with one of them shown it is one.
    property bool stacked: false
    readonly property bool stackedShown: stacked && text !== "" && detail !== ""
    // Stacked lines draw their own labels with a caption, else their own
    // icons, unless a spinner stands left of them.
    readonly property bool lineIcons: stackedShown && caption === "" && !spinning
    readonly property bool lineCaptions: stackedShown && caption !== "" && !spinning
    // "normal", "warning" or "danger".
    property string textLevel: "normal"
    property string detailLevel: "normal"
    property string countLevel: "normal"
    property bool spinning: false
    property color spinnerColor: Theme.spinner.color
    property bool active: false
    property color tone: Theme.bar.foreground
    property string tooltip: ""
    property var tooltipDetails: []
    property bool focusPreview: false
    signal tooltipPageActivated(string page, string tab)
    // What a screen reader and a probe name the item: its text, or the
    // widget's name for an item that draws an icon alone.
    property string label: text
    readonly property color foreground: active ? Theme.bar.onActive : tone
    // The most severe level among the values and the count shown; an
    // unknown level ranks as normal.
    readonly property var levels: ["normal", "warning", "danger"]
    readonly property string level: levels[Math.max(0, text === "" ? 0 : levels.indexOf(textLevel),
        detail === "" ? 0 : levels.indexOf(detailLevel), count === "" ? 0 : levels.indexOf(countLevel))]
    function levelColor(value) {
        return value === "danger" ? Theme.color.danger : value === "warning" ? Theme.color.warning : foreground;
    }
    // Each value's colour, on one line or stacked.
    readonly property color textColor: levelColor(textLevel)
    readonly property color detailColor: levelColor(detailLevel)

    implicitWidth: Math.max(implicitHeight, Math.ceil(implicitContentWidth) + leftPadding + rightPadding)
    implicitHeight: Theme.bar.item.height
    readonly property bool iconOnly: text === "" && detail === "" && caption === ""
    leftPadding: iconOnly ? Math.floor((Theme.bar.item.height - Theme.bar.item.icon) / 2) : Theme.bar.item.paddingX
    rightPadding: leftPadding
    spacing: Theme.bar.item.iconGap
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    PointerCursor {}
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: label
    // The tooltip takes a key first, so a key on its current link opens the
    // link's page and does not click the item. Keys emits `pressed` only
    // for a key none of its own handlers took, and before the button reads
    // Space (tst_baritem.qml test_a_tooltip_link_opens_its_page_from_the_keys
    // under scripts/qml-unit.sh, Qt 6.11.2, on 2026-10-13).
    Keys.onReturnPressed: event => { if (!tip.takeKey(event)) KeyNavLogic.activate(root); }
    Keys.onEnterPressed: event => { if (!tip.takeKey(event)) KeyNavLogic.activate(root); }
    Keys.onPressed: event => { event.accepted = tip.takeKey(event); }

    contentItem: Item {
        id: content
        // The row's width with every reading at its sample; stacked, the
        // block's width with its wider line at its sample.
        readonly property real held: row.implicitWidth + textLabel.room + detailLabel.room
            + (stack.visible ? Math.max(textLine.implicitWidth + stackText.room, detailLine.implicitWidth + stackDetail.room) - stack.implicitWidth : 0)
        implicitWidth: held
        implicitHeight: row.implicitHeight
        // The stacked labels' one column.
        readonly property real captionWidth: Math.max(textCaption.implicitWidth, detailCaption.implicitWidth)

        // The held box centres in the content and the row ends at its
        // right edge, on a whole pixel.
        Row {
            id: row
            x: Math.round((content.width + content.held) / 2 - width)
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.spacing

            // Built only while named, so an item without one holds no
            // second Icon for a reader of its icon to find. The Loader
            // takes the Icon's size
            // (https://doc.qt.io/qt-6/qml-qtquick-loader.html#loader-sizing-behavior).
            Loader {
                objectName: "bar-item-leading"
                active: root.leadingIconName !== ""
                visible: active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: Icon {
                    name: root.leadingIconName
                    size: Theme.bar.item.icon
                    color: root.foreground
                }
            }
            Label {
                role: "bar"
                visible: root.caption !== "" && !root.spinning && !root.lineCaptions
                text: root.caption
                color: glyph.color
                y: topForCapCenter(row.height)
            }
            Item {
                visible: ((root.iconName !== "" && root.caption === "") || root.spinning) && !root.lineIcons
                width: Theme.bar.item.icon
                height: Theme.bar.item.icon
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    id: glyph
                    anchors.centerIn: parent
                    visible: !root.spinning
                    name: root.iconName
                    size: Theme.bar.item.icon
                    color: root.levelColor(root.level)
                }
                Spinner {
                    anchors.centerIn: parent
                    visible: root.spinning
                    size: Theme.bar.item.icon
                    color: root.spinnerColor
                }
            }
            Row {
                id: values
                visible: !root.stackedShown && (root.text !== "" || root.detail !== "")
                spacing: root.separator !== "" ? 0 : root.spacing
                Reading {
                    id: textLabel
                    sample: root.textSample
                    visible: root.text !== ""
                    text: root.text
                    color: root.textColor
                    y: topForCapCenter(row.height)
                }
                Label {
                    role: "bar"
                    visible: root.separator !== "" && root.text !== "" && root.detail !== ""
                    text: root.separator
                    color: Theme.bar.item.separator
                    y: topForCapCenter(row.height)
                }
                Reading {
                    id: detailLabel
                    sample: root.detailSample
                    visible: root.detail !== ""
                    text: root.detail
                    color: root.detailColor
                    y: topForCapCenter(row.height)
                }
            }
            Column {
                id: stack
                visible: root.stackedShown
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    id: textLine
                    spacing: Theme.bar.item.gap
                    LineIcon { visible: root.lineIcons && name !== ""; name: root.iconName; color: root.textColor }
                    Reading { id: textCaption; visible: root.lineCaptions; stacked: true; width: content.captionWidth; text: root.caption; color: root.textColor }
                    Reading { id: stackText; stacked: true; sample: root.textSample; text: root.text; color: root.textColor; font.capitalization: Font.MixedCase }
                }
                Row {
                    id: detailLine
                    spacing: Theme.bar.item.gap
                    LineIcon { visible: root.lineIcons && name !== ""; name: root.detailIconName; color: root.detailColor }
                    Reading { id: detailCaption; visible: root.lineCaptions; stacked: true; width: content.captionWidth; text: root.detailCaption; color: root.detailColor }
                    Reading { id: stackDetail; stacked: true; sample: root.detailSample; text: root.detail; color: root.detailColor; font.capitalization: Font.MixedCase }
                }
            }
        }
    }

    background: Rectangle {
        radius: Theme.bar.item.radius
        color: root.active ? Theme.bar.active : root.down ? Theme.bar.item.pressed : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
        // One ring at a time: while the tooltip's link is current the link
        // draws it, and a FocusRing with no target draws none.
        FocusRing { target: tip.currentLine === -1 ? root : null }
    }

    Tooltip {
        id: tip
        text: root.tooltip !== "" ? root.tooltip
            : root.iconOnly || root.tooltipDetails.length > 0 || (root.label !== root.text && root.label !== root.detail) ? root.label : ""
        details: root.tooltipDetails
        pageLinks: true
        onPageActivated: (page, tab) => root.tooltipPageActivated(page, tab)
    }

    // The corner count, over the content at the item's top-right corner,
    // built only while there is a count, so an item without one holds no
    // Badge for a reader of its icon or labels to find. The Loader takes
    // the Badge's size
    // (https://doc.qt.io/qt-6/qml-qtquick-loader.html#loader-sizing-behavior).
    Loader {
        id: badge
        objectName: "bar-item-count"
        active: root.count !== ""
        z: 2
        x: root.width - width
        y: 0
        sourceComponent: Badge {
            variant: "unread"
            size: "corner"
            level: root.countLevel
            text: root.count
        }
    }
}
