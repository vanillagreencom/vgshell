#!/usr/bin/env node
// Table-driven checks for vgs.fonts's pure decisions, FontsLogic.js: the
// fonts it reads from fontconfig's list, the families the interface font's
// select keeps, the families the terminal font's select keeps, and the
// family in effect it keeps offered. The lists are stand-ins and the
// expected values are written here by hand. Controls edit one rule at a time
// in a copy and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const logicFile = path.join(repo, "shell", "plugins", "vgs.fonts", "FontsLogic.js");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message);

// One font a line as the pane's fc-list format prints it: spacing, charset,
// then each name, a tab before each. Each row is a font, the line, its
// names, and whether it is a terminal font.
const FONTS = [
    ["two fonts of one family, each with a style name", "100\t20-7e a0-17e\tFira Code\tFira Code Light", ["Fira Code", "Fira Code Light"], true],
    ["", "100\t20-7e\tFira Code\tFira Code Retina", ["Fira Code", "Fira Code Retina"], true],
    ["adjacent charset ranges cover printable ASCII", "100\t20-40 41-7e e000-e0ff\tJetBrains Mono", ["JetBrains Mono"], true],
    ["a range that starts below the space covers it", "100\t0-ff\tFoo-Bar, Mono", ["Foo-Bar, Mono"], true],
    ["an icon font maps letters but not all punctuation", "100\t20 2e 30-39 41-5a 5f 61-7a a0 e000-e004\tMaterial Symbols Outlined", ["Material Symbols Outlined"], false],
    ["an emoji font maps no letters", "100\t20 23 2a 30-39 a9 ae\tNoto Color Emoji", ["Noto Color Emoji"], false],
    ["a fixed-width font with a gap in printable ASCII", "100\t20-3f 41-7e\tGapped Mono", ["Gapped Mono"], false],
    ["a fixed-width font whose one gap is below the digits, no #", "100\t20-22 24-7e\tHashless Mono", ["Hashless Mono"], false],
    ["a fixed-width font that stops before the tilde", "100\t20-7d\tShort Mono", ["Short Mono"], false],
    ["a proportional font with a spacing element", "0\t20-7e\tPlain Serif", ["Plain Serif"], false],
    ["a font with no spacing element", "\t\tInter\tInter Light", ["Inter", "Inter Light"], false],
    ["a family that is a style name of another font", "\t\tNoto Sans\tNoto Sans Display", ["Noto Sans", "Noto Sans Display"], false],
    ["", "\t\tNoto Sans Display", ["Noto Sans Display"], false]
];
// fontconfig's list: the fonts, with blank lines between and after them.
const LIST = FONTS.map(([, line]) => line).join("\n\n") + "\n";

// The families Qt lists, in Qt's order: every name above, and Inter
// Variable, a family the shell loads itself, which fontconfig does not list.
const FAMILIES = [
    "Fira Code", "Fira Code Light", "Fira Code Retina", "Foo-Bar, Mono", "Gapped Mono", "Hashless Mono", "Inter", "Inter Light",
    "Inter Variable", "JetBrains Mono", "Material Symbols Outlined", "Noto Color Emoji", "Noto Sans",
    "Noto Sans Display", "Plain Serif", "Short Mono"
];

function verify(logic) {
    const fonts = logic.listed(LIST);
    FONTS.forEach(([label, line, names, terminal], at) => {
        same(fonts[at], { names: names, terminal: terminal }, `listed: ${label || line}`);
    });
    assert.equal(fonts.length, FONTS.length, "listed: a blank line is no font");
    same(logic.listed(""), [], "listed: no font");

    same(logic.families(FAMILIES, fonts), [
        "Fira Code", "Foo-Bar, Mono", "Gapped Mono", "Hashless Mono", "Inter", "Inter Variable", "JetBrains Mono",
        "Material Symbols Outlined", "Noto Color Emoji", "Noto Sans", "Noto Sans Display", "Plain Serif", "Short Mono"
    ], "families: each family once, no style name, a family fontconfig does not list kept, in Qt's order");
    same(logic.families(FAMILIES, []), FAMILIES, "families: every family before fontconfig answers");

    same(logic.terminal(FAMILIES, fonts), ["Fira Code", "Foo-Bar, Mono", "JetBrains Mono"], "terminal: the fixed-width families that draw printable ASCII, each once, in Qt's order");
    same(logic.terminal(FAMILIES, []), [], "terminal: no family before fontconfig answers");

    const terminal = logic.terminal(FAMILIES, fonts);
    same(logic.offers(terminal, "Inter"), ["Inter", "Fira Code", "Foo-Bar, Mono", "JetBrains Mono"], "offers: the family in effect stays offered when the list does not hold it");
    same(logic.offers(terminal, "Fira Code"), terminal, "offers: a listed family in effect is offered once");
    same(logic.offers(terminal, undefined), terminal, "offers: no family in effect adds none");
    same(logic.offers([], "Inter"), ["Inter"], "offers: the family in effect alone before fontconfig answers");
}

verify(load(logicFile));

const CONTROLS = [
    ["a style-name entry is dropped", `return first[family] === true || other[family] !== true;`, `return true;`],
    ["a first name stays though another font lists it", `return first[family] === true || other[family] !== true;`, `return other[family] !== true;`],
    ["a family fontconfig does not list stays", `|| other[family] !== true;`, `|| false;`],
    ["an icon font is refused", `covers(fields[1] || "", TEXT_FIRST, TEXT_LAST)`, `covers(fields[1] || "", 0x61, 0x7a)`],
    ["coverage starts at the space", `var TEXT_FIRST = 0x20;`, `var TEXT_FIRST = 0x30;`],
    ["a gap in the charset is not covered", `if (low > next) return false;`, ``],
    ["a charset that stops early is not covered", `if (next > last) return true;\n    }\n    return false;`, `if (next > last) return true;\n    }\n    return true;`],
    ["adjacent ranges are covered", `if (high >= next) next = high + 1;`, `if (high >= next) next = high;`],
    ["a proportional font is refused", `fields[0] === FIXED_WIDTH && `, ``],
    ["a style name of a terminal font is no terminal family", `first[font.names[0]] = true;`, `font.names.forEach(function (name) { first[name] = true; });`],
    ["a blank line is no font", `return line !== "";`, `return true;`],
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
