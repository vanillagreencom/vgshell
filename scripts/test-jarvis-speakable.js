#!/usr/bin/env node
// Synthetic TTS fixtures from jarvis-plan.md §§ 5 and 9, 2026-09-30.
// This is text-only in-process evidence, not a speech-quality measurement.
"use strict";
const { assert, path, backend, world, control } = require("./fixtures/jarvis-voice/assertions.js");
const Speakable = require(path.join(backend, "Speakable.js"));
const fixtures = require("./fixtures/jarvis-voice/speakable.json");
// A row is read as any text, and with replied as a brain's reply: reply holds
// the tool names of that reading and its sentences, where they differ.
function spoken(logic, row, chunks = [row.text], replied = false) {
    const stream = replied ? logic.create(row.language, { tools: row.reply?.tools ?? [] }) : logic.create(row.language);
    const sentences = replied ? row.reply?.sentences ?? row.sentences : row.sentences;
    const name = row.name + (replied ? " as a reply" : "");
    const early = chunks.flatMap(chunk => stream.push(chunk));
    if (row.incremental) assert.deepEqual(early, sentences, name + " before finish");
    const output = early.concat(stream.finish());
    assert.deepEqual(output, sentences, name);
    if (replied) return;
    if (row.counts !== undefined)
        for (const [kind, expected] of Object.entries(row.counts)) assert.equal(stream.counts()[kind], expected, row.name + " " + kind);
    if (row.violations === 0) assert.equal(Object.values(stream.counts()).reduce((a, b) => a + b, 0), 0, row.name + " measurement");
}
const replied = (logic, row) => spoken(logic, row, [row.text], true);
assert.ok(fixtures.length >= 75, "sanitation coverage floor");
const long = { name: "bounded-sentences-after-comparison", language: "en", incremental: true,
    text: "If a<b then stop. " + "Next sentence. ".repeat(300),
    sentences: ["If a b then stop.", ...Array(300).fill("Next sentence.")] };
assert.ok(long.text.length > Speakable.limits.token, "aggregate reaches the old held-candidate overflow");
// In a reply, a tag with no closing tag within the bound opened no element:
// every sentence after it is spoken, and before the reply ends. A tool call
// longer than the bound stays silent as the JSON value it is, and a JSON
// value is read as it arrives, so it reaches no bound.
const stray = { name: "element-unclosed-past-bound", language: "en", incremental: true,
    text: "Replace <filename> with yours. " + "Next word. ".repeat(60),
    sentences: ["Replace with yours.", ...Array(60).fill("Next word.")] };
const call = { name: "element-call-past-bound", language: "en",
    text: 'Saved. <tool_call>{"name": "files.write", "arguments": {"text": "' + "word ".repeat(100) + '"}}</tool_call> Done. ',
    reply: { tools: [], sentences: ["Saved.", "Done."] } };
const value = { name: "json-past-bound", language: "en", text: '{"a": "' + "x".repeat(10000) + '"} Done. ', reply: { tools: [], sentences: ["Done."] } };
assert.ok('{"name": "files.read", "arguments": {"path": "~/notes.md"}}'.length <= Speakable.limits.element, "a tool call of the usual size fits the wait");
for (const row of [stray, call]) assert.ok(row.text.length > 2 * Speakable.limits.element, row.name + " passes the element bound");
assert.ok(value.text.length > Speakable.limits.token, "json-past-bound passes the token bound");
for (const row of [stray, call, value]) {
    replied(Speakable, row);
    spoken(Speakable, row, row.text.split(""), true);
}
spoken(Speakable, stray);
for (const row of [...fixtures, long])
    for (const reply of [false, true]) {
        spoken(Speakable, row, [row.text], reply);
        spoken(Speakable, row, row.text.split(""), reply);
        for (let cut = 0; cut <= row.text.length; cut++)
            spoken(Speakable, row, [row.text.slice(0, cut), row.text.slice(cut)], reply);
    }
const stream = Speakable.create("en");
assert.deepEqual(stream.push("First. "), ["First."], "deliver before brain EOF");
assert.deepEqual(stream.push("Second"), []);
assert.deepEqual(stream.finish(), ["Second"]);
assert.throws(() => stream.push("Later"), { message: "jarvis: speakable=stream-closed" });
assert.throws(() => stream.finish(), { message: "jarvis: speakable=stream-closed" });
const counts = Speakable.violations("**At** 2 kg see https://example.com. `code` /tmp/file.", "en");
assert.deepEqual(counts, { markdown: 4, code: 1, url: 1, path: 1, symbol: 0, number: 1, unit: 1, date: 0, time: 0 });
assert.deepEqual(Speakable.violations("All done.", "es"),
    { markdown: 0, code: 0, url: 0, path: 0, symbol: 0, number: 0, unit: 0, date: 0, time: 0 });
assert.equal(Object.isFrozen(counts), true);
const overflow = [
    ["chunk", "a".repeat(16385)], ["token", "https://" + "a".repeat(4090)],
    ["sentence", "a ".repeat(2049)], ["output", ("4".repeat(4000) + ". ").repeat(4)]
];
function refused(logic, [cause, input]) {
    const stream = logic.create("es");
    assert.throws(() => stream.push(input), { message: "jarvis: speakable=" + cause + "-overflow" });
    assert.throws(() => stream.finish(), { message: "jarvis: speakable=stream-failed" });
}
for (const row of overflow) refused(Speakable, row);
assert.equal(Speakable.create("en").push("a".repeat(4096)).length, 0);
assert.equal(Speakable.create("en").push("`" + "x".repeat(16000)).length, 0, "code body is discarded, not stored");
assert.throws(() => Speakable.create("en").push(null), { message: "jarvis: speakable=chunk-type" });

let controls = 0;
world("js", root => {
    const rows = [
        ["kept-url", 'plain(siteName(address) + trailing, output);', 'plain(address + trailing, output);',
            logic => spoken(logic, fixtures.find(row => row.name === "url"))],
        ["kept-code", 'else { mode.word = /[\\p{L}\\p{N}]/u.test(pending[0]); pending = pending.slice(1); }',
            'else { plain(pending[0], output); pending = pending.slice(1); }',
            logic => spoken(logic, fixtures.find(row => row.name === "fenced-code"))],
        ["markdown-count", 'note("markdown"); pending = pending.slice(1); plain(" ", output);',
            'if (false) note("markdown"); pending = pending.slice(1); plain(" ", output);',
            logic => assert.equal(logic.violations("**Ready**.", "en").markdown, 4)],
        ["kept-path", 'note("path"); plain(" " + trailing, output);',
            'note("path"); plain(pending.slice(0, length), output);',
            logic => spoken(logic, fixtures.find(row => row.name === "paths"))],
        ["comparison-prose", 'plain("<", output); pending = pending.slice(1); continue;',
            'plain("<", output); mode = { kind: "code", fence: ">", span: false, word: false }; pending = pending.slice(1); continue;',
            logic => spoken(logic, fixtures.find(row => row.name === "comparison-spaced"))],
        ["unterminated-prose", 'if (!final && tag.kind === "pending") return;',
            'if (tag.kind === "pending") { if (final) pending = ""; return; }',
            logic => spoken(logic, fixtures.find(row => row.name === "unterminated-short-candidate"))],
        ["html-prefix-viability", 'if (space === null) return { kind: "prose" };',
            'if (space === null) return { kind: "pending" };',
            logic => spoken(logic, fixtures.find(row => row.name === "comparison-incremental"))],
        ["html-removal", 'if (tag.kind === "tag")', 'if (false)',
            logic => spoken(logic, fixtures.find(row => row.name === "html-attributes"))],
        ["path-boundary", 'pathBoundary && /', 'true && /',
            logic => spoken(logic, fixtures.find(row => row.name === "rates-en"))],
        ["path-punctuation", '!/[\\p{L}\\p{N}]$/u.test(sentence)', '/\\s$/u.test(sentence)',
            logic => spoken(logic, fixtures.find(row => row.name === "path-punctuation"))],
        ["html-path-separator", 'pending = pending.slice(tag.length); plain(" ", output);',
            'pending = pending.slice(tag.length);',
            logic => spoken(logic, fixtures.find(row => row.name === "path-html-separator"))],
        ["spanish-punctuation", "!?¿¡;", "!?;",
            logic => spoken(logic, fixtures.find(row => row.name === "punctuation-es"))],
        ["streaming-cut", 'emit(sentence.slice(0, end), output);', 'emit("", output);',
            logic => spoken(logic, fixtures.find(row => row.name === "markdown"))],
        ["violation-count", 'counts[kind]++;', 'counts[kind] += 0;',
            logic => assert.equal(logic.violations("https://example.com", "en").url, 1)],
        ["chunk-type", 'typeof chunk !== "string"', 'false',
            logic => assert.throws(() => logic.create("en").push(null), { message: "jarvis: speakable=chunk-type" })],
        ["lifetime", 'lifecycle !== "open"', 'false', logic => {
            const stream = logic.create("en"); stream.finish();
            assert.throws(() => stream.push("Later"), { message: "jarvis: speakable=stream-closed" });
        }],
        // One row for each rule of what stays silent in a reply. A rule's
        // control reads the fixture only that rule keeps silent.
        ...[
            ["element-content", 'if (reply !== null && tag.element !== null) mode = { kind: "element", closer: "</" + tag.element.toLowerCase(), held: "" };', "", "element"],
            ["element-name", "[A-Za-z_:][A-Za-z0-9_:-]*(?:\\.[A-Za-z0-9_:-]+)*", "[A-Za-z][A-Za-z0-9:-]*", "element-names"],
            ["element-end", 'if (end !== null) { pending = rest.slice(end[0].length); mode = PROSE; plain(" ", output); continue; }', "", "element"],
            ["element-letter-case", "if (pending.toLowerCase().startsWith(mode.closer)) {", "if (pending.startsWith(mode.closer)) {", "element-letter-case"],
            ["element-unclosed", 'while (mode.kind === "element") {', "while (false) {", "element-unclosed"],
            ["json-value", 'if (judged === "json") {', "if (false) {", "json-object"],
            ["json-string", "else if (char === '\"') mode.quoted = true;", "", "json-object"],
            ["json-array", 'if (rest[0] === "{") return "json";', "", "json-array"],
            ["json-bare-values", "const scalar = JSON_SCALAR.exec(rest);", "const scalar = null;", "json-array"],
            ["json-link-label", 'scalar[2] === "(" && scalar[1] === "]" ? "prose" : "json"', '"json"', "json-prose"],
            ["json-unfinished", "if (rest[0] === '\"' || rest[0] === (text[0] === \"{\" ? \"}\" : \"]\")) return \"json\";",
                "if (rest[0] === (text[0] === \"{\" ? \"}\" : \"]\")) return \"json\";", "json-unfinished"],
            ["table-row", 'if (reply !== null && first === "|" && /(?:^|\\n)[ \\t]*$/u.test(sentence)) {', "if (false) {", "table"],
            ["tool-name", "if (names.length !== 0 && wordStart()) {", "if (false) {", "tool-line"],
            ["tool-name-in-code", "if (mode.span && !mode.word) {", "if (false) {", "tool-code"],
            ["tool-name-behind-prefix", "mode.word = /[\\p{L}\\p{N}]/u.test(pending[0]);", "mode.word = true;", "tool-prefixed"],
            ["tool-name-in-block", "if (mode.span && !mode.word) {", "if (!mode.word) {", "tool-fenced-block"],
            ["tool-line-words", 'sentence = sentence.slice(0, sentence.lastIndexOf("\\n") + 1);', "", "tool-line"],
            ["tool-sentence-end", "/^(?:\\n|[.!?]+(?=\\s))/u.exec(pending)", "/^(?:\\n)/u.exec(pending)", "tool-line"],
            ["tool-line-end", "/^(?:\\n|[.!?]+(?=\\s))/u.exec(pending)", "/^(?:[.!?]+(?=\\s))/u.exec(pending)", "tool-lines"],
            ["tool-one-word", "reply.tools.filter(name => /[._]/u.test(name))", "reply.tools", "tool-word"],
            ["tool-word-start", "if (names.length !== 0 && wordStart()) {", "if (names.length !== 0) {", "tool-boundary"],
            ["tool-word-end", "!/[\\p{L}\\p{N}_]/u.test(pending[name.length])", "true", "tool-boundary"]
        ].map(([name, needle, replacement, fixture]) =>
            [name, needle, replacement, logic => replied(logic, fixtures.find(row => row.name === fixture))]),
        // The wait for a closing tag: bounded, and at its end the text kept
        // is read by every rule, with no word lost.
        ...[
            ["element-wait-bound", "if (mode.held.length === LIMITS.element) { pending = mode.held + pending; mode = PROSE; continue; }", "", stray],
            ["element-wait-keeps-words", "{ pending = mode.held + pending; mode = PROSE; continue; }", "{ mode = PROSE; continue; }", stray],
            ["element-wait-other-rules", "{ pending = mode.held + pending; mode = PROSE; continue; }",
                "{ plain(mode.held, output); mode = PROSE; continue; }", call]
        ].map(([name, needle, replacement, row]) => [name, needle, replacement, logic => replied(logic, row)]),
        // The rules of a reply read no other text: a row's plain reading
        // keeps the words a reply's would lose.
        ...[
            ["reply-only-element", "if (reply !== null && tag.element !== null) mode", "if (tag.element !== null) mode", "element"],
            ["reply-only-tag-name", "htmlCandidate(pending, reply !== null)", "htmlCandidate(pending, true)", "element-names"],
            ["reply-only-json", 'if (reply !== null && (first === "{" || first === "[")) {', 'if (first === "{" || first === "[") {', "json-object"],
            ["reply-only-table", 'if (reply !== null && first === "|" && ', 'if (first === "|" && ', "table"]
        ].map(([name, needle, replacement, fixture]) =>
            [name, needle, replacement, logic => spoken(logic, fixtures.find(row => row.name === fixture))])
    ];
    for (const [name, needle, replacement, check] of rows) {
        control(root, name, "Speakable.js", needle, replacement, check); controls++;
    }
    for (const row of overflow) {
        const [name] = row;
        const needle = name === "output" ? 'output.reduce((size, item) => size + item.length, 0) > LIMITS.output'
            : 'bound(' + (name === "token" ? "pending" : name) + ', LIMITS.' + name + ', "' + name + '");';
        control(root, name + "-bound", "Speakable.js", needle, name === "output" ? "false" : ";",
            logic => refused(logic, row)); controls++;
    }
});
console.log("test-jarvis-speakable: ok fixtures=" + fixtures.length + " controls=" + controls);
