#!/usr/bin/env node
"use strict";
const fs = require("fs");
const path = require("path");
const { load } = require("../bin/lib/qml-library.js");

const LOGIC = path.join(__dirname, "..", "shell", "plugins", "vgs.screensaver", "ScreensaverLogic.js");
const HELP = path.join(__dirname, "fixtures", "screensaver", "ttfx-help.txt");
let failures = 0;

function report(name, got, want) {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    console.log("  ok    " + name);
    return;
  }
  failures += 1;
  console.log("  FAIL  " + name + "\n        got  " + g + "\n        want " + w);
}

function rowsOf(ctx, frame, previous) {
  return ctx.parseFrame(frame, previous).rows;
}

function suite(ctx, check) {
  const help = fs.readFileSync(HELP, "utf8");
  const choices = ctx.effectChoices(help);
  check("effects include random first", choices[0], { label: "Random", value: "random" });
  check("effects include beams", choices.some(c => c.value === "beams"), true);
  check("effects include thunderstorm", choices.some(c => c.value === "thunderstorm"), true);
  check("effects omit help", choices.some(c => c.value === "help"), false);

  const frame = "\u001b7\u001b[2A\u001b[38;2;255;0;0mR R\u001b[0m&\n<\u001b[48;2;0;0;255mB";
  check("frame parser escapes text, preserves spaces and resets SGR", rowsOf(ctx, frame), ["<font color=\"#ff0000\">R\u00a0R</font>&amp;", "&lt;B"]);
  check("non-SGR CSI is ignored but trailing text stays", rowsOf(ctx, "\u001b[?25lA\u001b[2NB"), ["AB"]);
  check("run merging keeps one font tag for same colour", rowsOf(ctx, "\u001b[38;2;1;2;3mA\u001b[38;2;1;2;3mB"), ["<font color=\"#010203\">AB</font>"]);
  const first = ctx.parseFrame("\u001b[38;2;1;2;3m\nA");
  const second = ctx.parseFrame("\u001b[38;2;4;5;6m\nA", first);
  check("changed carried-in colour reparses unchanged raw row", [second.parsedRows, second.reusedRows, second.rows[1]], [2, 0, "<font color=\"#040506\">A</font>"]);
  const third = ctx.parseFrame("\u001b[38;2;4;5;6m\nA", second);
  check("same raw rows and colours reuse parsed rows", [third.parsedRows, third.reusedRows], [0, 2]);
  const many = Array.from({ length: 4100 }, (_, i) => `\u001b[38;2;${i};0;0mX`).join("");
  check("colour cache has a ceiling", ctx.parseFrame(many).cacheSize <= ctx.COLOR_CACHE_MAX, true);
  check("canvas size floors cells", ctx.canvasSize(2560, 1440, 15, 32), { columns: 170, rows: 45 });
  check("newest frame drops older rows", ctx.newestFrame(["old"], ["new"]), ["new"]);
  check("background drops alpha for ttfx", ctx.backgroundHex("#ff102030"), "#102030");
  check("random command uses random flag", ctx.command("/art", "random", 30, 80, 24, "#000000").slice(-1), ["--random-effect"]);
  check("named command passes the effect", ctx.command("/art", "beams", 30, 80, 24, "#000000").slice(-1), ["beams"]);
  const exits = ctx.createExitState();
  check("quick exits fail after the limit", [
    ctx.effectExitAction(0, 100, exits),
    ctx.effectExitAction(1000, 1100, exits),
    ctx.effectExitAction(2000, 2100, exits)
  ], ["restart", "restart", "fail"]);
  const resetExits = ctx.createExitState();
  ctx.effectExitAction(0, 100, resetExits);
  ctx.effectExitAction(1000, 2500, resetExits);
  check("a long run resets quick exit counting", [
    ctx.effectExitAction(3000, 3100, resetExits),
    ctx.effectExitAction(4000, 4100, resetExits)
  ], ["restart", "restart"]);
}

function runCase(name, file) {
  console.log(name);
  suite(load(file), (row, got, want) => report(row, got, want));
}

runCase("screensaver logic", LOGIC);

const controls = [
  ["SGR reset is handled", "if (code === 0 || code === 39) {\n            color = \"\";\n        }", "if (false) {\n            color = \"\";\n        }"],
  ["help is not an effect", "if (value === \"help\" || seen[value]) continue;", "if (seen[value]) continue;"],
  ["only newest frame is kept", "function newestFrame(previous, next) {\n    return next;\n}", "function newestFrame(previous, next) {\n    return (previous || []).concat(next);\n}"],
  ["NBSP preserves spaces", "out += \"\\u00a0\";", "out += ch;"],
  ["entity escaping handles ampersand", "out += \"&amp;\";", "out += ch;"],
  ["same raw row with changed carried colour reparses", "state.rawRows[i] === raw && state.colorsIn[i] === color", "state.rawRows[i] === raw"],
  ["same colour run is merged", "if (next !== KEEP_COLOR && next !== current) {", "if (next !== KEEP_COLOR) {"],
  ["colour cache is bounded", "if (state.cacheSize > COLOR_CACHE_MAX) {", "if (false) {"],
  ["quick exits stop respawn", "if (state.quickExits >= QUICK_EXIT_LIMIT) {", "if (false) {"],
];

for (const [name, needle, replacement] of controls) {
  const scratchRoot = path.join(process.cwd(), "tmp");
  fs.mkdirSync(scratchRoot, { recursive: true });
  const dir = fs.mkdtempSync(path.join(scratchRoot, "vgs-screensaver-logic-"));
  try {
    const copy = path.join(dir, "ScreensaverLogic.js");
    const text = fs.readFileSync(LOGIC, "utf8");
    const count = text.split(needle).length - 1;
    if (count !== 1) {
      failures += 1;
      console.log("  FAIL  control " + name + " matched " + count + " times");
      continue;
    }
    fs.writeFileSync(copy, text.replace(needle, replacement));
    let tripped = false;
    const savedFailures = failures;
    suite(load(copy), (row, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) tripped = true; });
    failures = savedFailures;
    if (tripped) console.log("  ok    control " + name + " turns the suite red");
    else {
      failures += 1;
      console.log("  FAIL  control " + name + " did not turn the suite red");
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

if (failures) {
  console.log("FAIL screensaver logic failures=" + failures);
  process.exit(1);
}
console.log("PASS screensaver logic");
