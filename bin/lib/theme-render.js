// The target renderer bin/vgshell-theme-judge runs: the judge of a target's
// target.json, the template renderer and the terminal fallback. Nothing here
// reads or writes a file; the caller reads target.json, the templates and a
// package's curated files and hands over their text or bytes.
//
// LOGIC is the shell's theme judge, shell/Commons/ThemeLogic.js, and TOKENS
// its token table, both loaded by the caller through bin/lib/qml-library.js,
// so a token path and a terminal slot name mean here what they mean to the
// shell. docs/architecture/themes.md § Targets holds the rules.
//
// A refusal is { ok: false, reason, detail }; `refusalLine` prints it.
"use strict";
const crypto = require("crypto");

// Every key target.json carries, each required. `wiring` and `reload` may
// be null. `runsCode` is true when the application loads or runs code from
// the target's files, so an installed package's curated file there is
// dropped and the template rendered in its place: renderTarget.
const TARGET_KEYS = ["app", "encoder", "files", "detect", "wiring", "reload", "runsCode"];
// An optional account target writes one render into each account directory
// of one harness, named by its id in shell/Commons/AccountDirectories.js.
// Its entry wiring and selection are relative to each account directory.
// The caller, which reads the account rule, judges that the id names a
// harness: readTarget in bin/vgshell-theme-judge.
const ACCOUNTS_KEY = "accounts";
// The one optional top-level key: the theme selection apply keeps in the
// application's own settings file, `{ base, file, format, key, value }`,
// beside any wiring form. `key` is one key path, or a list of two or more
// key paths that each take the value. bin/lib/theme-select.js makes the
// edit.
const SELECT_KEY = "select";
// An optional editors target serves every installed editor of one family
// from one render: each `{ detect, extensions, user }` names the editor's
// command, its extensions directory under the home directory and its user
// settings directory under the configuration home. An editor is wired only
// while its own command is on PATH, so the target's `detect` is empty. Its
// wiring is the extension form and its selection is relative to each
// editor's `user` directory.
const EDITORS_KEY = "editors";
const EDITOR_KEYS = ["detect", "extensions", "user"];
const EDITOR_BASE = "editor";
// The optional top-level key naming the command a one-time owner step
// installs and the target's hook runs: until it is on PATH the target is
// skipped with `setup-absent`, so no apply runs a hook that cannot work.
const SETUP_KEY = "setup";
const SELECT_KEYS = ["base", "file", "format", "key", "value"];
// `jsonc` is JSON with comments and trailing commas, as VS Code-family
// editors read their settings.
const SELECT_FORMATS = ["json", "jsonc", "toml", "yaml"];
// The longest `key` a line-exact format takes: a root key, or a key in one
// table or top-level mapping. JSON takes any depth.
const SELECT_LINE_DEPTH = 2;
// One segment of a JSON key path: a bare name that may hold dots, since VS
// Code-family editors read `workbench.colorTheme` as one flat key.
const JSON_KEY_PATTERN = /^[A-Za-z0-9_.-]+$/;
// A character a selection value may not hold, since a TOML basic string
// refuses it raw.
const CONTROL_CHARACTER = /[\u0000-\u001f\u007f]/;
const FILE_KEYS = ["template", "destination"];
// The one optional key of a `files` entry: the top-level JSON keys, one of
// which a package's curated file of that destination must hold to be taken.
const CURATED_KEYS_KEY = "curatedKeys";
// The three wiring forms. An include wiring keeps one line in the
// application's configuration file; its optional keys are the section the
// line goes into, the Mozilla profiles.ini paths whose profile directories
// the file is relative to, and the fallback files under HOME tried when the
// configuration-home file is absent. An entry wiring keeps entries to the
// target's files in the application's theme or extension directory and edits
// no file; its optional key is the Obsidian vault registry whose vaults the
// directory is relative to. Exactly one of `links` or `copies` tells which
// entry kind it writes. An extension wiring, an editors target's only form,
// keeps one generated extension in each wired editor's extensions directory:
// `extension` is its `<publisher>.<name>` id, `version` the destination
// whose final bytes make its version, and `copies` its files, each a copy of
// one of the target's files. A null wiring keeps nothing: the target's hook
// asserts the setting that makes its application read the files.
const WIRING_KEYS = ["file", "line", "create"];
const INCLUDE_OPTIONAL_KEYS = ["section", "profiles", "fallbacks"];
const ENTRY_BASE_KEYS = ["base", "dir", "owned"];
const ENTRY_ITEM_KEYS = ["links", "copies"];
const ENTRY_OPTIONAL_KEYS = ["vaults"];
const EXTENSION_KEYS = ["extension", "version", "copies"];
// An extension id, `<publisher>.<name>`, as the editors' own manifests
// spell one, in lower case so it is the folder name the editors compare.
const EXTENSION_ID_PATTERN = /^[a-z0-9][a-z0-9-]*\.[a-z0-9][a-z0-9-]*$/;
// The placeholder a file of an extension target writes its version with.
const VERSION_PLACEHOLDER = "extension.version";
// The directories an entry's `dir` and a selection's `file` are relative
// to: the user's configuration home, ${XDG_CONFIG_HOME:-~/.config}, the home
// directory, or the user's cache home, ${XDG_CACHE_HOME:-~/.cache}.
const ENTRY_BASES = ["config", "home", "cache"];
const ACCOUNT_BASE = "account";
const RELOAD_KEYS = ["command", "timeoutMs"];
// The one optional reload key: `true` makes the hook due on every apply that
// lands the target, for a hook that asserts a setting no file carries.
const ALWAYS_KEY = "always";

// A target name holds no dot, so a destination named `<target>.<ext>` names
// its target by the text before its first dot and no two targets can write
// one state file.
const TARGET_NAME_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

// The one file of a target directory that is never a template.
const TARGET_FILE = "target.json";

// A placeholder naming a terminal slot starts with this; every other one
// names a token path. The token table holds no `terminal` group.
const TERMINAL_PREFIX = "terminal.";

// A placeholder's cases follow its token path, each `|<option>=<text>`, the
// option before the first `=`: caseText.
const CASE_SEPARATOR = "|";
const CASE_PATTERN = /^([^=]+)=(.+)$/;

// The placeholders a wiring line, a reload argument and a selection value
// hold: the stable state directory, which each of them may hold, and the one
// wiring file and the target's own directory, which only a reload argument
// may. A hook reaches the files a target ships beside its templates, such
// as icon themes, through its directory.
const STATE_PLACEHOLDER = "state";
const WIRING_PLACEHOLDER = "wiring";
const TARGET_PLACEHOLDER = "target";

// One segment of an entry's `dir` or `vaults` or of a wiring's `profiles`:
// a directory or file name, a leading dot allowed so `.vscode` can be
// named, never `.` or `..`.
const DIR_SEGMENT_PATTERN = /^\.?[A-Za-z0-9][A-Za-z0-9._-]*$/;
// A segment of an editor's `user` directory, which may hold inner spaces:
// VS Code Insiders keeps its settings under `Code - Insiders/User`.
const USER_SEGMENT_PATTERN = /^[A-Za-z0-9](?:[A-Za-z0-9._ -]*[A-Za-z0-9._-])?$/;

// A wiring section is one bare name, as an INI section or a TOML table
// header writes it between brackets; so is each segment of a selection's
// `key`.
const SECTION_PATTERN = /^[A-Za-z0-9_-]+$/;

// A section header line: the name between brackets, whitespace around it
// and a `#` comment after it allowed. `[[name]]`, a TOML array of tables, is
// no header of `name`.
const SECTION_HEADER = /^\s*\[\s*([^\]]*?)\s*\]\s*(?:#.*)?$/;

// A line that opens a section, a TOML array of tables included: the end of
// the section before it.
const ANY_HEADER = /^\s*\[/;
// A profiles.ini section that names one profile: `[Profile0]`, `[Profile1]`.
// The ini's `[General]` and `[Install<hash>]` sections name none of their own.
const PROFILE_SECTION = /^Profile[0-9]+$/;

// `@@{` is a literal `@{`, `@{name}` a placeholder and a `@{` with no `}`
// after it unterminated. Every other character is literal text, so `#{...}`
// and `${...}` pass through.
const MARKER = /@@\{|@\{((?:[^{}]|\{[^{}]*\})*)\}|@\{/g;

// Each encoder writes one resolved colour, which is `#rrggbbaa`.
const ENCODERS = {
    hex6: (hex, background) => hex6(hex, background),
    hex8: hex => hex.slice(1, 9),
    "gnome-accent": (hex, background) => gnomeAccent(hex6(hex, background))
};

// The accents org.gnome.desktop.interface accent-color names, each with the
// colour libadwaita 1.9.4 draws it in (AdwAccentColor, read from
// libadwaita-1.so). `slate` is the grey one.
const GNOME_ACCENTS = {
    blue: "3584e4", teal: "2190a4", green: "3a944a", yellow: "c88800", orange: "ed5b00",
    red: "e62d42", pink: "d56199", purple: "9141ac", slate: "6f8396"
};
const GREY_ACCENT = "slate";
// Below this OKLCh chroma a colour reads as grey, so its hue says nothing
// and it takes the grey accent: #8ba4b0, chroma 0.033, is a blue-grey that
// takes slate, and #94afca, chroma 0.049, a pale blue that takes blue.
const GREY_CHROMA = 0.045;

function channel(hex, at) {
    return parseInt(hex.slice(at, at + 2), 16);
}

function byteHex(value) {
    return value.toString(16).padStart(2, "0");
}

function hex6(hex, background) {
    if (hex.length < 9 || channel(hex, 7) === 255) return hex.slice(1, 7);
    const alpha = channel(hex, 7) / 255;
    return [1, 3, 5].map(at => byteHex(Math.round(channel(hex, at) * alpha + channel(background, at) * (1 - alpha)))).join("");
}

// RGB, six hex digits, as OKLCh lightness, chroma and hue in degrees,
// by Björn Ottosson's OKLab matrices.
function oklch(rgb) {
    const [r, g, b] = [0, 2, 4].map(at => {
        const c = parseInt(rgb.slice(at, at + 2), 16) / 255;
        return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    });
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    const a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    const bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
    return { l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, c: Math.hypot(a, bb), h: (Math.atan2(bb, a) * 180 / Math.PI + 360) % 360 };
}

function hueDistance(a, b) {
    const d = Math.abs(a - b) % 360;
    return Math.min(d, 360 - d);
}

// The GNOME accent nearest RGB by hue: a theme's accent is a hue, and the
// accents differ by hue at one lightness, so lightness would only pull a
// pale accent toward the paler of two neighbours.
function gnomeAccent(rgb) {
    const colour = oklch(rgb);
    if (colour.c < GREY_CHROMA) return GREY_ACCENT;
    let best = null;
    for (const [name, accent] of Object.entries(GNOME_ACCENTS)) {
        if (name === GREY_ACCENT) continue;
        const distance = hueDistance(colour.h, oklch(accent).h);
        if (best === null || distance < best.distance) best = { name, distance };
    }
    return best.name;
}

function refused(reason, detail) {
    return { ok: false, reason, detail };
}

// The first line a refusal of target NAME is printed with.
function refusalLine(name, refusal) {
    return "target=" + name + " reason=" + refusal.reason + (refusal.detail === "" ? "" : " " + refusal.detail);
}

function isLine(value) {
    return typeof value === "string" && value.trim() !== "" && !/[\r\n]/.test(value);
}

function hasExactKeys(logic, value, keys) {
    return logic.isPlainObject(value) && Object.keys(value).length === keys.length && keys.every(key => logic.hasOwn(value, key));
}

// TEXT as its parts in order: literal strings and { name } placeholders, or
// { ok: false, at } for an unterminated `@{` at offset `at`.
function parseTemplate(text) {
    const parts = [];
    let literal = "";
    let last = 0;
    for (const m of text.matchAll(MARKER)) {
        literal += text.slice(last, m.index);
        last = m.index + m[0].length;
        if (m[0] === "@@{") {
            literal += "@{";
            continue;
        }
        if (m[1] === undefined) return { ok: false, at: m.index };
        parts.push(literal, { name: m[1] });
        literal = "";
    }
    parts.push(literal + text.slice(last));
    return { ok: true, parts };
}

// The first defect of one `files` entry, or "".
function fileError(logic, name, file, at) {
    const key = "files[" + at + "]";
    if (!logic.isPlainObject(file) || !FILE_KEYS.every(k => logic.hasOwn(file, k)) ||
        !Object.keys(file).every(k => FILE_KEYS.includes(k) || k === CURATED_KEYS_KEY)) return "key=" + key;
    if (!logic.isPackageName(file.template) || file.template === TARGET_FILE) return "key=" + key + ".template";
    if (!logic.isPackageName(file.destination) || !file.destination.startsWith(name + ".")) return "key=" + key + ".destination";
    if (logic.hasOwn(file, CURATED_KEYS_KEY) && (!Array.isArray(file.curatedKeys) || file.curatedKeys.length === 0 || !file.curatedKeys.every(isLine)))
        return "key=" + key + ".curatedKeys";
    return "";
}

// The names of the placeholders TEXT holds, or null when a `@{` in it is
// unterminated.
function placeholderNames(text) {
    const parsed = parseTemplate(text);
    return parsed.ok ? parsed.parts.filter(part => typeof part !== "string").map(part => part.name) : null;
}

// TEXT, which acceptTarget admits with placeholders named by VALUES, with
// each written and `@@{` as `@{`. WHAT names the text in the error an
// unexpected placeholder throws.
function withValues(text, values, what) {
    const parsed = parseTemplate(text);
    if (!parsed.ok) throw new Error("theme-render: " + what + " is unterminated");
    return parsed.parts.map(part => {
        if (typeof part === "string") return part;
        if (!Object.prototype.hasOwnProperty.call(values, part.name)) throw new Error("theme-render: " + what + " names placeholder " + part.name);
        return values[part.name];
    }).join("");
}

// The first defect of `wiring`, or "". `file` is relative to the user's
// configuration home, or to each profile directory when `profiles` is
// present, one directory name per segment; `line` holds the state
// directory's placeholder and no other; `section`, when present, is one bare
// section name; `profiles`, when present, is one or more paths relative to
// the home directory, one name per segment, in the order they are tried.
// `fallbacks`, when present, is the same path shape and is tried only after
// the configuration-home file is absent.
function wiringError(logic, wiring) {
    if (!logic.isPlainObject(wiring) || !WIRING_KEYS.every(key => logic.hasOwn(wiring, key)) ||
        !Object.keys(wiring).every(key => WIRING_KEYS.includes(key) || INCLUDE_OPTIONAL_KEYS.includes(key))) return "key=wiring";
    if (typeof wiring.file !== "string" || !wiring.file.split("/").every(logic.isPackageName)) return "key=wiring.file";
    if (!isLine(wiring.line)) return "key=wiring.line";
    const names = placeholderNames(wiring.line) || [];
    if (names.length === 0 || names.some(placeholder => placeholder !== STATE_PLACEHOLDER)) return "key=wiring.line";
    if (typeof wiring.create !== "boolean") return "key=wiring.create";
    if (logic.hasOwn(wiring, "section") && (typeof wiring.section !== "string" || !SECTION_PATTERN.test(wiring.section))) return "key=wiring.section";
    if (logic.hasOwn(wiring, "profiles") && (!Array.isArray(wiring.profiles) || wiring.profiles.length === 0 ||
        !wiring.profiles.every(ini => typeof ini === "string" && ini.split("/").every(segment => DIR_SEGMENT_PATTERN.test(segment))))) return "key=wiring.profiles";
    if (logic.hasOwn(wiring, "fallbacks") && (!Array.isArray(wiring.fallbacks) || wiring.fallbacks.length === 0 ||
        !wiring.fallbacks.every(file => typeof file === "string" && file.split("/").every(segment => DIR_SEGMENT_PATTERN.test(segment))))) return "key=wiring.fallbacks";
    if (logic.hasOwn(wiring, "fallbacks") && logic.hasOwn(wiring, "profiles")) return "key=wiring.fallbacks";
    return "";
}

// The form of an accepted target's WIRING, `include`, `entry`, `extension`
// or `none`,
// which each caller matches exhaustively.
function wiringForm(wiring) {
    if (wiring === null) return "none";
    if (Object.prototype.hasOwnProperty.call(wiring, "extension")) return "extension";
    return entryItemKey(wiring) === "" ? "include" : "entry";
}

function entryItemKey(wiring) {
    const present = ENTRY_ITEM_KEYS.filter(key => Object.prototype.hasOwnProperty.call(wiring, key));
    return present.length === 1 ? present[0] : "";
}

// Whether VALUE is a relative path of one name per segment.
function isRelativePath(value) {
    return typeof value === "string" && value.split("/").every(segment => DIR_SEGMENT_PATTERN.test(segment));
}

// The first defect of an entry `wiring`, or "". `dir` is relative to its
// `base`, or, with `vaults`, to each vault the Obsidian registry at `vaults`
// under `base` lists, one directory name per segment. Exactly one of
// `links` or `copies` maps each entry's file name in `dir` to one of
// DESTINATIONS, the target's own files.
function entryBaseAccepted(base, hasAccounts) {
    return ENTRY_BASES.includes(base) || (hasAccounts && base === ACCOUNT_BASE);
}

function entryError(logic, wiring, destinations, hasAccounts) {
    const itemKey = entryItemKey(wiring);
    if (itemKey === "" || !ENTRY_BASE_KEYS.every(key => logic.hasOwn(wiring, key)) ||
        !Object.keys(wiring).every(key => ENTRY_BASE_KEYS.includes(key) || ENTRY_ITEM_KEYS.includes(key) || ENTRY_OPTIONAL_KEYS.includes(key))) return "key=wiring";
    if (!entryBaseAccepted(wiring.base, hasAccounts)) return "key=wiring.base";
    if (!isRelativePath(wiring.dir)) return "key=wiring.dir";
    if (logic.hasOwn(wiring, "vaults") && !isRelativePath(wiring.vaults)) return "key=wiring.vaults";
    if (typeof wiring.owned !== "boolean") return "key=wiring.owned";
    if (!logic.isPlainObject(wiring[itemKey]) || Object.keys(wiring[itemKey]).length === 0) return "key=wiring." + itemKey;
    for (const [name, destination] of Object.entries(wiring[itemKey])) {
        if (!logic.isPackageName(name)) return "key=wiring." + itemKey + "." + name;
        if (!destinations.has(destination)) return "key=wiring." + itemKey + "." + name;
    }
    return "";
}

// The first defect of an extension `wiring`, or "": its id, the destination
// its version is made from, and its copies, each a package file name mapped
// to one of DESTINATIONS. The version destination itself cannot name the
// version, which renderTarget refuses.
function extensionError(logic, wiring, destinations) {
    if (!hasExactKeys(logic, wiring, EXTENSION_KEYS)) return "key=wiring";
    if (typeof wiring.extension !== "string" || !EXTENSION_ID_PATTERN.test(wiring.extension)) return "key=wiring.extension";
    if (!destinations.has(wiring.version)) return "key=wiring.version";
    if (!logic.isPlainObject(wiring.copies) || Object.keys(wiring.copies).length === 0) return "key=wiring.copies";
    for (const [name, destination] of Object.entries(wiring.copies))
        if (!logic.isPackageName(name) || !destinations.has(destination)) return "key=wiring.copies." + name;
    return "";
}

// The first defect of `editors`, or "": one or more editors, each a command
// name, an extensions directory relative to the home directory and a user
// directory relative to the configuration home, no two sharing a command or
// a directory.
function editorsError(logic, editors) {
    if (!Array.isArray(editors) || editors.length === 0) return "key=editors";
    const seen = new Set();
    for (let at = 0; at < editors.length; at++) {
        const editor = editors[at];
        const key = "key=editors[" + at + "]";
        if (!hasExactKeys(logic, editor, EDITOR_KEYS)) return key;
        if (!logic.isPackageName(editor.detect)) return key + ".detect";
        if (!isRelativePath(editor.extensions)) return key + ".extensions";
        if (typeof editor.user !== "string" || !editor.user.split("/").every(segment => USER_SEGMENT_PATTERN.test(segment))) return key + ".user";
        for (const value of ["detect:" + editor.detect, "extensions:" + editor.extensions, "user:" + editor.user]) {
            if (seen.has(value)) return key;
            seen.add(value);
        }
    }
    return "";
}

// The entries an accepted entry TARGET keeps in its `dir`, in the order
// target.json names them: each entry's `kind`, file `name`, destination and
// path in LIVE, the state directory's `theme/` path. `link` entries are
// symlinks to `to`; `copy` entries are atomic copies of it.
function entryItems(target, live) {
    const form = wiringForm(target.wiring);
    if (form !== "entry") throw new Error("theme-render: entryItems: target " + target.name + " has wiring form " + form);
    const itemKey = entryItemKey(target.wiring);
    const kind = itemKey === "links" ? "link" : "copy";
    return Object.entries(target.wiring[itemKey]).map(([name, destination]) => ({ kind, name, destination, to: live + "/" + destination }));
}

// The placeholders a reload command may name for TARGET.
function reloadPlaceholders(logic, target) {
    const names = [STATE_PLACEHOLDER, TARGET_PLACEHOLDER];
    if (target.wiring !== null && wiringForm(target.wiring) === "include" && !logic.hasOwn(target.wiring, "profiles")) names.push(WIRING_PLACEHOLDER);
    return names;
}

// Whether TARGET's reload command names the wiring-file placeholder.
function reloadNamesWiring(target) {
    if (target.reload === null) return false;
    return target.reload.command.some(arg => {
        const names = placeholderNames(arg);
        return names !== null && names.includes(WIRING_PLACEHOLDER);
    });
}

// The first defect of `reload`, or "": null, or an argv whose placeholders
// are admitted for TARGET, a timeout in whole milliseconds and, when
// present, a boolean `always`.
function reloadError(logic, reload, target) {
    if (reload === null) return "";
    if (!logic.isPlainObject(reload) || !RELOAD_KEYS.every(key => logic.hasOwn(reload, key)) ||
        !Object.keys(reload).every(key => RELOAD_KEYS.includes(key) || key === ALWAYS_KEY)) return "key=reload";
    if (!Array.isArray(reload.command) || reload.command.length === 0 || !reload.command.every(isLine)) return "key=reload.command";
    const names = reload.command.map(placeholderNames);
    const allowed = reloadPlaceholders(logic, target);
    if (names.some(list => list === null || list.some(name => !allowed.includes(name)))) return "key=reload.command";
    if (!Number.isInteger(reload.timeoutMs) || reload.timeoutMs <= 0) return "key=reload.timeoutMs";
    if (logic.hasOwn(reload, ALWAYS_KEY) && typeof reload.always !== "boolean") return "key=reload.always";
    return "";
}

// A `detect` entry: a command name, required, or a non-empty list of command
// names, any one of which stands for the entry. A list holds names only.
function isDetectEntry(logic, entry) {
    if (!Array.isArray(entry)) return logic.isPackageName(entry);
    return entry.length > 0 && entry.every(logic.isPackageName);
}

// Whether the accepted DETECT list is met: every entry is a command ON_PATH
// answers true for, a list entry through any one of its names. An empty
// list is always met. Both of the judge's enablement checks ask this.
function detected(detect, onPath) {
    return detect.every(entry => Array.isArray(entry) ? entry.some(onPath) : onPath(entry));
}

// Whether an accepted TARGET's setup command, when it names one, is a
// command ON_PATH answers true for. Both of the judge's enablement checks
// ask this after `detected`.
function setupDone(target, onPath) {
    return target.setup === undefined || onPath(target.setup);
}

function isJsonFormat(format) {
    return format === "json" || format === "jsonc";
}

// Whether KEY is a key path FORMAT takes: one bare name per segment, a dot
// allowed in a JSON one, and at most SELECT_LINE_DEPTH of them for a
// line-exact format.
function isKeyPath(format, key) {
    const segment = isJsonFormat(format) ? JSON_KEY_PATTERN : SECTION_PATTERN;
    return Array.isArray(key) && key.length > 0 && key.every(name => typeof name === "string" && segment.test(name)) &&
        (isJsonFormat(format) || key.length <= SELECT_LINE_DEPTH);
}

// Whether key path A is B or a table, mapping or object on B's path, so the
// two cannot both hold a string.
function isKeyPrefix(a, b) {
    return a.every((segment, at) => segment === b[at]);
}

// The first defect of `select`, or "": a settings file under one of the
// entry bases, or under each editor's user directory for an editors target,
// one name per segment, its format, the key path the theme is
// named at, or a list of two or more such paths none of which is another or
// lies on another's path, and one line of value whose only placeholder is
// `@{state}`.
function selectError(logic, select, hasAccounts, hasEditors) {
    if (!hasExactKeys(logic, select, SELECT_KEYS)) return "key=select";
    if (!entryBaseAccepted(select.base, hasAccounts) && !(hasEditors && select.base === EDITOR_BASE)) return "key=select.base";
    if (!isRelativePath(select.file)) return "key=select.file";
    if (!SELECT_FORMATS.includes(select.format)) return "key=select.format";
    if (!isKeyPath(select.format, select.key)) {
        const keys = select.key;
        if (!Array.isArray(keys) || keys.length < 2 || !keys.every(key => isKeyPath(select.format, key))) return "key=select.key";
        if (keys.some((a, i) => keys.some((b, j) => i !== j && isKeyPrefix(a, b)))) return "key=select.key";
    }
    if (!isLine(select.value) || CONTROL_CHARACTER.test(select.value)) return "key=select.value";
    const names = placeholderNames(select.value);
    if (names === null || names.some(name => name !== STATE_PLACEHOLDER)) return "key=select.value";
    return "";
}

// Judge the target.json TEXT of the target directory NAME. Answers
// { ok: true, target } with `target` the document and its `name`, or one
// refusal.
function acceptTarget(logic, name, text) {
    if (typeof name !== "string" || !TARGET_NAME_PATTERN.test(name)) return refused("target-name", "got=" + JSON.stringify(name));
    let document;
    try {
        document = JSON.parse(text);
    } catch (e) {
        return refused("target-json", "");
    }
    if (!logic.isPlainObject(document)) return refused("target-schema", "key=document");
    for (const key of Object.keys(document))
        if (!TARGET_KEYS.includes(key) && ![SELECT_KEY, SETUP_KEY, ACCOUNTS_KEY, EDITORS_KEY].includes(key)) return refused("target-schema", "unknown=" + key);
    for (const key of TARGET_KEYS)
        if (!logic.hasOwn(document, key)) return refused("target-schema", "missing=" + key);
    if (!isLine(document.app)) return refused("target-schema", "key=app");
    if (typeof document.runsCode !== "boolean") return refused("target-schema", "key=runsCode");
    if (!logic.hasOwn(ENCODERS, document.encoder)) return refused("target-schema", "key=encoder");
    if (!Array.isArray(document.files) || document.files.length === 0) return refused("target-schema", "key=files");
    const destinations = new Set();
    for (let at = 0; at < document.files.length; at++) {
        const defect = fileError(logic, name, document.files[at], at);
        if (defect !== "") return refused("target-schema", defect);
        if (destinations.has(document.files[at].destination)) return refused("target-schema", "key=files[" + at + "].destination");
        destinations.add(document.files[at].destination);
    }
    if (!Array.isArray(document.detect) || !document.detect.every(entry => isDetectEntry(logic, entry))) return refused("target-schema", "key=detect");
    if (logic.hasOwn(document, SETUP_KEY) && !logic.isPackageName(document.setup)) return refused("target-schema", "key=setup");
    const hasAccounts = logic.hasOwn(document, ACCOUNTS_KEY);
    if (hasAccounts && !logic.isPackageName(document.accounts)) return refused("target-schema", "key=accounts");
    const hasEditors = logic.hasOwn(document, EDITORS_KEY);
    if (hasEditors) {
        const editors = editorsError(logic, document.editors);
        if (editors !== "") return refused("target-schema", editors);
        if (document.detect.length !== 0) return refused("target-schema", "key=detect");
        if (!logic.isPlainObject(document.wiring) || wiringForm(document.wiring) !== "extension") return refused("target-schema", "key=wiring");
    }
    const form = logic.isPlainObject(document.wiring) ? wiringForm(document.wiring) : "";
    const wiring = document.wiring === null ? ""
        : form === "extension" ? (hasEditors ? extensionError(logic, document.wiring, destinations) : "key=wiring")
        : form === "entry" ? entryError(logic, document.wiring, destinations, hasAccounts)
        : wiringError(logic, document.wiring);
    if (wiring !== "") return refused("target-schema", wiring);
    const reload = reloadError(logic, document.reload, document);
    if (reload !== "") return refused("target-schema", reload);
    const select = logic.hasOwn(document, SELECT_KEY) ? selectError(logic, document.select, hasAccounts, hasEditors) : "";
    if (select !== "") return refused("target-schema", select);
    if (hasAccounts) {
        if (!logic.hasOwn(document, SELECT_KEY) || wiringForm(document.wiring) !== "entry" ||
            document.wiring.base !== ACCOUNT_BASE || document.select.base !== ACCOUNT_BASE) return refused("target-schema", "key=accounts");
    } else if ((logic.isPlainObject(document.wiring) && document.wiring.base === ACCOUNT_BASE) ||
        (logic.hasOwn(document, SELECT_KEY) && document.select.base === ACCOUNT_BASE)) {
        return refused("target-schema", "key=accounts");
    }
    return { ok: true, target: Object.assign({ name }, document) };
}

// The package whose terminal slots a render and the state directory take:
// PKG when it carries its own, else DEFAULTS, the shipped `vgs` package, when
// it does, else null. Each is null or carries `terminal`, the slots
// ThemeLogic.acceptPackage answered or null.
function terminalSource(pkg, defaults) {
    for (const candidate of [pkg, defaults]) {
        if (candidate === null) continue;
        if (candidate.terminal === undefined) throw new Error("theme-render: terminalSource: a package without its terminal verdict");
        if (candidate.terminal !== null) return candidate;
    }
    return null;
}

// The text a `choice` token LEAF whose resolved value is VALUE takes under
// CASES, each `<option>=<text>`, or undefined unless the cases name every
// option of the token exactly once, so a template cannot leave an option
// unwritten: `@{scheme.mode|dark=vs-dark|light=vs}` is VS Code's uiTheme.
function caseText(leaf, cases, value) {
    if (leaf.type !== "choice") return undefined;
    const texts = new Map();
    for (const item of cases) {
        const m = CASE_PATTERN.exec(item);
        if (m === null || !leaf.options.includes(m[1]) || texts.has(m[1])) return undefined;
        texts.set(m[1], m[2]);
    }
    return texts.size === leaf.options.length ? texts.get(value) : undefined;
}

// Templates use the token judge's colour expressions. Resolve only the
// references the expression reads, from this package's already resolved
// values, so mix and contrast retain the judge's types and refusal rules.
function expressionColor(logic, tokens, input, expression) {
    const tree = logic.parseExpression(expression);
    if (tree.error !== undefined || tree.kind !== "call") return undefined;
    const table = { motion: { scale: { ...tokens.motion.scale, value: input.values.motion.scale } } };
    function addReferences(node) {
        if (node.kind === "reference") {
            const leaf = logic.nodeAt(tokens, node.path);
            if (!logic.isLeaf(leaf)) return false;
            const parts = node.path.split(".");
            let group = table;
            for (const part of parts.slice(0, -1)) {
                if (!Object.hasOwn(group, part)) group[part] = {};
                group = group[part];
            }
            group[parts.at(-1)] = { ...leaf, value: logic.valueAt(input.values, node.path) };
        }
        return node.kind !== "call" || node.args.every(addReferences);
    }
    if (!addReferences(tree)) return undefined;
    table.result = { type: "color", value: expression };
    const result = logic.resolve(table, {});
    return result.ok ? result.values.result : undefined;
}

// The text placeholder NAME stands for, or undefined when it names no token
// and no slot. A colour is written by ENCODE; a token with cases as the case
// of its value; any other token as its value.
function placeholderText(logic, tokens, input, name, encode) {
    const [path, ...cases] = name.split(CASE_SEPARATOR);
    if (path.startsWith(TERMINAL_PREFIX)) {
        if (cases.length > 0) return undefined;
        const slot = path.slice(TERMINAL_PREFIX.length);
        return logic.terminalSlotNames().includes(slot) ? encode(input.slots[slot]) : undefined;
    }
    if (path.includes("(") && cases.length === 0) {
        const value = expressionColor(logic, tokens, input, path);
        return value === undefined ? undefined : encode(value);
    }
    const leaf = logic.nodeAt(tokens, path);
    if (!logic.isLeaf(leaf)) return undefined;
    const value = path.split(".").reduce((node, key) => node[key], input.values);
    if (cases.length > 0) return caseText(leaf, cases, value);
    return leaf.type === "color" ? encode(value) : String(value);
}

// Whether BYTES, a package's curated file for the accepted `files` entry
// FILE, stand in for its render. With `curatedKeys` they must be a JSON
// object holding one of those keys, so a package file of another shape at
// that name, such as a vscode.json naming an extension, is not taken.
function curatedTaken(logic, file, bytes) {
    if (!logic.hasOwn(file, CURATED_KEYS_KEY)) return true;
    let document;
    try {
        document = JSON.parse(bytes.toString("utf8"));
    } catch (e) {
        return false;
    }
    return logic.isPlainObject(document) && file.curatedKeys.some(key => logic.hasOwn(document, key));
}

// The owner's tmux formats use ANSI blue for active text and brightblack
// for inactive text. Preserve a readable, distinct brightblack; otherwise
// use the nearest grey to the theme's muted text. The RGB separation floor
// is the smallest nonzero gap in the seven owner-requested main renders,
// measured in tmp/tmux-block-role-probe.json on 2026-10-07. It is a channel
// distance, not a perceptual standard; the pictures judge appearance.
function tmuxSlots(logic, input) {
    const background = logic.parseColor(input.values.color.background);
    const active = logic.parseColor(input.values.color.info);
    const inactive = logic.parseColor(input.slots.color8);
    const separation = color => 255 * Math.hypot(color.r - active.r, color.g - active.g, color.b - active.b);
    const readable = color => color.a === 1 && logic.contrastRatio(color, background) >= logic.READABILITY_FLOOR;
    const distinct = color => separation(color) >= 55.65;
    if (readable(inactive) && distinct(inactive)) return input.slots;
    const muted = logic.parseColor(input.values.color.textMuted);
    const middle = (muted.r + muted.g + muted.b) / 3;
    let chosen = null;
    let distance = Infinity;
    for (let channel = 0; channel <= 255; channel++) {
        const value = channel / 255;
        const grey = { r: value, g: value, b: value, a: 1 };
        if (!readable(grey) || !distinct(grey)) continue;
        const next = Math.abs(value - middle);
        if (next < distance) {
            chosen = grey;
            distance = next;
        }
    }
    if (chosen === null) throw new Error("theme-render: tmux has no readable, distinct inactive colour");
    return { ...input.slots, color8: logic.formatColor(chosen) };
}

// Each stack is ordered from the page upward. One scale applies to every
// layer, so quantization cannot give related fills independent caps. Check
// the encoded bytes the application receives, including text compositing.
// A cell's midpoint is safe from its half-byte rounding boundaries.
function strongestReadableScale(logic, page, text, stacks, cap) {
    const over = (top, below) => ({
        r: top.r * top.a + below.r * (1 - top.a),
        g: top.g * top.a + below.g * (1 - top.a),
        b: top.b * top.a + below.b * (1 - top.a), a: 1
    });
    const cuts = new Set([0, cap]);
    for (const { alpha } of stacks.flat()) {
        for (let byte = 0; byte < 255; byte++) {
            const boundary = (byte + 0.5) / (255 * alpha);
            if (boundary > 0 && boundary < cap) cuts.add(boundary);
        }
    }
    const ordered = [...cuts].sort((a, b) => a - b);
    const candidates = [cap, ...ordered.slice(1).map((upper, index) => (ordered[index] + upper) / 2).reverse()];
    for (const scale of candidates) {
        const readable = stacks.every(stack => {
            let fill = page;
            for (const { colour, alpha } of stack) {
                const tint = logic.parseColor(logic.formatColor({ ...colour, a: alpha * scale }));
                fill = over(tint, fill);
            }
            return logic.contrastRatio(over(text, fill), fill) >= logic.READABILITY_FLOOR;
        });
        if (readable) return scale;
    }
    return null;
}

// The template owns the desired strengths. Adjust only its authored recipe;
// unrelated or broken template values still reach the ordinary renderer and
// its coverage, opacity and contrast checks. Headers and secondary marks
// have separate roles and never enter this common cap.
function editorHighlightTemplate(logic, input, text) {
    let document;
    try {
        document = JSON.parse(text);
    } catch (e) {
        return text;
    }
    if (!logic.isPlainObject(document.colors)) return text;
    const page = logic.parseColor(input.values.color.background);
    const foreground = logic.parseColor(input.values.color.text);
    const success = logic.parseColor(input.values.color.success);
    const danger = logic.parseColor(input.values.color.danger);
    const warning = logic.parseColor(input.values.color.warning);
    const scale = strongestReadableScale(logic, page, foreground, [
        [{ colour: success, alpha: 0.12 }],
        [{ colour: success, alpha: 0.12 }, { colour: success, alpha: 0.24 }],
        [{ colour: danger, alpha: 0.12 }],
        [{ colour: danger, alpha: 0.12 }, { colour: danger, alpha: 0.24 }],
        [{ colour: warning, alpha: 0.12 }]
    ], 1);
    if (scale === null) return null;
    if (scale === 1) return text;
    for (const [key, role, alpha] of [
        ["diffEditor.insertedLineBackground", "success", 0.12],
        ["diffEditorGutter.insertedLineBackground", "success", 0.12],
        ["diffEditor.removedLineBackground", "danger", 0.12],
        ["diffEditorGutter.removedLineBackground", "danger", 0.12],
        ["merge.currentContentBackground", "success", 0.12],
        ["merge.incomingContentBackground", "danger", 0.12],
        ["merge.commonContentBackground", "warning", 0.12],
        ["mergeEditor.change.background", "success", 0.12],
        ["mergeEditor.changeBase.background", "danger", 0.12],
        ["mergeEditor.conflict.input1.background", "success", 0.12],
        ["mergeEditor.conflict.input2.background", "danger", 0.12],
        ["diffEditor.insertedTextBackground", "success", 0.24],
        ["diffEditor.removedTextBackground", "danger", 0.24],
        ["mergeEditor.change.word.background", "success", 0.24],
        ["mergeEditor.changeBase.word.background", "danger", 0.24]
    ]) {
        const desired = "#@{alpha({color." + role + "}, " + alpha + ")}";
        if (document.colors[key] === desired)
            document.colors[key] = "#@{alpha({color." + role + "}, " + alpha * scale + ")}";
    }
    return JSON.stringify(document, null, 2) + "\n";
}

// Render every file of an accepted TARGET. TEMPLATES maps each template name
// the target names to its text. INPUT carries the package's resolved token
// `values`, the terminal `slots` terminalSource chose, `curated`, a Map
// from destination to the bytes of the package's `targets/<destination>`,
// and `installed`, true for a package under the configuration home's
// themes/ and false for a shipped one. Every template is rendered, so a
// placeholder naming no token or slot refuses the target even where a
// curated file stands in. On a `runsCode` target an installed package's
// curated file is dropped, never judged, and its destination listed in
// `dropped`; any other curated file curatedTaken admits is taken verbatim.
// An extension target renders its `version` destination first and writes
// its extensionVersion wherever another file names `@{extension.version}`;
// any other file naming it refuses the target.
// Answers { ok: true, files: [{ destination, bytes, curated }], dropped,
// version } in the target's order, `version` undefined but on an extension
// target, or one refusal.
function renderTarget(logic, tokens, target, templates, input) {
    if (input.slots === null || typeof input.slots !== "object")
        throw new Error("theme-render: renderTarget: target " + target.name + " rendered without terminal slots");
    if (typeof input.installed !== "boolean")
        throw new Error("theme-render: renderTarget: target " + target.name + " rendered without the package's source");
    if (target.name === "tmux") input = { ...input, slots: tmuxSlots(logic, input) };
    const encode = hex => ENCODERS[target.encoder](hex, input.values.color.background);
    const rendered = new Map();
    const dropped = [];
    const versionFrom = target.wiring !== null && wiringForm(target.wiring) === "extension" ? target.wiring.version : undefined;
    const order = target.files.filter(file => file.destination === versionFrom).concat(target.files.filter(file => file.destination !== versionFrom));
    let version;
    for (const file of order) {
        let text = templates.get(file.template);
        if (typeof text !== "string")
            throw new Error("theme-render: renderTarget: template " + file.template + " of target " + target.name + " was not read");
        if (target.name === "vscode" && file.destination === "vscode.json") {
            text = editorHighlightTemplate(logic, input, text);
            if (text === null) return refused("readability", "template=" + file.template);
        }
        const template = parseTemplate(text);
        if (!template.ok) return refused("placeholder", "template=" + file.template + " unterminated=" + template.at);
        let out = "";
        for (const part of template.parts) {
            if (typeof part === "string") {
                out += part;
                continue;
            }
            const value = part.name === VERSION_PLACEHOLDER ? version : placeholderText(logic, tokens, input, part.name, encode);
            if (value === undefined) return refused("placeholder", "template=" + file.template + " placeholder=" + JSON.stringify(part.name));
            out += value;
        }
        const present = input.curated.has(file.destination);
        const drop = present && input.installed && target.runsCode;
        if (drop) dropped.push(file.destination);
        const curated = present && !drop && curatedTaken(logic, file, input.curated.get(file.destination));
        const bytes = curated ? input.curated.get(file.destination) : Buffer.from(out, "utf8");
        if (file.destination === versionFrom) version = extensionVersion(bytes);
        rendered.set(file.destination, { destination: file.destination, bytes, curated });
    }
    const destinations = target.files.map(file => file.destination);
    return { ok: true, files: destinations.map(destination => rendered.get(destination)), dropped: destinations.filter(destination => dropped.includes(destination)), version };
}

// The version an extension whose `version` file holds BYTES carries:
// `1.0.<n>`, n the first 32 bits of the bytes' sha256, so new bytes make a
// new version and the editors replace the theme they cached for the old one.
function extensionVersion(bytes) {
    return "1.0." + parseInt(crypto.createHash("sha256").update(bytes).digest("hex").slice(0, 8), 16);
}

// The include line an accepted TARGET keeps in its application's
// configuration file, with `@{state}` written as STATE, the state
// directory's `theme/` path. acceptTarget admits no other placeholder.
function wiringLine(target, state) {
    const form = wiringForm(target.wiring);
    if (form !== "include") throw new Error("theme-render: wiringLine: target " + target.name + " has wiring form " + form);
    return withValues(target.wiring.line, { [STATE_PLACEHOLDER]: state }, "wiringLine: the wiring line of target " + target.name);
}

// The argv an accepted TARGET's reload hook runs, with `@{state}` written as
// STATE, the state directory's `theme/` path, `@{target}` as DIR, the
// target's own directory, and `@{wiring}` written as WIRING, the file its
// include line is kept in, in each argument.
function reloadCommand(target, state, dir, wiring) {
    if (target.reload === null) throw new Error("theme-render: reloadCommand: target " + target.name + " has no reload");
    const values = { [STATE_PLACEHOLDER]: state, [TARGET_PLACEHOLDER]: dir };
    if (wiring !== undefined) values[WIRING_PLACEHOLDER] = wiring;
    return target.reload.command.map(arg => withValues(arg, values, "reloadCommand: a reload argument of target " + target.name));
}

// The value an accepted TARGET's `select` names its theme with, `@{state}`
// written as STATE, the state directory's `theme/` path.
function selectValue(target, state) {
    if (target.select === undefined) throw new Error("theme-render: selectValue: target " + target.name + " has no select");
    return withValues(target.select.value, { [STATE_PLACEHOLDER]: state }, "selectValue: the selection value of target " + target.name);
}

// The key paths an accepted TARGET's `select` sets, in its order: its one
// key, or each of its list.
function selectKeys(target) {
    if (target.select === undefined) throw new Error("theme-render: selectKeys: target " + target.name + " has no select");
    return typeof target.select.key[0] === "string" ? [target.select.key] : target.select.key;
}

// Whether an accepted TARGET's hook is due on every apply that lands it,
// not only on changed bytes or a pending reload.
function reloadAlways(target) {
    return target.reload !== null && target.reload.always === true;
}

// The profile directories a Mozilla profiles.ini holding TEXT lists, in its
// order: each `[Profile<N>]` section's `Path`, as { path, relative }.
// `relative` is true when the section's `IsRelative` is `1`, and `path` is
// then under the ini's own directory; otherwise `path` is absolute. A
// section with no `Path`, or one not relative whose `Path` does not start
// with `/`, names no directory the browser opens and is left out. Keys and
// values are trimmed, so a CRLF file reads as an LF one.
function profileDirs(text) {
    const sections = [];
    let current = null;
    for (const raw of text.split("\n")) {
        const line = raw.trim();
        if (line.startsWith("[") && line.endsWith("]")) {
            current = PROFILE_SECTION.test(line.slice(1, -1).trim()) ? new Map() : null;
            if (current !== null) sections.push(current);
            continue;
        }
        const at = line.indexOf("=");
        if (current !== null && at !== -1) current.set(line.slice(0, at).trim(), line.slice(at + 1).trim());
    }
    return sections.map(keys => ({ path: keys.get("Path") || "", relative: keys.get("IsRelative") === "1" }))
        .filter(dir => dir.relative ? dir.path !== "" : dir.path.startsWith("/"));
}

// The vault directories an Obsidian registry, obsidian.json, holding TEXT
// lists, in its order and each once: every `vaults.<id>.path` that is
// absolute. A registry without `vaults` lists none. Null for TEXT that is
// not a JSON object, or whose `vaults` is no object, since no vault it
// names can then be known.
function vaultDirs(logic, text) {
    let registry;
    try {
        registry = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!logic.isPlainObject(registry)) return null;
    if (!logic.hasOwn(registry, "vaults")) return [];
    if (!logic.isPlainObject(registry.vaults)) return null;
    const dirs = [];
    for (const vault of Object.values(registry.vaults)) {
        const dir = logic.isPlainObject(vault) ? vault.path : undefined;
        if (typeof dir === "string" && dir.startsWith("/") && !dirs.includes(dir)) dirs.push(dir);
    }
    return dirs;
}

// The folder extension ID at VERSION is kept in, in an editor's extensions
// directory, as the editors name an installed extension's folder.
function extensionFolder(id, version) {
    return id + "-" + version;
}

// Whether NAME is a folder extensionFolder gives extension ID at any
// version: what an apply removes once another version is registered.
function isExtensionFolder(name, id) {
    return name.startsWith(id + "-") && /^[0-9]+\.[0-9]+\.[0-9]+$/.test(name.slice(id.length + 1));
}

// TEXT parsed as JSON when it is a value CHECK admits, else undefined.
function parsedJson(text, check) {
    try {
        const value = JSON.parse(text);
        return check(value) ? value : undefined;
    } catch (e) {
        return undefined;
    }
}

function registeredId(logic, entry) {
    return logic.isPlainObject(entry) && logic.isPlainObject(entry.identifier) && typeof entry.identifier.id === "string"
        ? entry.identifier.id.toLowerCase() : null;
}

// The text an editor's extensions.json holding TEXT, undefined when it is
// absent, takes so that it registers extension ID at VERSION in its folder
// under DIR, the extensions directory, and no other version of it: null when
// it already does, or the refusal `registry-refused` for a file that is no
// JSON array. An entry the editor already holds for that folder is kept as
// it is, so metadata the editor added to it stays.
function registeredText(logic, text, id, version, dir) {
    const entries = text === undefined ? [] : parsedJson(text, Array.isArray);
    if (entries === undefined) return refused("registry-refused", "file=extensions.json");
    const folder = extensionFolder(id, version);
    const own = entries.filter(entry => registeredId(logic, entry) === id);
    if (own.length === 1 && own[0].version === version && own[0].relativeLocation === folder) return null;
    return JSON.stringify(entries.filter(entry => registeredId(logic, entry) !== id).concat({
        identifier: { id }, version, location: { $mid: 1, path: dir + "/" + folder, scheme: "file" }, relativeLocation: folder, metadata: { source: "vsix" }
    }));
}

// The text an editor's extensions.json holding TEXT takes once it registers
// no version of extension ID: null when it registers none or is absent, or
// the refusal `registry-refused` for a file that is no JSON array.
function unregisteredText(logic, text, id) {
    if (text === undefined) return null;
    const entries = parsedJson(text, Array.isArray);
    if (entries === undefined) return refused("registry-refused", "file=extensions.json");
    const kept = entries.filter(entry => registeredId(logic, entry) !== id);
    return kept.length === entries.length ? null : JSON.stringify(kept);
}

// The text an editor's `.obsolete` holding TEXT takes once it marks no
// folder of extension ID obsolete, since a marked folder is one the editor
// skips and deletes: null when it marks none or is absent, or the refusal
// `registry-refused` for a file that is no JSON object.
function unobsoletedText(logic, text, id) {
    if (text === undefined) return null;
    const marks = parsedJson(text, logic.isPlainObject);
    if (marks === undefined) return refused("registry-refused", "file=.obsolete");
    const kept = Object.keys(marks).filter(name => !isExtensionFolder(name, id));
    return kept.length === Object.keys(marks).length ? null : JSON.stringify(Object.fromEntries(kept.map(name => [name, marks[name]])));
}

// Whether the line TEXT is the header of SECTION. bin/lib/theme-select.js
// takes the same judgement for a TOML table.
function isSectionHeader(text, section) {
    const m = SECTION_HEADER.exec(text);
    return m !== null && m[1] === section;
}

// Whether the line TEXT opens a section, a TOML array of tables included.
function opensSection(text) {
    return ANY_HEADER.test(text);
}

// The key a `key = value` line TEXT assigns, trimmed, or null for a line
// that assigns none.
function assignedKey(text) {
    const at = text.indexOf("=");
    return at === -1 ? null : text.slice(0, at).trim();
}

// The one-line TOML array of strings the `key = [...]` line TEXT assigns:
// `close`, the offset of its `]`, and each element's { start, end } offsets,
// quotes included. Null for any other value: an array that goes on past
// this line, an element that is no basic or literal string, and anything
// after the `]` but blanks and a `#` comment. A multi-line string's `"""`
// reads as an empty string followed by a quote, and so as no array.
function stringArray(text) {
    let at = text.indexOf("=") + 1;
    const blanks = () => { while (text[at] === " " || text[at] === "\t") at++; };
    if (at === 0) return null;
    blanks();
    if (text[at] !== "[") return null;
    at++;
    const elements = [];
    for (;;) {
        blanks();
        if (text[at] === "]") break;
        const quote = text[at];
        if (quote !== "\"" && quote !== "'") return null;
        const start = at++;
        while (at < text.length && text[at] !== quote) at += quote === "\"" && text[at] === "\\" ? 2 : 1;
        elements.push({ start, end: ++at });
        blanks();
        if (text[at] === ",") at++;
        else if (text[at] !== "]") return null;
    }
    return /^\s*(?:#.*)?$/.test(text.slice(at + 1)) ? { close: at, elements } : null;
}

// The text of the one element LINE's one-line string array holds, quotes
// included, or null for a line that assigns no such array.
function soleElement(line) {
    const array = stringArray(line);
    return array === null || array.elements.length !== 1 ? null : line.slice(array.elements[0].start, array.elements[0].end);
}

// The index of the first header of SECTION among LINES, or -1.
function sectionAt(lines, section) {
    return lines.findIndex(existing => isSectionHeader(existing, section));
}

// The index of the line that ends the section whose header is line AT of
// LINES: the next header of any kind, or the line count.
function sectionEnd(lines, at) {
    const end = lines.findIndex((existing, index) => index > at && ANY_HEADER.test(existing));
    return end === -1 ? lines.length : end;
}

// The text a configuration file holding TEXT takes so that LINE is one of its
// lines, or null when it already is one; the rest of the text is kept byte
// for byte. With SECTION undefined the line goes first, ahead of every
// section, so an INI file reads it in its main section and the file's own
// settings after it override the included theme, and an absent file (TEXT
// undefined) becomes the line alone. With a SECTION the line goes right
// after the first header of that section, or, with none, the header and the
// line are added at the end, so a TOML file never declares the table twice.
// A section that already assigns the line's key on one line of a one-line
// string array, where LINE assigns a one-line array of one string, takes
// that string first in its array instead, the rest of that line kept byte
// for byte, or is left when the array already holds it. Any other assignment
// of the key in the section, or a file that defines the section by dotted
// keys ahead of every header, would then hold a key twice, which TOML
// refuses: that answers the refusal
// { ok: false, reason: "wiring-conflict", detail } and the file is left.
function wiredText(text, line, section) {
    const lines = text === undefined ? [] : text.split("\n");
    if (lines.includes(line)) return null;
    if (section === undefined) return line + "\n" + (text === undefined ? "" : text);
    const key = assignedKey(line);
    const at = sectionAt(lines, section);
    if (at !== -1) {
        const assigning = [];
        for (let index = at + 1, end = sectionEnd(lines, at); index < end; index++)
            if (key !== null && assignedKey(lines[index]) === key) assigning.push(index);
        if (assigning.length === 0) return lines.slice(0, at + 1).concat(line, lines.slice(at + 1)).join("\n");
        const element = soleElement(line);
        const own = lines[assigning[0]];
        const array = assigning.length === 1 && element !== null ? stringArray(own) : null;
        if (array === null) return refused("wiring-conflict", "section=" + section + " key=" + key);
        if (array.elements.some(held => own.slice(held.start, held.end) === element)) return null;
        const into = array.elements.length === 0 ? array.close : array.elements[0].start;
        lines[assigning[0]] = own.slice(0, into) + element + (array.elements.length === 0 ? "" : ", ") + own.slice(into);
        return lines.join("\n");
    }
    const first = lines.findIndex(existing => ANY_HEADER.test(existing));
    const root = lines.slice(0, first === -1 ? lines.length : first);
    if (root.some(existing => { const name = assignedKey(existing); return name === section || (name !== null && name.startsWith(section + ".")); }))
        return refused("wiring-conflict", "section=" + section + " key=" + section);
    const before = text === undefined ? "" : text;
    return before + (before === "" || before.endsWith("\n") ? "" : "\n") + "[" + section + "]\n" + line + "\n";
}

// The text a configuration file holding TEXT takes once LINE is none of its
// lines, or null when it is none already or the file is absent (TEXT
// undefined). Every whole line equal to LINE goes, with its line break; with
// a SECTION, every copy of the one string LINE's one-line array holds goes
// from the one-line string array that assigns LINE's key under the first
// header of that section, with the separator after it, or the one before it
// for the last of several. The rest of the text is kept byte for byte, so
// this undoes wiredText but for a section header wiredText added, which
// stays.
function unwiredText(text, line, section) {
    if (text === undefined) return null;
    const lines = text.split("\n").filter(existing => existing !== line);
    const at = section === undefined ? -1 : sectionAt(lines, section);
    const key = assignedKey(line);
    const element = soleElement(line);
    for (let index = at + 1, end = at === -1 ? 0 : sectionEnd(lines, at); index < end; index++) {
        if (key === null || element === null || assignedKey(lines[index]) !== key) continue;
        for (let array = stringArray(lines[index]); array !== null; array = stringArray(lines[index])) {
            const own = lines[index];
            const k = array.elements.findIndex(held => own.slice(held.start, held.end) === element);
            if (k === -1) break;
            const [from, to] = array.elements.length === 1 ? [array.elements[0].start, array.close]
                : k < array.elements.length - 1 ? [array.elements[k].start, array.elements[k + 1].start]
                : [array.elements[k - 1].end, array.elements[k].end];
            lines[index] = own.slice(0, from) + own.slice(to);
        }
    }
    const next = lines.join("\n");
    return next === text ? null : next;
}

module.exports = { TARGET_FILE, EDITOR_BASE, extensionVersion, extensionFolder, isExtensionFolder, registeredText, unregisteredText, unobsoletedText, acceptTarget, placeholderNames, detected, setupDone, curatedTaken, renderTarget, terminalSource, refusalLine, wiringForm, wiringLine, entryItems, profileDirs, vaultDirs, reloadNamesWiring, reloadCommand, reloadAlways, selectKeys, selectValue, wiredText, unwiredText, isSectionHeader, opensSection, assignedKey };
