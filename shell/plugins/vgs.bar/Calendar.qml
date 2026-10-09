import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// The calendar the bar clock opens under itself, the bar's panel: the
// month and year, Previous and Next month buttons, and Qt's own weekday
// row and month grid in the system locale, today filled in its own month
// alone. It opens on this month every time; Left and Right switch the
// month, and Escape, a click outside or a second click on the clock close
// it. A click on a day of the shown month opens that day in the web
// calendar the `calendarUrl` setting names, through the default browser,
// and closes the calendar; Enter opens today, or the 1st of another shown
// month. The day buttons take no Tab stop, so Tab moves between the two
// month buttons alone. Qt's month grid model holds six weeks for every
// month, 42 days, the days of the months around it drawn disabled, so the
// calendar's height never changes (Qt's own Basic MonthGrid.qml lays its
// `source` out as 6 rows of 7, qtdeclarative 6.11).
Item {
    id: root

    property var shell: null
    property Item initialFocus: root

    // Today, read apart so the month grid's cells change only at midnight,
    // not on every tick of the clock.
    readonly property int todayYear: Time.now.getFullYear()
    readonly property int todayMonth: Time.now.getMonth()
    readonly property int todayDay: Time.now.getDate()

    // The month the calendar shows, as Qt's month grid counts it: January
    // is month 0.
    property int shownYear: todayYear
    property int shownMonth: todayMonth

    function open(payloadJson) {
        shownYear = todayYear;
        shownMonth = todayMonth;
    }
    function close() {}
    function showMonth(delta) {
        const first = new Date(shownYear, shownMonth + delta, 1);
        shownYear = first.getFullYear();
        shownMonth = first.getMonth();
    }
    // Today in this month, else the shown month's 1st.
    function openShownDay() {
        const thisMonth = shownYear === todayYear && shownMonth === todayMonth;
        openDay(shownYear, shownMonth, thisMonth ? todayDay : 1);
    }
    // MONTH counts from 0, as the grid does; the address counts from 1.
    function openDay(year, month, day) {
        const url = String(shell.settings.calendarUrl).replace(/\{year\}/g, year).replace(/\{month\}/g, month + 1).replace(/\{day\}/g, day);
        const reply = shell.run.detached(DesktopLaunch.open(url));
        if (reply !== "ok") {
            console.warn("vgs.bar: calendar open " + reply);
            return;
        }
        shell.surfaces.hide("panel");
    }

    implicitWidth: Theme.size.panel.sm
    implicitHeight: layout.implicitHeight
    // Qt hands a key an item does not accept to its parent, so Left and
    // Right reach the calendar from a focused month button.
    Keys.onLeftPressed: root.showMonth(-1)
    Keys.onRightPressed: root.showMonth(1)
    Keys.onReturnPressed: root.openShownDay()
    Keys.onEnterPressed: root.openShownDay()

    Surface {
        anchors.fill: parent
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        // The month row is the header, so the Settings gear the panel host
        // adds sits at its end, not on a row of its own.
        header: [
            Row {
                width: layout.headerWidth
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
        ]

        Column {
            id: page
            readonly property real cellHeight: Theme.size.control.sm

            width: layout.contentWidth
            spacing: Theme.space.sm

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
                // Qt's month grid takes Tab focus by default
                // (QQuickMonthGrid, qtdeclarative 6.11); the calendar is
                // one composite whose keys are the page's, so it takes none.
                activeFocusOnTab: false
                month: root.shownMonth
                year: root.shownYear
                // keyboard-path: Enter on the calendar opens today, or the 1st of the shown month
                delegate: Button {
                    // The roles of Qt's month grid model.
                    required property int day
                    required property int month
                    required property int year
                    readonly property bool inMonth: month === grid.month
                    readonly property bool today: inMonth && year === root.todayYear && month === root.todayMonth && day === root.todayDay

                    size: "sm"
                    focusPolicy: Qt.NoFocus
                    text: String(day)
                    variant: today ? "primary" : "ghost"
                    enabled: inMonth
                    onClicked: root.openDay(year, month, day)
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
