.pragma library

// The one rule for starting what a user picked, read by the launcher and
// by Jarvis, which runs this file under node through bin/lib/qml-library.js,
// and the browser profiles a link may open with, read by the bar's calendar.
// entry, open and openWith return the argv a caller hands to
// shell.run.detached.
//
// entry(ENTRY): the parsed Exec of ENTRY, a Quickshell DesktopEntry or an
// object with its `command` and `runInTerminal`. Quickshell leaves the
// terminal to the caller, so a terminal entry runs through
// xdg-terminal-exec; its window then carries the terminal's class.
function entry(desktopEntry) {
    var argv = Array.from(desktopEntry.command);
    return desktopEntry.runInTerminal === true ? ["xdg-terminal-exec"].concat(argv) : argv;
}

// open(TARGET): a file, folder or URL opened with its default application.
function open(target) {
    return ["gio", "open", target];
}

// The Chromium-family browsers a link may open with in one of their
// profiles: `command` is the program the package installs, and `config` the
// directory under XDG_CONFIG_HOME that holds the browser's `Local State`,
// whose `profile.info_cache` names each profile directory's display name.
var BROWSERS = [
    { id: "chromium", name: "Chromium", command: "chromium", config: "chromium" },
    { id: "chrome", name: "Google Chrome", command: "google-chrome-stable", config: "google-chrome" },
    { id: "brave", name: "Brave", command: "brave", config: "BraveSoftware/Brave-Browser" },
    { id: "vivaldi", name: "Vivaldi", command: "vivaldi-stable", config: "vivaldi" },
    { id: "edge", name: "Microsoft Edge", command: "microsoft-edge-stable", config: "microsoft-edge" }
];
// The bounds of a published `choices` status, PluginLogic.STATUS_LABEL_MAX
// and STATUS_LIST_MAX: a list past either is refused whole.
var CHOICE_LABEL_MAX = 60;
var CHOICES_MAX = 64;
// The first choice, which the Settings select stores as "".
var DEFAULT_CHOICE = { label: "Default browser", value: "default" };

function browserById(id) {
    for (var i = 0; i < BROWSERS.length; i++)
        if (BROWSERS[i].id === id) return BROWSERS[i];
    return null;
}

// profiles(BROWSER, TEXT): one choice per profile the `Local State` TEXT of
// BROWSER lists, in the file's order, as { label: "<Browser>: <name>",
// value: "<id>/<directory>" }; none for text that is not JSON or holds no
// profile list. A label past the choices bound ends in an ellipsis.
function profiles(browser, text) {
    var state;
    try {
        state = JSON.parse(text);
    } catch (e) {
        return [];
    }
    var cache = state !== null && typeof state === "object" && state.profile !== null && typeof state.profile === "object" ? state.profile.info_cache : null;
    if (cache === null || typeof cache !== "object") return [];
    var out = [];
    Object.keys(cache).forEach(function (dir) {
        var entry = cache[dir];
        if (entry === null || typeof entry !== "object" || typeof entry.name !== "string" || entry.name === "") return;
        var label = browser.name + ": " + entry.name;
        if (label.length > CHOICE_LABEL_MAX) label = label.slice(0, CHOICE_LABEL_MAX - 1) + "…";
        out.push({ label: label, value: browser.id + "/" + dir });
    });
    return out;
}

// openWithChoices(TEXTS): the Open with choices, the default browser first
// and then the profiles of each browser TEXTS holds a `Local State` text
// for, keyed by browser id, in BROWSERS order, cut to the choices bound.
function openWithChoices(texts) {
    var out = [DEFAULT_CHOICE];
    BROWSERS.forEach(function (browser) {
        if (Object.prototype.hasOwnProperty.call(texts, browser.id)) out = out.concat(profiles(browser, texts[browser.id]));
    });
    return out.slice(0, CHOICES_MAX);
}

// openWith(TARGET, CHOICE): TARGET opened as the Open with CHOICE says:
// "" with the default application, as `open` does, and "<id>/<directory>"
// with that browser in that profile. Any other CHOICE throws
// `refused: open-with=<choice>`.
function openWith(target, choice) {
    if (choice === "") return open(target);
    var slash = typeof choice === "string" ? choice.indexOf("/") : -1;
    var browser = slash > 0 ? browserById(choice.slice(0, slash)) : null;
    if (browser === null || slash === choice.length - 1) throw new Error("refused: open-with=" + JSON.stringify(choice));
    return [browser.command, "--profile-directory=" + choice.slice(slash + 1), target];
}
