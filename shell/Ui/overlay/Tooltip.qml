import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui

// A tooltip for `anchorItem`, the item it is declared in unless set, as a
// control's helper sets it on the control: it draws one title line and
// optional quieter detail lines. A detail is a string line, or `{ label,
// value }` for a count row whose value column aligns with the other count
// rows. After the theme's delay with the pointer resting on the item or
// after keyboard focus reaches it, the tooltip opens in its own surface
// on the item's `side`, "below" (the default), "right", "belowStart",
// under the item from its start edge, or "clear", beside the item where it
// covers no text, image or Tab stop of its window (`placed`), and takes no
// focus. It closes when the pointer leaves and focus leaves, on a press on
// the item, when the item hides, and it does
// not open while another overlay is open. After a press it stays closed
// until the pointer leaves the item, so it never covers what the press
// opened. It opens beside `box`, a rectangle in the item's coordinates,
// the item's own box unless set, and wraps its text past `maxWidth`,
// `tooltip.maxWidth` unless set, and is no narrower than `minWidth`, so a
// caller can have it span a row. Under its item from the start edge it
// is a band of help under a form row: it draws `band`, a neutral plate
// with no outline, since an input shows by its outline and a band with
// one read as an empty input. A title or a plain detail line that holds a
// page or file reference (PageReference.js) draws the reference's words
// alone. With `pageLinks` set, such a line whose reference names a page
// or a file draws as a link (LinkText), and a click on it, or Enter,
// Return or Space on it, emits `pageActivated` with that page and tab, a
// file reference's being `file:<path>` and "", and closes the tooltip;
// the owner opens it through the core's reference route.
// The pointer reaches a link across the gap: when it leaves the item, a
// tooltip with a link stays for `tooltip.delay`, stays while the pointer
// is on it, and closes that long after the pointer left it too. The
// tooltip never takes the keyboard. The item hands each key it gets to
// `takeKey` first, which answers whether the tooltip took it: Tab moves
// to the next link and draws its focus ring, and past the last one goes
// on to the next item; Shift+Tab moves back; Escape closes the tooltip,
// which opens again only after the pointer and the focus have both left
// the item. A tooltip with no link takes no key. Under a last line that
// is a link, the tooltip is as much taller as keeps that link's ring
// `focusRing.offset` clear of its border. The declaring item is an
// invisible, sizeless member of its parent. Its hover and press handlers
// are made on the anchor once, when it completes, so a later anchor is
// not followed.
Item {
    id: root

    property string text: ""
    property var details: []
    // Draw a page reference as a link; the owner opens the page.
    property bool pageLinks: false
    signal pageActivated(string page, string tab)
    // An item with a label under it opens its tooltip to the right, so the
    // tooltip never covers that label.
    property string side: "below"
    property rect box: Qt.rect(0, 0, anchorItem === null ? 0 : anchorItem.width, anchorItem === null ? 0 : anchorItem.height)
    property real maxWidth: Theme.tooltip.maxWidth
    property real minWidth: 0
    // A fill lifted off the surface it lies on, its border in that fill.
    readonly property var band: ({ background: Theme.color.surfaceHover, border: Theme.color.surfaceHover, radius: Theme.tooltip.radius })
    readonly property int edge: edgeFor(side)
    // A corner of the box with the gravity of the opposite corner starts
    // the popup on that corner; only opposing edges are refused.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/PopupAnchor/
    readonly property int anchorEdges: side === "belowStart" ? Edges.Bottom | Edges.Left : edge
    readonly property int anchorGravity: side === "belowStart" || side === "clear" ? Edges.Bottom | Edges.Right : edge
    // What a "clear" tooltip's window draws, read once as it opens
    // (`survey`), so no binding reads the item tree; null while closed.
    property var scene: null
    // The box a "clear" tooltip takes, in the item's coordinates; it moves
    // with the item, and the window is read again only at the next open.
    readonly property rect placed: side === "clear" && scene !== null && popup.item !== null ? placedOn(scene, popup.item.implicitWidth, popup.item.implicitHeight) : Qt.rect(0, 0, 0, 0)
    readonly property rect anchorRect: side === "clear" ? placed : box
    // A "clear" tooltip is no wider than the box its window's content spans.
    readonly property real clearWidth: scene === null ? Infinity : scene.content.width
    property bool shown: false
    readonly property bool opened: popup.item !== null && popup.item.visible
    readonly property var tracker: popup.item === null ? null : popup.item.tracker
    property Item anchorItem: parent

    // The handlers live on the anchor, made once it is known: a handler
    // declared with a parent binding crashes the engine while the parent
    // is still null.
    property HoverHandler hover: null
    property TapHandler press: null
    // A press on the item since the pointer last entered it.
    property bool pressedHere: false
    readonly property Component hoverComponent: Component { HoverHandler { onHoveredChanged: if (!hovered) root.pressedHere = false } }
    // pointer-cursor-exempt: it watches a press on the anchor to close the tooltip; the anchor's own control owns the cursor
    // keyboard-path: the anchor's focus opens the tooltip and focus leaving closes it
    readonly property Component pressComponent: Component { TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onPressedChanged: if (pressed) root.pressedHere = true } }
    readonly property bool focusResting: anchorItem !== null && ("visualFocus" in anchorItem) && anchorItem.visualFocus === true
    readonly property bool live: anchorItem !== null && anchorItem.visible && anchorItem.enabled && text !== ""
    readonly property bool unpressed: !(press !== null && press.pressed) && !pressedHere
    readonly property bool pointerResting: hover !== null && hover.hovered && unpressed
    readonly property bool resting: live && (pointerResting || focusResting)

    // The lines that draw as links, the title as 0 and detail i as i + 1,
    // in the order Tab takes them.
    readonly property var links: [text].concat(Array.isArray(details) ? details : []).map((line, at) => linked(line) ? at : -1).filter(at => at !== -1)
    // The place in `links` of the link the keyboard is on, -1 for none.
    property int current: -1
    readonly property int currentLine: current >= 0 && current < links.length ? links[current] : -1
    // The line and the target of the link the keyboard is on, by which a
    // refresh of the lines finds that link again.
    property var held: null
    // The pointer may cross to a link and rest on it.
    readonly property bool reachable: live && unpressed && links.length > 0
    readonly property bool reached: reachable && popup.item !== null && popup.item.pointerOver
    // The pointer on the item or the popup, as `settle` last read it.
    property bool pointerWasOn: false

    visible: false

    // A line that draws as a link, in the place and the look of the Label
    // that draws it as words. `current` draws its focus ring.
    component LinkLine: Loader {
        id: slot

        property string line: ""
        property string role: "body"
        property color tint
        property int wrapMode: Text.Wrap
        property bool current: false
        // How far the link's ring reaches under this line.
        readonly property real ringBelow: item !== null ? item.ringBelow : 0
        signal pageActivated(string page, string tab)

        width: parent.width
        sourceComponent: LinkText {
            objectName: "tooltipLink"
            text: slot.line
            role: slot.role
            color: slot.tint
            wrapMode: slot.wrapMode
            focusPreview: slot.current
            onPageActivated: (page, tab) => slot.pageActivated(page, tab)
        }
    }

    function linked(line) {
        return pageLinks && typeof line === "string" && PageReference.parse(line).page !== "";
    }

    function lineAt(at) { return at === 0 ? text : details[at - 1]; }

    function linkAt(at) {
        const reference = PageReference.parse(lineAt(at));
        return { line: at, page: reference.page, tab: reference.tab };
    }

    // The place in `links` of the held link, -1 once its line links
    // elsewhere or is no link.
    function heldPlace() {
        const place = held === null ? -1 : links.indexOf(held.line);
        if (place === -1) return -1;
        const link = linkAt(held.line);
        return link.page === held.page && link.tab === held.tab ? place : -1;
    }

    // Start the grace when the pointer leaves the item or the popup, end it
    // when the pointer is on either, and close once nothing holds the
    // tooltip open. Several bindings change on one pointer move, in no
    // fixed order, so every one of them settles here from the state it
    // finds.
    function settle() {
        const pointerOn = pointerResting || reached;
        if (pointerOn || !reachable) grace.stop();
        else if (pointerWasOn && shown) grace.restart();
        pointerWasOn = pointerOn;
        if (!resting && !reached && !grace.running) shown = false;
    }

    function activate(page, tab) {
        pageActivated(page, tab);
        closing.restart();
    }

    // Whether the tooltip took the key the item got.
    function takeKey(event) {
        if (!shown || links.length === 0) return false;
        if (event.key === Qt.Key_Escape) {
            shown = false;
            return true;
        }
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false;
        if (event.key === Qt.Key_Tab) {
            current = current + 1 < links.length ? current + 1 : -1;
            return current !== -1;
        }
        if (event.key === Qt.Key_Backtab) {
            if (current === -1) return false;
            current -= 1;
            return true;
        }
        if (currentLine !== -1 && [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].indexOf(event.key) !== -1) {
            const reference = PageReference.parse(lineAt(currentLine));
            activate(reference.page, reference.tab);
            return true;
        }
        return false;
    }

    function edgeFor(name) {
        if (name === "below" || name === "belowStart") return Edges.Bottom;
        if (name === "right") return Edges.Right;
        if (name === "clear") return Edges.Top | Edges.Left;
        throw new Error("Tooltip: side=" + JSON.stringify(name) + " unexpected");
    }

    // The overlap of two boxes, null where they share no area.
    function cut(a, b) {
        const x = Math.max(a.x, b.x), y = Math.max(a.y, b.y);
        const width = Math.min(a.x + a.width, b.x + b.width) - x;
        const height = Math.min(a.y + a.height, b.y + b.height) - y;
        return width > 0 && height > 0 ? { x: x, y: y, width: width, height: height } : null;
    }

    function covered(a, b) {
        const both = cut(a, b);
        return both === null ? 0 : both.width * both.height;
    }

    // What a drawn item is to a "clear" tooltip: a Tab stop is a
    // "control", a Text, TextInput or TextEdit a "text" ("repeat" when
    // it declares repeatsReason), an Image or an
    // Icon of this module an "image"; anything else, another Shape such as
    // a card's background too, draws no obstacle of its own. A Qt Quick
    // Controls control sets activeFocusOnTab from its focusPolicy: a
    // qml-unit run of tst_reasontip.qml read it true on Button and
    // IconButton (2026-10-13).
    function obstacleKind(item) {
        if (item.activeFocusOnTab === true) return "control";
        if (typeof item.text === "string" && item.contentWidth !== undefined && item.font !== undefined) return item.repeatsReason === true ? "repeat" : "text";
        if (item.sourceSize !== undefined) return "image";
        if (Array.isArray(item.painted) && item.stroke !== undefined) return "image";
        return "";
    }

    // The box `item` draws in `view`'s coordinates: a text's words where
    // its alignment puts them, since the room after them is free, an
    // Icon's ink (`painted`, [left, top, right, bottom]), else the item's
    // box.
    function drawnBox(item, kind, view) {
        if (kind === "image" && Array.isArray(item.painted)) {
            const ink = item.painted;
            return item.mapToItem(view, ink[0], ink[1], ink[2] - ink[0], ink[3] - ink[1]);
        }
        if (kind !== "text" && kind !== "repeat") return item.mapToItem(view, 0, 0, item.width, item.height);
        const roomX = item.width - item.leftPadding - item.rightPadding;
        const roomY = item.height - item.topPadding - item.bottomPadding;
        const across = item.effectiveHorizontalAlignment;
        const along = item.verticalAlignment;
        const x = item.leftPadding + (across === Text.AlignRight ? roomX - item.contentWidth : across === Text.AlignHCenter ? (roomX - item.contentWidth) / 2 : 0);
        const y = item.topPadding + (along === Text.AlignBottom ? roomY - item.contentHeight : along === Text.AlignVCenter ? (roomY - item.contentHeight) / 2 : 0);
        return item.mapToItem(view, x, y, item.contentWidth, item.contentHeight);
    }

    // What the item's window draws, in its content item's coordinates:
    // `obstacles`, { x, y, width, height, control } for each drawn text,
    // image and Tab stop, cut by every clipping item that holds it;
    // `anchor`, the box the places keep clear of, the item's `box` and,
    // for an item that lies in a control as an unlock mark lies in its
    // toggle, the nearest such control, which the tooltip explains too;
    // `origin`, the item's own corner; and `content`, the box the
    // obstacles and that anchor span inside the window, on whole pixels. The item and all it holds, an unlock mark
    // too, are no obstacle, and an item that holds the item, a Tab stop
    // too, is read into. It surveys before the popup is built, then finds
    // the covered repeat text when the popup opens at its final size.
    function survey(place) {
        const view = anchorItem.Window.contentItem;
        if (view === null) throw new Error("Tooltip: anchor=" + anchorItem + " has no window to place a clear tooltip in");
        const holders = [];
        for (let at = anchorItem.parent; at !== null; at = at.parent) holders.push(at);
        const obstacles = [], repeats = [];
        let coveredRepeat = null;
        const walk = (item, held) => {
            if (item === anchorItem || !item.visible || item.opacity <= 0) return;
            const kind = holders.indexOf(item) === -1 ? obstacleKind(item) : "";
            if (kind !== "") {
                const drawn = cut(drawnBox(item, kind, view), held);
                if (kind === "repeat" && drawn !== null && place !== undefined && covered(place, drawn) > 0) coveredRepeat = item;
                if (drawn !== null) (kind === "repeat" ? repeats : obstacles).push({ x: drawn.x, y: drawn.y, width: drawn.width, height: drawn.height, control: kind === "control" });
                return;
            }
            const inner = item.clip ? cut(item.mapToItem(view, 0, 0, item.width, item.height), held) : held;
            if (inner === null) return;
            for (const child of item.children) walk(child, inner);
        };
        const whole = { x: 0, y: 0, width: view.width, height: view.height };
        walk(view, whole);
        const mapped = anchorItem.mapToItem(view, box.x, box.y, box.width, box.height);
        const owner = holders.find(item => item.activeFocusOnTab === true);
        const owned = owner === undefined ? mapped : owner.mapToItem(view, 0, 0, owner.width, owner.height);
        const anchor = {
            x: Math.min(mapped.x, owned.x), y: Math.min(mapped.y, owned.y),
            width: Math.max(mapped.x + mapped.width, owned.x + owned.width) - Math.min(mapped.x, owned.x),
            height: Math.max(mapped.y + mapped.height, owned.y + owned.height) - Math.min(mapped.y, owned.y)
        };
        const span = obstacles.concat(repeats, [anchor]).reduce((all, each) => ({
            x: Math.min(all.x, each.x), y: Math.min(all.y, each.y),
            right: Math.max(all.right, each.x + each.width), bottom: Math.max(all.bottom, each.y + each.height)
        }), { x: Infinity, y: Infinity, right: -Infinity, bottom: -Infinity });
        const left = Math.ceil(Math.max(span.x, 0)), top = Math.ceil(Math.max(span.y, 0));
        const right = Math.floor(Math.min(span.right, whole.width)), bottom = Math.floor(Math.min(span.bottom, whole.height));
        const corner = anchorItem.mapToItem(view, 0, 0);
        return {
            obstacles: obstacles,
            repeats: repeats,
            covered: coveredRepeat,
            anchor: anchor,
            origin: { x: corner.x, y: corner.y },
            content: { x: left, y: top, width: Math.max(0, right - left), height: Math.max(0, bottom - top) }
        };
    }

    // The box, in the window's content item coordinates, that a "clear"
    // tooltip `width` by `height` takes in `scene` (survey). The places
    // lie `gap` from the item, below, above, right and left in that order,
    // each centred on the item, then on its start and on its end edge,
    // held inside `content`; none overlaps the item. The first place by
    // [outside content, covers a Tab stop, the obstacle area it covers]
    // plus each repeat text's rows, end and start aligned to the anchor,
    // then centred on the text. The first
    // free place wins, else the place that covers the least,
    // one that stays inside the content and covers no Tab stop first.
    function clearPlace(scene, width, height, gap) {
        const a = scene.anchor, room = scene.content;
        const w = Math.ceil(width), h = Math.ceil(height);
        const hold = (at, low, size, span) => Math.max(low, Math.min(Math.round(at), low + span - size));
        const across = [a.x + (a.width - w) / 2, a.x, a.x + a.width - w].map(x => hold(x, room.x, w, room.width));
        const along = [a.y + (a.height - h) / 2, a.y, a.y + a.height - h].map(y => hold(y, room.y, h, room.height));
        const places = [];
        for (const y of [Math.ceil(a.y + a.height + gap), Math.floor(a.y - gap - h)])
            for (const x of across) places.push({ x: x, y: y, width: w, height: h });
        for (const x of [Math.ceil(a.x + a.width + gap), Math.floor(a.x - gap - w)])
            for (const y of along) places.push({ x: x, y: y, width: w, height: h });
        // On repeated text's rows, stay under the control before moving away.
        for (const repeat of scene.repeats) {
            const xs = [across[2], across[1], hold(repeat.x + (repeat.width - w) / 2, room.x, w, room.width)];
            for (const x of xs) {
                const place = { x: x, y: hold(repeat.y + (repeat.height - h) / 2, room.y, h, room.height), width: w, height: h };
                if (covered(place, a) === 0) places.push(place);
            }
        }
        const rank = place => [
            covered(place, room) === w * h ? 0 : 1,
            scene.obstacles.some(each => each.control && covered(place, each) > 0) ? 1 : 0,
            scene.obstacles.reduce((sum, each) => sum + covered(place, each), 0)
        ];
        const first = (one, other) => {
            for (let i = 0; i < one.length; i++) if (one[i] !== other[i]) return one[i] < other[i];
            return false;
        };
        let best = places[0], bestRank = rank(best);
        for (const place of places.slice(1)) {
            const placeRank = rank(place);
            if (first(placeRank, bestRank)) { best = place; bestRank = placeRank; }
        }
        return best;
    }

    // The place `clearPlace` picks, in the item's coordinates.
    function placedOn(scene, width, height) {
        const box = clearPlace(scene, width, height, Theme.tooltip.gap);
        return Qt.rect(box.x - scene.origin.x, box.y - scene.origin.y, box.width, box.height);
    }

    Component.onCompleted: {
        if (anchorItem === null) return;
        hover = hoverComponent.createObject(anchorItem);
        press = pressComponent.createObject(anchorItem);
    }

    onRestingChanged: {
        if (resting) delay.restart();
        else delay.stop();
        settle();
    }
    onPointerRestingChanged: settle()
    onReachableChanged: settle()
    onReachedChanged: settle()
    onShownChanged: if (!shown) {
        current = -1;
        scene = null;
    }
    function publishCoverage() {
        if (side !== "clear") return;
        OverlayState.coveredReason = opened && scene !== null ? survey({ x: placed.x + scene.origin.x, y: placed.y + scene.origin.y, width: placed.width, height: placed.height }).covered : null;
    }
    onOpenedChanged: publishCoverage()
    onPlacedChanged: if (opened) publishCoverage()
    onCurrentChanged: held = current === -1 ? null : linkAt(links[current])
    // Every assign of the text or the details makes new `links`, the same
    // lines included, so the current link is kept by what it holds.
    onLinksChanged: current = heldPlace()

    Timer {
        id: delay
        interval: Theme.tooltip.delay
        // The window is read before the popup is built, so the popup is
        // built at the width that content box allows.
        onTriggered: if (root.resting && OverlayState.open === 0) {
            if (root.side === "clear") root.scene = root.survey();
            root.shown = true;
        }
    }

    // How long the pointer may take from the item to a link and back.
    Timer {
        id: grace
        interval: Theme.tooltip.delay
        onTriggered: root.settle()
    }

    // An activation closes the tooltip once its handler has returned: a
    // click's handler runs inside the popup the close destroys.
    Timer {
        id: closing
        interval: 0
        onTriggered: root.shown = false
    }

    // Another overlay opening closes a tooltip already shown.
    Connections {
        target: OverlayState
        function onOpenChanged() { if (OverlayState.open > 0) root.shown = false; }
    }

    // LazyLoader owns its item and destroys it when active drops. A
    // tooltip has no window or content tree until its delay has elapsed.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/LazyLoader/
    LazyLoader {
        id: popup
        active: root.shown

        PopupWindow {
            id: window

            anchor.item: root.anchorItem
            anchor.rect.x: root.anchorRect.x
            anchor.rect.y: root.anchorRect.y
            anchor.rect.width: root.anchorRect.width
            anchor.rect.height: root.anchorRect.height
            // A negative margin grows the anchor rect past that edge, so the
            // popup opens the gap away from the item.
            anchor.edges: root.anchorEdges
            anchor.gravity: root.anchorGravity
            anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
            anchor.margins.bottom: root.edge === Edges.Bottom ? -Theme.tooltip.gap : 0
            anchor.margins.right: root.edge === Edges.Right ? -Theme.tooltip.gap : 0
            // No grab: Quickshell makes this a Qt ToolTip, which an outside
            // click leaves open; grabFocus true is a Popup with an xdg_popup
            // grab the compositor dismisses on a click outside.
            grabFocus: false
            visible: root.shown
            readonly property AnchorTracker tracker: AnchorTracker { popup: window; anchor: root.anchorItem }
            readonly property bool pointerOver: over.hovered
            color: "transparent"
            // One line up to `maxWidth`, then title and plain details
            // wrap; never wider than the output less its gutters, nor,
            // when "clear", than its window's content.
            readonly property real paddedWidth: Math.min(Math.max(root.minWidth, content.implicitWidth + 2 * Theme.tooltip.paddingX), OverlayState.widthFor(root.anchorItem, Math.min(root.maxWidth + 2 * Theme.tooltip.paddingX, root.clearWidth)))
            // The room under the content: the padding, or what the last
            // line's link ring needs to stand clear of the border.
            readonly property real paddingBelow: Math.max(Theme.tooltip.paddingY, content.ringBelow + Theme.focusRing.offset + Theme.surface.border)
            implicitWidth: Math.max(1, paddedWidth)
            implicitHeight: Math.max(1, content.implicitHeight + Theme.tooltip.paddingY + paddingBelow)

            // Under a rounded theme the text sits in from the sides until it
            // clears the drawn corner.
            ClearingInset {
                id: sideInset
                pad: Theme.tooltip.paddingX
                radius: Theme.tooltip.radius
                width: window.paddedWidth
                height: content.implicitHeight + Theme.tooltip.paddingY + window.paddingBelow
                top: Theme.tooltip.paddingY
            }

            // Solid while glass is on: its text is judged on that fill
            // (ThemeLogic.readabilityShortfalls), which reads over any
            // backdrop, where translucent glass over a light one would not.
            GlassSurface {
                objectName: "tooltipSurface"
                anchors.fill: parent
                standard: root.side === "belowStart" ? root.band : Theme.tooltip
                elevation: "tight"
                solidOnly: true
            }

            // The whole popup, its padding too, holds a tooltip with a
            // link open under the pointer.
            HoverHandler { id: over }

            Item {
                id: content
                objectName: "tooltipContent"
                x: sideInset.inset
                y: Theme.tooltip.paddingY
                width: Math.max(0, window.width - 2 * sideInset.inset)
                height: column.implicitHeight
                implicitWidth: Math.min(Math.max(titleWidth, detailWidth), root.maxWidth)
                implicitHeight: column.implicitHeight

                readonly property real titleWidth: Math.min(Math.ceil(titleLink.active ? titleLink.implicitWidth : titleLabel.implicitWidth), root.maxWidth)
                readonly property real labelColumnWidth: detailColumn.maxColumn("labelImplicitWidth")
                readonly property real valueColumnWidth: detailColumn.maxColumn("valueImplicitWidth")
                readonly property real countWidth: labelColumnWidth > 0 || valueColumnWidth > 0 ? labelColumnWidth + Theme.tooltip.gap + valueColumnWidth : 0
                readonly property real detailWidth: Math.min(Math.max(detailColumn.maxColumn("detailWidth"), countWidth), root.maxWidth)
                readonly property string detailRole: "itemHint"
                // The role's faint text unless it falls short on the fill
                // the tooltip's glass draws (Tokens.js tooltip.detail).
                readonly property color detailColor: Theme.tooltip.detail
                readonly property real ringBelow: detailColumn.visible ? detailColumn.lastRingBelow() : titleLink.ringBelow
                readonly property int lineWrapMode: Text.Wrap

                function detailModel() {
                    if (Array.isArray(root.details)) return root.details;
                    throw new Error("Tooltip: details=" + JSON.stringify(root.details) + " unexpected");
                }

                function isCount(entry) {
                    return entry !== null && typeof entry === "object" && !Array.isArray(entry)
                        && Object.prototype.hasOwnProperty.call(entry, "label")
                        && Object.prototype.hasOwnProperty.call(entry, "value");
                }

                function detailKind(entry, index) {
                    if (typeof entry === "string") return "plain";
                    if (isCount(entry)) return "count";
                    throw new Error("Tooltip: details[" + index + "]=" + JSON.stringify(entry) + " unexpected");
                }

                function detailHidden(entry) {
                    return isCount(entry) && (entry.value === 0 || entry.value === "0");
                }

                Column {
                    id: column
                    width: content.width
                    spacing: Theme.tooltip.gap

                    Item {
                        width: parent.width
                        height: titleLink.active ? titleLink.height : titleLabel.height

                        Label {
                            id: titleLabel
                            objectName: "tooltipTitle"
                            visible: !titleLink.active
                            role: "tooltip"
                            text: PageReference.plain(root.text)
                            color: Theme.tooltip.foreground
                            width: parent.width
                            wrapMode: content.lineWrapMode
                        }

                        LinkLine {
                            id: titleLink
                            active: root.linked(root.text)
                            line: root.text
                            role: titleLabel.role
                            tint: titleLabel.color
                            wrapMode: content.lineWrapMode
                            current: root.currentLine === 0
                            onPageActivated: (page, tab) => root.activate(page, tab)
                        }
                    }

                    Column {
                        id: detailColumn
                        objectName: "tooltipDetails"
                        width: parent.width
                        spacing: Theme.tooltip.gap
                        visible: root.details.length > 0

                        function maxColumn(propertyName) {
                            var max = 0;
                            for (var i = 0; i < children.length; i++) {
                                var child = children[i];
                                if (child.visible && child[propertyName] !== undefined)
                                    max = Math.max(max, Math.ceil(child[propertyName]));
                            }
                            return max;
                        }

                        // The last drawn row's, 0 where it holds no link.
                        function lastRingBelow() {
                            for (var i = children.length - 1; i >= 0; i--)
                                if (children[i].visible && children[i].ringBelow !== undefined) return children[i].ringBelow;
                            return 0;
                        }

                        Repeater {
                            model: content.detailModel()
                            delegate: Item {
                                objectName: kind === "count" ? "tooltipCountRow" : "tooltipDetailRow"
                                property var entry: modelData
                                readonly property string kind: content.detailKind(entry, index)
                                readonly property bool zeroRow: content.detailHidden(entry)
                                readonly property bool isCountDetail: kind === "count"
                                readonly property real ringBelow: plainLink.ringBelow
                                readonly property real labelImplicitWidth: countLabel.implicitWidth
                                readonly property real valueImplicitWidth: valueLabel.implicitWidth
                                readonly property real detailWidth: kind === "plain" ? Math.min(Math.ceil(plainLink.active ? plainLink.implicitWidth : plainLabel.implicitWidth), root.maxWidth) : labelImplicitWidth + Theme.tooltip.gap + valueImplicitWidth
                                width: detailColumn.width
                                height: !visible ? 0 : plainLink.active ? plainLink.height : kind === "plain" ? plainLabel.height : Math.max(countLabel.height, valueLabel.height)
                                visible: !zeroRow

                                Label {
                                    id: plainLabel
                                    objectName: "tooltipDetailLine"
                                    visible: kind === "plain" && !plainLink.active
                                    role: content.detailRole
                                    color: content.detailColor
                                    text: kind === "plain" ? PageReference.plain(entry) : ""
                                    width: parent.width
                                    wrapMode: content.lineWrapMode
                                }

                                LinkLine {
                                    id: plainLink
                                    active: root.linked(entry)
                                    line: active ? entry : ""
                                    role: plainLabel.role
                                    tint: plainLabel.color
                                    wrapMode: content.lineWrapMode
                                    current: root.currentLine === index + 1
                                    onPageActivated: (page, tab) => root.activate(page, tab)
                                }

                                Label {
                                    id: countLabel
                                    objectName: "tooltipCountLabel"
                                    visible: kind === "count"
                                    role: content.detailRole
                                    color: content.detailColor
                                    text: kind === "count" ? String(entry.label) : ""
                                    width: Math.max(0, parent.width - content.valueColumnWidth - Theme.tooltip.gap)
                                    elide: Text.ElideRight
                                }

                                Label {
                                    id: valueLabel
                                    objectName: "tooltipCountValue"
                                    visible: kind === "count"
                                    role: content.detailRole
                                    color: content.detailColor
                                    text: kind === "count" ? String(entry.value) : ""
                                    x: parent.width - width
                                    width: content.valueColumnWidth
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: popup.item
        function onVisibleChanged() { if (popup.item !== null && !popup.item.visible) root.shown = false; }
    }

    Component.onDestruction: {
        if (hover !== null) hover.destroy();
        if (press !== null) press.destroy();
    }
}
