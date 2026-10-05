import QtQuick
import QtTest
import Quickshell
import "../../shell/plugins/vgs.launcher"

// The launcher's application list handler: a loaded apps menu follows a
// change of the desktop entries, and an application that left takes its
// row with it. The stand-in DesktopEntries list is replaced by hand, which
// emits valuesChanged as a rescan does.
Item {
    id: root
    width: 800
    height: 600

    Launcher {
        id: launcher
        anchors.fill: parent
    }

    TestCase {
        name: "launcherApps"
        when: windowShown

        function app(id, name) {
            return { id: id, name: name, genericName: "", comment: "", keywords: [], icon: "" };
        }

        function test_an_application_that_left_takes_its_row() {
            launcher.readMenu("shipped", "stand-in", JSON.stringify({ schemaVersion: 1, items: {
                apps: { icon: "layout-grid", label: "Apps", provider: "apps" }
            } }));
            DesktopEntries.applications.values = [app("a", "Alpha"), app("b", "Beta")];
            launcher.loadProvider("apps");
            compare(launcher.itemOrder.join(" "), "root apps apps.a apps.b");

            DesktopEntries.applications.values = [app("a", "Alpha"), app("c", "Gamma")];
            compare(launcher.itemOrder.join(" "), "root apps apps.a apps.c", "the handler swapped the apps menu");
            compare(Object.keys(launcher.items).sort().join(" "), "apps apps.a apps.c root", "the items hold the order's ids");
            compare(launcher.items["apps.c"].label, "Gamma");
        }
    }
}
