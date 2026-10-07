#!/usr/bin/env node
// Exercise the shipped catalog parser, ordered edits and active layout
// selection. Disposable mutations must fail these same assertions.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const repo = path.join(__dirname, "..");
const file = path.join(repo, "shell/plugins/vgs.keyboard/KeyboardLogic.js");
const fixture = fs.readFileSync(path.join(__dirname, "fixtures/keyboard/evdev.xml"), "utf8");
const same = (got, want) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want);
const devices = { keyboards: [{ name: "aux", layout: "fr", variant: "", main: false, activeLayoutIndex: 0, activeKeymap: "French" }, { name: "main", layout: "us,de", variant: ",nodeadkeys", main: true, activeLayoutIndex: 1, activeKeymap: "German" }] };
function verify(logic) {
    const catalog = logic.parseCatalog(fixture);
    same(catalog, [{ code: "us", name: "English (US)", variants: [{ code: "intl", name: "English (US, intl., with dead keys)" }, { code: "altgr-intl", name: "English & international" }] }, { code: "de", name: "German", variants: [{ code: "nodeadkeys", name: "German (no dead keys)" }] }, { code: "fr", name: "Français", variants: [] }]);
    for (const bad of ["<layoutList></layoutList>", "<layoutList><layout></layout></layoutList>", "<layoutList>", fixture + " ".repeat(logic.XML_MAX)]) assert.throws(() => logic.parseCatalog(bad));
    const huge = '<layoutList>' + '<layout><configItem><name>us</name><description>' + 'a'.repeat(logic.DATA_MAX) + '</description></configItem></layout></layoutList>';
    assert.throws(() => logic.parseCatalog(huge));
    const rows = [{ code: "us", variant: "" }, { code: "de", variant: "nodeadkeys" }];
    for (const [layouts, variants, source, want] of [["", "", devices, rows], ["fr,us", ",intl", devices, [{ code: "fr", variant: "" }, { code: "us", variant: "intl" }]], ["", "", null, []]]) same(logic.sources(layouts, variants, source), want);
    same(logic.serialize(rows), { layouts: "us,de", variants: ",nodeadkeys" });
    same(logic.addSource(rows, "us", ""), rows);
    same(logic.addSource(rows, "us", "intl"), rows.concat([{ code: "us", variant: "intl" }]));
    same(logic.moveSource(rows, 1, -1), [rows[1], rows[0]]);
    same(logic.moveSource(rows, 0, 1), [rows[1], rows[0]]);
    same(logic.moveSource(rows, 0, -1), rows);
    same(logic.removeSource(rows, 0), [rows[1]]);
    same(logic.removeSource([rows[0]], 0), [rows[0]]);
    same(logic.activeValue(devices, null), { code: "DE", name: "German", count: 2 });
    same(logic.activeValue(devices, { keyboard: "main", name: "English, alternate" }), { code: "DE", name: "English, alternate", count: 2 });
    same(logic.activeValue(devices, { keyboard: "aux", name: "French" }), { code: "DE", name: "German", count: 2 });
    same(logic.activeValue(null, null), { code: "", name: "", count: 0 });
    same(logic.sourceRows(rows, catalog).map(row => [row.key, row.text, row.secondary]), [["0", "English (US)", "Default"], ["1", "German", "German (no dead keys)"]]);
}
verify(load(file));
const controls = [
    ["layout parse", "var row = configItem(layout[1]);", 'var row = {code:"wrong",name:"wrong"};'],
    ["source bound", 'if (xml.length > XML_MAX) throw new Error("catalog=source-bound");', 'if (false) throw new Error("catalog=source-bound");'],
    ["data bound", 'if (JSON.stringify(layouts).length > DATA_MAX) throw new Error("catalog=data-bound");', 'if (false) throw new Error("catalog=data-bound");'],
    ["ordered move", "next.splice(target, 0, moved);", "next.splice(index, 0, moved);"],
    ["last source", "if (rows.length <= 1 || index < 0 || index >= rows.length) return rows;", "if (index < 0 || index >= rows.length) return rows;"],
    ["variant alignment", 'return { layouts: rows.map(function (row) { return row.code; }).join(","),', 'return { layouts: rows.map(function (row) { return row.variant; }).join(","),'],
    ["main keyboard", "return rows.find(function (row) { return row.main; }) || rows[0];", "return rows[0];"]
];
const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(repo, "tmp/keyboard-logic-"));
try {
    for (const [label, needle, replacement] of controls) {
        assert.equal(source.split(needle).length, 2, label);
        const mutant = path.join(temp, "KeyboardLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => verify(load(mutant)), undefined, label);
    }
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
console.log(`test-keyboard-logic: ok controls=${controls.length}`);
