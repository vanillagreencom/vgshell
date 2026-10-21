import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import "../../shell/plugins/vgs.vpn" as Vpn
import "../../shell/plugins/vgs.vpn/VpnLogic.js" as Logic

// The VPN flyout and System Settings section over a stub shell whose
// `profiles` value is the stand-in data of scripts/fixtures/vpn/: what
// each kind of row offers, the Updates section and the empty states, and
// the remove confirmation by keyboard: Cancel takes the focus, Cancel
// hands it back to Remove profile, and once the profile leaves the list
// the focus moves to the profile now in its place, else the one before
// it, else Import a VPN file; and an open password prompt keeps its
// profile when another connect ends at Needs password.
Item {
    id: root
    width: 900
    height: 1000

    property var calls: []
    property var missing: []
    property var values: ({})

    function record(call) {
        root.calls = root.calls.concat([call]);
        return "ok";
    }

    readonly property string home: "9d76b882-ead1-4c49-8675-7be6431d5f71"
    readonly property string office: "95ea5c2d-312f-4a84-8fd1-9ebc0a4a7581"
    readonly property string travel: "5b1c0a9e-2f43-4d7a-9a51-0c3e6e1d2b84"
    readonly property string campus: "2e8f4d1a-7c6b-4f3e-8a29-6d5b4c3a2f10"
    readonly property string branch: "76ceb7f0-0f5b-4315-9f38-2af0937bb726"

    // The stand-in rows as VpnLogic.list and VpnLogic.details read them
    // from list.txt and details.txt (scripts/test-vpn-logic.js pins the
    // parse), less the uuids NAMES leaves out.
    function payload(names, options) {
        const all = [
            [home, "Home tunnel", "wireguard", "activated", "", "203.0.113.10:51820"],
            [office, "Office VPN", "vpn", "", "openvpn", "vpn.example.com"],
            [travel, "Travel L2TP", "vpn", "", "l2tp", "l2tp.example.net"],
            [campus, "Campus AnyConnect", "vpn", "", "openconnect", "vpn.example.edu"],
            [branch, "Branch IPsec", "vpn", "", "vpnc", "ipsec.example.net"]
        ].filter(row => names.indexOf(row[1]) !== -1);
        const rows = all.map(row => ({ uuid: row[0], name: row[1], type: row[2], state: row[3] }));
        const details = {};
        for (const row of all) details[row[0]] = { service: row[4], server: row[5] };
        const opts = options || {};
        const listing = { state: opts.state || "available", rows: rows, count: rows.length, activeCount: rows.filter(row => row.state === "activated").length };
        const failures = Object.assign({ [travel]: { kind: "needs-password", service: "" }, [branch]: { kind: "sign-in", service: "" } }, opts.failures || {});
        return Logic.compose(listing, details, { [home]: "10.20.0.2" }, failures, opts.action || null, opts.problem || "");
    }
    readonly property var standIn: ["Home tunnel", "Office VPN", "Travel L2TP", "Campus AnyConnect", "Branch IPsec"]

    function shell() {
        return {
            status: { values: root.values },
            settings: { pollSeconds: 30 },
            configure: { set: (key, value) => root.record(["configure", key, value]) },
            requirements: { missing: root.missing, offer: commands => root.record(["offer", commands]) },
            ipc: { call: (name, arg) => root.record(["ipc", name, arg]) },
            surfaces: { summon: kind => root.record(["summon", kind]), hide: kind => root.record(["hide", kind]) }
        };
    }

    Button { id: outside; text: "Outside" }

    Component {
        id: paneComponent
        Vpn.Pane { y: outside.height; width: 720 }
    }
    Component {
        id: panelComponent
        Item {
            property alias panel: panel
            y: outside.height
            width: panel.implicitWidth
            height: panel.implicitHeight
            property string settingsPage: ""
            Vpn.Panel { id: panel; anchors.fill: parent }
        }
    }

    TestCase {
        name: "vpn_views"
        when: windowShown

        property Item view: null

        function publish(value) {
            root.values = { profiles: value, connection: Logic.connection(value) };
            (view.panel !== undefined ? view.panel : view).shell = root.shell();
            waitForRendering(view);
        }
        function open(component, value) {
            root.calls = [];
            root.missing = [];
            view = createTemporaryObject(component, root);
            verify(view !== null);
            publish(value);
            return view;
        }
        function cleanup() { view = null; }

        function find(item, wanted) {
            for (const child of item.children) {
                if (child.visible && wanted(child)) return child;
                const found = find(child, wanted);
                if (found !== null) return found;
            }
            return null;
        }
        function named(name) { return find(view, item => item.objectName === name); }
        function row(uuid) {
            const found = named("vpn-profile:" + uuid);
            verify(found !== null, "a row shows " + uuid);
            return found;
        }
        function lastIpc() {
            const ipc = root.calls.filter(call => call[0] === "ipc" && call[1] === "action").map(call => JSON.parse(call[2]));
            return ipc.length === 0 ? null : ipc[ipc.length - 1];
        }

        // Each row draws what VpnLogic.rowView decides, and a switch that
        // cannot be used keeps its reason.
        function test_rows_draw_their_states() {
            open(paneComponent, root.payload(root.standIn));
            for (const uuid of [root.home, root.office, root.travel, root.campus, root.branch]) {
                const shown = row(uuid);
                const want = Logic.rowView(root.values.profiles.rows.find(entry => entry.uuid === uuid), root.values.profiles);
                compare(shown.secondary, want.secondary);
                const toggle = named("vpn-profile-toggle:" + uuid);
                compare(toggle.checked, want.switchOn);
                compare(toggle.disabledReason !== "", want.reason !== "", uuid);
            }
            compare(row(root.home).iconName, "shield-check");
            compare(row(root.office).iconName, "shield");
            verify(named("vpn-updates") !== null, "the Updates section shows");
            verify(named("vpn-import-hint") !== null, "the import hint shows");
            verify(named("vpn-empty") === null, "no empty state with profiles");
            const profilesSection = named("vpn-profiles");
            const info = find(profilesSection, item => "infoOpen" in item);
            verify(info !== null, "the Profiles section has its info button");
            compare(info.title, profilesSection.infoTitle);
            verify(info.title !== profilesSection.title, "the dialog is titled apart from the section");
        }

        // An expanded profile shows its details; connected, its address.
        function test_expanded_profile_shows_details() {
            open(paneComponent, root.payload(root.standIn));
            row(root.home).expanded = true;
            waitForRendering(view);
            compare(named("vpn-type:" + root.home).text, Logic.typeName("wireguard", ""));
            compare(named("vpn-server:" + root.home).text, "203.0.113.10:51820");
            compare(named("vpn-address:" + root.home).text, "10.20.0.2");
            compare(lastIpc(), { kind: "profile-details", id: root.home });
            row(root.office).expanded = true;
            waitForRendering(view);
            verify(named("vpn-address:" + root.office) === null, "an off profile shows no address");
            const remove = named("vpn-remove:" + root.office);
            verify(remove !== null);
            compare(remove.tone, "danger");
            verify(!remove.removesItem, "Remove profile leads its text with the trash mark");
        }

        // A missing core requirement disables the switch before a connect.
        // Its one Install action raises the core's requirement notice.
        function test_missing_plugin_disables_its_switch() {
            open(paneComponent, root.payload(root.standIn));
            root.missing = ["org.freedesktop.NetworkManager.openvpn"];
            publish(root.values.profiles);
            const shown = row(root.office);
            compare(shown.view.key, "plugin-needed");
            shown.expanded = true;
            waitForRendering(view);
            const toggle = named("vpn-profile-toggle:" + root.office);
            verify(toggle.disabledReason !== "", "the switch keeps its reason");
            mouseClick(toggle);
            compare(lastIpc(), { kind: "profile-details", id: root.office }, "a disabled switch asks for nothing");
            const actions = [];
            (function collect(item) {
                for (const child of item.children) {
                    if (child.visible && "removesItem" in child) actions.push(child.objectName);
                    collect(child);
                }
            })(shown);
            compare(actions, ["vpn-install-plugin:" + root.office, "vpn-edit:" + root.office, "vpn-remove:" + root.office]);
            compare(root.calls.filter(call => call[0] === "offer"), []);
            mouseClick(named("vpn-install-plugin:" + root.office));
            compare(root.calls.filter(call => call[0] === "offer"), [["offer", ["org.freedesktop.NetworkManager.openvpn"]]]);
            root.missing = [];
            publish(root.values.profiles);
            compare(shown.view.key, "off");
            compare(toggle.disabledReason, "");
            verify(named("vpn-install-plugin:" + root.office) === null);
        }

        // The confirmation asks first, with Cancel focused; Cancel removes
        // nothing and hands the focus back to Remove profile.
        function test_cancel_returns_to_remove_profile() {
            open(paneComponent, root.payload(root.standIn));
            row(root.office).expanded = true;
            waitForRendering(view);
            const remove = named("vpn-remove:" + root.office);
            remove.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            const confirm = named("vpn-remove-confirm");
            verify(confirm !== null, "the confirmation shows");
            tryVerify(() => find(confirm, item => item.activeFocus && item.text === "Cancel") !== null, 1000, "Cancel holds the focus");
            keyClick(Qt.Key_Return);
            tryVerify(() => named("vpn-remove-confirm") === null);
            tryVerify(() => remove.activeFocus, 1000, "Remove profile holds the focus again");
            compare(root.calls.filter(call => call[0] === "ipc" && JSON.parse(call[2]).kind === "profile-remove"), []);
        }

        function remove(uuid) {
            row(uuid).expanded = true;
            waitForRendering(view);
            named("vpn-remove:" + uuid).forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            const confirm = named("vpn-remove-confirm");
            verify(confirm !== null);
            const accept = find(confirm, item => "variant" in item && item.variant === "danger");
            verify(accept !== null, "Remove shows in the danger variant");
            mouseClick(accept);
            compare(lastIpc(), { kind: "profile-remove", id: uuid });
        }

        // After a removal the focus goes to the profile now in its place,
        // else the one before it, else Import a VPN file.
        function test_removal_moves_the_focus() {
            open(paneComponent, root.payload(root.standIn));
            remove(root.office);
            publish(root.payload(root.standIn, { action: { kind: "profile-remove", uuid: root.office, name: "Office VPN" } }));
            publish(root.payload(["Home tunnel", "Travel L2TP", "Campus AnyConnect", "Branch IPsec"]));
            tryVerify(() => row(root.travel).focusItem.activeFocus, 1000, "the next profile's row holds the focus");

            remove(root.branch);
            publish(root.payload(["Home tunnel", "Travel L2TP", "Campus AnyConnect"]));
            tryVerify(() => row(root.campus).focusItem.activeFocus, 1000, "the previous profile's row holds the focus");
        }

        function test_last_removal_focuses_import() {
            open(paneComponent, root.payload(["Office VPN"]));
            remove(root.office);
            publish(root.payload([]));
            const empty = named("vpn-empty");
            verify(empty !== null, "the no-profile state shows");
            tryVerify(() => find(empty, item => item.activeFocus && item.text === "Import a VPN file") !== null, 1000, "Import a VPN file holds the focus");
        }

        // A removal that fails keeps the profile and its problem line.
        function test_failed_removal_keeps_the_profile() {
            open(paneComponent, root.payload(root.standIn));
            remove(root.office);
            publish(root.payload(root.standIn, { problem: Logic.problem("profile-remove", "Office VPN", 1) }));
            verify(named("vpn-problem") !== null, "the problem line shows");
            compare(find(view, item => "removingUuid" in item).removingUuid, "");
        }

        // A prompt open for one profile keeps that profile and its typed
        // password when another profile's followed connect ends at Needs
        // password: retargeting it would send the password to the other
        // profile's server.
        function test_prompt_keeps_its_profile() {
            open(paneComponent, root.payload(root.standIn));
            mouseClick(named("vpn-profile-toggle:" + root.office));
            compare(lastIpc(), { kind: "profile-up", id: root.office });
            publish(root.payload(root.standIn, { action: { kind: "profile-up", uuid: root.office, name: "Office VPN" } }));
            mouseClick(named("vpn-profile-toggle:" + root.travel));
            const prompt = named("vpn-connect-prompt");
            verify(prompt !== null, "the prompt shows");
            compare(prompt.target.uuid, root.travel);
            const field = named("vpn-password");
            tryVerify(() => field.activeFocus, 1000, "the password field holds the focus");
            for (const key of "stand-in") keyClick(key);
            publish(root.payload(root.standIn, { failures: { [root.office]: { kind: "needs-password", service: "" } } }));
            compare(row(root.office).view.key, "needs-password");
            compare(prompt.target.uuid, root.travel);
            compare(field.text, "stand-in");
        }

        function test_empty_states() {
            open(paneComponent, root.payload([]));
            verify(named("vpn-empty") !== null);
            verify(named("vpn-updates") !== null, "Updates shows while NetworkManager answers");
            verify(named("vpn-profiles") === null);
            for (const state of ["missing", "not-running", "no-answer"]) {
                publish(root.payload([], { state: state }));
                const empty = named("vpn-empty");
                verify(empty !== null, state);
                compare(empty.actionText, "", state + " offers no import");
                verify(named("vpn-updates") === null, state + " shows no Updates");
            }
        }

        // The flyout: no Remove, no Updates, no empty state.
        function test_flyout() {
            open(panelComponent, root.payload(root.standIn));
            const panel = view.panel;
            compare(named("vpn-subtitle").text, Logic.summary(root.values.profiles));
            row(root.office).expanded = true;
            waitForRendering(view);
            verify(named("vpn-remove:" + root.office) === null, "the flyout offers no Remove");
            verify(named("vpn-updates") === null);
            verify(named("vpn-import-hint") === null);
            verify(named("vpn-import") !== null);
            mouseClick(named("vpn-import"));
            compare(root.calls.filter(call => call[0] === "ipc" && call[1] === "import").length, 1);
            mouseClick(named("vpn-profile-toggle:" + root.office));
            compare(lastIpc(), { kind: "profile-up", id: root.office });
            // The bar icon hides with no profile and with no NetworkManager.
            for (const state of ["available", "not-running"]) {
                publish(root.payload([], { state: state }));
                verify(named("vpn-empty") === null, state + " draws no empty state");
            }
        }
    }
}
