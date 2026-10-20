import QtQuick
import QtTest
import qs.Commons
import qs.Ui

Item {
    id: root
    width: 440
    height: 440

    Button { id: before; text: "Before" }
    SectionHeader {
        id: plain
        y: 60
        width: 260
        text: "Keys"
        description: "Select a shortcut and press its new keys"
    }
    Label {
        id: oldDescription
        visible: false
        width: plain.bodyWidth
        role: "hint"
        text: plain.description
        wrapMode: Text.Wrap
    }
    Section {
        id: linked
        y: 150
        width: 260
        title: "Pads"
        description: "Each pad holds one app. Set its key under [Keys](page:vgs.scratchpads/Settings)."
    }
    Button { id: after; y: 280; text: "After" }
    Section {
        id: titled
        x: 280
        width: 150
        title: "Profiles"
        info: "Which profiles connect."
        infoTitle: "What VGS can connect"
    }
    Section {
        id: untitled
        x: 280
        y: 80
        width: 150
        title: "Pads"
        info: "Each pad holds one app."
    }
    SignalSpy { id: headerPages; target: linked.children[0]; signalName: "pageActivated" }
    SignalSpy { id: sectionPages; target: linked; signalName: "pageActivated" }

    function descriptionOf(header) { return header.children[1]; }
    function labelOf(link) { return link.children[0]; }
    function infoButtonOf(item) {
        for (const child of item.children) {
            if ("infoOpen" in child) return child;
            const nested = infoButtonOf(child);
            if (nested !== null) return nested;
        }
        return null;
    }
    function focusRingOf(item) {
        for (const child of item.children) {
            if (child.toString().indexOf("FocusRing") === 0) return child;
            const nested = focusRingOf(child);
            if (nested !== null) return nested;
        }
        return null;
    }

    TestCase {
        name: "sectionheader"
        when: windowShown

        function init() {
            headerPages.clear();
            sectionPages.clear();
        }

        function test_plain_description_keeps_label_metrics_data() {
            return [
                { tag: "one line", text: "Tools this plugin needs", width: 360 },
                { tag: "wrapped", text: "Select a shortcut and press its new keys", width: 180 }
            ];
        }
        function test_plain_description_keeps_label_metrics(data) {
            plain.description = data.text;
            plain.width = data.width;
            const description = descriptionOf(plain);
            const label = labelOf(description);
            tryCompare(description, "height", oldDescription.height);
            compare(label.font.family, oldDescription.font.family);
            compare(label.font.pixelSize, oldDescription.font.pixelSize);
            compare(label.font.weight, oldDescription.font.weight);
            compare(label.font.letterSpacing, oldDescription.font.letterSpacing);
            compare(label.color, oldDescription.color);
            compare(label.width, oldDescription.width);
            compare(label.wrapMode, oldDescription.wrapMode);
            compare(label.lineHeight, oldDescription.lineHeight);
            compare(label.lineHeightMode, oldDescription.lineHeightMode);
            compare(label.lineCount, oldDescription.lineCount);
            compare(description.activeFocusOnTab, false);
        }
        function test_description_link_activates_by_pointer() {
            const link = descriptionOf(linked.children[0]);
            tryVerify(() => link.underlined.length > 0);
            const span = link.underlined[0];
            mouseClick(link, (span.left + span.right) / 2, (span.line + 0.5) * link.linePitch);
            compare(headerPages.count, 1);
            compare(sectionPages.count, 1);
            compare(sectionPages.signalArguments[0][0], "vgs.scratchpads");
            compare(sectionPages.signalArguments[0][1], "Settings");
        }
        // The info dialog takes the section's info title, else its title.
        function test_info_dialog_title() {
            const named = infoButtonOf(titled);
            verify(named !== null);
            compare(named.title, titled.infoTitle);
            const plainInfo = infoButtonOf(untitled);
            verify(plainInfo !== null);
            compare(plainInfo.title, untitled.title);
        }
        function test_description_link_is_in_tab_order_with_focus_ring() {
            const link = descriptionOf(linked.children[0]);
            before.forceActiveFocus(Qt.OtherFocusReason);
            keyClick(Qt.Key_Tab);
            tryCompare(link, "activeFocus", true);
            compare(descriptionOf(plain).activeFocus, false);
            const ring = focusRingOf(link);
            verify(ring !== null);
            tryCompare(ring, "visible", true);
            keyClick(Qt.Key_Return);
            compare(headerPages.count, 1);
            compare(sectionPages.count, 1);
            keyClick(Qt.Key_Tab);
            tryCompare(after, "activeFocus", true);
        }
    }
}
