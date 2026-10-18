#!/usr/bin/env node
// The one reference reader (shell/Commons/PageReference.js): parse
// answers a text's first reference, its words, page and tab, and the text
// with the words in the reference's place, for every form LinkText draws,
// a page reference's and a file reference's; plain answers that text
// alone, and file the path a file reference's page names. The control
// edits a disposable copy and requires the rows it names to fail.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const file = path.join(__dirname, "..", "shell", "Commons", "PageReference.js");
const same = (got, want, name) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, name);

// Each row: [name, text, parse, plain].
const CASES = [
    ["no reference", "Turn it on in Plugins.",
        { text: "Turn it on in Plugins.", words: "", page: "", tab: "", reference: "" }, "Turn it on in Plugins."],
    ["a page", "[Models](page:acme.models) holds the keys.",
        { text: "Models holds the keys.", words: "Models", page: "acme.models", tab: "", reference: "[Models](page:acme.models)" }, "Models holds the keys."],
    ["a page and a tab", "Add a key on [Models](page:acme.models/Setup) first.",
        { text: "Add a key on Models first.", words: "Models", page: "acme.models", tab: "Setup", reference: "[Models](page:acme.models/Setup)" }, "Add a key on Models first."],
    ["an empty page", "Turn it on in [Plugins](page:).",
        { text: "Turn it on in Plugins.", words: "Plugins", page: "", tab: "", reference: "[Plugins](page:)" }, "Turn it on in Plugins."],
    ["two references, the first wins", "[Models](page:acme.models/Setup) or [Voice](page:vgs.voice).",
        { text: "Models or [Voice](page:vgs.voice).", words: "Models", page: "acme.models", tab: "Setup", reference: "[Models](page:acme.models/Setup)" }, "Models or Voice."],
    ["spaces inside the words", "Add a key on the [Models page](page:acme.models/Setup).",
        { text: "Add a key on the Models page.", words: "Models page", page: "acme.models", tab: "Setup", reference: "[Models page](page:acme.models/Setup)" }, "Add a key on the Models page."],
    ["a Settings field", "Choose it in [Home folder](page:acme.models/Settings/home).",
        { text: "Choose it in Home folder.", words: "Home folder", page: "acme.models", tab: "Settings/home", reference: "[Home folder](page:acme.models/Settings/home)" }, "Choose it in Home folder."],
    ["a field on another tab is no reference", "Open [Home](page:acme.models/Setup/home).",
        { text: "Open [Home](page:acme.models/Setup/home).", words: "", page: "", tab: "", reference: "" }, "Open [Home](page:acme.models/Setup/home)."],
    ["a file in the configuration directory", "Edit [hyprland.lua](file:hypr%2Fhyprland.lua) by hand.",
        { text: "Edit hyprland.lua by hand.", words: "hyprland.lua", page: "file:hypr%2Fhyprland.lua", tab: "", reference: "[hyprland.lua](file:hypr%2Fhyprland.lua)" }, "Edit hyprland.lua by hand."],
    ["an absolute file", "See [the hook](file:%2Fetc%2Fpacman.d%2Fhooks%2Fvgs.hook).",
        { text: "See the hook.", words: "the hook", page: "file:%2Fetc%2Fpacman.d%2Fhooks%2Fvgs.hook", tab: "", reference: "[the hook](file:%2Fetc%2Fpacman.d%2Fhooks%2Fvgs.hook)" }, "See the hook."],
    ["a file in the home folder", "Shorten [AGENTS.md](file:~%2F.local%2Fshare%2Fvgs%2FAGENTS.md).",
        { text: "Shorten AGENTS.md.", words: "AGENTS.md", page: "file:~%2F.local%2Fshare%2Fvgs%2FAGENTS.md", tab: "", reference: "[AGENTS.md](file:~%2F.local%2Fshare%2Fvgs%2FAGENTS.md)" }, "Shorten AGENTS.md."],
    ["a folder", "Remove skills from [the skills folder](file:~%2Fvgs%2Fskills%2F).",
        { text: "Remove skills from the skills folder.", words: "the skills folder", page: "file:~%2Fvgs%2Fskills%2F", tab: "", reference: "[the skills folder](file:~%2Fvgs%2Fskills%2F)" }, "Remove skills from the skills folder."],
    ["a file before a page, the first wins", "[notes](file:notes.md) or [Voice](page:vgs.voice).",
        { text: "notes or [Voice](page:vgs.voice).", words: "notes", page: "file:notes.md", tab: "", reference: "[notes](file:notes.md)" }, "notes or Voice."],
    ["a file with a space is no reference", "Open [notes](file:my notes.md).",
        { text: "Open [notes](file:my notes.md).", words: "", page: "", tab: "", reference: "" }, "Open [notes](file:my notes.md)."],
    ["a file with spaces and parentheses", "Open [notes](file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md).",
        { text: "Open notes.", words: "notes", page: "file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md", tab: "", reference: "[notes](file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md)" }, "Open notes."],
    ["an empty file is no reference", "Open [notes](file:).",
        { text: "Open [notes](file:).", words: "", page: "", tab: "", reference: "" }, "Open [notes](file:)."]
];

// Each row: [name, page, file].
const FILES = [
    ["a file path with spaces and parentheses", "file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md", "/home/My Home/notes (draft).md"],
    ["a literal percent decodes once", "file:notes%2520%20%28draft%29.md", "notes%20 (draft).md"],
    ["a file reference's page", "file:~%2Fvgs%2FAGENTS.md", "~/vgs/AGENTS.md"],
    ["a plugin page", "acme.models", ""],
    ["no page", "", ""]
];

// Each row: [name, tab, place].
const PLACES = [
    ["a tab alone", "Setup", { tab: "Setup", field: "" }],
    ["no tab", "", { tab: "", field: "" }],
    ["Settings at a field", "Settings/home", { tab: "Settings", field: "home" }]
];

// The names of the rows LIBRARY fails.
function failures(library) {
    const failed = [];
    for (const [name, text, parsed, plain] of CASES) {
        try {
            same(library.parse(text), parsed, name + ": parse");
            assert.equal(library.plain(text), plain, name + ": plain");
        } catch (e) {
            if (!(e instanceof assert.AssertionError)) throw e;
            failed.push(name);
        }
    }
    for (const [name, page, path] of FILES) {
        try {
            assert.equal(library.file(page), path, name + ": file");
        } catch (e) {
            if (!(e instanceof assert.AssertionError)) throw e;
            failed.push(name);
        }
    }
    for (const [name, tab, place] of PLACES) {
        try {
            same(library.place(tab), place, name + ": place");
        } catch (e) {
            if (!(e instanceof assert.AssertionError)) throw e;
            failed.push(name);
        }
    }
    try {
        assert.equal(library.fileReference("notes", "/home/My Home/notes (draft).md"), "[notes](file:%2Fhome%2FMy%20Home%2Fnotes%20%28draft%29.md)");
        same(library.references("notes [notes](file:a.md) or [notes](page:vgs.voice/Setup)."), {
            text: "notes notes or notes.", links: [
                { start: 6, end: 11, words: "notes", page: "file:a.md", tab: "", reference: "[notes](file:a.md)" },
                { start: 15, end: 20, words: "notes", page: "vgs.voice", tab: "Setup", reference: "[notes](page:vgs.voice/Setup)" }
            ]
        }, "positioned references");
    } catch (e) {
        if (!(e instanceof assert.AssertionError)) throw e;
        failed.push("producer and positioned references");
    }
    return failed;
}
same(failures(load(file)), [], "every row holds");

// Each control: [name, text to replace, replacement, rows that must fail].
const CONTROLS = [
    ["a file path without decoding", "decodeURIComponent(page.slice(FILE_SCHEME.length))", "page.slice(FILE_SCHEME.length)", ["a file path with spaces and parentheses", "a literal percent decodes once"]],
    ["a parser without the tab group", "(?:\\/(Settings\\/[^\\s()\\/]+|[^\\s()\\/]+))?", "", ["a page and a tab", "spaces inside the words", "a Settings field"]],
    ["a parser without the field form", "Settings\\/[^\\s()\\/]+|", "", ["a Settings field"]],
    ["a place that keeps the field in the tab", "return at === -1 ?", "return true ?", ["Settings at a field"]],
    ["a page-only parser", "|file:((?:[A-Za-z0-9_.!~*'\\-]|%[0-9A-Fa-f]{2})+)", "", ["a file in the configuration directory", "an absolute file", "a file in the home folder", "a folder", "a file before a page, the first wins"]],
    ["a file read as a plugin page", "page: file ? FILE_SCHEME + found[4] : found[2]", "page: file ? found[4] : found[2]", ["a file in the configuration directory", "a folder"]]
];
const source = fs.readFileSync(file, "utf8");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "page-reference-control-"));
try {
    for (const [name, needle, replacement, rows] of CONTROLS) {
        assert.equal(source.split(needle).length - 1, 1, name + " match count");
        const copy = path.join(scratch, "PageReference.js");
        fs.writeFileSync(copy, source.replace(needle, replacement));
        assert.notEqual(fs.readFileSync(copy, "utf8"), source, name + " changed the copy");
        const failed = failures(load(copy));
        for (const row of rows) assert.ok(failed.includes(row), name + " must fail row " + row + ", failed " + JSON.stringify(failed));
        console.log("  ok    control: " + name + " turns red");
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
console.log("test-page-reference: ok");
