#!/usr/bin/env node
// Table-driven checks for vgs.fonts's pure decisions, FontsLogic.js: the
// names it reads from fontconfig's list, the families the terminal font's
// select keeps, and the family in effect it keeps offered. The lists are
// stand-ins and the expected values are written here by hand. Controls edit
// one rule at a time in a copy and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const logicFile = path.join(repo, "shell", "plugins", "vgs.fonts", "FontsLogic.js");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message);

// The families Qt lists: two proportional, three fixed-width.
const FAMILIES = ["Fira Code", "Fira Code Light", "Inter", "JetBrains Mono", "Noto Serif"];
// fontconfig's fixed-width list, one name a line: a font with two names, a
// font Qt does not list, and a name that holds a hyphen and a comma.
const LIST = "JetBrains Mono\nFira Code\nFira Code Light\nTerminus\nFoo-Bar, Mono\n";

function verify(logic) {
    const names = logic.listed(LIST);
    same(names, ["JetBrains Mono", "Fira Code", "Fira Code Light", "Terminus", "Foo-Bar, Mono"], "listed: one name a line, as fontconfig holds it");
    same(logic.listed(""), [], "listed: no fixed-width font");

    const terminal = logic.fixedWidth(FAMILIES, names);
    same(terminal, ["Fira Code", "Fira Code Light", "JetBrains Mono"], "fixedWidth: the fixed-width families, in Qt's order");
    assert.equal(terminal.indexOf("Inter"), -1, "fixedWidth: a proportional family is refused");
    same(logic.fixedWidth(FAMILIES, []), [], "fixedWidth: no family before fontconfig answers");

    same(logic.offers(terminal, "Inter"), ["Inter", "Fira Code", "Fira Code Light", "JetBrains Mono"], "offers: the family in effect stays offered when fontconfig does not list it");
    same(logic.offers(terminal, "Fira Code"), terminal, "offers: a listed family in effect is offered once");
    same(logic.offers(terminal, undefined), terminal, "offers: no family in effect adds none");
    same(logic.offers([], "Inter"), ["Inter"], "offers: the family in effect alone before fontconfig answers");
}

verify(load(logicFile));

const CONTROLS = [
    ["a proportional family is refused", `return names.indexOf(family) !== -1;`, `return true;`],
    ["a blank line is no family", `return name !== "";`, `return true;`],
    ["the family in effect stays offered", `? families : [shown].concat(families);`, `? families : families;`],
    ["a listed family in effect is offered once", `|| families.indexOf(shown) !== -1 ? families`, `? families`],
    ["no family in effect adds none", `typeof shown !== "string" || families.indexOf(shown) !== -1`, `families.indexOf(shown) !== -1`]
];

const source = fs.readFileSync(logicFile, "utf8");
const tempRoot = path.join(repo, "tmp");
fs.mkdirSync(tempRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(tempRoot, "fonts-logic-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "FontsLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on the mutated logic`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-fonts-logic: ok controls=${CONTROLS.length}`);
