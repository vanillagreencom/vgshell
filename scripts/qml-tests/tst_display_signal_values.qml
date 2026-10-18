import QtQuick
import QtTest
import qs.Core
import qs.Unit
import "../../shell/plugins/vgs.displays" as Displays

// inputs: shell/plugins/vgs.displays/* shell/Ui/* shell/Ui/**/* shell/Commons/* shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/MonitorLogic.js shell/Core/Pads.js
// Arrangement.moved reaches the shipped Pane, its trial request, and Keep's
// configuration write. The capability stand-ins record calls, and the real
// manager judge and writer produce the settings every instance receives.
Item {
    id: root
    width: 900
    height: 1200

    readonly property var manifest: readJson("../../shell/plugins/vgs.displays/manifest.json")
    property var user: ({})
    property var trialRules: null
    property string refusal: ""
    readonly property var outputs: [{
        id: 0, name: "DP-1", identifier: "fixture", description: "Fixture display", make: "Fixture", model: "Display", serial: "1",
        width: 1920, height: 1080, refreshRate: 60, x: 0, y: 0, scale: 1, transform: 0,
        disabled: false, mirrorOf: null, availableModes: [{ width: 1920, height: 1080, refresh: 60 }],
        bitdepth: 8, colorManagementPreset: "srgb", sdrBrightness: 1, sdrSaturation: 1
    }]

    function readJson(path) {
        const request = new XMLHttpRequest();
        request.open("GET", Qt.resolvedUrl(path), false);
        request.send();
        return JSON.parse(request.responseText);
    }

    QtObject {
        id: fakeShell
        readonly property var manifest: root.manifest
        readonly property var settings: PluginLogic.settingsFor(root.user, root.manifest)
        readonly property var status: ({ values: {}, rows: [] })
        readonly property var monitors: ({
            outputs: root.outputs, support: null,
            trialState: { phase: "idle", token: "", deadline: 0, failure: "" },
            wantSupport: () => () => {},
            overridden: rules => ({}),
            trial: (rules, saved) => { root.trialRules = rules; return "ok"; },
            keep: (token, done) => { done({ ok: true, rules: root.trialRules }); return "pending"; }
        })
        readonly property var configure: ({ set: (key, value) => {
            root.refusal = PluginLogic.settingRefusal(root.manifest, key, value);
            if (root.refusal !== "") return root.refusal;
            root.user = PluginLogic.withSetting(root.user, root.manifest, key, value, {});
            return "ok";
        } })
    }

    Component { id: paneComponent; Displays.Pane { width: 850; shell: fakeShell } }

    TestCase {
        name: "display_signal_values"
        when: windowShown

        function init() { root.user = {}; root.trialRules = null; root.refusal = ""; }
        function cleanup() { UnitTheme.reset(); }

        function test_moved_object_reaches_trial_and_published_settings() {
            const pane = createTemporaryObject(paneComponent, root);
            verify(pane !== null);
            const canvas = pane.initialFocus;
            canvas.forceActiveFocus();
            keyClick(Qt.Key_Right, Qt.ShiftModifier);
            compare(pane.outputDraft["DP-1"].position.x, 96);
            compare(pane.outputDraft["DP-1"].position.y, 0);
            compare(pane.outputDirty, true);
            pane.applyOutputDraft();
            compare(root.trialRules["DP-1"].position, { x: 96, y: 0 });
            pane.keepTrial();
            compare(root.refusal, "");
            compare(fakeShell.settings.outputs["DP-1"].position, { x: 96, y: 0 });
            compare(fakeShell.settings.outputs["DP-1"].mode, { width: 1920, height: 1080, refresh: 60 });
            compare(root.user.plugins[0].outputs["DP-1"].position, { x: 96, y: 0 });
            compare(pane.outputDirty, false);
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            compare(pane.outputDraft["DP-1"].position.x, 96);
            compare(pane.outputDraft["DP-1"].position.y, 96);
        }
    }
}
