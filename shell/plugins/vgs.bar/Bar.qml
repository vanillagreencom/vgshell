import QtQuick
import QtQml.Models
import qs.Commons
import qs.Ui

// The core orders registered built-ins and plugin widgets together.
// The bar owns its built-in model; visual section changes keep its delegates.
Item {
    id: bar

    property var shell: null
    property var screen: null

    readonly property color foreground: Theme.bar.foreground
    readonly property color background: Theme.bar.background
    readonly property string fontFamily: Theme.text.bar.family
    readonly property int barSize: Theme.bar.height

    // The host maps this screen's bar only while it is shown; the `hidden`
    // setting, which the service's toggle writes, hides it everywhere.
    readonly property bool shown: shell === null || shell.settings.hidden !== true

    readonly property Item leftSection: leftZone.content
    readonly property Item centerSection: center
    readonly property Item rightSection: rightZone.content

    readonly property var builtinLabels: ({ "left-workspaces": "Workspaces", "center-clock": "Clock" })
    readonly property var builtinNames: Object.keys(builtinLabels)
    // Gaps and separators the user adds from the bar's right-click menu:
    // one builtin per layout entry, `gap-<n>` or `separator-<n>`.
    readonly property var builtinFamilies: ["gap", "separator"]
    readonly property var familyLabels: ({ gap: "Gap", separator: "Separator" })
    // The family of registration `name`, or "" for a fixed builtin.
    function familyOf(name) {
        const match = /^([a-z][a-z0-9]*)-[1-9][0-9]*$/.exec(name);
        return match !== null && builtinFamilies.indexOf(match[1]) !== -1 ? match[1] : "";
    }
    function builtinLabel(name) {
        const family = familyOf(name);
        return family !== "" ? familyLabels[family] : builtinLabels[name];
    }
    property var widgetLayout: ({ left: [], center: [], right: [] })
    readonly property string builtinKey: JSON.stringify(
        ["left", "center", "right"].reduce((entries, section) => entries.concat(widgetLayout[section]), [])
            .filter(entry => shell !== null && entry.id.indexOf(shell.manifest.id + "/") === 0)
            .map(entry => shell === null ? "" : entry.id.slice(shell.manifest.id.length + 1)))

    // ListModel.move keeps Repeater delegates alive across section changes:
    // https://doc.qt.io/qt-6/qml-qtqml-models-listmodel.html#move-method.
    function syncBuiltins(model, key) {
        const names = JSON.parse(key);
        for (let i = model.count - 1; i >= 0; --i)
            if (names.indexOf(model.get(i).name) === -1) model.remove(i);
        for (let i = 0; i < names.length; ++i) {
            let at = i;
            while (at < model.count && model.get(at).name !== names[i]) ++at;
            if (at === model.count) model.insert(i, { name: names[i] });
            else if (at !== i) model.move(at, i, 1);
        }
    }
    ListModel { id: builtinModel }
    onBuiltinKeyChanged: syncBuiltins(builtinModel, builtinKey)
    Component.onCompleted: syncBuiltins(builtinModel, builtinKey)
    Repeater { model: builtinModel; Builtin { barItem: bar } }

    readonly property bool spacerMenuOpen: spacerUi.item !== null && spacerUi.item.menuOpened
    // The texts of the open add menu's entries, in order; [] while closed.
    readonly property var spacerMenuEntries: spacerUi.item !== null ? spacerUi.item.menuEntries : []

    // Whether bar point (x, y) falls on a drawn widget, whose own frame
    // menu takes the right click. A side section's parent is its zone,
    // and a widget the zone clips away is not drawn there.
    function overWidget(x, y) {
        return [leftSection, centerSection, rightSection].some(section =>
            section.parent.contains(section.parent.mapFromItem(bar, x, y)) && section.children.some(item =>
                item.visible && item.width > 0 && item.contains(item.mapFromItem(bar, x, y))));
    }

    // The new entry lands where a widget dragged to the click would drop.
    function addSpacer(family, x) {
        const reply = shell.builtins.add(family, bar.mapToItem(null, x, 0).x);
        if (reply !== "ok") console.warn("vgs.bar: add " + family + " " + reply);
    }

    // TapHandler's default DragThreshold policy takes a passive grab, so
    // a widget's own frame handler sees the same right click; overWidget
    // leaves that click to it (Qt Quick TapHandler gesturePolicy reference).
    // pointer-cursor-exempt: it adds the right click to the empty bar, which shows no control
    // keyboard-path: none; adding a gap or a separator is a pointer arrangement of the bar, as a drag is
    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: bar.shell !== null
        onTapped: eventPoint => {
            const at = eventPoint.position;
            if (bar.overWidget(at.x, at.y)) return;
            spacerUi.active = true;
            spacerUi.item.openAt(at.x);
        }
    }

    // The add menu is built on the first right click on the empty bar and
    // released once closed, so a bar at rest holds none.
    Loader {
        id: spacerUi

        function release() {
            if (item !== null && !item.menuOpened) active = false;
        }

        active: false
        sourceComponent: Item {
            id: ui

            readonly property bool menuOpened: spacerMenu.opened
            readonly property var menuEntries: spacerMenu.opened ? spacerMenu.items().map(entry => entry.text) : []

            // The menu opens under the click, which is where its entry lands.
            function openAt(clickX) {
                x = clickX;
                spacerMenu.open();
            }

            // The menu opens at this rectangle's bottom-left corner; one
            // stroke wide keeps it non-empty.
            width: Theme.divider.thickness
            height: bar.height
            onMenuOpenedChanged: if (!menuOpened) Qt.callLater(spacerUi.release)

            Menu {
                id: spacerMenu

                MenuItem {
                    text: "Add separator"
                    iconName: "separator-vertical"
                    onTriggered: bar.addSpacer("separator", ui.x)
                }
                MenuItem {
                    text: "Add gap"
                    iconName: "space"
                    onTriggered: bar.addSpacer("gap", ui.x)
                }
            }
        }
    }

    // The core positions children and sizes these passive containers.
    // Qt 6.11 Row transitions write y even when their animation names x;
    // that write removes the core's vertical-centering binding.
    // The centre keeps its own width; each side zone draws in the room
    // from its bar edge, after the padding, to the centre, less the gap,
    // and scrolls what does not fit there.
    Item {
        id: center
        readonly property real spacing: Theme.bar.gap
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; bottom: parent.bottom }
    }
    Zone {
        id: leftZone
        objectName: "bar-zone-left"
        edge: Qt.LeftEdge
        room: center.x - Theme.bar.gap - Theme.bar.padding
        anchors { left: parent.left; leftMargin: Theme.bar.padding; top: parent.top; bottom: parent.bottom }
    }
    Zone {
        id: rightZone
        objectName: "bar-zone-right"
        edge: Qt.RightEdge
        room: bar.width - Theme.bar.padding - center.x - center.width - Theme.bar.gap
        anchors { right: parent.right; rightMargin: Theme.bar.padding; top: parent.top; bottom: parent.bottom }
    }

    // A side zone of the bar: `content`, the section the core fills and
    // positions, in a view at most `room` wide. A zone that fits is as wide as
    // its content and draws it alone. A zone that does not fit clips its
    // content to `room` and shows a "<" button at its start while a widget
    // lies hidden before the shown ones, and a ">" button at its end while one
    // lies hidden after them. The buttons, the wheel over the zone and keyboard
    // focus on a hidden widget scroll it by whole widgets: each step lands a
    // widget's edge beside the fade, or at the zone's edge where no button
    // shows. At rest the widgets nearest the zone's bar edge show.
    component Zone: Item {
        id: zone

        // Qt.LeftEdge or Qt.RightEdge: the bar edge the zone stands at.
        required property int edge
        // The widest the zone may draw.
        property real room: 0
        readonly property Item content: section
        readonly property bool clipped: section.width > room
        readonly property real travel: Math.max(0, section.width - width)
        // What a step asked for: the width hidden before the view, and for
        // a right zone whether it rests at its bar edge. A content width
        // change leaves them, so a change undone within one turn, as a
        // reading that redraws narrower and back, moves nothing for good.
        property real held: 0
        property bool resting: true
        // How far the content is scrolled from its rest at the bar edge:
        // a right zone at rest keeps its edge, and one scrolled off it
        // keeps the width it hides before the view, so the widgets it shows
        // stay put; neither scrolls past its travel.
        readonly property real scroll: edge === Qt.LeftEdge ? Math.min(held, travel) : resting ? 0 : Math.max(0, travel - held)
        // The width of the content hidden before the view once the scroll is done.
        readonly property real before: edge === Qt.LeftEdge ? scroll : travel - scroll
        readonly property bool moreBefore: clipped && before > 0.5
        readonly property bool moreAfter: clipped && before < travel - 0.5
        // The room a shown button and its fade take from the view.
        readonly property real inset: startScroller.width
        // The scroll drawn now. Only a step slides it; a content width
        // change moves the content at once.
        property real drawnScroll: 0
        property bool stepping: false
        onScrollChanged: if (!stepping) {
            slide.stop();
            drawnScroll = scroll;
        }
        // A zone that still fits once the turn that made it fit has ended
        // starts at rest when it clips again.
        function settleFit() {
            if (clipped) return;
            held = 0;
            resting = true;
        }
        onClippedChanged: if (!clipped) Qt.callLater(settleFit)
        NumberAnimation {
            id: slide
            target: zone
            property: "drawnScroll"
            duration: Theme.motion.duration.normal
            easing.type: Theme.motion.easing.standard
        }

        // An item that clips hands no pointer event to its children outside
        // its box, so a hidden widget takes no click (Qt Quick 6.11
        // QQuickDeliveryAgentPrivate::pointerTargets; rows/bar.sh right-clicks
        // the clock over clipped widgets).
        width: Math.min(section.width, Math.max(0, room))
        clip: clipped

        // The drawn widgets in the order they stand.
        function widgets() {
            return section.children.filter(item => item.visible && item.width > 0 && item.height > 0)
                .sort((a, b) => a.x - b.x);
        }

        // Scroll so `hidden` of the content lies before the view.
        function scrollTo(hidden) {
            const at = Math.max(0, Math.min(travel, hidden));
            stepping = true;
            resting = edge === Qt.RightEdge && at >= travel - 0.5;
            held = at;
            stepping = false;
            slide.stop();
            slide.from = drawnScroll;
            slide.to = scroll;
            slide.start();
        }

        // One step toward the zone's end (1) or its start (-1): the first
        // widget the end cuts lands its right edge at the end, or the last
        // widget the start cuts lands its left edge at the start.
        function step(direction) {
            const items = widgets();
            if (direction > 0) {
                const end = before + width - (moreAfter ? inset : 0);
                const next = items.find(item => item.x + item.width > end + 0.5);
                scrollTo(next === undefined ? travel : next.x + next.width - width + inset);
            } else {
                const start = before + (moreBefore ? inset : 0);
                const previous = items.filter(item => item.x < start - 0.5).pop();
                scrollTo(previous === undefined ? 0 : previous.x - inset);
            }
        }

        // Scroll the least that shows all of `item`, an item of the content.
        function reveal(item) {
            if (item.x < before + (moreBefore ? inset : 0) - 0.5) scrollTo(item.x - inset);
            else if (item.x + item.width > before + width - (moreAfter ? inset : 0) + 0.5)
                scrollTo(item.x + item.width - width + inset);
        }

        // Keyboard focus that moves onto a hidden widget, or a control in one,
        // scrolls that widget into view.
        readonly property Item focusItem: Window.activeFocusItem
        onFocusItemChanged: {
            if (!clipped) return;
            for (let at = focusItem; at !== null; at = at.parent)
                if (at.parent === section) {
                    reveal(at);
                    return;
                }
        }

        // The wheel steps one widget a notch, toward the end for a turn
        // down or right. Qt reports a notch as an angleDelta of 120
        // (QWheelEvent::angleDelta); smaller deltas add up to one.
        property real wheelCarry: 0
        function takeWheel(wheel) {
            const delta = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y) ? wheel.angleDelta.x : wheel.angleDelta.y;
            if (delta * wheelCarry < 0) wheelCarry = 0;
            wheelCarry += delta;
            while (Math.abs(wheelCarry) >= 120) {
                step(wheelCarry < 0 ? 1 : -1);
                wheelCarry -= Math.sign(wheelCarry) * 120;
            }
        }

        // The wheel over the zone, under the content, so a widget that
        // takes the wheel itself, as Sound does, keeps it.
        // pointer-cursor-exempt: it takes the wheel alone, never a click
        // keyboard-path: the < and > buttons and keyboard focus scroll the zone
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            enabled: zone.clipped
            onWheel: wheel => zone.takeWheel(wheel)
        }

        // The section the core fills. The core's drop reads the box the
        // zone draws in and the part of it that shows whole widgets, in
        // section coordinates, and hands `reveal` a drag's preview gap and
        // the widget it drops.
        Item {
            id: section
            readonly property real spacing: Theme.bar.gap
            readonly property real viewX: -x
            readonly property real viewWidth: zone.width
            readonly property real shownX: -x + (zone.moreBefore ? zone.inset : 0)
            readonly property real shownWidth: zone.width - (zone.moreBefore ? zone.inset : 0) - (zone.moreAfter ? zone.inset : 0)
            function reveal(item) { zone.reveal(item); }
            x: zone.edge === Qt.LeftEdge ? -zone.drawnScroll : zone.width - width + zone.drawnScroll
            height: zone.height
        }

        Scroller {
            id: startScroller
            owner: zone
            direction: -1
            visible: zone.moreBefore
        }
        Scroller {
            owner: zone
            direction: 1
            visible: zone.moreAfter
        }
    }

    // A zone button on the bar's colour, with the fade beside it toward
    // the zone's middle.
    component Scroller: Item {
        id: scroller

        required property Item owner
        // -1 for the start's "<", 1 for the end's ">".
        required property int direction
        readonly property bool start: direction < 0

        width: button.width + Theme.bar.scroll.fade
        height: scroller.owner.height
        x: start ? 0 : scroller.owner.width - width

        // The backdrop takes every press, hover and wheel turn the bar
        // item in it leaves, so the widget it covers opens no menu, shows
        // no tooltip and takes no wheel from under the button. A press on
        // it steps as the button does, and a turn over it scrolls the
        // zone. A right click on the bar item steps the zone too (the bar
        // row reads it).
        // keyboard-path: the button inside takes Tab focus and Enter
        MouseArea {
            x: scroller.start ? 0 : Theme.bar.scroll.fade
            width: button.width
            height: parent.height
            acceptedButtons: Qt.AllButtons
            hoverEnabled: true
            onClicked: scroller.owner.step(scroller.direction)
            onWheel: wheel => scroller.owner.takeWheel(wheel)
            PointerCursor {}

            Rectangle {
                anchors.fill: parent
                color: Theme.bar.scroll.backdrop
            }
            BarItem {
                id: button
                objectName: scroller.owner.objectName + (scroller.start ? "-start" : "-end")
                anchors.verticalCenter: parent.verticalCenter
                iconName: scroller.start ? "chevron-left" : "chevron-right"
                label: scroller.start ? "Scroll left" : "Scroll right"
                onClicked: scroller.owner.step(scroller.direction)
            }
        }
        Rectangle {
            x: scroller.start ? button.width : 0
            width: Theme.bar.scroll.fade
            height: parent.height
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: scroller.start ? Theme.bar.scroll.backdrop : Theme.bar.scroll.clear }
                GradientStop { position: 1; color: scroller.start ? Theme.bar.scroll.clear : Theme.bar.scroll.backdrop }
            }
        }
    }
}
