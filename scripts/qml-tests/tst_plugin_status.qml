import QtQuick
import QtTest
import qs.Core

// PluginStatus notifies per plugin: a status write re-runs the bindings
// that read the writing plugin's status and no other plugin's. A record
// holds the values as the plugin wrote them.
Item {
    id: root
    readonly property var aValues: PluginStatus.valuesOf("acme.a")
    readonly property var bValues: PluginStatus.valuesOf("acme.b")
    readonly property int bRevision: PluginStatus.revisionOf("acme.b")
    readonly property string aTab: PluginStatus.viewedTabOf("acme.a")
    // Each value aTab took, in order.
    property var aTabs: []
    onATabChanged: aTabs = aTabs.concat([aTab])

    function manifest(revision) {
        return { __revision: revision, status: { pending: { type: "count" }, detail: { type: "data" } } };
    }

    function context(id) {
        return { id: id, manifest: Registry.manifests[id] };
    }

    // valuesOf hands each evaluation a new copy, so each re-run of a reader
    // emits its change signal once.
    SignalSpy { id: aReads; target: root; signalName: "aValuesChanged" }
    SignalSpy { id: bReads; target: root; signalName: "bValuesChanged" }

    TestCase {
        name: "plugin-status"

        function init() {
            Registry.manifests = { "acme.a": root.manifest("a1"), "acme.b": root.manifest("b1") };
            compare(PluginStatus.set(root.context("acme.a"), "pending", 1), "ok");
            compare(PluginStatus.set(root.context("acme.b"), "pending", 1), "ok");
            compare(root.aValues.pending, 1);
            compare(root.bValues.pending, 1);
            aReads.clear();
            bReads.clear();
        }

        function cleanup() {
            PluginStatus.view("", "");
            Registry.manifests = {};
            Registry.changed();
            wait(0); // QObject.destroy() completes after the current event turn.
        }

        function test_a_write_reruns_only_its_own_plugins_readers() {
            const serial = PluginStatus.serial;
            const bRevision = root.bRevision;
            compare(PluginStatus.set(root.context("acme.a"), "pending", 2), "ok");
            compare(PluginStatus.serial, serial + 1);
            compare(aReads.count, 1);
            compare(root.aValues.pending, 2);
            compare(bReads.count, 0);
            compare(root.bRevision, bRevision);
        }

        function test_a_first_write_keeps_the_value_as_written() {
            Registry.manifests = Object.assign({ "acme.c": root.manifest("c1") }, Registry.manifests);
            compare(PluginStatus.set(root.context("acme.c"), "detail", { zeta: 1, alpha: [1, 2] }), "ok");
            compare(JSON.stringify(PluginStatus.valuesOf("acme.c")), '{"detail":{"zeta":1,"alpha":[1,2]}}');
        }

        // The tab the Settings window shows reaches the plugin whose page it
        // is alone, and a bound reader follows each report.
        function test_a_viewed_tab_reaches_only_its_plugin() {
            PluginStatus.view("acme.a", "Setup");
            compare([root.aTab, PluginStatus.viewedTabOf("acme.b")], ["Setup", ""]);
            PluginStatus.view("acme.a", "Details");
            compare(root.aTab, "Details");
            PluginStatus.view("acme.b", "Setup");
            compare([root.aTab, PluginStatus.viewedTabOf("acme.b")], ["", "Setup"]);
            PluginStatus.view("", "");
            compare([root.aTab, PluginStatus.viewedTabOf("acme.b"), PluginStatus.viewed], ["", "", ""]);
        }

        // A report names its page and tab together: a plugin's bound reader
        // never reads its page beside the tab the page before it showed, as
        // Jarvis's Setup tab reader would start a package check on it.
        function test_a_page_change_never_shows_the_last_pages_tab() {
            PluginStatus.view("acme.b", "Setup");
            root.aTabs = [];
            PluginStatus.view("acme.a", "Settings");
            compare(root.aTabs, ["Settings"]);
        }

        function test_a_dropped_record_reruns_its_readers_and_keeps_the_others() {
            Registry.manifests = { "acme.b": root.manifest("b1") };
            Registry.changed();
            compare(aReads.count, 1);
            compare(JSON.stringify(root.aValues), "{}");
            compare(PluginStatus.revisionOf("acme.a"), 0);
            compare(root.bValues.pending, 1);
            compare(PluginStatus.set(root.context("acme.b"), "pending", 3), "ok");
            compare(root.bValues.pending, 3);
            compare(aReads.count, 1);
        }
    }
}
