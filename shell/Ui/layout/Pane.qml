import QtQuick
import qs.Commons
import qs.Ui

// One inset box for a container: an optional title row, optional header
// slot, scrolling body and optional footer all start at the same content
// edge. A non-empty `title` draws in the container's title role and can
// put a feature switch at the row's end; plugins pass the switch's state
// and action, and the switch stays beside the Settings gear when one
// shows. A switch that controls less than the title names, such as Wi-Fi
// under Network, carries its `switchName` as a hint label at its left, so
// it does not read as switching off the whole feature. The header slot stays below that row, so a plugin can add a
// sentence without owning the dropdown title pattern. `titleContent` holds
// a title with inline controls; `subtitle` stays with that title before the
// shared title space. The scroll bar lives
// in the right inset strip, outside the body's content width, so content
// never moves when it overflows. The footer stays outside the scrolling
// body, so its actions stay in view while the body scrolls. While the body
// is scrolled, a divider runs under the header, and while more of it lies
// below the view, one runs over the footer; both span the box from the
// container's frame on one side to its frame on the other, meeting the
// border and never covering it. Each is the only line on its edge: the
// body's ScrollArea keeps its edge shade there but draws no hairline of
// its own, which would span the inset viewport alone and show as a second,
// shorter line. A pane without a header or footer leaves that edge's
// hairline to the ScrollArea. Inside a summoned plugin whose host names
// a Settings page (PluginSlot's `settingsPage`), the outermost pane draws
// a gear at the header's end that opens that page, and the header takes
// `headerWidth`, which leaves the gear its room. `padding`
// and `cornerRadius` default to the container class's tokens; a plugin that
// owns its look (design-system.md § Appearance) hands its own. The `overlay` class is a
// full-screen surface over a scrim, which draws no container and so has
// no corner for its content to clear. The viewport reaches the
// focus ring's room past the content's left, top and bottom edges, so a
// ring drawn around a row on an edge is never clipped.
Item {
    id: root

    property string container: "panel"
    property real padding: paddingOf(container)
    property real cornerRadius: radiusOf(container)
    property bool fitToContent: false
    property real maximumHeight: 0
    property real gap: container === "window" ? Theme.stack.section : Theme.stack.group
    property real bodySpacing: container === "window" ? Theme.stack.page : Theme.stack.group
    property string title: ""
    property string titleRole: container === "window" ? "windowTitle" : "h3"
    property int titleWrapMode: Text.NoWrap
    property alias titleContent: titleSlot.data
    property alias subtitle: subtitleColumn.data
    property bool switchShown: false
    property bool switchChecked: false
    property bool switchEnabled: true
    property string switchName: title
    // The width of a divider under the header while the body is scrolled,
    // and its colour.
    property real dividerWidth: Theme.divider.thickness
    property color dividerColor: Theme.divider.color
    // The width of the frame the container draws at each side, which a
    // divider meets.
    property real frameBorder: frameBorderOf(container)
    property alias header: headerSlot.data
    default property alias body: bodyColumn.data
    property alias footer: footerSlot.data
    signal switchToggled(bool checked)
    // The room a focus ring takes outside its row.
    readonly property real ringRoom: Theme.focusRing.width + Theme.focusRing.offset
    // The viewport's ring room and its scrollbar gutter must fit inside
    // the container, including when its requested padding is smaller.
    readonly property real contentInset: Math.max(clearingInset.inset, scroll.focusInset + Math.max(ringRoom, Theme.scrollArea.gutter))
    readonly property real contentWidth: Math.max(0, width - 2 * contentInset)
    // The nearest ancestor that declares `settingsPage`, the slot that hosts
    // this plugin, or null, as it is for a pane inside another pane, which
    // leaves the gear to the outer one.
    readonly property Item settingsHost: {
        for (let item = root.parent; item !== null; item = item.parent) {
            if (item.settingsHost !== undefined) return null;
            if (item.settingsPage !== undefined) return item;
        }
        return null;
    }
    readonly property bool showsSettings: settingsHost !== null && settingsHost.settingsPage !== ""
    // True while the SurfaceHeight card holding this pane grows toward its
    // content: the body is short only until the card lands, so it shows no
    // scroll bar or footer divider for that.
    readonly property bool cardGrowing: {
        for (let item = root.parent; item !== null; item = item.parent)
            if (item.surfaceGrowing !== undefined) return item.surfaceGrowing;
        return false;
    }
    readonly property real gearRoom: gear.item ? gear.item.width + Theme.stack.inline : 0
    readonly property Item headerSwitch: switchLoader.item
    readonly property bool hasTitle: title !== "" || titleSlot.children.some(child => child.visible)
    readonly property bool switchLabelShown: switchLoader.item !== null && switchName !== title
    readonly property real switchLabelRoom: switchLabelShown ? switchLabel.implicitWidth + Theme.stack.inline : 0
    readonly property real switchRoom: switchLoader.item ? switchLoader.item.width + Theme.stack.inline + switchLabelRoom : 0
    readonly property real titleRowHeight: hasTitle ? Math.max(title !== "" ? titleLabel.implicitHeight : 0, titleSlot.implicitHeight, switchLoader.item ? switchLoader.item.height : 0, gear.item ? gear.item.height : 0) : 0
    readonly property real subtitleHeight: subtitleSlot.implicitHeight
    readonly property real subtitleGap: titleRowHeight > 0 && subtitleHeight > 0 ? Theme.row.lineGap : 0
    readonly property real titleBlockHeight: titleRowHeight + subtitleGap + subtitleHeight
    readonly property real headerSlotImplicitHeight: headerSlot.children.length > 0 ? headerSlot.implicitHeight : 0
    readonly property real titleToHeaderGap: hasTitle && titleBlockHeight > 0 && headerSlotImplicitHeight > 0 ? Theme.stack.titleSpace : 0
    // The header's width: the content width less the gear and its gap
    // while the gear shows.
    readonly property real headerWidth: Math.max(0, contentWidth - gearRoom)
    readonly property real bodyContentHeight: bodyColumn.implicitHeight
    readonly property real headerHeight: hasTitle ? titleBlockHeight + titleToHeaderGap + headerSlotImplicitHeight : Math.max(subtitleHeight + (subtitleHeight > 0 && headerSlotImplicitHeight > 0 ? gap : 0) + headerSlotImplicitHeight, gear.item ? gear.item.height : 0)
    readonly property real footerHeight: footerSlot.children.length > 0 ? footerSlot.implicitHeight : 0
    readonly property bool contentBelowHeader: bodyContentHeight > 0 || footerHeight > 0
    readonly property real headerBodyGap: hasTitle && headerSlotImplicitHeight === 0 ? Theme.stack.titleSpace : gap
    // A sticky bar keeps the container inset between its content and its
    // line. Leave the viewport's ring room on the other side of that line.
    readonly property real stickyGap: contentInset + dividerWidth + ringRoom
    readonly property real bodyGap: hasTitle && headerSlotImplicitHeight === 0 ? headerBodyGap : Math.max(headerBodyGap, stickyGap)
    readonly property real headerGap: headerHeight > 0 && contentBelowHeader ? (bodyContentHeight > 0 ? bodyGap : headerBodyGap) : 0
    readonly property real footerGap: footerHeight > 0 && bodyContentHeight > 0 ? Math.max(gap, stickyGap) : 0
    readonly property real uncappedHeight: 2 * contentInset + headerHeight + headerGap + bodyContentHeight + footerGap + footerHeight
    readonly property real cappedHeight: maximumHeight > 0 ? Math.min(uncappedHeight, maximumHeight) : uncappedHeight
    // The height the box lays out in: a fitted pane's capped height, or
    // less when its host gives it less, such as a popup held inside a
    // short output; the body then scrolls and the footer stays inside.
    readonly property real boxHeight: fitToContent ? (height > 0 ? Math.min(cappedHeight, height) : cappedHeight) : height
    // The height a body with content shows at the pane's limit: a fitted
    // pane's `maximumHeight`, unbounded without one, else its height, less
    // the insets, the header, the footer and the gaps a header and a
    // footer keep from a body. It reads no height of the body, so a body
    // sized from it, such as a rail that shrinks to fit, fills the pane to
    // its cap without a binding loop and without overflowing.
    readonly property real bodyRoom: {
        const limit = fitToContent ? (maximumHeight > 0 ? maximumHeight : Infinity) : height;
        return Math.max(0, limit - 2 * contentInset - headerHeight - footerHeight - (headerHeight > 0 ? bodyGap : 0) - (footerHeight > 0 ? Math.max(gap, stickyGap) : 0));
    }
    readonly property alias scrollArea: scroll

    // A slot's width is its widest child's implicit width, never the
    // children's laid-out boxes: read through `childrenRect`, a header of
    // implicit width and a footer bound to `contentWidth` each moved the
    // other's box, which fed `implicitWidth` back into itself.
    // Qt clears the Pane id before removing the slot's children, as the
    // assembled System check reaches. Keep the binding in the slot so
    // child removal does not call the destroyed Pane.
    component Slot: Item {
        property Item contentItem: this
        implicitHeight: contentItem === null ? 0 : (contentItem === this ? childrenRect.height : contentItem.implicitHeight)
        implicitWidth: {
            if (contentItem === null) return 0;
            let widest = 0;
            for (const child of contentItem.children) widest = Math.max(widest, child.implicitWidth);
            return widest;
        }
    }

    implicitWidth: Math.max(hasTitle ? Math.max(titleLabel.implicitWidth, titleSlot.implicitWidth, subtitleSlot.implicitWidth) + switchRoom + gearRoom : 0, headerSlot.implicitWidth > 0 ? headerSlot.implicitWidth + gearRoom : 0, bodyColumn.implicitWidth, footerSlot.implicitWidth) + 2 * contentInset
    implicitHeight: fitToContent ? cappedHeight : uncappedHeight

    ClearingInset {
        id: clearingInset
        pad: root.padding
        radius: root.cornerRadius
        width: root.width
        height: root.boxHeight
        top: root.padding
    }

    function paddingOf(name) {
        switch (name) {
        case "dialog": return Theme.dialog.padding;
        case "popover": return Theme.popover.padding;
        case "panel": return Theme.surface.padding;
        case "window": return Theme.inset.window;
        case "overlay": return Theme.inset.overlay;
        }
        console.error("Pane: no padding rule named " + JSON.stringify(name));
        return Theme.surface.padding;
    }

    // A dialog and a popover draw their outline `border.thin` wide, a panel
    // its Surface `surface.border` wide; a window's frame is Hyprland's, and
    // an overlay draws none.
    function frameBorderOf(name) {
        switch (name) {
        case "dialog":
        case "popover": return Theme.border.thin;
        case "panel": return Theme.surface.border;
        case "overlay":
        case "window": return 0;
        }
        console.error("Pane: no frame border rule named " + JSON.stringify(name));
        return Theme.surface.border;
    }

    function radiusOf(name) {
        switch (name) {
        case "dialog": return Theme.dialog.radius;
        case "popover": return Theme.popover.radius;
        case "window":
        case "panel": return Theme.surface.radius;
        case "overlay": return 0;
        }
        console.error("Pane: no radius rule named " + JSON.stringify(name));
        return Theme.surface.radius;
    }

    function switchX(item) {
        return root.contentWidth - root.gearRoom - (item ? item.width : 0);
    }

    Item {
        id: titleRow
        x: root.contentInset
        y: root.contentInset
        width: root.contentWidth
        height: root.titleBlockHeight
        visible: root.hasTitle || titleSlot.children.length > 0 || subtitleSlot.children.length > 0

        Label {
            id: titleLabel
            role: root.titleRole
            visible: root.title !== ""
            wrapMode: root.titleWrapMode
            text: root.title
            width: Math.max(0, parent.width - root.switchRoom - root.gearRoom)
            y: root.titleWrapMode === Text.NoWrap ? topForCapCenter(root.titleRowHeight) : 0
            elide: Text.ElideRight
        }

        Loader {
            id: switchLoader
            x: root.switchX(item)
            y: item ? Math.round((root.titleRowHeight - item.height) / 2) : 0
            active: root.hasTitle && root.switchShown
            sourceComponent: Switch {
                size: "sm"
                Accessible.name: root.switchName
                checked: root.switchChecked
                enabled: root.switchEnabled
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.switchChecked);
                    root.switchToggled(wanted);
                }
            }
        }

        // The switch's accessible name already says this, so a screen
        // reader skips the label rather than read the name twice.
        Label {
            id: switchLabel
            role: "hint"
            text: root.switchName
            visible: root.switchLabelShown
            x: switchLoader.x - Theme.stack.inline - width
            y: topForCapCenter(root.titleRowHeight)
            Accessible.ignored: true
        }

        // Implicit sizes flow from children; widths flow from the pane:
        // https://quickshell.org/docs/v0.3.1/guide/size-position/.
        Slot {
            id: titleSlot
            width: parent.width - root.gearRoom
            height: root.titleRowHeight
        }

        Slot {
            id: subtitleSlot
            y: root.titleRowHeight + root.subtitleGap
            width: parent.width - root.gearRoom
            height: implicitHeight
            contentItem: subtitleColumn
            Column {
                id: subtitleColumn
                width: parent.width
                spacing: Theme.row.lineGap
            }
        }
    }

    // Built only while it shows, so a pane without a Settings page holds no
    // gear. Declared after the title row switch, so Tab reaches the switch
    // before the gear, and before the body.
    // `x` reads the button's width, not the Loader's: a move resizes the
    // Loader to its item, which fed its own `width` back into `x`.
    Loader {
        id: gear
        x: root.contentInset + root.contentWidth - (item ? item.width : 0)
        y: root.contentInset + (root.hasTitle && item ? Math.round((root.titleRowHeight - item.height) / 2) : 0)
        active: root.showsSettings
        sourceComponent: IconButton {
            size: "sm"
            iconName: "settings"
            label: "Settings"
            onClicked: root.settingsHost.openSettingsPage()
        }
    }

    Slot {
        id: headerSlot
        x: root.contentInset
        y: root.contentInset + root.titleBlockHeight + root.titleToHeaderGap + (!root.hasTitle && root.subtitleHeight > 0 && root.headerSlotImplicitHeight > 0 ? root.gap : 0)
        width: root.headerWidth
        height: root.hasTitle ? root.headerSlotImplicitHeight : root.headerHeight
    }

    // ScrollArea adds its own side inset for keyboard scrolling. Give that
    // inset room outside the body's width so the body keeps the header's
    // edges and the bar stays in the container's right inset strip.
    ScrollArea {
        id: scroll
        x: root.contentInset - root.ringRoom - focusInset
        y: root.contentInset + root.headerHeight + root.headerGap - root.ringRoom
        width: Math.max(0, root.width - root.contentInset + root.ringRoom + focusInset)
        // A container inset narrower than the bar's gutter still leaves the
        // gutter, so the bar never covers the content.
        rightInset: Math.max(root.contentInset - focusInset, Theme.scrollArea.gutter)
        barHeld: root.cardGrowing
        cueLineAbove: root.headerHeight <= 0
        cueLineBelow: root.footerHeight <= 0
        contentPadding: root.ringRoom
        height: root.ringRoom * 2 + Math.max(0, root.boxHeight - 2 * root.contentInset - root.headerHeight - root.headerGap - root.footerGap - root.footerHeight)

        Item {
            width: scroll.contentWidth
            implicitHeight: bodyColumn.implicitHeight + 2 * root.ringRoom
            height: implicitHeight

            Column {
                id: bodyColumn
                x: root.ringRoom
                y: root.ringRoom
                width: parent.width - root.ringRoom
                spacing: root.bodySpacing
            }
        }
    }

    Slot {
        id: footerSlot
        x: root.contentInset
        y: scroll.y + scroll.height - root.ringRoom + root.footerGap
        width: root.contentWidth
        height: root.footerHeight
    }

    // Both dividers share one geometry: from the frame's border on one
    // side to the border on the other.
    component Rule: Rectangle {
        x: root.frameBorder
        width: Math.max(0, root.width - 2 * root.frameBorder)
        height: root.dividerWidth
        color: root.dividerColor
    }

    Rule {
        id: headerDivider
        y: root.contentInset + root.headerHeight + Math.min(root.contentInset, root.headerGap - root.ringRoom - height)
        visible: root.headerHeight > 0 && scroll.contentY > 0
    }

    Rule {
        id: footerDivider
        y: footerSlot.y - root.contentInset - height
        visible: root.footerHeight > 0 && !root.cardGrowing && scroll.contentY + scroll.height < scroll.contentHeight - 1
    }
}
