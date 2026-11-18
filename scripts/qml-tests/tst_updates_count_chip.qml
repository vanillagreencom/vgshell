import QtQuick
import QtTest
import "../../shell/plugins/vgs.updates" as Updates
import "../../shell/plugins/vgs.updates/UpdatesLogic.js" as Logic

// inputs: shell/plugins/vgs.updates/*
Item {
    id: root
    width: 700
    height: 700
    Component { id: flyout; Updates.Window { anchors.fill: parent } }

    function descendants(item) {
        let found = [];
        for (const child of item.children) found = found.concat([child], descendants(child));
        return found;
    }

    TestCase {
        name: "UpdatesCountChip"
        when: windowShown

        function test_vgs_build_uses_the_source_count_chip() {
            const view = createTemporaryObject(flyout, root);
            const now = Date.now();
            const sources = [Logic.sourceRow("aur", 5, [], now, null),
                             Logic.sourceRow("vgs", 0, [], now, null, { kind: "aurUpgrade" })];
            view.shell = { screens: { current: null }, status: { values: {
                sources: sources, pending: 5, checkState: { tone: "ok", text: "Updates available" }
            } } };
            function chip(source) {
                const row = root.descendants(view).find(item => item.focusItem !== undefined && item.modelData?.source === source);
                return row && root.descendants(row.focusItem).find(item => item.visible && item.displayedText !== undefined);
            }
            tryVerify(() => !!chip("aur") && !!chip("vgs"));
            const aur = chip("aur"), vgs = chip("vgs");
            compare([vgs.displayedText, vgs.size, vgs.color, vgs.foreground],
                    ["1", aur.size, aur.color, aur.foreground]);
            compare(aur.displayedText, "5");
            const heading = root.descendants(view).find(item => item.role === "hint"
                && item.visible && /^\d+ updates$/.test(item.text));
            verify(heading !== undefined, "the heading shows the total");
            compare(heading.text, (Number(aur.displayedText) + Number(vgs.displayedText)) + " updates");
        }
    }
}
