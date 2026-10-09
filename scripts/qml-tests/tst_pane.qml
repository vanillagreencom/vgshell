import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.displays" as Displays

// Pane owns the layout contract for an inset container: title row, header,
// body and footer share one content edge, the title row owns a feature
// switch at its end, the scroll bar sits in the right inset strip,
// fit-to-content caps at a maximum height, a rounded container clears its
// drawn corner through the shared inset rule, both dividers run from the
// frame's border on one side to the other, and inside a host that names a
// Settings page the outermost pane draws the gear that opens it.
Item {
    id: root
    width: 500
    height: 500

    Pane {
        id: pane
        width: 240
        height: 200
        container: "window"
        header: [ Label { text: "Header"; role: "h2"; width: parent.width } ]
        Repeater { model: 12; ListItem { required property int index; width: parent.width; text: "Row " + index } }
        footer: [ Button { text: "Apply"; variant: "secondary" } ]
    }

    Pane {
        id: fitted
        y: 240
        width: 240
        fitToContent: true
        maximumHeight: 120
        container: "dialog"
        header: [ Label { text: "Tall"; role: "h3"; width: parent.width } ]
        Rectangle { width: parent.width; height: 220; color: "transparent" }
    }

    Pane {
        id: emptyBody
        x: 260
        width: 200
        fitToContent: true
        container: "dialog"
        header: [ Label { text: "Header"; role: "h3"; width: parent.width } ]
        footer: [ Button { text: "Apply"; variant: "secondary" } ]
    }

    Pane {
        id: hiddenBody
        x: 260
        y: 120
        width: 200
        fitToContent: true
        container: "dialog"
        header: [ Label { text: "Header"; role: "h3"; width: parent.width } ]
        Rectangle { width: parent.width; height: 80; color: "transparent"; visible: false }
        footer: [ Button { text: "Apply"; variant: "secondary" } ]
    }

    // A fitted pane its host holds shorter than its fitted height, as a
    // popup held inside a short output does.
    Pane {
        id: held
        x: 260
        y: 240
        width: 200
        height: 140
        fitToContent: true
        maximumHeight: 400
        container: "dialog"
        header: [ Label { text: "Header"; role: "h3"; width: parent.width } ]
        Rectangle { width: parent.width; height: 300; color: "transparent" }
        footer: [ Button { text: "Apply"; variant: "secondary" } ]
    }

    // A panel over a click target: a bare header label, a short body and
    // a footer bound to the content width, fitted under a cap.
    Component {
        id: overTarget
        Item {
            width: 240
            height: 300
            property alias pane: layer
            property alias spy: clicks
            MouseArea { id: target; anchors.fill: parent }
            SignalSpy { id: clicks; target: target; signalName: "clicked" }
            Pane {
                id: layer
                anchors.fill: parent
                container: "panel"
                fitToContent: true
                maximumHeight: 300
                header: [ Label { role: "h3"; text: "Themes" } ]
                Section {
                    title: "Wallpaper"
                    Item { width: layer.contentWidth; height: 72 }
                }
                footer: [ Column { width: layer.contentWidth; Button { width: parent.width; text: "Add" } } ]
            }
        }
    }
    // A fitted pane whose body takes the room the pane leaves it.
    Component {
        id: filled
        Pane {
            id: layer
            width: 240
            container: "panel"
            fitToContent: true
            maximumHeight: 300
            header: [ Item { width: 10; height: 20 } ]
            Item { width: layer.contentWidth; height: layer.bodyRoom }
            footer: [ Item { width: 10; height: 30 } ]
        }
    }

    // A panel whose body overflows under its footer, so both dividers can
    // show at once.
    Component {
        id: scrolledPanel
        Pane {
            id: layer
            width: 240
            height: 200
            property int rowCount: 12
            container: "panel"
            header: [ Item { width: 10; height: 20 } ]
            Repeater { model: layer.rowCount; ListItem { required property int index; width: layer.contentWidth; text: "Row " + index } }
            footer: [ Item { width: 10; height: 30 } ]
        }
    }

    // A stand-in for the slot that hosts a summoned plugin: it names a
    // Settings page and records each request to open it. The plugin's root
    // stands between it and the pane, as in a slot, and a pane nested in
    // the body is a second pane of the same plugin.
    Component {
        id: settingsHost
        Item {
            id: host
            width: 300
            height: 300
            property string settingsPage: "acme.x"
            property int opened: 0
            function openSettingsPage() { opened += 1; }
            property alias pane: outer
            property alias nested: inner
            property alias bare: headerless
            property alias titled: titledPane
            Item {
                anchors.fill: parent
                Pane {
                    id: outer
                    width: 300
                    container: "panel"
                    fitToContent: true
                    header: [ Label { role: "h3"; text: "Acme" } ]
                    Pane {
                        id: inner
                        width: outer.contentWidth
                        height: 100
                        container: "panel"
                        header: [ Label { role: "h3"; text: "Inner" } ]
                    }
                }
                Item {
                    y: 200
                    width: 300
                    height: 100
                    Pane {
                        id: headerless
                        anchors.fill: parent
                        container: "panel"
                        Item { width: headerless.contentWidth; height: 20 }
                    }
                }
                Pane {
                    id: titledPane
                    x: 320
                    width: 300
                    container: "panel"
                    fitToContent: true
                    title: "Network"
                    switchShown: true
                    Item { width: titledPane.contentWidth; height: 20 }
                }
            }
        }
    }

    Component {
        id: mountedSection
        Item {
            id: parentSection
            property bool dirty: false
            readonly property Item footer: SaveBar {
                parent: null
                width: parent === null ? 0 : parent.width
                dirty: parentSection.dirty
            }
        }
    }

    Component {
        id: footerHolder
        Pane {
            width: 400
            height: 300
            container: "window"
            property Item section: null
            property Item rememberedFooter: section === null ? null : section.footer
            footer: section === null ? [] : [section.footer]
            Item { width: parent.width; height: 700 }
        }
    }

    Component { id: displaysSection; Displays.Pane {} }

    Component {
        id: titledSources
        Pane {
            id: layout
            width: 320
            height: implicitHeight
            fitToContent: true
            container: "window"
            title: "Sources"
            subtitle: Label { text: "Ready"; role: "hint" }
            property alias rows: sourceRows
            Column {
                width: parent.width
                spacing: Theme.stack.row
                Repeater {
                    id: sourceRows
                    model: 7
                    ListItem { required property int index; width: parent.width; text: "Source " + index; secondary: "Ready" }
                }
            }
            footer: Button { text: "Refresh" }
        }
    }

    TestCase {
        name: "pane"
        when: windowShown

        function init() { UnitTheme.reset(); }
        function titleRow(of) { return of.children[0]; }
        function titleLabel(of) { return titleRow(of).children[0]; }
        function scroll(of) { return of.scrollArea; }
        // The gear's Loader holds no item while the gear does not show.
        function gear(of) { return of.children[1].item; }
        function headerSlot(of) { return of.children[2]; }
        function footerSlot(of) { return of.children[4]; }
        function divider(of) { return of.children[5]; }
        function footerDivider(of) { return of.children[6]; }
        // The scroll area's touchpad area is an item of its content too.
        function body(of) { return of.scrollArea.contentItem.children.find(child => !(child instanceof TouchpadScroll)).children[0]; }

        function test_title_growth_keeps_the_last_source_row_reachable_data() {
            return [
                { tag: "one line fits", lines: 1, cap: 0 },
                { tag: "added line fits", lines: 2, cap: 0 },
                { tag: "one line scrolls", lines: 1, cap: 300 },
                { tag: "added line scrolls", lines: 2, cap: 300 }
            ];
        }

        function test_title_growth_keeps_the_last_source_row_reachable(data) {
            compare(UnitTheme.override({ stack: { titleSpace: data.lines }, motion: { scale: 0 } }), "ok");
            const made = createTemporaryObject(titledSources, root, { maximumHeight: data.cap });
            waitForRendering(made);
            const view = made.scrollArea;
            const last = made.rows.itemAt(made.rows.count - 1);
            compare(view.overflowing, data.cap > 0);
            if (data.cap > 0) {
                verify(view.bar.visible);
                view.contentY = view.contentHeight - view.height;
                verify(view.contentY > 0);
            }
            const rowTop = last.mapToItem(view, 0, 0).y;
            verify(rowTop >= made.ringRoom - 0.5, "the last source row starts inside the viewport");
            verify(rowTop + last.height <= view.height - made.ringRoom + 0.5, "the last source row ends inside the viewport");
            const footer = footerSlot(made);
            compare(footer.y + footer.height, made.height - made.contentInset);
        }

        function test_an_external_footer_stays_pinned_and_dies_with_its_section() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const holder = createTemporaryObject(footerHolder, root);
            const section = mountedSection.createObject(root);
            holder.section = section;
            const bar = section.footer;
            holder.rememberedFooter = bar;
            compare(bar.parent, footerSlot(holder));
            verify(bar.parent !== body(holder));
            compare(holder.footerHeight, 0);
            compare(holder.footerGap, 0);
            section.dirty = true;
            tryCompare(bar, "drawn", true);
            verify(holder.footerHeight > 0);
            compare(bar.width, holder.contentWidth);
            const bottom = bar.mapToItem(holder, 0, bar.height).y;
            compare(bottom, holder.height - holder.contentInset);
            scroll(holder).contentY = 100;
            compare(bar.mapToItem(holder, 0, bar.height).y, bottom);
            section.dirty = false;
            tryCompare(holder, "footerHeight", 0);
            compare(holder.footerGap, 0);
            section.destroy();
            tryCompare(holder, "section", null);
            tryCompare(holder, "rememberedFooter", null);
            compare(footerSlot(holder).children.length, 0);
        }

        function test_displays_returns_the_keyboard_when_its_footer_hides() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const holder = createTemporaryObject(footerHolder, root);
            const section = createTemporaryObject(displaysSection, root);
            holder.section = section;
            const bar = section.footer;
            compare(bar.parent, footerSlot(holder));
            section.outputDraft = { test: { scale: 2 } };
            tryCompare(bar, "drawn", true);
            const actions = bar.children.find(child => child.children.some(button => button.text === "Save"));
            const save = actions.children.find(button => button.text === "Save");
            save.forceActiveFocus(Qt.TabFocusReason);
            verify(bar.activeFocus);
            section.outputDraft = ({});
            tryCompare(section.initialFocus, "activeFocus", true);
            verify(!bar.activeFocus);
            tryCompare(holder, "footerHeight", 0);
        }

        function test_header_body_and_footer_share_the_content_edge() {
            compare(pane.contentInset, Theme.inset.window);
            compare(headerSlot(pane).x, pane.contentInset);
            compare(headerSlot(pane).y, pane.contentInset);
            compare(headerSlot(pane).width, pane.width - 2 * pane.contentInset);
            // The body sits on the content edge; the viewport reaches the
            // ring's room past it.
            compare(body(pane).mapToItem(pane, 0, 0).x, pane.contentInset);
            compare(body(pane).width, pane.width - 2 * pane.contentInset);
            compare(scroll(pane).x, pane.contentInset - pane.ringRoom);
            compare(footerSlot(pane).x, pane.contentInset);
            compare(footerSlot(pane).y, scroll(pane).y + scroll(pane).height - pane.ringRoom + pane.footerGap);
            compare(footerSlot(pane).width, pane.width - 2 * pane.contentInset);
        }

        function test_container_sets_the_header_to_body_gap() {
            const windowPane = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 240; height: 160; container: "window"; header: [ Item { width: 10; height: 20 } ]\nItem { width: parent.width; height: 20 } }', root, "windowPane");
            const panelPane = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 240; height: 160; container: "panel"; header: [ Item { width: 10; height: 20 } ]\nItem { width: parent.width; height: 20 } }', root, "panelPane");
            compare(windowPane.gap, Theme.stack.section);
            compare(panelPane.gap, Theme.stack.group);
            compare(scroll(windowPane).y + windowPane.ringRoom - (headerSlot(windowPane).y + headerSlot(windowPane).height), Theme.stack.section);
            compare(scroll(panelPane).y + panelPane.ringRoom - (headerSlot(panelPane).y + headerSlot(panelPane).height), Theme.stack.group);
            windowPane.destroy();
            panelPane.destroy();
        }

        function test_container_sets_the_gap_between_body_blocks() {
            const windowPane = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 240; height: 160; container: "window"\nItem { width: parent.width; height: 20 }\nItem { width: parent.width; height: 20 } }', root, "windowBody");
            const panelPane = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 240; height: 160; container: "panel"\nItem { width: parent.width; height: 20 }\nItem { width: parent.width; height: 20 } }', root, "panelBody");
            waitForRendering(windowPane);
            waitForRendering(panelPane);
            compare(body(windowPane).children[1].y - body(windowPane).children[0].height, Theme.stack.page);
            compare(body(panelPane).children[1].y - body(panelPane).children[0].height, Theme.stack.group);
            windowPane.destroy();
            panelPane.destroy();
        }

        function test_title_row_draws_an_h3_title_at_the_content_edge() {
            const made = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 240; container: "panel"; fitToContent: true; title: "Bluetooth"\nItem { width: parent.width; height: 20 } }', root, "titleOnly");
            const label = titleLabel(made);
            compare(label.text, "Bluetooth");
            compare(label.role, "h3");
            compare(label.mapToItem(made, 0, 0).x, made.contentInset);
            compare(label.y, label.topForCapCenter(titleRow(made).height));
            compare(made.headerSwitch, null);
            compare(made.headerHeight, titleRow(made).height);
            verify(body(made).mapToItem(made, 0, 0).y >= made.contentInset + made.headerHeight + made.headerGap, "the body starts below the title row");
            made.destroy();
        }

        function test_header_slot_sits_under_the_title_row() {
            const made = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 240; container: "panel"; fitToContent: true; title: "Agents"; header: [ Label { role: "body"; text: "Agent Warden is starting."; width: parent.width } ]\nItem { width: parent.width; height: 20 } }', root, "titleWithHeader");
            compare(headerSlot(made).y, made.contentInset + titleRow(made).height + Theme.stack.titleSpace);
            compare(headerSlot(made).children[0].text, "Agent Warden is starting.");
            compare(made.headerHeight, titleRow(made).height + Theme.stack.titleSpace + headerSlot(made).implicitHeight);
            made.destroy();
        }

        function test_title_switch_sits_at_the_content_edge_and_keeps_its_binding() {
            const made = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 240; container: "panel"; fitToContent: true; title: "Bluetooth"; switchShown: true; property var toggles: []\nonSwitchToggled: checked => toggles = toggles.concat([checked])\nItem { width: parent.width; height: 20 } }', root, "titleSwitch");
            const toggle = made.headerSwitch;
            verify(toggle !== null && toggle.visible, "the switch shows");
            compare(toggle.mapToItem(made, 0, 0).x + toggle.width, made.contentInset + made.contentWidth);
            compare(toggle.mapToItem(made, 0, 0).y + toggle.height / 2, made.contentInset + titleRow(made).height / 2);
            verify(titleLabel(made).width <= toggle.mapToItem(made, 0, 0).x - made.contentInset - Theme.stack.inline, "the title leaves the switch room");
            mouseClick(toggle);
            compare(made.toggles, [true]);
            compare(toggle.checked, false);
            made.switchChecked = true;
            compare(toggle.checked, true);
            made.destroy();
        }

        function switchLabel(of) { return titleRow(of).children[2]; }

        // A switch that controls less than the title names says what it
        // controls at its left; one that controls the titled feature, or
        // no switch at all, draws no label.
        function test_switch_label_shows_only_when_the_switch_names_another_thing_data() {
            return [
                { tag: "names another thing", title: "Network", name: "Wi-Fi", shown: true, labelled: true },
                { tag: "names the title", title: "Bluetooth", name: "Bluetooth", shown: true, labelled: false },
                { tag: "no switch", title: "Network", name: "Wi-Fi", shown: false, labelled: false },
            ];
        }

        function test_switch_label_shows_only_when_the_switch_names_another_thing(data) {
            const made = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 240; container: "panel"; fitToContent: true\nItem { width: parent.width; height: 20 } }', root, "switchLabel");
            made.title = data.title;
            made.switchName = data.name;
            made.switchShown = data.shown;
            const label = switchLabel(made);
            compare(label.visible, data.labelled);
            if (data.labelled) {
                const toggle = made.headerSwitch;
                compare(label.text, data.name);
                compare(label.role, "hint");
                compare(label.x + label.width + Theme.stack.inline, toggle.mapToItem(titleRow(made), 0, 0).x);
                verify(titleLabel(made).width <= label.x - Theme.stack.inline, "the title leaves the label room");
            }
            made.destroy();
        }

        function test_title_switch_sits_beside_the_settings_gear() {
            const host = settingsHost.createObject(root);
            const of = host.titled;
            const toggle = of.headerSwitch;
            const button = gear(of);
            verify(toggle !== null && button !== null, "the switch and gear show");
            compare(toggle.mapToItem(of, 0, 0).x + toggle.width + Theme.stack.inline, button.mapToItem(of, 0, 0).x);
            compare(button.mapToItem(of, 0, 0).y + button.height / 2, of.contentInset + titleRow(of).height / 2);
            compare(toggle.mapToItem(of, 0, 0).y + toggle.height / 2, of.contentInset + titleRow(of).height / 2);
            host.destroy();
        }

        function test_keyboard_scrolling_keeps_the_body_on_the_header_edges_data() {
            return [
                { tag: "pointer scrolling", keyboard: false, focused: false },
                { tag: "keyboard scrolling without focus", keyboard: true, focused: false },
                { tag: "focused keyboard scrolling", keyboard: true, focused: true },
                { tag: "body fits", keyboard: true, focused: true, rows: 1 },
                { tag: "narrow pane", keyboard: true, focused: true, width: 120 },
                { tag: "small pointer padding", keyboard: false, focused: false, smallPadding: true },
                { tag: "small keyboard padding", keyboard: true, focused: true, smallPadding: true },
                { tag: "wider gutter", keyboard: true, focused: true, gutterScale: 2 },
                { tag: "larger ring", keyboard: true, focused: true, ringScale: 2 },
            ];
        }

        function test_keyboard_scrolling_keeps_the_body_on_the_header_edges(data) {
            if (data.gutterScale)
                compare(UnitTheme.override({ scrollArea: { gutter: Theme.scrollArea.gutter * data.gutterScale } }), "ok");
            if (data.ringScale)
                compare(UnitTheme.override({ focusRing: { width: Theme.focusRing.width * data.ringScale, offset: Theme.focusRing.offset * data.ringScale } }), "ok");
            const made = scrolledPanel.createObject(root);
            if (data.width) made.width = data.width;
            if (data.rows) made.rowCount = data.rows;
            if (data.smallPadding) made.padding = Theme.space.xs;
            const view = made.scrollArea;
            view.keyboardScroll = data.keyboard;
            if (data.focused) view.focusProxy.forceActiveFocus(Qt.TabFocusReason);
            waitForRendering(made);
            const column = body(made);
            const head = headerSlot(made);
            tryCompare(column, "width", head.width);
            const left = column.mapToItem(made, 0, 0).x;
            compare(left, head.x);
            compare(left + column.width, head.x + head.width);
            compare(left, made.width - left - column.width, "both body insets are equal");
            const viewportLeft = view.mapToItem(made, 0, 0).x;
            verify(viewportLeft >= 0, "the viewport starts inside the pane");
            verify(viewportLeft + view.width <= made.width, "the viewport ends inside the pane");
            const barLeft = view.bar.mapToItem(made, 0, 0).x;
            verify(barLeft >= left + column.width, "the bar stays past the body's right edge");
            verify(barLeft + view.bar.width <= made.width, "the bar stays inside the pane");
            compare(view.overflowing, data.rows !== 1);
            if (data.focused) verify(view.focusProxy.visualFocus, "the viewport shows keyboard focus");
            made.destroy();
        }

        function test_scroll_bar_sits_inside_the_right_inset_strip() {
            const contentRight = body(pane).mapToItem(pane, 0, 0).x + body(pane).width;
            const insetRight = pane.width - pane.contentInset;
            compare(contentRight, insetRight);
            verify(scroll(pane).bar.x + scroll(pane).x >= contentRight, "bar starts in the right inset strip");
            verify(scroll(pane).bar.x + scroll(pane).bar.width + scroll(pane).x <= pane.width, "bar stays inside the pane");
        }

        // A bare header label sizes the header slot by its implicit width,
        // beside a footer bound to the content width, with no binding loop:
        // the runner fails a file that logs one.
        function test_a_bare_header_beside_a_footer_loops_nothing() {
            const made = overTarget.createObject(root);
            const label = headerSlot(made.pane).children[0];
            const footer = footerSlot(made.pane).children[0];
            compare(headerSlot(made.pane).implicitWidth, label.implicitWidth);
            tryCompare(footer, "width", made.pane.contentWidth);
            compare(footerSlot(made.pane).implicitWidth, footer.implicitWidth);
            made.destroy();
        }

        // The body fits, so a press on its empty part, 10 px above the
        // viewport's bottom, reaches the target under the pane.
        function test_a_press_on_a_body_that_fits_reaches_what_lies_under_it() {
            const made = overTarget.createObject(root);
            tryVerify(() => made.pane.bodyContentHeight > 72, 1000, "the body is laid out");
            verify(!made.pane.scrollArea.overflowing, "the body fits");
            const view = made.pane.scrollArea;
            mouseClick(made, 120, view.mapToItem(made, 0, view.height - made.pane.ringRoom - 10).y);
            compare(made.spy.count, 1);
            made.destroy();
        }

        // The body's room at the cap: 300 less 12 inset twice, the 20 px
        // header, the 30 px footer and a 12 px gap after the header and
        // before the footer is 300 - 24 - 20 - 30 - 24 = 202. A body that
        // takes it fills the pane to its cap and does not scroll.
        function test_a_body_sized_from_its_room_fills_the_pane_to_its_cap() {
            const made = filled.createObject(root);
            compare(made.bodyRoom, 202);
            tryCompare(made, "bodyContentHeight", 202);
            compare(made.height, 300);
            verify(!made.scrollArea.overflowing, "the filled body does not scroll");
            compare(made.scrollArea.interactive, false);
            made.destroy();
        }

        function test_fit_to_content_caps_the_body() {
            compare(fitted.implicitHeight, 120);
            compare(fitted.scrollArea.height, 120 - 2 * fitted.contentInset - headerSlot(fitted).height - fitted.headerGap + 2 * fitted.ringRoom);
            verify(fitted.scrollArea.overflowing, "the capped pane scrolls its body");
        }

        // A 4 px pad under a 20 px corner: the content's top stands 4 in,
        // dy = 20 - 4 = 16 and reach = 20 - 4 = 16, so the corner stays one
        // step inside the curve only at 20 - sqrt(16^2 - 16^2) = 20.
        function test_radius_sets_the_effective_inset_floor() {
            compare(UnitTheme.override({ radius: { md: 20 }, inset: { window: 4 } }), "ok");
            const expected = 20;
            tryCompare(pane, "contentInset", expected);
            compare(body(pane).width, pane.width - 2 * expected);
            compare(UnitTheme.override({ radius: { md: 0 }, inset: { window: 18 } }), "ok");
            tryCompare(pane, "contentInset", 18);
            compare(body(pane).width, pane.width - 36);
        }

        function test_header_and_footer_keep_one_gap_when_the_body_is_empty() {
            compare(emptyBody.bodyContentHeight, 0);
            compare(footerSlot(emptyBody).y, headerSlot(emptyBody).y + headerSlot(emptyBody).height + emptyBody.gap);
            compare(emptyBody.implicitHeight, 2 * emptyBody.contentInset + headerSlot(emptyBody).height + emptyBody.gap + footerSlot(emptyBody).height);
            compare(hiddenBody.bodyContentHeight, 0);
            compare(footerSlot(hiddenBody).y, headerSlot(hiddenBody).y + headerSlot(hiddenBody).height + hiddenBody.gap);
            compare(hiddenBody.implicitHeight, 2 * hiddenBody.contentInset + headerSlot(hiddenBody).height + hiddenBody.gap + footerSlot(hiddenBody).height);
        }

        // A plugin that owns its look hands its own padding and radius.
        function test_explicit_padding_and_radius_win() {
            const padding = Theme.scrollArea.gutter + Theme.border.thin;
            emptyBody.padding = padding;
            compare(emptyBody.contentInset, padding);
            compare(headerSlot(emptyBody).x, padding);
            emptyBody.cornerRadius = 40;
            tryVerify(() => emptyBody.contentInset > padding, 1000, "a rounded explicit corner moves the content in");
            emptyBody.padding = Qt.binding(() => emptyBody.paddingOf(emptyBody.container));
            emptyBody.cornerRadius = Qt.binding(() => emptyBody.radiusOf(emptyBody.container));
        }

        // The divider under the header shows while the body is scrolled.
        function test_the_header_divider_shows_while_scrolled() {
            compare(divider(pane).visible, false);
            scroll(pane).contentY = 20;
            compare(divider(pane).visible, true);
            verify(divider(pane).y >= headerSlot(pane).y + headerSlot(pane).height && divider(pane).y + divider(pane).height <= body(pane).mapToItem(pane, 0, 0).y + scroll(pane).contentY, "the divider sits in the header gap");
            scroll(pane).contentY = 0;
            compare(divider(pane).visible, false);
        }

        // A host shorter than the fitted height keeps the footer inside
        // the box it gives: the body shrinks and scrolls, and the pane
        // still asks for its fitted height.
        function test_a_short_host_keeps_the_footer_inside() {
            verify(held.cappedHeight > held.height, "the fixture is held short");
            compare(held.implicitHeight, held.cappedHeight);
            const foot = footerSlot(held);
            verify(foot.y + foot.height <= held.height - held.contentInset + 0.5, "footer ends at " + (foot.y + foot.height) + " in a " + held.height + " box");
            verify(scroll(held).contentHeight > scroll(held).height, "the body scrolls");
        }

        // The divider over the footer shows while more of the body lies
        // below the view, and sits in the footer gap.
        function test_the_footer_divider_shows_while_more_lies_below() {
            verify(scroll(pane).contentHeight > scroll(pane).height, "the fixture overflows");
            scroll(pane).contentY = 0;
            compare(footerDivider(pane).visible, true);
            verify(footerDivider(pane).y >= scroll(pane).y + scroll(pane).height - pane.ringRoom && footerDivider(pane).y + footerDivider(pane).height <= footerSlot(pane).y, "the divider sits in the footer gap");
            scroll(pane).contentY = scroll(pane).contentHeight - scroll(pane).height;
            compare(footerDivider(pane).visible, false);
            scroll(pane).contentY = 0;
        }

        // A focus ring around a row on the content's left and top edges
        // lies inside the viewport, so the scroll area's clip keeps it.
        function test_a_ring_on_the_content_edge_stays_in_the_viewport() {
            const row = body(pane).children[0];
            const ringLeft = row.mapToItem(scroll(pane), -Theme.focusRing.offset - Theme.focusRing.width, 0).x;
            const ringTop = row.mapToItem(scroll(pane), 0, -Theme.focusRing.offset - Theme.focusRing.width).y;
            verify(ringLeft >= 0, "the ring's left edge " + ringLeft + " is inside the viewport");
            verify(ringTop >= 0, "the ring's top edge " + ringTop + " is inside the viewport");
        }

        // An overlay draws no container: its content sits inset.overlay,
        // 32, in. With a requested 4 px pad, a 30 px corner moves nothing:
        // there is no corner to clear, only the scrollbar gutter.
        function test_an_overlay_sits_its_inset_in_and_clears_no_corner() {
            const made = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 300; height: 200; container: "overlay"; header: [ Item { width: 10; height: 10 } ] }', root, "overlay");
            compare(made.cornerRadius, 0);
            tryCompare(made, "contentInset", 32);
            compare(UnitTheme.override({ radius: { md: 30 }, inset: { overlay: 4 } }), "ok");
            tryCompare(made, "cornerRadius", 0);
            tryCompare(made, "contentInset", Theme.scrollArea.gutter);
            compare(made.contentInset, Theme.scrollArea.gutter);
            made.destroy();
        }

        // Both dividers, shown at once, are one line: the divider's 1 px
        // thickness, from the frame's border on one side to the other. A
        // window's frame is Hyprland's, so its lines run edge to edge; a
        // panel's Surface draws a 1 px border, and a theme's 3 px border
        // moves both lines in with it.
        function test_both_dividers_meet_the_frame_alike() {
            const panel = scrolledPanel.createObject(root);
            const rows = [["window", pane, 0], ["panel", panel, 1]];
            for (const [name, of, border] of rows) {
                tryVerify(() => scroll(of).contentHeight > scroll(of).height + 40, 1000, name + " overflows");
                scroll(of).contentY = 20;
                const lines = [divider(of), footerDivider(of)];
                for (const line of lines) {
                    verify(line.visible, name + " shows both dividers");
                    compare(line.x, border, name + " divider x");
                    compare(line.width, of.width - 2 * border, name + " divider width");
                    compare(line.height, 1, name + " divider thickness");
                }
                scroll(of).contentY = 0;
            }
            compare(UnitTheme.override({ surface: { border: 3 } }), "ok");
            compare(divider(panel).x, 3);
            compare(footerDivider(panel).width, panel.width - 6);
            panel.destroy();
        }

        // Inside a host that names a Settings page, the gear shows at the
        // header's end: the header is the content width less the gear's
        // 24 px box and the 8 px inline gap, and the gear ends on the
        // content edge. A click, Space and Return each ask the host once;
        // the gear is a Tab stop. A pane nested in the body draws none.
        function test_the_gear_opens_the_hosts_settings_page() {
            const host = settingsHost.createObject(root);
            const of = host.pane;
            const button = gear(of);
            verify(button !== null && button.visible, "the gear shows");
            compare(of.headerWidth, of.contentWidth - 32);
            compare(headerSlot(of).width, of.headerWidth);
            const at = button.mapToItem(of, 0, 0);
            verify(at.x >= of.contentInset + of.headerWidth, "the gear sits after the header");
            compare(at.x + button.width, of.contentInset + of.contentWidth);
            compare(at.y, of.contentInset);
            verify((button.focusPolicy & Qt.TabFocus) !== 0, "the gear takes Tab");
            mouseClick(button);
            compare(host.opened, 1);
            button.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(host.opened, 2);
            keyClick(Qt.Key_Return);
            compare(host.opened, 3);
            compare(gear(host.nested), null, "a nested pane holds no gear");
            compare(host.nested.headerWidth, host.nested.contentWidth);
            host.destroy();
        }

        // A host that names no page, and a pane with no host, hold no gear
        // and give the header the whole content width.
        function test_no_named_page_draws_no_gear() {
            compare(gear(pane), null, "a pane with no host holds no gear");
            compare(pane.headerWidth, pane.contentWidth);
            const host = settingsHost.createObject(root);
            host.settingsPage = "";
            compare(gear(host.pane), null, "a host that names no page holds no gear");
            compare(host.pane.headerWidth, host.pane.contentWidth);
            host.destroy();
        }

        // A pane with no header still keeps the gear's row: the body starts
        // a gap below it.
        function test_the_gear_keeps_its_row_without_a_header() {
            const host = settingsHost.createObject(root);
            const of = host.bare;
            verify(gear(of) !== null && gear(of).visible, "the gear shows");
            compare(of.headerHeight, gear(of).height);
            // The body's column lays out on the next polish.
            tryVerify(() => of.bodyContentHeight > 0, 1000, "the body is laid out");
            verify(body(of).mapToItem(of, 0, 0).y >= gear(of).mapToItem(of, 0, 0).y + gear(of).height + of.gap, "the body starts below the gear");
            host.destroy();
        }

        function test_dialog_padding_token_sets_the_dialog_container_inset() {
            compare(UnitTheme.override({ dialog: { padding: 31 } }), "ok");
            compare(emptyBody.contentInset, 31);
            compare(headerSlot(emptyBody).x, 31);
            compare(UnitTheme.override({ inset: { dialog: 27 } }), "ok");
            compare(Theme.dialog.padding, 27);
            compare(emptyBody.contentInset, 27);
            compare(headerSlot(emptyBody).x, 27);
        }
    }
}
