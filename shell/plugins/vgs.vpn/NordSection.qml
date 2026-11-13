import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

Section {
    id: root
    property var shell: null
    required property Item overlayHost
    property real overlayCorner: 0
    property bool opened: false
    property string requestProblem: ""
    property string openId: ""
    property int countryId: 0
    property int regionId: 0
    property int cityId: 0
    signal replied(string reply, string refusal)
    readonly property real dialogHeight: picker.implicitHeight
    readonly property var state: shell === null || !shell.status.values.nordState ? { phase: "closed", problem: "", countries: [] } : shell.status.values.nordState
    readonly property var schema: shell === null ? ({}) : shell.manifest.schema
    readonly property var choices: shell === null || !Array.isArray(shell.status.values.nordProfiles) ? [] : shell.status.values.nordProfiles
    readonly property string profile: shell === null || typeof shell.settings.nordProfile !== "string" ? "" : shell.settings.nordProfile
    readonly property int profileIndex: profile === "" ? 0 : choices.findIndex(row => row.value === profile)
    readonly property var catalog: ({ kind: "ready", rows: state.countries || [] })
    readonly property var countries: Logic.nordChoices(catalog, []).rows
    readonly property var country: catalog.rows.find(row => row.id === countryId) || null
    readonly property var regions: country === null || country.subdivisions.length === 0 ? [] : Logic.nordChoices(catalog, [countryId]).rows
    readonly property var cities: country === null ? [] : Logic.nordChoices(catalog, regions.length === 0 ? [countryId] : [countryId, regionId]).rows
    readonly property bool changing: state.phase === "changing"
    readonly property bool ready: cityId > 0 && cities.some(row => row.id === cityId) && !changing
    readonly property string problem: opened && requestProblem !== "" ? requestProblem : state.problem || ""
    // The holder owns scrolling. Use its public reveal operation for the
    // whole card; focusing one field alone can leave the footer clipped.
    readonly property Item scrollHost: {
        for (let at = overlayHost; at !== null; at = at.parent)
            if (typeof at.reveal === "function") return at;
        return null;
    }
    function revealPicker() { if (opened && scrollHost !== null) scrollHost.reveal(picker); }
    onProfileIndexChanged: if (opened && profileIndex < 0) close()
    onVisibleChanged: if (!visible) close(false)

    objectName: "vpn-nord-section"
    title: schema.nordProfile === undefined ? "" : schema.nordProfile.group
    function call(request) { return shell.ipc.call("nord", JSON.stringify(request)); }
    function show() {
        if (shell.requirements.missing.indexOf("curl") !== -1) {
            replied(shell.requirements.offer(["curl"]), "VGS could not open the tool install notice.");
            return;
        }
        countryId = 0;
        regionId = 0;
        cityId = 0;
        openId = String(root) + ":" + Date.now();
        const reply = call({ kind: "open", id: openId });
        replied(reply, "VGS could not open NordVPN locations.");
        if (reply !== "ok") return;
        opened = true;
        Qt.callLater(() => { root.revealPicker(); picker.takeFocus(); });
    }
    function close(restore) {
        if (!opened) return;
        call({ kind: "close", id: openId });
        opened = false;
        replied("ok", "");
        if (restore !== false) Qt.callLater(() => { if (root !== null && root.visible) change.forceActiveFocus(Qt.TabFocusReason); });
    }
    onStateChanged: if (opened && state.phase === "done") close()
    Component.onDestruction: if (opened && shell !== null) call({ kind: "close", id: openId })

    Field {
        width: root.width
        inline: true
        label: root.schema.nordProfile === undefined ? "" : root.schema.nordProfile.label
        hint: root.schema.nordProfile === undefined ? "" : root.schema.nordProfile.description
        Select {
            objectName: "vpn-nord-profile"
            width: parent.width
            model: root.choices
            textRole: "label"
            currentIndex: root.profileIndex
            placeholderText: "Profile unavailable"
            disabledReason: root.changing ? "Wait for the location change to finish." : ""
            Accessible.name: "NordVPN profile: " + currentText
            onActivated: index => {
                currentIndex = Qt.binding(() => root.profileIndex);
                root.replied(root.call({ kind: "profile", uuid: index === 0 ? "" : root.choices[index].value }), "VGS could not save the NordVPN profile.");
            }
        }
    }
    RowAction {
        id: change
        objectName: "vpn-nord-location"
        text: "Change location"
        disabledReason: root.profile === "" ? "Set the NordVPN profile first."
            : root.profileIndex < 0 ? "This profile is no longer saved. Set another profile."
            : root.changing ? "Wait for the location change to finish." : ""
        onClicked: root.show()
    }
    Callout {
        width: root.width
        visible: !root.opened && root.problem !== ""
        tone: "danger"
        text: root.problem
    }
    Scrim {
        parent: root.overlayHost
        visible: root.opened
        radius: root.overlayCorner
        onClicked: picker.takeFocus()
    }
    Dialog {
        id: picker
        parent: root.overlayHost
        objectName: "vpn-nord-picker"
        visible: root.opened
        z: 1
        width: Math.min(implicitWidth, parent.width)
        anchors.horizontalCenter: parent.horizontalCenter
        // The body can extend below its viewport. Keep the dialog beside
        // the visible action, as the profile prompts do, not at the body's
        // off-screen centre.
        readonly property real anchorY: change.mapToItem(parent, 0, change.height / 2).y
        y: Math.max(0, Math.min(parent.height - height, anchorY - height / 2))
        availableHeight: root.scrollHost === null ? parent.height : root.scrollHost.height
        onHeightChanged: if (root.opened) Qt.callLater(root.revealPicker)
        onYChanged: if (root.opened) Qt.callLater(root.revealPicker)
        title: "NordVPN location"
        initialFocus: countriesField
        tabItems: [countriesField, regionsField, citiesField]
        actions: [{ label: root.changing ? "Close" : "Cancel", role: "cancel" }, { label: "Change", role: "accept", enabled: root.ready }]
        onRejected: root.close()
        onAccepted: root.replied(root.call({ kind: "city", countryId: root.countryId, subdivisionId: root.regionId, cityId: root.cityId }), "VGS could not change the VPN location.")

        Label {
            width: parent.width
            visible: root.changing
            text: "Changing server…"
        }
        Callout {
            width: parent.width
            visible: root.problem !== ""
            tone: "danger"
            text: root.problem
        }
        Field {
            width: parent.width
            label: "Country"
            Select {
                id: countriesField
                objectName: "vpn-nord-country"
                width: parent.width
                model: root.countries
                textRole: "name"
                currentIndex: model.findIndex(row => row.id === root.countryId)
                placeholderText: "Not set"
                emptyText: root.state.phase === "loading" ? "Loading…" : "Locations unavailable"
                disabledReason: root.changing ? "Wait for the location change to finish." : ""
                Accessible.name: "Country: " + currentText
                onActivated: index => { currentIndex = Qt.binding(() => model.findIndex(row => row.id === root.countryId)); root.countryId = model[index].id; root.regionId = 0; root.cityId = 0; }
            }
        }
        Field {
            width: parent.width
            visible: root.regions.length > 0
            label: "Region or state"
            Select {
                id: regionsField
                objectName: "vpn-nord-region"
                width: parent.width
                model: root.regions
                textRole: "name"
                currentIndex: model.findIndex(row => row.id === root.regionId)
                placeholderText: "Not set"
                disabledReason: root.changing ? "Wait for the location change to finish." : ""
                Accessible.name: "Region or state: " + currentText
                onActivated: index => { currentIndex = Qt.binding(() => model.findIndex(row => row.id === root.regionId)); root.regionId = model[index].id; root.cityId = 0; }
            }
        }
        Field {
            width: parent.width
            visible: root.country !== null && (root.regions.length === 0 || root.regionId > 0)
            label: "City"
            Select {
                id: citiesField
                objectName: "vpn-nord-city"
                width: parent.width
                model: root.cities
                textRole: "name"
                currentIndex: model.findIndex(row => row.id === root.cityId)
                placeholderText: "Not set"
                disabledReason: root.changing ? "Wait for the location change to finish." : ""
                Accessible.name: "City: " + currentText
                onActivated: index => { currentIndex = Qt.binding(() => model.findIndex(row => row.id === root.cityId)); root.cityId = model[index].id; }
            }
        }
    }
    Connections {
        target: root.scrollHost
        function onHeightChanged() { if (root.opened) Qt.callLater(root.revealPicker); }
    }
}
