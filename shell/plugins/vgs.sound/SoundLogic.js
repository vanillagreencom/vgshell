.pragma library

// Pure decisions for vgs.sound: the icon and the text a level draws with,
// a volume step and its clamp, wheel notches, which streams are apps,
// which of them a new output takes, which sink a volume change reaches
// when the default output is a DSP sink, whether an IPC reply failed, the
// playing-apps status value and what the on-screen display shows. QML
// owns PipeWire, processes and timers; scripts/test-sound-logic.js runs
// this file under node.

// One notch of a mouse wheel, in the angle units a WheelEvent reports.
var WHEEL_NOTCH = 120;
// The application.name EasyEffects gives its output stream, and the sink
// it offers apps. Its output carries the processed sound to the device.
var EASYEFFECTS_APP = "EasyEffects";
var EASYEFFECTS_SINK = "easyeffects_sink";

function hasOwn(object, key) {
    return object !== null && typeof object === "object" && Object.prototype.hasOwnProperty.call(object, key);
}

// A volume as a whole percentage.
function percent(volume) {
    return Math.round(volume * 100);
}

// The Lucide icon of an output level: `volume-off` while PipeWire is not
// there, `volume-x` while muted, then `volume`, `volume-1` and `volume-2`
// as the level rises.
function levelIcon(available, volume, muted) {
    if (!available) return "volume-off";
    if (muted) return "volume-x";
    var level = percent(volume);
    if (level <= 0) return "volume";
    if (level < 50) return "volume-1";
    return "volume-2";
}

// A level as a user reads it: Muted, or its percentage.
function levelText(volume, muted) {
    return muted ? "Muted" : percent(volume) + "%";
}

// The Lucide icon of an input: `mic-off` while PipeWire is not there or
// the input is muted.
function inputIcon(available, muted) {
    return available && !muted ? "mic" : "mic-off";
}

// The volume one step of STEP percent in DIRECTION, 1 up or -1 down, leads
// to from VOLUME: whole percentages, never below 0, and never above 100% by
// a step up. A level some other program set above 100% stays where it is
// on a step up, so a step up never lowers it.
function stepped(volume, direction, step) {
    if (direction !== 1 && direction !== -1)
        throw new Error("SoundLogic.stepped: direction " + JSON.stringify(direction) + " is not 1 or -1");
    if (!(typeof step === "number" && step > 0))
        throw new Error("SoundLogic.stepped: step " + JSON.stringify(step) + " is not a positive number");
    var now = percent(volume);
    var next = now + direction * step;
    if (direction > 0) next = Math.max(now, Math.min(next, 100));
    else next = Math.max(next, 0);
    return next / 100;
}

// Whole wheel notches in CARRY plus DELTA, and what is left over, so a
// touchpad's small deltas add up to a step: { steps, carry }, steps
// positive for a turn away from the user.
function wheelSteps(carry, delta) {
    var total = carry + delta;
    var steps = total > 0 ? Math.floor(total / WHEEL_NOTCH) : Math.ceil(total / WHEEL_NOTCH);
    return { steps: steps, carry: total - steps * WHEEL_NOTCH };
}

// The playing streams `pactl --format=json list sink-inputs` printed, as
// { ok: true, inputs: [{ index, app, linkGroup }] }, `app` the stream's
// application.name and `linkGroup` its node.link-group, "" when absent; or
// { ok: false, error } for text that is not that list.
function parseSinkInputs(text) {
    var rows;
    try {
        rows = JSON.parse(text);
    } catch (e) {
        return { ok: false, error: "json=" + e.message };
    }
    if (!Array.isArray(rows)) return { ok: false, error: "shape=not-a-list" };
    var inputs = [];
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (row === null || typeof row !== "object" || typeof row.index !== "number" || row.index < 0 || Math.floor(row.index) !== row.index)
            return { ok: false, error: "input=" + i + " index=malformed" };
        var props = hasOwn(row, "properties") && row.properties !== null && typeof row.properties === "object" ? row.properties : {};
        inputs.push({
            index: row.index,
            app: typeof props["application.name"] === "string" ? props["application.name"] : "",
            linkGroup: typeof props["node.link-group"] === "string" ? props["node.link-group"] : ""
        });
    }
    return { ok: true, inputs: inputs };
}

// Whether a playing stream with application.name APP and node.link-group
// LINKGROUP is an app's: the Apps rows list it and a new output takes it.
// A stream without application.name is no app's; EasyEffects' output and a
// filter chain's output, which shares its node.link-group with the
// filter's sink, carry processed sound to a device, and moving one would
// rewire the processing (Omarchy's bin/omarchy-audio-output-set-default).
function isAppStream(app, linkGroup) {
    return app !== "" && app !== EASYEFFECTS_APP && linkGroup === "";
}

// The indexes of the INPUTS a new output takes: the app streams alone.
function streamsToMove(inputs) {
    var out = [];
    for (var i = 0; i < inputs.length; i++)
        if (isAppStream(inputs[i].app, inputs[i].linkGroup)) out.push(inputs[i].index);
    return out;
}

// The sink a volume change reaches while SINKNAME is the default output.
// NODES are { name, stream, sink, app, linkGroup }, LINKS { source, target }
// node names. A DSP sink, a filter chain's sink or EasyEffects', changes
// what goes into its processing, so its volume would move while the
// speakers did not: the change goes to the device the DSP sink's output
// stream plays to, followed through a chain of them, else to SINKNAME
// itself (Omarchy's shell/plugins/panels/audio/Panel.qml, `volumeSink`).
// A filter chain's output stream shares the filter sink's node.link-group;
// EasyEffects' is the stream its app name names. "" for no default.
function volumeTarget(sinkName, nodes, links) {
    if (sinkName === "") return "";
    var byName = {};
    for (var i = 0; i < nodes.length; i++) byName[nodes[i].name] = nodes[i];
    var seen = {};
    var current = sinkName;
    while (!hasOwn(seen, current)) {
        seen[current] = true;
        var next = downstream(byName[current], nodes, links);
        if (next === "") return current;
        current = next;
    }
    return sinkName;
}

// The device sink SINK's processing plays to, or "" when SINK is no DSP
// sink or its output is not linked to a device sink.
function downstream(sink, nodes, links) {
    if (sink === undefined || sink.stream) return "";
    for (var i = 0; i < nodes.length; i++) {
        var node = nodes[i];
        if (!node.stream || node.sink !== true) continue;
        var feeds = sink.linkGroup !== "" && node.linkGroup === sink.linkGroup
            || sink.name === EASYEFFECTS_SINK && node.app === EASYEFFECTS_APP;
        if (!feeds) continue;
        for (var j = 0; j < links.length; j++) {
            if (links[j].source !== node.name) continue;
            for (var k = 0; k < nodes.length; k++)
                if (nodes[k].name === links[j].target && !nodes[k].stream && nodes[k].sink === true && nodes[k].name !== sink.name)
                    return nodes[k].name;
        }
    }
    return "";
}

// The `streams` status value: whether a new output takes the apps already
// playing, which needs pactl; PACTL is whether the last scan found it.
function streamsState(pactl) {
    if (pactl !== true)
        return { tone: "warning", text: "Apps that play now stay on their output when you choose another. Install pactl to move them.", action: true };
    return { tone: "ok", text: "Apps that play now move to the output you choose." };
}

// Whether an IPC reply REPLY is a refusal or a failure: the capability's
// `refused:`, `unknown:` and `error:` lines.
function replyFailed(reply) {
    return /^(refused|unknown|error):/.test(String(reply));
}

// What the on-screen display shows for KIND, `output` or `input`, at
// VOLUME and MUTED: { icon, level, text }, a muted level empty.
function osdView(kind, volume, muted) {
    var text = levelText(volume, muted);
    if (kind === "output") return { icon: levelIcon(true, volume, muted), level: muted ? 0 : volume, text: text };
    if (kind === "input") return { icon: inputIcon(true, muted), level: muted ? 0 : volume, text: text };
    throw new Error("SoundLogic.osdView: kind " + JSON.stringify(kind) + " is not output or input");
}

// The bar widget's tooltip: the output's name and level, or why there is
// none.
function widgetTooltip(available, device, volume, muted) {
    if (!available) return "Sound is not available";
    if (device === "") return "No output device";
    return device + ": " + levelText(volume, muted);
}
