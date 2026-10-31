import QtQuick
import QtQuick.Window
import QtTest
import qs.Ui
import qs.Unit

// inputs: shell/Ui/* shell/Ui/**/* shell/Commons/*
// Automations Cancel removes its Network Field hint while the following
// Notify row measures it. The nested VGS-2077 caller stack reaches the
// text measure before cached subText clears. Query that same production
// helper during textChanged, without relying on the adapter's binding order.
Item {
    id: root
    width: 700
    height: 500

    Component {
        id: fields
        Column {
            width: 600
            property alias field: field
            property alias below: below
            Field {
                id: field
                width: parent.width
                label: "Network"
                inline: true
                Switch { size: "sm" }
            }
            Field {
                id: below
                width: parent.width
                label: "Notify"
                inline: true
                Switch { size: "sm" }
            }
        }
    }

    UnitCase {
        name: "automation_network_hint"
        when: windowShown

        function cleanup() { UnitTheme.reset(); }

        function test_text_removal_keeps_the_following_row_measure_defined_data() {
            const cases = [
                { tag: "hint-to-none", hint: "Waiting", lines: [], nextHint: "", nextLines: [] },
                { tag: "hint-to-line", hint: "Waiting", lines: ["Detail"], nextHint: "", nextLines: ["Detail"] },
                { tag: "lines-to-none", hint: "", lines: ["Detail"], nextHint: "", nextLines: [] },
                { tag: "lines-to-link", hint: "Open details", lines: ["Detail"], nextHint: "Open details", nextLines: [], link: "details" }
            ];
            const rows = [];
            for (const light of [false, true])
                for (const inline of [false, true])
                    for (const row of cases)
                        rows.push(Object.assign({}, row, { tag: row.tag + "/" + light + "/" + inline, light: light, inline: inline }));
            return rows;
        }

        function test_text_removal_keeps_the_following_row_measure_defined(data) {
            failOnWarning(/.*/);
            if (data.light) compare(UnitTheme.override({ scheme: { mode: "light" } }), "ok");
            const rows = createTemporaryObject(fields, root);
            rows.field.inline = data.inline;
            rows.field.hint = data.hint;
            rows.field.lines = data.lines;
            rows.field.hintLink = data.link || "";
            verify(renderedFrame(rows));
            verify(waitForPolish(rows.Window.window));
            const slot = rows.field.children.find(child => typeof child.textLineBelow === "function");
            verify(slot !== undefined);
            const hint = slot.children.find(child => child instanceof LinkText);
            verify(hint !== undefined);
            let reentrantMeasures = 0;
            hint.textChanged.connect(() => {
                slot.textLineBelow();
                verify(Number.isFinite(rows.field.lineBelow()));
                verify(Number.isFinite(rows.field.inkBelow()));
                reentrantMeasures++;
            });
            rows.field.hint = data.nextHint;
            rows.field.lines = data.nextLines;
            if (data.hint !== data.nextHint) verify(reentrantMeasures > 0);
            verify(waitForPolish(rows.Window.window));
            slot.textLineBelow();
            verify(Number.isFinite(rows.field.lineBelow()));
            verify(Number.isFinite(rows.field.inkBelow()));
            verify(Number.isFinite(rows.below.topPadding));
        }
    }
}
