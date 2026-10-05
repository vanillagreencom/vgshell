#!/usr/bin/env node
// Table-driven checks for vgs.sound's pure decisions, SoundLogic.js: the
// level icon and text, percentage rounding, a volume step and its clamp,
// wheel notches, which streams are apps and which of them a new output
// takes, which sink a volume change reaches behind a DSP default output,
// a failed IPC reply, the playing-apps status, the on-screen display and
// the widget's tooltip. Expected values are written here by hand.
// Controls edit one rule at a time in a copy of the logic and require this
// suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.sound", "SoundLogic.js");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message);

// `pactl --format=json list sink-inputs` as pipewire-pulse prints it, cut
// to the fields the logic reads: an app, EasyEffects' output, a filter
// chain's output, a stream no app owns and a second app.
const SINK_INPUTS = JSON.stringify([
    { index: 42, sink: 3, properties: { "application.name": "Firefox", "node.name": "Firefox" } },
    { index: 43, sink: 3, properties: { "application.name": "EasyEffects", "node.name": "ee_soe_output_level" } },
    { index: 44, sink: 1, properties: { "application.name": "pipewire", "node.name": "effect_output.eq", "node.link-group": "filter-chain-1-12" } },
    { index: 45, sink: 3, properties: { "node.name": "alsa_playback.speaker-test" } },
    { index: 46, sink: 3, properties: { "application.name": "Spotify", "node.name": "spotify" } }
]);

function node(name, kind, extra) {
    const kinds = { sink: { stream: false, sink: true }, source: { stream: false, sink: false }, out: { stream: true, sink: true }, in: { stream: true, sink: false } };
    return Object.assign({ name, app: "", linkGroup: "" }, kinds[kind], extra || {});
}

function verify(logic) {
    const icons = [
        ["unavailable", false, 0.5, false, "volume-off"],
        ["muted", true, 0.5, true, "volume-x"],
        ["silent", true, 0, false, "volume"],
        ["rounds to silent", true, 0.004, false, "volume"],
        ["low", true, 0.25, false, "volume-1"],
        ["just under half", true, 0.494, false, "volume-1"],
        ["rounds up to half", true, 0.496, false, "volume-2"],
        ["half", true, 0.5, false, "volume-2"],
        ["above full", true, 1.2, false, "volume-2"]
    ];
    for (const [label, available, volume, muted, want] of icons)
        assert.equal(logic.levelIcon(available, volume, muted), want, "levelIcon: " + label);
    assert.equal(logic.inputIcon(true, false), "mic", "inputIcon: live");
    assert.equal(logic.inputIcon(true, true), "mic-off", "inputIcon: muted");
    assert.equal(logic.inputIcon(false, false), "mic-off", "inputIcon: unavailable");

    const steps = [
        ["up", 0.37, 1, 5, 0.42],
        ["down", 0.37, -1, 5, 0.32],
        ["up stops at full", 0.98, 1, 5, 1],
        ["up from full", 1, 1, 10, 1],
        ["up keeps a level above full", 1.2, 1, 5, 1.2],
        ["down from above full", 1.2, -1, 5, 1.15],
        ["down stops at silent", 0.03, -1, 5, 0],
        ["a fine step", 0.5, 1, 2, 0.52],
        ["a part percent rounds first", 0.404, 1, 5, 0.45],
        ["a part percent rounds to the nearest", 0.3499, 1, 5, 0.4]
    ];
    for (const [label, volume, direction, step, want] of steps)
        assert.equal(logic.stepped(volume, direction, step), want, "stepped: " + label);
    assert.throws(() => logic.stepped(0.5, 0, 5), /direction 0 is not 1 or -1/, "stepped: no direction");
    assert.throws(() => logic.stepped(0.5, 1, 0), /step 0 is not a positive number/, "stepped: no step");

    const wheels = [
        ["one notch up", 0, 120, { steps: 1, carry: 0 }],
        ["half a notch", 0, 60, { steps: 0, carry: 60 }],
        ["two halves", 60, 60, { steps: 1, carry: 0 }],
        ["two notches down", 0, -240, { steps: -2, carry: 0 }],
        ["a notch down and a rest", -30, -100, { steps: -1, carry: -10 }],
        ["a turn back cancels the carry", 60, -60, { steps: 0, carry: 0 }]
    ];
    for (const [label, carry, delta, want] of wheels)
        same(logic.wheelSteps(carry, delta), want, "wheelSteps: " + label);

    const parsed = logic.parseSinkInputs(SINK_INPUTS);
    same(parsed, { ok: true, inputs: [
        { index: 42, app: "Firefox", linkGroup: "" },
        { index: 43, app: "EasyEffects", linkGroup: "" },
        { index: 44, app: "pipewire", linkGroup: "filter-chain-1-12" },
        { index: 45, app: "", linkGroup: "" },
        { index: 46, app: "Spotify", linkGroup: "" }
    ] }, "parseSinkInputs: pipewire-pulse's list");
    same(logic.streamsToMove(parsed.inputs), [42, 46], "streamsToMove: the apps alone, never EasyEffects, a filter output or an app-less stream");
    const apps = [
        ["an app", "Firefox", "", true],
        ["no application.name", "", "", false],
        ["EasyEffects' output", "EasyEffects", "", false],
        ["a filter chain's output", "pipewire", "filter-chain-1-12", false],
        ["an app inside a link group", "Firefox", "loopback-3", false]
    ];
    for (const [label, app, linkGroup, want] of apps)
        assert.equal(logic.isAppStream(app, linkGroup), want, "isAppStream: " + label);
    same(logic.parseSinkInputs("[]"), { ok: true, inputs: [] }, "parseSinkInputs: nothing plays");
    same(logic.streamsToMove([]), [], "streamsToMove: nothing plays");
    const refused = [
        ["not JSON", "Sink Input #42", /^json=/],
        ["not a list", "{}", /^shape=not-a-list$/],
        ["no index", "[{\"properties\":{}}]", /^input=0 index=malformed$/],
        ["a negative index", "[{\"index\":-1}]", /^input=0 index=malformed$/],
        ["a part index", "[{\"index\":1.5}]", /^input=0 index=malformed$/]
    ];
    for (const [label, text, want] of refused) {
        const got = logic.parseSinkInputs(text);
        assert.equal(got.ok, false, "parseSinkInputs refuses " + label);
        assert.match(got.error, want, "parseSinkInputs: " + label);
    }

    const speakers = node("speakers", "sink");
    const headphones = node("headphones", "sink");
    const eq = node("eq", "sink", { linkGroup: "filter-chain-7-1" });
    const eqOut = node("eq.output", "out", { linkGroup: "filter-chain-7-1" });
    const ee = node("easyeffects_sink", "sink");
    const eeOut = node("ee_soe_output_level", "out", { app: "EasyEffects" });
    const app = node("Firefox", "out", { app: "Firefox" });
    const mic = node("mic", "source");
    const targets = [
        ["no default", "", [speakers], [], ""],
        ["a device default", "speakers", [speakers, headphones, app], [{ source: "Firefox", target: "speakers" }], "speakers"],
        ["a filter chain in front of the speakers", "eq", [speakers, eq, eqOut, app], [{ source: "Firefox", target: "eq" }, { source: "eq.output", target: "speakers" }], "speakers"],
        ["a filter chain whose output is not linked", "eq", [speakers, eq, eqOut], [], "eq"],
        ["a filter output linked to no device sink", "eq", [eq, eqOut, mic, node("rec", "in")], [{ source: "eq.output", target: "rec" }], "eq"],
        ["EasyEffects in front of the headphones", "easyeffects_sink", [headphones, ee, eeOut], [{ source: "ee_soe_output_level", target: "headphones" }], "headphones"],
        ["EasyEffects in front of a filter chain", "easyeffects_sink", [speakers, eq, eqOut, ee, eeOut], [{ source: "ee_soe_output_level", target: "eq" }, { source: "eq.output", target: "speakers" }], "speakers"],
        ["an app's stream does not make a sink a DSP sink", "speakers", [speakers, headphones, node("Player", "out", { app: "Player", linkGroup: "" })], [{ source: "Player", target: "headphones" }], "speakers"],
        ["another filter's output does not count", "eq", [speakers, eq, node("other.output", "out", { linkGroup: "filter-chain-7-2" })], [{ source: "other.output", target: "speakers" }], "eq"],
        ["a default no node names", "gone", [speakers], [], "gone"],
        ["a chain into two filters feeding each other keeps the default", "a", [node("a", "sink", { linkGroup: "g1" }), node("a.out", "out", { linkGroup: "g1" }),
            node("b", "sink", { linkGroup: "g2" }), node("b.out", "out", { linkGroup: "g2" }), node("c", "sink", { linkGroup: "g3" }), node("c.out", "out", { linkGroup: "g3" })],
            [{ source: "a.out", target: "b" }, { source: "b.out", target: "c" }, { source: "c.out", target: "b" }], "a"]
    ];
    for (const [label, sinkName, nodes, links, want] of targets)
        assert.equal(logic.volumeTarget(sinkName, nodes, links), want, "volumeTarget: " + label);

    same(logic.streamsState(false), { tone: "warning", text: "Apps that play now stay on their output when you choose another. Install pactl to move them.", action: true }, "streamsState: pactl missing");
    same(logic.streamsState(true), { tone: "ok", text: "Apps that play now move to the output you choose." }, "streamsState: pactl present");

    const levels = [
        ["a level", 0.45, false, "45%"],
        ["a level that rounds up", 0.3499, false, "35%"],
        ["above full", 1.5, false, "150%"],
        ["muted", 0.45, true, "Muted"]
    ];
    for (const [label, volume, muted, want] of levels)
        assert.equal(logic.levelText(volume, muted), want, "levelText: " + label);

    const replies = [
        ["ok", "ok", false],
        ["a percentage", "45", false],
        ["a refusal", "refused: sound=unavailable", true],
        ["an unknown handler", "unknown: step", true],
        ["a thrown handler", "error: boom", true],
        ["a refusal word later in the line", "muted refused: no", false]
    ];
    for (const [label, reply, want] of replies)
        assert.equal(logic.replyFailed(reply), want, "replyFailed: " + label);

    same(logic.osdView("output", 0.45, false), { icon: "volume-1", level: 0.45, text: "45%" }, "osdView: output");
    same(logic.osdView("output", 0.45, true), { icon: "volume-x", level: 0, text: "Muted" }, "osdView: muted output");
    same(logic.osdView("input", 0.8, false), { icon: "mic", level: 0.8, text: "80%" }, "osdView: input");
    same(logic.osdView("input", 0.8, true), { icon: "mic-off", level: 0, text: "Muted" }, "osdView: muted input");
    assert.throws(() => logic.osdView("speakers", 1, false), /kind "speakers" is not output or input/, "osdView: unknown kind");

    assert.equal(logic.widgetTooltip(false, "Speakers", 0.5, false), "Sound is not available", "widgetTooltip: unavailable");
    assert.equal(logic.widgetTooltip(true, "", 0, false), "No output device", "widgetTooltip: no device");
    assert.equal(logic.widgetTooltip(true, "Speakers", 0.5, false), "Speakers: 50%", "widgetTooltip: level");
    assert.equal(logic.widgetTooltip(true, "Speakers", 0.5, true), "Speakers: Muted", "widgetTooltip: muted");
}

verify(load(file));

const CONTROLS = [
    ["unavailable draws volume-off", "if (!available) return \"volume-off\";", "if (false) return \"volume-off\";"],
    ["muted draws volume-x", "if (muted) return \"volume-x\";", "if (false) return \"volume-x\";"],
    ["the low band ends at half", "if (level < 50) return \"volume-1\";", "if (level <= 50) return \"volume-1\";"],
    ["the input icon reads mute", "return available && !muted ? \"mic\" : \"mic-off\";", "return available ? \"mic\" : \"mic-off\";"],
    ["a step up stops at full", "if (direction > 0) next = Math.max(now, Math.min(next, 100));", "if (direction > 0) next = Math.max(now, next);"],
    ["a step up never lowers", "if (direction > 0) next = Math.max(now, Math.min(next, 100));", "if (direction > 0) next = Math.min(next, 100);"],
    ["a step down stops at silent", "else next = Math.max(next, 0);", "else next = next;"],
    ["a step needs a direction", "if (direction !== 1 && direction !== -1)", "if (false)"],
    ["a wheel turn down rounds toward zero", "var steps = total > 0 ? Math.floor(total / WHEEL_NOTCH) : Math.ceil(total / WHEEL_NOTCH);", "var steps = Math.floor(total / WHEEL_NOTCH);"],
    ["a list that is no JSON is refused", "return { ok: false, error: \"json=\" + e.message };", "return { ok: true, inputs: [] };"],
    ["an input needs a whole index", "|| row.index < 0 || Math.floor(row.index) !== row.index)", ")"],
    ["an app-less stream is no app", "return app !== \"\" && app !== EASYEFFECTS_APP && linkGroup === \"\";", "return app !== EASYEFFECTS_APP && linkGroup === \"\";"],
    ["EasyEffects is no app", "return app !== \"\" && app !== EASYEFFECTS_APP && linkGroup === \"\";", "return app !== \"\" && linkGroup === \"\";"],
    ["a filter output is no app", "return app !== \"\" && app !== EASYEFFECTS_APP && linkGroup === \"\";", "return app !== \"\" && app !== EASYEFFECTS_APP;"],
    ["a new output takes the apps alone", "if (isAppStream(inputs[i].app, inputs[i].linkGroup)) out.push(inputs[i].index);", "out.push(inputs[i].index);"],
    ["a percentage rounds to the nearest", "return Math.round(volume * 100);", "return Math.floor(volume * 100);"],
    ["a refusal reads failed", "return /^(refused|unknown|error):/.test(String(reply));", "return /^(unknown|error):/.test(String(reply));"],
    ["a failure word counts only first", "return /^(refused|unknown|error):/.test(String(reply));", "return /(refused|unknown|error):/.test(String(reply));"],
    ["a filter sink resolves to its device", "var feeds = sink.linkGroup !== \"\" && node.linkGroup === sink.linkGroup", "var feeds = false"],
    ["an empty link group feeds nothing", "var feeds = sink.linkGroup !== \"\" && node.linkGroup === sink.linkGroup", "var feeds = node.linkGroup === sink.linkGroup"],
    ["EasyEffects resolves to its device", "|| sink.name === EASYEFFECTS_SINK && node.app === EASYEFFECTS_APP;", ";"],
    ["the target is a device sink", "if (nodes[k].name === links[j].target && !nodes[k].stream && nodes[k].sink === true && nodes[k].name !== sink.name)", "if (nodes[k].name === links[j].target)"],
    ["a chain is followed to its end", "        current = next;\n", "        return next;\n"],
    ["a cycle ends where it began", "    return sinkName;\n}\n\n// The device sink", "    return current;\n}\n\n// The device sink"],
    ["missing pactl offers it", "if (pactl !== true)", "if (false)"],
    ["a muted display is empty", "level: muted ? 0 : volume, text: text };\n    if (kind === \"input\")", "level: volume, text: text };\n    if (kind === \"input\")"],
    ["a muted level reads Muted", "return muted ? \"Muted\" : percent(volume) + \"%\";", "return percent(volume) + \"%\";"],
    ["the tooltip says when sound is not available", "if (!available) return \"Sound is not available\";", "if (false) return \"Sound is not available\";"]
];

const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "sound-logic-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "SoundLogic.js");
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
console.log(`test-sound-logic: ok controls=${CONTROLS.length}`);
