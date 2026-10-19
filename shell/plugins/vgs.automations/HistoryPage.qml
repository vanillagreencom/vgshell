import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "AutomationsViewLogic.js" as View

// The run history, a section a day. Only the rows the body shows are
// built: every row is a two-line ListItem, `listItem.twoLineHeight` tall
// (ListItem's header), so a row's place follows from its index and a day
// takes its full height with no row built. A day's rows are a model of the
// shown rows' keys, so a new run, a scroll or a filter builds the rows that
// arrive and keeps every row that stays.
FocusScope {
    id: page

    required property Item panel
    property string filterId: ""
    property int current: 0
    readonly property var filterOptions: [{ id: "", label: "All automations" }].concat(panel.automations.map(a => ({ id: a.id, label: a.name })))
    readonly property var groups: panel.filteredHistoryGroups(filterId)
    readonly property var flatRows: {
        let out = [];
        for (const group of groups) out = out.concat(group.rows);
        return out;
    }
    readonly property real rowHeight: Theme.listItem.twoLineHeight
    readonly property real rowPitch: rowHeight + Theme.stack.row
    // Where the runs' item starts in the body's content. mapToItem is no
    // binding dependency; the item's own y is what moves.
    readonly property real runsTop: {
        runs.y;
        return runs.mapToItem(layout.scrollArea.contentItem, 0, 0).y;
    }
    // The part of the runs' item the body shows, in its own coordinates.
    readonly property real shownTop: layout.scrollArea.contentY - runsTop
    readonly property real shownBottom: shownTop + layout.scrollArea.height

    signal clearRequested(string id)
    signal openRequested(string transcript)

    focus: true

    function filterIndex() {
        const ids = filterOptions.map(option => option.id);
        return Math.max(0, ids.indexOf(filterId));
    }
    function move(step) {
        if (flatRows.length === 0) return;
        plate.disarm();
        current = Math.max(0, Math.min(flatRows.length - 1, current + step));
        reveal(current);
    }
    function openCurrent() { if (flatRows.length > 0) openRequested(flatRows[current].transcript); }

    // Scroll the body until row `index` lies in view, built or not.
    function reveal(index) {
        const g = groups.findIndex(group => index < group.start + group.rows.length);
        const day = g < 0 ? null : days.itemAt(g);
        if (day === null) return;
        const area = layout.scrollArea;
        const top = runsTop + day.bandTop + (index - groups[g].start) * rowPitch;
        if (top < area.contentY) area.contentY = top;
        else if (top + rowHeight > area.contentY + area.height) area.contentY = top + rowHeight - area.height;
    }

    // `model` holds `keys`, in order, after the two steps: dropKeys removes
    // every key `keys` lacks, then fillKeys inserts the ones it lacks. A
    // key that stays keeps its entry, and so its row.
    function dropKeys(model, keys) {
        const wanted = new Set(keys);
        for (let i = model.count - 1; i >= 0; i--)
            if (!wanted.has(model.get(i).key)) model.remove(i);
    }
    function fillKeys(model, keys) {
        for (let i = 0; i < keys.length; i++)
            if (i >= model.count || model.get(i).key !== keys[i]) model.insert(i, { key: keys[i] });
        if (model.count > keys.length) model.remove(keys.length, model.count - keys.length);
    }

    // A new read hands each day its rows at once, so a new run builds its
    // row in the turn that read it. The days take them from this call, not
    // from a binding on `groups`: Qt runs this handler and the bindings that
    // read `groups` in no fixed order, and a binding read here could still
    // hold the read before (traced in VGS-1901's unit run).
    function placeDays() {
        const keys = groups.map(group => group.key);
        dropKeys(dayModel, keys);
        fillKeys(dayModel, keys);
        for (let i = 0; i < days.count; i++) days.itemAt(i).place(groups[i]);
    }
    // A scroll, a resize or a day that moves places the shown rows again
    // once Qt.callLater runs it: after the polish that moved the days, when
    // every day stands where it is drawn. Placed during that polish, a day
    // the column has not moved yet would build the rows of its old place;
    // placed after it, an opening page builds its shown rows alone (traced
    // in VGS-1901's unit run).
    function placeShown() {
        for (let i = 0; i < days.count; i++) days.itemAt(i).place(days.itemAt(i).group);
    }

    onGroupsChanged: placeDays()
    onFlatRowsChanged: { plate.disarm(); plate.snap(); current = Math.max(0, Math.min(current, flatRows.length - 1)); }
    Component.onCompleted: placeDays()

    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onReturnPressed: openCurrent()
    Keys.onEnterPressed: openCurrent()
    Keys.onDeletePressed: clearRequested(filterId)
    Keys.onEscapePressed: event => { event.accepted = false; }

    ListModel { id: dayModel }

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        bodySpacing: Theme.stack.group

        titleContent: [
            PageHeader {
                width: layout.contentWidth
                text: "History"
                trailing: [
                    Button { text: "Clear history"; iconName: "trash"; size: "sm"; variant: "danger"; anchors.verticalCenter: parent.verticalCenter; onClicked: page.clearRequested(page.filterId) }
                ]
            }
        ]

        Field {
            width: parent.width
            label: "Automation"
            inline: true
            Select {
                width: parent.width
                model: page.filterOptions
                textRole: "label"
                currentIndex: page.filterIndex()
                onCurrentIndexChanged: page.filterId = page.filterOptions[currentIndex].id
            }
        }

        Item {
            id: runs
            width: parent.width
            height: historyColumn.implicitHeight

            // The cursor sits in this item, beside the rows' column: a
            // positioner would lay the plate out as a row.
            ListCursor { id: plate }
            Column {
                id: historyColumn
                width: parent.width
                spacing: Theme.stack.group

                Field {
                    width: parent.width
                    label: "History"
                    info: "Run history and saved output are kept for up to 30 days so old runs do not keep using disk space. Change how long to keep them in [Plugins](page:vgs.automations/Settings/historyDays)."
                    onInfoPageActivated: (target, tab) => page.panel.shell.surfaces.openPage(target, tab)
                    visible: page.groups.length === 0
                    Label {
                        width: parent.width
                        role: "hint"
                        text: "No runs from the last 30 days."
                        wrapMode: Text.Wrap
                    }
                }

                Repeater {
                    id: days
                    model: dayModel
                    Section {
                        id: day
                        // The day its rows show. place() sets it between
                        // dropping the rows that leave and building the ones
                        // that arrive, so every built row's key is in it.
                        property var group: ({ label: "", start: 0, rows: [], at: {} })
                        // Whether rows built now enter: the rows a new read
                        // brings, a new run's, a filter's or the opening
                        // page's, enter once the day is laid out; a scroll
                        // shows its rows where they lie.
                        property bool entering: false
                        // Where this day's rows start in the runs' item, once
                        // the column has positioned the day: a new day stands
                        // at the column's top until its first layout, and
                        // Positioner.index reads -1 until then (Qt 6.12,
                        // traced in VGS-1901's unit run).
                        readonly property real bandTop: y + band.parent.y
                        readonly property bool laidOut: Positioner.index >= 0
                        readonly property int firstShown: Math.floor((page.shownTop - bandTop + Theme.stack.row) / page.rowPitch)
                        readonly property int endShown: Math.ceil((page.shownBottom - bandTop) / page.rowPitch)

                        // Show the rows of `next`, the day placeDays hands
                        // it, that lie between shownTop and shownBottom: row
                        // i spans i * rowPitch to i * rowPitch + rowHeight
                        // below bandTop.
                        function place(next) {
                            const from = Math.max(0, firstShown);
                            const to = laidOut ? Math.min(next.rows.length, endShown) : from;
                            const keys = next.rows.slice(from, Math.max(from, to)).map(View.historyKey);
                            if (next !== group) entering = true;
                            page.dropKeys(shown, keys);
                            group = next;
                            page.fillKeys(shown, keys);
                            if (laidOut) entering = false;
                        }
                        onFirstShownChanged: Qt.callLater(page.placeShown)
                        onEndShownChanged: Qt.callLater(page.placeShown)
                        onLaidOutChanged: Qt.callLater(page.placeShown)

                        width: historyColumn.width
                        title: group.label
                        headerInset: 0

                        Item {
                            id: band
                            width: parent.width
                            height: Math.max(0, day.group.rows.length * page.rowPitch - Theme.stack.row)

                            ListModel { id: shown }
                            Repeater {
                                model: shown
                                HistoryRow {
                                    required property string key
                                    readonly property int at: day.group.at[key]
                                    y: at * page.rowPitch
                                    width: band.width
                                    height: page.rowHeight
                                    row: day.group.rows[at]
                                    enters: day.entering
                                    highlighted: day.group.start + at === page.current
                                    cursorItem: plate
                                    onOpenRequested: transcript => page.openRequested(transcript)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
