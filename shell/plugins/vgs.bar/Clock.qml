import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Date and time from the shared clock, in the bar's `clockFormat`, on a bar
// item at the bar's vertical centre, where the workspace pills sit. The
// shared clock ticks once a second only while some format on some screen
// shows seconds.
//
// A click opens the calendar under it, in the shared popover: the month and
// year, Previous and Next month buttons, and Qt's own weekday row and month
// grid in the system locale, today marked in its own month alone. It opens
// on this month every time; Left and Right switch the month and Escape or a
// second click closes it. Qt's month grid model holds six weeks for every
// month, 42 days, the days of the months around it drawn muted, so the
// calendar's height never changes (Qt's own Basic MonthGrid.qml lays its
// `source` out as 6 rows of 7, qtdeclarative 6.11).
Item {
    id: root

    // The bar, read for its `shell` alone; it goes before its built-ins when
    // a screen goes away, so the read is null-checked.
    required property Item bar
    readonly property string format: bar && bar.shell !== null ? String(bar.shell.settings.clockFormat) : ""

    // A quoted literal such as 'secs' is not a seconds field.
    readonly property bool showsSeconds: format.replace(/'[^']*'/g, "").indexOf("s") !== -1
    onShowsSecondsChanged: Time.holdSeconds(root, root.showsSeconds)
    Component.onCompleted: Time.holdSeconds(root, root.showsSeconds)
    Component.onDestruction: Time.holdSeconds(root, false)

    // Today, read apart so the month grid's cells change only at midnight,
    // not on every tick of the clock.
    readonly property int todayYear: Time.now.getFullYear()
    readonly property int todayMonth: Time.now.getMonth()
    readonly property int todayDay: Time.now.getDate()

    // The month the calendar shows, as Qt's month grid counts it: January
    // is month 0.
    property int shownYear: todayYear
    property int shownMonth: todayMonth

    function openCalendar() {
        shownYear = todayYear;
        shownMonth = todayMonth;
        // A pointer opens it: Qt raises visualFocus for a keyboard focus
        // reason alone, so the first button takes focus without a ring.
        calendar.open(Qt.MouseFocusReason);
    }
    function showMonth(delta) {
        const first = new Date(shownYear, shownMonth + delta, 1);
        shownYear = first.getFullYear();
        shownMonth = first.getMonth();
    }

    implicitWidth: button.width
    implicitHeight: Theme.bar.height

    BarItem {
        id: button
        anchors.centerIn: parent
        text: Qt.formatDateTime(Time.now, root.format)
        tone: Theme.bar.foreground
        active: calendar.opened
        onClicked: root.openCalendar()

        Popover {
            id: calendar
            width: Theme.size.panel.sm

            Column {
                id: page
                readonly property real cellHeight: Theme.size.control.sm

                width: parent.width
                spacing: Theme.space.sm
                // Qt hands a key an item does not accept to its parent, so
                // Left and Right reach the page from the focused month button.
                Keys.onLeftPressed: root.showMonth(-1)
                Keys.onRightPressed: root.showMonth(1)

                Row {
                    width: parent.width
                    spacing: Theme.space.xs
                    IconButton { id: previous; iconName: "chevron-left"; label: "Previous month"; onClicked: root.showMonth(-1) }
                    Label {
                        objectName: "calendarTitle"
                        role: "bodyStrong"
                        text: grid.locale.standaloneMonthName(root.shownMonth, Locale.LongFormat) + " " + root.shownYear
                        width: parent.width - previous.width - next.width - 2 * parent.spacing
                        horizontalAlignment: Text.AlignHCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    IconButton { id: next; iconName: "chevron-right"; label: "Next month"; onClicked: root.showMonth(1) }
                }

                // Both Qt controls take their height from tokens, not from
                // their content: a popup takes the size of its first frame,
                // and a control sized by its content item reaches its height
                // only on a later one. Each sizes its own cells to share its
                // width, and the grid its height, gapped by its `spacing`
                // (read back in the sandbox, qtdeclarative 6.11).
                T.AbstractDayOfWeekRow {
                    id: weekdays
                    width: parent.width
                    implicitHeight: page.cellHeight
                    spacing: Theme.space.xs
                    locale: grid.locale
                    delegate: Label {
                        required property string shortName
                        role: "label"
                        text: shortName
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    contentItem: Row {
                        spacing: weekdays.spacing
                        Repeater { model: weekdays.source; delegate: weekdays.delegate }
                    }
                }

                T.AbstractMonthGrid {
                    id: grid
                    width: parent.width
                    implicitHeight: 6 * page.cellHeight + 5 * spacing
                    spacing: Theme.space.xs
                    month: root.shownMonth
                    year: root.shownYear
                    delegate: Rectangle {
                        id: cell
                        // The roles of Qt's month grid model.
                        required property int day
                        required property int month
                        required property int year
                        readonly property bool inMonth: month === grid.month
                        readonly property bool today: inMonth && year === root.todayYear && month === root.todayMonth && day === root.todayDay
                        readonly property string text: String(day)

                        objectName: "calendarDay"
                        radius: Theme.radius.md
                        color: today ? Theme.color.accent : "transparent"

                        Label {
                            anchors.centerIn: parent
                            role: "body"
                            text: cell.text
                            color: cell.today ? Theme.color.onAccent : cell.inMonth ? Theme.color.text : Theme.color.textMuted
                        }
                    }
                    contentItem: Grid {
                        rows: 6
                        columns: 7
                        rowSpacing: grid.spacing
                        columnSpacing: grid.spacing
                        Repeater { model: grid.source; delegate: grid.delegate }
                    }
                }
            }
        }
    }
}
