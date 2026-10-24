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
// of one harness, named by its id in shell/Commons/AccountDirectories.js,
// or each existing configuration directory named by { base, prefix }.
// Its entry wiring and selection are relative to each account directory.
// The caller, which reads the account rule, judges that the id names a
// harness: readTarget in bin/vgshell-theme-judge.
const ACCOUNTS_KEY = "accounts";
// The one optional top-level key: the theme selection apply keeps in the
// application's own settings file, `{ base, file, format, key, value }`,
// beside any wiring form. `key` is one key path, or a list of two or more
// key paths that each take the value. The named terminal apps use
// `{ base, file, format, values }` for their native colour spans; `file`
// may name several existing configurations. bin/lib/theme-select.js owns
// both edits. Optional `create` permits a detected app's absent settings
// file. Base `vault` uses the registered roots of the entry's vault wiring.
// KDE's `source` names the rendered colour-scheme destination whose native
// colour groups also belong in kdeglobals.
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
const COLOR_SELECT_KEYS = ["base", "file", "format", "values"];
const COLOR_SELECT_FORMATS = ["starship", "yazi", "bat", "fastfetch", "television"];
// `jsonc` is JSON with comments and trailing commas, as VS Code-family
// editors read their settings. Zed keeps its native mode object or string.
// Posh edits a literal init command's config argument. The line-exact `toml` edit also handles
// btop.conf's quoted root assignment without parsing unrelated settings.
const SELECT_FORMATS = ["json", "jsonc", "toml", "yaml", "qtct", "json-array", "userjs", "zed", "posh", "kcolorscheme"];
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
// the file is relative to, the fallback files under HOME tried when the
// configuration-home file is absent, and whether the line goes last. An
// entry wiring keeps entries to the target's files in the application's
// theme or extension directory and edits no file; its optional key is the
// Obsidian vault registry whose vaults the directory is relative to.
// Exactly one of `links` or `copies` tells which
// entry kind it writes. An extension wiring, an editors target's only form,
// keeps one generated extension in each wired editor's extensions directory:
// `extension` is the `<publisher>.<name>` id its id starts with, `stamp` the
// destination whose final bytes make the rest of its id, and `copies` its
// files, each a copy of one of the target's files. A null wiring keeps nothing: the target's hook
// asserts the setting that makes its application read the files.
const WIRING_KEYS = ["file", "line", "create"];
const INCLUDE_OPTIONAL_KEYS = ["section", "profiles", "fallbacks", "last", "init"];
const ENTRY_BASE_KEYS = ["base", "dir", "owned"];
const ENTRY_ITEM_KEYS = ["links", "copies"];
const ENTRY_OPTIONAL_KEYS = ["vaults"];
const EXTENSION_KEYS = ["extension", "stamp", "copies"];
// An extension id, `<publisher>.<name>`, as the editors' own manifests
// spell one, in lower case so it is the folder name the editors compare.
const EXTENSION_ID_PATTERN = /^[a-z0-9][a-z0-9-]*\.[a-z0-9][a-z0-9-]*$/;
// The placeholders a file of an extension target writes its stamp and its
// version with.
const STAMP_PLACEHOLDER = "extension.stamp";
const VERSION_PLACEHOLDER = "extension.version";
// The version every generated extension carries. Its id changes with its
// theme's bytes instead: a running editor window adds no extension whose id
// it already holds, so only a new id reaches it without a reload.
const EXTENSION_VERSION = "1.0.0";
// The directories an entry's `dir` and a selection's `file` are relative
// to: the user's configuration home, ${XDG_CONFIG_HOME:-~/.config}, the home
// directory, or the user's cache home, ${XDG_CACHE_HOME:-~/.cache}.
const ENTRY_BASES = ["config", "home", "cache"];
const ACCOUNT_BASE = "account";
const RELOAD_KEYS = ["command", "timeoutMs"];
// The optional reload keys, each a boolean. `always` true makes the hook due
// on every apply that lands the target, for a hook that asserts a setting no
// file carries. `last` true runs the hook after every due hook without it,
// for a setting an application lets a later toolkit change override.
const RELOAD_OPTIONAL_KEYS = ["always", "last"];

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

// The placeholder for the user's terminal font, the `terminalFont` member
// of shell.json `appearance`, which no token holds. A line that names it is
// written only while the user set one, so a render without a font holds no
// font line. Its one case, `|set=<text>`, writes <text> in place of the
// name, for a line that belongs with the font's line.
const TERMINAL_FONT = "appearance.terminalFont";
const TERMINAL_FONT_SET = "set";

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

// Each encoder writes one resolved colour. tmux writes a terminal slot name.
const ENCODERS = {
    hex6: (hex, background) => hex6(hex, background),
    tmux: value => value,
    hex8: hex => hex.slice(1, 9),
    rgb: (hex, background) => {
        const rgb = hex6(hex, background);
        return [0, 2, 4].map(at => channel(rgb, at)).join(", ");
    },
    hsl: (hex, background) => hsl(hex6(hex, background)),
    "hsl-h": (hex, background) => hsl(hex6(hex, background)).split(" ")[0],
    "hsl-s": (hex, background) => hsl(hex6(hex, background)).split(" ")[1],
    "hsl-l": (hex, background) => hsl(hex6(hex, background)).split(" ")[2],
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

// Claude Desktop Extra reads CSS HSL components without the hsl() wrapper.
// Keep fractional components so converting back retains the RGB bytes.
function hsl(rgb) {
    const [r, g, b] = [0, 2, 4].map(at => parseInt(rgb.slice(at, at + 2), 16) / 255);
    const high = Math.max(r, g, b), low = Math.min(r, g, b);
    const delta = high - low, light = (high + low) / 2;
    let hue = 0;
    if (delta !== 0) {
        hue = high === r ? (g - b) / delta : high === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
        hue = (hue * 60 + 360) % 360;
    }
    const saturation = delta === 0 ? 0 : delta / (1 - Math.abs(2 * light - 1));
    const decimal = value => String(Number(value.toFixed(4)));
    return decimal(hue) + " " + decimal(saturation * 100) + "% " + decimal(light * 100) + "%";
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
// the configuration-home file is absent. `last`, when present, is a boolean;
// true puts the line after every line of the file, which a section placement
// cannot do, so `last` with `section` is refused.
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
    if (logic.hasOwn(wiring, "last") && (typeof wiring.last !== "boolean" || logic.hasOwn(wiring, "section"))) return "key=wiring.last";
    if (logic.hasOwn(wiring, "init") && (wiring.init !== "emacs" || ["profiles", "fallbacks", "section"].some(key => logic.hasOwn(wiring, key)))) return "key=wiring.init";
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
// `links` or `copies` maps each entry's relative path in `dir` to one of
// DESTINATIONS, the target's own files. A destination list follows the
// directory order when configurations retain different customizations.
function entryBaseAccepted(base, hasAccounts) {
    return ENTRY_BASES.includes(base) || (hasAccounts && base === ACCOUNT_BASE);
}

function entryError(logic, wiring, destinations, hasAccounts) {
    const itemKey = entryItemKey(wiring);
    if (itemKey === "" || !ENTRY_BASE_KEYS.every(key => logic.hasOwn(wiring, key)) ||
        !Object.keys(wiring).every(key => ENTRY_BASE_KEYS.includes(key) || ENTRY_ITEM_KEYS.includes(key) || ENTRY_OPTIONAL_KEYS.includes(key))) return "key=wiring";
    if (!entryBaseAccepted(wiring.base, hasAccounts)) return "key=wiring.base";
    if (Array.isArray(wiring.dir)) {
        if (hasAccounts || logic.hasOwn(wiring, "vaults") || wiring.dir.length === 0 || !wiring.dir.every(isRelativePath) || new Set(wiring.dir).size !== wiring.dir.length) return "key=wiring.dir";
    } else {
        if (!(hasAccounts && wiring.dir === ".") && !isRelativePath(wiring.dir)) return "key=wiring.dir";
    }
    if (logic.hasOwn(wiring, "vaults") && !isRelativePath(wiring.vaults)) return "key=wiring.vaults";
    if (typeof wiring.owned !== "boolean") return "key=wiring.owned";
    if (!logic.isPlainObject(wiring[itemKey]) || Object.keys(wiring[itemKey]).length === 0) return "key=wiring." + itemKey;
    for (const [name, destination] of Object.entries(wiring[itemKey])) {
        if (!isRelativePath(name)) return "key=wiring." + itemKey + "." + name;
        const listed = Array.isArray(destination) ? destination : [destination];
        if (Array.isArray(destination) && (!Array.isArray(wiring.dir) || listed.length !== wiring.dir.length)) return "key=wiring." + itemKey + "." + name;
        if (!listed.every(file => destinations.has(file))) return "key=wiring." + itemKey + "." + name;
    }
    return "";
}

// The first defect of an extension `wiring`, or "": the id its ids start
// with, the destination its stamp is made from, and its copies, each a
// package file name mapped to one of DESTINATIONS. The stamp destination
// itself cannot name the stamp, which renderTarget refuses.
function extensionError(logic, wiring, destinations) {
    if (!hasExactKeys(logic, wiring, EXTENSION_KEYS)) return "key=wiring";
    if (typeof wiring.extension !== "string" || !EXTENSION_ID_PATTERN.test(wiring.extension)) return "key=wiring.extension";
    if (!destinations.has(wiring.stamp)) return "key=wiring.stamp";
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
// symlinks to the destination; copies are atomic. INDEX selects a directory's
// destination when its declaration supplies a list.
function entryItems(target, live, index = 0) {
    const form = wiringForm(target.wiring);
    if (form !== "entry") throw new Error("theme-render: entryItems: target " + target.name + " has wiring form " + form);
    const itemKey = entryItemKey(target.wiring);
    const kind = itemKey === "links" ? "link" : "copy";
    return Object.entries(target.wiring[itemKey]).map(([name, declared]) => {
        const destination = Array.isArray(declared) ? declared[index] : declared;
        return { kind, name, destination, to: live + "/" + destination };
    });
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
// present, a boolean `always` and a boolean `last`.
function reloadError(logic, reload, target) {
    if (reload === null) return "";
    if (!logic.isPlainObject(reload) || !RELOAD_KEYS.every(key => logic.hasOwn(reload, key)) ||
        !Object.keys(reload).every(key => RELOAD_KEYS.includes(key) || RELOAD_OPTIONAL_KEYS.includes(key))) return "key=reload";
    if (!Array.isArray(reload.command) || reload.command.length === 0 || !reload.command.every(isLine)) return "key=reload.command";
    const names = reload.command.map(placeholderNames);
    const allowed = reloadPlaceholders(logic, target);
    if (names.some(list => list === null || list.some(name => !allowed.includes(name)))) return "key=reload.command";
    if (!Number.isInteger(reload.timeoutMs) || reload.timeoutMs <= 0) return "key=reload.timeoutMs";
    const flag = RELOAD_OPTIONAL_KEYS.find(key => logic.hasOwn(reload, key) && typeof reload[key] !== "boolean");
    if (flag !== undefined) return "key=reload." + flag;
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
    return format === "json" || format === "jsonc" || format === "json-array" || format === "userjs";
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
// lies on another's path, and one line of value whose only placeholders are
// `@{state}` and, on an editors target, `@{extension.stamp}`.
function selectError(logic, select, hasAccounts, hasEditors) {
    if (logic.isPlainObject(select) && COLOR_SELECT_FORMATS.includes(select.format)) {
        if (!hasExactKeys(logic, select, COLOR_SELECT_KEYS)) return "key=select";
        if (!ENTRY_BASES.includes(select.base)) return "key=select.base";
        const files = Array.isArray(select.file) ? select.file : [select.file];
        if (files.length === 0 || !files.every(isRelativePath) || new Set(files).size !== files.length) return "key=select.file";
        if (!logic.isPlainObject(select.values)) return "key=select.values";
        for (const [key, value] of Object.entries(select.values)) {
            if (!JSON_KEY_PATTERN.test(key) || !isLine(value) || CONTROL_CHARACTER.test(value) || placeholderNames(value) === null) return "key=select.values";
        }
        const required = select.format === "yazi" ? ["fg", "bg"] : select.format === "bat" ? ["theme"] : [];
        if (required.some(key => !logic.hasOwn(select.values, key))) return "key=select.values";
        if (select.format === "bat" && (Object.keys(select.values).length !== 1 || select.values.theme !== "vgs")) return "key=select.values";
        return "";
    }
    if (!logic.isPlainObject(select) || SELECT_KEYS.some(key => !logic.hasOwn(select, key)) ||
        Object.keys(select).some(key => ![...SELECT_KEYS, "create", "source"].includes(key))) return "key=select";
    if (logic.hasOwn(select, "create") && typeof select.create !== "boolean") return "key=select.create";
    if (select.format === "kcolorscheme" ? !isRelativePath(select.source) : logic.hasOwn(select, "source")) return "key=select.source";
    if (!entryBaseAccepted(select.base, hasAccounts) && !(hasEditors && select.base === EDITOR_BASE) && select.base !== "vault") return "key=select.base";
    if (!(select.format === "posh" && Array.isArray(select.file) && select.file.length > 0
        ? select.file.every(isRelativePath) : isRelativePath(select.file))) return "key=select.file";
    if (!SELECT_FORMATS.includes(select.format)) return "key=select.format";
    if (!isKeyPath(select.format, select.key)) {
        const keys = select.key;
        if (!Array.isArray(keys) || keys.length < 2 || !keys.every(key => isKeyPath(select.format, key))) return "key=select.key";
        if (keys.some((a, i) => keys.some((b, j) => i !== j && isKeyPrefix(a, b)))) return "key=select.key";
    }
    if (!isLine(select.value) || CONTROL_CHARACTER.test(select.value)) return "key=select.value";
    const names = placeholderNames(select.value);
    if (names === null || names.some(name => name !== STATE_PLACEHOLDER && !(hasEditors && name === STAMP_PLACEHOLDER))) return "key=select.value";
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
    if (!Array.isArray(document.files) || document.files.length === 0 &&
        !(document.wiring === null && ["starship", "fastfetch"].includes(document.select?.format))) return refused("target-schema", "key=files");
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
    if (hasAccounts && !logic.isPackageName(document.accounts) &&
        !(hasExactKeys(logic, document.accounts, ["base", "prefix"]) && document.accounts.base === "config" &&
            typeof document.accounts.prefix === "string" && DIR_SEGMENT_PATTERN.test(document.accounts.prefix))) return refused("target-schema", "key=accounts");
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
    if (document.select?.format === "qtct" && (JSON.stringify(document.select.key) !== '["Appearance","color_scheme_path"]'))
        return refused("target-schema", "key=select.key");
    if (document.select?.format === "kcolorscheme" && (!destinations.has(document.select.source) ||
        JSON.stringify(document.select.key) !== '["General","ColorScheme"]')) return refused("target-schema", "key=select.source");
    if (document.select?.format === "userjs" && (document.wiring?.profiles === undefined || document.select.base !== "home" ||
        document.select.file !== "user.js" || JSON.stringify(document.select.key) !== '["toolkit.legacyUserProfileCustomizations.stylesheets"]' || document.select.value !== "true"))
        return refused("target-schema", "key=select");
    if (document.select?.base === "vault" && document.wiring?.vaults === undefined) return refused("target-schema", "key=select.base");
    if (document.select?.format === "posh" && (form !== "entry" || !isRelativePath(document.select.value))) return refused("target-schema", "key=select.value");
    if (document.select?.format === "yazi") {
        const files = Array.isArray(document.select.file) ? document.select.file : [document.select.file];
        const dirs = Array.isArray(document.wiring?.dir) ? document.wiring.dir : [document.wiring?.dir];
        const flavor = document.wiring?.links?.["flavor.toml"];
        const outputs = Array.isArray(flavor) ? flavor : [flavor];
        if (form !== "entry" || document.wiring.links?.["flavor.toml"] === undefined || dirs.length !== files.length ||
            document.wiring.base !== document.select.base || new Set(outputs).size !== files.length) return refused("target-schema", "key=select.file");
    }
    if (document.select?.format === "bat" && !document.detect.includes("bat")) return refused("target-schema", "key=detect");
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

// The user's terminal font INPUT carries, or null for none.
function terminalFont(input) {
    return typeof input.terminalFont === "string" ? input.terminalFont : null;
}

// The text placeholder NAME stands for, or undefined when it names no token
// and no slot. A colour is written by ENCODE; a token with cases as the case
// of its value; any other token as its value.
function placeholderText(logic, tokens, input, name, encode) {
    let [path, ...cases] = name.split(CASE_SEPARATOR);
    const format = cases.length === 1 && cases[0].startsWith("format=") ? cases[0].slice("format=".length) : null;
    if (format !== null) {
        if (!Object.hasOwn(ENCODERS, format)) return undefined;
        encode = hex => ENCODERS[format](hex, input.values.color.background, logic, input);
        cases = [];
    }
    if (input.targetColors && Object.hasOwn(input.targetColors, path) && cases.length === 0) return encode(input.targetColors[path]);
    if (path.startsWith(TERMINAL_PREFIX)) {
        if (cases.length > 0) return undefined;
        const slot = path.slice(TERMINAL_PREFIX.length);
        return logic.terminalSlotNames().includes(slot) ? encode(input.slots[slot]) : undefined;
    }
    if (path === TERMINAL_FONT) {
        if (format !== null) return undefined;
        if (cases.length === 0) return terminalFont(input) || "";
        const set = cases.length === 1 ? CASE_PATTERN.exec(cases[0]) : null;
        return set !== null && set[1] === TERMINAL_FONT_SET ? set[2] : undefined;
    }
    if (path.includes("(") && cases.length === 0) {
        const value = expressionColor(logic, tokens, input, path);
        return value === undefined ? undefined : encode(value);
    }
    const leaf = logic.nodeAt(tokens, path);
    if (!logic.isLeaf(leaf)) return undefined;
    if (format !== null && leaf.type !== "color") return undefined;
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

// sRGB to CIELAB under D65. Keep colour difference separate from WCAG
// luminance: its XYZ matrix and transfer breakpoint belong to the metric.
function colorLab(color) {
    const linear = value => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    const r = linear(color.r), g = linear(color.g), b = linear(color.b);
    const f = value => value > 0.008856 ? Math.cbrt(value) : 7.787 * value + 16 / 116;
    const x = f((0.412424 * r + 0.357579 * g + 0.180464 * b) / 0.95047);
    const y = f(0.212656 * r + 0.715158 * g + 0.0721856 * b);
    const z = f((0.0193324 * r + 0.119193 * g + 0.950444 * b) / 1.08883);
    return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}

// CIEDE2000, unit weighting factors, Sharma et al. equations 2-22.
// https://www.hajim.rochester.edu/ece/sites/gsharma/ciede2000/ciede2000noteCRNA.pdf
function colorDeltaE([l1, a1, b1], [l2, a2, b2]) {
    const radians = degrees => degrees * Math.PI / 180;
    const cos = degrees => Math.cos(radians(degrees));
    const sin = degrees => Math.sin(radians(degrees));
    const chroma = (a, b) => Math.hypot(a, b);
    const initialMean = (chroma(a1, b1) + chroma(a2, b2)) / 2;
    const compensation = 0.5 * (1 - Math.sqrt(initialMean ** 7 / (initialMean ** 7 + 25 ** 7)));
    const adjustedA1 = (1 + compensation) * a1, adjustedA2 = (1 + compensation) * a2;
    const c1 = chroma(adjustedA1, b1), c2 = chroma(adjustedA2, b2);
    const hue = (a, b) => a === 0 && b === 0 ? 0 : (Math.atan2(b, a) * 180 / Math.PI + 360) % 360;
    const h1 = hue(adjustedA1, b1), h2 = hue(adjustedA2, b2);
    let deltaHue = h2 - h1;
    if (c1 * c2 === 0) deltaHue = 0;
    else if (deltaHue > 180) deltaHue -= 360;
    else if (deltaHue < -180) deltaHue += 360;
    let meanHue = (h1 + h2) / 2;
    if (c1 * c2 === 0) meanHue = h1 + h2;
    else if (Math.abs(h1 - h2) > 180) meanHue += h1 + h2 < 360 ? 180 : -180;
    const meanL = (l1 + l2) / 2, meanC = (c1 + c2) / 2;
    const t = 1 - 0.17 * cos(meanHue - 30) + 0.24 * cos(2 * meanHue) +
        0.32 * cos(3 * meanHue + 6) - 0.20 * cos(4 * meanHue - 63);
    const offset = meanL - 50;
    const sl = 1 + 0.015 * offset * offset / Math.sqrt(20 + offset * offset);
    const sc = 1 + 0.045 * meanC, sh = 1 + 0.015 * meanC * t;
    const rotation = -2 * Math.sqrt(meanC ** 7 / (meanC ** 7 + 25 ** 7)) *
        sin(60 * Math.exp(-(((meanHue - 275) / 25) ** 2)));
    const dl = (l2 - l1) / sl, dc = (c2 - c1) / sc;
    const dh = 2 * Math.sqrt(c1 * c2) * sin(deltaHue / 2) / sh;
    return Math.sqrt(dl * dl + dc * dc + dh * dh + rotation * dc * dh);
}
const colorDifference = (a, b) => colorDeltaE(colorLab(a), colorLab(b));

// Marks try their semantic role first, then cycle through this one role order.
// The fixed tint keeps a mark quieter than page text. Compare the rounded
// output colours, since those are the colours kitty actually draws.
const KITTY_ROLE_ORDER = ["accent", "warning", "info", "success", "danger", "textMuted", "textDisabled", "text", "textFaint", "borderControl", "accentPressed", "accentHover", "textHeading"];
function kittyColors(logic, tokens, input) {
    const page = logic.parseColor(input.values.palette.background);
    const plain = logic.parseColor(input.values.palette.foreground);
    const active = logic.parseColor(input.values.bar.active);
    const distinct = (a, b) => logic.contrastRatio(a, b) >= 3 || colorDifference(a, b) >= 15;
    // A locally valid middle mark can consume the only role left for the
    // info mark. Select the first complete set in role order instead.
    function select(chosen) {
        const index = chosen.length;
        if (index === 3) return chosen;
        const tint = [0.52, 0.14, 0.04][index];
        for (let offset = 0; offset < KITTY_ROLE_ORDER.length; offset++) {
            const role = KITTY_ROLE_ORDER[(index + offset) % KITTY_ROLE_ORDER.length];
            const value = expressionColor(logic, tokens, input, `mix({color.${role}}, {palette.background}, ${tint})`);
            const candidate = logic.parseColor("#" + hex6(value, input.values.color.background));
            const luminance = logic.luminance(candidate);
            if (!(input.values.scheme.mode === "light" ? luminance > logic.luminance(plain) : luminance < logic.luminance(plain))) continue;
            if (!distinct(candidate, page) || !chosen.every(earlier => distinct(candidate, earlier))) continue;
            if (index === 2 && !distinct(candidate, active)) continue;
            const complete = select([...chosen, candidate]);
            if (complete !== null) return complete;
        }
        return null;
    }
    const chosen = select([]);
    if (chosen === null) throw new Error("theme-render: kitty has no distinct role colour set");
    const colors = {};
    for (const [index, fill] of chosen.entries()) {
        colors[`kitty.mark${index + 1}_background`] = logic.formatColor(fill);
        colors[`kitty.mark${index + 1}_foreground`] = logic.formatColor(logic.contrastColor(fill));
    }
    return colors;
}

// tmux keeps native palette fields and ordinary package roles client-relative.
// The two preview-authoritative packages fix only their four status roles.
// Default follows the client page/text; reverse uses that page as label text.
function tmuxColors(logic, tokens, input) {
    if (typeof input.name !== "string" || input.name === "")
        throw new Error("theme-render: tmux rendered without the package identity");
    const background = logic.parseColor(input.values.palette.background);
    const colors = {
        "color.background": "default", "color.surfaceRaised": "default", "color.text": "default",
        "color.textMuted": "colour8", "color.border": "colour8", "color.borderStrong": "colour8",
        "bar.onActive": "default"
    };
    for (const [index, name] of logic.terminalSlotNames().entries()) colors["terminal." + name] = "colour" + index;
    const readable = color => color.a === 1 && logic.contrastRatio(color, background) >= logic.READABILITY_FLOOR;
    for (const role of ["palette.accent", "color.accent", "color.info", "color.warning", "palette.warning", "color.danger", "palette.danger", "bar.active"]) {
        const value = role.split(".").reduce((node, key) => node[key], input.values);
        const hue = oklch(hex6(value, input.values.color.background)).h;
        let chosen = null, distance = Infinity;
        for (const [index, name] of logic.terminalSlotNames().entries()) {
            const candidate = logic.parseColor(input.slots[name]);
            if (!readable(candidate)) continue;
            const next = hueDistance(hue, oklch(hex6(input.slots[name], input.values.color.background)).h);
            if (next < distance) { chosen = index; distance = next; }
        }
        if (chosen === null) throw new Error("theme-render: tmux has no readable role colour " + role);
        colors[role] = "colour" + chosen;
    }
    const active = logic.parseColor(input.slots["color" + colors["color.info"].slice("colour".length)]);
    const inactive = logic.parseColor(input.slots.color8);
    // Channel-distance floor from tmp/tmux-block-role-probe.json, 2026-10-07.
    const separation = color => 255 * Math.hypot(color.r - active.r, color.g - active.g, color.b - active.b);
    const distinct = color => separation(color) >= 55.65;
    const muted = logic.parseColor(input.values.color.textMuted);
    let chosen = 8;
    if (!readable(inactive) || !distinct(inactive)) {
        chosen = null;
        let distance = Infinity;
        for (const [index, name] of logic.terminalSlotNames().entries()) {
            const candidate = logic.parseColor(input.slots[name]);
            if (!readable(candidate) || !distinct(candidate)) continue;
            const next = (candidate.r - muted.r) ** 2 + (candidate.g - muted.g) ** 2 + (candidate.b - muted.b) ** 2;
            if (next < distance) { chosen = index; distance = next; }
        }
    }
    if (chosen === null) throw new Error("theme-render: tmux has no readable, distinct inactive colour");
    colors["color.textMuted"] = "colour" + chosen;
    colors["tmux.session"] = colors["bar.active"];
    colors["tmux.current_foreground"] = colors["color.info"];
    colors["tmux.inactive_foreground"] = colors["color.textMuted"];
    colors["tmux.status_foreground"] = colors["color.textMuted"];
    // These preview-authoritative status roles stay fixed over SSH. Moon uses
    // the shared authored danger/info/success roles without changing its palette.
    if (input.name === "vgs" || input.name === "rose-pine-moon") {
        const moon = input.name === "rose-pine-moon";
        const rgb = value => "#" + hex6(value, input.values.color.background);
        colors["tmux.session"] = rgb(moon ? tokens.palette.danger.value : input.values.bar.active);
        if (moon) colors["bar.onActive"] = rgb(tokens.palette.background.value);
        colors["tmux.current_foreground"] = rgb(moon ? tokens.palette.info.value : input.values.color.info);
        colors["tmux.inactive_foreground"] = rgb(moon ? tokens.palette.success.value : input.values.color.textMuted);
        colors["tmux.status_foreground"] = rgb(input.values.color.textMuted);
    }
    return colors;
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
// `values`, its existing package `name`, the terminal `slots` terminalSource chose, `curated`, a Map
// from destination to the bytes of the package's `targets/<destination>`,
// `installed`, true for a package under the configuration home's
// themes/ and false for a shipped one, and `terminalFont`, the user's
// terminal font, absent or null for none. Every template is rendered, so a
// placeholder naming no token or slot refuses the target even where a
// curated file stands in, and so is a line that names an unset terminal
// font, which is then left out whole. On a `runsCode` target an installed package's
// curated file is dropped, never judged, and its destination listed in
// `dropped`; any other curated file curatedTaken admits is taken verbatim.
// An extension target renders its `stamp` destination first and writes its
// extensionStamp wherever another file names `@{extension.stamp}`, and
// EXTENSION_VERSION wherever a file names `@{extension.version}`; the stamp
// file naming the stamp, or a file of any other target naming either,
// refuses the target.
// Answers { ok: true, files: [{ destination, bytes, curated }], dropped,
// extension } in the target's order, `extension` the generated extension's
// extensionOf on an extension target and undefined on any other, or
// one refusal.
function renderTarget(logic, tokens, target, templates, input) {
    if (input.slots === null || typeof input.slots !== "object")
        throw new Error("theme-render: renderTarget: target " + target.name + " rendered without terminal slots");
    if (typeof input.installed !== "boolean")
        throw new Error("theme-render: renderTarget: target " + target.name + " rendered without the package's source");
    const selection = selectValues(logic, tokens, target, input);
    if (selection !== undefined && !selection.ok) return selection;
    if (target.name === "kitty") input = { ...input, targetColors: kittyColors(logic, tokens, input) };
    if (target.name === "tmux") input = { ...input, targetColors: tmuxColors(logic, tokens, input) };
    const encode = hex => ENCODERS[target.encoder](hex, input.values.color.background, logic, input);
    const rendered = new Map();
    const dropped = [];
    const stampFrom = target.wiring !== null && wiringForm(target.wiring) === "extension" ? target.wiring.stamp : undefined;
    const order = target.files.filter(file => file.destination === stampFrom).concat(target.files.filter(file => file.destination !== stampFrom));
    // The extension placeholders' values, the stamp once its file rendered.
    const extensionValues = new Map(stampFrom === undefined ? [] : [[VERSION_PLACEHOLDER, EXTENSION_VERSION]]);
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
        // Where the line being written began in `out`, once it named an
        // unset terminal font, else -1: the line is cut at its end.
        let dropFrom = -1;
        for (const part of template.parts) {
            if (typeof part === "string") {
                const end = dropFrom === -1 ? -1 : part.indexOf("\n");
                if (end === -1) {
                    out += part;
                } else {
                    out = out.slice(0, dropFrom) + part.slice(end + 1);
                    dropFrom = -1;
                }
                continue;
            }
            const value = part.name === STAMP_PLACEHOLDER || part.name === VERSION_PLACEHOLDER ? extensionValues.get(part.name)
                : placeholderText(logic, tokens, input, part.name, encode);
            if (value === undefined) return refused("placeholder", "template=" + file.template + " placeholder=" + JSON.stringify(part.name));
            if (dropFrom === -1 && terminalFont(input) === null && part.name.split(CASE_SEPARATOR)[0] === TERMINAL_FONT) dropFrom = out.lastIndexOf("\n") + 1;
            out += value;
        }
        if (dropFrom !== -1) out = out.slice(0, dropFrom);
        const present = input.curated.has(file.destination);
        const drop = present && input.installed && target.runsCode;
        if (drop) dropped.push(file.destination);
        const curated = present && !drop && curatedTaken(logic, file, input.curated.get(file.destination));
        const bytes = curated ? input.curated.get(file.destination) : Buffer.from(out, "utf8");
        if (file.destination === stampFrom) extensionValues.set(STAMP_PLACEHOLDER, extensionStamp(bytes));
        rendered.set(file.destination, { destination: file.destination, bytes, curated });
    }
    const destinations = target.files.map(file => file.destination);
    const extension = stampFrom === undefined ? undefined : extensionOf(target, rendered.get(stampFrom).bytes);
    const selectionValues = target.select?.format === "kcolorscheme"
        ? { scheme: rendered.get(target.select.source).bytes.toString("latin1") } : selection?.values;
    return { ok: true, files: destinations.map(destination => rendered.get(destination)), dropped: destinations.filter(destination => dropped.includes(destination)), extension, selectionValues };
}

// The stamp of an extension whose `stamp` file holds BYTES: the first 32
// bits of the bytes' sha256 in decimal, so new bytes make a new id.
function extensionStamp(bytes) {
    return String(parseInt(crypto.createHash("sha256").update(bytes).digest("hex").slice(0, 8), 16));
}

// The generated extension of an accepted editors TARGET whose `stamp` file
// holds BYTES: its { id, version, stamp }.
function extensionOf(target, bytes) {
    const stamp = extensionStamp(bytes);
    return { id: target.wiring.extension + "-" + stamp, version: EXTENSION_VERSION, stamp };
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
// written as STATE, the state directory's `theme/` path, and on an editors
// target `@{extension.stamp}` as the stamp of EXTENSION, its extensionOf, so
// the selection names the theme that one extension contributes.
function selectValue(target, state, extension) {
    if (target.select === undefined) throw new Error("theme-render: selectValue: target " + target.name + " has no select");
    const values = { [STATE_PLACEHOLDER]: state };
    if (extension !== undefined) values[STAMP_PLACEHOLDER] = extension.stamp;
    return withValues(target.select.value, values, "selectValue: the selection value of target " + target.name);
}

// The key paths an accepted TARGET's `select` sets, in its order: its one
// key, or each of its list.
function selectKeys(target) {
    if (target.select === undefined) throw new Error("theme-render: selectKeys: target " + target.name + " has no select");
    return typeof target.select.key[0] === "string" ? [target.select.key] : target.select.key;
}

// App colour edits use the same placeholder owner and encoder as templates.
function selectValues(logic, tokens, target, input) {
    if (target.select === undefined || target.select.values === undefined) return undefined;
    const encode = hex => ENCODERS[target.encoder](hex, input.values.color.background);
    const values = {};
    for (const [key, text] of Object.entries(target.select.values)) {
        const parsed = parseTemplate(text);
        if (!parsed.ok) return refused("placeholder", "selection=" + key);
        let value = "";
        for (const part of parsed.parts) {
            const rendered = typeof part === "string" ? part : placeholderText(logic, tokens, input, part.name, encode);
            if (rendered === undefined) return refused("placeholder", "selection=" + key);
            value += rendered;
        }
        values[key] = value;
    }
    return { ok: true, values };
}

// Whether an accepted TARGET's hook is due on every apply that lands it,
// not only on changed bytes or a pending reload.
function reloadAlways(target) {
    return target.reload !== null && target.reload.always === true;
}

// Whether an accepted TARGET's hook runs after every due hook whose target
// does not declare `last`.
function reloadLast(target) {
    return target.reload !== null && target.reload.last === true;
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

// Whether ID is an extension id an extension target whose ids start with
// BASE renders: BASE and a stamp. BASE alone is the id a release before
// stamped ids registered, so the next apply or disable removes it too.
function isStampedId(id, base) {
    return id === base || (id.startsWith(base + "-") && /^[0-9]+$/.test(id.slice(base.length + 1)));
}

// The id NAME is the folder of, when extensionFolder gives NAME for an id
// isStampedId admits for BASE at any version, else null: the folders an
// apply removes but those it keeps.
function extensionFolderId(name, base) {
    const version = /-([0-9]+\.[0-9]+\.[0-9]+)$/.exec(name);
    if (version === null) return null;
    const id = name.slice(0, version.index);
    return isStampedId(id, base) ? id : null;
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
// no id isStampedId admits for BASE but those in the list KEEP: null when it
// registers none or is absent, or the refusal `registry-refused` for a file
// that is no JSON array.
function unregisteredText(logic, text, base, keep) {
    if (text === undefined) return null;
    const entries = parsedJson(text, Array.isArray);
    if (entries === undefined) return refused("registry-refused", "file=extensions.json");
    const kept = entries.filter(entry => {
        const id = registeredId(logic, entry);
        return id === null || keep.includes(id) || !isStampedId(id, base);
    });
    return kept.length === entries.length ? null : JSON.stringify(kept);
}

// The extension a VS Code-family manifest, package.json, holding TEXT
// declares: its lower-case `<publisher>.<name>` id, and the settings id of
// each theme it contributes, its `id`, else its `label`, the name an editor's
// workbench.colorTheme selects it by. Null for text that is no manifest.
function manifestThemes(logic, text) {
    const manifest = parsedJson(text, logic.isPlainObject);
    if (manifest === undefined || typeof manifest.publisher !== "string" || typeof manifest.name !== "string") return null;
    const contributes = logic.isPlainObject(manifest.contributes) ? manifest.contributes : {};
    const themes = Array.isArray(contributes.themes) ? contributes.themes.filter(logic.isPlainObject) : [];
    return { id: (manifest.publisher + "." + manifest.name).toLowerCase(),
        settingsIds: themes.map(theme => theme.id || theme.label).filter(id => typeof id === "string" && id !== "") };
}

// The text an editor's `.obsolete` holding TEXT takes once it marks no
// folder extensionFolderId admits for BASE obsolete, since a marked folder is
// one the editor skips and deletes: null when it marks none or is absent, or
// the refusal `registry-refused` for a file that is no JSON object.
function unobsoletedText(logic, text, base) {
    if (text === undefined) return null;
    const marks = parsedJson(text, logic.isPlainObject);
    if (marks === undefined) return refused("registry-refused", "file=.obsolete");
    const kept = Object.keys(marks).filter(name => extensionFolderId(name, base) === null);
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
// for byte. With LAST true the line must be the file's last non-empty line,
// so the file's own settings never override the included theme: a file
// whose last non-empty line is LINE answers null, and any other loses every
// whole line equal to LINE and takes LINE at its end, so an apply moves a
// line an earlier placement put elsewhere. With
// LAST not true and SECTION undefined the line goes first, ahead of every
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
function wiredText(text, line, section, last) {
    const lines = text === undefined ? [] : text.split("\n");
    if (last === true) {
        if (lines.findLast(existing => existing !== "") === line) return null;
        const kept = lines.filter(existing => existing !== line).join("\n");
        return kept + (kept === "" || kept.endsWith("\n") ? "" : "\n") + line + "\n";
    }
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

module.exports = { colorDeltaE, colorDifference, TARGET_FILE, EDITOR_BASE, extensionOf, extensionFolder, manifestThemes, extensionFolderId, registeredText, unregisteredText, unobsoletedText, acceptTarget, placeholderNames, detected, setupDone, curatedTaken, renderTarget, terminalSource, refusalLine, wiringForm, wiringLine, entryItems, profileDirs, vaultDirs, reloadNamesWiring, reloadCommand, reloadAlways, reloadLast, selectKeys, selectValue, selectValues, wiredText, unwiredText, isSectionHeader, opensSection, assignedKey };
