import QtQuick
import qs.Commons
import qs.Ui

// The Tailscale flyout. Its main view is TailscaleBody.qml under the title
// "Tailscale", the connection switch and the state line. The Exit node row
// swaps the body for the chooser (ExitNodes.qml) inside the same Pane: a
// Back button and "Exit nodes" in the title row, the search field as the
// sticky header, and the switch hidden; a country with several cities
// opens its own view under its name. Back or Escape leaves a view: the
// country view for the chooser, the chooser for the main view with the
// keyboard on the Exit node row. A chosen node returns to the main view
// once the service's change ends without a problem. The footer holds Open
// admin console and Tailscale settings, which opens this plugin's System
// Settings section and closes the flyout, in every view.
Item {
    id: root

    property var shell: null
    property var payload: ({})
    // `main`, `exit-nodes` or `country`.
    property string view: "main"
    readonly property bool main: view === "main"
    // The header switch while it can be used, else where the body opens.
    readonly property Item initialFocus: layout.headerSwitch !== null && layout.headerSwitch.enabled && body.lockReason === "" ? layout.headerSwitch : body.initialFocus

    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight

    // Hosts own Escape (design-system.md § Keyboard): it closes the flyout
    // from the main view, and leaves the chooser's views first.
    Keys.onEscapePressed: event => {
        if (root.main) {
            event.accepted = false;
            return;
        }
        root.back();
        event.accepted = true;
    }

    function open(payloadJson) {
        payload = payloadJson ? JSON.parse(payloadJson) : {};
        view = "main";
        chooser.country = "";
        search.text = "";
        body.open();
    }
    function close() {
        view = "main";
        body.close();
    }

    function openSettings() {
        const reply = shell.surfaces.summon("pane", "{}");
        if (reply !== "ok") console.warn("tailscale panel: pane " + reply);
        else shell.surfaces.hide("panel");
    }

    function showExitNodes() {
        body.localProblem = "";
        chooser.country = "";
        search.text = "";
        view = "exit-nodes";
        body.suggest();
        search.forceActiveFocus(Qt.OtherFocusReason);
    }
    function openCountry(code) {
        chooser.country = code;
        view = "country";
        Qt.callLater(() => chooser.focusFirst());
    }
    function back() {
        if (view === "country") {
            const code = chooser.country;
            chooser.country = "";
            view = "exit-nodes";
            Qt.callLater(() => chooser.focusCountry(code));
            return;
        }
        showMain();
    }
    function showMain() {
        if (root.main) return;
        view = "main";
        Qt.callLater(() => body.focusExitRow());
    }

    Surface { anchors.fill: parent }

    Pane {
        id: layout
        anchors.fill: parent
        container: "panel"
        fitToContent: true
        maximumHeight: Theme.size.panel.maxHeight
        title: root.main ? "Tailscale" : ""
        titleContent: [
            Row {
                visible: !root.main
                spacing: Theme.control.gap

                IconButton {
                    objectName: "tailscale-back"
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "chevron-left"
                    label: "Back"
                    onClicked: root.back()
                }
                Label {
                    objectName: "tailscale-view-title"
                    anchors.verticalCenter: parent.verticalCenter
                    role: "h3"
                    text: root.view === "country" ? chooser.countryName : "Exit nodes"
                }
            }
        ]
        subtitle: [
            Label {
                objectName: "tailscale-state"
                width: layout.headerWidth
                visible: root.main
                role: "body"
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: body.tailscale.tone === "warning" ? Theme.color.warning : Theme.text.body.color
                text: body.tailscale.text
            }
        ]
        // While the service is off the switch shows locked, its unlock
        // mark the Enable step.
        switchShown: root.main && (body.switchable || body.tailscale.state === "service-off")
        switchChecked: body.tailscale.state === "running" || body.tailscale.state === "starting"
        switchEnabled: !body.busy
        switchDisabledReason: body.lockReason
        switchUnlock: body.unlock
        switchName: "Tailscale"
        onSwitchToggled: checked => body.request(checked ? "connect" : "disconnect", "")

        // The header slot counts every child it holds, shown or not, so
        // the field's holder takes no height outside the chooser.
        header: [
            Item {
                width: layout.headerWidth
                implicitWidth: 0
                height: root.view === "exit-nodes" ? search.implicitHeight : 0

                TextField {
                    id: search
                    objectName: "tailscale-exit-search-field"
                    width: parent.width
                    visible: root.view === "exit-nodes"
                    leadingIcon: "search"
                    placeholderText: "Search countries, cities and devices"
                    Keys.onDownPressed: chooser.focusFirst()
                }
            }
        ]

        footer: [
            Row {
                spacing: Theme.stack.inline

                Button {
                    objectName: "tailscale-admin-console"
                    text: "Open admin console"
                    variant: "tertiary"
                    iconName: "external-link"
                    onClicked: body.request("admin-console", "")
                }
                Button {
                    objectName: "tailscale-settings"
                    text: "Tailscale settings"
                    variant: "tertiary"
                    iconName: "settings"
                    onClicked: root.openSettings()
                }
            }
        ]

        TailscaleBody {
            id: body
            width: layout.contentWidth
            visible: root.main
            shell: root.shell
            promptPane: layout
            onExitNodesRequested: root.showExitNodes()
            onExitChosen: root.showMain()
        }
        ExitNodes {
            id: chooser
            objectName: "tailscale-exit-nodes"
            width: layout.contentWidth
            visible: !root.main
            tailscale: body.tailscale
            exitNodes: body.exitNodes
            query: search.text
            pending: body.busy ? body.pendingExit : null
            disabledReason: body.lockReason
            problem: body.problemText
            onCountryOpened: code => root.openCountry(code)
            onChose: id => body.chooseExit(id)
            onClearRequested: {
                search.text = "";
                search.forceActiveFocus(Qt.TabFocusReason);
            }
        }
    }
}
