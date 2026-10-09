#!/usr/bin/env node
// The launch rule, shell/Commons/DesktopLaunch.js, under node: the argv the
// launcher and Jarvis hand to shell.run.detached. Expected values are
// written by hand. The controls edit a copy of the file, one rule at a time,
// and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "Commons", "DesktopLaunch.js");

function verify(launch) {
    const ENTRIES = [
        ["a graphical entry runs its command", { command: ["editor", "--new-window"], runInTerminal: false }, ["editor", "--new-window"]],
        ["a terminal entry runs in the default terminal", { command: ["htop"], runInTerminal: true }, ["xdg-terminal-exec", "htop"]],
        ["an entry with no terminal flag runs its command", { command: ["viewer"] }, ["viewer"]]
    ];
    for (const [label, entry, want] of ENTRIES) assert.deepEqual(Array.from(launch.entry(entry)), want, label);
    const command = ["editor"];
    Array.from(launch.entry({ command, runInTerminal: true })).push("extra");
    assert.deepEqual(command, ["editor"], "the entry's command is copied");
    assert.deepEqual(Array.from(launch.open("/home/user/report.txt")), ["gio", "open", "/home/user/report.txt"]);
    assert.deepEqual(Array.from(launch.open("https://example.test/")), ["gio", "open", "https://example.test/"]);

    const plain = value => JSON.parse(JSON.stringify(value));
    const chromium = launch.BROWSERS.find(b => b.id === "chromium");
    const state = cache => JSON.stringify({ profile: { info_cache: cache } });
    const PROFILES = [
        ["each profile in the file's order", state({ Default: { name: "Person 1" }, "Profile 2": { name: "Work" } }),
            [{ label: "Chromium: Person 1", value: "chromium/Default" }, { label: "Chromium: Work", value: "chromium/Profile 2" }]],
        ["text that is not JSON", "{", []],
        ["no profile key", JSON.stringify({ browser: {} }), []],
        ["no info_cache", JSON.stringify({ profile: {} }), []],
        ["JSON null", "null", []],
        ["a profile without a name is left out", state({ Default: {}, "Profile 1": { name: "" }, "Profile 2": { name: "Home" } }),
            [{ label: "Chromium: Home", value: "chromium/Profile 2" }]],
        ["a label past 60 characters ends in an ellipsis", state({ Default: { name: "n".repeat(60) } }),
            [{ label: "Chromium: " + "n".repeat(49) + "\u2026", value: "chromium/Default" }]]
    ];
    for (const [label, text, want] of PROFILES) assert.deepEqual(plain(launch.profiles(chromium, text)), want, "profiles: " + label);

    const defaultChoice = { label: "Default browser", value: "default" };
    const many = {};
    for (let i = 0; i < 70; i++) many["Profile " + i] = { name: "P" + i };
    const CHOICES = [
        ["no browser read offers the default browser alone", {}, [defaultChoice]],
        ["browsers follow the table's order, whatever the keys' order",
            { brave: state({ Default: { name: "Me" } }), chromium: state({ Default: { name: "You" } }) },
            [defaultChoice, { label: "Chromium: You", value: "chromium/Default" }, { label: "Brave: Me", value: "brave/Default" }]],
        ["an unreadable Local State adds nothing", { edge: "not json" }, [defaultChoice]]
    ];
    for (const [label, texts, want] of CHOICES) assert.deepEqual(plain(launch.openWithChoices(texts)), want, "openWithChoices: " + label);
    const capped = plain(launch.openWithChoices({ vivaldi: state(many) }));
    assert.equal(capped.length, 64, "openWithChoices: cut to 64 choices");
    assert.deepEqual(capped[63], { label: "Vivaldi: P62", value: "vivaldi/Profile 62" }, "openWithChoices: the cut keeps the first profiles");

    const target = "https://example.test/day";
    const OPEN_WITH = [
        ["the unset choice opens with the default application", "", ["gio", "open", target]],
        ["Chromium in its Default profile", "chromium/Default", ["chromium", "--profile-directory=Default", target]],
        ["Google Chrome", "chrome/Profile 1", ["google-chrome-stable", "--profile-directory=Profile 1", target]],
        ["Brave", "brave/Profile 2", ["brave", "--profile-directory=Profile 2", target]],
        ["Vivaldi", "vivaldi/Default", ["vivaldi-stable", "--profile-directory=Default", target]],
        ["Microsoft Edge", "edge/Profile 3", ["microsoft-edge-stable", "--profile-directory=Profile 3", target]]
    ];
    for (const [label, choice, want] of OPEN_WITH) assert.deepEqual(Array.from(launch.openWith(target, choice)), want, "openWith: " + label);
    for (const choice of ["default", "firefox/Default", "chromium", "chromium/", "/Default", null])
        assert.throws(() => launch.openWith(target, choice), error => error.message === "refused: open-with=" + JSON.stringify(choice), "openWith refuses " + JSON.stringify(choice));
    for (const browser of launch.BROWSERS) {
        const profile = plain(launch.profiles(browser, state({ Default: { name: "Me" } })))[0];
        assert.deepEqual(Array.from(launch.openWith(target, profile.value)), [browser.command, "--profile-directory=Default", target], "openWith takes the choice profiles offers for " + browser.id);
    }
}

verify(load(file));
const source = fs.readFileSync(file, "utf8");
const parent = path.join(__dirname, "..", "tmp");
fs.mkdirSync(parent, { recursive: true });
const scratch = fs.mkdtempSync(path.join(parent, "desktop-launch-"));
let controls = 0;
try {
    for (const [name, needle, replacement] of [
        ["terminal", 'desktopEntry.runInTerminal === true ? ["xdg-terminal-exec"].concat(argv) : argv', "argv"],
        ["opener", 'return ["gio", "open", target];', 'return ["xdg-open", target];'],
        ["profile directory", '"--profile-directory=" + choice.slice(slash + 1)', '"--profile-directory=" + choice'],
        ["unknown choice", 'if (browser === null || slash === choice.length - 1) throw', 'if (slash === choice.length - 1) throw'],
        ["default choice", 'if (choice === "") return open(target);', 'if (choice === "" || choice === "default") return open(target);'],
        ["profile name", 'typeof entry.name !== "string" || entry.name === "") return;', 'typeof entry.name !== "string") return;'],
        ["label bound", "if (label.length > CHOICE_LABEL_MAX)", "if (false)"],
        ["choices bound", "return out.slice(0, CHOICES_MAX);", "return out;"],
        ["browser order", "BROWSERS.forEach(function (browser) {", "BROWSERS.slice().reverse().forEach(function (browser) {"]
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " control matches once");
        const copy = path.join(scratch, "DesktopLaunch.js");
        fs.writeFileSync(copy, source.replace(needle, () => replacement));
        assert.throws(() => verify(load(copy)), assert.AssertionError, name + " control must fail");
        controls++;
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("test-desktop-launch: ok controls=" + controls);
