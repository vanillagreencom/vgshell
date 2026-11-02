import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// The message pattern keeps its source link separate from response
// buttons, preserves small secondary controls and their disabled reason,
// and wraps long content. Unread badges retain full accessible counts.
Item {
    id: scene
    width: 640
    height: 900

    MessageRow {
        id: message
        width: 540
        sender: "Owner"
        timeText: "10:41 am"
        initials: "O"
        title: "Review the change"
        bodyText: "First idea.\nSecond idea."
        linkText: "Open the original request"
        stateText: "Needs reply"
        stateTone: "warning"
        actions: [{ id: "reply", label: "Reply" }, { id: "done", label: "Done" },
            { id: "later", label: "Later", disabledReason: "Choose a date first." }]
    }
    Badge { id: count; y: 400; variant: "unread"; text: "3" }
    Badge { id: largeCount; x: 40; y: 400; variant: "unread"; text: "120" }
    Tabs { id: tabs; y: 450; width: 540; model: ["Current", "Waiting"]; unreadCounts: ({ Waiting: "3" }) }
    ResultsFilter { id: filter; y: 510; accessibleLabel: "Records"; model: ["Every type", "Messages", "Tasks", "Problems"]; currentIndex: 0 }
    SignalSpy { id: actionSpy; target: message; signalName: "actionTriggered" }
    SignalSpy { id: linkSpy; target: message; signalName: "linkActivated" }
    SignalSpy { id: filterSpy; target: filter; signalName: "activated" }

    TestCase {
        name: "message_patterns"
        when: windowShown

        function init() {
            UnitTheme.reset();
            message.width = 540;
            message.bodyText = "First idea.\nSecond idea.";
            message.actions = [{ id: "reply", label: "Reply" }, { id: "done", label: "Done" },
                { id: "later", label: "Later", disabledReason: "Choose a date first." }];
            actionSpy.clear(); linkSpy.clear(); filterSpy.clear();
            filter.currentIndex = 0;
            tabs.currentIndex = 0;
            tabs.unreadCounts = ({ Waiting: "3" });
        }

        function allChildren(item) {
            let found = [];
            for (const child of item.children) found = found.concat([child], allChildren(child));
            return found;
        }

        function test_response_buttons_are_separate_and_disabled_actions_do_not_fire() {
            const reply = message.actionAt(0), done = message.actionAt(1), later = message.actionAt(2);
            compare(reply.variant, "secondary");
            compare(reply.size, "sm");
            compare(reply.height, Theme.size.control.sm);
            compare(done.x - reply.x - reply.width, Theme.stack.page);
            const linkBottom = message.linkControl.mapToItem(message, 0, message.linkControl.height).y;
            const buttonTop = reply.mapToItem(message, 0, 0).y;
            verify(buttonTop - linkBottom >= Theme.stack.inline);
            message.linkControl.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(linkSpy.count, 1);
            compare(actionSpy.count, 0);
            reply.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(actionSpy.count, 1);
            compare(actionSpy.signalArguments[0][0], message.actions[0].id);
            mouseClick(later);
            later.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(actionSpy.count, 1);
            compare(later.disabledReason, message.actions[2].disabledReason);
        }

        function test_message_preserves_plain_text_and_grows_for_wrapped_content() {
            const originalHeight = message.implicitHeight;
            message.bodyText = "<b>One long body that must remain plain text rather than markup.</b> ".repeat(6);
            message.width = 300;
            tryVerify(() => message.implicitHeight > originalHeight);
            const body = allChildren(message).find(item => item.text === message.bodyText);
            verify(body !== undefined);
            compare(body.textFormat, Text.PlainText);
            const firstInk = Math.min(...allChildren(message).filter(item => item.text === message.sender).map(item => item.mapToItem(message, 0, 0).y));
            verify(firstInk >= message.paddingY);
            const last = message.actionAt(message.actions.length - 1);
            const bottom = last.mapToItem(message, 0, last.height).y;
            verify(message.height - bottom >= message.paddingY);
        }

        function test_action_publication_keeps_focused_button_and_current_reason() {
            const reply = message.actionAt(0);
            reply.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(reply, "activeFocus", true);
            message.actions = [{ id: "done", label: "Done" },
                { id: "reply", label: "Reply again", disabledReason: "Reply is being sent." },
                { id: "later", label: "Later" }];
            tryVerify(() => message.actionAt(1) === reply);
            compare(reply.activeFocus, true);
            compare(reply.text, "Reply again");
            compare(reply.disabledReason, "Reply is being sent.");
            keyClick(Qt.Key_Return);
            compare(actionSpy.count, 0);
        }

        function test_unread_badges_are_circular_and_keep_the_full_accessible_count() {
            compare(count.width, count.height);
            compare(count.height, Theme.badge.size.sm.height);
            compare(count.radius, Theme.radius.full);
            compare(count.color, Qt.color(Theme.color.accent));
            compare(count.foreground, Qt.color(Theme.color.onAccent));
            compare(largeCount.displayedText, "99+");
            compare(largeCount.Accessible.name, largeCount.text);
            compare(largeCount.width, largeCount.height);
            compare(largeCount.height, Theme.size.control.sm);
        }

        function test_tab_count_follows_its_label_and_keeps_navigation() {
            const waiting = tabs.itemAt(1);
            compare(waiting.unreadCount, "3");
            const badge = allChildren(waiting).find(item => item.variant === "unread");
            verify(badge !== undefined && badge.visible);
            compare(badge.text, tabs.unreadCounts.Waiting);
            mouseClick(waiting);
            compare(tabs.currentIndex, 1);
            tabs.unreadCounts = ({ Waiting: "2" });
            compare(badge.text, "2");
        }

        function test_results_filter_has_a_name_without_a_visible_label() {
            compare(filter.Accessible.name, filter.accessibleLabel + ": " + filter.currentText);
            filter.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Down);
            compare(filter.currentIndex, 1);
            compare(filterSpy.count, 1);
            compare(filter.Accessible.name, filter.accessibleLabel + ": " + filter.currentText);
        }
    }
}
