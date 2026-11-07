#!/usr/bin/env node
// KeyNav's pure decisions, shell/Ui/foundation/KeyNavLogic.js, under node:
// keyboard intent, roving steps, type-ahead, reveal math, activation, a
// click's opener and shortcut keycap labels. The controls edit a temporary copy and require
// this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { spawnSync } = require("node:child_process");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const file = path.join(repo, "shell", "Ui", "foundation", "KeyNavLogic.js");
const captureNames = load(path.join(repo, "shell", "Core", "PluginLogic.js")).CAPTURE_KEY_NAMES;

// Real libxkbcommon answers, not a duplicate physical-position table.
const layouts = [["us", "U"], ["ru", "Г"]];
const nativeRows = layouts.map(([layout, want]) => {
    const run = spawnSync("python3", ["-I", path.join(repo, "bin/lib/xkb-keys.py")], {
        input: JSON.stringify({ keyboard: { layout, variant: "", options: "", activeLayoutIndex: 0 }, keys: ["SUPER+code:30", "code:105", "code:108"] }),
        encoding: "utf8", timeout: 10000, env: { PATH: process.env.PATH, LANG: "C.UTF-8" }
    });
    assert.ifError(run.error);
    assert.equal(run.status, 0, run.stderr || run.stdout);
    const answer = JSON.parse(run.stdout);
    assert.equal(answer.ok, true);
    return { layout, want, names: Object.fromEntries(answer.keys.map(row => ["CODE:" + row.keycode, row])) };
});
const labelsOnly = process.argv.length === 3 && process.argv[2] === "--labels-only";
assert.ok(process.argv.length === 2 || labelsOnly, "only --labels-only is supported");

function verifyLabels(logic) {
    const rows = [
        ["SUPER+SHIFT+T", undefined, ["Super", "Shift", "T"]],
        ["Ctrl+PageDown", undefined, ["Ctrl", "PageDown"]],
        ["SUPER+code:30", nativeRows[0].names, ["Super", "U"]],
        ["SUPER+code:30", nativeRows[1].names, ["Super", "Г"]],
        ["SUPER+SHIFT+CODE:0030", nativeRows[0].names, ["Super", "Shift", "U"]],
        ["code:0108", nativeRows[0].names, ["Right Alt"]],
        ["SUPER+code:105", nativeRows[0].names, ["Super", "Right Ctrl"]],
        ["SUPER+code:109", {}, ["Choose a key in [Settings](page:vgs.settings)"]],
        ["SUPER+code:30", null, ["Choose a key in [Settings](page:vgs.settings)"]],
        ["SUPER+code:30", { "CODE:30": null }, ["Choose a key in [Settings](page:vgs.settings)"]],
        ["SUPER+code:30+SHIFT", {}, ["Choose a key in [Settings](page:vgs.settings)"]],
        ["SUPER+SLASH", { SLASH: { keysym: "SLASH", codepoint: 47 } }, ["Super", "/"]],
        ["SUPER+ALT+PERIOD", logic.symbolNames(captureNames), ["Super", "Alt", "."]],
        ["", {}, []],
        [null, {}, []]
    ];
    for (const [shortcut, names, caps] of rows) {
        const stored = shortcut;
        assert.deepEqual(Array.from(logic.keyCaps(shortcut, names)), caps, "shortcut display contract: " + shortcut);
        assert.equal(shortcut, stored, "display does not rewrite the stored binding");
    }
    assert.deepEqual(Array.from(logic.physicalKeys(["SUPER+code:0030", "code:30", "SHIFT+T", null, "CODE:105"])),
        ["code:105", "code:30"], "current keys discover and normalize physical parts");
    for (const { layout, want, names } of nativeRows)
        console.log("layout-label: layout=" + layout + " key=SUPER+code:30 label=" + logic.keyCaps("SUPER+code:30", names).join("+") + " want=Super+" + want);
}

function verify(logic) {
    verifyLabels(logic);
    if (labelsOnly) return;
    const K = logic.KEY;
    const M = logic.MOD;
    assert.equal(logic.intent(K.Down, 0, "vertical", false), "next", "Down moves a vertical composite");
    assert.equal(logic.intent(K.Up, 0, "vertical", false), "prev", "Up moves a vertical composite");
    assert.equal(logic.intent(K.Right, 0, "horizontal", false), "next", "Right moves a horizontal composite");
    assert.equal(logic.intent(K.Left, 0, "horizontal", false), "prev", "Left moves a horizontal composite");
    assert.equal(logic.intent(K.Home, 0, "vertical", false), "first", "Home reaches the first row");
    assert.equal(logic.intent(K.End, 0, "vertical", false), "last", "End reaches the last row");
    assert.equal(logic.intent(K.PageUp, 0, "vertical", false), "pagePrev", "PageUp moves a page");
    assert.equal(logic.intent(K.PageDown, 0, "vertical", false), "pageNext", "PageDown moves a page");
    assert.equal(logic.intent(K.Space, 0, "vertical", false), "activate", "Space activates a composite row");
    assert.equal(logic.intent(K.Space, 0, "vertical", false, { spaceActivates: false }), "", "an owner can keep Space for text entry");
    assert.equal(logic.intent(K.Return, 0, "vertical", false), "activate", "Return activates a composite row");
    assert.equal(logic.intent(K.Enter, 0x20000000, "vertical", false), "activate", "keypad Enter activates a composite row");
    assert.equal(logic.intent(K.Delete, 0, "vertical", false), "remove", "Delete removes a selected row");
    assert.equal(logic.intent(K.F10, M.Shift, "vertical", false), "menu", "Shift+F10 opens a context menu");
    assert.equal(logic.intent(K.Menu, 0, "vertical", false), "menu", "the Menu key opens a context menu");
    assert.equal(logic.intent(K.Tab, M.Control, "vertical", false), "tabNext", "Ctrl+Tab switches to the next tab");
    assert.equal(logic.intent(K.Tab, M.Control | M.Shift, "vertical", false), "tabPrev", "Ctrl+Shift+Tab switches to the previous tab");
    assert.equal(logic.intent(K.PageDown, M.Control, "vertical", false), "tabNext", "Ctrl+PageDown switches to the next tab");
    assert.equal(logic.intent(K.PageUp, M.Control, "vertical", false), "tabPrev", "Ctrl+PageUp switches to the previous tab");
    assert.equal(logic.intent(K.Left, 0, "vertical", false, { crossAxis: true }), "crossPrev", "Left crosses to the previous choice in a vertical row");
    assert.equal(logic.intent(K.Right, 0, "vertical", false, { crossAxis: true }), "crossNext", "Right crosses to the next choice in a vertical row");
    assert.equal(logic.intent(K.Left, 0, "horizontal", true), "", "a text entry keeps Left for the caret");
    assert.equal(logic.intent(K.Up, 0, "vertical", true), "prev", "a text entry in a searchable list keeps Up for the list");
    assert.equal(logic.intent(K.Down, 0, "vertical", true), "next", "a text entry in a searchable list keeps Down for the list");
    assert.equal(logic.intent(K.Space, 0, "horizontal", true), "", "a text entry keeps Space for text");
    assert.equal(logic.intent(K.Home, M.Control, "vertical", true), "first", "Ctrl+Home leaves a text field for the list");
    assert.equal(logic.intent(K.End, M.Control, "vertical", true), "last", "Ctrl+End leaves a text field for the list");

    const reachable = index => index !== 1 && index !== 4;
    assert.equal(logic.step(-1, 5, 1, true, reachable), 0, "from none forward reaches the first row");
    assert.equal(logic.step(-1, 5, -1, true, reachable), 3, "from none backward reaches the last row");
    assert.equal(logic.step(-1, 5, -1, false, reachable), 3, "from none backward without wrap reaches the last row");
    assert.equal(logic.step(0, 5, 1, true, reachable), 2, "step skips an unreachable row");
    assert.equal(logic.step(3, 5, 1, true, reachable), 0, "wrapped step skips an unreachable tail");
    assert.equal(logic.step(3, 5, 1, false, reachable), 3, "clamped step stays when only unreachable rows follow");
    assert.equal(logic.step(5, 8, 3, false, index => index !== 7), 6, "PageDown lands before an unreachable page target");
    assert.equal(logic.step(2, 8, -3, false, index => index !== 0), 1, "PageUp lands after an unreachable page target");
    assert.equal(logic.edge(5, reachable, false), 0, "first edge skips unreachable rows");
    assert.equal(logic.edge(5, reachable, true), 3, "last edge skips unreachable rows");
    assert.equal(logic.pageRows(93, 20), 4, "pageRows floors visible rows");
    assert.equal(logic.pageRows(0, 20), 1, "pageRows keeps one row minimum");

    const labels = ["Alpha", "Beta", "Bravo", "Gamma"];
    let typed = logic.typeAhead("", "b", labels, null, 0);
    assert.equal(typed.typed, "b", "type-ahead starts a prefix");
    assert.equal(typed.index, 1, "type-ahead starts after the current row");
    typed = logic.typeAhead("b", "r", labels, null, 1);
    assert.equal(typed.typed, "br", "type-ahead extends a prefix");
    assert.equal(typed.index, 2, "type-ahead reaches the extended prefix");
    typed = logic.typeAhead("a", "p", ["Apple", "Apricot"], null, 0);
    assert.equal(typed.typed, "ap", "multi-letter type-ahead keeps the current matching entry");
    assert.equal(typed.index, 0, "multi-letter type-ahead starts at the current entry");
    typed = logic.typeAhead("br", "g", labels, null, 2);
    assert.equal(typed.typed, "g", "type-ahead falls back to one letter");
    assert.equal(typed.index, 3, "type-ahead reaches the fallback prefix");
    assert.equal(logic.printable("x", 0), "x", "plain typed text is printable");
    assert.equal(logic.printable("x", M.Control), "", "modified typed text is not printable");
    assert.equal(logic.revealY(8, 10, 20, 60, 4), 4, "reveal moves up with a margin");
    assert.equal(logic.revealY(90, 20, 20, 60, 4), 54, "reveal moves down with a margin");
    assert.equal(logic.revealY(40, 10, 20, 60, 4), 20, "reveal keeps a visible item still");
    assert.equal(logic.revealY(8.5, 10, 20, 60, 4), 4, "a reveal up lands on the whole pixel above the item");
    assert.equal(logic.revealY(90.25, 20, 20, 60, 4), 55, "a reveal down lands on the whole pixel below the item");

    const exclusive = { enabled: true, checkable: true, checked: false, autoExclusive: true, clickedCount: 0, clicked() { this.clickedCount += 1; } };
    assert.equal(logic.activate(exclusive), true, "activation reaches an enabled control");
    assert.equal(exclusive.checked, true, "activation checks an exclusive checkable");
    assert.equal(exclusive.clickedCount, 1, "activation emits clicked");
    const check = { enabled: true, checkable: true, checked: false, toggledValue: null, toggled() { this.toggledValue = this.checked; } };
    logic.activate(check);
    assert.equal(check.checked, true, "activation toggles a checkable");
    assert.equal(check.toggledValue, true, "activation emits toggled with the new value");
    assert.equal(logic.activate({ enabled: false, clicked() { throw new Error("disabled clicked"); } }), false, "disabled controls do not activate");
    assert.equal(logic.activate({ enabled: true, lock: { locked: true }, clicked() { throw new Error("locked clicked"); } }), false, "locked controls do not activate");
    assert.equal(logic.activate({ enabled: true, lock: { locked: false }, clicked() {} }), true, "an unlocked control activates");
    assert.equal(logic.opener({ visualFocus: true }), "key", "a click on a control showing keyboard focus came from a key");
    assert.equal(logic.opener({ visualFocus: false }), "pointer", "a click on a control without keyboard focus came from the pointer");

}

verify(load(file));

const CONTROLS = [
    ["Space activation switch", "if (key === KEY.Space) return spaceActivates ? \"activate\" : \"\";", "if (key === KEY.Space) return \"activate\";"],
    ["Enter activation", "if (key === KEY.Return || key === KEY.Enter) return \"activate\";", "if (false) return \"activate\";"],
    ["Delete intent", "if (key === KEY.Delete) return \"remove\";", "if (false) return \"remove\";"],
    ["menu intent", "if (((key === KEY.F10 && has(modifiers, MOD.Shift)) || key === KEY.Menu) && (modifiers & (MOD.Control | MOD.Alt | MOD.Meta)) === 0) return \"menu\";", "if (false) return \"menu\";"],
    ["tab intent", "if (key === KEY.Tab || key === KEY.PageDown) return has(modifiers, MOD.Shift) ? \"tabPrev\" : \"tabNext\";", "if (false) return has(modifiers, MOD.Shift) ? \"tabPrev\" : \"tabNext\";"],
    ["cross-axis intent", "if (key === KEY.Left) return \"crossPrev\";", "if (false) return \"crossPrev\";"],
    ["text-entry caret ownership", "if ((key === KEY.Return || key === KEY.Enter) && plain(modifiers)) return \"activate\";\n        if ((key === KEY.Up || key === KEY.Down) && plain(modifiers)) return key === KEY.Up ? \"prev\" : \"next\";\n        return \"\";", "if (key === KEY.Space || key === KEY.Return || key === KEY.Enter) return \"activate\";\n        if ((key === KEY.Up || key === KEY.Down) && plain(modifiers)) return key === KEY.Up ? \"prev\" : \"next\";\n        return \"\";"],
    ["text-entry vertical movement", "if ((key === KEY.Up || key === KEY.Down) && plain(modifiers)) return key === KEY.Up ? \"prev\" : \"next\";", "if ((key === KEY.Up || key === KEY.Down) && plain(modifiers)) return \"\";"],
    ["reachable skipping", "if (reachableAt(reachable, at)) return at;", "return at;"],
    ["from-none backward", "if (index < 0 || index >= count) return edge(count, reachable, delta < 0);", "if (index < 0 || index >= count) return edge(count, reachable, false);"],
    ["page target reachability", "for (var down = target; down > index; down--) if (reachableAt(reachable, down)) return down;", "for (var down = target; down > index; down--) return down;"],
    ["reverse page target reachability", "for (var up = target; up < index; up++) if (reachableAt(reachable, up)) return up;", "for (var up = target; up < index; up++) return up;"],
    ["type-ahead fallback", "wanted = lower;\n        found = findPrefix(wanted, labels, reachable, from, false);", "wanted = lower;\n        found = -1;"],
    ["type-ahead current prefix", "var found = findPrefix(wanted, labels, reachable, from, typed !== \"\");", "var found = findPrefix(wanted, labels, reachable, from, false);"],
    ["disabled activation", "if (control === null || control === undefined || control.enabled === false) return false;", "if (control === null || control === undefined) return false;"],
    ["locked activation", "if (control.lock !== undefined && control.lock !== null && control.lock.locked === true) return false;", ""],
    ["key opener", "return control.visualFocus === true ? \"key\" : \"pointer\";", "return \"pointer\";"],
    ["pointer opener", "return control.visualFocus === true ? \"key\" : \"pointer\";", "return \"key\";"],
    ["keycap modifier display", "\"SUPER\": \"Super\",", "\"SUPER\": \"SUPER\","],
    ["layout-label old raw code", 'var physical = /^CODE:[0-9]+$/.test(upper);', 'var physical = /^CODE:[0-9]+$/.test(upper); if (physical) return "Code:" + Number(upper.slice(5));'],
    ["layout-label fixed US map", 'var physical = /^CODE:[0-9]+$/.test(upper);', 'var physical = /^CODE:[0-9]+$/.test(upper); if (upper === "CODE:30") return "U";'],
    ["layout-label missing name", 'return UNNAMED_KEY;', 'return key;'],
    ["layout-label fallback retains key parts", 'if (label === UNNAMED_KEY) return [label];', 'if (false) return [label];'],
    ["layout-label symbol inputs", 'if (value > 32 && value < 127)', 'if (false)'],
    ["layout-label leading zeros", 'if (physical) upper = "CODE:" + String(Number(upper.slice(5)));', 'if (physical) upper = "CODE:" + upper.slice(5);']
];

const source = fs.readFileSync(file, "utf8");
const scratchRoot = os.tmpdir();
fs.mkdirSync(scratchRoot, { recursive: true });
const scratch = fs.mkdtempSync(path.join(scratchRoot, "test-key-nav-logic-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        if (labelsOnly && !label.startsWith("layout-label ")) continue;
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(scratch, "KeyNavLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
        } catch (_e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on a copy without that rule`);
        if (label.startsWith("layout-label ")) console.log("control: killed " + label);
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
console.log(`test-key-nav-logic: ok controls=${labelsOnly ? CONTROLS.filter(row => row[0].startsWith("layout-label ")).length : CONTROLS.length}`);
