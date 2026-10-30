import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.tailscale" as Tailscale
import "../../shell/plugins/vgs.tailscale/TailscaleLogic.js" as Logic

// The Tailscale flyout by keyboard alone, over a stub shell whose status
// values the plugin's own logic makes from one tailnet: this device, a
// tagged online gateway and an offline attic-nas that offer themselves as
// exit nodes, a phone, and Mullvad's Stockholm (in use, and suggested) and
// Gothenburg in Sweden and Zurich in Switzerland. The stub answers each
// action as the service's command judge does and records the ones it
// takes. The flyout opens on its header switch and draws no poll
// setting; Tab reaches Add account and Sign out after the account list;
// Sign out asks first, and only the dialog's accept sends `logout`; Copy
// puts this device's address on the clipboard; the Exit node row opens the
// chooser on its search field and asks for a suggestion, at its top, and
// Back or Escape leaves each view with the keyboard on the row it came
// from; the card keeps its height while the chooser shows; Tailscale
// stopping leaves the chooser with the keyboard on the header switch; an
// offline node of your own is refused with its sentence and nothing runs.
// Down from the search field lands on Recommended when the suggestion is
// read after the chooser opened.
// The System pane uses the shared account and device lists in open
// sections. It keeps Account and This device while approval waits, and
// expands exit countries inline: Tab enters the cities, Shift+Tab returns
// to their Disclosure, and Clear search returns to the field. Stopping
// returns the chooser's keyboard to the connection switch.
// inputs: shell/plugins/vgs.tailscale/* shell/Ui/* shell/Ui/**/* shell/Commons/*
Item {
    id: root
    width: 600
    height: 1000

    // Each request the flyout makes of the stub shell, in order: IPC calls
    // as [name, arg], actions the judge took as [kind, id].
    property var calls: []
    property var actions: []

    readonly property string mullvadTag: "tag:mullvad-exit-node"
    // The daemon's state, which a case changes and cleanup() restores.
    property string backend: "Running"
    // Whether the service has read its suggestion, which a case clears
    // and cleanup() restores.
    property bool suggested: true
    readonly property var snapshot: Logic.snapshot(0, JSON.stringify({
        BackendState: root.backend,
        Self: { ID: "nDESK", HostName: "desk", DNSName: "desk.tail-fixture.ts.net.", OS: "linux", UserID: 1, TailscaleIPs: ["100.64.0.1"] },
        CurrentTailnet: { Name: "example.com" },
        User: { "1": { LoginName: "amelie@example.com" } },
        Peer: {
            a: { ID: "nGATE", HostName: "gateway", DNSName: "gateway.tail-fixture.ts.net.", OS: "linux", Tags: ["tag:server"], TailscaleIPs: ["100.64.0.2"], Online: true, ExitNodeOption: true },
            b: { ID: "nATTIC", HostName: "attic-nas", DNSName: "attic-nas.tail-fixture.ts.net.", OS: "linux", TailscaleIPs: ["100.64.0.3"], Online: false, ExitNodeOption: true },
            c: { ID: "nPIXEL", HostName: "pixel", DNSName: "pixel.tail-fixture.ts.net.", OS: "android", TailscaleIPs: ["100.64.0.4"], Online: true },
            d: { ID: "mSTO", DNSName: "se-sto-wg-001.mullvad.ts.net.", Tags: [mullvadTag], TailscaleIPs: ["100.64.2.1"], Online: true, ExitNodeOption: true, ExitNode: true,
                Location: { Country: "Sweden", CountryCode: "SE", City: "Stockholm", CityCode: "STO", Priority: 100 } },
            e: { ID: "mGOT", DNSName: "se-got-wg-001.mullvad.ts.net.", Tags: [mullvadTag], TailscaleIPs: ["100.64.2.2"], Online: true, ExitNodeOption: true,
                Location: { Country: "Sweden", CountryCode: "SE", City: "Gothenburg", CityCode: "GOT", Priority: 50 } },
            f: { ID: "mZRH", DNSName: "ch-zrh-wg-001.mullvad.ts.net.", Tags: [mullvadTag], TailscaleIPs: ["100.64.2.3"], Online: true, ExitNodeOption: true,
                Location: { Country: "Switzerland", CountryCode: "CH", City: "Zurich", CityCode: "ZRH", Priority: 80 } }
        }
    }), "")
    readonly property var accounts: [
        { id: "a1", tailnet: "example.com", account: "amelie@example.com", current: true },
        { id: "a2", tailnet: "example.org", account: "amelie@example.org", current: false }
    ]
    readonly property var setupLine: Logic.setup({ missing: false, state: "running", service: "ready", operator: "ready" })

    function values() {
        return {
            tailscale: Logic.published(false, snapshot, setupLine, { accounts: accounts, action: "", login: "idle", problem: "",
                suggestion: root.suggested ? Logic.suggestion("se-sto-wg-001.mullvad.ts.net", snapshot) : null }),
            devices: snapshot.devices,
            exitNodes: snapshot.exitNodes
        };
    }

    function call(name, arg) {
        root.calls = root.calls.concat([[name, arg]]);
        if (name !== "action") return "ok";
        const request = JSON.parse(arg);
        const plan = Logic.command(request, { state: snapshot.state, targets: snapshot.targets, accounts: accounts });
        if (plan.refusal !== undefined) return plan.refusal;
        root.actions = root.actions.concat([[request.kind, request.id]]);
        return "ok";
    }

    QtObject {
        id: stub
        readonly property var settings: ({ pollSeconds: 30 })
        readonly property var status: ({ values: root.values(), rows: [], act: key => "ok" })
        readonly property var ipc: ({ call: (name, arg) => root.call(name, arg) })
        readonly property var surfaces: ({ summon: () => "ok", hide: () => "ok" })
    }

    Tailscale.Panel { id: panel; width: implicitWidth; height: 900 }
    // The System pane's body, made by the cases that read it, over the
    // flyout, which they hide.
    Component {
        id: paneBody
        Tailscale.TailscaleBody { width: 560; z: 1; shell: stub; expanded: true }
    }
    // A chooser alone, with its own search field.
    Component {
        id: chooserAlone
        Item {
            readonly property alias chooser: alone
            readonly property alias field: aloneField
            width: 480
            height: 900
            z: 1
            TextField { id: aloneField; width: 480 }
            Tailscale.ExitNodes {
                id: alone
                y: 60
                width: 480
                tailscale: Logic.unread()
                searchField: aloneField
            }
        }
    }
    Component { id: chooseSpy; SignalSpy { signalName: "chose" } }
    // Reads the clipboard back.
    TextEdit { id: paste; y: 950; width: 300; height: 20 }

    TestCase {
        name: "tailscale_flyout"
        when: windowShown

        function init() {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            panel.shell = stub;
            panel.open("{}");
            waitForRendering(panel);
            root.calls = [];
            root.actions = [];
            const start = panel.initialFocus;
            start.forceActiveFocus(Qt.OtherFocusReason);
        }

        function cleanup() {
            panel.close();
            panel.height = 900;
            panel.visible = true;
            root.backend = "Running";
            root.suggested = true;
        }

        function find(item, wanted) {
            for (const child of item.children) {
                if (child.visible && wanted(child)) return child;
                const found = find(child, wanted);
                if (found !== null) return found;
            }
            return null;
        }
        function named(name) {
            const found = find(panel, item => item.objectName === name);
            verify(found !== null, "the flyout shows " + name);
            return found;
        }
        function focused() { return root.Window.window.activeFocusItem; }
        function within(item, ancestor) {
            for (let at = item; at !== null; at = at.parent) if (at === ancestor) return true;
            return false;
        }
        function tabTo(test, what) {
            for (let presses = 0; !test(focused()); presses++) {
                verify(presses < 30, "Tab reaches " + what);
                keyClick(Qt.Key_Tab);
            }
        }

        function test_opens_on_the_switch_with_no_poll_setting() {
            compare(panel.initialFocus.Accessible.name, "Tailscale", "the header switch takes the keys");
            compare(find(panel, item => item.objectName === "tailscale-poll"), null, "the flyout draws no Check every");
        }

        function test_accounts_card_has_header_actions_and_a_keyboard_list() {
            const card = named("tailscale-accounts-card");
            verify(card.visible);
            compare(named("tailscale-accounts-header").text, "Accounts");
            const add = named("tailscale-add-account");
            compare(add.label, "Add account");
            compare(named("tailscale-sign-out").label, "Sign out");
            verify(add.y + add.height < named("tailscale-accounts").y);
            add.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(root.actions, [["add-account", ""]]);
            keyClick(Qt.Key_Tab);
            compare(focused(), named("tailscale-sign-out"));
            keyClick(Qt.Key_Tab);
            verify(within(focused(), named("tailscale-accounts")));
        }

        function test_signed_out_saved_account_sign_in_targets_its_id() {
            root.backend = "NeedsLogin";
            const list = named("tailscale-accounts");
            compare(list.actionOf(list.rows[1]).text, "Sign in");
            list.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(root.actions, [["sign-in", "a2"]]);
        }

        function test_sign_out_asks_and_only_its_accept_signs_out() {
            const signOut = named("tailscale-sign-out");
            signOut.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            const prompt = named("tailscale-sign-out-prompt");
            const cancel = prompt.buttons()[prompt.entries.findIndex(entry => entry.role === "cancel")];
            tryCompare(root.Window.window, "activeFocusItem", cancel);
            keyClick(Qt.Key_Return);
            verify(!prompt.visible, "Cancel closes the confirmation");
            compare(root.actions, [], "Cancel sends nothing");
            compare(focused(), signOut, "the keys return to Sign out");
            keyClick(Qt.Key_Return);
            tryCompare(root.Window.window, "activeFocusItem", cancel);
            keyClick(Qt.Key_Escape);
            verify(!prompt.visible, "Escape closes the confirmation");
            compare(root.actions, [], "Escape sends nothing");
            keyClick(Qt.Key_Return);
            tryCompare(root.Window.window, "activeFocusItem", cancel);
            keyClick(Qt.Key_Tab);
            compare(focused(), prompt.buttons()[prompt.acceptIndex], "Tab moves to the dialog's Sign out");
            keyClick(Qt.Key_Return);
            compare(root.actions, [["logout", ""]]);
            verify(!prompt.visible);
        }

        function test_copy_puts_this_devices_address_on_the_clipboard() {
            const row = named("tailscale-this-device");
            const action = named("tailscale-self-copy");
            const before = action.text;
            mouseClick(row);
            paste.text = "";
            paste.paste();
            compare(paste.text, "100.64.0.1");
            verify(action.text !== before, "the action reads its confirmation");
            tryVerify(() => action.text === before, 5000, "the action returns once the copy stops confirming");
        }

        function test_this_device_and_network_devices_share_one_hover_plate() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const device = named("tailscale-this-device");
            const network = named("tailscale-network-devices");
            network.expanded = true;
            waitForRendering(network);
            const child = named("tailscale-devices").rowAt(0);
            compare(device.cursor, network.cursor, "This device belongs to the flyout's row list");
            const cursor = network.cursor;
            cursor.arm();
            mouseMove(network.focusItem, 20, 10);
            compare(cursor.hovered, network.focusItem);
            mouseMove(device, 20, 10);
            compare(cursor.hovered, device);
            mouseMove(network.focusItem, 22, 10);
            compare(cursor.hovered, network.focusItem);
            mouseMove(child, 20, 10);
            mouseMove(child, 22, 10);
            compare(child.cursor.hovered, child);
            compare(cursor.shown, false);
            compare(network.focusItem.active, true);
            mouseMove(device, 22, 10);
            compare(cursor.hovered, device);
            compare(child.cursor.hovered, null);
            compare(network.focusItem.active, false);
            UnitTheme.reset();
        }

        function test_back_and_escape_return_to_the_exit_node_row() {
            const exitRow = named("tailscale-exit-row");
            for (const leave of ["escape", "back"]) {
                root.calls = [];
                exitRow.forceActiveFocus(Qt.TabFocusReason);
                keyClick(Qt.Key_Return);
                compare(panel.view, "exit-nodes");
                compare(focused(), named("tailscale-exit-search-field"), "the chooser opens on its search field");
                verify(root.calls.some(entry => entry[0] === "suggest"), "the chooser asks for a suggestion");
                if (leave === "escape") keyClick(Qt.Key_Escape);
                else mouseClick(named("tailscale-back"));
                compare(panel.view, "main", leave);
                tryCompare(root.Window.window, "activeFocusItem", exitRow);
            }
        }

        function test_a_country_opens_and_returns_to_its_row() {
            named("tailscale-exit-row").forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            const countries = named("tailscale-exit-countries");
            tabTo(item => within(item, countries), "the Mullvad list");
            const sweden = Logic.countryRows(root.snapshot.exitNodes).findIndex(row => row.code === "SE");
            while (countries.current !== sweden) keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(panel.view, "country");
            tryVerify(() => within(focused(), named("tailscale-exit-cities")), 1000, "the cities take the keys");
            keyClick(Qt.Key_Escape);
            compare(panel.view, "exit-nodes");
            tryVerify(() => within(focused(), countries) && focused().visible, 1000, "the keys return to the countries");
            compare(countries.currentKey, "SE", "the keys return to Sweden");
            compare(root.actions, [], "opening a country changes nothing");
        }

        // The suggestion is read after the chooser opens, so Recommended is
        // listed above None after the view first drew None alone; Down
        // from the search field lands on Recommended, the first row, then
        // and after the keyboard chose None.
        function test_down_from_the_search_field_reaches_a_later_recommended() {
            root.suggested = false;
            named("tailscale-exit-row").forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            const top = named("tailscale-exit-top");
            compare(top.rows.map(row => row.key), ["none"], "the chooser opens before the suggestion");
            root.suggested = true;
            compare(top.rows.map(row => row.key), ["recommended", "none"], "Recommended is listed first");
            compare(focused(), named("tailscale-exit-search-field"));
            keyClick(Qt.Key_Down);
            verify(within(focused(), top), "Down from the search field reaches the top list");
            compare(top.currentKey, "recommended", "Down from the search field lands on Recommended");
            // A later Down from the field lands on the top again, not on
            // the row the keyboard last chose.
            keyClick(Qt.Key_Down);
            compare(top.currentKey, "none");
            named("tailscale-exit-search-field").forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Down);
            compare(top.currentKey, "recommended", "a later Down from the search field lands on Recommended");
        }

        // The main view, short enough to scroll, reveals the Exit node row;
        // the Exit nodes view then opens at its top, Recommended first.
        function test_the_exit_nodes_view_opens_at_its_top() {
            panel.height = 300;
            const area = find(panel, item => item.scrollArea !== undefined).scrollArea;
            named("tailscale-exit-row").forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => area.contentY > 0, 1000, "the main view scrolls to the Exit node row");
            keyClick(Qt.Key_Return);
            compare(panel.view, "exit-nodes");
            waitForRendering(panel);
            compare(area.contentY, 0, "the Exit nodes view opens at its top");
        }

        // design VGS-1923 § 4: the card keeps its height or grows while the
        // chooser shows, and the main view fits its content again.
        function test_the_card_keeps_its_height_while_the_chooser_shows() {
            const fitted = panel.implicitHeight;
            named("tailscale-exit-row").forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            const opened = panel.implicitHeight;
            verify(opened >= fitted, "the chooser opens no shorter than the main view: " + opened + " < " + fitted);
            for (const key of [Qt.Key_Z, Qt.Key_U, Qt.Key_R, Qt.Key_X]) {
                keyClick(key);
                verify(panel.implicitHeight >= opened, "a search keeps the card's height: " + panel.implicitHeight + " < " + opened);
            }
            keyClick(Qt.Key_Escape);
            compare(panel.view, "main");
            // The shown body lays its rows out on the next polish.
            tryCompare(panel, "implicitHeight", fitted, 1000, "the main view fits its content again");
        }

        // Tailscale stopping, as from another client, ends every choice.
        function test_tailscale_stopping_leaves_the_chooser() {
            named("tailscale-exit-row").forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(panel.view, "exit-nodes");
            root.backend = "Stopped";
            tryCompare(panel, "view", "main");
            tryCompare(root.Window.window, "activeFocusItem", panel.initialFocus);
            compare(panel.initialFocus.Accessible.name, "Tailscale", "the keys land on the header switch");
        }

        function findIn(item, name) {
            const found = find(item, child => child.objectName === name);
            verify(found !== null, "the pane shows " + name);
            return found;
        }
        function openPane() {
            panel.visible = false;
            const body = createTemporaryObject(paneBody, root);
            body.open();
            waitForRendering(body);
            return body;
        }

        function test_the_pane_shows_its_lists_in_open_sections() {
            compare(named("tailscale-network-devices").expanded, false, "the flyout opens its devices closed");
            const body = openPane();
            for (const name of ["tailscale-accounts-card", "tailscale-device-section", "tailscale-exit-section",
                "tailscale-network-section", "tailscale-admin-section", "tailscale-updates-section"])
                verify(findIn(body, name).visible, name + " is open");
            compare(findIn(body, "tailscale-accounts").rows.map(row => row.key), ["a1", "a2"]);
            compare(findIn(body, "tailscale-devices").rows.map(row => row.key), ["nGATE", "nPIXEL", "nATTIC"]);
            findIn(body, "tailscale-self-address");
            findIn(body, "tailscale-self-dns");
        }

        function test_the_pane_keeps_the_account_while_waiting_for_approval() {
            root.backend = "NeedsMachineAuth";
            tryVerify(() => find(panel, item => item.objectName === "tailscale-approval-console") !== null, 1000, "the flyout shows the approval step");
            verify(named("tailscale-accounts-card").visible, "accounts remain available while approval waits");
            const body = openPane();
            findIn(body, "tailscale-accounts-card");
            findIn(body, "tailscale-accounts");
            findIn(body, "tailscale-device-section");
            findIn(body, "tailscale-self-address");
            findIn(body, "tailscale-self-dns");
            compare(find(body, item => item.objectName === "tailscale-exit-section"), null);
            compare(find(body, item => item.objectName === "tailscale-network-section"), null);
        }

        // Stopping hides the inline chooser and returns its held keyboard.
        function test_tailscale_stopping_returns_the_panes_keyboard() {
            const body = openPane();
            const sweden = findIn(body, "tailscale-exit-country-SE");
            sweden.focusItem.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            verify(sweden.expanded);
            keyClick(Qt.Key_Tab);
            const cities = findIn(body, "tailscale-exit-country-cities-SE");
            tryVerify(() => within(focused(), cities), 1000, "the inline cities take the keys");
            root.backend = "Stopped";
            tryVerify(() => focused() === body.initialFocus, 1000, "the keys go where the pane opens");
            verify(focused().visible, "the keys rest on a shown item");
            compare(focused().Accessible.name, "Tailscale");
        }

        function test_the_panes_chooser_keeps_the_keyboard_on_a_shown_row() {
            const body = openPane();
            const sweden = findIn(body, "tailscale-exit-country-SE");
            sweden.focusItem.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            verify(sweden.expanded, "Return expands the country in place");
            compare(focused(), sweden.focusItem);
            keyClick(Qt.Key_Tab);
            const cities = findIn(body, "tailscale-exit-country-cities-SE");
            tryVerify(() => focused().visible && within(focused(), cities), 1000, "Tab enters the inline cities");
            keyClick(Qt.Key_Down);
            compare(cities.currentKey, "city:GOT");
            keyClick(Qt.Key_Tab, Qt.ShiftModifier);
            compare(focused(), sweden.focusItem, "Shift+Tab returns to the country");
            keyClick(Qt.Key_Return);
            verify(!sweden.expanded, "Return collapses the country");
            verify(focused().visible);
            const field = findIn(body, "tailscale-inline-search");
            field.forceActiveFocus(Qt.TabFocusReason);
            for (const key of [Qt.Key_X, Qt.Key_Y, Qt.Key_Z]) keyClick(key);
            const empty = findIn(body, "tailscale-exit-no-match");
            const clear = find(empty, item => item.text === "Clear search" && item.clicked !== undefined);
            verify(clear !== null, "the empty search offers Clear search");
            clear.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(field.text, "");
            tryVerify(() => focused().visible && within(focused(), field), 1000, "Clear search returns the keys to the search field");
        }

        // A one-city country chooses, so a lock refuses it; a country with
        // cities opens, which changes nothing, so it still works.
        function test_a_lock_refuses_a_one_city_country_and_opens_a_country() {
            panel.visible = false;
            const made = createTemporaryObject(chooserAlone, root);
            made.chooser.exitNodes = root.snapshot.exitNodes;
            made.chooser.disabledReason = "The administrator holds Tailscale.";
            const spy = createTemporaryObject(chooseSpy, root, { target: made.chooser });
            const countries = find(made, item => item.objectName === "tailscale-exit-countries");
            countries.current = countries.rows.findIndex(row => row.code === "CH");
            countries.focusCurrent(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(spy.count, 0, "Enter or Space on a locked one-city country chooses nothing");
            compare(made.chooser.country, "");
            countries.current = countries.rows.findIndex(row => row.code === "SE");
            countries.focusCurrent(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(made.chooser.country, "SE", "a country with cities opens under the lock");
        }

        // Mullvad's cities, enough that one letter matches past the ceiling.
        function manyNodes() {
            const countries = [];
            for (let c = 0; c < 15; c++) {
                const cities = [];
                for (let k = 0; k < 4; k++) {
                    const n = c * 4 + k;
                    cities.push({ code: "C" + n, name: (n % 2 === 0 ? "London " : "Oslo ") + n, id: "city" + n, target: "t" + n, active: false });
                }
                countries.push({ code: "K" + c, name: "Land " + c, best: { id: cities[0].id, city: cities[0].name }, cities: cities });
            }
            return { own: [], countries: countries, cityCount: 60 };
        }

        // A narrower search drops rows and keeps the others' items, and a
        // wider one keeps them again; at most SEARCH_MAX rows draw.
        function test_a_search_keeps_its_rows_and_draws_at_most_its_ceiling() {
            panel.visible = false;
            const made = createTemporaryObject(chooserAlone, root);
            made.chooser.exitNodes = manyNodes();
            made.field.text = "o";
            const list = find(made, item => item.objectName === "tailscale-exit-search");
            compare(list.rows.length, Logic.SEARCH_MAX, "the search draws at most its ceiling");
            verify(made.chooser.searchMatches.length > Logic.SEARCH_MAX, "the stand-in matches past the ceiling");
            verify(find(made, item => item.objectName === "tailscale-exit-search-more") !== null, "the list says it shows the first matches");
            const items = {};
            for (let index = 0; index < list.count; index++) items[list.rows[index].key] = list.rowAt(index);
            made.field.text = "on";
            const kept = [];
            for (let index = 0; index < list.count; index++) {
                const key = list.rows[index].key;
                if (items[key] === undefined) continue;
                compare(list.rowAt(index), items[key], "a narrower search keeps the row of " + key);
                kept.push(key);
            }
            verify(kept.length > 0, "the narrower search keeps rows");
            made.field.text = "o";
            for (const key of kept) {
                const index = list.rows.findIndex(row => row.key === key);
                compare(list.rowAt(index), items[key], "a wider search keeps the row of " + key);
            }
            made.field.text = "london 1";
            verify(list.rows.length <= Logic.SEARCH_MAX && list.rows.length > 0);
            compare(find(made, item => item.objectName === "tailscale-exit-search-more"), null, "a search within the ceiling draws no count");
        }

        // expected-log: tailscale: refused: exit-node=offline -- the view logs the service's refusal
        function test_an_offline_node_of_your_own_is_refused() {
            named("tailscale-exit-row").forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            const own = named("tailscale-exit-own");
            const attic = own.rows.findIndex(row => row.id === "nATTIC");
            verify(attic !== -1, "the offline node is listed");
            own.current = attic;
            own.focusCurrent(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(root.actions, [], "no set runs");
            compare(named("tailscale-exit-problem").text, Logic.replyText("refused: exit-node=offline"));
            compare(panel.view, "exit-nodes", "the chooser stays");
        }

        function test_a_search_shows_matching_cities_flat() {
            named("tailscale-exit-row").forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Z);
            keyClick(Qt.Key_U);
            keyClick(Qt.Key_R);
            compare(named("tailscale-exit-search").rows.map(row => row.id), ["mZRH"]);
            keyClick(Qt.Key_X);
            verify(find(panel, item => item.objectName === "tailscale-exit-search") === null, "no row matches");
            named("tailscale-exit-no-match");
        }
    }
}
