import QtQuick
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.capture" as Capture

// The Capture panel's target tiles are a mode chooser, not a settings input:
// they span the panel's content, flush with the full-width primary action.
Item {
    id: root
    width: 1200
    height: 1000

    Component {
        id: options
        Capture.Options { width: Theme.size.panel.lg; height: implicitHeight }
    }

    UnitCase {
        name: "captureOptions"
        when: windowShown

        function init() { void Theme.color; UnitTheme.reset(); }
        function descendants(item) {
            let out = [];
            for (const child of item.children) out = out.concat([child], descendants(child));
            return out;
        }
        function shell() {
            return {
                status: { values: {}, rows: [], act: key => "ok" },
                manifest: { name: "Capture", schema: { ocrLanguages: { label: "Languages", presets: [] } } },
                settings: {},
                ipc: { call: (name, payload) => "ok" },
                compositor: { readWindows: done => {} },
                surfaces: { hide: id => {}, openPage: (page, tab) => {} },
                screens: { all: [] }
            };
        }

        function test_tiles_span_the_panel() {
            const view = createTemporaryObject(options, root, { shell: shell() });
            verify(view !== null);
            verify(renderedFrame(view));
            const pane = descendants(view).find(item => item instanceof Pane);
            const tiles = descendants(view).find(item => item instanceof TileGroup);
            const action = view.initialFocus;
            verify(pane !== undefined && tiles !== undefined && action instanceof Button);
            verify(pane.contentWidth > Theme.control.maxWidth, "the panel is wider than a settings input");
            tryCompare(tiles, "width", pane.contentWidth);
            compare(tiles.mapToItem(view, 0, 0).x, action.mapToItem(view, 0, 0).x);
            compare(tiles.width, action.width);
        }
    }
}
