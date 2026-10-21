import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "TailscaleLogic.js" as Logic

// The exit node chooser, which the flyout swaps in for its main view and
// the System pane holds inline: Recommended while the service read a
// suggestion, None, your own exit nodes, then Mullvad by country. A
// country with one city chooses it; one with more opens the country view
// (`openCountry`), which shows `country`: Best available, the best city at
// the moment of the click, then each city. While the host's
// `searchField` holds text, the rows that match it show flat, cities as
// "City, Country", at most SEARCH_MAX of them. The host draws the search
// field, the title and Back, which calls `closeCountry`. The System pane
// sets `inlineCountries` to expand each country in place with Disclosure.
//
// The chooser moves the keyboard itself, for both hosts: Down from the
// search field takes it to the view's first row, Recommended while it is
// listed, an opened country's view takes it on its first row, Back
// returns it to the country that was open, and Clear search to the search
// field, so it never rests on a row the view hides.
//
// A row's click, Enter or Space emits `chose` with the node's id, "" for
// None, and never a target: the service maps the id. The row whose node a
// change runs for, `pending`, shows a spinner. Each list is one Tab stop
// whose arrows move inside it.
FocusScope {
    id: root

    property var tailscale: Logic.unread()
    property var exitNodes: Logic.emptySnapshot("checking").exitNodes
    // The host's search field: its text filters the rows.
    property TextField searchField: null
    readonly property string query: searchField === null ? "" : searchField.text
    // The code of the country the view shows, "" for the list.
    property string country: ""
    // The System pane expands countries in place; the flyout opens a view.
    property bool inlineCountries: false
    // The id of the node a change runs for, null while none does.
    property var pending: null
    property string disabledReason: ""
    // The line the last refused or failed change left, "" for none, such
    // as "This exit node is offline.".
    property string problem: ""

    signal chose(string id)

    readonly property bool searching: query.trim() !== ""
    readonly property bool listShown: country === "" && !searching
    readonly property var shownCountry: exitNodes.countries.find(entry => entry.code === country) || null
    readonly property string countryName: shownCountry === null ? "" : shownCountry.name
    readonly property var topRows: withPending(Logic.exitTopRows(tailscale))
    readonly property var ownRows: withPending(Logic.ownRows(exitNodes))
    readonly property var countryRows: withPending(Logic.countryRows(exitNodes))
    readonly property var cityRows: shownCountry === null ? [] : withPending(Logic.cityRows(shownCountry))
    readonly property var searchMatches: Logic.searchRows(exitNodes, query)
    readonly property var searchRows: withPending(searchMatches.slice(0, Logic.SEARCH_MAX))

    implicitHeight: column.implicitHeight

    // A row that opens a country runs no change, so no spinner.
    function withPending(rows) {
        return rows.map(row => Object.assign({}, row, { busy: root.pending !== null && row.opens !== true && row.id === root.pending }));
    }
    function act(row) {
        if (row === undefined) return;
        if (row.opens) openCountry(row.code);
        else root.chose(row.id);
    }
    function actOn(list, key) { act(list.rows.find(row => row.key === key)); }

    // Gives the keyboard to the first row of the first list the view
    // shows. A keyed list keeps its selection on the row it held, so a
    // Recommended row listed after the view opened would otherwise leave
    // the selection on None, below it.
    function focusFirst() {
        const lists = [cityList, topList, searchList];
        const shown = lists.find(list => list.visible);
        if (shown === undefined) return;
        shown.current = 0;
        shown.focusCurrent(Qt.TabFocusReason);
    }
    // Gives the keyboard to the Mullvad list on country CODE.
    function focusCountry(code) {
        const index = countryRows.findIndex(row => row.code === code);
        if (index === -1) {
            focusFirst();
            return;
        }
        countryList.current = index;
        countryList.focusCurrent(Qt.TabFocusReason);
    }
    // Shows country CODE's view, the keyboard on its first row once its
    // rows are built.
    function openCountry(code) {
        country = code;
        Qt.callLater(() => { if (root.country === code) root.focusFirst(); });
    }
    // Leaves the country view, the keyboard on the country it showed.
    function closeCountry() {
        const code = country;
        country = "";
        Qt.callLater(() => { if (root.country === "") root.focusCountry(code); });
    }
    // Empties the search, the keyboard on its field.
    function clearSearch() {
        searchField.text = "";
        searchField.forceActiveFocus(Qt.TabFocusReason);
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

            // A country with several cities opens, so a lock leaves it
            // working (DeviceList `opens`).
            DeviceList {
                id: countryList
                visible: !root.inlineCountries
                objectName: "tailscale-exit-countries"
                width: parent.width
                disabledReason: root.disabledReason
                rows: root.countryRows
                onActed: key => root.actOn(countryList, key)
            }
            Item {
                width: parent.width
                height: countriesColumn.implicitHeight
                visible: root.inlineCountries && root.listShown
                ListCursor { id: countryCursor }
                Column {
                    id: countriesColumn
                    width: parent.width
                    Repeater {
                        // Stable keys keep an expanded country's controls
                        // alive when the service updates a node's state.
                        // https://quickshell.org/docs/v0.3.1/types/Quickshell/ScriptModel/
                        model: ScriptModel { values: root.inlineCountries && root.listShown ? root.exitNodes.countries.map(entry => entry.code) : [] }
                        Column {
                            id: countryBlock
                            required property var modelData
                            readonly property var countryData: root.exitNodes.countries.find(entry => entry.code === modelData)
                                || ({ code: String(modelData), name: "", cities: [], best: { id: "", city: "" } })
                            width: countriesColumn.width
                            Disclosure {
                                objectName: "tailscale-exit-country-" + countryBlock.countryData.code
                                width: parent.width
                                visible: countryBlock.countryData.cities.length > 1
                                cursor: countryCursor
                                iconName: "map-pin"
                                text: countryBlock.countryData.name
                                secondary: countryBlock.countryData.cities.length + " cities"
                                trailing: [Badge {
                                    visible: countryBlock.countryData.cities.some(city => city.active)
                                    text: "In use"
                                    tone: "success"
                                }]
                                DeviceList {
                                    objectName: "tailscale-exit-country-cities-" + countryBlock.countryData.code
                                    width: parent.width
                                    disabledReason: root.disabledReason
                                    rows: root.withPending(Logic.cityRows(countryBlock.countryData))
                                    onActed: key => root.act(rows.find(row => row.key === key))
                                }
                            }
                            DeviceList {
                                objectName: "tailscale-exit-country-single-" + countryBlock.countryData.code
                                width: parent.width
                                visible: countryBlock.countryData.cities.length === 1
                                disabledReason: root.disabledReason
                                rows: root.withPending(root.countryRows.filter(row => row.code === countryBlock.countryData.code))
                                onActed: key => root.act(rows.find(row => row.key === key))
                            }
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
        Row {
            objectName: "tailscale-exit-search-more"
            visible: searchList.visible && root.searchMatches.length > root.searchRows.length
            spacing: Theme.stack.inline

            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "hint"
                text: "Showing " + root.searchRows.length + " of " + root.searchMatches.length + " matches."
            }
            InfoButton {
                anchors.verticalCenter: parent.verticalCenter
                title: "Search"
                info: "The list shows the first " + Logic.SEARCH_MAX + " matches, so it opens quickly. Type more of a name to find the others."
            }
        }
        EmptyState {
            objectName: "tailscale-exit-no-match"
            width: parent.width
            visible: root.searching && root.country === "" && root.searchRows.length === 0
            iconName: "search"
            text: "No exit node matches “" + root.query.trim() + "”."
            actionText: "Clear search"
            onActivated: root.clearSearch()
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
