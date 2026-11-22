import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.themes" as Themes

// The Themes panel over a stub shell: a key move to a theme row the
// panel's first view has not built, made after its first frame and before
// its later rows build, builds that row, brings it into the list's view,
// and Return applies it.
Item {
    id: root
    width: 700
    height: 700

    // Each apply the panel asks of the stub shell, in order.
    property var applied: []

    // More packages than the panel's cap holds, the last the only name
    // that starts with Z.
    readonly property var packages: {
        const out = [];
        for (let i = 0; i < 59; i++)
            out.push({ name: "theme-" + i, source: "installed", state: "ok", reason: null, current: false });
        out.push({ name: "zulu", source: "installed", state: "ok", reason: null, current: false });
        return out;
    }

    function shell() {
        return {
            theme: {
                listing: { packages: root.packages, file: null },
                last: { applying: null, result: null, downloading: null },
                swatch: name => null,
                apply: (name, done) => {
                    root.applied = root.applied.concat([name]);
                    return "ok";
                }
            },
            ipc: {
                call: (name, arg) => name === "browser-data"
                    ? JSON.stringify({ revision: 1, listReason: "", catalog: { reason: null, entries: [] } })
                    : "ok"
            }
        };
    }

    Component {
        id: panelComponent
        Themes.ThemesPanel {}
    }

    UnitCase {
        name: "themes_panel"
        when: windowShown

        function descendants(item) {
            const out = [];
            for (const child of item.children) out.push(child, ...descendants(child));
            return out;
        }

        function rowNamed(panel, name) {
            return descendants(panel).find(item => item.rowKey !== undefined && item.name === name) || null;
        }

        function test_a_key_move_before_the_rows_build_reveals_and_applies_its_row() {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            root.applied = [];
            const panel = createTemporaryObject(panelComponent, root);
            verify(panel !== null);
            panel.shell = root.shell();
            panel.open("{}");
            panel.initialFocus.forceActiveFocus(Qt.OtherFocusReason);
            verify(renderedFrame(panel));
            const view = descendants(panel).find(item => item.firstViewRoot === true);
            tryVerify(() => !view.first, 2000, "the steps after the first frame start");
            verify(!view.settled && !view.first, "the first frame is drawn and the later rows still build");
            verify(rowNamed(panel, "zulu") === null, "the last row is not built");
            keyClick("z");
            compare(panel.currentKey, "installed:installed/zulu", "type-ahead selects the last row");
            const row = rowNamed(panel, "zulu");
            verify(row !== null, "the move builds the row");
            const flick = descendants(panel).find(item => item instanceof Flickable && item.contentHeight > item.height);
            verify(flick !== undefined, "the list scrolls");
            const top = row.mapToItem(flick, 0, 0).y;
            verify(top >= 0 && top + row.height <= flick.height, "the row is in the list's view: top " + top + " in " + flick.height);
            keyClick(Qt.Key_Return);
            compare(root.applied, ["zulu"], "Return applies the selected row");
        }
    }
}
