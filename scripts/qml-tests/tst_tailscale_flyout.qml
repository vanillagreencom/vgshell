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
// chooser on its search field and asks for a suggestion, and Back or
// Escape leaves each view with the keyboard on the row it came from; an
// offline node of your own is refused with its sentence and nothing runs.
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
    readonly property var snapshot: Logic.snapshot(0, JSON.stringify({
        BackendState: "Running",
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
                suggestion: Logic.suggestion("se-sto-wg-001.mullvad.ts.net", snapshot) }),
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

        function cleanup() { panel.close(); }

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

        function test_tab_reaches_add_account_and_sign_out_after_the_list() {
            const account = named("tailscale-account");
            account.focusItem.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            verify(account.expanded, "Space opens the account row");
            keyClick(Qt.Key_Tab);
            verify(within(focused(), named("tailscale-accounts")), "the account list follows the row");
            keyClick(Qt.Key_Tab);
            compare(focused(), named("tailscale-add-account"));
            keyClick(Qt.Key_Tab);
            compare(focused(), named("tailscale-sign-out"));
            keyClick(Qt.Key_Tab);
            verify(within(focused(), named("tailscale-this-device")), "this device follows Sign out");
        }

        function test_sign_out_asks_and_only_its_accept_signs_out() {
            const account = named("tailscale-account");
            account.focusItem.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
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
            const device = named("tailscale-this-device");
            const row = device.rowAt(0);
            const before = row.rowAction.text;
            mouseClick(row);
            paste.text = "";
            paste.paste();
            compare(paste.text, "100.64.0.1");
            verify(row.rowAction.text !== before, "the action reads its confirmation");
            tryVerify(() => row.rowAction.text === before, 5000, "the action returns once the copy stops confirming");
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
            tabTo(item => item === countries, "the Mullvad list");
            const sweden = Logic.countryRows(root.snapshot.exitNodes).findIndex(row => row.code === "SE");
            while (countries.current !== sweden) keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(panel.view, "country");
            tryVerify(() => within(focused(), named("tailscale-exit-cities")), 1000, "the cities take the keys");
            keyClick(Qt.Key_Escape);
            compare(panel.view, "exit-nodes");
            tryCompare(root.Window.window, "activeFocusItem", countries);
            compare(countries.current, sweden, "the keys return to Sweden");
            compare(root.actions, [], "opening a country changes nothing");
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
