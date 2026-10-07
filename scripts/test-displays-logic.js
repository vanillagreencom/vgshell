#!/usr/bin/env node
// Table-driven checks for vgs.displays' pure decisions
// (shell/plugins/vgs.displays/DisplaysLogic.js): the helper's answers
// judged, the coalescing of the helper's runs, what a brightness key and a
// linked slider change, the assignments file's judge and how its entries,
// stale ones included, apply, the pane's Screen choices, what the idle dim
// sets and brings back, and the status and sentences the surfaces read. Expected
// values are written here by hand. Controls edit one rule in a copy of the
// logic and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.displays", "DisplaysLogic.js");
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message || "");

const XDR = "hidraw:devices/usb1/1-2";
const STUDIO_A = "hidraw:class/hidraw/hidraw1/device";
const STUDIO_B = "hidraw:class/hidraw/hidraw2/device";

// A `list` answer as helper/brightness.py prints it: a tiled XDR it mapped,
// two Studio Displays with one serial it could not place, a DDC display
// the user may not open, and a laptop backlight.
function listAnswer() {
  return {
    backends: { ddc: { state: "ready" }, backlight: { state: "ready" } },
    displays: [
      { id: XDR, backend: "hidraw", label: "Apple Pro Display XDR", state: "ready", percent: 50, outputs: ["DP-1", "DP-5"],
        product: "9243", identity: { parent: "devices/usb1/1-2", serial: "C02" } },
      { id: STUDIO_A, backend: "hidraw", label: "Apple Studio Display", state: "ready", percent: 30, outputs: [],
        product: "1114", identity: { parent: "class/hidraw/hidraw1/device", serial: "S" } },
      { id: STUDIO_B, backend: "hidraw", label: "Apple Studio Display", state: "ready", percent: 95, outputs: [],
        product: "1114", identity: { parent: "class/hidraw/hidraw2/device", serial: "S" } },
      { id: "ddc:HDMI-A-1", backend: "ddc", label: "DELL U2720Q", state: "no-access", percent: null, outputs: ["HDMI-A-1"] },
      { id: "backlight:intel_backlight", backend: "backlight", label: "intel_backlight", state: "ready", percent: 3, outputs: ["eDP-1"] }
    ]
  };
}

const output = (name, identifier) => ({ name, identifier, make: "Apple", model: "M", serial: "" });
const OUTPUTS = [output("DP-1", "desc:Apple ProDisplayXDR 0x03"), output("DP-5", "desc:Apple ProDisplayXDR 0x03"),
  output("DP-2", "DP-2"), output("DP-3", "DP-3"), output("HDMI-A-1", "HDMI-A-1"), output("eDP-1", "eDP-1")];
const KEY_A = "usb:class/hidraw/hidraw1/device#S";
const KEY_B = "usb:class/hidraw/hidraw2/device#S";

function verify(logic) {
  // --- The helper's answers ------------------------------------------------
  const listed = logic.parseList(JSON.stringify(listAnswer()));
  assert.equal(listed.ok, true, JSON.stringify(listed));
  same(listed.displays.map(d => [d.id, d.state, d.percent, d.identity === null ? null : d.identity.serial]),
    [[XDR, "ready", 50, "C02"], [STUDIO_A, "ready", 30, "S"], [STUDIO_B, "ready", 95, "S"],
      ["ddc:HDMI-A-1", "no-access", null, null], ["backlight:intel_backlight", "ready", 3, null]]);
  const broken = (edit) => { const a = listAnswer(); edit(a); return JSON.stringify(a); };
  const listRefusals = [
    ["not JSON", "{", "refused: list=unparsed"],
    ["helper failure", JSON.stringify({ error: "usage" }), "refused: list=helper error=\"usage\""],
    ["unknown backend state", broken(a => { a.backends.ddc.state = "fine"; }), "refused: list=shape backend=ddc"],
    ["unknown display backend", broken(a => { a.displays[0].backend = "usb"; }), "refused: list=shape display=0 field=backend"],
    ["empty label", broken(a => { a.displays[0].label = ""; }), "refused: list=shape display=0 field=label"],
    ["percent below 0", broken(a => { a.displays[0].percent = -1; }), "refused: list=shape display=0 field=percent"],
    ["repeated id", broken(a => { a.displays[1].id = XDR; }), "refused: list=shape display=1 field=id"],
    ["ready without a percent", broken(a => { a.displays[0].percent = null; }), "refused: list=shape display=0 field=percent"],
    ["percent past 100", broken(a => { a.displays[0].percent = 101; }), "refused: list=shape display=0 field=percent"],
    ["not ready with a percent", broken(a => { a.displays[3].percent = 40; }), "refused: list=shape display=3 field=percent"],
    ["unknown display state", broken(a => { a.displays[3].state = "asleep"; }), "refused: list=shape display=3 field=state"],
    ["empty output name", broken(a => { a.displays[0].outputs = [""]; }), "refused: list=shape display=0 field=outputs"],
    ["identity without parent", broken(a => { a.displays[0].identity = { serial: "x" }; }), "refused: list=shape display=0 field=identity"]
  ];
  for (const [name, text, want] of listRefusals) same(logic.parseList(text), { ok: false, error: want }, "parseList: " + name);

  same(logic.parseSet(JSON.stringify({ id: XDR, percent: 40 }), XDR), { ok: true, percent: 40 });
  same(logic.parseSet(JSON.stringify({ error: "state", state: "no-access", id: XDR }), XDR),
    { ok: false, error: "refused: set=helper error=\"state\" state=\"no-access\"" });
  same(logic.parseSet(JSON.stringify({ id: STUDIO_A, percent: 40 }), XDR), { ok: false, error: "refused: set=shape id=\"" + STUDIO_A + "\" percent=40" });
  for (const percent of [-1, 101])
    same(logic.parseSet(JSON.stringify({ id: XDR, percent: percent }), XDR), { ok: false, error: "refused: set=shape id=\"" + XDR + "\" percent=" + percent }, "parseSet: percent " + percent);

  // --- Runs: latest wins per display, one run in flight --------------------
  let runs = logic.emptyRuns();
  let taken = logic.takeRun(runs);
  same(taken.run, null, "nothing waits");
  runs = logic.queueSet(runs, XDR, 1);
  taken = logic.takeRun(runs);
  same(taken.run, { verb: "set", id: XDR, percent: 1 });
  runs = taken.runs;
  assert.equal(logic.pendingPercent(runs, XDR), 1, "the level in flight is shown while no newer one waits");
  // A 20-event drag while the first run is in flight: 2 runs in all, the
  // last one carrying the drag's final value.
  const started = [taken.run];
  for (let p = 2; p <= 20; p++) {
    runs = logic.queueSet(runs, XDR, p);
    taken = logic.takeRun(runs);
    assert.equal(taken.run, null, "no second run while one is in flight");
    assert.equal(logic.pendingPercent(runs, XDR), p, "the drag's latest value is shown while it waits");
  }
  runs = logic.queueList(runs);
  runs = logic.queueSet(runs, STUDIO_A, 70);
  for (;;) {
    runs = logic.endRun(runs);
    taken = logic.takeRun(runs);
    if (taken.run === null) break;
    started.push(taken.run);
    runs = taken.runs;
  }
  same(started, [{ verb: "set", id: XDR, percent: 1 }, { verb: "set", id: XDR, percent: 20 }, { verb: "set", id: STUDIO_A, percent: 70 }, { verb: "list" }],
    "a drag of 20 makes 2 runs, each display keeps its place and a list waits behind the changes");
  assert.throws(() => logic.endRun(logic.emptyRuns()), /endRun with no run in flight/);
  assert.equal(logic.pendingPercent(logic.emptyRuns(), XDR), null);

  // --- Assignments ---------------------------------------------------------
  const valid = { assignments: [{ device: KEY_A, label: "Apple Studio Display", output: "DP-2" }] };
  same(logic.parseAssignments(JSON.stringify(valid)), { ok: true, entries: valid.assignments });
  const entry = (device, output) => ({ device: device, label: "L", output: output });
  const fileRefusals = [
    ["not JSON", "[", "refused: assignments=unparsed"],
    ["a list", "[]", "refused: assignments=shape want={\"assignments\":[...]}"],
    ["another key", JSON.stringify({ assignments: [], extra: 1 }), "refused: assignments=shape want={\"assignments\":[...]}"],
    ["an entry key too many", JSON.stringify({ assignments: [Object.assign(entry(KEY_A, "DP-2"), { x: 1 })] }), "refused: assignment=0 keys=[\"device\",\"label\",\"output\",\"x\"] want=device,label,output"],
    ["an empty output", JSON.stringify({ assignments: [entry(KEY_A, "")] }), "refused: assignment=0 output=\"\""],
    ["a control character", JSON.stringify({ assignments: [entry("a\nb", "DP-2")] }), "refused: assignment=0 device=\"a\\nb\""],
    ["an output past 512 characters", JSON.stringify({ assignments: [entry(KEY_A, "D".repeat(513))] }), "refused: assignment=0 output=\"" + "D".repeat(56) + "..."],
    ["one device twice", JSON.stringify({ assignments: [entry(KEY_A, "DP-2"), entry(KEY_A, "DP-3")] }), "refused: assignment=1 device=\"" + KEY_A + "\" reason=repeated"],
    ["past the ceiling", JSON.stringify({ assignments: Array.from({ length: 65 }, (_, i) => entry("d" + i, "DP-2")) }), "refused: assignments=too-many count=65 max=64"]
  ];
  for (const [name, text, want] of fileRefusals) same(logic.parseAssignments(text), { ok: false, error: want }, "parseAssignments: " + name);
  same(logic.parseAssignments(JSON.stringify({ assignments: [entry(KEY_A, "D".repeat(512))] })), { ok: true, entries: [entry(KEY_A, "D".repeat(512))] }, "512 characters is the longest text");
  assert.equal(logic.assignmentsText(valid.assignments), JSON.stringify(valid, null, 2) + "\n");

  const entries = [
    entry(KEY_A, "DP-2"),
    entry(KEY_B, "DP-9"),                        // its output is gone: stale
    entry("usb:devices/usb1/1-9#S", "DP-3"),     // its device is gone: stale
    entry("usb:devices/usb1/1-2#C02", "DP-3"),   // the helper placed the XDR: unused
    entry("backlight:intel_backlight", "DP-2")   // DP-2 already shows Studio A: unused
  ];
  const resolved = logic.resolve(listed.displays, OUTPUTS, entries);
  same(resolved.assignments.map(e => e.state), ["applied", "stale", "stale", "unused", "unused"]);
  same(resolved.displays.map(d => [d.device, d.outputs, d.assigned]), [
    ["usb:devices/usb1/1-2#C02", ["DP-1", "DP-5"], false],
    [KEY_A, ["DP-2"], true],
    [KEY_B, [], false],
    ["ddc:HDMI-A-1", ["HDMI-A-1"], false],
    ["backlight:intel_backlight", ["eDP-1"], false]]);
  // An identifier two outputs share, as the tiled XDR's, places both.
  const tiled = logic.resolve(listed.displays.map(d => d.id === XDR ? Object.assign({}, d, { outputs: [] }) : d), OUTPUTS,
    [entry("usb:devices/usb1/1-2#C02", "desc:Apple ProDisplayXDR 0x03")]);
  same(tiled.displays[0].outputs, ["DP-1", "DP-5"]);
  // An output another display lights takes no second one: the helper's
  // XDR and laptop panel keep theirs, and of two unplaced displays on one
  // output the first entry wins.
  const contested = [
    ["the helper's tiled XDR", [entry(KEY_B, "desc:Apple ProDisplayXDR 0x03")], ["unused"], [[], []]],
    ["the helper's laptop panel", [entry(KEY_B, "eDP-1")], ["unused"], [[], []]],
    ["two unplaced displays", [entry(KEY_A, "DP-3"), entry(KEY_B, "DP-3")], ["applied", "unused"], [["DP-3"], []]]
  ];
  for (const [name, choices, states, outputs] of contested) {
    const r = logic.resolve(listed.displays, OUTPUTS, choices);
    same([r.assignments.map(e => e.state), [r.displays[1].outputs, r.displays[2].outputs]], [states, outputs], "resolve: " + name);
  }
  same(resolved.displays.map(d => logic.placeable(d)), [false, true, true, false, false], "only an unplaced or user-placed display takes a Screen choice");
  same(logic.screenChoices(resolved.displays, OUTPUTS), [
    { label: "Choose a screen", value: "" }, { label: "DP-2: Apple M", value: "DP-2" }, { label: "DP-3: Apple M", value: "DP-3" }],
    "a screen the helper lit is no choice; one a user's choice lit stays");
  same(logic.screenChoices([], [output("DP-1", "tile"), output("DP-5", "tile"), { name: "HDMI-A-2", identifier: "HDMI-A-2", make: "", model: "", serial: "" }]), [
    { label: "Choose a screen", value: "" }, { label: "DP-1 + DP-5: Apple M", value: "tile" }, { label: "HDMI-A-2", value: "HDMI-A-2" }],
    "one choice per identifier, named by its outputs and product");
  const monitorOutput = { identifier: "DP-2", name: "DP-2", description: "LG HDR 4K", make: "LG", model: "HDR 4K", serial: "", width: 3840, height: 2160, refreshRate: 144, x: 10, y: 20, scale: 2, transform: 0, disabled: false, mirrorOf: null,
    availableModes: [{ width: 3840, height: 2160, refresh: 144 }, { width: 3840, height: 2160, refresh: 60 }, { width: 2560, height: 1440, refresh: 60 }] };
  same(logic.outputChoices([monitorOutput]), [{ label: "DP-2: LG HDR 4K", value: "DP-2" }], "the output chooser names the connector and description");
  same(logic.modeChoices(monitorOutput).map(c => c.label), ["3840 × 2160", "2560 × 1440"], "mode choices group refresh rates by size");
  same(logic.refreshChoices(monitorOutput, { width: 3840, height: 2160, refresh: 144 }).map(c => c.label), ["144 Hz", "60 Hz"], "refresh choices follow the selected size");
  same(logic.scaleChoices({ width: 3840, height: 2160, refresh: 144 }, 2).map(c => c.value), [1, 1.25, 4 / 3, 1.5, 1.6, 5 / 3, 2, 2.5, 3], "scale choices keep whole logical pixels");
  const drafted = logic.withOutputDraft([monitorOutput], {}, {}, "DP-2", { mode: { width: 2560, height: 1440, refresh: 60 }, scale: 2.25 });
  same(drafted, { "DP-2": { mode: { width: 2560, height: 1440, refresh: 60 }, position: { x: 10, y: 20 }, scale: 2.25, transform: 0 } }, "a draft carries the display's own position");
  same(logic.dirtyRules(drafted, {}), drafted, "dirty rules are the pending monitor rules");
  assert.equal(logic.countdownText(12.4), "Keep these display settings? Reverting in 13 s");
  assert.equal(logic.countdownDetail(12.4), "Reverting in 13 s");
  const side = Object.assign({}, monitorOutput, { identifier: "DP-3", name: "DP-3", x: 1930, y: 20, scale: 2 });
  const shifted = logic.withOutputDraft([monitorOutput, side], {}, {}, "DP-2", { scale: 1 });
  same(shifted["DP-3"].position, { x: 3850, y: 20 }, "a scale change shifts a neighbour at the right edge by the size delta");
  const snapped = logic.moveGroup([monitorOutput, side], {}, { "DP-2": logic.effectiveRule(monitorOutput, {}, {}) }, "DP-3", 1915, 20);
  same([snapped["DP-2"].position, snapped["DP-3"].position], [{ x: 10, y: 20 }, { x: 1930, y: 20 }], "dragged outputs snap to a neighbour edge");
  const tiledOutputs = [Object.assign({}, monitorOutput, { name: "DP-1", identifier: "xdr", x: 0 }), Object.assign({}, monitorOutput, { name: "DP-5", identifier: "xdr", x: 3840 })];
  const tiledDraft = {
    "DP-1": Object.assign(logic.effectiveRule(tiledOutputs[0], {}, {}), { position: { x: 100, y: 0 } }),
    "DP-5": Object.assign(logic.effectiveRule(tiledOutputs[1], {}, {}), { position: { x: 3900, y: 0 } })
  };
  const tiledMove = logic.moveGroup(tiledOutputs, {}, tiledDraft, "xdr", 200, 0);
  same([tiledMove["DP-1"].position, tiledMove["DP-5"].position], [{ x: 200, y: 0 }, { x: 4000, y: 0 }],
    "a tiled group moves through connector rules and keeps tile offsets");

  // --- The arrangement canvas ------------------------------------------------
  // rows: [name, items, bounds]
  const boundsRows = [
    ["no display", [], { x: 0, y: 0, width: 1, height: 1 }],
    ["one display off the origin", [{ x: 5, y: 7, width: 10, height: 11 }], { x: 5, y: 7, width: 10, height: 11 }],
    ["a display left of and above the origin", [{ x: 0, y: 0, width: 3008, height: 1692 }, { x: -1440, y: -620, width: 1440, height: 2560 }],
      { x: -1440, y: -620, width: 4448, height: 2560 }]
  ];
  for (const [name, items, want] of boundsRows) same(logic.arrangementBounds(items), want, "arrangementBounds: " + name);
  // rows: [name, bounds, box width, max height, margin, fit]
  const fitRows = [
    ["the width limits a wide layout", { x: 0, y: 0, width: 400, height: 100 }, 220, 500, 10, { scale: 0.5, x: 10, y: 10, height: 70 }],
    ["the height limits a tall layout, centred across", { x: -1440, y: -620, width: 4448, height: 2560 }, 1000, 300, 20,
      { scale: 260 / 2560, x: 274.125 + 146.25, y: 20 + 62.96875, height: 300 }],
    ["a box too narrow for its margins draws nothing", { x: 0, y: 0, width: 10, height: 10 }, 0, 300, 20, { scale: 0, x: 0, y: 20, height: 40 }]
  ];
  for (const [name, bounds, width, maxHeight, margin, want] of fitRows) same(logic.arrangementFit(bounds, width, maxHeight, margin), want, "arrangementFit: " + name);
  // The owner's desk: a portrait 5K at scale 2 left of and above a 6K at
  // scale 2. Each display is drawn whole inside the box's margin.
  const ownerDesk = [
    Object.assign({}, monitorOutput, { identifier: "DP-1", name: "DP-1", make: "Apple Computer Inc", model: "ProDisplayXDR", width: 6016, height: 3384, x: 0, y: 0, scale: 2, transform: 0 }),
    Object.assign({}, monitorOutput, { identifier: "DP-2", name: "DP-2", make: "Apple Computer Inc", model: "StudioDisplay", width: 5120, height: 2880, x: -1440, y: -620, scale: 2, transform: 1 })
  ];
  const deskItems = logic.arrangementItems(ownerDesk, {}, {});
  same(deskItems.map(item => [item.label, item.product]), [["DP-1", "Apple Computer Inc ProDisplayXDR"], ["DP-2", "Apple Computer Inc StudioDisplay"]],
    "the canvas names each display's connector and model");
  const deskFit = logic.arrangementFit(logic.arrangementBounds(deskItems), 1000, 300, 20);
  assert.equal(deskFit.height, 300, "the desk's box is its drawing's height plus both margins");
  for (const item of deskItems) {
    const left = deskFit.x + item.x * deskFit.scale, top = deskFit.y + item.y * deskFit.scale;
    assert.ok(left >= 20 && top >= 20 && left + item.width * deskFit.scale <= 980 && top + item.height * deskFit.scale <= 280,
      `${item.label} draws inside the box's margin: ${[left, top, item.width * deskFit.scale, item.height * deskFit.scale]}`);
  }
  same(logic.moveGroup(ownerDesk, {}, {}, "DP-2", -1430, -600), { "DP-2": Object.assign(logic.effectiveRule(ownerDesk[1], {}, {}), { position: { x: -1440, y: -600 } }) },
    "a display dragged left of and above the origin keeps its place and moves no other");

  // --- Use this display and Mirror -------------------------------------------
  same(logic.outputChoices(tiledOutputs), [{ label: "DP-1 + DP-5: LG HDR 4K", value: "xdr" }], "the output chooser takes a tiled group once");
  const offLive = Object.assign({}, side, { disabled: true });
  const mirrorLive = Object.assign({}, side, { mirrorOf: "DP-2" });
  const third = Object.assign({}, monitorOutput, { identifier: "HDMI-A-1", name: "HDMI-A-1", x: 3850 });
  const stateOf = rule => [rule.disabled === true, rule.mirror === undefined ? null : rule.mirror];
  // rows: [name, output, saved, draft, [off, mirror]]
  const states = [
    ["Hyprland's off output with no rule", offLive, undefined, undefined, [true, null]],
    ["Hyprland's mirror with no rule, by connector", mirrorLive, undefined, undefined, [false, "DP-2"]],
    ["a saved rule over Hyprland's state", offLive, { scale: 2 }, undefined, [false, null]],
    ["a draft over the saved rule, whole", side, { mirror: "DP-2" }, { scale: 2 }, [false, null]],
    ["a draft that turns the output off", side, undefined, { scale: 2, disabled: true }, [true, null]]
  ];
  for (const [name, out, saved, draft, want] of states) same(stateOf(logic.effectiveRule(out, saved, draft)), want, "effectiveRule: " + name);
  const pair = [monitorOutput, side];
  const off = logic.withOutputDraft(pair, {}, {}, "DP-3", { disabled: true, mirror: "" });
  same(stateOf(off["DP-3"]), [true, null], "turning a display off drafts disabled");
  same(Object.keys(logic.withOutputDraft(pair, {}, off, "DP-3", { disabled: false })["DP-3"]).sort(), ["mode", "position", "scale", "transform"], "turning it back on leaves no disabled field");
  const mirrored = logic.withOutputDraft(pair, {}, {}, "DP-3", { mirror: "DP-2" });
  same(stateOf(mirrored["DP-3"]), [false, "DP-2"], "a mirror choice drafts the mirror");
  same(stateOf(logic.withOutputDraft(pair, {}, mirrored, "DP-3", { mirror: "" })["DP-3"]), [false, null], "Off leaves no mirror field");
  same(stateOf(logic.withOutputDraft(pair, {}, mirrored, "DP-3", { disabled: true, mirror: "" })["DP-3"]), [true, null], "turning a mirroring display off drops its mirror");
  const tiledOff = logic.withOutputDraft(tiledOutputs.concat([side]), {}, {}, "xdr", { disabled: true, mirror: "" });
  same([stateOf(tiledOff["DP-1"]), stateOf(tiledOff["DP-5"])], [[true, null], [true, null]], "a tiled group turns off on every connector");
  same(Object.keys(logic.withOutputDraft([monitorOutput, offLive], {}, {}, "DP-2", { scale: 1 })), ["DP-2"], "a size change moves no display that is off");
  const arranged = logic.arrangementItems([monitorOutput, offLive, Object.assign({}, third, { mirrorOf: "DP-2" })], {}, {});
  same(arranged.map(item => [item.identifier, item.off]), [["DP-2", false], ["DP-3", true]], "the canvas greys a display that is off and leaves out one that mirrors");
  const LG = "desc:LG HDR 4K X0";
  const lgDesk = Object.assign({}, monitorOutput, { identifier: LG });
  // rows: [name, outputs, saved, identifier, offBlock]
  const blocks = [
    ["another display on", pair, {}, "DP-2", ""],
    ["the other display off", [monitorOutput, offLive], {}, "DP-2", "only-on"],
    ["the other display mirrors it", [monitorOutput, mirrorLive], {}, "DP-2", "only-on"],
    ["a third display on while one mirrors it by connector", [lgDesk, mirrorLive, third], {}, LG, "mirrored"],
    ["a saved rule mirrors it by identifier", [lgDesk, side, third], { "DP-3": { mirror: LG } }, LG, "mirrored"],
    ["the other connector of its own tiled group", tiledOutputs.concat([side]), {}, "xdr", ""]
  ];
  for (const [name, list, saved, id, want] of blocks) same(logic.offBlock(list, saved, {}, id), want, "offBlock: " + name);
  // rows: [name, outputs, draft, identifier, choice values]
  const mirrorRows = [
    ["each other display on", [monitorOutput, side, third], {}, "DP-2", ["", "DP-3", "HDMI-A-1"]],
    ["no display that is off", [monitorOutput, offLive, third], {}, "DP-2", ["", "HDMI-A-1"]],
    ["no display drafted off", [monitorOutput, side, third], off, "DP-2", ["", "HDMI-A-1"]],
    ["no display that mirrors", [monitorOutput, side, Object.assign({}, third, { mirrorOf: "DP-3" })], {}, "DP-2", ["", "DP-3"]],
    ["Off alone for a display another mirrors", [monitorOutput, mirrorLive, third], {}, "DP-2", [""]],
    ["no tiled group", tiledOutputs.concat([side]), {}, "DP-3", [""]]
  ];
  for (const [name, list, draft, id, want] of mirrorRows) same(logic.mirrorChoices(list, {}, draft, id).map(c => c.value), want, "mirrorChoices: " + name);
  const choices = logic.mirrorChoices([monitorOutput, side, third], {}, {}, "DP-2");
  same([logic.mirrorIndex(choices, undefined), logic.mirrorIndex(choices, "HDMI-A-1"), logic.mirrorIndex(choices, "DP-3"), logic.mirrorIndex(choices, "DP-9")], [0, 2, 1, 0], "mirrorIndex finds the target by identifier or connector");
  const desk = [monitorOutput, Object.assign({}, side, { identifier: "desc:LG HDR 4K X1" })];
  same(logic.mirrorIndex(logic.mirrorChoices(desk, {}, {}, "DP-2"), "DP-3"), 1, "mirrorIndex finds a target saved by connector whose choice is its identifier");

  // --- Colour ------------------------------------------------------------------
  const hdrLive = Object.assign({}, monitorOutput, { colorManagementPreset: "hdr", bitdepth: 10, sdrBrightness: 1.3, sdrSaturation: 1.1 });
  const sdrLive = Object.assign({}, monitorOutput, { colorManagementPreset: "srgb", bitdepth: 8, sdrBrightness: 1, sdrSaturation: 1 });
  const colourKeys = rule => Object.keys(rule).filter(key => ["mode", "position", "scale", "transform"].indexOf(key) === -1);
  same(colourKeys(logic.effectiveRule(hdrLive, undefined, undefined)), [], "effectiveRule names no colour field Hyprland set");
  same(colourKeys(logic.effectiveRule(hdrLive, { cm: "wide", bitdepth: 10 }, undefined)), ["cm", "bitdepth"], "effectiveRule keeps the colour fields a rule names");
  const draftColour = (live, steps) => steps.reduce((draft, patch) => logic.withOutputDraft([live], {}, draft, "DP-2", patch), {})["DP-2"];
  // rows: [name, live output, patches, colour fields of the draft]
  const drafts = [
    ["a colour mode", sdrLive, [{ cm: "wide" }], { cm: "wide" }],
    ["an HDR level beside an HDR mode", sdrLive, [{ cm: "hdr" }, { sdrbrightness: 1.5 }], { cm: "hdr", sdrbrightness: 1.5 }],
    ["an HDR level alone keeps the mode Hyprland shows", hdrLive, [{ sdrsaturation: 0.8 }], { cm: "hdr", sdrsaturation: 0.8 }],
    ["leaving HDR drops its levels", sdrLive, [{ cm: "hdr" }, { sdrbrightness: 1.5 }, { cm: "srgb" }], { cm: "srgb" }],
    ["a depth", sdrLive, [{ bitdepth: 10 }], { bitdepth: 10 }]
  ];
  for (const [name, live, steps, want] of drafts) {
    const rule = draftColour(live, steps);
    const colour = {};
    colourKeys(rule).forEach(key => { colour[key] = rule[key]; });
    same(colour, want, "withOutputDraft: " + name);
  }
  // rows: [name, live output, rule, colourOf]
  const colours = [
    ["Hyprland's reading where the rule names none", hdrLive, {}, { cm: "hdr", bitdepth: 10, sdrbrightness: 1.3, sdrsaturation: 1.1 }],
    ["an sRGB display at 8 bits", sdrLive, {}, { cm: "srgb", bitdepth: 8, sdrbrightness: 1, sdrsaturation: 1 }],
    ["an HDR mode the rule names without levels", hdrLive, { cm: "hdredid" }, { cm: "hdredid", bitdepth: 10, sdrbrightness: 1, sdrsaturation: 1 }],
    ["the rule's own fields", sdrLive, { cm: "hdr", bitdepth: 10, sdrbrightness: 1.5, sdrsaturation: 0.7 }, { cm: "hdr", bitdepth: 10, sdrbrightness: 1.5, sdrsaturation: 0.7 }]
  ];
  for (const [name, live, rule, want] of colours) same(logic.colourOf(live, rule), want, "colourOf: " + name);
  const wide = { hdr: false, chroma: true, bt2020: true, colourModes: ["auto", "srgb", "wide", "edid", "dcip3", "dp3", "adobe"] };
  same(logic.colourModeChoices(null, "srgb").map(c => c.value), ["srgb"], "colourModeChoices: sRGB alone while no panel is read");
  same(logic.colourModeChoices(wide, "srgb").map(c => c.value), wide.colourModes, "colourModeChoices: the modes the panel offers");
  same(logic.colourModeChoices(wide, "hdr").map(c => c.value), wide.colourModes.concat(["hdr"]), "colourModeChoices: the current mode the panel does not offer");
  assert.ok(logic.colourModeChoices(wide, "hdr").every(c => typeof c.label === "string" && c.label !== ""), "colourModeChoices: every mode has a label");
  const takesAll = { hdr: true, chroma: true, bt2020: true, colourModes: ["auto", "srgb", "wide", "edid", "hdr", "hdredid", "dcip3", "dp3", "adobe"] };
  const takesNone = { hdr: false, chroma: false, bt2020: false, colourModes: ["srgb"] };
  const on = logic.effectiveRule(sdrLive, undefined, undefined);
  // rows: [name, rule, panel, colour, rows shown]
  const rowsShown = [
    ["a display that is off", Object.assign({}, on, { disabled: true }), takesAll, logic.colourOf(hdrLive, {}), { mode: false, depth: false, hdr: false }],
    ["a display that mirrors", Object.assign({}, on, { mirror: "DP-3" }), takesAll, logic.colourOf(hdrLive, {}), { mode: false, depth: false, hdr: false }],
    ["a panel that takes nothing", on, takesNone, logic.colourOf(sdrLive, {}), { mode: false, depth: true, hdr: false }],
    ["no panel read", on, null, logic.colourOf(sdrLive, {}), { mode: false, depth: true, hdr: false }],
    ["an HDR panel in HDR", on, takesAll, logic.colourOf(hdrLive, {}), { mode: true, depth: true, hdr: true }],
    ["an HDR panel in sRGB", on, takesAll, logic.colourOf(sdrLive, {}), { mode: true, depth: true, hdr: false }],
    ["a mode the panel lacks, so Standard is a choice", on, takesNone, logic.colourOf(sdrLive, { cm: "wide" }), { mode: true, depth: true, hdr: false }]
  ];
  for (const [name, rule, panel, colour, want] of rowsShown) same(logic.colourRows(rule, panel, colour), want, "colourRows: " + name);
  assert.ok(/(^|[^0-9])125([^0-9]|$)/.test(logic.levelText(1.25)), "levelText shows a level as its percent");
  // The panel of a display, keyed by connector. rows: [name, support, output, panel]
  const panelRows = [
    ["a capable panel", { "DP-2": takesAll }, monitorOutput, takesAll],
    ["a panel not read", { "DP-3": takesAll }, monitorOutput, null],
    ["no panel read", null, monitorOutput, null],
    ["a display named by description, keyed by its connector", { "DP-2": takesAll }, lgDesk, takesAll]
  ];
  for (const [name, support, out, want] of panelRows) same(logic.panelOf(support, out), want, "panelOf: " + name);
  same(logic.colourModeChoices(logic.panelOf({ "DP-3": takesAll }, monitorOutput), "srgb").map(c => c.value), ["srgb"], "a display with no panel read offers sRGB alone");
  // A tiled display takes each colour change on every connector.
  const tiledLive = tiledOutputs.map(o => Object.assign({}, o, sdrLive, { name: o.name, identifier: o.identifier, x: o.x }));
  const tiledColour = [{ cm: "hdr" }, { sdrbrightness: 1.4 }, { bitdepth: 10 }].reduce((draft, patch) => logic.withOutputDraft(tiledLive, {}, draft, "xdr", patch), {});
  same(["DP-1", "DP-5"].map(name => [tiledColour[name].cm, tiledColour[name].sdrbrightness, tiledColour[name].bitdepth]), [["hdr", 1.4, 10], ["hdr", 1.4, 10]], "withOutputDraft: a tiled display's colour on every connector");
  const tiledBack = logic.withOutputDraft(tiledLive, {}, tiledColour, "xdr", { cm: "srgb" });
  same(["DP-1", "DP-5"].map(name => [tiledBack[name].cm, tiledBack[name].sdrbrightness]), [["srgb", undefined], ["srgb", undefined]], "withOutputDraft: leaving HDR drops the levels on every connector");

  const present = resolved.displays.map(d => d.device);
  same(logic.setAssignment(entries, KEY_B, "Apple Studio Display", "DP-3", present).map(e => [e.device, e.output]), [
    [KEY_A, "DP-2"],
    ["usb:devices/usb1/1-9#S", "DP-3"],
    ["backlight:intel_backlight", "DP-2"],
    [KEY_B, "DP-3"]], "a new choice replaces the device's own entry and a present device's entry on that output, and keeps a stale one there");
  same(logic.clearAssignment(entries, KEY_A).map(e => e.device), [KEY_B, "usb:devices/usb1/1-9#S", "usb:devices/usb1/1-2#C02", "backlight:intel_backlight"]);
  const full = Array.from({ length: 64 }, (_, i) => entry(i === 0 ? KEY_A : "gone-" + i, "X" + i));
  const capped = logic.setAssignment(full, KEY_B, "L", "DP-3", [KEY_A, KEY_B]);
  same([capped.length, capped[0].device, capped[1].device, capped[63].device], [64, KEY_A, "gone-2", KEY_B], "past the ceiling the oldest absent device's entry goes");
  same(logic.parseAssignRequest(JSON.stringify({ device: KEY_A, output: "" })), { ok: true, device: KEY_A, output: "" });
  for (const request of [{ device: KEY_A }, { device: "", output: "DP-2" }])
    same(logic.parseAssignRequest(JSON.stringify(request)), { ok: false, error: "refused: assign=shape want={device,output}" }, "parseAssignRequest: " + JSON.stringify(request));

  // --- Keys, scrolls and links ----------------------------------------------
  const shown = logic.displaysValue(resolved, logic.emptyRuns());
  const keySteps = [
    [50, "up", 5, 55], [98, "up", 5, 100], [3, "up", 5, 4], [4, "up", 5, 5], [5, "up", 5, 10],
    [6, "down", 5, 1], [5, "down", 5, 4], [2, "down", 5, 1], [1, "down", 5, 1], [50, "down", 10, 40]
  ];
  for (const [current, direction, step, want] of keySteps) assert.equal(logic.keyStep(current, direction, step), want, `keyStep(${current}, ${direction}, ${step})`);
  // The presses that waited for one helper list step in order from its level.
  const pressRuns = [[50, [], 50], [50, ["down", "down", "up"], 45], [6, ["down", "up"], 2], [6, ["up", "down"], 6]];
  for (const [current, directions, want] of pressRuns) assert.equal(logic.keySteps(current, directions, 5), want, `keySteps(${current}, ${JSON.stringify(directions)}, 5)`);
  same(logic.keyChanges(shown, "DP-5", "focused", ["down", "down", "up"], 5, false), [{ id: XDR, percent: 45 }], "every waiting press moves the focused display");
  same(logic.keyChanges(shown, "DP-5", "focused", ["up"], 5, false), [{ id: XDR, percent: 55 }], "a key changes the display on the focused output");
  same(logic.keyChanges(shown, "DP-2", "focused", ["down"], 5, false), [{ id: STUDIO_A, percent: 25 }], "an assigned display takes its screen's key");
  same(logic.keyChanges(shown, "DP-3", "focused", ["up"], 5, false), [], "no display on the focused output changes nothing");
  same(logic.keyChanges(shown, "HDMI-A-1", "focused", ["up"], 5, false), [], "a display that is not ready changes nothing");
  same(logic.keyChanges(shown, "DP-1", "all", ["up"], 5, false),
    [{ id: XDR, percent: 55 }, { id: STUDIO_A, percent: 35 }, { id: STUDIO_B, percent: 100 }, { id: "backlight:intel_backlight", percent: 4 }],
    "keysTarget all moves every ready display by its own step");
  same(logic.keyChanges(shown, "DP-2", "all", ["up"], 5, false).map(c => c.id), [STUDIO_A, XDR, STUDIO_B, "backlight:intel_backlight"],
    "keysTarget all changes the focused output's display first, where the on-screen display shows");
  same(logic.keyChanges(shown, "eDP-1", "focused", ["up"], 5, true),
    [{ id: "backlight:intel_backlight", percent: 4 }, { id: XDR, percent: 51 }, { id: STUDIO_A, percent: 31 }, { id: STUDIO_B, percent: 96 }],
    "a linked key moves the others by the focused display's change");
  assert.throws(() => logic.keyChanges(shown, "DP-1", "every", ["up"], 5, false), /keysTarget "every"/);
  same(logic.linkedChanges(shown, STUDIO_A, 60, true),
    [{ id: STUDIO_A, percent: 60 }, { id: XDR, percent: 80 }, { id: STUDIO_B, percent: 100 }, { id: "backlight:intel_backlight", percent: 33 }],
    "a linked slider moves every other ready display by its delta, held to 100");
  same(logic.linkedChanges(shown, STUDIO_B, 0, true),
    [{ id: STUDIO_B, percent: 1 }, { id: XDR, percent: 1 }, { id: STUDIO_A, percent: 1 }, { id: "backlight:intel_backlight", percent: 1 }],
    "a linked slider holds every display at 1 or more");
  same(logic.linkedChanges(shown, STUDIO_A, 60, false), [{ id: STUDIO_A, percent: 60 }], "unlinked moves its own display alone");
  same(logic.linkedChanges(shown, "ddc:HDMI-A-1", 60, true), [], "a display that is not ready changes nothing");
  assert.equal(logic.scrollTarget(50, 20, 1), 70);
  assert.equal(logic.scrollTarget(50, -60, 1), 1);
  same(logic.panelOrder(shown, "DP-2").map(d => d.id), [STUDIO_A, XDR, STUDIO_B, "ddc:HDMI-A-1", "backlight:intel_backlight"], "the flyout's own screen first");
  same(logic.parseSetRequest(JSON.stringify({ id: XDR, percent: 140, osd: true })), { ok: true, id: XDR, percent: 100, osd: true });
  for (const request of [{ id: XDR, percent: "60" }, { id: XDR, percent: 60, osd: "yes" }])
    same(logic.parseSetRequest(JSON.stringify(request)), { ok: false, error: "refused: set=shape want={id,percent,osd?}" }, "parseSetRequest: " + JSON.stringify(request));

  // --- The idle dim ----------------------------------------------------------
  // `shown` holds the XDR at 50, Studio A at 30, Studio B at 95, the DDC
  // display not ready and the backlight at 3.
  same(logic.dimPlan(shown, 30),
    { sets: [{ id: XDR, percent: 30 }, { id: STUDIO_B, percent: 30 }], kept: [{ id: XDR, percent: 50 }, { id: STUDIO_B, percent: 95 }] },
    "every ready display brighter than the level dims to it and keeps its level before; one at the level or darker is left");
  same(logic.dimPlan(shown, 100), { sets: [], kept: [] }, "a level no display is above dims nothing");
  assert.throws(() => logic.dimPlan(shown, "30"), /dimPercent "30"/);
  const kept = [{ id: XDR, percent: 50 }, { id: STUDIO_B, percent: 95 }, { id: "hidraw:gone", percent: 40 }, { id: "ddc:HDMI-A-1", percent: 60 }];
  same(logic.restoreChanges(shown, kept), [{ id: XDR, percent: 50 }, { id: STUDIO_B, percent: 95 }],
    "input brings back each kept display still ready, at its kept level; one gone or not ready is skipped");
  same(logic.releaseKept(kept, [XDR, "ddc:HDMI-A-1"]), [{ id: STUDIO_B, percent: 95 }, { id: "hidraw:gone", percent: 40 }],
    "a display set while dimmed is no longer brought back");
  const presetText = (entry, preset) => preset.label !== undefined ? preset.label : preset.value + " " + entry.unit;
  const after = { unit: "seconds", presets: [{ value: 0, label: "Never" }, { value: 60 }, { value: 120 }] };
  same(logic.presetChoices(after, 60, presetText), [{ label: "Never", value: 0 }, { label: "60 seconds", value: 60 }, { label: "120 seconds", value: 120 }],
    "one choice per preset, in order");
  same(logic.presetChoices(after, 45, presetText).slice(-1), [{ label: "45 seconds", value: 45 }], "a custom value is the last choice");

  // --- Status ----------------------------------------------------------------
  let waiting = logic.queueSet(logic.emptyRuns(), XDR, 80);
  assert.equal(logic.displaysValue(resolved, waiting)[0].percent, 80, "a display shows the level waiting for it");
  const inFlight = logic.takeRun(waiting).runs;
  assert.equal(logic.displaysValue(resolved, inFlight)[0].percent, 80, "a display shows the level in flight for it");
  const steps = { "apple-displays": { state: "needed", reason: "hidraw-denied" }, "i2c-dev": { state: "denied", reason: "no-uaccess-rule" } };
  const values = logic.statusValues(resolved, listed.backends, logic.emptyRuns(), steps, ["ddcutil"], null, "ready");
  same(Object.keys(values), ["displays", "assignments", "appleAccess", "ddcAccess", "ddcTool", "backlightTool"]);
  same(values.displays.state, "ready");
  same(values.displays.items[1], { id: STUDIO_A, device: KEY_A, label: "Apple Studio Display", backend: "hidraw", state: "ready", percent: 30, outputs: ["DP-2"], assigned: true });
  same(values.assignments, { entries: resolved.assignments, error: null });
  same(values.appleAccess, { tone: "warning", text: "Needs your permission", action: true });
  same(values.ddcAccess, { tone: "danger", text: "DDC access isn't supported on this system", action: false });
  same(values.ddcTool, { tone: "warning", text: "Not installed", action: true });
  same(values.backlightTool, { tone: "ok", text: "Installed", action: false });
  const noTool = { ddc: { state: "ready" }, backlight: { state: "missing" } };
  same(logic.statusValues(resolved, noTool, logic.emptyRuns(), steps, ["brightnessctl"], null, "ready").backlightTool,
    { tone: "warning", text: "Not installed", action: true }, "Install is offered while a backlight needs brightnessctl");
  const texts = { absent: "absent text", denied: "denied text" };
  const stepStates = [
    ["ready", { tone: "ok", text: "Allowed", action: false }],
    ["needed", { tone: "warning", text: "Needs your permission", action: true }],
    ["nixos", { tone: "warning", text: "Needs your NixOS configuration", action: true }],
    ["absent", { tone: "info", text: "absent text", action: false }],
    ["denied", { tone: "danger", text: "denied text", action: false }],
    ["unknown", { tone: "warning", text: "Access could not be checked", action: false }]
  ];
  for (const [state, want] of stepStates) same(logic.stepState({ state: state, reason: "r" }, texts), want, "stepState: " + state);
  same(logic.stepState(null, texts), stepStates[5][1], "an unprobed step reads unknown");
  assert.throws(() => logic.stepState({ state: "maybe" }, texts), /step state "maybe"/);
  const unread = logic.statusValues(null, null, logic.emptyRuns(), null, ["brightnessctl"], "refused: assignments=unparsed", "failed");
  same([unread.displays, unread.assignments.error, unread.appleAccess.text, unread.backlightTool], [{ state: "failed", items: [] }, "refused: assignments=unparsed",
    "Access could not be checked", { tone: "info", text: "Not needed", action: false }]);
  same(logic.statusWrites({ displays: values.displays, ddcTool: { tone: "ok", text: "Installed", action: false } }, values).map(w => w.key),
    ["assignments", "appleAccess", "ddcAccess", "ddcTool", "backlightTool"], "only changed values are written");
  const needed = [["ok", false], ["info", false], ["warning", true], ["danger", true]];
  for (const [tone, want] of needed) assert.equal(logic.accessNeeded({ tone: tone, text: "t", action: false }), want, "accessNeeded: " + tone);
  same(["success", "info", "warning", "danger"].map(tone => logic.formWarningTone(tone)), ["muted", "muted", "warning", "danger"],
    "status tones are mapped to form warning tones");
  const noAccess = (backend) => ({ id: backend + ":x", backend: backend, state: "no-access" });
  const accessKeys = [[noAccess("hidraw"), "appleAccess"], [noAccess("ddc"), "ddcAccess"], [noAccess("backlight"), null], [shown[0], null]];
  for (const [display, want] of accessKeys) same(logic.accessKey(display), want, "accessKey: " + display.backend + " " + display.state);
  assert.throws(() => logic.accessKey(noAccess("usb")), /backend "usb"/);
  const listTexts = [
    ["pending", 0, "Reading displays"], ["ready", 0, "No display with brightness control"], ["ready", 2, ""],
    ["failed", 0, "Displays could not be read."], ["failed", 2, "Displays could not be read again, so these may be out of date."]
  ];
  for (const [state, count, want] of listTexts) assert.equal(logic.listText(state, count), want, `listText(${state}, ${count})`);
  assert.throws(() => logic.listText("gone", 0), /list state "gone"/);
  const savedTexts = [
    [null, "These displays or screens are not connected now."],
    ["refused: assignments=unwritten error=3", "Your choice could not be saved and will be lost when VGS restarts."],
    ["refused: assignments=unparsed", "The saved choices could not be read. Your next choice replaces them."]
  ];
  for (const [error, want] of savedTexts) assert.equal(logic.savedChoicesText(error), want, "savedChoicesText: " + error);
  assert.equal(logic.stateText("no-access"), "Needs your permission");
  assert.equal(logic.clampPercent(0), 1);
  assert.equal(logic.clampPercent(NaN), null);
}

verify(load(file));

const CONTROLS = [
  ["no coalescing: each change waits as its own run", "            next.sets[i].percent = percent;\n            return next;", "            break;"],
  ["a waiting list goes before the changes", "    if (next.sets.length > 0) {", "    if (next.sets.length > 0 && !next.list) {"],
  ["a second run starts while one is in flight", "    if (runs.busy !== null) return { runs: runs, run: null };", ""],
  ["the key ignores the focused output", "        if (displays[i].state === \"ready\" && displays[i].outputs.indexOf(name) !== -1) return displays[i];", "        if (displays[i].state === \"ready\") return displays[i];"],
  ["no fine steps at the dark end", "    var size = fine ? 1 : step;", "    var size = step;"],
  ["the waiting presses step out of order", "return directions.reduce(", "return directions.slice().reverse().reduce("],
  ["a waiting press is lost", "return directions.reduce(function (level, direction) { return keyStep(level, direction, step); }, current);", "return keyStep(current, directions[0], step);"],
  ["linked displays take the level, not the delta", "changes.push({ id: d.id, percent: clampPercent(d.percent + delta) });", "changes.push({ id: d.id, percent: wanted });"],
  ["a stale entry whose output is gone applies", "if (display === null || group === null) {", "if (display === null) {"],
  ["an entry places a display the helper placed", "} else if (display.outputs.length > 0 || group", "} else if (group"],
  ["the judge takes one device twice", "if (hasOwn(devices, e.device)) return", "if (false) return"],
  ["a new choice drops stale entries", "return e.device !== device && !(e.output === output && present.indexOf(e.device) !== -1);", "return e.device !== device && e.output !== output;"],
  ["a level of 0 turns a panel off", "return Math.max(MIN_PERCENT, Math.min(MAX_PERCENT, Math.round(value)));", "return Math.max(0, Math.min(MAX_PERCENT, Math.round(value)));"],
  ["a needed step offers no Allow", "case \"needed\": return { tone: \"warning\", text: \"Needs your permission\", action: true };", "case \"needed\": return { tone: \"warning\", text: \"Needs your permission\", action: false };"],
  ["an allowed step offers Allow", "case \"ready\": return { tone: \"ok\", text: \"Allowed\", action: false };", "case \"ready\": return { tone: \"ok\", text: \"Allowed\", action: true };"],
  ["an entry takes an output another display lights", "group.names.some(function (name) { return lit[name] === true; })", "group.names.some(function (name) { return false; })"],
  ["the level in flight is not shown", "runs.busy.id === id) return runs.busy.percent;", "runs.busy.id === id) return null;"],
  ["the pane shows a step that is ready", "return value.tone === \"warning\" || value.tone === \"danger\";", "return true;"],
  ["the pane hides a step the system blocks", "return value.tone === \"warning\" || value.tone === \"danger\";", "return value.tone === \"warning\";"],
  ["form rows take a status success tone", "return tone === \"danger\" ? \"danger\" : tone === \"warning\" ? \"warning\" : \"muted\";", "return tone;"],
  ["a no-access Apple display offers the DDC step", "case \"hidraw\": return \"appleAccess\";", "case \"hidraw\": return \"ddcAccess\";"],
  ["brightnessctl is never offered", "backends !== null && backends.backlight.state === \"missing\"", "false"],
  ["a screen the helper lit is a choice", "return helperLit[name] === true;", "return false;"],
  ["a screen a user's choice lit is no choice", "if (!d.assigned) d.outputs.forEach(", "if (true) d.outputs.forEach("],
  ["a user-placed display takes no Screen choice", "return display.outputs.length === 0 || display.assigned;", "return display.outputs.length === 0;"],
  ["keysTarget all ignores the focused output's order", "return panelOrder(displays, focused).filter(", "return displays.filter("],
  ["a failed list with items says nothing", "\"Displays could not be read again, so these may be out of date.\"", "\"\""],
  ["a failed write reads as an unread file", "if (error.indexOf(\"refused: assignments=unwritten \") === 0)", "if (false)"],
  ["the list judge takes an unknown backend", "if (BACKENDS.indexOf(d.backend) === -1) return bad(\"backend\");", "if (false) return bad(\"backend\");"],
  ["the list judge takes an empty label", "if (typeof d.label !== \"string\" || d.label === \"\") return", "if (typeof d.label !== \"string\") return"],
  ["the list judge takes a negative percent", "Number.isInteger(d.percent) && d.percent >= 0 && d.percent <= 100", "Number.isInteger(d.percent) && d.percent <= 100"],
  ["the set judge takes a percent past 100", "answer.percent < 0 || answer.percent > 100)", "answer.percent < 0)"],
  ["the set judge takes a negative percent", "!Number.isInteger(answer.percent) || answer.percent < 0 ||", "!Number.isInteger(answer.percent) ||"],
  ["assignment text has no length cap", "value.length <= ASSIGNMENT_TEXT_MAX && ", ""],
  ["a set request takes any osd", "(hasOwn(r, \"osd\") && typeof r.osd !== \"boolean\")", "false"],
  ["an assign request takes an empty device", "!isPlainObject(r) || !isText(r.device) ||", "!isPlainObject(r) ||"],
  ["the dim raises a darker display", "return d.state === \"ready\" && d.percent > level;", "return d.state === \"ready\";"],
  ["the dim keeps the dimmed level", "kept: brighter.map(function (d) { return { id: d.id, percent: d.percent }; })", "kept: brighter.map(function (d) { return { id: d.id, percent: level }; })"],
  ["a level set while dimmed is brought back over", "return ids.indexOf(k.id) === -1;", "return true;"],
  ["a display gone is brought back", "return display !== null && display.state === \"ready\";", "return display === null || display.state === \"ready\";"],
  ["a display no longer ready is brought back", "return display !== null && display.state === \"ready\";", "return display !== null;"],
  ["a custom value has no choice", "if (!choices.some(function (c) { return c.value === value; }))", "if (false)"]
  ,["mode choices do not group sizes", "if (seen[key]) return;", ""],
  ["scale choices allow fractional logical pixels", "if (!scaleFits(mode, scale)) return;", ""],
  ["a draft loses the current position", "merged.position = { x: current.position.x, y: current.position.y };", "merged.position = { x: 0, y: 0 };"],
  ["dirty rules ignore pending changes", "if (JSON.stringify(draft[id]) !== JSON.stringify((saved || {})[id] || {}))", "if (false)"],
  ["a drag pulls a display back to the origin", "rule.position = { x: snapped.x + dx, y: snapped.y + dy };", "rule.position = { x: Math.max(0, snapped.x + dx), y: Math.max(0, snapped.y + dy) };"],
  ["the canvas measures from 0,0", "var left = Math.min.apply(null, items.map(function (item) { return item.x; }));", "var left = 0;"],
  ["the canvas measures from 0,0 down", "var top = Math.min.apply(null, items.map(function (item) { return item.y; }));", "var top = 0;"],
  ["the canvas names no model", "product: productOf(output),", "product: \"\","],
  ["snap ignores neighbour edges", "if (Math.abs(x - candidate) <= SNAP) x = candidate;", "if (false) x = candidate;"],
  ["mode resize leaves neighbours behind", "if (otherRule.position.x >= current.position.x + before.width) {", "if (false) {"],
  ["a tiled group loses its tile offsets", "var dx = rule.position.x - item.x;", "var dx = output.x - item.x;"],
  ["the draft merges over the saved rule", "var rule = named || {};", "var rule = Object.assign({}, saved || {}, draft || {});"],
  ["Hyprland's off state is lost", "if (named ? rule.disabled === true : output.disabled) out.disabled = true;", "if (named && rule.disabled === true) out.disabled = true;"],
  ["Hyprland's mirror is lost", "var mirror = named ? rule.mirror : output.mirrorOf === null ? undefined : output.mirrorOf;", "var mirror = named ? rule.mirror : undefined;"],
  ["a display turned on keeps disabled", "if (out.disabled !== true) delete out.disabled;", ""],
  ["Off keeps an empty mirror", 'if (out.mirror === "" || out.mirror === undefined) delete out.mirror;', ""],
  ["a tiled group turns off one connector", "        next[member.name] = rule;\n", ""],
  ["a size change moves a display that is off", "if (!staysOn(otherRule)) return;", ""],
  ["the canvas draws a mirroring display", "if (rules.every(function (rule) { return rule.mirror !== undefined; })) return;", ""],
  ["the canvas greys nothing", "off: rules.every(function (rule) { return rule.disabled === true; })", "off: false"],
  ["a display counts itself on", "return output.identifier !== identifier && staysOn(ruleOf(saved, draft, output));", "return staysOn(ruleOf(saved, draft, output));"],
  ["a mirror by connector goes unseen", "(mirror === identifier || names.indexOf(mirror) !== -1)", "mirror === identifier"],
  ["a mirrored display turns off", 'return mirroredBy(outputs, saved, draft, identifier).length > 0 ? "mirrored" : "";', 'return "";'],
  ["a mirrored display mirrors", "if (mirroredBy(outputs, saved, draft, identifier).length > 0) return choices;", ""],
  ["a tiled group is a mirror choice", "if (g.identifier === identifier || g.names.length > 1) return;", "if (g.identifier === identifier) return;"],
  ["a display mirrors itself", "if (g.identifier === identifier || g.names.length > 1) return;", "if (g.names.length > 1) return;"],
  ["a display off is a mirror choice", "if (staysOn(ruleOf(saved, draft, output))) choices.push(", "choices.push("],
  ["a mirror saved by connector shows Off", " || choices[i].names.indexOf(mirror) !== -1", ""],
  ["a draft drops the colour a rule names", "COLOUR_KEYS.forEach(function (key) { if (rule[key] !== undefined) out[key] = rule[key]; });", ""],
  ["a draft takes the colour Hyprland set", "COLOUR_KEYS.forEach(function (key) { if (rule[key] !== undefined) out[key] = rule[key]; });", "COLOUR_KEYS.forEach(function (key) { if (rule[key] !== undefined) out[key] = rule[key]; }); if (out.cm === undefined) out.cm = output.colorManagementPreset;"],
  ["an HDR level drafted alone has no mode", "&& merged.cm === undefined) merged.cm = output.colorManagementPreset;", "&& false) merged.cm = output.colorManagementPreset;"],
  ["an HDR level outlives its HDR mode", "if (HDR_MODES.indexOf(merged.cm) === -1) SDR_LEVELS.forEach(function (level) { delete merged[level.key]; });", ""],
  ["the colour shown ignores the rule's mode", "cm: named ? rule.cm : output.colorManagementPreset,", "cm: output.colorManagementPreset,"],
  ["the depth shown ignores Hyprland's", "bitdepth: rule.bitdepth !== undefined ? rule.bitdepth : output.bitdepth\n", "bitdepth: rule.bitdepth !== undefined ? rule.bitdepth : 8\n"],
  ["an HDR level beside a named mode reads as Hyprland's", "rule[level.key] !== undefined ? rule[level.key] : named ? 1 : live[level.key]", "rule[level.key] !== undefined ? rule[level.key] : live[level.key]"],
  ["no panel read offers every mode", 'var modes = panel === null ? ["srgb"] : panel.colourModes.slice();', 'var modes = panel === null ? Object.keys(COLOUR_MODE_LABELS) : panel.colourModes.slice();'],
  ["the current mode is no choice", "if (modes.indexOf(current) === -1) modes.push(current);", ""],
  ["colour rows show for a display that is off", "if (rule.disabled === true || rule.mirror !== undefined) return { mode: false", "if (rule.mirror !== undefined) return { mode: false"],
  ["colour rows show for a display that mirrors", "if (rule.disabled === true || rule.mirror !== undefined) return { mode: false", "if (rule.disabled === true) return { mode: false"],
  ["Colour mode shows with one choice", "mode: colourModeChoices(panel, colour.cm).length > 1,", "mode: true,"],
  ["the HDR levels show outside HDR", "hdr: HDR_MODES.indexOf(colour.cm) !== -1\n", "hdr: true\n"],
  ["a panel is found by identifier", "return support !== null && hasOwn(support, output.name) ? support[output.name] : null;", "return support !== null && hasOwn(support, output.identifier) ? support[output.identifier] : null;"],
  ["a panel not read is found", "return support !== null && hasOwn(support, output.name) ? support[output.name] : null;", "return support !== null ? support[Object.keys(support)[0]] : null;"],
  ["a tiled display's colour reaches one connector", "if (member.name === output.name || (patch.disabled === undefined && patch.mirror === undefined && !colourPatch)) return;", "if (member.name === output.name || (patch.disabled === undefined && patch.mirror === undefined)) return;"],
  ["a tiled connector keeps levels HDR left", "if (merged[key] === undefined) delete rule[key];", "if (merged[key] === undefined) return;"],
];

const source = fs.readFileSync(file, "utf8");
fs.mkdirSync(path.join(__dirname, "..", "tmp"), { recursive: true });
const temp = fs.mkdtempSync(path.join(__dirname, "..", "tmp", "displays-logic-control-"));
try {
  for (const [label, needle, replacement] of CONTROLS) {
    assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
    const mutant = path.join(temp, "DisplaysLogic.js");
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
console.log(`test-displays-logic: ok controls=${CONTROLS.length}`);
