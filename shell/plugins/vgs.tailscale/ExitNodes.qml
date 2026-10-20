import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "TailscaleLogic.js" as Logic

// The exit node chooser, which the flyout swaps in for its main view and
// the System pane holds inline: Recommended while the service read a
// suggestion, None, your own exit nodes, then Mullvad by country. A
// country with one city chooses it; one with more opens the country view
// (`countryOpened`), which the host shows by setting `country`: Best
// available, the best city at the moment of the click, then each city.
// While `query` holds text, the rows that match it show flat, cities as
// "City, Country". The host draws the search field and the title.
//
// A row's click, Enter or Space emits `chose` with the node's id, "" for
// None, and never a target: the service maps the id. The row whose node a
// change runs for, `pending`, shows a spinner. Each list is one Tab stop
// whose arrows move inside it.
FocusScope {
    id: root

    property var tailscale: Logic.unread()
    property var exitNodes: Logic.emptySnapshot("checking").exitNodes
    property string query: ""
    // The code of the country the view shows, "" for the list.
    property string country: ""
    // The id of the node a change runs for, null while none does.
    property var pending: null
    property string disabledReason: ""
    // The line the last refused or failed change left, "" for none, such
    // as "This exit node is offline.".
    property string problem: ""

    signal countryOpened(string code)
    signal chose(string id)
    // The empty search's Clear search.
    signal clearRequested()

    readonly property bool searching: query.trim() !== ""
    readonly property bool listShown: country === "" && !searching
    readonly property var shownCountry: exitNodes.countries.find(entry => entry.code === country) || null
    readonly property string countryName: shownCountry === null ? "" : shownCountry.name
    readonly property var topRows: withPending(Logic.exitTopRows(tailscale))
    readonly property var ownRows: withPending(Logic.ownRows(exitNodes))
    readonly property var countryRows: Logic.countryRows(exitNodes)
    readonly property var cityRows: shownCountry === null ? [] : withPending(Logic.cityRows(shownCountry))
    readonly property var searchRows: withPending(Logic.searchRows(exitNodes, query))

    implicitHeight: column.implicitHeight

    function withPending(rows) {
        return rows.map(row => Object.assign({}, row, { busy: root.pending !== null && row.id === root.pending }));
    }
    function act(row) {
        if (row === undefined) return;
        if (row.opens) root.countryOpened(row.code);
        else root.chose(row.id);
    }
    function actOn(list, key) { act(list.rows.find(row => row.key === key)); }

    // Gives the keyboard to the first list the view shows.
    function focusFirst() {
        const lists = [cityList, topList, searchList];
        const shown = lists.find(list => list.visible);
        if (shown !== undefined) shown.focusCurrent(Qt.TabFocusReason);
    }
    // Gives the keyboard to the Mullvad list on country CODE.
    function focusCountry(code) {
        const index = countryRows.findIndex(row => row.code === code);
        if (index === -1) {
            focusFirst();
            return;
        }
        countryList.current = index;
        countryList.forceActiveFocus(Qt.TabFocusReason);
    }

    Column {
        id: column
        width: root.width
        spacing: Theme.stack.group

        Label {
            objectName: "tailscale-exit-problem"
            width: parent.width
            visible: text !== ""
            role: "hint"
            color: Theme.color.danger
            text: root.problem
            wrapMode: Text.Wrap
        }
        DeviceList {
            id: topList
            objectName: "tailscale-exit-top"
            width: parent.width
            visible: root.listShown
            disabledReason: root.disabledReason
            rows: root.topRows
            onActed: key => root.actOn(topList, key)
        }
        Section {
            width: parent.width
            visible: root.listShown && root.ownRows.length > 0
            title: "Your exit nodes"

            DeviceList {
                id: ownList
                objectName: "tailscale-exit-own"
                width: parent.width
                disabledReason: root.disabledReason
                rows: root.ownRows
                onActed: key => root.actOn(ownList, key)
            }
        }
        Section {
            width: parent.width
            visible: root.listShown && root.countryRows.length > 0
            title: "Mullvad"

            // focus-indicator: the one ListCursor marks the selected country
            FocusScope {
                id: countryList
                objectName: "tailscale-exit-countries"
                property int current: 0
                readonly property string currentKey: current >= 0 && current < root.countryRows.length ? root.countryRows[current].key : ""
                width: parent.width
                implicitHeight: countryColumn.implicitHeight
                // A hidden list is no Tab stop already; reading `visible`
                // here would clear the stop while the list holds the keys
                // as the country view opens, which Qt refuses with a warning.
                activeFocusOnTab: root.countryRows.length > 0
                Keys.onPressed: event => { event.accepted = countryNav.handle(event); }
                onVisibleChanged: current = Math.max(0, Math.min(current, root.countryRows.length - 1))

                ListCursor { id: countryCursor; shown: root.countryRows.length > 0 }
                KeyNav {
                    id: countryNav
                    count: root.countryRows.length
                    currentIndex: countryList.current
                    cursor: countryCursor
                    labelAt: index => root.countryRows[index].text
                    onMoved: index => countryList.current = index
                    onActivated: index => root.act(root.countryRows[index])
                }
                Column {
                    id: countryColumn
                    width: countryList.width

                    Repeater {
                        model: ScriptModel { values: root.countryRows; objectProp: "key" }

                        // keyboard-path: the list's KeyNav moves to the country and Enter or Space chooses it
                        ListItem {
                            id: countryRow
                            required property var modelData
                            required property int index
                            readonly property bool busy: root.pending !== null && !modelData.opens && modelData.id === root.pending
                            width: countryColumn.width
                            // A country that opens its cities chooses nothing,
                            // so a lock leaves it open.
                            enabled: modelData.opens || root.disabledReason === ""
                            focusPolicy: Qt.NoFocus
                            cursor: countryCursor
                            highlighted: countryList.activeFocus && countryList.current === index
                            iconName: modelData.iconName
                            text: modelData.text
                            secondary: modelData.secondary
                            onClicked: {
                                countryList.current = index;
                                root.act(modelData);
                            }
                            trailing: [
                                Spinner {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: countryRow.busy
                                    running: visible
                                },
                                Badge {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: countryRow.modelData.badge !== ""
                                    text: countryRow.modelData.badge
                                    tone: countryRow.modelData.badgeTone
                                },
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: countryRow.modelData.opens
                                    name: "chevron-right"
                                    size: Theme.icon.size.md
                                    color: Theme.color.textMuted
                                }
                            ]
                        }
                    }
                }
            }
        }
        DeviceList {
            id: searchList
            objectName: "tailscale-exit-search"
            width: parent.width
            visible: root.searching && root.country === "" && root.searchRows.length > 0
            disabledReason: root.disabledReason
            rows: root.searchRows
            onActed: key => root.actOn(searchList, key)
        }
        EmptyState {
            objectName: "tailscale-exit-no-match"
            width: parent.width
            visible: root.searching && root.country === "" && root.searchRows.length === 0
            iconName: "search"
            text: "No exit node matches “" + root.query.trim() + "”."
            actionText: "Clear search"
            onActivated: root.clearRequested()
        }
        DeviceList {
            id: cityList
            objectName: "tailscale-exit-cities"
            width: parent.width
            visible: root.shownCountry !== null
            disabledReason: root.disabledReason
            rows: root.cityRows
            onActed: key => root.actOn(cityList, key)
        }
    }
}
