import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.tailscale" as Tailscale
import "../../shell/plugins/vgs.tailscale/TailscaleLogic.js" as TailscaleLogic

// A disabled control's reason (DisabledReason, Tooltip's "clear" side)
// opens where it covers no text, icon or Tab stop of its window, inside
// the box the window's content spans, and is no wider than that box. An
// unlock mark's reason covers its toggle neither. Where no place is free,
// it takes the place that covers the least, one that covers no Tab stop
// first.
// Every visible item of this window is an obstacle, so each test shows
// one fixture. The stand-in popup positions nothing: the box a tooltip
// takes is read from the anchor the popup is handed, as the compositor
// reads it (xdg_positioner: the anchor point on the rect's `edges`, the
// popup grown from it toward `gravity`).
Item {
    id: root
    width: 480
    height: 260

    readonly property string reason: "Sign in to your VPN account to turn on this switch"
    readonly property int inset: 16

    // A 320 px flyout: a heading, a row of a locked control and a sibling
    // button, a hint under the control, and a button on the bottom end
    // corner. `where` puts the control on the start edge, the end edge or
    // the centre, and the hint's words under it.
    Item {
        id: narrow
        visible: false
        width: 320
        height: 216

        property string where: "start"
        readonly property rect content: Qt.rect(root.inset, root.inset, width - 2 * root.inset, height - 2 * root.inset)

        Label { id: heading; x: root.inset; y: root.inset; width: narrow.content.width; role: "subheading"; text: "VPN profiles" }
        Button {
            id: locked
            y: 96
            x: narrow.where === "start" ? root.inset : narrow.where === "end" ? narrow.width - root.inset - width : Math.round((narrow.width - width) / 2)
            text: "Sign in"
            disabledReason: root.reason
        }
        Button {
            id: sibling
            y: locked.y
            x: narrow.where === "end" ? locked.x - Theme.stack.inline - width : locked.x + locked.width + Theme.stack.inline
            text: "Edit"
            variant: "secondary"
        }
        Label {
            id: hint
            x: root.inset
            y: locked.y + locked.height + Theme.tooltip.gap
            width: narrow.content.width
            role: "hint"
            text: "Routes your traffic through the VPN"
            horizontalAlignment: narrow.where === "start" ? Text.AlignLeft : narrow.where === "end" ? Text.AlignRight : Text.AlignHCenter
        }
        Button {
            id: close
            x: narrow.width - root.inset - width
            y: narrow.height - root.inset - height
            text: "Close"
            variant: "secondary"
        }
    }

    // A pane header: a title on the start edge and a locked switch with no
    // text on the end edge, whose step is one click, so its unlock mark
    // shows the switch's reason to the keyboard. A line above the row and
    // a hint under the switch leave the room before the switch, over its
    // track, as the one free place round the mark alone.
    Item {
        id: marked
        visible: false
        width: 320
        height: 216

        readonly property rect content: Qt.rect(root.inset, root.inset, width - 2 * root.inset, height - 2 * root.inset)

        Label { id: markedHeading; x: root.inset; y: root.inset; width: marked.content.width; role: "subheading"; text: "VPN profiles" }
        Label {
            id: markedAbove
            x: root.inset
            y: markedSwitch.y - Theme.tooltip.gap - height
            width: marked.content.width
            elide: Text.ElideRight
            text: "Turn on the VPN to route your traffic through your provider and keep it private"
        }
        Label { id: markedTitle; x: root.inset; y: markedSwitch.y; text: "VPN" }
        Switch {
            id: markedSwitch
            x: marked.width - root.inset - width
            y: 110
            disabledReason: "Sign in first"
            unlock: ({ label: "Sign in", run: () => {} })
        }
        Label {
            id: markedHint
            x: root.inset
            y: markedSwitch.y + markedSwitch.height + Theme.tooltip.gap
            width: marked.content.width
            role: "hint"
            horizontalAlignment: Text.AlignRight
            text: "Routes your traffic through the VPN"
        }
        Button {
            id: markedClose
            x: marked.width - root.inset - width
            y: marked.height - root.inset - height
            text: "Close"
            variant: "secondary"
        }
    }

    // A locked button with an icon under its start edge and room after
    // it: the places under the button cover the icon.
    Item {
        id: iconed
        visible: false
        width: 320
        height: 216

        readonly property rect content: Qt.rect(root.inset, root.inset, width - 2 * root.inset, height - 2 * root.inset)

        Label { id: iconedHeading; x: root.inset; y: root.inset; role: "subheading"; text: "VPN profiles" }
        Button { id: iconLocked; x: root.inset; y: 60; text: "Sign in"; disabledReason: "Sign in first" }
        Icon { id: shield; x: root.inset; y: iconLocked.y + iconLocked.height + 2 * Theme.tooltip.gap; name: "shield" }
        Button {
            id: iconedClose
            x: iconed.width - root.inset - width
            y: iconed.height - root.inset - height
            text: "Close"
            variant: "secondary"
        }
    }

    // A window packed with text round a locked control: lines above and
    // under it, a label before it, and a small Tab stop after it, so every
    // place covers something, and the place that covers the least covers
    // the Tab stop.
    Item {
        id: packed
        visible: false
        width: 448
        height: below.y + below.height + root.inset

        readonly property rect content: Qt.rect(root.inset, root.inset, width - 2 * root.inset, height - 2 * root.inset)
        readonly property string filler: "Account name and password and server and port and the protocol it uses"

        Column {
            id: above
            x: root.inset
            y: root.inset
            Repeater {
                model: 4
                Label { width: packed.content.width; text: packed.filler; elide: Text.ElideRight }
            }
        }
        Button {
            id: crowded
            x: 200
            y: above.y + above.height + 2 * Theme.tooltip.gap
            text: "Sign in"
            disabledReason: "Sign in first"
        }
        Label {
            id: before
            x: root.inset
            width: crowded.x - Theme.tooltip.gap - root.inset
            y: crowded.y + Math.round((crowded.height - height) / 2)
            horizontalAlignment: Text.AlignRight
            text: "Account name"
        }
        IconButton {
            id: smallStop
            size: "sm"
            iconName: "x"
            label: "Clear"
            x: crowded.x + crowded.width + 2 * Theme.tooltip.gap
            y: crowded.y + Math.round((crowded.height - height) / 2)
        }
        Column {
            id: below
            x: root.inset
            y: crowded.y + crowded.height + 2 * Theme.tooltip.gap
            Repeater {
                model: 4
                Label { width: packed.content.width; text: packed.filler; elide: Text.ElideRight }
            }
        }
    }

    // A flyout's Pane header: the title, a locked switch whose name label
    // sits before it and its unlock mark after it, over a line of text and
    // a hint that span the body, so every place under the switch covers
    // text and the one free place lies between the title and the label.
    // `named` false gives the switch the title's name, so no label shows.
    // It is a flyout less the room a summoned flyout's gear takes, so the
    // title leaves the reason less than its own width.
    Item {
        id: header
        visible: false
        width: Theme.size.panel.lg - 40
        height: 216

        property bool named: true

        Rectangle { anchors.fill: parent; color: Theme.color.surface }
        Pane {
            id: headerPane
            anchors.fill: parent
            title: "VPN"
            switchShown: true
            switchChecked: true
            switchName: header.named ? "Tailscale" : "VPN"
            switchDisabledReason: "Sign in as the administrator to change this switch."
            switchUnlock: ({ label: "Let my login control Tailscale", run: () => {} })

            Column {
                width: headerPane.contentWidth
                Label { id: headerState; width: parent.width; text: "Connected through Zurich, Switzerland and its exit node" }
                Label { id: headerHint; width: parent.width; role: "hint"; text: "Routes your traffic through the exit node you choose here" }
            }
        }
    }

    Item {
        id: repeated
        visible: false
        width: 480
        height: 260
        property string settingsPage: "VPN"
        function openSettingsPage() {}
        Pane {
            id: repeatedPane
            anchors.fill: parent
            title: "VPN"
            switchShown: true
            switchName: "Tailscale"
            switchDisabledReason: "The administrator holds Tailscale until you choose Let my login control Tailscale."
            switchUnlock: ({ label: "Let my login control Tailscale", run: () => {} })
            // The flyout draws the state line as the title's subtitle
            // (vgs.tailscale Panel.qml).
            subtitle: [Label { id: repeatedState; width: repeatedPane.headerWidth; text: repeatedBody.tailscale.text; wrapMode: Text.Wrap }]
            Tailscale.TailscaleBody {
                id: repeatedBody
                width: repeatedPane.contentWidth
                shell: ({ settings: { pollSeconds: 30 }, status: { values: { tailscale: Object.assign(TailscaleLogic.unread(), { state: "running", text: "Connected through Zurich, Switzerland" }) }, rows: [{ key: "setup", action: { offered: true, label: "Let my login control Tailscale" }, hint: "The administrator holds Tailscale. After this step, VGS connects and disconnects for you without a password." }] } })
            }
        }
    }

    TestCase {
        name: "reasontip"
        when: windowShown

        function init() {
            UnitTheme.reset();
            compare(UnitTheme.override({ tooltip: { delay: 50 } }), "ok");
            root.forceActiveFocus();
        }

        function cleanup() {
            for (const control of [locked, crowded, iconLocked]) {
                const tip = reasonTip(control);
                if (tip === null) continue;
                tip.shown = false;
                tryCompare(tip, "opened", false);
            }
            const tip = markTip();
            if (tip !== null) {
                tip.shown = false;
                tryCompare(tip, "opened", false);
            }
            if (headerPane.headerSwitch !== null) {
                const tip = reasonTip(headerPane.headerSwitch);
                if (tip !== null) {
                    tip.shown = false;
                    tryCompare(tip, "opened", false);
                }
            }
            const repeatedTip = reasonTip(repeatedPane.headerSwitch);
            if (repeatedTip !== null) {
                repeatedTip.shown = false;
                tryCompare(repeatedTip, "opened", false);
            }
            header.visible = false;
            header.named = true;
            headerPane.switchDisabledReason = "Sign in as the administrator to change this switch.";
            narrow.visible = false;
            marked.visible = false;
            iconed.visible = false;
            packed.visible = false;
            repeated.visible = false;
        }

        function descendants(node) {
            let out = [];
            for (const child of node.children) out = out.concat([child], descendants(child));
            return out;
        }

        function reasonTip(control) { return descendants(control).find(item => item.objectName === "disabledReasonTip") || null; }

        function markOf(control) { return descendants(control).find(item => item.iconName === "lock-open") || null; }

        function markTip() {
            const mark = markOf(markedSwitch);
            return mark === null ? null : mark.data.find(child => child.anchorItem === mark && child.side !== undefined) || null;
        }

        function box(item) {
            const at = item.mapToItem(root, 0, 0);
            return Qt.rect(at.x, at.y, item.width, item.height);
        }

        // A text's words where its alignment puts them; the room after the
        // words is free.
        function words(label) {
            const at = label.mapToItem(root, 0, 0);
            const free = label.width - label.contentWidth;
            const shift = label.horizontalAlignment === Text.AlignRight ? free : label.horizontalAlignment === Text.AlignHCenter ? free / 2 : 0;
            return Qt.rect(at.x + shift, at.y, label.contentWidth, label.contentHeight);
        }

        function overlap(a, b) {
            const width = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x);
            const height = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y);
            return width > 0 && height > 0 ? width * height : 0;
        }

        function inside(inner, outer) {
            return inner.x >= outer.x && inner.y >= outer.y && inner.x + inner.width <= outer.x + outer.width && inner.y + inner.height <= outer.y + outer.height;
        }

        function surfaceBox(surface) {
            const at = surface.mapToItem(root, surface.content.x, surface.content.y);
            return Qt.rect(at.x, at.y, surface.content.width, surface.content.height);
        }

        // The box the popup takes from the anchor it is handed, in the
        // window's coordinates.
        function placedBox(tip) {
            const popup = tip.tracker.popup;
            const anchor = popup.anchor;
            const m = anchor.margins;
            const r = { x: anchor.rect.x + m.left, y: anchor.rect.y + m.top, width: anchor.rect.width - m.left - m.right, height: anchor.rect.height - m.top - m.bottom };
            const e = anchor.edges, g = anchor.gravity;
            const px = e & Edges.Left ? r.x : e & Edges.Right ? r.x + r.width : r.x + r.width / 2;
            const py = e & Edges.Top ? r.y : e & Edges.Bottom ? r.y + r.height : r.y + r.height / 2;
            const x = g & Edges.Right ? px : g & Edges.Left ? px - popup.width : px - popup.width / 2;
            const y = g & Edges.Bottom ? py : g & Edges.Top ? py - popup.height : py - popup.height / 2;
            const at = anchor.item.mapToItem(root, x, y);
            return Qt.rect(at.x, at.y, popup.width, popup.height);
        }

        // Opens the control's reason the way the keyboard does.
        function openReason(control) {
            control.forceActiveFocus(Qt.TabFocusReason);
            compare(control.visualFocus, true);
            const tip = reasonTip(control);
            verify(tip !== null, "the locked control holds its reason");
            tryCompare(tip, "opened", true);
            return tip;
        }

        // What a place does wrong in the narrow flyout: the texts and the
        // Tab stops it covers and whether it leaves the content box.
        function narrowFaults(place) {
            const out = [];
            if (overlap(place, words(hint)) > 0) out.push("covers the hint");
            if (overlap(place, words(heading)) > 0) out.push("covers the heading");
            for (const control of [sibling, close]) if (overlap(place, box(control)) > 0) out.push("covers " + control.text);
            if (overlap(place, box(locked)) > 0) out.push("covers its control");
            if (!inside(place, surfaceBox(narrow))) out.push("leaves the content box");
            return out;
        }

        function test_a_reason_covers_no_sibling_in_a_narrow_flyout_data() {
            return [{ tag: "start edge", where: "start" }, { tag: "end edge", where: "end" }, { tag: "centre", where: "centre" }];
        }

        function test_a_reason_covers_no_sibling_in_a_narrow_flyout(data) {
            narrow.where = data.where;
            narrow.visible = true;
            const tip = openReason(locked);
            const popup = tip.tracker.popup;
            const place = placedBox(tip);
            compare(narrowFaults(place), [], "the reason's place " + JSON.stringify(place));
            verify(popup.width <= narrow.content.width, "the reason is no wider than the content: " + popup.width);
            // The handed anchor is the readback the place is judged by.
            compare(tip.placed.width, popup.width);
            compare(tip.placed.height, popup.height);
            const at = locked.mapToItem(root, tip.placed.x, tip.placed.y);
            compare(Qt.rect(at.x, at.y, tip.placed.width, tip.placed.height), place);

            // The judge fails the place a tooltip under its control,
            // centred on it, takes.
            const a = box(locked);
            const under = Qt.rect(a.x + (a.width - popup.width) / 2, a.y + a.height + Theme.tooltip.gap, popup.width, popup.height);
            verify(narrowFaults(under).length > 0, "the judge refuses the place under the control");
        }

        // The unlock mark shows the switch's reason to the keyboard through
        // the same rule: it covers no hint, heading or button, and stays
        // inside the content box.
        function test_an_unlock_mark_shows_its_reason_where_it_covers_no_sibling() {
            marked.visible = true;
            const mark = markOf(markedSwitch);
            verify(mark !== null, "the locked switch draws its mark");
            mark.forceActiveFocus(Qt.TabFocusReason);
            const tip = markTip();
            verify(tip !== null, "the mark holds its tooltip");
            tryCompare(tip, "opened", true);
            compare(tip.text, markedSwitch.disabledReason);
            const place = placedBox(tip);
            const faults = [];
            if (overlap(place, words(markedHint)) > 0) faults.push("covers the hint");
            if (overlap(place, words(markedHeading)) > 0) faults.push("covers the heading");
            if (overlap(place, words(markedAbove)) > 0) faults.push("covers the line above");
            if (overlap(place, words(markedTitle)) > 0) faults.push("covers the title");
            if (overlap(place, box(markedSwitch)) > 0) faults.push("covers its switch");
            if (overlap(place, box(markedClose)) > 0) faults.push("covers Close");
            if (overlap(place, box(mark)) > 0) faults.push("covers its mark");
            if (!inside(place, surfaceBox(marked))) faults.push("leaves the content box");
            compare(faults, [], "the mark's reason's place " + JSON.stringify(place));
        }

        // What a place does wrong in the Pane header: the texts, the Tab
        // stops and the switch it covers, and whether it leaves the
        // content box.
        function headerFaults(place) {
            const control = headerPane.headerSwitch;
            const labels = descendants(headerPane).filter(item => item.text === "VPN" || item.text === "Tailscale").filter(item => item.contentWidth !== undefined && item.visible);
            const out = [];
            for (const label of labels.concat([headerState, headerHint]))
                if (overlap(place, words(label)) > 0) out.push("covers " + label.text);
            if (overlap(place, box(control)) > 0) out.push("covers its switch");
            const mark = markOf(control);
            if (mark !== null && overlap(place, box(mark)) > 0) out.push("covers its mark");
            if (!inside(place, Qt.rect(0, 0, header.width, header.height))) out.push("leaves the pane");
            return out;
        }

        // A header switch with a name label keeps its reason clear of the
        // label and the title: the label lies in the box the places keep
        // clear of, and the text wraps in the room the title leaves.
        function test_a_pane_switch_reason_covers_no_name_label_or_title() {
            header.visible = true;
            const control = headerPane.headerSwitch;
            verify(headerPane.switchLabelShown, "the switch draws its name label");
            const tip = openReason(control);
            const place = placedBox(tip);
            compare(headerFaults(place), [], "the reason's place " + JSON.stringify(place));

            // Planted: the switch's own box as the anchor, as before the
            // label joined it. The left place then ends on the label.
            root.forceActiveFocus();
            tryCompare(tip, "opened", false);
            tip.box = Qt.rect(0, 0, control.width, control.height);
            openReason(control);
            compare(headerFaults(placedBox(tip)), ["covers Tailscale"], "a switch-only anchor's place " + JSON.stringify(placedBox(tip)));
            tip.box = Qt.binding(() => control.lock.reasonBox);
        }

        function test_a_pane_reason_keeps_its_padding_from_title_ink_data() {
            return [{ tag: "vgs", theme: "vgs" }, { tag: "flexoki-light", theme: "catalog/flexoki-light" }];
        }

        function test_a_pane_reason_keeps_its_padding_from_title_ink(data) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../themes/" + data.theme + "/theme.json"), false);
            request.send();
            compare(UnitTheme.override(JSON.parse(request.responseText).tokens), "ok");
            headerPane.switchDisabledReason = "The administrator holds Tailscale until you choose Let my login control Tailscale.";
            header.visible = true;
            verify(waitForRendering(header));
            const tip = openReason(headerPane.headerSwitch);
            const title = descendants(headerPane).find(item => item.text === "VPN" && item.contentWidth !== undefined && item.visible);
            verify(title !== undefined, "the header draws its title");
            const at = title.mapToItem(header, 0, 0), image = grabImage(header), bg = Qt.color(Theme.color.surface);
            let last = -1;
            for (let x = Math.floor(at.x); x < Math.ceil(at.x + title.contentWidth); x++)
                for (let y = Math.floor(at.y); y < Math.ceil(at.y + title.height); y++)
                    if (Math.abs(image.red(x, y) - Math.round(bg.r * 255)) > 8 || Math.abs(image.green(x, y) - Math.round(bg.g * 255)) > 8 || Math.abs(image.blue(x, y) - Math.round(bg.b * 255)) > 8) last = x;
            verify(last >= 0, "the title has ink");
            const gap = placedBox(tip).x - (last + 1);
            console.log("reason-gap: theme=" + data.tag + " gap=" + gap + " padding=" + Theme.tooltip.paddingX);
            verify(gap >= Theme.tooltip.paddingX, "the title ink keeps the tooltip padding: " + gap);
        }

        // A header switch named as its title draws no label, and its reason
        // keeps the switch's own box and the tooltip's own width.
        function test_a_pane_switch_with_no_label_keeps_its_own_box() {
            header.named = false;
            header.visible = true;
            const control = headerPane.headerSwitch;
            verify(!headerPane.switchLabelShown, "the switch draws no name label");
            compare(control.lock.reasonBox, Qt.rect(0, 0, control.width, control.height));
            compare(control.lock.reasonWidth, Theme.tooltip.maxWidth);
            const tip = openReason(control);
            compare(tip.box, Qt.rect(0, 0, control.width, control.height));
            compare(tip.maxWidth, Theme.tooltip.maxWidth);
        }

        function test_a_reason_can_cover_only_text_that_repeats_its_cause_data() {
            return [{ tag: "vgs", theme: "vgs" }, { tag: "flexoki-light", theme: "catalog/flexoki-light" }];
        }

        function test_a_reason_can_cover_only_text_that_repeats_its_cause(data) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../themes/" + data.theme + "/theme.json"), false);
            request.send();
            compare(UnitTheme.override(JSON.parse(request.responseText).tokens), "ok");
            repeated.visible = true;
            const repeatedHint = descendants(repeatedBody).find(item => item.objectName === "tailscale-setup-hint");
            const repeatedAction = descendants(repeatedBody).find(item => item.objectName === "tailscale-setup");
            compare(repeatedHint.opacity, 1);
            const control = repeatedPane.headerSwitch;
            const tip = openReason(control);
            const place = placedBox(tip);
            compare(tip.scene.obstacles.reduce((sum, each) => sum + overlap(place, each), 0), 0);
            compare(overlap(place, words(repeatedState)), 0);
            compare(overlap(place, box(repeatedAction)), 0);
            compare(overlap(place, box(control)), 0);
            verify(overlap(place, words(repeatedHint)) > 0);
            const anchor = tip.scene.anchor;
            compare(place.x + place.width, anchor.x + anchor.width);
            verify(place.x + place.width >= box(control).x);
            compare(OverlayState.coveredReason, repeatedHint);
            compare(repeatedHint.opacity, Theme.opacity.disabled);
            root.forceActiveFocus();
            tryCompare(tip, "opened", false);
            compare(OverlayState.coveredReason, null);
            compare(repeatedHint.opacity, 1);
        }

        function test_the_covered_text_reference_clears_on_destruction() {
            const text = Qt.createQmlObject('import QtQuick; Text { text: "repeat" }', root);
            OverlayState.coveredReason = text;
            text.destroy();
            tryCompare(OverlayState, "coveredReason", null);
        }

        // An icon is an image the reason never covers.
        function test_a_reason_covers_no_icon() {
            iconed.visible = true;
            const tip = openReason(iconLocked);
            const place = placedBox(tip);
            const faults = [];
            if (overlap(place, box(shield)) > 0) faults.push("covers the icon");
            if (overlap(place, words(iconedHeading)) > 0) faults.push("covers the heading");
            if (overlap(place, box(iconedClose)) > 0) faults.push("covers Close");
            if (overlap(place, box(iconLocked)) > 0) faults.push("covers its control");
            if (!inside(place, surfaceBox(iconed))) faults.push("leaves the content box");
            compare(faults, [], "the reason's place " + JSON.stringify(place));
        }

        // The places a model of the rule tries: below, above, right and
        // left of the control, each centred and on either edge, held in
        // the content box.
        function places(a, c, w, h, gap) {
            const hold = (at, low, size, span) => Math.max(low, Math.min(Math.round(at), low + span - size));
            const xs = [a.x + (a.width - w) / 2, a.x, a.x + a.width - w].map(x => hold(x, c.x, w, c.width));
            const ys = [a.y + (a.height - h) / 2, a.y, a.y + a.height - h].map(y => hold(y, c.y, h, c.height));
            const out = [];
            for (const y of [Math.ceil(a.y + a.height + gap), Math.floor(a.y - gap - h)]) for (const x of xs) out.push(Qt.rect(x, y, w, h));
            for (const x of [Math.ceil(a.x + a.width + gap), Math.floor(a.x - gap - w)]) for (const y of ys) out.push(Qt.rect(x, y, w, h));
            return out;
        }

        function test_with_no_free_place_a_reason_covers_the_least_and_no_tab_stop() {
            packed.visible = true;
            const tip = openReason(crowded);
            const place = placedBox(tip);
            const content = surfaceBox(packed);
            const texts = descendants(packed).filter(item => item.contentWidth !== undefined && item.font !== undefined && item.visible && item.text !== "" && !descendants(crowded).includes(item) && !descendants(smallStop).includes(item));
            verify(texts.length >= 9, "the fixture's texts are found: " + texts.length);
            const textCover = p => texts.reduce((sum, label) => sum + overlap(p, words(label)), 0);

            verify(inside(place, content), "the reason stays inside the content box: " + JSON.stringify(place));
            compare(overlap(place, box(smallStop)), 0, "the reason covers no Tab stop");
            compare(overlap(place, box(crowded)), 0, "the reason covers no part of its control");

            const all = places(box(crowded), content, tip.tracker.popup.width, tip.tracker.popup.height, Theme.tooltip.gap).filter(p => inside(p, content));
            verify(all.every(p => textCover(p) + overlap(p, box(smallStop)) > 0), "no place in the fixture is free");
            const clear = all.filter(p => overlap(p, box(smallStop)) === 0);
            const least = Math.min(...clear.map(textCover));
            compare(textCover(place), least, "the reason covers the least text of the places that cover no Tab stop");

            // Ranked by the area alone, the place that covers the Tab stop
            // would win: it covers less than the reason's place.
            const cover = p => textCover(p) + overlap(p, box(smallStop));
            const byArea = all.reduce((best, p) => cover(p) < cover(best) ? p : best);
            verify(overlap(byArea, box(smallStop)) > 0, "the least area place covers the Tab stop: " + JSON.stringify(byArea));
            verify(cover(byArea) < cover(place), "it covers less than the reason's place");
        }
    }
}
