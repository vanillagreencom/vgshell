.pragma library
.import "../Commons/SettingValues.js" as SettingValues
.import "../Ui/icons/Lucide.js" as Lucide
.import "PackageManagers.js" as PackageManagers
.import "HyprlandLayer.js" as HyprlandLayer
.import "Pads.js" as Pads
.import "MonitorLogic.js" as MonitorLogic

// Pure decisions about plugins and configuration. No QML objects, no I/O, so
// scripts/test-plugin-logic.js runs every function under node. The icon set
// a manifest's `icon` names is the one Icon draws from, and the manager ids
// a requirement's `packages` names are the package-manager table's (D034),
// and the size classes a `tui` entry names are the Hyprland layer's window
// table, each imported here so the shell and every offline reader judge
// against one list.

// The kinds the core hosts. A manifest naming any other kind is refused. A
// kind's entry point is keyed by the kind name in `entryPoints`.
var KINDS = ["bar-widget", "bar", "panel", "overlay", "menu", "window", "pane", "service", "background", "cover"];

// Capabilities the core can hand a plugin. A manifest naming another one is
// refused. Capabilities.qml maps each name to its provider.
var CAPABILITIES = ["compositor", "configure", "idle", "ipc", "lock", "session", "notifications", "polkit", "run", "screens", "shortcut", "surfaces", "builtins", "manager", "panes", "notify", "theme", "layers", "status", "tui", "system", "requirements", "doctor", "secrets", "hyprland", "bluetoothAgent", "monitors"];

// A plugin's system notification, shell.notify.send. The tones and the
// icon grammar are the ones the `x-vgs-tone` and `x-vgs-icon` hints take
// (shell/plugins/vgs.notifications/developer.md § Hints). A title is one
// line and a message a few. At most NOTIFY_RUNS_MAX notify-send runs are in
// flight at once, the ceiling the capture and agent-warden runs keep.
var NOTIFY_KEYS = ["title", "message", "tone", "icon", "urgency", "transient"];
var NOTIFY_TONES = ["success", "warning", "danger", "info"];
var NOTIFY_URGENCIES = ["low", "normal", "critical"];
var NOTIFY_ICON = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
var NOTIFY_ICON_MAX = 64;
var NOTIFY_TITLE_MAX = 120;
var NOTIFY_MESSAGE_MAX = 600;
var NOTIFY_RUNS_MAX = 8;

// Capabilities whose core object serves one plugin at a time: the session
// lock, the polkit agent, the Bluetooth pairing agent and the panes
// holder, each a session-wide role. A second plugin
// naming one is not built while another plugin holds it.
var EXCLUSIVE_CAPABILITIES = ["lock", "polkit", "bluetoothAgent", "panes"];

// The types a settings schema entry may declare, and the keys an entry may
// carry. `presets`, `allowCustom`, `format` and `unit` choose the Settings
// editor; `min`, `max` and `step` bound a number's control; `group` names
// the section heading the entry is drawn under. Pads.js judges a `list`.
var SETTING_TYPES = ["string", "number", "boolean", "enum", "list"];
var SCHEMA_ENTRY_KEYS = ["type", "label", "description", "info", "options", "optionsFrom", "presets", "allowCustom", "format", "unit", "min", "max", "step", "group", "items", "defaults"];
var NUMBER_BOUND_KEYS = ["min", "max", "step"];
var PRESET_KEYS = ["value", "label"];
var PRESET_LABEL_MAX = 40;

// The icon a plugin without a manifest `icon` is listed with.
var DEFAULT_ICON = "package";

var SECTIONS = ["left", "center", "right"];

// Kinds a host shows on demand: `summon`, `hide` and `toggle` reach them.
// Every other kind is shown for as long as it is enabled.
var SUMMONABLE_KINDS = ["panel", "overlay", "menu", "window"];

// Where a summoned panel or menu may sit when no anchor places it, read
// from the plugin's `placement` setting. `center` when the setting is
// absent.
var PLACEMENTS = ["top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"];

// A pane plugin supplies one section of the System window. The manifest's
// `pane` key groups and orders it in the one holder's list.
var PANE_KEYS = ["group", "order"];
var PANE_GROUP_MAX = 60;

// Every key a manifest may carry. An unknown key is refused, so a misspelt
// key fails loudly instead of being carried and ignored.
var MANIFEST_KEYS = ["schemaVersion", "id", "name", "version", "author", "description", "license", "icon", "kinds", "entryPoints", "capabilities", "systemSteps", "settings", "schema", "defaultSection", "pane", "appearance", "hyprland", "requirements", "status", "tui", "menu", "secrets", "alwaysOn"];

// What one entry of a manifest's `requirements`, and of the core's own
// config/requirements.json, may carry: an external command the plugin runs
// or a D-Bus name it reaches, the package that provides it per manager id of
// PackageManagers.js, whether the plugin works without it, and one line
// saying what it is for. The states a probed requirement is reported in.
var REQUIREMENT_KEYS = ["command", "dbus", "packages", "optional", "purpose"];
var REQUIREMENT_DBUS_KEYS = ["bus", "name"];
var REQUIREMENT_BUSES = ["system", "session"];
var REQUIREMENT_PURPOSE_MAX = 120;
var REQUIREMENT_STATES = ["present", "missing"];
// A purpose is one printable line: no C0 or C1 control character.
var CONTROL_CHARACTER = /[\u0000-\u001f\u007f-\u009f]/;
var DBUS_NAME_PART = /^[A-Za-z_-][A-Za-z0-9_-]*$/;


// Plugin status: the runtime values a plugin publishes through its `status`
// capability, each declared in the manifest's `status` key with one of these
// types. `data` is structured JSON only the plugin's own instances read; the
// Settings window draws every other type unless the entry is `hidden`;
// `choices` feeds a setting's Select instead of a Status row.
var STATUS_TYPES = ["presence", "presenceList", "state", "text", "count", "time", "data", "choices", "launcherRows"];
var STATUS_ENTRY_KEYS = ["type", "label", "group", "hint", "info", "hidden", "action", "actions"];
// A status key names a value in `shell.status.values`, so it is a plain
// identifier.
var STATUS_KEY_PATTERN = /^[a-z][A-Za-z0-9]*$/;
// Declaration text lengths, in characters: a label and a group are one short
// line, and a hint a sentence. A `text` value and a `state` value's text are
// one line of this length.
var STATUS_LABEL_MAX = 60;
var STATUS_HINT_MAX = 200;
var STATUS_TEXT_MAX = 200;
// An info dialog is the longer help a row keeps out of the page.
var INFO_MAX = 400;
// The ceiling on one plugin's published values: the UTF-8 bytes of their
// JSON. A write that would pass it is refused and the values stay.
var STATUS_MAX_BYTES = 65536;
// A `presence` value, and the badge tone Settings draws it with: the thing is
// stored and readable; not stored; stored but locked, so a background probe
// cannot read it without prompting; its store cannot be asked; stored where
// another user can read it.
var STATUS_PRESENCE_TONES = { present: "success", absent: "warning", locked: "info", unavailable: "neutral", unsafe: "danger" };
// A `state` value's `tone`, and the badge tone Settings draws it with.
var STATUS_STATE_TONES = { ok: "success", info: "info", warning: "warning", danger: "danger" };
// The keys a `state` value carries. `action` is its writer's to decide
// (D061): true when the entry's declared `action` applies to this value,
// or the name of the one of the entry's declared `actions` that does.
// `lines` is the further printable lines a state that names several things
// draws under `text`, at most STATUS_LIST_MAX. `hint` is bounded plain
// guidance for this state; without it, the declaration's hint applies.
var STATUS_STATE_KEYS = ["tone", "text", "lines", "hint", "action"];
// A `presenceList` value is a list of at most STATUS_LIST_MAX items, each
// carrying these keys: a printable `label` and a `presence` value, with an
// optional printable `hint` and an optional `secret`, the account of the
// plugin's declared `secrets` the item is the presence of.
var STATUS_LIST_MAX = 64;
var STATUS_LIST_ITEM_KEYS = ["label", "value", "hint", "secret"];
// Choice values are stable ids, not their display labels. Empty string is
// reserved for a setting that follows the first offered value.
var STATUS_CHOICE_KEYS = ["label", "value"];
// A plugin-published launcher provider can expose a category of dynamic
// rows. The ceiling admits a 150-row catalog with growth room and keeps
// search work bounded.
var LAUNCHER_ROWS_MAX = 256;
var LAUNCHER_ROW_KEYS = ["id", "label", "icon", "description", "aliases", "menu"];

// A status entry's `action` (D061): the one-click setup step the Settings
// page draws as a button beside the entry. It carries a printable `label`
// and exactly one route, STATUS_ACTION_ROUTES: `tui`, a name of the
// manifest's own `tui` key the core opens in a floating terminal;
// `install`, a list of the manifest's own requirements the core
// offers through the requirement notice; or `system`, a step of the
// manifest's own `systemSteps` the core applies in its `core/system` TUI
// (D081). An entry of a type in STATUS_ACTION_TYPES takes one. A `state`
// entry whose step differs by what its writer found declares `actions`
// instead: two or more such steps by name, a STATUS_KEY_PATTERN
// identifier, of which a value names at most one.
var STATUS_ACTION_ROUTES = ["tui", "install", "system"];
var STATUS_ACTION_KEYS = ["label"].concat(STATUS_ACTION_ROUTES);
var STATUS_ACTION_TYPES = ["presence", "state"];
// The refusal reasons of the `manager` capability's `act`.
var STATUS_ACTION_REASONS = ["undeclared", "disabled", "not-offered"];

// The system steps (D081): the closed table bin/vgshell-system holds, which a
// manifest's `systemSteps` names from, in the order `vgshell-system status`
// prints them, and the states a probe reads each one in. The script is the
// table's owner; scripts/test-vgshell-system.sh reads its status back against
// this list.
var SYSTEM_STEPS = ["apple-displays", "i2c-dev", "service-bluetooth", "service-tailscaled", "tailscale-operator", "greeter", "bandwhich-capture"];
var SYSTEM_STATES = ["ready", "needed", "denied", "absent", "unknown", "nixos"];
// A probe's reason: a short key of lower case letters and dashes.
var SYSTEM_REASON_PATTERN = /^[a-z][a-z-]{0,39}$/;

// A manifest's `secrets` (D061): the libsecret items the core stores and
// clears for the plugin from a masked field on its Settings page, never
// through a command the user types. `service` is the items' `service`
// attribute; `label` leads each item's libsecret label.
var SECRETS_KEYS = ["service", "label"];
var SECRET_SERVICE_PATTERN = /^[a-z][a-z0-9-]{0,63}$/;
// An item's `account` attribute, as a `presenceList` item's `secret` names
// it: letters and digits, then those and `:._-`.
var SECRET_ACCOUNT_PATTERN = /^[A-Za-z0-9][A-Za-z0-9:._-]{0,127}$/;
// A secret the core stores is 1 to SECRET_VALUE_MAX characters with no
// control character, line separator or paragraph separator. secret-tool reads a secret from a stdin that is no
// terminal up to its end, at most 8192 bytes, and keeps every byte
// (libsecret tool/secret-tool.c, read_password_stdin), so the core writes the
// value alone, with no newline, and closes stdin; 4096 characters of at
// most two UTF-8 bytes each fit.
var SECRET_VALUE_MAX = 4096;
// What the Settings page offers a `presenceList` item with a `secret`, by
// its presence: Connect while nothing is stored, Disconnect while something
// is, and nothing while the store cannot be asked.
var SECRET_ACCESS = { absent: "connect", present: "disconnect", locked: "disconnect", unsafe: "disconnect", unavailable: "" };
var SECRET_VERBS = { store: "connect", clear: "disconnect" };
var SECRET_REASONS = ["undeclared", "disabled", "unlisted", "not-offered", "value", "busy"];

// A name a plugin registers a shortcut, an IPC target or a built-in widget
// under, the name a manifest's Hyprland bind gives its shortcut, and the name
// a manifest's `tui` key declares a script under.
// Capabilities.checkName refuses any other.
var NAME_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

// What a manifest's `hyprland` key may hold: binds of the plugin's own
// shortcuts, blur rules for the core's layer namespaces, the theme
// appearance switches, the input options its settings set and one monitor
// rule setting. Data only;
// the core renders it (HyprlandLayer.js), so no plugin text reaches the
// compositor's Lua.
var HYPRLAND_KEYS = ["binds", "layerRules", "appearance", "options", "pads", "monitors"];
var HYPRLAND_BIND_KEYS = ["shortcut", "key", "hold", "tap", "info"];
var HYPRLAND_RULE_KEYS = ["namespace", "blur", "ignoreAlpha"];
// The modifiers a Hyprland key may hold, in the order a normalised key
// writes them, and the key name after them: a keysym name, which Hyprland
// looks up without regard to case.
var HYPRLAND_MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT"];
var HYPRLAND_KEY_NAME = /^[A-Za-z0-9_]+$/;
// A layer rule matches one core host's namespace, anchored: `^vgs:<name>$`.
var HYPRLAND_NAMESPACE = /^\^vgs:[a-z][a-z0-9-]*\$$/;
var HYPRLAND_APPEARANCE_GROUPS = HyprlandLayer.APPEARANCE_GROUPS;

function hasOwn(obj, key) {
    return obj !== null && typeof obj === "object" && Object.prototype.hasOwnProperty.call(obj, key);
}

var ID_PATTERN = /^[a-z0-9]+(\.[a-z0-9-]+)+$/;

// First-party plugins carry this prefix. They are enabled unless disabled;
// every other plugin is enabled only when the configuration names it.
var FIRST_PARTY_PREFIX = "vgs.";

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function clone(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

// The version a configuration file declares. Each user-file edit here
// (`withEnabled`, `withPlaced`, `withSetting`, `withKey`) writes it into a
// user file that has none.
var CONFIG_VERSION = 1;

// The first defect of a configuration file (shipped or user), or "". The
// file is an object; `version`, when present, is CONFIG_VERSION; `plugins`
// is a list of objects each with a string `id`, and a row's `keys`, when
// present, passes keysError; `disabledPlugins` and
// `disabledTargets` are lists of strings; `bar` is an object whose `id` is
// a string and whose `layout` holds, per section in SECTIONS, a list of
// objects each with a string `id`; `packages` is an object whose `elevate`,
// when present, is one of PackageManagers.ELEVATORS, the command
// `vgshell pkg run` elevates through; `welcome` is an object whose `keys` is
// a list of objects each with a string `id`, a string `shortcut` and a
// non-empty string `text`, the welcome's key lines (consentSlotView);
// `manager` is an object whose `id` is a string (managerId).
// A key outside that set is carried untouched. Config.qml runs this judge
// on every parsed file and reports a defect as the file's state, so no
// malformed row is dropped on the way to the screen.
function configError(config) {
    if (!isPlainObject(config))
        return "config must be an object";
    if (config.version !== undefined && config.version !== CONFIG_VERSION)
        return "version must be " + CONFIG_VERSION + ", got " + JSON.stringify(config.version);
    var rows = function (list, at) {
        if (!Array.isArray(list))
            return at + " must be a list";
        for (var i = 0; i < list.length; i++) {
            if (!isPlainObject(list[i]) || typeof list[i].id !== "string")
                return at + "." + i + " must be an object with a string id";
        }
        return "";
    };
    var bad;
    if (config.plugins !== undefined && (bad = rows(config.plugins, "plugins")) !== "")
        return bad;
    if (config.plugins !== undefined) {
        for (var p = 0; p < config.plugins.length; p++) {
            if (config.plugins[p].keys !== undefined && (bad = keysError(config.plugins[p].keys, "plugins." + p + ".keys")) !== "")
                return bad;
        }
    }
    var names = function (list, at) {
        if (!Array.isArray(list))
            return at + " must be a list";
        for (var i = 0; i < list.length; i++) {
            if (typeof list[i] !== "string")
                return at + "." + i + " must be a string";
        }
        return "";
    };
    if (config.disabledPlugins !== undefined && (bad = names(config.disabledPlugins, "disabledPlugins")) !== "")
        return bad;
    if (config.disabledTargets !== undefined && (bad = names(config.disabledTargets, "disabledTargets")) !== "")
        return bad;
    if (config.packages !== undefined) {
        if (!isPlainObject(config.packages))
            return "packages must be an object";
        if (config.packages.elevate !== undefined && PackageManagers.ELEVATORS.indexOf(config.packages.elevate) === -1)
            return "packages.elevate must be one of " + PackageManagers.ELEVATORS.join(", ") + ", got " + JSON.stringify(config.packages.elevate);
    }
    if (config.bar !== undefined) {
        if (!isPlainObject(config.bar))
            return "bar must be an object";
        if (config.bar.id !== undefined && typeof config.bar.id !== "string")
            return "bar.id must be a string";
        if (config.bar.layout !== undefined) {
            if (!isPlainObject(config.bar.layout))
                return "bar.layout must be an object";
            for (var s = 0; s < SECTIONS.length; s++) {
                var section = SECTIONS[s];
                if (config.bar.layout[section] !== undefined && (bad = rows(config.bar.layout[section], "bar.layout." + section)) !== "")
                    return bad;
            }
        }
    }
    if (config.manager !== undefined) {
        if (!isPlainObject(config.manager))
            return "manager must be an object";
        if (typeof config.manager.id !== "string")
            return "manager.id must be a string";
    }
    if (config.welcome !== undefined) {
        if (!isPlainObject(config.welcome))
            return "welcome must be an object";
        if ((bad = rows(config.welcome.keys, "welcome.keys")) !== "")
            return bad;
        for (var w = 0; w < config.welcome.keys.length; w++) {
            var line = config.welcome.keys[w];
            if (typeof line.shortcut !== "string" || typeof line.text !== "string" || line.text === "")
                return "welcome.keys." + w + " must hold a string shortcut and a non-empty string text";
        }
    }
    return "";
}

function presetValues(entry) {
    return Array.isArray(entry.presets) ? entry.presets.map(function (preset) { return preset.value; }) : [];
}

function presetMembershipError(entry, value) {
    return entry.presets !== undefined && entry.allowCustom !== true && presetValues(entry).indexOf(value) === -1 ? "want=one-of-presets" : "";
}

// Why `value` does not fit a schema entry, or "" when it does. A number
// outside the entry's `min` or `max` does not fit; `step` refuses nothing.
// A preset list without `allowCustom` accepts only one of its values.
function settingError(entry, value) {
    if (entry.type === "string") {
        if (typeof value !== "string") return "want=string";
        if (entry.format === "datetime") {
            var problem = SettingValues.datetimeFormatProblem(value);
            if (problem !== "") return "want=datetime-format reason=" + problem;
        }
        return presetMembershipError(entry, value);
    }
    if (entry.type === "number") {
        if (typeof value !== "number" || !isFinite(value)) return "want=number";
        if (entry.min !== undefined && value < entry.min) return "want=at-least:" + entry.min;
        if (entry.max !== undefined && value > entry.max) return "want=at-most:" + entry.max;
        return presetMembershipError(entry, value);
    }
    if (entry.type === "boolean") return typeof value === "boolean" ? "" : "want=boolean";
    if (entry.type === "enum") return entry.options.indexOf(value) !== -1 ? "" : "want=one-of:" + entry.options.join("|");
    if (entry.type === "list") return Pads.listValueError(entry, value, settingError, NAME_PATTERN);
    throw new Error("settingError: schema entry type " + JSON.stringify(entry.type) + " passed validation but has no rule");
}

// The first defect of a settings schema, or "". Every entry names a type
// from SETTING_TYPES and a label; an enum entry lists its options; a number
// entry may bound its control with finite `min` below finite `max` and a
// positive `step`, which no other type carries; `unit` names a number's
// words; `group`, when present, is a non-empty string; every entry has a
// default of its type, inside its bounds, in `settings`, so a form always
// has a value to show. A string declares `presets` or `optionsFrom`.
// optionsFrom connects a string to a declared choices status, never to
// another plugin. Presets declare the picker values, and `allowCustom` lets
// another fitting value write.
function schemaError(schema, settings, status) {
    if (!isPlainObject(schema))
        return "schema must be an object";
    if (hasOwn(schema, "id"))
        return "schema must not carry an id key";
    var keys = Object.keys(schema);
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        var entry = schema[key];
        var at = "schema." + key;
        if (!isPlainObject(entry))
            return at + " must be an object";
        var entryKeys = Object.keys(entry);
        for (var u = 0; u < entryKeys.length; u++) {
            if (SCHEMA_ENTRY_KEYS.indexOf(entryKeys[u]) === -1)
                return at + " has unknown key " + JSON.stringify(entryKeys[u]);
        }
        if (SETTING_TYPES.indexOf(entry.type) === -1)
            return at + ".type must be one of " + SETTING_TYPES.join(", ") + ", got " + JSON.stringify(entry.type);
        if (typeof entry.label !== "string" || entry.label.length === 0)
            return at + ".label must be a non-empty string";
        if (entry.description !== undefined && typeof entry.description !== "string")
            return at + ".description must be a string when present";
        var schemaInfo = infoError(entry.info, at);
        if (schemaInfo !== "")
            return schemaInfo;
        var listBad = Pads.listEntryError(entry, at, status, schemaError);
        if (listBad !== "")
            return listBad;
        if (entry.type === "enum") {
            if (!Array.isArray(entry.options) || entry.options.length === 0)
                return at + ".options must be a non-empty array for type enum";
            for (var o = 0; o < entry.options.length; o++) {
                if (typeof entry.options[o] !== "string" || entry.options[o].length === 0 || entry.options.indexOf(entry.options[o]) !== o)
                    return at + ".options must hold distinct non-empty strings";
            }
        } else if (entry.options !== undefined) {
            return at + ".options needs type enum";
        }
        if (entry.optionsFrom !== undefined) {
            if (entry.type !== "string")
                return at + ".optionsFrom needs type string";
            if (typeof entry.optionsFrom !== "string" || !STATUS_KEY_PATTERN.test(entry.optionsFrom))
                return at + ".optionsFrom must name a status key";
            if (!hasOwn(status, entry.optionsFrom) || status[entry.optionsFrom].type !== "choices")
                return at + ".optionsFrom must name a choices status entry";
        }
        if (entry.presets !== undefined && entry.optionsFrom !== undefined)
            return at + " must not declare both presets and optionsFrom";
        if (entry.allowCustom !== undefined && entry.presets === undefined)
            return at + ".allowCustom needs presets";
        if (entry.format !== undefined && entry.presets === undefined)
            return at + ".format needs presets";
        if (entry.type === "string" && entry.presets === undefined && entry.optionsFrom === undefined)
            return at + " with type string must declare presets or optionsFrom";
        if (entry.presets !== undefined) {
            if (entry.type !== "string" && entry.type !== "number")
                return at + ".presets needs type string or number";
            if (!Array.isArray(entry.presets) || entry.presets.length === 0)
                return at + ".presets must be a non-empty array";
            var seenPresets = [];
            for (var p = 0; p < entry.presets.length; p++) {
                var preset = entry.presets[p];
                var presetAt = at + ".presets." + p;
                if (!isPlainObject(preset))
                    return presetAt + " must be an object";
                var presetKeys = Object.keys(preset);
                for (var pk = 0; pk < presetKeys.length; pk++) {
                    if (PRESET_KEYS.indexOf(presetKeys[pk]) === -1)
                        return presetAt + " has unknown key " + JSON.stringify(presetKeys[pk]);
                }
                if (!hasOwn(preset, "value"))
                    return presetAt + ".value is required";
                if (preset.label !== undefined && !isPrintableLine(preset.label, PRESET_LABEL_MAX))
                    return presetAt + ".label must be a printable line of 1 to " + PRESET_LABEL_MAX + " characters";
                if (preset.value === "" && preset.label === undefined)
                    return presetAt + ".label is required when value is empty";
                var presetKey = JSON.stringify(preset.value);
                if (seenPresets.indexOf(presetKey) !== -1)
                    return at + ".presets must hold distinct values";
                seenPresets.push(presetKey);
                var badPreset = settingError(Object.assign({}, entry, { allowCustom: true }), preset.value);
                if (badPreset !== "")
                    return presetAt + ".value does not fit its schema: " + badPreset;
            }
        }
        if (entry.allowCustom !== undefined) {
            if (typeof entry.allowCustom !== "boolean")
                return at + ".allowCustom must be a boolean";
        }
        if (entry.format !== undefined) {
            if (entry.type !== "string")
                return at + ".format needs type string";
            if (SettingValues.FORMATS.indexOf(entry.format) === -1)
                return at + ".format must be one of " + SettingValues.FORMATS.join(", ") + ", got " + JSON.stringify(entry.format);
        }
        if (entry.unit !== undefined) {
            if (entry.type !== "number")
                return at + ".unit needs type number";
            if (SettingValues.UNITS.indexOf(entry.unit) === -1)
                return at + ".unit must be one of " + SettingValues.UNITS.join(", ") + ", got " + JSON.stringify(entry.unit);
        }
        for (var n = 0; n < NUMBER_BOUND_KEYS.length; n++) {
            var bound = NUMBER_BOUND_KEYS[n];
            if (entry[bound] === undefined)
                continue;
            if (entry.type !== "number")
                return at + "." + bound + " needs type number";
            if (typeof entry[bound] !== "number" || !isFinite(entry[bound]))
                return at + "." + bound + " must be a finite number";
        }
        if (entry.min !== undefined && entry.max !== undefined && !(entry.min < entry.max))
            return at + ".min must be less than max";
        if (entry.step !== undefined && !(entry.step > 0))
            return at + ".step must be positive";
        if (entry.group !== undefined && (typeof entry.group !== "string" || entry.group.length === 0))
            return at + ".group must be a non-empty string when present";
        if (!hasOwn(settings, key))
            return at + " has no default in settings";
        var bad = settingError(entry, settings[key]);
        if (bad !== "")
            return "settings." + key + " does not fit its schema: " + bad;
    }
    return "";
}

// Whether `text` is one printable line of 1 to `max` characters: a string
// with no control character (C0, DEL, C1) and no line or paragraph
// separator, so a page draws it on one line and a log line holds it whole.
function isPrintableLine(text, max) {
    return typeof text === "string" && text.length > 0 && text.length <= max && !SettingValues.CONTROL_OR_SEPARATOR.test(text);
}

function infoError(info, at) {
    return info === undefined || isPrintableLine(info, INFO_MAX) ? "" : at + ".info must be a printable line of 1 to " + INFO_MAX + " characters when present";
}

// The first defect of a manifest's `status` key, or "". An object keyed by
// status key (STATUS_KEY_PATTERN), each entry naming a type from
// STATUS_TYPES and a printable `label`, with an optional printable `group`
// and `hint`, an optional `action` statusActionError admits, and an
// optional boolean `hidden`. A `state` entry may declare `actions` in
// place of `action`: an object of two or more named actions. A `data`
// entry is never drawn, so it carries none of `group`, `hint`, `hidden`,
// `action` or `actions`. A plugin publishes status
// only through its `status` capability, so the key needs the capability,
// and the capability needs at least one entry. TUI is the manifest's `tui`
// key or undefined, REQUIREMENTS its judged `requirements` list, SYSTEM
// its judged `systemSteps` or undefined.
function statusError(status, capabilities, tui, requirements, system) {
    if (!isPlainObject(status))
        return "status must be an object";
    var keys = Object.keys(status);
    if (keys.length === 0)
        return "status must declare at least one entry";
    if (capabilities.indexOf("status") === -1)
        return "status needs capability status";
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        var entry = status[key];
        var at = "status." + key;
        if (!STATUS_KEY_PATTERN.test(key))
            return "status key " + JSON.stringify(key) + " must match " + STATUS_KEY_PATTERN.source;
        if (!isPlainObject(entry))
            return at + " must be an object";
        var entryKeys = Object.keys(entry);
        for (var u = 0; u < entryKeys.length; u++) {
            if (STATUS_ENTRY_KEYS.indexOf(entryKeys[u]) === -1)
                return at + " has unknown key " + JSON.stringify(entryKeys[u]);
        }
        if (STATUS_TYPES.indexOf(entry.type) === -1)
            return at + ".type must be one of " + STATUS_TYPES.join(", ") + ", got " + JSON.stringify(entry.type);
        if (!isPrintableLine(entry.label, STATUS_LABEL_MAX))
            return at + ".label must be a printable line of 1 to " + STATUS_LABEL_MAX + " characters";
        if (entry.group !== undefined && !isPrintableLine(entry.group, STATUS_LABEL_MAX))
            return at + ".group must be a printable line of 1 to " + STATUS_LABEL_MAX + " characters when present";
        if (entry.hint !== undefined && !isPrintableLine(entry.hint, STATUS_HINT_MAX))
            return at + ".hint must be a printable line of 1 to " + STATUS_HINT_MAX + " characters when present";
        var statusInfo = infoError(entry.info, at);
        if (statusInfo !== "")
            return statusInfo;
        if (entry.hidden !== undefined && typeof entry.hidden !== "boolean")
            return at + ".hidden must be a boolean when present";
        if (entry.action !== undefined && entry.actions !== undefined)
            return at + " declares both action and actions";
        if (entry.actions !== undefined) {
            if (entry.type !== "state")
                return at + ".actions needs type state, whose value names the one that applies";
            if (!isPlainObject(entry.actions) || Object.keys(entry.actions).length < 2)
                return at + ".actions must be an object of two or more actions; one action is the entry's action";
        }
        var declared = statusEntryActions(entry);
        for (var a = 0; a < declared.length; a++) {
            if (declared[a].name !== null && !STATUS_KEY_PATTERN.test(declared[a].name))
                return at + ".actions key " + JSON.stringify(declared[a].name) + " must match " + STATUS_KEY_PATTERN.source;
            var badAction = statusActionError(entry.type, declared[a].action, at + declared[a].at, tui, requirements, system);
            if (badAction !== "")
                return badAction;
        }
        if (entry.type === "data" || entry.type === "launcherRows") {
            var drawn = ["group", "hint", "info", "hidden", "action", "actions"];
            for (var d = 0; d < drawn.length; d++) {
                if (entry[drawn[d]] !== undefined)
                    return at + "." + drawn[d] + " needs a type Settings draws; " + entry.type + " is never drawn";
            }
        }
    }
    return "";
}

// The actions status entry ENTRY declares, each { name, at, action }: its
// one `action`, NAME null and AT `.action`, or each of its `actions` by
// NAME, AT `.actions.<name>`; none for an entry without either.
function statusEntryActions(entry) {
    if (entry.action !== undefined)
        return [{ name: null, at: ".action", action: entry.action }];
    if (!isPlainObject(entry.actions))
        return [];
    return Object.keys(entry.actions).map(function (name) {
        return { name: name, at: ".actions." + name, action: entry.actions[name] };
    });
}

// The first defect of ACTION, one action of a status entry of type TYPE,
// AT its path, or "": an object of STATUS_ACTION_KEYS on an entry whose
// type is in STATUS_ACTION_TYPES, a printable `label` of at most STATUS_LABEL_MAX
// characters, and exactly one of STATUS_ACTION_ROUTES: `tui`, a name the
// manifest's TUI key declares; `install`, a non-empty list of requirements the
// manifest's REQUIREMENTS declare, each once; `system`, a step the
// manifest's SYSTEM, its `systemSteps`, declares.
function statusActionError(type, action, at, tui, requirements, system) {
    if (STATUS_ACTION_TYPES.indexOf(type) === -1)
        return at + " needs a type whose value says when it applies, one of " + STATUS_ACTION_TYPES.join(", ");
    if (!isPlainObject(action))
        return at + " must be an object";
    var keys = Object.keys(action);
    for (var i = 0; i < keys.length; i++) {
        if (STATUS_ACTION_KEYS.indexOf(keys[i]) === -1)
            return at + " has unknown key " + JSON.stringify(keys[i]);
    }
    if (!isPrintableLine(action.label, STATUS_LABEL_MAX))
        return at + ".label must be a printable line of 1 to " + STATUS_LABEL_MAX + " characters";
    if (STATUS_ACTION_ROUTES.filter(function (route) { return action[route] !== undefined; }).length !== 1)
        return at + " must name exactly one of " + STATUS_ACTION_ROUTES.join(", ");
    if (action.system !== undefined) {
        if (typeof action.system !== "string" || !Array.isArray(system) || system.indexOf(action.system) === -1)
            return at + ".system must name a step of the manifest's systemSteps, got " + JSON.stringify(action.system);
        return "";
    }
    if (action.tui !== undefined) {
        if (typeof action.tui !== "string" || !isPlainObject(tui) || !hasOwn(tui, action.tui))
            return at + ".tui must name a script of the manifest's tui key, got " + JSON.stringify(action.tui);
        return "";
    }
    if (!Array.isArray(action.install) || action.install.length === 0)
        return at + ".install must be a non-empty list of the manifest's requirements";
    var declared = requirements.map(requirementName);
    for (var n = 0; n < action.install.length; n++) {
        if (declared.indexOf(action.install[n]) === -1)
            return at + ".install." + n + " must name a requirement of the manifest's requirements, got " + JSON.stringify(action.install[n]);
        if (action.install.indexOf(action.install[n]) !== n)
            return at + ".install." + n + " repeats " + JSON.stringify(action.install[n]);
    }
    return "";
}

// The first defect of a manifest's `systemSteps`, or "": a non-empty list
// of SYSTEM_STEPS, each once. The plugin reads their states through
// capability `system`, which the manifest must name, and the capability
// needs the key.
function systemStepsError(steps, capabilities) {
    if (!Array.isArray(steps) || steps.length === 0)
        return "systemSteps must be a non-empty list of steps of the core's table";
    if (capabilities.indexOf("system") === -1)
        return "systemSteps needs capability system";
    for (var i = 0; i < steps.length; i++) {
        if (typeof steps[i] !== "string" || SYSTEM_STEPS.indexOf(steps[i]) === -1)
            return "systemSteps." + i + " must be one of " + SYSTEM_STEPS.join(", ") + ", got " + JSON.stringify(steps[i]);
        if (steps.indexOf(steps[i]) !== i)
            return "systemSteps." + i + " repeats " + JSON.stringify(steps[i]);
    }
    return "";
}

// Every step of SYSTEM_STEPS as { state: "unknown", reason: REASON }.
function systemUnknown(reason) {
    var out = {};
    SYSTEM_STEPS.forEach(function (step) { out[step] = { state: "unknown", reason: reason }; });
    return out;
}

// What the SystemSteps owner holds after one run of `bin/vgshell-system
// status --json`, COMPLETION { code, status } or null for a run that never
// started, STDOUT its output: { steps, line }. `steps` maps every step of
// SYSTEM_STEPS to { state, reason }, a state of SYSTEM_STATES and a reason
// SYSTEM_REASON_PATTERN admits. A run that gives no such report reads
// every step `unknown` with reason `probe-failed`, never ready, and `line`
// is the log line naming why: `system: probe=unstarted`, `system:
// probe=failed exit=<code> status=<status> <first stderr line>`, or
// `system: probe=malformed` with what the report lacks. `line` is ""
// otherwise.
function systemReport(completion, stdout, stderr) {
    var failed = function (line) { return { steps: systemUnknown("probe-failed"), line: line }; };
    if (completion === null)
        return failed("system: probe=unstarted");
    if (completion.status !== 0 || completion.code !== 0)
        return failed("system: probe=failed exit=" + completion.code + " status=" + completion.status + " " + String(stderr).split("\n")[0]);
    var doc;
    try {
        doc = JSON.parse(stdout);
    } catch (e) {
        return failed("system: probe=malformed reason=json");
    }
    if (!isPlainObject(doc) || Object.keys(doc).length !== 1 || !isPlainObject(doc.steps))
        return failed("system: probe=malformed reason=shape");
    var names = Object.keys(doc.steps);
    if (names.length !== SYSTEM_STEPS.length || !SYSTEM_STEPS.every(function (step) { return hasOwn(doc.steps, step); }))
        return failed("system: probe=malformed reason=steps");
    var steps = {};
    for (var i = 0; i < SYSTEM_STEPS.length; i++) {
        var step = SYSTEM_STEPS[i];
        var entry = doc.steps[step];
        if (!isPlainObject(entry) || Object.keys(entry).length !== 2 || SYSTEM_STATES.indexOf(entry.state) === -1 ||
            typeof entry.reason !== "string" || !SYSTEM_REASON_PATTERN.test(entry.reason))
            return failed("system: probe=malformed reason=step step=" + step);
        steps[step] = { state: entry.state, reason: entry.reason };
    }
    return { steps: steps, line: "" };
}

// Whether two `steps` of systemReport read the same states and reasons.
function systemStepsEqual(a, b) {
    return SYSTEM_STEPS.every(function (step) {
        return a[step].state === b[step].state && a[step].reason === b[step].reason;
    });
}

// The states the `system` capability lends a plugin: one { state, reason }
// of STEPS per step of DECLARED, its manifest's `systemSteps`, in that
// order, each a copy.
function systemStateOf(steps, declared) {
    var out = {};
    declared.forEach(function (step) { out[step] = { state: steps[step].state, reason: steps[step].reason }; });
    return out;
}

// The name a raw requirement entry, one requirementsError accepted, is
// listed and named by: its command, or its D-Bus name.
function requirementName(requirement) {
    return requirement.command !== undefined ? requirement.command : requirement.dbus.name;
}

// The first defect of a manifest's `pane` key, or "": a plugin of kind
// `pane` needs { group, order } so the one panes holder can list it; a
// manifest without the kind may not carry the key.
function paneError(pane, kinds) {
    if (kinds.indexOf("pane") === -1)
        return "pane needs kind pane";
    if (!isPlainObject(pane))
        return "pane must be an object";
    var keys = Object.keys(pane);
    for (var i = 0; i < keys.length; i++) {
        if (PANE_KEYS.indexOf(keys[i]) === -1)
            return "pane has unknown key " + JSON.stringify(keys[i]);
    }
    if (!isPrintableLine(pane.group, PANE_GROUP_MAX))
        return "pane.group must be a printable line of 1 to " + PANE_GROUP_MAX + " characters";
    if (typeof pane.order !== "number" || !isFinite(pane.order))
        return "pane.order must be a finite number";
    return "";
}

// The first defect of a manifest's `secrets` key, or "": an object of
// SECRETS_KEYS with a `service` of SECRET_SERVICE_PATTERN and a printable
// `label` of at most STATUS_LABEL_MAX characters. The core writes the items
// only for the plugin that declares them, whose instances learn of each
// write through capability `secrets`, which the key needs and which needs
// the key; a `presenceList` status entry is where its items are listed.
function secretsError(secrets, capabilities, status) {
    if (!isPlainObject(secrets))
        return "secrets must be an object";
    var keys = Object.keys(secrets);
    for (var i = 0; i < keys.length; i++) {
        if (SECRETS_KEYS.indexOf(keys[i]) === -1)
            return "secrets has unknown key " + JSON.stringify(keys[i]);
    }
    if (typeof secrets.service !== "string" || !SECRET_SERVICE_PATTERN.test(secrets.service))
        return "secrets.service must match " + SECRET_SERVICE_PATTERN.source + ", got " + JSON.stringify(secrets.service);
    if (!isPrintableLine(secrets.label, STATUS_LABEL_MAX))
        return "secrets.label must be a printable line of 1 to " + STATUS_LABEL_MAX + " characters";
    if (capabilities.indexOf("secrets") === -1)
        return "secrets needs capability secrets";
    var lists = status === undefined ? [] : Object.keys(status).filter(function (key) { return isPlainObject(status[key]) && status[key].type === "presenceList"; });
    if (lists.length === 0)
        return "secrets needs a presenceList status entry to list its items";
    return "";
}

// Whether `value` is plain JSON: null, a boolean, a finite number, a string,
// an array of plain JSON, or an object whose prototype is Object's or none
// holding plain JSON. Anything JSON.stringify would drop, change or refuse,
// such as a function, a Date or a QML object, is not.
function isPlainJson(value) {
    if (value === null || typeof value === "boolean" || typeof value === "string")
        return true;
    if (typeof value === "number")
        return isFinite(value);
    if (Array.isArray(value)) {
        for (var i = 0; i < value.length; i++)
            if (!isPlainJson(value[i])) return false;
        return true;
    }
    if (typeof value !== "object")
        return false;
    // A plain object's prototype is Object.prototype of whichever realm made
    // it, whose own prototype is null, or it has none.
    var proto = Object.getPrototypeOf(value);
    if (Object.prototype.toString.call(value) !== "[object Object]" || (proto !== null && Object.getPrototypeOf(proto) !== null))
        return false;
    var keys = Object.keys(value);
    for (var k = 0; k < keys.length; k++)
        if (!isPlainJson(value[keys[k]])) return false;
    return true;
}

// Whether `value` fits a status entry of type `type`: `presence` a key of
// STATUS_PRESENCE_TONES; `presenceList` a list statusListItemFits admits
// item by item, at most STATUS_LIST_MAX long; `state` { tone, text, action? }
// with a tone of STATUS_STATE_TONES, a printable text and a boolean
// `action` when present; `text` a printable line; `count`
// a whole number from 0; `time` a whole number of milliseconds since the
// Unix epoch, from 0; `data` plain JSON; `choices` a bounded list of labeled,
// distinct, non-empty string ids.
function statusValueFits(type, value) {
    if (type === "presence") return typeof value === "string" && hasOwn(STATUS_PRESENCE_TONES, value);
    if (type === "presenceList") {
        if (!Array.isArray(value) || value.length > STATUS_LIST_MAX) return false;
        for (var n = 0; n < value.length; n++)
            if (!statusListItemFits(value[n])) return false;
        return true;
    }
    if (type === "launcherRows") {
        if (!Array.isArray(value) || value.length > LAUNCHER_ROWS_MAX) return false;
        var seenLauncherIds = [];
        var launcherMenus = [];
        for (var r = 0; r < value.length; r++) {
            var item = value[r];
            if (!launcherRowFits(item)) return false;
            if (seenLauncherIds.indexOf(item.id) !== -1) return false;
            var dot = item.id.lastIndexOf(".");
            if (dot >= 0 && launcherMenus.indexOf(item.id.substring(0, dot)) === -1) return false;
            seenLauncherIds.push(item.id);
            if (item.menu === true) launcherMenus.push(item.id);
        }
        return true;
    }
    if (type === "choices") {
        if (!Array.isArray(value) || value.length > STATUS_LIST_MAX) return false;
        var seen = [];
        for (var c = 0; c < value.length; c++) {
            var choice = value[c];
            if (!isPlainObject(choice) || !isPlainJson(choice)) return false;
            if (Object.keys(choice).some(function (key) { return STATUS_CHOICE_KEYS.indexOf(key) === -1; })) return false;
            if (!isPrintableLine(choice.label, STATUS_LABEL_MAX)) return false;
            if (!isPrintableLine(choice.value, STATUS_TEXT_MAX)) return false;
            if (seen.indexOf(choice.value) !== -1) return false;
            seen.push(choice.value);
        }
        return true;
    }
    if (type === "state") {
        if (!isPlainObject(value) || !isPlainJson(value)) return false;
        var keys = Object.keys(value);
        for (var i = 0; i < keys.length; i++)
            if (STATUS_STATE_KEYS.indexOf(keys[i]) === -1) return false;
        return typeof value.tone === "string" && hasOwn(STATUS_STATE_TONES, value.tone) && isPrintableLine(value.text, STATUS_TEXT_MAX)
            && (value.lines === undefined || (Array.isArray(value.lines) && value.lines.length > 0 && value.lines.length <= STATUS_LIST_MAX
                && value.lines.every(function (line) { return isPrintableLine(line, STATUS_TEXT_MAX); })))
            && (value.hint === undefined || isPrintableLine(value.hint, STATUS_HINT_MAX))
            && (value.action === undefined || typeof value.action === "boolean" || typeof value.action === "string");
    }
    if (type === "text") return isPrintableLine(value, STATUS_TEXT_MAX);
    if (type === "count" || type === "time") return typeof value === "number" && isFinite(value) && value >= 0 && Math.floor(value) === value && value <= Number.MAX_SAFE_INTEGER;
    if (type === "data") return isPlainJson(value);
    throw new Error("statusValueFits: status type " + JSON.stringify(type) + " passed validation but has no rule");
}

// Whether `item` is one item of a `presenceList` value: plain JSON holding
// only STATUS_LIST_ITEM_KEYS, a printable `label` of at most
// STATUS_LABEL_MAX characters, a `value` of STATUS_PRESENCE_TONES, and when
// present a printable `hint` of at most STATUS_HINT_MAX and a `secret` of
// SECRET_ACCOUNT_PATTERN.
function statusListItemFits(item) {
    if (!isPlainObject(item) || !isPlainJson(item)) return false;
    var keys = Object.keys(item);
    for (var i = 0; i < keys.length; i++)
        if (STATUS_LIST_ITEM_KEYS.indexOf(keys[i]) === -1) return false;
    return isPrintableLine(item.label, STATUS_LABEL_MAX)
        && typeof item.value === "string" && hasOwn(STATUS_PRESENCE_TONES, item.value)
        && (item.hint === undefined || isPrintableLine(item.hint, STATUS_HINT_MAX))
        && (item.secret === undefined || (typeof item.secret === "string" && SECRET_ACCOUNT_PATTERN.test(item.secret)));
}

// Whether item is one row of a launcherRows status value. It is JSON with
// only row fields the launcher can render or activate. Parent existence and
// duplicate ids are list-level rules in statusValueFits.
function launcherRowFits(item) {
    if (!isPlainObject(item) || !isPlainJson(item)) return false;
    var keys = Object.keys(item);
    for (var i = 0; i < keys.length; i++)
        if (LAUNCHER_ROW_KEYS.indexOf(keys[i]) === -1) return false;
    return typeof item.id === "string" && MENU_ID_PATTERN.test(item.id)
        && isPrintableLine(item.label, MENU_TEXT_MAX)
        && typeof item.icon === "string" && hasOwn(Lucide.ICONS, item.icon)
        && (item.description === undefined || isPrintableLine(item.description, MENU_DESCRIPTION_MAX))
        && (item.aliases === undefined || (Array.isArray(item.aliases) && item.aliases.every(function (alias) { return isPrintableLine(alias, MENU_TEXT_MAX); })))
        && (item.menu === undefined || typeof item.menu === "boolean");
}

// A deep-frozen copy of plain JSON, so the writer cannot reach a published
// value. The QML engine lets a frozen array be written in place, so
// PluginStatus hands each reader a copy of its own.
function frozenJson(value) {
    var copy = JSON.parse(JSON.stringify(value));
    var freeze = function (node) {
        if (node === null || typeof node !== "object") return node;
        var keys = Object.keys(node);
        for (var i = 0; i < keys.length; i++) freeze(node[keys[i]]);
        return Object.freeze(node);
    };
    return freeze(copy);
}

// The one keyed line a refused status write answers:
// `refused: status=<key> reason=<reason>`, a key STATUS_KEY_PATTERN does not
// admit written as JSON so the line stays one line.
function statusRefusal(key, reason) {
    var named = typeof key === "string" && STATUS_KEY_PATTERN.test(key) ? key : JSON.stringify(String(key));
    return "refused: status=" + named + " reason=" + reason;
}

// One status write by a plugin whose validated manifest is `manifest` and
// whose published values are `values`: { ok: true, values, bytes } with
// the new deep-frozen values and their size, or { ok: false, error } with
// the one keyed line `refused: status=<key> reason=<reason>`, the reason
// `undeclared` (the manifest's `status` has no such key), `type` (the value
// does not fit the entry's type) or `size` (the values would pass
// STATUS_MAX_BYTES). A refused write leaves `values` as they were.
function statusWrite(manifest, values, key, value) {
    var refused = function (reason) { return { ok: false, error: statusRefusal(key, reason) }; };
    if (typeof key !== "string" || !hasOwn(manifest.status, key))
        return refused("undeclared");
    if (value === null && manifest.status[key].type !== "data") {
        var cleared = {};
        var kept = Object.keys(values);
        for (var c = 0; c < kept.length; c++)
            if (kept[c] !== key) cleared[kept[c]] = values[kept[c]];
        return { ok: true, values: frozenJson(cleared), bytes: SettingValues.utf8Bytes(JSON.stringify(cleared)) };
    }
    if (!statusValueFits(manifest.status[key].type, value) || !statusDeclarationFits(manifest, manifest.status[key], value))
        return refused("type");
    var next = {};
    var keys = Object.keys(values);
    for (var i = 0; i < keys.length; i++) next[keys[i]] = values[keys[i]];
    next[key] = value;
    var bytes = SettingValues.utf8Bytes(JSON.stringify(next));
    if (bytes > STATUS_MAX_BYTES)
        return refused("size");
    return { ok: true, values: frozenJson(next), bytes: bytes };
}

// Whether VALUE, which statusValueFits admitted for ENTRY's type, also fits
// what MANIFEST declares: a `state` value carries a boolean `action` only
// for an entry that declares an action and a name only for an entry whose
// `actions` hold it, and a `presenceList` item carries `secret` only for a
// manifest that declares `secrets`.
function statusDeclarationFits(manifest, entry, value) {
    if (entry.type === "state") {
        if (value.action === undefined) return true;
        if (typeof value.action === "string") return entry.actions !== undefined && hasOwn(entry.actions, value.action);
        return entry.action !== undefined;
    }
    if (entry.type === "presenceList") return manifest.secrets !== undefined || value.every(function (item) { return item.secret === undefined; });
    return true;
}

// Whether the Settings window draws status entry `entry`: every type but
// `data` and `choices`, unless the entry is `hidden`. Choices feed editors.
function statusDisplayable(entry) {
    return entry.type !== "data" && entry.type !== "choices" && entry.type !== "launcherRows" && entry.hidden !== true;
}

// Select models keyed by string setting name. Only accepted status enters
// here. Neither a new list nor an absent configured id writes settings.
// Settings choices: docs/architecture/design-system.md § Settings pages.
function settingChoices(manifest, values, settings) {
    var out = {};
    var choices = function (from, configured) {
        var offered = hasOwn(values, from) ? values[from] : [];
        var model = offered.length === 0 ? [] : [{ label: "First offered: " + offered[0].label, value: "" }];
        offered.forEach(function (choice) { model.push({ label: choice.label, value: choice.value }); });
        if (configured !== "" && !offered.some(function (choice) { return choice.value === configured; }))
            model.push({ label: configured + " (unavailable)", value: configured });
        return model;
    };
    Object.keys(manifest.schema).forEach(function (key) {
        var entry = manifest.schema[key];
        if (entry.type === "list") out[key] = Pads.listChoices(entry, settings[key], choices);
        else if (entry.optionsFrom !== undefined) out[key] = choices(entry.optionsFrom, settings[key]);
    });
    return frozenJson(out);
}

// The badge tone Settings draws a reported status value with: the
// presence's or the state's tone, "" for a type drawn as text and for a
// `presenceList`, whose items carry their own (statusRowValue).
function statusTone(type, value) {
    if (type === "presence") return STATUS_PRESENCE_TONES[value];
    if (type === "state") return STATUS_STATE_TONES[value.tone];
    return "";
}

// A reported value as a Status row carries it: a `presenceList`'s items
// each as { label, value, hint, tone, secret, access }, `hint` and `secret`
// "" when the item omits them, `tone` its presence's, and `access` what the
// page offers for its secret, SECRET_ACCESS by its presence, "" for an item
// without one; any other value as published.
function statusRowValue(type, value) {
    if (type !== "presenceList") return value;
    return value.map(function (item) {
        return {
            label: item.label,
            value: item.value,
            hint: item.hint === undefined ? "" : item.hint,
            tone: STATUS_PRESENCE_TONES[item.value],
            secret: item.secret === undefined ? "" : item.secret,
            access: item.secret === undefined ? "" : SECRET_ACCESS[item.value]
        };
    });
}

// The action of status entry ENTRY that applies to its published VALUE, or
// null: its declared `action` for a `presence` while nothing is there,
// `absent`, and for a `state` while its writer says so, `action: true`; the
// one of its declared `actions` a `state` value names (D061).
function statusActionOffered(entry, value) {
    switch (entry.type) {
    case "presence": return value === "absent" ? entry.action : null;
    case "state":
        if (entry.actions !== undefined) return typeof value.action === "string" ? entry.actions[value.action] : null;
        return value.action === true ? entry.action : null;
    }
    throw new Error("statusActionOffered: status type " + JSON.stringify(entry.type) + " takes no action");
}

// What a Status row carries of ENTRY's step for its published VALUE, null
// while unreported: null for an entry that declares none, else { label,
// offered, tui }, the label of the action that applies, STATUS_WITHHELD_LABEL
// while that action's TUI lacks the requirements LACKING, or of the entry's one
// `action` while it does not, "" for `actions` none of which applies, and
// `tui` the plugin's own TUI the offered action opens, "" while none is
// offered or it opens none, so a page can draw that TUI's button as the step.
function statusRowAction(entry, value, lacking) {
    if (entry.action === undefined && entry.actions === undefined) return null;
    var offered = value === null ? null : statusActionOffered(entry, value);
    if (offered !== null) return { label: lacking.length > 0 ? STATUS_WITHHELD_LABEL : offered.label, offered: true, tui: offered.tui === undefined ? "" : offered.tui };
    return { label: entry.action === undefined ? "" : entry.action.label, offered: false, tui: "" };
}

// The label a Status row's button reads while the TUI its action opens
// lacks a command it needs; the press opens the requirement notice.
var STATUS_WITHHELD_LABEL = "Install requirements";

// The requirements MANIFEST's TUI that status ENTRY offers for its published
// VALUE needs and MISSING holds, [] while it offers no TUI.
function statusActionLacking(manifest, entry, value, missing) {
    if (value === null || (entry.action === undefined && entry.actions === undefined)) return [];
    var offered = statusActionOffered(entry, value);
    return offered !== null && offered.tui !== undefined ? tuiMissingRequirements(manifest, offered.tui, missing) : [];
}

// The hint of a Status row whose action is withheld for the requirements
// LACKING: what is missing and that the offered button installs it, in
// place of the entry's hint and its state's text, which name the withheld
// action.
function statusWithheldHint(lacking) {
    var one = lacking.length === 1;
    return requirementNames(lacking) + (one ? " is" : " are") + " missing. " + STATUS_WITHHELD_LABEL + " installs " + (one ? "it." : "them.");
}

// The requirement names NAMES as a person reads a list: `a`, `a and b`,
// `a, b and c`.
function requirementNames(names) {
    return names.length === 1 ? names[0] : names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
}

// Why a listed TUI's button takes no press while it lacks the requirements
// LACKING, which its press could only install: one line naming them and the
// step that installs them.
function tuiWithheldReason(lacking) {
    return "Needs " + requirementNames(lacking) + ". " + STATUS_WITHHELD_LABEL + " first.";
}

// The Status rows the plugin manager shows for a plugin: one per entry
// statusDisplayable admits, in manifest key order, as { key, type, label,
// group, hint, info, action, report, value, tone }. `group`, `hint` and
// `info` are "" when the manifest omits them. `action` is
// statusRowAction's: null for an entry without one, else { label, offered },
// `offered` false while unreported. `report` is `reported` with the published `value`
// (statusRowValue) and its `tone`, or `unreported` with `value` null and
// `tone` "" while `values` holds nothing for the key. While the offered
// action's TUI lacks a command MISSING holds, `hint` is statusWithheldHint's
// and a `state` value reads STATUS_WITHHELD_STATE with its `action`, so no
// text names the withheld action.
function statusRows(manifest, values, missing) {
    return Object.keys(manifest.status).filter(function (key) {
        return statusDisplayable(manifest.status[key]);
    }).map(function (key) {
        var entry = manifest.status[key];
        var reported = hasOwn(values, key);
        var value = reported ? values[key] : null;
        var lacking = statusActionLacking(manifest, entry, value, missing);
        var hint = entry.type === "state" && value !== null && value.hint !== undefined
            ? value.hint : entry.hint === undefined ? "" : entry.hint;
        if (lacking.length > 0) {
            hint = statusWithheldHint(lacking);
            if (entry.type === "state") value = Object.assign({ action: value.action }, STATUS_WITHHELD_STATE);
        }
        return {
            key: key,
            type: entry.type,
            label: entry.label,
            group: entry.group === undefined ? "" : entry.group,
            hint: hint,
            info: entry.info === undefined ? "" : entry.info,
            action: statusRowAction(entry, value, lacking),
            report: reported ? "reported" : "unreported",
            value: reported ? statusRowValue(entry.type, value) : null,
            tone: reported ? statusTone(entry.type, value) : ""
        };
    });
}

// What a `state` row reads while its action is withheld.
var STATUS_WITHHELD_STATE = { tone: "warning", text: "Requirements missing" };

// The one keyed line a refused status action answers:
// `refused: action=<key> reason=<reason>`, REASON one of
// STATUS_ACTION_REASONS, a key STATUS_KEY_PATTERN does not admit written as
// JSON.
function statusActionRefusal(key, reason) {
    if (STATUS_ACTION_REASONS.indexOf(reason) === -1)
        throw new Error("statusActionRefusal: reason " + JSON.stringify(reason) + " is not one of " + STATUS_ACTION_REASONS.join(", "));
    var named = typeof key === "string" && STATUS_KEY_PATTERN.test(key) ? key : JSON.stringify(String(key));
    return "refused: action=" + named + " reason=" + reason;
}

// The requirements MANIFEST's TUI NAME needs that MISSING holds, in declaration
// order: its `requires`, none when that list is empty, or, for a TUI that
// declares no `requires`, every requirement of the active manifest that is not
// optional.
function tuiMissingRequirements(manifest, name, missing) {
    var requires = manifest.tui[name].requires;
    var needed = requires !== null ? requires : manifest.requirements.filter(function (row) {
        return !row.optional;
    }).map(function (row) { return row.name; });
    return needed.filter(function (name) { return missing.indexOf(name) !== -1; });
}

// The manager's setup request keeps tuiRun's refusal and focus rules. A valid
// step with missing requirements goes to the existing requirement notice.
function tuiRunFor(manifest, enabled, sourceDir, runner, name, missing) {
    var request = tuiRun(manifest, enabled, sourceDir, runner, name, []);
    if (!request.ok && request.action === "none") return request;
    if (tuiMissingRequirements(manifest, name, missing).length > 0) return { ok: true, kind: "install" };
    return request;
}

// What the `manager` capability's `act(id, key)` does for status entry KEY
// of plugin MANIFEST, null for an id no plugin has, ENABLED and VALUES its
// published values: { ok: true, kind: "tui", name } to open the plugin's own
// TUI NAME, { ok: true, kind: "install", commands } to offer its own
// requirement COMMANDS through the requirement notice, { ok: true, kind:
// "system", args } to open the core TUI `core/system` with ARGS, `apply`
// and its declared step, or { ok: false,
// answer } with `unknown: <id>` or statusActionRefusal's line: `undeclared`
// for an entry without an action, `disabled` for a disabled plugin and
// `not-offered` while the published value does not call for it.
function statusActionRequest(manifest, id, enabled, values, key) {
    if (manifest === null)
        return { ok: false, answer: "unknown: " + tuiLabel(id) };
    if (typeof key !== "string" || !hasOwn(manifest.status, key) || statusEntryActions(manifest.status[key]).length === 0)
        return { ok: false, answer: statusActionRefusal(key, "undeclared") };
    if (!enabled)
        return { ok: false, answer: statusActionRefusal(key, "disabled") };
    var action = hasOwn(values, key) ? statusActionOffered(manifest.status[key], values[key]) : null;
    if (action === null)
        return { ok: false, answer: statusActionRefusal(key, "not-offered") };
    if (action.tui !== undefined)
        return { ok: true, kind: "tui", name: action.tui };
    if (action.system !== undefined)
        return { ok: true, kind: "system", args: ["apply", action.system] };
    return { ok: true, kind: "install", commands: action.install.slice() };
}

// The one keyed line a refused secret write answers:
// `refused: secret=<account> reason=<reason>`, REASON one of
// SECRET_REASONS, an account SECRET_ACCOUNT_PATTERN does not admit written
// as JSON. No secret value enters it.
function secretRefusal(account, reason) {
    if (SECRET_REASONS.indexOf(reason) === -1)
        throw new Error("secretRefusal: reason " + JSON.stringify(reason) + " is not one of " + SECRET_REASONS.join(", "));
    var named = typeof account === "string" && SECRET_ACCOUNT_PATTERN.test(account) ? account : JSON.stringify(String(account));
    return "refused: secret=" + named + " reason=" + reason;
}

// Whether SECRET is a value the core stores: 1 to SECRET_VALUE_MAX
// characters, none a control character, a line separator or a paragraph
// separator.
function secretValueValid(secret) {
    return typeof secret === "string" && secret.length > 0 && secret.length <= SECRET_VALUE_MAX && !/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(secret);
}

// What the `manager` capability's `storeSecret` (VERB `store`, with SECRET)
// or `clearSecret` (VERB `clear`) does for account ACCOUNT of status entry
// KEY of plugin MANIFEST, null for an id no plugin has, ENABLED and VALUES
// its published values. The core writes only an account the plugin itself
// lists: an item of the `presenceList` entry KEY whose `secret` is ACCOUNT,
// and only the verb its access offers, `store` for `connect` and `clear` for
// `disconnect`. { ok: true, argv, input } with the secret-tool argv and the
// text for its stdin, the secret for a store and null for a clear, so no
// secret reaches an argv; or { ok: false, answer } with `unknown: <id>` or
// secretRefusal's line: `undeclared` for a manifest without `secrets` or a
// KEY that is no `presenceList` entry, `disabled`, `unlisted` for an account
// no published item of KEY names, `not-offered` for a verb its access does
// not offer, `value` for a SECRET secretValueValid refuses.
function secretRequest(manifest, id, enabled, values, key, account, verb, secret) {
    if (!hasOwn(SECRET_VERBS, verb))
        throw new Error("secretRequest: verb " + JSON.stringify(verb) + " is not one of " + Object.keys(SECRET_VERBS).join(", "));
    if (manifest === null)
        return { ok: false, answer: "unknown: " + tuiLabel(id) };
    var refused = function (reason) { return { ok: false, answer: secretRefusal(account, reason) }; };
    if (manifest.secrets === undefined || typeof key !== "string" || !hasOwn(manifest.status, key) || manifest.status[key].type !== "presenceList")
        return refused("undeclared");
    if (!enabled)
        return refused("disabled");
    var items = hasOwn(values, key) ? values[key] : [];
    var item = null;
    for (var i = 0; i < items.length; i++)
        if (items[i].secret !== undefined && items[i].secret === account) item = items[i];
    if (item === null)
        return refused("unlisted");
    if (SECRET_ACCESS[item.value] !== SECRET_VERBS[verb])
        return refused("not-offered");
    var attributes = ["service", manifest.secrets.service, "account", account];
    if (verb === "clear")
        return { ok: true, argv: ["secret-tool", "clear"].concat(attributes), input: null };
    if (!secretValueValid(secret))
        return refused("value");
    return { ok: true, argv: ["secret-tool", "store", "--label=" + manifest.secrets.label + " " + account].concat(attributes), input: secret };
}

// A Hyprland key written `MOD+MOD+KEY`, such as `SUPER+SPACE`, normalised:
// { ok: true, key } with keysyms upper case, `code:<uint32>` lower case,
// the modifiers in
// HYPRLAND_MODIFIERS order, each once, and the key name last, joined by
// `+`; or { ok: false, error }. A manifest's bind and a shell.json `keys`
// entry both pass through here, so two spellings of one key compare equal.
function hyprlandKey(text) {
    if (typeof text !== "string")
        return { ok: false, error: "must be a string such as SUPER+SPACE" };
    var parts = text.split("+").map(function (part) { return part.trim().toUpperCase(); });
    if (parts.some(function (part) { return part.length === 0; }))
        return { ok: false, error: "has an empty part: " + JSON.stringify(text) };
    var name = parts[parts.length - 1];
    if (HYPRLAND_MODIFIERS.indexOf(name) !== -1)
        return { ok: false, error: "ends in the modifier " + name + " and names no key" };
    if (/^CODE:[0-9]+$/.test(name) && Number(name.slice(5)) <= 4294967295)
        name = "code:" + String(Number(name.slice(5)));
    else if (!HYPRLAND_KEY_NAME.test(name))
        return { ok: false, error: "names no key: " + JSON.stringify(name) };
    var mods = parts.slice(0, -1);
    for (var i = 0; i < mods.length; i++) {
        if (HYPRLAND_MODIFIERS.indexOf(mods[i]) === -1)
            return { ok: false, error: "has the unknown modifier " + JSON.stringify(mods[i]) + ", want one of " + HYPRLAND_MODIFIERS.join(", ") };
        if (mods.indexOf(mods[i]) !== i)
            return { ok: false, error: "repeats the modifier " + mods[i] };
    }
    var ordered = HYPRLAND_MODIFIERS.filter(function (mod) { return mods.indexOf(mod) !== -1; });
    return { ok: true, key: ordered.concat([name]).join("+") };
}

// The key capture control's key table: a Qt 6 `Qt::Key` value
// (qnamespace.h) and the keysym name hyprlandKey writes for it. A key
// outside the table, such as a shifted symbol Qt reports by its glyph, is
// unnamed, and the user types it into the text entry instead.
var CAPTURE_KEY_NAMES = (function () {
    var names = {
        0x20: "SPACE", 0x27: "APOSTROPHE", 0x2c: "COMMA", 0x2d: "MINUS", 0x2e: "PERIOD", 0x2f: "SLASH",
        0x3b: "SEMICOLON", 0x3d: "EQUAL", 0x5b: "BRACKETLEFT", 0x5c: "BACKSLASH", 0x5d: "BRACKETRIGHT", 0x60: "GRAVE",
        0x01000001: "TAB", 0x01000002: "TAB", 0x01000003: "BACKSPACE", 0x01000004: "RETURN", 0x01000005: "KP_ENTER",
        0x01000006: "INSERT", 0x01000007: "DELETE", 0x01000008: "PAUSE", 0x01000009: "PRINT", 0x0100000a: "SYS_REQ",
        0x01000010: "HOME", 0x01000011: "END", 0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT", 0x01000015: "DOWN",
        0x01000016: "PAGE_UP", 0x01000017: "PAGE_DOWN", 0x01000055: "MENU",
        0x01000070: "XF86AUDIOLOWERVOLUME", 0x01000071: "XF86AUDIOMUTE", 0x01000072: "XF86AUDIORAISEVOLUME",
        0x01000080: "XF86AUDIOPLAY", 0x01000081: "XF86AUDIOSTOP", 0x01000082: "XF86AUDIOPREV", 0x01000083: "XF86AUDIONEXT",
        0x010000b2: "XF86MONBRIGHTNESSUP", 0x010000b3: "XF86MONBRIGHTNESSDOWN"
    };
    var code;
    for (code = 0x30; code <= 0x39; code++) names[code] = String.fromCharCode(code);
    for (code = 0x41; code <= 0x5a; code++) names[code] = String.fromCharCode(code);
    for (code = 1; code <= 35; code++) names[0x01000030 + code - 1] = "F" + code;
    return names;
})();
// The keys that only modify, by Qt value: Shift, Control, Meta, Alt, the
// two Super keys, AltGr and the three locks, each with the modifier its
// press holds, "" for none.
var CAPTURE_MODIFIER_KEYS = {
    0x01000020: "SHIFT", 0x01000021: "CTRL", 0x01000022: "SUPER", 0x01000023: "ALT",
    0x01000053: "SUPER", 0x01000054: "SUPER", 0x01001103: "", 0x01000024: "", 0x01000025: "", 0x01000026: ""
};
// Each of HYPRLAND_MODIFIERS as a `Qt::KeyboardModifier` flag. Qt reports
// the Super key as the Meta modifier on Linux.
var CAPTURE_MODIFIER_FLAGS = { SUPER: 0x10000000, CTRL: 0x04000000, ALT: 0x08000000, SHIFT: 0x02000000 };
var CAPTURE_KEYPAD_FLAG = 0x20000000;
// The keys Qt reports with `Qt.KeypadModifier`, by Qt value, as the keypad
// keysyms: digits and operators with Num Lock on, the movement keys with
// it off, and Enter. Another key with the flag is unnamed.
var CAPTURE_KEYPAD_NAMES = (function () {
    var names = {
        0x2a: "KP_MULTIPLY", 0x2b: "KP_ADD", 0x2c: "KP_SEPARATOR", 0x2d: "KP_SUBTRACT", 0x2e: "KP_DECIMAL", 0x2f: "KP_DIVIDE", 0x3d: "KP_EQUAL",
        0x01000005: "KP_ENTER", 0x01000006: "KP_INSERT", 0x01000007: "KP_DELETE", 0x0100000b: "KP_BEGIN",
        0x01000010: "KP_HOME", 0x01000011: "KP_END", 0x01000012: "KP_LEFT", 0x01000013: "KP_UP", 0x01000014: "KP_RIGHT", 0x01000015: "KP_DOWN",
        0x01000016: "KP_PRIOR", 0x01000017: "KP_NEXT"
    };
    for (var code = 0x30; code <= 0x39; code++) names[code] = "KP_" + String.fromCharCode(code);
    return names;
})();
// The keys that edit text without typing a character. Qt gives every key
// that types one a value below 0x01000000, its character's code.
var CAPTURE_EDIT_KEYS = ["TAB", "RETURN", "KP_ENTER", "BACKSPACE", "DELETE", "KP_DELETE"];
var CAPTURE_TEXT_BELOW = 0x01000000;

// What one key press the key capture control receives names, from a QML
// KeyEvent's `key` and `modifiers`: { kind: "key", key } with the key
// hyprlandKey writes, so a captured combo is the string the text entry
// stores for the same keys; { kind: "held", modifiers } while only
// modifiers are down, in HYPRLAND_MODIFIERS order; { kind: "text" } for a
// key that types or edits text with no modifier but SHIFT, which a global
// bind would take from every text field; or { kind: "unnamed" } for a key
// neither table names.
function capturedKey(key, modifiers) {
    var held = HYPRLAND_MODIFIERS.filter(function (mod) {
        return (modifiers & CAPTURE_MODIFIER_FLAGS[mod]) !== 0 || CAPTURE_MODIFIER_KEYS[key] === mod;
    });
    if (hasOwn(CAPTURE_MODIFIER_KEYS, key))
        return { kind: "held", modifiers: held };
    var names = (modifiers & CAPTURE_KEYPAD_FLAG) !== 0 ? CAPTURE_KEYPAD_NAMES : CAPTURE_KEY_NAMES;
    if (!hasOwn(names, key))
        return { kind: "unnamed" };
    var typesText = key < CAPTURE_TEXT_BELOW || CAPTURE_EDIT_KEYS.indexOf(names[key]) !== -1;
    if (typesText && held.every(function (mod) { return mod === "SHIFT"; }))
        return { kind: "text" };
    return { kind: "key", key: hyprlandKey(held.concat([names[key]]).join("+")).key };
}

// Who else asks for KEY, the key a capture or the text entry gives
// shortcut SHORTCUT of plugin ID: { plugins: [{ id, shortcut }], user },
// the plugins, by id, from the key each bind of SECTIONS asks for, whether
// or not the layer's first-by-id rule (HyprlandLayer.resolveBinds) gives it
// the key, so a key that would take another plugin's bind names it; and
// whether FOREIGN, the keys something other than the layer binds
// (HyprlandState.foreignBinds), holds it. A hint: nothing refuses the key.
function keyConflicts(key, sections, foreign, id, shortcut) {
    var parsed = hyprlandKey(key);
    var plugins = [];
    sections.slice().sort(function (a, b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; }).forEach(function (section) {
        section.binds.forEach(function (bind) {
            if (bind.key === parsed.key && !(section.id === id && bind.shortcut === shortcut))
                plugins.push({ id: section.id, shortcut: bind.shortcut });
        });
    });
    return { plugins: plugins, user: parsed.ok && foreign.indexOf(parsed.key) !== -1 };
}

// The hint a key field draws under its key, from FOUND, keyConflicts'
// answer with `binds`, the state of the read of the user's binds
// (`unread`, `read` or `failed`), and `userBinds`, where the user's
// configuration binds the key ([{ place, line }], HyprlandState), beside
// it: each plugin that asks for the key by its name in NAMES (plugin id ->
// name; the id where NAMES has none) with the shortcut, then the user's own
// binds, by file and line where the layer recorded them, and whether those
// could not be read. "" when nobody else asks and the read did not fail.
// Every surface that shows a key draws this one line.
function conflictHint(found, names) {
    var places = (found.userBinds || []).map(function (row) { return row.place + " line " + row.line; });
    var holders = found.plugins.map(function (p) {
        return (hasOwn(names, p.id) ? names[p.id] : p.id) + " (" + p.shortcut + ")";
    }).concat(!found.user ? [] : places.length > 0 ? ["your Hyprland config at " + places.join(" and ")] : ["your other shortcuts"]);
    var unread = found.binds === "failed";
    if (holders.length === 0) return unread ? "VGS could not check your other shortcuts." : "";
    return "Also used by " + holders.join(", ") + (unread ? " (VGS could not check other shortcuts)." : ".");
}

function keyValueError(value, at, tap) {
    var values = Array.isArray(value) ? value : [value];
    if (Array.isArray(value) && value.length === 0)
        return at + " must not be an empty list";
    var seen = Object.create(null);
    for (var i = 0; i < values.length; i++) {
        var itemAt = Array.isArray(value) ? at + "." + i : at;
        var key = hyprlandKey(values[i]);
        if (!key.ok)
            return itemAt + " " + key.error;
        if (seen[key.key] !== undefined)
            return itemAt + " repeats " + key.key;
        if (tap === true && keyHasModifiers(key.key))
            return itemAt + " tap-lone-key";
        seen[key.key] = true;
    }
    return "";
}

function keyValues(value) {
    return (Array.isArray(value) ? value : [value]).map(function (item) { return hyprlandKey(item).key; });
}

function keyWriteValue(value) {
    var keys = keyValues(value);
    return keys.length === 1 ? keys[0] : keys;
}

function keyRowValue(value) {
    return value === null ? null : keyWriteValue(value);
}

// The first defect of a plugins row's `keys`, or "": an object whose names
// are shortcut names and whose values are keys hyprlandKey accepts, a
// non-empty list of those keys, or null for a shortcut the user unbinds. A
// name the plugin binds nothing under is no defect here; the Hyprland layer
// reports it (hyprlandSection).
function keysError(keys, at) {
    if (!isPlainObject(keys))
        return at + " must be an object";
    var names = Object.keys(keys);
    for (var i = 0; i < names.length; i++) {
        if (!NAME_PATTERN.test(names[i]))
            return at + "." + names[i] + " is not a shortcut name";
        if (keys[names[i]] === null)
            continue;
        var bad = keyValueError(keys[names[i]], at + "." + names[i], false);
        if (bad !== "")
            return bad;
    }
    return "";
}

function keyHasModifiers(key) {
    return typeof key === "string" && key.indexOf("+") !== -1;
}

// The first defect of a manifest's `hyprland` key, or "". It holds `binds`,
// a list of { shortcut, key, hold?, tap?, info? } whose key is one key, a list of
// keys as a plugins row's `keys` takes, or null, `layerRules`, a list of
// { namespace, blur, ignoreAlpha }, and `appearance`, an object mapping the
// fixed theme-appearance groups to boolean settings in this manifest. A bind's
// shortcut is a name the plugin registers through its `shortcut` capability,
// which the manifest must name, so a plugin binds only its own shortcuts. A
// rule matches `^vgs:<name>$` and sets blur, ignoreAlpha from 0 to 1, or
// both. Appearance needs the `theme` capability because those switches change
// how the theme reaches Hyprland. Options need the `hyprland` capability
// because the same plugin must read the compositor state back. Monitors
// need the `monitors` capability and name a plugin settings key without a
// schema row, so the Settings page does not draw it.
// Neither a shortcut, a key nor a namespace appears twice.
function hyprlandError(hyprland, capabilities, schema) {
    if (!isPlainObject(hyprland))
        return "hyprland must be an object";
    var keys = Object.keys(hyprland);
    for (var u = 0; u < keys.length; u++) {
        if (HYPRLAND_KEYS.indexOf(keys[u]) === -1)
            return "hyprland has unknown key " + JSON.stringify(keys[u]);
    }
    var binds = hyprland.binds === undefined ? [] : hyprland.binds;
    var rules = hyprland.layerRules === undefined ? [] : hyprland.layerRules;
    var appearance = hyprland.appearance;
    var options = hyprland.options;
    var monitors = hyprland.monitors;
    if (!Array.isArray(binds))
        return "hyprland.binds must be a list";
    if (!Array.isArray(rules))
        return "hyprland.layerRules must be a list";
    if (binds.length === 0 && rules.length === 0 && appearance === undefined && options === undefined && hyprland.pads === undefined && monitors === undefined)
        return "hyprland declares no binds, layer rules, appearance, options, pads or monitors";
    if (binds.length > 0 && capabilities.indexOf("shortcut") === -1)
        return "hyprland.binds needs capability shortcut";
    var shortcuts = [];
    var boundKeys = [];
    for (var b = 0; b < binds.length; b++) {
        var bind = binds[b];
        var at = "hyprland.binds." + b;
        if (!isPlainObject(bind))
            return at + " must be an object";
        var bindKeys = Object.keys(bind);
        for (var k = 0; k < bindKeys.length; k++) {
            if (HYPRLAND_BIND_KEYS.indexOf(bindKeys[k]) === -1)
                return at + " has unknown key " + JSON.stringify(bindKeys[k]);
        }
        if (typeof bind.shortcut !== "string" || !NAME_PATTERN.test(bind.shortcut))
            return at + ".shortcut must be a shortcut name, got " + JSON.stringify(bind.shortcut);
        if (shortcuts.indexOf(bind.shortcut) !== -1)
            return at + ".shortcut " + bind.shortcut + " is bound twice";
        shortcuts.push(bind.shortcut);
        if (bind.hold !== undefined && typeof bind.hold !== "boolean")
            return at + ".hold must be a boolean";
        if (bind.tap !== undefined && typeof bind.tap !== "boolean")
            return at + ".tap must be a boolean";
        if (bind.tap === true && bind.hold === true)
            return at + " must not set tap and hold together";
        if (bind.info !== undefined && (typeof bind.info !== "string" || bind.info.length === 0))
            return at + ".info must be a non-empty string";
        if (bind.key === null)
            continue;
        var keyBad = keyValueError(bind.key, at + ".key", false);
        if (keyBad !== "")
            return keyBad;
        var values = keyValues(bind.key);
        for (var v = 0; v < values.length; v++) {
            var keyAt = Array.isArray(bind.key) ? at + ".key." + v : at + ".key";
            if (bind.tap === true && keyHasModifiers(values[v]))
                return keyAt + " " + values[v] + " must be a lone key for tap";
            if (boundKeys.indexOf(values[v]) !== -1)
                return keyAt + " " + values[v] + " is bound twice";
            boundKeys.push(values[v]);
        }
    }
    var namespaces = [];
    for (var r = 0; r < rules.length; r++) {
        var rule = rules[r];
        var where = "hyprland.layerRules." + r;
        if (!isPlainObject(rule))
            return where + " must be an object";
        var ruleKeys = Object.keys(rule);
        for (var q = 0; q < ruleKeys.length; q++) {
            if (HYPRLAND_RULE_KEYS.indexOf(ruleKeys[q]) === -1)
                return where + " has unknown key " + JSON.stringify(ruleKeys[q]);
        }
        if (typeof rule.namespace !== "string" || !HYPRLAND_NAMESPACE.test(rule.namespace))
            return where + ".namespace must be ^vgs:<name>$, got " + JSON.stringify(rule.namespace);
        if (namespaces.indexOf(rule.namespace) !== -1)
            return where + ".namespace " + rule.namespace + " has a rule already";
        namespaces.push(rule.namespace);
        if (rule.blur === undefined && rule.ignoreAlpha === undefined)
            return where + " sets neither blur nor ignoreAlpha";
        if (rule.blur !== undefined && typeof rule.blur !== "boolean")
            return where + ".blur must be a boolean";
        if (rule.ignoreAlpha !== undefined && (typeof rule.ignoreAlpha !== "number" || !isFinite(rule.ignoreAlpha) || rule.ignoreAlpha < 0 || rule.ignoreAlpha > 1))
            return where + ".ignoreAlpha must be a number from 0 to 1";
    }
    if (appearance !== undefined) {
        if (!isPlainObject(appearance) || Object.keys(appearance).length === 0)
            return "hyprland.appearance must be a non-empty object";
        if (capabilities.indexOf("theme") === -1)
            return "hyprland.appearance needs capability theme";
        var appearanceKeys = Object.keys(appearance);
        for (var a = 0; a < appearanceKeys.length; a++) {
            var group = appearanceKeys[a];
            var at = "hyprland.appearance." + group;
            if (HYPRLAND_APPEARANCE_GROUPS.indexOf(group) === -1)
                return at + " must be one of " + HYPRLAND_APPEARANCE_GROUPS.join(", ");
            var setting = appearance[group];
            if (typeof setting !== "string" || setting.length === 0)
                return at + " must name a boolean schema entry";
            if (!hasOwn(schema, setting))
                return at + " names no schema entry " + JSON.stringify(setting);
            if (schema[setting].type !== "boolean")
                return at + " must name a boolean schema entry, got " + schema[setting].type;
        }
    }
    var padsBad = Pads.manifestError(hyprland.pads, capabilities, schema);
    if (padsBad !== "")
        return padsBad;
    if (options !== undefined && capabilities.indexOf("hyprland") === -1)
        return "hyprland.options needs capability hyprland";
    if (options !== undefined)
        return hyprlandOptionsError(options, schema);
    if (monitors !== undefined && capabilities.indexOf("monitors") === -1)
        return "hyprland.monitors needs capability monitors";
    if (monitors !== undefined) {
        if (typeof monitors !== "string" || !STATUS_KEY_PATTERN.test(monitors))
            return "hyprland.monitors must name a settings key";
    }
    return "";
}

// The first defect of a manifest's `hyprland.options`, or "": a non-empty
// object mapping a schema setting to a path of HyprlandLayer.OPTIONS, each
// path once, the setting's entry of the path's type (optionSchemaError).
function hyprlandOptionsError(options, schema) {
    if (!isPlainObject(options) || Object.keys(options).length === 0)
        return "hyprland.options must be a non-empty object";
    var names = Object.keys(options);
    var paths = [];
    for (var i = 0; i < names.length; i++) {
        var name = names[i];
        var path = options[name];
        var at = "hyprland.options." + name;
        if (!STATUS_KEY_PATTERN.test(name))
            return at + " must be a setting name";
        if (typeof path !== "string" || !hasOwn(HyprlandLayer.OPTIONS, path))
            return at + " must be one of " + Object.keys(HyprlandLayer.OPTIONS).join(", ") + ", got " + JSON.stringify(path);
        if (paths.indexOf(path) !== -1)
            return at + " sets " + path + ", which another setting sets already";
        paths.push(path);
        if (!hasOwn(schema, name))
            return at + " names no schema entry " + JSON.stringify(name);
        var bad = optionSchemaError(HyprlandLayer.OPTIONS[path], schema[name]);
        if (bad !== "")
            return at + " " + bad;
    }
    return "";
}

// Why schema ENTRY cannot hold option row ROW's values, or "": a `bool`
// takes a boolean; an `int` or a `float` a number whose `min` and `max` lie
// in the row's range, whole with a whole `step` for an `int`; a string with
// `choices` an enum whose options are among them; any other string a string
// or an enum.
function optionSchemaError(row, entry) {
    switch (row.type) {
    case "bool":
        return entry.type === "boolean" ? "" : "needs a boolean schema entry, got " + entry.type;
    case "int":
    case "float":
        if (entry.type !== "number")
            return "needs a number schema entry, got " + entry.type;
        if (entry.min === undefined || entry.max === undefined || entry.min < row.min || entry.max > row.max)
            return "needs min and max within " + row.min + " to " + row.max;
        if (row.type === "int" && !(Number.isInteger(entry.min) && Number.isInteger(entry.max) && (entry.step === undefined || Number.isInteger(entry.step))))
            return "needs a whole min, max and step";
        return "";
    case "string":
        if (row.choices === undefined)
            return entry.type === "string" || entry.type === "enum" ? "" : "needs a string or enum schema entry, got " + entry.type;
        if (entry.type !== "enum")
            return "needs an enum schema entry, got " + entry.type;
        for (var o = 0; o < entry.options.length; o++) {
            if (row.choices.indexOf(entry.options[o]) === -1)
                return "offers " + JSON.stringify(entry.options[o]) + ", not one of " + row.choices.join(", ");
        }
        return "";
    }
    throw new Error("optionSchemaError: option type " + JSON.stringify(row.type) + " has no rule");
}

function dbusNameValid(name) {
    if (typeof name !== "string" || name.length > 255 || name[0] === ":" || name[0] === ".")
        return false;
    var parts = name.split(".");
    return parts.length >= 2 && parts.every(function (part) { return DBUS_NAME_PART.test(part); });
}

function requirementIdentity(requirement, at) {
    var hasCommand = hasOwn(requirement, "command");
    var hasDbus = hasOwn(requirement, "dbus");
    if (hasCommand === hasDbus)
        return { ok: false, error: at + " must name exactly one of command or dbus" };
    if (hasCommand) {
        if (!PackageManagers.validCommand(requirement.command))
            return { ok: false, error: at + ".command must be a bare command name looked up on PATH, got " + JSON.stringify(requirement.command) };
        if (ID_PATTERN.test(requirement.command))
            return { ok: false, error: at + ".command " + JSON.stringify(requirement.command) + " is spelt as a plugin id: a requirement names a command or D-Bus name, never a plugin (D005)" };
        return { ok: true, at: at + ".command", name: requirement.command };
    }
    if (!isPlainObject(requirement.dbus))
        return { ok: false, error: at + ".dbus must be an object" };
    var keys = Object.keys(requirement.dbus);
    for (var k = 0; k < keys.length; k++) {
        if (REQUIREMENT_DBUS_KEYS.indexOf(keys[k]) === -1)
            return { ok: false, error: at + ".dbus has unknown key " + JSON.stringify(keys[k]) };
    }
    if (REQUIREMENT_BUSES.indexOf(requirement.dbus.bus) === -1)
        return { ok: false, error: at + ".dbus.bus must be one of system, session, got " + JSON.stringify(requirement.dbus.bus) };
    if (!dbusNameValid(requirement.dbus.name))
        return { ok: false, error: at + ".dbus.name must be a well-known D-Bus name, got " + JSON.stringify(requirement.dbus.name) };
    return { ok: true, at: at + ".dbus.name", name: requirement.dbus.name };
}

// The first defect of a `requirements` list, or "": a manifest's key and
// the core's own config/requirements.json both pass through here. Each
// entry is an object of REQUIREMENT_KEYS and names exactly one identity:
// `command`, a bare command name PackageManagers.validCommand accepts, or
// `dbus`, a well-known name on the system or session bus. The identity is
// declared once, and never names a plugin (D005). `packages`, when present,
// is an object whose keys are manager ids of PackageManagers.MANAGERS and
// whose values are package names PackageManagers.validName accepts;
// `optional`, when present, is a boolean; `purpose` is one printable line
// of 1 to REQUIREMENT_PURPOSE_MAX characters.
function requirementsError(requirements) {
    if (!Array.isArray(requirements))
        return "requirements must be a list";
    var names = [];
    for (var i = 0; i < requirements.length; i++) {
        var requirement = requirements[i];
        var at = "requirements." + i;
        if (!isPlainObject(requirement))
            return at + " must be an object";
        var keys = Object.keys(requirement);
        for (var k = 0; k < keys.length; k++) {
            if (REQUIREMENT_KEYS.indexOf(keys[k]) === -1)
                return at + " has unknown key " + JSON.stringify(keys[k]);
        }
        var identity = requirementIdentity(requirement, at);
        if (!identity.ok)
            return identity.error;
        if (names.indexOf(identity.name) !== -1)
            return identity.at + " " + JSON.stringify(identity.name) + " is declared twice";
        names.push(identity.name);
        if (requirement.packages !== undefined) {
            if (!isPlainObject(requirement.packages))
                return at + ".packages must be an object of manager ids to package names";
            var managers = Object.keys(requirement.packages);
            for (var m = 0; m < managers.length; m++) {
                if (PackageManagers.managerRow(managers[m]) === null)
                    return at + ".packages names the unknown manager " + JSON.stringify(managers[m]) + ", want one of " + PackageManagers.MANAGERS.map(function (row) { return row.id; }).join(", ");
                if (!PackageManagers.validName(requirement.packages[managers[m]]))
                    return at + ".packages." + managers[m] + " must be a package name: printable ASCII without a space, not starting with -, got " + JSON.stringify(requirement.packages[managers[m]]);
            }
        }
        if (requirement.optional !== undefined && typeof requirement.optional !== "boolean")
            return at + ".optional must be a boolean when present";
        if (typeof requirement.purpose !== "string" || requirement.purpose.trim().length === 0 || Array.from(requirement.purpose).length > REQUIREMENT_PURPOSE_MAX || CONTROL_CHARACTER.test(requirement.purpose))
            return at + ".purpose must be one printable line of 1 to " + REQUIREMENT_PURPOSE_MAX + " characters";
    }
    return "";
}

// A `requirements` list requirementsError accepted, each entry with every
// key: `name`, `bus`, `packages` {} and `optional` false when absent.
function normalRequirements(requirements) {
    return requirements.map(function (entry) {
        return { name: requirementName(entry), bus: entry.dbus === undefined ? null : entry.dbus.bus, packages: entry.packages === undefined ? {} : clone(entry.packages), optional: entry.optional === true, purpose: entry.purpose };
    });
}

// The rows a plugin's requirements are reported as: each normalized entry
// of MANIFEST's `requirements`, in order, with `state` from
// REQUIREMENT_STATES: "missing" when MISSING, the requirement names the
// last scan did not find, names its identity, else "present".
function requirementRows(manifest, missing) {
    return manifest.requirements.map(function (entry) {
        var row = clone(entry);
        row.state = missing.indexOf(entry.name) === -1 ? "present" : "missing";
        return row;
    });
}

// The requirement notice, shell/Core/Notices.qml
// (docs/architecture/commands-are-data.md § Consent). At most NOTICE_QUEUE_MAX plugins hold a notice at once, the
// first shown and the rest waiting. After the user answers a plugin's
// notice Not now, the plugin's own offers are refused for
// NOTICE_OFFER_REST_MS; the install and enable triggers are the user's own
// acts, which no rest refuses. An offer names 1 to NOTICE_OFFER_MAX
// commands. Core policy, like the notify run ceiling.
var NOTICE_QUEUE_MAX = 8;
var NOTICE_OFFER_REST_MS = 600000;
var NOTICE_OFFER_MAX = 16;
// What raises a notice: `installed`, the pluginInstalled IPC function
// `vgshell plugin add` calls; `enabled`, setPluginEnabled turning a plugin on;
// `offered`, the plugin's own `requirements` capability; `requested`, the
// `manager` capability's installRequirements, the Settings window's
// Install; `chosen`, a user's press asking for the core's or an enabled
// plugin's requirements: the `doctor` capability, a view of every owner's
// requirements, and the `manager` capability's act on a status action that
// installs (D061).
var NOTICE_TRIGGERS = ["installed", "enabled", "offered", "requested", "chosen"];
// The owner a notice is raised for when it is the core's own requirements,
// config/requirements.json, rather than a plugin's. A plugin id is dotted,
// so no plugin can take it.
var CORE_OWNER = "core";

// The owner the notice lists the core's requirements for: the shape a
// manifest gives noticeRequest and noticeView, `requirements` the core's
// list as normalRequirements returns it.
function coreOwner(requirements) {
    return { id: CORE_OWNER, name: "VGS", requirements: requirements };
}

// The first reason the `doctor` capability's request for OWNER is refused,
// or "": OWNER is a string, a key of OWNERS, the core's owner and every
// known plugin's manifest by id, and, for a plugin, one of ENABLED, the
// enabled ids, since a disabled plugin's commands run nowhere.
function noticeOwnerError(owner, owners, enabled) {
    if (typeof owner !== "string")
        return "refused: owner=malformed";
    if (!hasOwn(owners, owner))
        return "refused: owner=" + tuiLabel(owner) + " reason=unknown";
    if (owner !== CORE_OWNER && enabled.indexOf(owner) === -1)
        return "refused: owner=" + owner + " reason=disabled";
    return "";
}

// The notice TRIGGER asks for MANIFEST, a plugin's manifest or the core's
// owner, whose requirements MISSING the last scan did not find: { answer,
// commands, required }, `commands` the requirement names the notice lists and
// `required` those whose absence keeps it open. `answer` is "ok",
// "satisfied" when `required` is empty and no notice is due, or a refusal.
// The install and enable triggers list every missing requirement and require
// those the plugin does not mark optional, so a plugin missing only
// optional requirements raises none. A request lists and requires every
// missing requirement, optional ones included, since the user asked to install
// them. An offer, and a choice, lists and requires each of COMMANDS still
// missing, and is refused as
// `refused: requirements=malformed` for anything but a list of 1 to
// NOTICE_OFFER_MAX strings, then as `refused: requirement=<name>
// reason=undeclared` for the first command MANIFEST does not declare, so a
// notice never names a package its owner did not declare.
function noticeRequest(manifest, missing, trigger, commands) {
    var rows = requirementRows(manifest, missing);
    var listed;
    var required;
    switch (trigger) {
    case "installed":
    case "enabled":
    case "requested":
        listed = rows.filter(function (row) { return row.state === "missing"; });
        required = trigger === "requested" ? listed : listed.filter(function (row) { return !row.optional; });
        break;
    case "offered":
    case "chosen":
        if (!Array.isArray(commands) || commands.length === 0 || commands.length > NOTICE_OFFER_MAX || !commands.every(function (c) { return typeof c === "string"; }))
            return { answer: "refused: requirements=malformed", commands: [], required: [] };
        var declared = rows.map(function (row) { return row.name; });
        var undeclared = commands.filter(function (c) { return declared.indexOf(c) === -1; });
        if (undeclared.length > 0)
            return { answer: "refused: requirement=" + tuiLabel(undeclared[0]) + " reason=undeclared", commands: [], required: [] };
        listed = rows.filter(function (row) { return row.state === "missing" && commands.indexOf(row.name) !== -1; });
        required = listed;
        break;
    default:
        throw new Error("notices: trigger " + JSON.stringify(trigger) + " is not one of " + NOTICE_TRIGGERS.join(", "));
    }
    var nameOf = function (row) { return row.name; };
    return { answer: required.length === 0 ? "satisfied" : "ok", commands: listed.map(nameOf), required: required.map(nameOf) };
}

// QUEUE, the notices held, each { id, commands, required }, the first
// shown, after REQUEST, an "ok" noticeRequest for plugin ID raised by
// TRIGGER at NOW, in ms since the epoch: { answer, queue }. A plugin
// holding a notice gets REQUEST's commands merged into it, after those it
// holds, and answers "ok" whatever the trigger, since the user sees one
// notice either way. Otherwise an offer while REST, plugin id -> the end
// of its rest in ms, holds a later end for ID is refused as
// `refused: requirements=<id> reason=resting retry-ms=<ms>`; a queue
// holding NOTICE_QUEUE_MAX notices refuses as
// `refused: notices=full limit=<n>`; and any other request joins the end
// of the queue.
function noticeAdmit(queue, rest, id, request, trigger, now) {
    if (NOTICE_TRIGGERS.indexOf(trigger) === -1)
        throw new Error("notices: trigger " + JSON.stringify(trigger) + " is not one of " + NOTICE_TRIGGERS.join(", "));
    var union = function (held, added) { return held.concat(added.filter(function (c) { return held.indexOf(c) === -1; })); };
    var at = -1;
    for (var i = 0; i < queue.length; i++)
        if (queue[i].id === id) at = i;
    if (at !== -1) {
        var merged = queue.slice();
        merged[at] = { id: id, commands: union(queue[at].commands, request.commands), required: union(queue[at].required, request.required) };
        return { answer: "ok", queue: merged };
    }
    if (trigger === "offered" && hasOwn(rest, id) && rest[id] > now)
        return { answer: "refused: requirements=" + id + " reason=resting retry-ms=" + (rest[id] - now), queue: queue };
    if (queue.length >= NOTICE_QUEUE_MAX)
        return { answer: "refused: notices=full limit=" + NOTICE_QUEUE_MAX, queue: queue };
    return { answer: "ok", queue: queue.concat([{ id: id, commands: request.commands.slice(), required: request.required.slice() }]) };
}

// What NOTICE, { commands, required }, shows for plugin MANIFEST after the
// last scan, whose missing requirements are MISSING, on a system whose managers
// are FOUND, detect's answer, or null when detection has no answer:
// { satisfied, rows, groups, install, byHand }. `satisfied` holds once no
// requirement of `required` is missing. `rows` are the listed requirements
// still missing, in declaration order, each { name, purpose, optional,
// package }, the package PackageManagers.installGroups picks, null with
// FOUND null or when no present manager maps one. `groups` are those rows
// as noticeGroups gathers them. `install` is the arguments after
// `vgshell pkg run install` of the first group whose manager installs, null
// when none does; one Install runs one manager's packages, and the notice
// offers the next group once a rescan finds the first installed.
// `byHand` is each group whose manager installs nothing through vgshell,
// nix, as { manager, names }.
function noticeView(manifest, missing, notice, found) {
    var rows = requirementRows(manifest, missing).filter(function (row) { return row.state === "missing" && notice.commands.indexOf(row.name) !== -1; });
    var satisfied = !notice.required.some(function (c) { return missing.indexOf(c) !== -1; });
    var plan = found === null ? { picks: rows.map(function () { return null; }), groups: [] } : PackageManagers.installGroups(rows, found);
    var installable = plan.groups.filter(function (g) { return g.installs; });
    var install = installable.length === 0 ? null : PackageManagers.installArgs(installable[0]);
    var shown = rows.map(function (row, i) { return { name: row.name, purpose: row.purpose, optional: row.optional, package: plan.picks[i] }; });
    return {
        satisfied: satisfied,
        rows: shown,
        groups: noticeGroups(shown),
        install: install,
        byHand: plan.groups.filter(function (g) { return !g.installs; }).map(function (g) { return { manager: g.manager, names: g.names }; })
    };
}

// ROWS, noticeView's, as the user installs them: one entry per package,
// keyed by its name, or per requirement when no package is known, keyed by
// the requirement's name, in first-appearance order, each { chip, packaged,
// purposes }. Two requirements one package provides read as one thing to
// install, and a package is never merged with a requirement of its name.
function noticeGroups(rows) {
    var out = [];
    rows.forEach(function (row) {
        var packaged = row.package !== null;
        var chip = packaged ? row.package.name : row.name;
        var held = out.filter(function (g) { return g.packaged === packaged && g.chip === chip; })[0];
        if (held === undefined) out.push({ chip: chip, packaged: packaged, purposes: [row.purpose] });
        else held.purposes.push(row.purpose);
    });
    return out;
}

// QUEUE after a scan, the notices of OWNERS, the core's owner and each
// plugin's manifest by id, whose missing requirements MISSING, owner id ->
// requirement names, now holds: a notice whose owner went is dropped, and so is one noticeView finds satisfied, except the
// notice of INSTALLING, the plugin id whose install runs or "". That notice
// stays until the scan after its run ended, however the run's own steps
// asked for a rescan first, so no waiting notice comes to the front while
// its terminal still holds the install's key.
function noticeSettle(queue, owners, missing, installing) {
    return queue.filter(function (n) {
        if (!hasOwn(owners, n.id))
            return false;
        if (n.id === installing)
            return true;
        return !noticeView(owners[n.id], hasOwn(missing, n.id) ? missing[n.id] : [], n, null).satisfied;
    });
}

// The managers `bin/vgshell-pkg detect --json` answered the notice with, from
// its COMPLETION, { code, status } or null for a run that never started,
// its STDOUT and its STDERR: { ok: true, found }, detect's { primary,
// overlays, sources } with each entry a known manager, or { ok: false,
// line }, the log line naming why there is none.
function noticeDetected(completion, stdout, stderr) {
    if (completion === null)
        return { ok: false, line: "notices: detect=unstarted" };
    if (completion.status !== 0 || completion.code !== 0)
        return { ok: false, line: "notices: detect=failed exit=" + completion.code + " status=" + completion.status + " " + stderr.split("\n")[0] };
    var found;
    try {
        found = JSON.parse(stdout);
    } catch (e) {
        return { ok: false, line: "notices: detect=unparseable" };
    }
    var entry = function (e) { return isPlainObject(e) && typeof e.id === "string" && PackageManagers.managerRow(e.id) !== null && typeof e.binary === "string"; };
    if (!isPlainObject(found) || !(found.primary === null || entry(found.primary)) || !Array.isArray(found.overlays) || !found.overlays.every(entry) || !Array.isArray(found.sources) || !found.sources.every(entry))
        return { ok: false, line: "notices: detect=malformed" };
    return { ok: true, found: found };
}

// The welcome the consent slot draws on the shell's first start for a
// user, until the user closes it: its title, the lines for the asking and
// Close-alone states, its cited file, and its one answer when no Hyprland
// question is asked. Its key rows come from the shipped shell.json's
// `welcome.keys`, since the core names no plugin.
var WELCOME = {
    title: "Welcome to VGS",
    firstLine: "VGS is a bar and a set of plugins on top of your Hyprland. Turn plugins on and off from the plugins button at the top right of the bar.",
    connectLine: "Press Connect below to add one line to the top of your hyprland.lua and wire up VGS. That line loads the keys, border colours and blur rules VGS generates. VGS changes nothing else in that file.",
    notNowLine: "Not now leaves hyprland.lua as it is. VGS asks again the next time Hyprland starts.",
    settledLine: "VGS adds one line to the top of your hyprland.lua. It loads a file VGS generates. VGS changes nothing else in that file.",
    link: { text: "hyprland.lua", path: "hypr/hyprland.lua" },
    keysTitle: "Quick commands",
    close: "Close"
};
// What the welcome-seen marker says: `reading` until its read ends, then
// `unseen` or `seen`.
var WELCOME_STATES = ["reading", "unseen", "seen"];
// HyprlandLayer.step's consent phases: the two the welcome waits through,
// on the way to an answer, and the four it shows in.
var WELCOME_WAITS = ["pending", "unwired"];
var WELCOME_SHOWS = ["asking", "wired", "settled", "declined"];
// Each key name CAPTURE_KEY_NAMES gives a printable character, mapped to
// that character: SLASH to `/`, A to `A`. Space prints nothing, so it keeps
// its name.
var KEY_GLYPHS = (function () {
    var glyphs = {};
    Object.keys(CAPTURE_KEY_NAMES).forEach(function (code) {
        var value = Number(code);
        if (value > 0x20 && value < 0x7f) glyphs[CAPTURE_KEY_NAMES[code]] = String.fromCharCode(value);
    });
    return glyphs;
})();

// KEY, a key as hyprlandKey writes it, as people read it: each modifier and
// a named key with only its first letter upper case, a key that types a
// character as that character, and a `code:` key as written, joined by
// `+`. SUPER+SLASH reads Super+/.
function keyLabel(key) {
    return key.split("+").map(function (part) {
        if (hasOwn(KEY_GLYPHS, part)) return KEY_GLYPHS[part];
        if (part.indexOf("code:") === 0) return part;
        return part.charAt(0) + part.slice(1).toLowerCase();
    }).join("+");
}

// What the consent slot draws, or null for nothing. WELCOME_STATE is one of
// WELCOME_STATES; CONSENT is HyprlandLayer.step's consent state. A seen
// welcome leaves the slot to the Hyprland question alone. An unseen one
// waits while the marker is read and while CONSENT is pending or unwired,
// so it never shows Close alone and then turns into a question; it then
// asks that question with Connect and Not now while CONSENT is asking, and
// offers Close alone once CONSENT settled without one. SHIPPED is the
// shipped shell.json: each of its `welcome.keys`, { id, shortcut, text },
// is a key row while SECTIONS, the enabled plugins'
// PluginLogic.hyprlandSection results, bind that shortcut, and no row
// otherwise. The view is { welcome, title, message, lines, link, keys,
// keysTitle, actions, failure, busy }; each action is { label, role,
// answer }, the answer `connect`, `decline` or `close`.
function consentSlotView(consent, welcomeState, shipped, sections) {
    if (WELCOME_STATES.indexOf(welcomeState) === -1)
        throw new Error("consentSlotView: welcome state " + JSON.stringify(welcomeState) + " is not one of " + WELCOME_STATES.join(", "));
    if (WELCOME_WAITS.indexOf(consent.phase) === -1 && WELCOME_SHOWS.indexOf(consent.phase) === -1)
        throw new Error("consentSlotView: consent phase " + JSON.stringify(consent.phase) + " is not one of " + WELCOME_WAITS.concat(WELCOME_SHOWS).join(", "));
    var question = HyprlandLayer.consentView(consent);
    var actions = question === null ? [] : [
        { label: question.actions.connect, role: "accept", answer: "connect" },
        { label: question.actions.decline, role: "cancel", answer: "decline" }
    ];
    if (welcomeState === "reading") return null;
    if (welcomeState === "seen")
        return question === null ? null : { welcome: false, title: question.title, message: question.message, lines: [], link: null, keys: [], keysTitle: "", actions: actions, failure: question.failure, busy: question.busy };
    if (WELCOME_WAITS.indexOf(consent.phase) !== -1) return null;
    var rows = isPlainObject(shipped) && isPlainObject(shipped.welcome) ? shipped.welcome.keys : [];
    var keyRows = rows.map(function (row) {
        var key = HyprlandLayer.shortcutKeys(sections, row.id)[row.shortcut];
        return typeof key === "string" ? { shortcut: keyLabel(key), text: row.text } : null;
    }).filter(function (line) { return line !== null; });
    var asking = question !== null;
    return {
        welcome: true,
        title: WELCOME.title,
        message: "",
        lines: asking ? [WELCOME.firstLine, WELCOME.connectLine, WELCOME.notNowLine] : [WELCOME.firstLine, WELCOME.settledLine],
        link: consent.phase === "settled" ? null : WELCOME.link,
        keys: keyRows,
        keysTitle: WELCOME.keysTitle,
        actions: question === null ? [{ label: WELCOME.close, role: "cancel", answer: "close" }] : actions,
        failure: question === null ? "" : question.failure,
        busy: question !== null && question.busy
    };
}

// The welcome state after EVENT, and whether the welcome-seen marker is
// written now: { welcome, write }. EVENT is { type: "read", seen } once the
// marker's read ends, { type: "answer", answer }, the consent slot's
// answer, or { type: "consent", before, after }, HyprlandLayer.step moving
// the consent state. The user closes an unseen welcome with Close, or
// with a Not now or Escape that declines, the consent going from asking to
// declined, or a Connect that wires, from asking to wired. Until the
// consent moves, the welcome stays, busy, so it never turns into the plain
// question; a Connect that fails keeps it open with the failure.
function welcomeStep(welcomeState, event) {
    var keep = { welcome: welcomeState, write: false };
    var seen = { welcome: "seen", write: true };
    switch (event.type) {
    case "read":
        if (welcomeState !== "reading")
            throw new Error("welcomeStep: a read ended in welcome state " + welcomeState + ", want reading");
        return { welcome: event.seen ? "seen" : "unseen", write: false };
    case "answer":
        switch (event.answer) {
        case "connect":
        case "decline":
            return keep;
        case "close":
            if (welcomeState !== "unseen")
                throw new Error("welcomeStep: close answered in welcome state " + welcomeState + ", want unseen");
            return seen;
        }
        throw new Error("welcomeStep: answer " + JSON.stringify(event.answer) + " is not one of connect, decline, close");
    case "consent":
        return welcomeState === "unseen" && event.before.phase === "asking" && (event.after.phase === "wired" || event.after.phase === "declined") ? seen : keep;
    }
    throw new Error("welcomeStep: unknown event " + JSON.stringify(event.type));
}

// What one entry of a manifest's `tui` key may carry, keyed by a
// NAME_PATTERN name: the script, the window's title, its size class and
// presentation, and, when present, the row shell.tui.entries lists it with.
// `script` is a path under the plugin's `tui/` directory, the one
// bin/vgshell-tui copies out of the published snapshot and runs from; each
// segment starts with a letter, a digit or `_`, so none is `.`, `..` or
// hidden. The sizes are the size classes of HyprlandLayer.TUI_WINDOWS, the
// table the layer's window rules and the launcher's app-ids come from, and
// the presentations are bin/vgshell-tui's. A title, a label and a group are one
// printable line of at most TUI_TEXT_MAX characters.
var TUI_KEYS = ["script", "title", "size", "presentation", "entry", "requires"];
var TUI_ENTRY_KEYS = ["label", "icon", "group"];
var TUI_SIZES = Object.keys(HyprlandLayer.TUI_WINDOWS);
var TUI_PRESENTATIONS = ["full", "plain"];
var TUI_TEXT_MAX = 60;
var TUI_SCRIPT = /^tui(\/[A-Za-z0-9_][A-Za-z0-9._-]*)+$/;
// The arguments shell.tui.run hands a plugin's script: at most TUI_ARGS_MAX
// strings, each 1 to TUI_ARG_MAX characters with no control character.
var TUI_ARGS_MAX = 16;
var TUI_ARG_MAX = 256;
// The exit status bin/vgshell-tui launch and check give when xdg-terminal-exec
// is not on PATH, their `terminal=missing` refusal.
var TUI_LAUNCHER_MISSING = 69;
// The exit status bin/vgshell-tui wait gives for a run with neither record, its
// `reason=gone` refusal: a later run of the key removed them after this run
// ended.
var TUI_WAIT_GONE = 3;
// What the core knows of the terminal launcher: `unknown` until a probe or a
// launch answers, `present` once one exited 0, `missing` once one exited
// TUI_LAUNCHER_MISSING. tuiLauncherAfter moves it.
var TUI_LAUNCHER_STATES = ["unknown", "present", "missing"];
// What a row of the core's own TUI table holds, and the command its argv
// starts with: a file of the core's own bin/ directory, which tuiCore
// resolves under the directory the shell hands it, since the shell's PATH
// need not hold the core's commands.
var CORE_TUI_KEYS = ["argv", "title", "size", "presentation", "entry"];
var CORE_TUI_COMMAND = /^vgshell(-[a-z]+)*$/;
// What a refused request asks the runner to do next: nothing, one probe of
// the launcher, or focus the window of the key's live run.
var TUI_ACTIONS = ["none", "probe", "focus"];
// The states of an exit record bin/vgshell-tui writes: `running` from the
// presenter's start, `ended` once it exited or `vgshell-tui reap` found it
// gone.
var TUI_RECORD_STATES = ["running", "ended"];
// A run id the core hands bin/vgshell-tui with --run, and the key a record
// carries: `core/<name>` or `<plugin id>/<name>`.
var TUI_RUN_PATTERN = /^[a-z0-9][a-z0-9-]*$/;
// The core's own floating TUIs, by name, listed in shell.tui.entries as
// `core/<name>` and opened by that key: each { argv, title, size,
// presentation, entry }, `argv` the core command the terminal runs and the
// rest as a normalized manifest `tui` entry has them. coreTuiTable judges
// the table when this file loads. The package pickers run in the default
// size.
// `edit`, `requirements-install`, `system`, `plugin-update` and
// `plugin-remove` are not listed. The first opens a cited file from a
// surface, the requirement notice opens the install row with the arguments
// PluginLogic.noticeView names, the `manager` capability's act opens
// `system` with `apply <step>` for a status action that names a system step
// (D081), and the plugin manager opens update and remove with one plugin id
// (MANAGER_TUIS). A plugin update shows its incoming diff, so it opens wide.
var CORE_TUIS = coreTuiTable({
    "pkg-install": {
        argv: ["vgshell", "pkg", "install"],
        title: "Install packages",
        size: "default",
        presentation: "full",
        entry: { label: "Install packages", icon: "package-plus", group: "Packages" }
    },
    "pkg-remove": {
        argv: ["vgshell", "pkg", "remove"],
        title: "Remove packages",
        size: "default",
        presentation: "full",
        entry: { label: "Remove packages", icon: "package-minus", group: "Packages" }
    },
    "sudo-grant": {
        argv: ["vgshell", "sudo", "grant"],
        title: "Passwordless sudo",
        size: "default",
        presentation: "full",
        entry: { label: "Passwordless sudo", icon: "shield-alert", group: "System" }
    },
    "doctor": {
        argv: ["vgshell", "doctor"],
        title: "Requirements",
        size: "default",
        presentation: "full",
        entry: { label: "Check requirements", icon: "stethoscope", group: "System" }
    },
    "plugin-add": {
        argv: ["vgshell", "plugin", "add"],
        title: "Add a plugin",
        size: "default",
        presentation: "full",
        entry: { label: "Add a plugin", icon: "circle-plus", group: "Plugins" }
    },
    "theme-add": {
        argv: ["vgshell", "theme", "add"],
        title: "Add a theme",
        size: "default",
        presentation: "full",
        entry: { label: "Add a theme", icon: "palette", group: "Themes" }
    },
    "requirements-install": {
        argv: ["vgshell", "pkg", "run", "install"],
        title: "Install requirements",
        size: "default",
        presentation: "full",
        entry: null
    },
    "edit": {
        argv: ["vgshell", "edit"],
        title: "Edit a file",
        size: "default",
        presentation: "plain",
        entry: null
    },
    "plugin-update": {
        argv: ["vgshell", "plugin", "update"],
        title: "Update a plugin",
        size: "wide",
        presentation: "full",
        entry: null
    },
    "plugin-remove": {
        argv: ["vgshell", "plugin", "remove"],
        title: "Remove a plugin",
        size: "default",
        presentation: "full",
        entry: null
    },
    "system": {
        argv: ["vgshell", "system"],
        title: "System setup",
        size: "default",
        presentation: "full",
        entry: null
    }
});

// The `manager` capability's TUI members, each with the CORE_TUIS row it
// opens for one installed plugin's id. A bundled plugin is disabled, never
// updated or removed.
var MANAGER_TUIS = {
    update: "plugin-update",
    remove: "plugin-remove"
};

// The core TUI the `manager` capability's member ACTION, a key of
// MANAGER_TUIS, opens for plugin ID, whose SOURCE is `bundled` or
// `installed` as Registry.sourceOf names it, or null for an id no plugin
// has: { ok: true, name, args } for tuiCore, or { ok: false, answer } with
// the manager's replies, `unknown: <id>` for an id no plugin has and
// `refused: bundled=<id>`, the refusal `vgshell plugin` prints, for a bundled
// plugin.
function managerTui(action, id, source) {
    if (!hasOwn(MANAGER_TUIS, action))
        throw new Error("manager: no TUI action " + JSON.stringify(action) + ", want one of " + Object.keys(MANAGER_TUIS).join(", "));
    if (typeof id !== "string" || source === null)
        return { ok: false, answer: "unknown: " + tuiLabel(id) };
    switch (source) {
    case "bundled":
        return { ok: false, answer: "refused: bundled=" + id };
    case "installed":
        return { ok: true, name: MANAGER_TUIS[action], args: [id] };
    }
    throw new Error("manager: plugin source " + JSON.stringify(source) + " is not one of bundled, installed");
}

// The one judgement of whether TUI KEY is on screen for ANSWER: `ok` when
// the launcher started, and when that key was busy, since the runner then
// asks the compositor to focus the live run's window. TuiRunner.open and
// the manager capability's TUI members use this; any other refusal passes
// through unchanged.
function tuiShownAnswer(key, answer) {
    return answer === tuiRefusal(key, "busy").answer ? "ok" : answer;
}

// One printable line of 1 to TUI_TEXT_MAX characters.
function tuiText(value) {
    return typeof value === "string" && value.trim().length > 0 && Array.from(value).length <= TUI_TEXT_MAX && !CONTROL_CHARACTER.test(value);
}

// The first defect of a manifest's `tui` key, or "": an object of at least
// one script, each named by NAME_PATTERN and holding only TUI_KEYS; `script`
// matches TUI_SCRIPT; `title` passes tuiText; `size` and `presentation`,
// when present, come from TUI_SIZES and TUI_PRESENTATIONS; `requires`, when
// present, names the REQUIREMENTS the script needs; `entry`, when
// present, holds a tuiText `label` and `group` and an `icon` of the shipped
// set. The plugin opens its scripts through capability `tui`, which the
// manifest must name. Whether the script is a regular executable file, and
// no link, is bin/lib/check-manifests.js's to read on disk.
function tuiError(tui, capabilities, requirements) {
    if (!isPlainObject(tui))
        return "tui must be an object of script names to scripts";
    var names = Object.keys(tui);
    if (names.length === 0)
        return "tui must declare at least one script";
    if (capabilities.indexOf("tui") === -1)
        return "tui needs capability tui";
    for (var i = 0; i < names.length; i++) {
        var name = names[i];
        var at = "tui." + name;
        if (!NAME_PATTERN.test(name))
            return "tui name " + JSON.stringify(name) + " must be lower case letters, digits and dashes";
        var row = tui[name];
        if (!isPlainObject(row))
            return at + " must be an object";
        var keys = Object.keys(row);
        for (var k = 0; k < keys.length; k++) {
            if (TUI_KEYS.indexOf(keys[k]) === -1)
                return at + " has unknown key " + JSON.stringify(keys[k]);
        }
        if (typeof row.script !== "string" || !TUI_SCRIPT.test(row.script))
            return at + ".script must be a relative path under tui/ inside the plugin, got " + JSON.stringify(row.script);
        var windowError = tuiWindowError(at, row);
        if (windowError !== "")
            return windowError;
        var requiresError = tuiRequiresError(at, row.requires, requirements);
        if (requiresError !== "")
            return requiresError;
        if (row.entry === undefined)
            continue;
        var entryError = tuiEntryError(at, row.entry);
        if (entryError !== "")
            return entryError;
    }
    return "";
}

// The first defect of the window a TUI row at AT opens, or "": `title`
// passes tuiText, and `size` and `presentation`, when present, come from
// TUI_SIZES and TUI_PRESENTATIONS.
function tuiWindowError(at, row) {
    if (!tuiText(row.title))
        return at + ".title must be one printable line of 1 to " + TUI_TEXT_MAX + " characters";
    if (row.size !== undefined && TUI_SIZES.indexOf(row.size) === -1)
        return at + ".size must be one of " + TUI_SIZES.join(", ") + ", got " + JSON.stringify(row.size);
    if (row.presentation !== undefined && TUI_PRESENTATIONS.indexOf(row.presentation) === -1)
        return at + ".presentation must be one of " + TUI_PRESENTATIONS.join(", ") + ", got " + JSON.stringify(row.presentation);
    return "";
}

// The first defect of the `requires` of a TUI row at AT, or "": absent, or
// a list of names from the manifest's REQUIREMENTS, each once. An empty
// list says the script needs none of them.
function tuiRequiresError(at, requires, requirements) {
    if (requires === undefined)
        return "";
    if (!Array.isArray(requires))
        return at + ".requires must be a list of the manifest's requirements";
    var declared = requirements.map(requirementName);
    for (var n = 0; n < requires.length; n++) {
        if (declared.indexOf(requires[n]) === -1)
            return at + ".requires." + n + " must name a requirement of the manifest's requirements, got " + JSON.stringify(requires[n]);
        if (requires.indexOf(requires[n]) !== n)
            return at + ".requires." + n + " repeats " + JSON.stringify(requires[n]);
    }
    return "";
}

// The first defect of the `entry` of a TUI row at AT, or "": an object of
// TUI_ENTRY_KEYS holding a tuiText `label` and `group` and an `icon` of the
// shipped set.
function tuiEntryError(at, entry) {
    if (!isPlainObject(entry))
        return at + ".entry must be an object";
    var entryKeys = Object.keys(entry);
    for (var e = 0; e < entryKeys.length; e++) {
        if (TUI_ENTRY_KEYS.indexOf(entryKeys[e]) === -1)
            return at + ".entry has unknown key " + JSON.stringify(entryKeys[e]);
    }
    if (!tuiText(entry.label))
        return at + ".entry.label must be one printable line of 1 to " + TUI_TEXT_MAX + " characters";
    if (typeof entry.icon !== "string" || !hasOwn(Lucide.ICONS, entry.icon))
        return at + ".entry.icon must name an icon of the shipped set, shell/Ui/icons/Lucide.js, got " + JSON.stringify(entry.icon);
    if (!tuiText(entry.group))
        return at + ".entry.group must be one printable line of 1 to " + TUI_TEXT_MAX + " characters";
    return "";
}

// The first defect of the core's own TUI NAME, ROW, or "": NAME matches
// NAME_PATTERN; ROW holds every key of CORE_TUI_KEYS and no other; `argv`
// is a CORE_TUI_COMMAND followed by arguments tuiArgsValid accepts; the
// window passes tuiWindowError with a `size` and `presentation` set; and
// `entry` is null or passes tuiEntryError.
function coreTuiError(name, row) {
    var at = "core/" + name;
    if (!NAME_PATTERN.test(name))
        return "core TUI name " + JSON.stringify(name) + " must be lower case letters, digits and dashes";
    if (!isPlainObject(row))
        return at + " must be an object";
    var keys = Object.keys(row);
    for (var k = 0; k < keys.length; k++) {
        if (CORE_TUI_KEYS.indexOf(keys[k]) === -1)
            return at + " has unknown key " + JSON.stringify(keys[k]);
    }
    for (var m = 0; m < CORE_TUI_KEYS.length; m++) {
        if (row[CORE_TUI_KEYS[m]] === undefined)
            return at + " needs key " + CORE_TUI_KEYS[m];
    }
    if (!Array.isArray(row.argv) || typeof row.argv[0] !== "string" || !CORE_TUI_COMMAND.test(row.argv[0]))
        return at + ".argv must start with a command of the core's bin/ directory, got " + JSON.stringify(row.argv);
    if (!tuiArgsValid(row.argv.slice(1)))
        return at + ".argv takes at most " + TUI_ARGS_MAX + " arguments of 1 to " + TUI_ARG_MAX + " characters with no control character";
    var windowError = tuiWindowError(at, row);
    if (windowError !== "")
        return windowError;
    return row.entry === null ? "" : tuiEntryError(at, row.entry);
}

// TABLE once every row passes coreTuiError. The table is the core's own
// code, so a defect throws when this file loads.
function coreTuiTable(table) {
    Object.keys(table).forEach(function (name) {
        var error = coreTuiError(name, table[name]);
        if (error !== "")
            throw new Error("tui: " + error);
    });
    return table;
}

// A `tui` key tuiError accepted, each entry with every key: `size`
// "default" and `presentation` "full" when absent, `entry` and `requires`
// null.
function normalTui(tui) {
    var out = {};
    Object.keys(tui).forEach(function (name) {
        var row = tui[name];
        out[name] = {
            script: row.script,
            title: row.title,
            size: row.size === undefined ? "default" : row.size,
            presentation: row.presentation === undefined ? "full" : row.presentation,
            entry: row.entry === undefined ? null : clone(row.entry),
            requires: row.requires === undefined ? null : row.requires.slice()
        };
    });
    return out;
}

// The name a TUI answer carries: the caller's text when it is one visible
// word, otherwise its JSON, so a log line never holds a raw space, newline
// or control character.
function tuiLabel(name) {
    return typeof name === "string" && /^[\x21-\x7e]+$/.test(name) ? name : JSON.stringify(name);
}

// A refusal: ANSWER's text, and ACTION, one of TUI_ACTIONS, for KEY.
function tuiRefusal(name, reason) {
    return { ok: false, answer: "refused: tui=" + tuiLabel(name) + " reason=" + reason, action: "none", key: null };
}

// The refusal of a request the judge accepted, for launch KEY, from the
// runner's state RUNNER, { launcher, busy, run }, or null to start it.
// `reason=busy` while KEY is in `busy`, the keys whose launcher is still
// waiting for its presenter or whose record says running: it asks the
// runner to focus that run's window, so a second click raises the open
// TUI instead of starting another. Then `reason=launcher-missing` while
// `launcher`, one of TUI_LAUNCHER_STATES, is `missing`: it asks for one
// probe, so a terminal installed since the last one is found by a later
// request without a restart. Any other state starts the launch: an
// `unknown` launcher that finds no terminal is logged by tuiLaunchOutcome
// and moves the state.
function tuiRunnerRefusal(runner, name, key) {
    if (TUI_LAUNCHER_STATES.indexOf(runner.launcher) === -1)
        throw new Error("tui: launcher state " + JSON.stringify(runner.launcher) + " is not one of " + TUI_LAUNCHER_STATES.join(", "));
    var refusal;
    if (runner.busy.indexOf(key) !== -1) {
        refusal = tuiRefusal(name, "busy");
        refusal.action = "focus";
    } else if (runner.launcher === "missing") {
        refusal = tuiRefusal(name, "launcher-missing");
        refusal.action = "probe";
    } else {
        return null;
    }
    refusal.key = key;
    return refusal;
}

// The `ipc` capability's answer to handler NAME of plugin ID with ARG, from
// TARGETS, IpcRegistry's record: each plugin id to { handler, functions },
// `functions` its handlers by name. Only ID's own handlers are looked up,
// so a plugin's `call` never reaches another plugin's target. The answer is
// { reply, error }: `reply` the handler's result as text, "" for none,
// `unknown: <name>` when ID holds no handler NAME, or `error: <message>`
// when it threw, with that message in `error`, null otherwise.
function ipcAnswer(targets, id, name, arg) {
    var target = hasOwn(targets, id) ? targets[id] : null;
    if (target === null || !hasOwn(target.functions, name))
        return { reply: "unknown: " + name, error: null };
    try {
        var result = target.functions[name](arg);
        return { reply: result === undefined ? "" : String(result), error: null };
    } catch (e) {
        // A plugin may throw a value that is not an Error.
        var message = e !== null && typeof e === "object" && typeof e.message === "string" ? e.message : String(e);
        return { reply: "error: " + message, error: message };
    }
}

// Why `shell.ipc.call(name, arg)` is refused, "" when it is not: a handler
// takes the text an outside `vgshell ipc call` sends, so ARG is a string.
function ipcCallRefusal(name, arg) {
    return typeof arg === "string" ? "" : "refused: ipc=" + name + " arg=not-a-string";
}

// Whether ARGS may follow a plugin's script: absent, or a list of at most
// TUI_ARGS_MAX strings, each 1 to TUI_ARG_MAX characters with no control
// character.
function tuiArgsValid(args) {
    if (args === undefined)
        return true;
    if (!Array.isArray(args) || args.length > TUI_ARGS_MAX)
        return false;
    return args.every(function (arg) {
        return typeof arg === "string" && arg.length > 0 && Array.from(arg).length <= TUI_ARG_MAX && !CONTROL_CHARACTER.test(arg);
    });
}

// The arguments for the core file editor: PATH is relative to the user's
// configuration directory and LINE, when present, is a positive integer.
// The CLI judges the same contract again before it opens anything.
function editArgs(path, line) {
    if (typeof path !== "string" || path.length === 0)
        return { ok: false, answer: "refused: edit=path reason=empty" };
    if (path.charAt(0) === "/")
        return { ok: false, answer: "refused: edit=" + tuiLabel(path) + " reason=absolute" };
    if (path.split("/").indexOf("..") !== -1)
        return { ok: false, answer: "refused: edit=" + tuiLabel(path) + " reason=parent" };
    if (line === undefined || line === null || line === "")
        return { ok: true, args: [path] };
    if (typeof line !== "string" && typeof line !== "number")
        return { ok: false, answer: "refused: line=" + tuiLabel(line) + " reason=positive-integer" };
    var text = String(line);
    if (!/^[1-9][0-9]*$/.test(text))
        return { ok: false, answer: "refused: line=" + tuiLabel(line) + " reason=positive-integer" };
    return { ok: true, args: [path, text] };
}

// The arguments after bin/vgshell-tui that open ROW, a normalized `tui` entry
// or a CORE_TUIS row, running COMMAND as launch KEY's run RUN, so the
// presenter writes the run's exit record; PLUGIN, { id, dir }, names the
// plugin and its published snapshot, null for a core TUI.
function tuiArgv(row, plugin, key, run, command) {
    var argv = ["launch", "--title", row.title, "--size", row.size, "--presentation", row.presentation];
    if (plugin !== null)
        argv.push("--plugin", plugin.id, "--dir", plugin.dir);
    argv.push("--record", key, "--run", run);
    return argv.concat(["--"], command);
}

// Plugin MANIFEST's own TUI NAME with ARGS, from its published snapshot
// under SOURCE_DIR (D014), from the runner's state RUNNER, { launcher, busy,
// run }, `run` the id the launch gets: { ok: true, key, run, argv }, `key`
// `<id>/<name>` and `argv` what follows bin/vgshell-tui, or { ok: false,
// answer, action, key } with answer `refused: tui=<name>` and, in this
// order, `reason=undeclared` for a name the manifest does not declare,
// `reason=disabled` while the plugin is not ENABLED, `reason=args` for
// arguments tuiArgsValid refuses, then `reason=busy` or
// `reason=launcher-missing` as tuiRunnerRefusal decides; `action` is
// `none` for the first three.
function tuiRun(manifest, enabled, sourceDir, runner, name, args) {
    if (typeof name !== "string" || !hasOwn(manifest.tui, name))
        return tuiRefusal(name, "undeclared");
    if (!enabled)
        return tuiRefusal(name, "disabled");
    if (!tuiArgsValid(args))
        return tuiRefusal(name, "args");
    var key = manifest.id + "/" + name;
    var refusal = tuiRunnerRefusal(runner, name, key);
    if (refusal !== null)
        return refusal;
    var row = manifest.tui[name];
    var plugin = { id: manifest.id, dir: sourceDir + "/" + manifest.__revision };
    return { ok: true, key: key, run: runner.run, argv: tuiArgv(row, plugin, key, runner.run, [row.script].concat(args === undefined ? [] : args)) };
}

// The core's own TUI NAME of CORE, the CORE_TUIS table, listed or not,
// with ARGS after its argv, its command resolved under CORE_BIN, the core's
// bin/ directory, for RUNNER: answers as tuiRun, keyed `core/<name>`, with
// `reason=undeclared` for a name CORE lacks, `reason=args` for arguments
// tuiArgsValid refuses, then `reason=busy` or `reason=launcher-missing` as
// tuiRunnerRefusal decides. The core alone calls it; tuiOpen opens a
// listed row with no arguments through it.
function tuiCore(core, coreBin, runner, name, args) {
    var key = "core/" + name;
    if (typeof name !== "string" || !hasOwn(core, name))
        return tuiRefusal(key, "undeclared");
    if (!tuiArgsValid(args))
        return tuiRefusal(key, "args");
    var refusal = tuiRunnerRefusal(runner, key, key);
    if (refusal !== null)
        return refusal;
    var row = core[name];
    return { ok: true, key: key, run: runner.run, argv: tuiArgv(row, null, key, runner.run, [coreBin + "/" + row.argv[0]].concat(row.argv.slice(1), args === undefined ? [] : args)) };
}

// The listed TUI KEY, with no arguments: `core/<name>` of a CORE row with
// an `entry`, through tuiCore, or `<plugin id>/<name>` of a script whose
// manifest in MANIFESTS gives it an `entry`, from the plugin's snapshot
// under SOURCE_DIR. Answers as tuiRun, with `reason=undeclared` for a key
// nothing lists, `reason=disabled` for a plugin not in ENABLED_IDS, then
// `reason=busy` or `reason=launcher-missing` as tuiRunnerRefusal decides
// for RUNNER. A plugin script that lacks a requirement its owner's entry
// in MISSING, owner id -> missing requirement names, holds answers
// { ok: true, kind: "install", id, name } in their place, as tuiRunFor
// does, so every route that opens a listed script raises the same notice.
function tuiOpen(manifests, enabledIds, sourceDir, coreBin, runner, core, missing, key) {
    var slash = typeof key === "string" ? key.indexOf("/") : -1;
    if (slash === -1)
        return tuiRefusal(key, "undeclared");
    var owner = key.slice(0, slash);
    var name = key.slice(slash + 1);
    if (owner === "core") {
        if (!hasOwn(core, name) || core[name].entry === null)
            return tuiRefusal(key, "undeclared");
        return tuiCore(core, coreBin, runner, name, []);
    }
    if (!hasOwn(manifests, owner) || !hasOwn(manifests[owner].tui, name) || manifests[owner].tui[name].entry === null)
        return tuiRefusal(key, "undeclared");
    if (enabledIds.indexOf(owner) === -1)
        return tuiRefusal(key, "disabled");
    if (tuiMissingRequirements(manifests[owner], name, hasOwn(missing, owner) ? missing[owner] : []).length > 0)
        return { ok: true, kind: "install", id: owner, name: name };
    var pluginRefusal = tuiRunnerRefusal(runner, key, key);
    if (pluginRefusal !== null)
        return pluginRefusal;
    var launch = tuiRun(manifests[owner], true, sourceDir, runner, name, []);
    return { ok: true, key: key, run: launch.run, argv: launch.argv };
}

// Every listed TUI, sorted by key: each CORE row with an `entry` as
// `core/<name>`, then those of the plugins in ENABLED_IDS as
// `<plugin id>/<name>`, each { key, plugin, name, title, label, icon, group }
// with `plugin` "core" for the core's own.
function tuiEntries(manifests, enabledIds, core) {
    var rows = [];
    function add(owner, name, row) {
        if (row.entry === null)
            return;
        rows.push({ key: owner + "/" + name, plugin: owner, name: name, title: row.title, label: row.entry.label, icon: row.entry.icon, group: row.entry.group });
    }
    Object.keys(core).forEach(function (name) { add("core", name, core[name]); });
    enabledIds.forEach(function (id) {
        if (!hasOwn(manifests, id))
            return;
        Object.keys(manifests[id].tui).forEach(function (name) { add(id, name, manifests[id].tui[name]); });
    });
    return rows.sort(function (a, b) { return a.key < b.key ? -1 : a.key > b.key ? 1 : 0; });
}

// The setup screens of plugin MANIFEST, for its manager row: each `tui`
// script with an `entry`, in manifest order, as { name, label, icon }.
function listedTuis(manifest) {
    return Object.keys(manifest.tui).filter(function (name) { return manifest.tui[name].entry !== null; }).map(function (name) {
        return { name: name, label: manifest.tui[name].entry.label, icon: manifest.tui[name].entry.icon };
    });
}

// The setup screens of plugin MANIFEST, its active manifest, as its manager
// row draws them, each listedTuis' row with `withheld`: "" while MISSING, the
// plugin's missing requirement names, holds none the screen needs
// (tuiMissingRequirements), else tuiWithheldReason's line, since its press
// would only raise the requirement notice. The page draws a withheld
// screen's button disabled, but for the step an offered status action
// names, which installs them.
function listedTuiRows(manifest, missing) {
    return listedTuis(manifest).map(function (tui) {
        var lacking = tuiMissingRequirements(manifest, tui.name, missing);
        return { name: tui.name, label: tui.label, icon: tui.icon, withheld: lacking.length === 0 ? "" : tuiWithheldReason(lacking) };
    });
}

// What the `manager` capability's `openTui(id, name)` does for TUI NAME
// of plugin MANIFEST, null for an id no plugin has: { ok: true, kind:
// "tui", name }, the request statusActionRequest makes for a TUI action,
// or { ok: false, answer } with `unknown: <id>`, or with tuiRefusal's
// `undeclared` line for a name listedTuis does not list. The run of the
// request refuses a disabled plugin, as tuiRun decides.
function listedTuiRequest(manifest, id, name) {
    if (manifest === null)
        return { ok: false, answer: "unknown: " + tuiLabel(id) };
    if (!listedTuis(manifest).some(function (tui) { return tui.name === name; }))
        return { ok: false, answer: tuiRefusal(name, "undeclared").answer };
    return { ok: true, kind: "tui", name: name };
}

// The Settings page's Open summons a plugin's working surface. A window
// wins over a panel because it is the plugin's application surface.
function openKind(manifest) {
    if (manifest.kinds.indexOf("window") !== -1) return "window";
    if (manifest.kinds.indexOf("panel") !== -1) return "panel";
    return "";
}

// What the manager's open(id) does. A disabled plugin is refused by the
// summon route itself, as the TUI run refuses one.
function openRequest(manifest, id) {
    if (manifest === null)
        return { ok: false, answer: "unknown: " + tuiLabel(id) };
    var kind = openKind(manifest);
    if (kind === "")
        return { ok: false, answer: "refused: open=" + tuiLabel(id) + " reason=no-surface" };
    return { ok: true, kind: "summon", surface: kind };
}

// The launcher state after a probe or a launch that was started while the
// state was STATE ended with COMPLETION, { code, status } or null for one
// that never started: `present` on exit 0, `missing` on
// TUI_LAUNCHER_MISSING, STATE for any other end, which says nothing about the
// terminal.
function tuiLauncherAfter(state, completion) {
    if (completion === null || completion.status !== 0)
        return state;
    if (completion.code === 0)
        return "present";
    if (completion.code === TUI_LAUNCHER_MISSING)
        return "missing";
    return state;
}

// The log line for a probe, `bin/vgshell-tui check`, that ended with
// COMPLETION and STDERR, or "" for one that answered: exit 0 or
// TUI_LAUNCHER_MISSING, which tuiLauncherAfter records. Every other end is
// `tui: probe=failed exit=<code> status=<status>` with the first stderr
// line, or `tui: probe=unstarted`.
function tuiProbeOutcome(completion, stderr) {
    if (completion === null)
        return "tui: probe=unstarted";
    if (completion.status === 0 && (completion.code === 0 || completion.code === TUI_LAUNCHER_MISSING))
        return "";
    return "tui: probe=failed exit=" + completion.code + " status=" + completion.status + " " + String(stderr).split("\n")[0];
}

// The log line for a launcher of TUI KEY that ended with COMPLETION,
// { code, status } or null for one that never started, and STDERR, or ""
// for a launch that handed the terminal its command. The request answered
// `ok` before the launcher ran, so its refusal is logged here:
// `tui: refused: tui=<key> reason=launcher-missing` for xdg-terminal-exec
// missing, `tui: launcher=unstarted tui=<key>`, and
// `tui: launcher=failed tui=<key> exit=<code> status=<status>` with the
// launcher's first stderr line for every other end.
function tuiLaunchOutcome(key, completion, stderr) {
    if (completion === null)
        return "tui: launcher=unstarted tui=" + tuiLabel(key);
    if (completion.status === 0 && completion.code === 0)
        return "";
    if (completion.status === 0 && completion.code === TUI_LAUNCHER_MISSING)
        return "tui: refused: tui=" + tuiLabel(key) + " reason=launcher-missing";
    return "tui: launcher=failed tui=" + tuiLabel(key) + " exit=" + completion.code + " status=" + completion.status + " " + String(stderr).split("\n")[0];
}

// The log lines of a `bin/vgshell-tui reap` that ended with COMPLETION, STDOUT
// and STDERR, each { level: "info" | "error", text }: one info line
// `tui: reaped=<key> run=<run>` per record it ended, an error line for any
// other line it printed, and `tui: reap=failed exit=<code> status=<status>`
// with its first stderr line, or `tui: reap=unstarted`, for a reap that did
// not exit 0.
function tuiReapOutcome(completion, stdout, stderr) {
    var lines = [];
    String(stdout).split("\n").forEach(function (line) {
        if (line === "")
            return;
        if (/^reaped=[a-z0-9.-]+\/[a-z0-9-]+ run=[a-z0-9-]+$/.test(line))
            lines.push({ level: "info", text: "tui: " + line });
        else
            lines.push({ level: "error", text: "tui: reap=unparsed line=" + JSON.stringify(line) });
    });
    if (completion === null)
        lines.push({ level: "error", text: "tui: reap=unstarted" });
    else if (completion.status !== 0 || completion.code !== 0)
        lines.push({ level: "error", text: "tui: reap=failed exit=" + completion.code + " status=" + completion.status + " " + String(stderr).split("\n")[0] });
    return lines;
}

// What a launch's `done` receives when its launcher ended with COMPLETION,
// or null for a launcher that saw the run's record: its `done` waits for
// the ended record. `{ code: null, reason: "launcher-missing" }` when no
// terminal was found, `{ code: null, reason: "launcher-failed" }` for every
// other end, the silent terminal included.
function tuiLaunchDone(completion) {
    if (completion !== null && completion.status === 0 && completion.code === 0)
        return null;
    if (completion !== null && completion.status === 0 && completion.code === TUI_LAUNCHER_MISSING)
        return { code: null, reason: "launcher-missing" };
    return { code: null, reason: "launcher-failed" };
}

// Whether KEY is a launch key: `core/<name>` or `<plugin id>/<name>`.
function tuiKeyValid(key) {
    if (typeof key !== "string")
        return false;
    var slash = key.indexOf("/");
    if (slash === -1)
        return false;
    var owner = key.slice(0, slash);
    return (owner === "core" || ID_PATTERN.test(owner)) && NAME_PATTERN.test(key.slice(slash + 1));
}

// One exit record's TEXT, as bin/vgshell-tui writes it: { ok: true, record }
// or { ok: false, error } naming the first defect. A running record has a
// null code and endedAt; an ended one an integer code, or null when
// `vgshell-tui reap` wrote it, and an endedAt.
function tuiRecord(text) {
    var value;
    try {
        value = JSON.parse(text);
    } catch (e) {
        return { ok: false, error: "record is not JSON: " + e.message };
    }
    if (!isPlainObject(value))
        return { ok: false, error: "record is not an object" };
    if (!tuiKeyValid(value.key))
        return { ok: false, error: "record key " + JSON.stringify(value.key) + " is not a launch key" };
    if (typeof value.run !== "string" || !TUI_RUN_PATTERN.test(value.run))
        return { ok: false, error: "record run " + JSON.stringify(value.run) + " is malformed" };
    if (TUI_RECORD_STATES.indexOf(value.state) === -1)
        return { ok: false, error: "record state " + JSON.stringify(value.state) + " is not one of " + TUI_RECORD_STATES.join(", ") };
    var ended = value.state === "ended";
    if (!(value.code === null || (ended && Number.isInteger(value.code))))
        return { ok: false, error: "record code " + JSON.stringify(value.code) + " does not fit state " + value.state };
    if (typeof value.startedAt !== "string" || value.startedAt.length === 0)
        return { ok: false, error: "record startedAt must be a string" };
    if (ended ? typeof value.endedAt !== "string" || value.endedAt.length === 0 : value.endedAt !== null)
        return { ok: false, error: "record endedAt " + JSON.stringify(value.endedAt) + " does not fit state " + value.state };
    if (!isPlainObject(value.window) || typeof value.window.appId !== "string" || typeof value.window.title !== "string")
        return { ok: false, error: "record window must be { appId, title }" };
    return { ok: true, record: { key: value.key, run: value.run, state: value.state, code: value.code, startedAt: value.startedAt, endedAt: value.endedAt, window: { appId: value.window.appId, title: value.window.title } } };
}

// The runs RECORDS, a list of tuiRecord records, describe: { runs, keys },
// `runs` each run's record by run id, an ended record over the running
// one of the same run, and `keys` per key { running, ended }: the running
// run with the latest startedAt, or null, and the ended run with the latest
// startedAt, or null: a record `vgshell-tui reap` wrote carries the time the
// reap found the run, which can follow a later run's end. A running record
// whose run also ended is not running.
function tuiRuns(records) {
    var runs = {};
    records.forEach(function (record) {
        if (!hasOwn(runs, record.run) || record.state === "ended")
            runs[record.run] = record;
    });
    var keys = {};
    Object.keys(runs).forEach(function (id) {
        var record = runs[id];
        if (!hasOwn(keys, record.key))
            keys[record.key] = { running: null, ended: null };
        var slot = keys[record.key];
        if (record.state === "running") {
            if (slot.running === null || record.startedAt > slot.running.startedAt)
                slot.running = record;
        } else if (slot.ended === null || record.startedAt > slot.ended.startedAt) {
            slot.ended = record;
        }
    });
    return { runs: runs, keys: keys };
}

// The keys a new run may not start under: every key in LAUNCHING, whose
// launcher still waits for its presenter, and every key of RUNS, a tuiRuns
// result, with a running run.
function tuiBusyKeys(runs, launching) {
    var busy = launching.slice();
    Object.keys(runs.keys).forEach(function (key) {
        if (runs.keys[key].running !== null && busy.indexOf(key) === -1)
            busy.push(key);
    });
    return busy.sort();
}

// shell.tui.state for the plugin ID's own TUIs NAMES, from RUNS, a tuiRuns
// result: per name { running, code, endedAt }, the last two from the key's
// latest ended run, null before any ended.
function tuiState(runs, id, names) {
    var out = {};
    names.forEach(function (name) {
        var slot = hasOwn(runs.keys, id + "/" + name) ? runs.keys[id + "/" + name] : { running: null, ended: null };
        out[name] = {
            running: slot.running !== null,
            code: slot.ended === null ? null : slot.ended.code,
            endedAt: slot.ended === null ? null : slot.ended.endedAt
        };
    });
    return out;
}

// What the `done` of RUN receives, from RUNS, a tuiRuns result: null while
// the run has no ended record, else { code, reason }, `reason` null for a
// run that ended with its code and `vanished` for one `vgshell-tui reap`
// ended, whose code is null.
function tuiRunDone(runs, run) {
    if (!hasOwn(runs.runs, run) || runs.runs[run].state !== "ended")
        return null;
    var code = runs.runs[run].code;
    return { code: code, reason: code === null ? "vanished" : null };
}

// The runs that need a `vgshell-tui wait` process: every launch the launcher
// handed to a terminal and that has no ended record yet, and every running
// record already listed, as after a shell restart. The caller filters waits
// already running or settled while the running record remains listed.
function tuiWaitRuns(runs, launched) {
    var wanted = {};
    function add(key, run) {
        var id = key + "|" + run;
        wanted[id] = { key: key, run: run };
    }
    launched.forEach(function (row) {
        if (!hasOwn(runs.runs, row.run) || runs.runs[row.run].state !== "ended")
            add(row.key, row.run);
    });
    Object.keys(runs.keys).forEach(function (key) {
        var running = runs.keys[key].running;
        if (running !== null)
            add(key, running.run);
    });
    return Object.keys(wanted).sort().map(function (id) { return wanted[id]; });
}

// The result of one `vgshell-tui wait --record KEY --run RUN`: either the ended
// record it printed, or log lines that name why the result was not accepted.
// WANTED is tuiWaitRuns's answer as the wait finished, before the wait's own
// run is dropped from the launches. A gone run WANTED no longer holds, by
// key and run, is a normal end: the core already read its ended record
// before a later run of the key removed it, so it logs nothing. A gone run
// WANTED still holds is one the core counts live with no record left.
function tuiWaitOutcome(key, run, wanted, completion, stdout, stderr) {
    var prefix = "tui: wait=" + tuiLabel(key) + " run=" + tuiLabel(run);
    if (completion === null)
        return { record: null, logs: [prefix + " reason=unstarted"] };
    if (completion.status === 0 && completion.code === TUI_WAIT_GONE) {
        var awaited = wanted.some(function (row) { return row.key === key && row.run === run; });
        return { record: null, logs: awaited ? [prefix + " reason=gone " + String(stderr).split("\n")[0]] : [] };
    }
    if (completion.status !== 0 || completion.code !== 0)
        return { record: null, logs: [prefix + " reason=failed exit=" + completion.code + " status=" + completion.status + " " + String(stderr).split("\n")[0]] };
    var lines = String(stdout).split("\n").filter(function (line) { return line !== ""; });
    if (lines.length !== 1)
        return { record: null, logs: [prefix + " reason=stdout-lines count=" + lines.length] };
    var judged = tuiRecord(lines[0]);
    if (!judged.ok)
        return { record: null, logs: [prefix + " reason=" + judged.error] };
    if (judged.record.key !== key || judged.record.run !== run || judged.record.state !== "ended")
        return { record: null, logs: [prefix + " reason=record-mismatch"] };
    return { record: judged.record, logs: [] };
}

// The ended records from `vgshell-tui wait` still needed beside LISTED, the
// records the listing holds, out of WAITED, the wait records held so far.
// One is kept while the listing holds its run's running record and not its
// ended one, so a listing that stays stale across later runs of the key
// cannot show that run running again, and the latest of each key is kept
// for the key's state. Every other is dropped: the kept set is bounded by
// the listed running records plus one per key.
function tuiWaitRecordsKept(listed, waited) {
    var listedEnded = {};
    var listedRunning = {};
    listed.forEach(function (record) {
        if (record.state === "ended")
            listedEnded[record.run] = true;
        else
            listedRunning[record.run] = true;
    });
    var latest = {};
    waited.forEach(function (record) {
        if (!hasOwn(latest, record.key) || record.startedAt > latest[record.key].startedAt)
            latest[record.key] = record;
    });
    return waited.filter(function (record) {
        if (hasOwn(listedEnded, record.run))
            return false;
        return hasOwn(listedRunning, record.run) || latest[record.key] === record;
    });
}

// The window of a run whose record carries WINDOW, { appId, title }, among
// WINDOWS, each { address, appId, title } as the compositor reports it:
// { state: "found", address } with a `0x` address for exactly one match,
// { state: "none" } for none, { state: "ambiguous", count } for more. The
// presenter records the app-id and the title the terminal was opened with,
// and a terminal that honours `--title` keeps it.
function tuiWindow(windows, window) {
    var matches = windows.filter(function (w) {
        return w.appId === window.appId && w.title === window.title && typeof w.address === "string" && w.address !== "";
    });
    if (matches.length === 0)
        return { state: "none" };
    if (matches.length > 1)
        return { state: "ambiguous", count: matches.length };
    var address = matches[0].address;
    return { state: "found", address: address.indexOf("0x") === 0 ? address : "0x" + address };
}

// Whether a bar instance maps a surface on its screen: while it is being
// built (null) and unless it declares `shown` false. BarHost maps the
// window on it, and the service gate waits for no other bar's frame.
function barShown(instance) {
    return instance === null || instance.shown !== false;
}

// Whether a per-screen layer host maps its window. A background includes an
// instance without a `shown` property. A cover starts hidden and maps only
// when an instance asks to cover the screen.
function perScreenLayerShown(kind, instance) {
    if (instance === null)
        return false;
    if (kind === "background")
        return instance.shown !== false;
    if (kind === "cover")
        return instance.shown === true;
    return false;
}

function perScreenLayerTakesKeyboard(kind, screens, screen) {
    return kind === "cover" && Array.isArray(screens) && screens.length > 0 && screen !== null && screens[0].name === screen.name;
}

// What a manifest's `menu` key may hold: launcher rows keyed by a dotted id
// whose dots name its parent, as in the launcher's menu files. A row with a
// `shortcut` runs that registered shortcut of the plugin's own; a row with
// `tui` or `tuiGroup` opens a listed TUI through the launcher; one without a
// kind is a category. A provider row names a launcherRows status key whose
// items fill the category and whose activations call the shortcut with an
// item id. A `toggle` names a boolean setting of the plugin's schema and the
// label, and optionally the icon, the row shows while it is true.
var MENU_ROW_KEYS = ["label", "icon", "aliases", "description", "shortcut", "tui", "tuiGroup", "toggle", "provider"];
var MENU_TOGGLE_KEYS = ["setting", "label", "icon"];
var MENU_ID_PATTERN = /^[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)*$/;
var MENU_TEXT_MAX = 60;
var MENU_DESCRIPTION_MAX = 120;

// The first defect of a manifest's `menu` key, or "": a non-empty object of
// MENU_ID_PATTERN ids to rows of MENU_ROW_KEYS, each with a printable
// `label` and a shipped `icon`, optional printable `aliases` and
// `description`, and at most one of `shortcut`, `tui` and `tuiGroup`.
// `shortcut` names a plugin shortcut and needs capability `shortcut`; `tui`
// names `core/<name>` or `<plugin id>/<name>` and needs no capability; and
// `tuiGroup` names one printable launcher TUI group. A `toggle` of
// MENU_TOGGLE_KEYS needs a shortcut and names a boolean schema entry. A
// `provider` names a status key of type `launcherRows`, needs a shortcut and
// refuses a toggle, `tui` and `tuiGroup`.
function menuError(menu, capabilities, schema, status) {
    if (!isPlainObject(menu) || Object.keys(menu).length === 0)
        return "menu must be a non-empty object of row ids to rows";
    var ids = Object.keys(menu);
    for (var i = 0; i < ids.length; i++) {
        var id = ids[i];
        var at = "menu." + id;
        if (!MENU_ID_PATTERN.test(id))
            return "menu id " + JSON.stringify(id) + " must be dotted lower-case words";
        var item = menu[id];
        if (!isPlainObject(item))
            return at + " must be an object";
        var keys = Object.keys(item);
        for (var k = 0; k < keys.length; k++) {
            if (MENU_ROW_KEYS.indexOf(keys[k]) === -1)
                return at + " has unknown key " + JSON.stringify(keys[k]);
        }
        if (!isPrintableLine(item.label, MENU_TEXT_MAX))
            return at + ".label must be a printable line of 1 to " + MENU_TEXT_MAX + " characters";
        if (typeof item.icon !== "string" || !hasOwn(Lucide.ICONS, item.icon))
            return at + ".icon must name an icon of the shipped set, got " + JSON.stringify(item.icon);
        if (item.aliases !== undefined && (!Array.isArray(item.aliases) || !item.aliases.every(function (alias) { return isPrintableLine(alias, MENU_TEXT_MAX); })))
            return at + ".aliases must be a list of printable lines of 1 to " + MENU_TEXT_MAX + " characters";
        if (item.description !== undefined && !isPrintableLine(item.description, MENU_DESCRIPTION_MAX))
            return at + ".description must be a printable line of 1 to " + MENU_DESCRIPTION_MAX + " characters";
        if (item.shortcut !== undefined) {
            if (typeof item.shortcut !== "string" || !NAME_PATTERN.test(item.shortcut))
                return at + ".shortcut must be a shortcut name, got " + JSON.stringify(item.shortcut);
            if (capabilities.indexOf("shortcut") === -1)
                return at + ".shortcut needs capability shortcut";
        }
        if (item.tui !== undefined && !tuiKeyValid(item.tui))
            return at + ".tui is not a TUI key, core/<name> or <plugin id>/<name>";
        if (item.tuiGroup !== undefined && !isPrintableLine(item.tuiGroup, MENU_TEXT_MAX))
            return at + ".tuiGroup must be a printable line of 1 to " + MENU_TEXT_MAX + " characters";
        if (item.provider !== undefined) {
            if (typeof item.provider !== "string" || !STATUS_KEY_PATTERN.test(item.provider) || !hasOwn(status, item.provider) || status[item.provider].type !== "launcherRows")
                return at + ".provider must name a launcherRows status entry, got " + JSON.stringify(item.provider);
            if (item.tui !== undefined || item.tuiGroup !== undefined)
                return at + ".provider must not declare tui or tuiGroup";
            if (item.shortcut === undefined)
                return at + ".provider needs a shortcut";
            if (item.toggle !== undefined)
                return at + ".provider must not declare toggle";
        }
        if (item.toggle === undefined) {
            var kindKeys = ["shortcut", "tui", "tuiGroup"].filter(function (key) { return item[key] !== undefined; });
            if (kindKeys.length > 1)
                return at + " states " + kindKeys.join(" and ");
            continue;
        }
        if (item.shortcut === undefined)
            return at + ".toggle needs a shortcut";
        if (item.tui !== undefined || item.tuiGroup !== undefined)
            return at + ".toggle must not declare tui or tuiGroup";
        var toggle = item.toggle;
        if (!isPlainObject(toggle))
            return at + ".toggle must be an object";
        var toggleKeys = Object.keys(toggle);
        for (var t = 0; t < toggleKeys.length; t++) {
            if (MENU_TOGGLE_KEYS.indexOf(toggleKeys[t]) === -1)
                return at + ".toggle has unknown key " + JSON.stringify(toggleKeys[t]);
        }
        if (typeof toggle.setting !== "string" || !hasOwn(schema, toggle.setting) || schema[toggle.setting].type !== "boolean")
            return at + ".toggle.setting must name a boolean schema entry, got " + JSON.stringify(toggle.setting);
        if (!isPrintableLine(toggle.label, MENU_TEXT_MAX))
            return at + ".toggle.label must be a printable line of 1 to " + MENU_TEXT_MAX + " characters";
        if (toggle.icon !== undefined && (typeof toggle.icon !== "string" || !hasOwn(Lucide.ICONS, toggle.icon)))
            return at + ".toggle.icon must name an icon of the shipped set, got " + JSON.stringify(toggle.icon);
    }
    return "";
}

// Every enabled plugin's launcher rows under CONFIG: { rows, conflicts }.
// `rows` holds the menus of the plugins in ENABLED_IDS that MANIFESTS
// holds, by plugin id and then in manifest order, gathered under their
// top-level id: each top-level id where its first row is listed, and under
// it the rows of the plugin that declares that id first, so a plugin's row
// in another plugin's category follows that plugin's own. Each row is
// { id, plugin, label, icon, aliases, description, shortcut, provider, tui,
// tuiGroup }: `shortcut` the global `<plugin id>:<name>` the row runs, ""
// for a category or TUI row, `tui` and `tuiGroup` the launcher TUI row fields
// or "", and a toggle row's label and icon those its setting, read from the
// plugin's `plugins` row as its service reads it, makes true. A row id an
// earlier plugin listed stays with that plugin; the later row is one of
// `conflicts`, { id, plugin, heldBy }.
function menuRows(manifests, enabledIds, config) {
    var rows = [];
    var conflicts = [];
    var owners = Object.create(null);
    enabledIds.filter(function (id) { return hasOwn(manifests, id); }).sort().forEach(function (plugin) {
        var manifest = manifests[plugin];
        var menu = manifest.menu;
        var ids = Object.keys(menu);
        if (ids.length === 0)
            return;
        var settings = settingsFor(config, manifest, "plugins", null);
        ids.forEach(function (id) {
            if (owners[id] !== undefined) {
                conflicts.push({ id: id, plugin: plugin, heldBy: owners[id] });
                return;
            }
            owners[id] = plugin;
            var row = menu[id];
            var on = row.toggle !== undefined && settings[row.toggle.setting] === true;
            rows.push({
                id: id,
                plugin: plugin,
                label: on ? row.toggle.label : row.label,
                icon: on && row.toggle.icon !== undefined ? row.toggle.icon : row.icon,
                aliases: (row.aliases || []).slice(),
                description: row.description || "",
                shortcut: row.shortcut === undefined ? "" : plugin + ":" + row.shortcut,
                provider: row.provider === undefined ? "" : row.provider,
                tui: row.tui === undefined ? "" : row.tui,
                tuiGroup: row.tuiGroup === undefined ? "" : row.tuiGroup
            });
        });
    });
    var tops = [];
    var byTop = Object.create(null);
    rows.forEach(function (row) {
        var top = row.id.split(".")[0];
        if (byTop[top] === undefined) {
            byTop[top] = [];
            tops.push(top);
        }
        byTop[top].push(row);
    });
    var ordered = [];
    tops.forEach(function (top) {
        var owner = owners[top];
        ordered = ordered.concat(byTop[top].filter(function (row) { return row.plugin === owner; }), byTop[top].filter(function (row) { return row.plugin !== owner; }));
    });
    return { rows: ordered, conflicts: conflicts };
}

// Dynamic rows published by the provider row MENU_ID, read from VALUES, the
// publishing plugin's status values. Each row id is nested under MENU_ID; a
// non-menu row carries ITEM, the id handed back to the shortcut handler.
function providerRows(rows, menuId, values) {
    var parent = null;
    for (var i = 0; i < rows.length; i++)
        if (rows[i].id === menuId && rows[i].provider !== undefined && rows[i].provider !== "") parent = rows[i];
    if (parent === null || !isPlainObject(values) || !Array.isArray(values[parent.provider])) return [];
    return values[parent.provider].map(function (item) {
        return {
            id: menuId + "." + item.id,
            label: item.label,
            icon: item.icon,
            description: item.description || "",
            aliases: item.aliases ? item.aliases.slice() : [],
            menu: item.menu === true,
            shortcut: parent.shortcut,
            item: item.id
        };
    });
}

function providerItemListed(row, values, item) {
    if (row.provider === undefined || row.provider === "" || !isPlainObject(values) || !Array.isArray(values[row.provider])) return false;
    return values[row.provider].some(function (published) { return published.id === item && published.menu !== true; });
}

// The answer to running global KEY from a launcher row: "ok" when ROWS,
// menuRows' rows, list a plain row that runs it and REGISTERED holds it.
// With ITEM, only a provider row may run, and only for a published non-menu
// item. VALUES_BY_PLUGIN maps plugin id to that plugin's status values.
function menuActivation(rows, registered, key, item, valuesByPlugin) {
    if (item !== undefined && item !== null && item !== "") {
        var listed = false;
        for (var p = 0; p < rows.length; p++) {
            var row = rows[p];
            if (row.shortcut !== key || row.provider === undefined || row.provider === "") continue;
            var values = isPlainObject(valuesByPlugin) && hasOwn(valuesByPlugin, row.plugin) ? valuesByPlugin[row.plugin] : {};
            if (providerItemListed(row, values, item)) listed = true;
        }
        if (!listed)
            return "refused: shortcut=" + tuiLabel(key) + " item=" + tuiLabel(item) + " reason=unlisted";
        if (!hasOwn(registered, key))
            return "refused: shortcut=" + tuiLabel(key) + " reason=unregistered";
        return "ok";
    }
    var listed = typeof key === "string" && key !== "" && rows.some(function (row) { return row.shortcut === key && (row.provider === undefined || row.provider === ""); });
    if (!listed)
        return "refused: shortcut=" + tuiLabel(key) + " reason=unlisted";
    if (!hasOwn(registered, key))
        return "refused: shortcut=" + tuiLabel(key) + " reason=unregistered";
    return "ok";
}

// Validate one manifest object. Returns { ok: true, manifest } with the
// normalized manifest, or { ok: false, error } naming the first defect.
// `sourceDir` is recorded on the manifest so entry points resolve later.
// A normalized manifest always carries `capabilities` and `requirements`
// (arrays, the latter's entries normalRequirements' shape), `settings`,
// `schema`, `status` and `tui` (objects, `tui` normalTui's shape),
// `menu` (an object, {} when undeclared),
// `defaultSection` only when declared, and
// `hyprland` only when declared, as { binds, layerRules, appearance,
// options } with every bind's key normalised by hyprlandKey.
function validateManifest(raw, sourceDir) {
    if (!isPlainObject(raw))
        return { ok: false, error: "manifest is not a JSON object" };
    if (hasOwn(raw, "requires"))
        return { ok: false, error: "requires is refused: a plugin names no other plugin (D005); declare the external commands it runs under requirements" };
    var keys = Object.keys(raw);
    for (var u = 0; u < keys.length; u++) {
        if (MANIFEST_KEYS.indexOf(keys[u]) === -1)
            return { ok: false, error: "unknown key " + JSON.stringify(keys[u]) };
    }
    if (raw.schemaVersion !== 1)
        return { ok: false, error: "schemaVersion must be 1, got " + JSON.stringify(raw.schemaVersion) };
    if (typeof raw.id !== "string" || !ID_PATTERN.test(raw.id))
        return { ok: false, error: "id must be dotted and author-namespaced, got " + JSON.stringify(raw.id) };
    var required = ["name", "version", "author", "description"];
    for (var i = 0; i < required.length; i++) {
        if (typeof raw[required[i]] !== "string" || raw[required[i]].length === 0)
            return { ok: false, error: required[i] + " must be a non-empty string" };
    }
    if (raw.license !== undefined && (typeof raw.license !== "string" || raw.license.length === 0))
        return { ok: false, error: "license must be a non-empty string when present" };
    if (raw.icon !== undefined && (typeof raw.icon !== "string" || !hasOwn(Lucide.ICONS, raw.icon)))
        return { ok: false, error: "icon must name an icon of the shipped set, shell/Ui/icons/Lucide.js, got " + JSON.stringify(raw.icon) };
    if (!Array.isArray(raw.kinds) || raw.kinds.length === 0)
        return { ok: false, error: "kinds must be a non-empty array" };
    for (var k = 0; k < raw.kinds.length; k++) {
        if (KINDS.indexOf(raw.kinds[k]) === -1)
            return { ok: false, error: "unknown kind " + JSON.stringify(raw.kinds[k]) };
        if (raw.kinds.indexOf(raw.kinds[k]) !== k)
            return { ok: false, error: "kind " + JSON.stringify(raw.kinds[k]) + " is declared twice" };
    }
    if (!isPlainObject(raw.entryPoints))
        return { ok: false, error: "entryPoints must be an object" };
    var entryKeys = Object.keys(raw.entryPoints);
    for (var x = 0; x < entryKeys.length; x++) {
        if (raw.kinds.indexOf(entryKeys[x]) === -1)
            return { ok: false, error: "entryPoints." + entryKeys[x] + " names a kind the manifest does not declare" };
    }
    for (var e = 0; e < raw.kinds.length; e++) {
        var kind = raw.kinds[e];
        var entry = raw.entryPoints[kind];
        if (typeof entry !== "string" || entry.length === 0)
            return { ok: false, error: "entryPoints." + kind + " is required for kind " + kind };
        if (entry.indexOf("..") !== -1 || entry.charAt(0) === "/")
            return { ok: false, error: "entryPoints." + kind + " must stay inside the plugin directory" };
    }
    // A plugin that owns its look names the `.pragma library` file whose
    // `TOKENS` and `LIGHT` ThemeLogic.acceptAppearance judges; the design
    // token check reads the table from it.
    if (raw.appearance !== undefined) {
        if (typeof raw.appearance !== "string" || !/\.js$/.test(raw.appearance))
            return { ok: false, error: "appearance must name a .js file, got " + JSON.stringify(raw.appearance) };
        if (raw.appearance.indexOf("..") !== -1 || raw.appearance.charAt(0) === "/")
            return { ok: false, error: "appearance must stay inside the plugin directory" };
    }
    var capabilities = raw.capabilities === undefined ? [] : raw.capabilities;
    if (!Array.isArray(capabilities))
        return { ok: false, error: "capabilities must be an array" };
    for (var c = 0; c < capabilities.length; c++) {
        if (CAPABILITIES.indexOf(capabilities[c]) === -1)
            return { ok: false, error: "unknown capability " + JSON.stringify(capabilities[c]) };
    }
    if (capabilities.indexOf("panes") !== -1 && raw.kinds.indexOf("window") === -1)
        return { ok: false, error: "capability panes needs kind window" };
    var settings = raw.settings === undefined ? {} : raw.settings;
    if (!isPlainObject(settings))
        return { ok: false, error: "settings must be an object" };
    if (hasOwn(settings, "id"))
        return { ok: false, error: "settings must not carry an id key" };
    if (hasOwn(settings, "keys"))
        return { ok: false, error: "settings must not carry a keys key: a plugins row's keys are its Hyprland keys" };
    if (hasOwn(settings, "placement") && PLACEMENTS.indexOf(settings.placement) === -1)
        return { ok: false, error: "settings.placement must be one of " + PLACEMENTS.join(", ") + ", got " + JSON.stringify(settings.placement) };
    // The requirements first: a status action names the requirements it
    // installs from them.
    var requirements = raw.requirements === undefined ? [] : raw.requirements;
    var badRequirements = requirementsError(requirements);
    if (badRequirements !== "")
        return { ok: false, error: badRequirements };
    // The system steps before the status: an action names a step from them.
    if (raw.systemSteps !== undefined) {
        var badSteps = systemStepsError(raw.systemSteps, capabilities);
        if (badSteps !== "")
            return { ok: false, error: badSteps };
    } else if (capabilities.indexOf("system") !== -1) {
        return { ok: false, error: "capability system needs a systemSteps declaration" };
    }
    if (raw.status !== undefined) {
        var badStatus = statusError(raw.status, capabilities, raw.tui, requirements, raw.systemSteps);
        if (badStatus !== "")
            return { ok: false, error: badStatus };
    } else if (capabilities.indexOf("status") !== -1) {
        return { ok: false, error: "capability status needs a status declaration" };
    }
    var schema = raw.schema === undefined ? {} : raw.schema;
    var badSchema = schemaError(schema, settings, raw.status === undefined ? {} : raw.status);
    if (badSchema !== "")
        return { ok: false, error: badSchema };
    if (capabilities.indexOf("configure") !== -1 && Object.keys(schema).length === 0)
        return { ok: false, error: "capability configure needs a schema" };
    if (raw.defaultSection !== undefined) {
        if (raw.kinds.indexOf("bar-widget") === -1)
            return { ok: false, error: "defaultSection needs kind bar-widget" };
        if (SECTIONS.indexOf(raw.defaultSection) === -1)
            return { ok: false, error: "defaultSection must be one of " + SECTIONS.join(", ") + ", got " + JSON.stringify(raw.defaultSection) };
    }
    // `alwaysOn` holds the "first-party" rule of enablementRule against
    // every disable, so only a manifest that rule serves may set it.
    if (raw.alwaysOn !== undefined) {
        if (typeof raw.alwaysOn !== "boolean")
            return { ok: false, error: "alwaysOn must be a boolean when present" };
        if (raw.alwaysOn && enablementRule(raw) !== "first-party")
            return { ok: false, error: "alwaysOn needs the first-party rule: a vgs. id, no kind bar, and a kind beside bar-widget" };
    }
    if (raw.pane !== undefined) {
        var badPane = paneError(raw.pane, raw.kinds);
        if (badPane !== "")
            return { ok: false, error: badPane };
    } else if (raw.kinds.indexOf("pane") !== -1) {
        return { ok: false, error: "kind pane needs a pane declaration" };
    }
    if (raw.hyprland !== undefined) {
        var badHyprland = hyprlandError(raw.hyprland, capabilities, schema);
        if (badHyprland !== "")
            return { ok: false, error: badHyprland };
        if (raw.hyprland.monitors !== undefined) {
            if (!hasOwn(settings, raw.hyprland.monitors))
                return { ok: false, error: "hyprland.monitors names no settings key " + JSON.stringify(raw.hyprland.monitors) };
            if (hasOwn(schema, raw.hyprland.monitors))
                return { ok: false, error: "hyprland.monitors must not name a schema entry" };
            var badMonitorDefault = MonitorLogic.rulesError(settings[raw.hyprland.monitors], null);
            if (badMonitorDefault !== "")
                return { ok: false, error: badMonitorDefault.replace("refused: monitors", "hyprland.monitors default") };
        }
    }
    if (raw.tui !== undefined) {
        var badTui = tuiError(raw.tui, capabilities, requirements);
        if (badTui !== "")
            return { ok: false, error: badTui };
    }
    if (raw.menu !== undefined) {
        var badMenu = menuError(raw.menu, capabilities, schema, raw.status === undefined ? {} : raw.status);
        if (badMenu !== "")
            return { ok: false, error: badMenu };
    }
    if (raw.secrets !== undefined) {
        var badSecrets = secretsError(raw.secrets, capabilities, raw.status);
        if (badSecrets !== "")
            return { ok: false, error: badSecrets };
    } else if (capabilities.indexOf("secrets") !== -1) {
        return { ok: false, error: "capability secrets needs a secrets declaration" };
    }
    var manifest = clone(raw);
    manifest.capabilities = capabilities.slice();
    manifest.requirements = normalRequirements(requirements);
    manifest.tui = normalTui(raw.tui === undefined ? {} : raw.tui);
    manifest.menu = raw.menu === undefined ? {} : clone(raw.menu);
    manifest.settings = clone(settings);
    manifest.schema = clone(schema);
    manifest.status = raw.status === undefined ? {} : clone(raw.status);
    if (raw.pane !== undefined) manifest.pane = clone(raw.pane);
    manifest.systemSteps = raw.systemSteps === undefined ? [] : raw.systemSteps.slice();
    if (raw.hyprland !== undefined) {
        manifest.hyprland = {
            binds: (raw.hyprland.binds || []).map(function (bind) {
                var result = { shortcut: bind.shortcut, key: keyRowValue(bind.key) };
                if (bind.hold === true) result.hold = true;
                if (bind.tap === true) result.tap = true;
                if (bind.info !== undefined) result.info = bind.info;
                return result;
            }),
            layerRules: clone(raw.hyprland.layerRules || []),
            appearance: clone(raw.hyprland.appearance || {}),
            options: clone(raw.hyprland.options || {}),
            pads: raw.hyprland.pads,
            monitors: raw.hyprland.monitors
        };
    }
    manifest.__sourceDir = sourceDir;
    return { ok: true, manifest: manifest };
}

// Merge the shipped defaults with the user file. Every top-level key in the
// user file replaces the shipped key whole, except `plugins`, whose entries
// merge by id with the user entry winning, and `disabledPlugins`, which is
// the user list when present. A shipped plugin entry the user file does not
// name still applies, which is the point of keeping two layers.
function effectiveConfig(shipped, user) {
    var out = clone(shipped);
    if (!isPlainObject(user))
        return out;
    Object.keys(user).forEach(function (key) {
        if (key === "plugins") {
            var byId = {};
            var order = [];
            (Array.isArray(out.plugins) ? out.plugins : []).forEach(function (entry) {
                byId[entry.id] = entry;
                order.push(entry.id);
            });
            user.plugins.forEach(function (entry) {
                if (!hasOwn(byId, entry.id)) order.push(entry.id);
                byId[entry.id] = entry;
            });
            out.plugins = order.map(function (id) { return byId[id]; });
        } else {
            out[key] = clone(user[key]);
        }
    });
    return out;
}

// The layout entries of one section, in order; [] when the section or the
// layout is absent. Both files passed configError, so every entry is an
// object with a string id.
function sectionEntries(config, section) {
    var layout = config && config.bar && isPlainObject(config.bar.layout) ? config.bar.layout : {};
    return Array.isArray(layout[section]) ? layout[section] : [];
}

// Ids placed in the bar layout, in section order.
function layoutIds(config) {
    var ids = [];
    SECTIONS.forEach(function (section) {
        sectionEntries(config, section).forEach(function (entry) { ids.push(entry.id); });
    });
    return ids;
}

// The id of the plugin whose window is the manager's user interface,
// config.manager.id, or "" when the file names none. Its window opens at a
// plugin's page on the payload { plugin: <id> }.
function managerId(config) {
    return isPlainObject(config) && isPlainObject(config.manager) && typeof config.manager.id === "string" ? config.manager.id : "";
}

// The active bar id: config.bar.id, or the shipped default bar when absent.
function activeBarId(config, defaultBarId) {
    return config && config.bar && typeof config.bar.id === "string" && config.bar.id.length > 0 ? config.bar.id : defaultBarId;
}

// The first layout entry with `id`, in section order, or null.
function layoutEntryOf(config, id) {
    for (var i = 0; i < SECTIONS.length; i++) {
        var hit = sectionEntries(config, SECTIONS[i]).filter(function (entry) { return entry.id === id; })[0];
        if (hit !== undefined) return hit;
    }
    return null;
}

// The position of LOCATOR, `{ section, nth }`, for plugin ID in CONFIG, or
// null. `nth` counts entries with ID in one section, the same locator
// withSetting receives from a mounted widget.
function layoutPositionOf(config, id, locator) {
    if (isPlainObject(locator) && SECTIONS.indexOf(locator.section) !== -1 && Number.isInteger(locator.nth) && locator.nth >= 0) {
        var seen = 0;
        var entries = sectionEntries(config, locator.section);
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].id !== id) continue;
            if (seen === locator.nth) return { section: locator.section, index: i, nth: locator.nth, entry: entries[i] };
            seen += 1;
        }
        return null;
    }
    for (var s = 0; s < SECTIONS.length; s++) {
        var section = SECTIONS[s];
        var rows = sectionEntries(config, section);
        for (var n = 0; n < rows.length; n++) {
            if (rows[n].id !== id) continue;
            return { section: section, index: n, nth: 0, entry: rows[n] };
        }
    }
    return null;
}

// The plugins[] row with `id`, or undefined.
function pluginRow(config, id) {
    return (config && Array.isArray(config.plugins) ? config.plugins : []).filter(function (entry) {
        return entry.id === id;
    })[0];
}

// The configuration entries a plugin's settings live in, in the order a
// plugin's target list reports them.
var SETTING_TARGETS = ["layout", "plugins"];

// The configuration entry an instance of `kind` reads its settings from
// and writes them to: "layout", its layout entry, for a bar widget;
// "plugins", the plugins[] row with its id, for every other kind. The one
// place this is decided; settingTargets, the configure capability and every
// core caller of settingsFor call it.
function settingTargetOf(kind) {
    return kind === "bar-widget" ? "layout" : "plugins";
}

// The settings a plugin receives from setting target `target`, one of
// SETTING_TARGETS: its manifest's `settings` under that entry. For
// "layout" the entry is `layoutEntry`, the widget's own layout entry the
// caller passes; for "plugins" it is the plugins[] row with the plugin's
// id, and `layoutEntry` is not read. A caller holding an instance's kind
// passes settingTargetOf(kind). Keys the entry sets win, but for the keys
// ENTRY_RESERVED_KEYS names, which are no setting. The result holds only
// declared settings and is a fresh object.
function settingsFor(config, manifest, target, layoutEntry) {
    var out = {};
    Object.keys(manifest.settings).forEach(function (k) { out[k] = manifest.settings[k]; });
    var entry;
    if (target === "layout") entry = layoutEntry;
    else if (target === "plugins") entry = pluginRow(config, manifest.id);
    else throw new Error("settingsFor: target " + JSON.stringify(target) + " is not one of " + SETTING_TARGETS.join(", "));
    return copyEntrySettings(clone(out), entry, manifest, false);
}

// Copy declared settings without reading undeclared values. Stored entries
// also keep their reserved keys; runtime settings and placement transfers
// exclude them. Values are copied so TARGET and ENTRY share nothing.
function copyEntrySettings(target, entry, manifest, stored) {
    if (isPlainObject(entry))
        Object.keys(entry).forEach(function (k) {
            if (hasOwn(manifest.settings, k) || (stored && ENTRY_RESERVED_KEYS.indexOf(k) !== -1))
                target[k] = clone(entry[k]);
        });
    return target;
}

// Keys of a configuration entry that are no setting: the plugin's `id`, and
// a plugins row's Hyprland `keys`, read through hyprlandSection.
// validateManifest refuses a default setting under either name.
var ENTRY_RESERVED_KEYS = ["id", "keys"];

// What plugin MANIFEST asks of Hyprland under CONFIG: { id, version, binds,
// layerRules, appearance, options, unknownKeys }. `binds` follows the manifest's
// `hyprland.binds` in order, each { shortcut, key, hold?, tap?, info? }: each key
// its plugins row's `keys` gives that shortcut, else each key of the
// manifest's, becomes one bind, normalised; one bind with key null when the
// row gives null (the user unbinds it) or the manifest gives none.
// `appearance` resolves each declared group to the boolean effective
// setting the plugin receives.
// `options` follows the manifest's `hyprland.options` in order, holding
// only the settings its plugins row sets, so an option the user never set
// is never written: { kind: "set", setting, path, value } for a value that
// fits the setting's schema entry, { kind: "unfit", setting, path, error }
// with settingError's reason for one that does not. Pads.expand gives
// `pads`, `padRefusals` and the last binds.
// `unknownKeys` lists, sorted, each name the row's `keys` gives that no bind
// declares. A manifest without `hyprland` asks nothing: empty lists, no
// appearance, and its row's names all unknown. CONFIG passed configError, so
// every key it gives is well formed.
function hyprlandSection(config, manifest) {
    var row = pluginRow(config, manifest.id);
    var keys = row !== undefined && isPlainObject(row.keys) ? row.keys : {};
    var declared = manifest.hyprland === undefined ? { binds: [], layerRules: [], appearance: {}, options: {} } : manifest.hyprland;
    var binds = [];
    declared.binds.forEach(function (bind) {
        var given = hasOwn(keys, bind.shortcut) ? keys[bind.shortcut] : bind.key;
        if (given === null) {
            binds.push(Object.assign({}, bind, { key: null }));
            return;
        }
        keyValues(given).forEach(function (value) {
            var key = hyprlandKey(value);
            if (!key.ok)
                throw new Error("hyprlandSection: key of " + manifest.id + ":" + bind.shortcut + " passed its judge but " + key.error);
            var result = Object.assign({}, bind, { key: key.key });
            if (bind.tap === true && keyHasModifiers(key.key))
                result.error = "tap key must be a lone key with no modifiers";
            binds.push(result);
        });
    });
    var names = declared.binds.map(function (bind) { return bind.shortcut; });
    var settings = settingsFor(config, manifest, "plugins", null);
    var appearance = {};
    Object.keys(declared.appearance || {}).forEach(function (group) {
        var setting = declared.appearance[group];
        appearance[group] = { setting: setting, enabled: settings[setting] === true };
    });
    var pads = Pads.expand(declared.pads, manifest.schema, settings, keys, hyprlandKey, settingError);
    var options = [];
    Object.keys(declared.options).forEach(function (setting) {
        if (row === undefined || !hasOwn(row, setting)) return;
        var path = declared.options[setting];
        var unfit = settingError(manifest.schema[setting], row[setting]);
        if (unfit !== "") {
            options.push({ kind: "unfit", setting: setting, path: path, error: unfit });
            return;
        }
        var literal = HyprlandLayer.optionLiteral(HyprlandLayer.OPTIONS[path], row[setting]);
        options.push(literal.ok ? { kind: "set", setting: setting, path: path, value: clone(row[setting]), lua: literal.lua } : { kind: "unfit", setting: setting, path: path, error: literal.error });
    });
    var monitors = null;
    if (declared.monitors !== undefined) {
        var monitorValue = clone(settings[declared.monitors] || {});
        var monitorBad = MonitorLogic.rulesError(monitorValue, null);
        monitors = monitorBad === "" ? { kind: "set", setting: declared.monitors, value: monitorValue } : { kind: "unfit", setting: declared.monitors, error: monitorBad };
    }
    return {
        id: manifest.id,
        version: manifest.version,
        binds: binds.concat(pads.binds),
        layerRules: clone(declared.layerRules),
        appearance: appearance,
        options: options,
        monitors: monitors,
        pads: pads.pads,
        padRefusals: pads.refusals,
        unknownKeys: Object.keys(keys).filter(function (name) { return names.indexOf(name) === -1 && !Pads.isPadShortcut(declared, name, NAME_PATTERN); }).sort()
    };
}

function monitorRuleOwners(manifests, enabledIds) {
    return enabledIds.filter(function (id) {
        var manifest = manifests[id];
        return manifest !== undefined && manifest.hyprland !== undefined && manifest.hyprland.monitors !== undefined;
    }).sort();
}

function monitorRuleOwner(manifests, enabledIds, held) {
    var owners = monitorRuleOwners(manifests, enabledIds);
    var heldOwners = owners.filter(function (id) { return hasOwn(held || {}, "monitors") && held.monitors === id; });
    if (heldOwners.length > 0) return heldOwners[0];
    return owners.length === 0 ? "" : owners[0];
}

function monitorRuleRefusal(manifests, enabledIds, held, id) {
    var owner = monitorRuleOwner(manifests, enabledIds, held);
    return owner !== "" && id !== owner && monitorRuleOwners(manifests, enabledIds).indexOf(id) !== -1 ? "refused: hyprland.monitors=" + id + " held-by=" + owner : "";
}

// The settings the plugin manager shows for a plugin: the ones its placed
// bar widget reads, from its first layout entry, or, for a plugin with no
// placed widget, the ones every other kind reads from its plugins[] row.
function managerSettings(config, manifest) {
    var entry = manifest.kinds.indexOf("bar-widget") !== -1 ? layoutEntryOf(config, manifest.id) : null;
    return entry !== null ? settingsFor(config, manifest, "layout", entry) : settingsFor(config, manifest, "plugins", null);
}

// Whether plugin MANIFEST's widget is placed under CONFIG: the manifest
// declares kind bar-widget and a bar section holds an entry with its id.
// Enablement is apart: a disabled plugin's entry still reads placed, and
// effectiveLayout leaves it off the screen. The one placed reading; the
// manager rows and every rule here that asks it call this.
function isPlaced(config, manifest) {
    return manifest.kinds.indexOf("bar-widget") !== -1 && layoutIds(config).indexOf(manifest.id) !== -1;
}

// What enables plugin MANIFEST, apart from disabledPlugins[], which wins
// over each answer. isEnabled matches on it, and each edit that gives a
// plugin its presence or takes one away asks it.
// - "bar": it declares kind bar and is enabled only as the active bar.
// - "widget": its only kind is bar-widget, so only a placed widget
//   enables it.
// - "first-party": it declares another kind, its id is under the `vgs.`
//   prefix, so it is enabled whether placed or not.
// - "row": a third-party plugin of another kind, enabled by its plugins[]
//   row or by a placed widget.
function enablementRule(manifest) {
    if (manifest.kinds.indexOf("bar") !== -1) return "bar";
    if (manifest.kinds.every(function (k) { return k === "bar-widget"; })) return "widget";
    return manifest.id.indexOf(FIRST_PARTY_PREFIX) === 0 ? "first-party" : "row";
}

// Whether a plugin is enabled under this configuration, by its
// enablementRule.
// - A plugin whose manifest sets `alwaysOn` is enabled whatever the
//   configuration says, a disabledPlugins[] row included.
// - disabledPlugins[] wins over every other rule.
// - A plugin declaring kind bar is enabled only as the active bar; every
//   other kind it declares comes and goes with its bar.
// - A bar widget is enabled when placed in a bar section.
// - A plugin declaring a kind other than bar and bar-widget is enabled when
//   listed in plugins[], and unlisted when it is first-party (id under the
//   `vgs.` prefix). A bar's settings row in plugins[]
//   enables nothing.
function isEnabled(config, manifest, defaultBarId) {
    if (manifest.alwaysOn === true)
        return true;
    var disabled = Array.isArray(config.disabledPlugins) ? config.disabledPlugins : [];
    if (disabled.indexOf(manifest.id) !== -1)
        return false;
    var rule = enablementRule(manifest);
    if (rule === "bar")
        return activeBarId(config, defaultBarId) === manifest.id;
    if (isPlaced(config, manifest))
        return true;
    if (rule === "widget") return false;
    if (rule === "first-party") return true;
    if (rule === "row") return pluginRow(config, manifest.id) !== undefined;
    throw new Error("isEnabled: enablement rule " + JSON.stringify(rule) + " is not one of bar, widget, first-party, row");
}

// The ids the configuration lists in `disabledPlugins` and `plugins` that
// no discovered plugin in `manifests` has, as { id, key } rows, `key` the
// configuration key that lists the id, in that key order and then in list
// order, each id once per key. A plugin removed or renamed leaves its id
// behind; the manager reports the row and changes nothing.
function unknownIds(config, manifests) {
    var out = [];
    function report(key, ids) {
        ids.forEach(function (id) {
            var listed = out.some(function (row) { return row.id === id && row.key === key; });
            if (!hasOwn(manifests, id) && !listed) out.push({ id: id, key: key });
        });
    }
    report("disabledPlugins", Array.isArray(config.disabledPlugins) ? config.disabledPlugins : []);
    report("plugins", (Array.isArray(config.plugins) ? config.plugins : []).map(function (entry) { return entry.id; }));
    return out;
}

// A registration name belongs only to the enabled active bar's catalogue.
function builtinOwner(config, manifests, defaultBarId, builtinNames, id) {
    var barId = activeBarId(config, defaultBarId);
    var prefix = barId + "/";
    var bar = hasOwn(manifests, barId) ? manifests[barId] : undefined;
    return bar !== undefined && isEnabled(config, bar, defaultBarId)
        && id.indexOf(prefix) === 0 && Array.isArray(builtinNames)
        && builtinNames.indexOf(id.slice(prefix.length)) !== -1 ? bar : null;
}

// One section order for enabled plugin widgets and advertised builtins.
// A registration has one object, so only its first placement is drawn.
function effectiveLayout(config, manifests, defaultBarId, builtinNames) {
    var out = {};
    var seenBuiltins = [];
    SECTIONS.forEach(function (section) {
        out[section] = sectionEntries(config, section).filter(function (entry) {
            var owner = builtinOwner(config, manifests, defaultBarId, builtinNames, entry.id);
            if (owner !== null) {
                if (seenBuiltins.indexOf(entry.id) !== -1) return false;
                seenBuiltins.push(entry.id);
                return true;
            }
            var m = hasOwn(manifests, entry.id) ? manifests[entry.id] : undefined;
            return m !== undefined && m.kinds.indexOf("bar-widget") !== -1 && isEnabled(config, m, defaultBarId);
        }).map(clone);
    });
    return out;
}

// Enabled bar widgets that stop showing when `id`, the active bar, is
// disabled. They stay enabled and keep every other kind they declare; the
// manager reports them so the user knows what leaves the screen. Only a
// placed widget shows, so a plugin enabled for another kind while its
// widget is unplaced hides nothing.
function hiddenByDisabling(manifests, config, id, defaultBarId) {
    var m = hasOwn(manifests, id) ? manifests[id] : undefined;
    if (!m || m.kinds.indexOf("bar") === -1 || activeBarId(config, defaultBarId) !== id)
        return [];
    return Object.keys(manifests).filter(function (other) {
        var o = manifests[other];
        return other !== id && isPlaced(config, o) && isEnabled(config, o, defaultBarId);
    }).sort();
}

// The user-file change that enables or disables one plugin. Returns the new
// user object; the caller writes it.
//
// Disabling only lists the id in disabledPlugins: every placement, every
// settings row and the active bar id stay in the file, so re-enabling
// restores the screen exactly. Enabling unlists the id and, only when the
// plugin has no presence yet, gives it one: a bar becomes the active bar; a
// bar widget not placed in any section is placed in its default section
// (`center` when the manifest names none); a "row" plugin (enablementRule)
// of another kind not listed in plugins[] is listed. A bar edit seeds the user `bar`
// first (seedUserBar), so it keeps every other widget in place. Enabling a
// plugin that already has its presence changes nothing but the disabled
// list.
function withEnabled(user, manifest, enabled, effective) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = CONFIG_VERSION;
    var disabled = Array.isArray(effective.disabledPlugins) ? effective.disabledPlugins.slice() : [];
    if (!enabled) {
        if (disabled.indexOf(manifest.id) === -1) disabled.push(manifest.id);
        out.disabledPlugins = disabled;
        return out;
    }
    out.disabledPlugins = disabled.filter(function (d) { return d !== manifest.id; });
    var isBar = manifest.kinds.indexOf("bar") !== -1;
    var isWidget = manifest.kinds.indexOf("bar-widget") !== -1;
    if (isBar && activeBarId(effective, "") !== manifest.id) {
        seedUserBar(out, effective);
        out.bar.id = manifest.id;
    }
    if (isWidget && !isPlaced(effective, manifest))
        placeWidget(out, manifest, effective);
    if (!isWidget && enablementRule(manifest) === "row" && pluginRow(effective, manifest.id) === undefined) {
        var plugins = Array.isArray(out.plugins) ? out.plugins : [];
        plugins.push({ id: manifest.id });
        out.plugins = plugins;
    }
    return out;
}

// Give OUT, a user file being edited, a `bar` copied from EFFECTIVE's when
// it has none. A user `bar` key replaces the shipped one whole, so a bar
// edit made without this would drop every other widget.
function seedUserBar(out, effective) {
    if (!isPlainObject(out.bar))
        out.bar = effective && isPlainObject(effective.bar) ? clone(effective.bar) : {};
}

// Place plugin MANIFEST's widget in OUT, a user file being edited: one
// entry at the end of its default section, `center` when the manifest names
// none. The entry carries the settings of the plugin's effective plugins[]
// row: the manager writes a plugin-wide setting to both entries
// (settingTargets), so a setting outlives an unplace and a place. The one
// placement rule; enabling and placing both call it.
function placeWidget(out, manifest, effective) {
    seedUserBar(out, effective);
    if (!isPlainObject(out.bar.layout)) out.bar.layout = { left: [], center: [], right: [] };
    var section = typeof manifest.defaultSection === "string" ? manifest.defaultSection : "center";
    if (!Array.isArray(out.bar.layout[section])) out.bar.layout[section] = [];
    out.bar.layout[section].push(copyEntrySettings({ id: manifest.id }, pluginRow(effective, manifest.id), manifest, false));
}

// Why plugin MANIFEST's widget may not be placed or unplaced under CONFIG,
// or "": a plugin without kind bar-widget has no widget, and a disabled
// plugin is refused, as its setting is. The reply is one keyed line.
function placedRefusal(config, manifest, defaultBarId) {
    if (manifest.kinds.indexOf("bar-widget") === -1)
        return "refused: placed=" + manifest.id + " reason=no-bar-widget";
    if (!isEnabled(config, manifest, defaultBarId))
        return "refused: placed=" + manifest.id + " reason=disabled";
    return "";
}

// Why plugin MANIFEST's widget may not be moved under CONFIG to SECTION at
// INDEX, or "". Moving keeps the existing layout entry and its settings, so
// it needs a placed and enabled widget. SECTION and INDEX are the persisted
// layout address, not pixel geometry.
function moveRefusal(config, manifest, section, index, defaultBarId) {
    if (manifest.kinds.indexOf("bar-widget") === -1)
        return "refused: moved=" + manifest.id + " reason=no-bar-widget";
    if (isPlaced(config, manifest) && !isEnabled(config, manifest, defaultBarId))
        return "refused: moved=" + manifest.id + " reason=disabled";
    if (!isPlaced(config, manifest))
        return "refused: moved=" + manifest.id + " reason=unplaced";
    if (SECTIONS.indexOf(section) === -1)
        return "refused: section=" + JSON.stringify(section) + " want=left|center|right";
    if (typeof index !== "number" || !Number.isInteger(index) || index < 0)
        return "refused: index=" + JSON.stringify(index) + " want=integer>=0";
    return "";
}

// Why plugin MANIFEST may not be set to ENABLED, or "": a plugin whose
// manifest sets `alwaysOn` refuses a disable. The reply is one keyed line.
function enabledRefusal(manifest, enabled) {
    if (!enabled && manifest.alwaysOn === true)
        return "refused: enabled=" + manifest.id + " reason=always-on";
    return "";
}

// The user-file change that shows or hides plugin MANIFEST's widget in the
// bar. disabledPlugins is never read or written. Returns the new user
// object; the caller checks placedRefusal first and writes it.
//
// Placing an unplaced widget is placeWidget. Unplacing seeds the user `bar`
// and removes every layout entry with the plugin's id from every section.
// It lists a plugin with no plugins[] row there, the row seeded with the
// first removed entry's settings: the row is the record firstPresence reads
// as the user's choice, so a hidden widget stays hidden, and a "row" plugin
// (enablementRule), enabled only by its placement, stays enabled through
// it. A "widget" plugin has nothing left once unplaced: it reads as
// disabled until enabling places it again. A widget already as asked
// changes nothing but the version stamp.
function withPlaced(user, manifest, placed, effective) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = CONFIG_VERSION;
    if (placed === isPlaced(effective, manifest))
        return out;
    if (placed) {
        placeWidget(out, manifest, effective);
        return out;
    }
    seedUserBar(out, effective);
    if (pluginRow(effective, manifest.id) === undefined) {
        var row = copyEntrySettings({ id: manifest.id }, layoutEntryOf(out, manifest.id), manifest, false);
        out.plugins = (Array.isArray(out.plugins) ? out.plugins : []).concat([row]);
    }
    SECTIONS.forEach(function (section) {
        var entries = out.bar.layout[section];
        if (Array.isArray(entries))
            out.bar.layout[section] = entries.filter(function (entry) { return entry.id !== manifest.id; });
    });
    return out;
}

// The user-file change that moves plugin MANIFEST's widget. FROM is
// `{ section, nth }` or null for the first entry in section order. INDEX is
// the target section's entry index after the source entry has been removed.
// The moved entry keeps its settings.
function withMoved(user, manifest, from, section, index, effective) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = CONFIG_VERSION;
    seedUserBar(out, effective);
    if (!isPlainObject(out.bar.layout)) out.bar.layout = { left: [], center: [], right: [] };
    for (var s = 0; s < SECTIONS.length; s++)
        if (!Array.isArray(out.bar.layout[SECTIONS[s]])) out.bar.layout[SECTIONS[s]] = [];
    var source = layoutPositionOf(out, manifest.id, from);
    if (source === null) return out;
    var entry = out.bar.layout[source.section].splice(source.index, 1)[0];
    var target = out.bar.layout[section];
    var at = Math.max(0, Math.min(index, target.length));
    target.splice(at, 0, entry);
    return out;
}

function locatorEquals(locator, id, section, nth) {
    return isPlainObject(locator) && locator.section === section && locator.id === id && locator.nth === nth;
}

// Convert a drop target `{ section, before }` into the configuration index
// `withMoved` takes: the index of BEFORE in SECTION after FROM has been
// removed, or the section's end when BEFORE is null.
function barDropIndex(config, section, before, from, movingId) {
    var kept = [];
    var nthById = {};
    var entries = sectionEntries(config, section);
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        var nth = nthById[entry.id] || 0;
        nthById[entry.id] = nth + 1;
        var removes = isPlainObject(from) && from.section === section && entry.id === movingId && from.nth === nth;
        if (!removes && before !== null && locatorEquals(before, entry.id, section, nth))
            return kept.length;
        if (!removes) kept.push(entry);
    }
    return kept.length;
}

// The geometry rule for a bar widget drop. X is in bar-window
// coordinates. SECTIONS maps each section to `{ x, width, widgets }`, and
// each widget is `{ x, width, locator }`, with the dragged widget already
// excluded.
function barDropTarget(width, x, sections) {
    var section = x < width / 3 ? "left" : x < 2 * width / 3 ? "center" : "right";
    var info = isPlainObject(sections) && isPlainObject(sections[section]) ? sections[section] : { x: 0, width: width, widgets: [] };
    var widgets = Array.isArray(info.widgets) ? info.widgets : [];
    var slot = 0;
    while (slot < widgets.length && widgets[slot].x + widgets[slot].width / 2 < x) slot += 1;
    var before = slot < widgets.length ? clone(widgets[slot].locator) : null;
    var markerX;
    if (before !== null) markerX = widgets[slot].x;
    else if (widgets.length > 0) markerX = widgets[widgets.length - 1].x + widgets[widgets.length - 1].width;
    else markerX = (typeof info.x === "number" ? info.x : 0) + (typeof info.width === "number" ? info.width : width) / 2;
    return { section: section, before: before, markerX: markerX };
}

// Whether plugin MANIFEST's widget shows in the bar once the plugin is
// installed or first discovered: it declares kind bar-widget.
// firstPresence and `vgshell plugin add` ask it.
function landsShown(manifest) {
    return manifest.kinds.indexOf("bar-widget") !== -1;
}

// The ids of the plugins in MANIFESTS whose widget takes its first presence
// under EFFECTIVE, sorted: each lands shown (landsShown), is not in
// disabledPlugins, is placed in no section and has no plugins[] row. A plugin the user disabled or hid (withPlaced leaves its row) keeps
// its state. So every widget a plugin brings shows in the bar when the
// plugin is installed or first discovered, with no step in Settings.
function firstPresence(manifests, effective) {
    var disabled = Array.isArray(effective.disabledPlugins) ? effective.disabledPlugins : [];
    return Object.keys(manifests).sort().filter(function (id) {
        var m = manifests[id];
        if (!landsShown(m) || disabled.indexOf(id) !== -1)
            return false;
        return !isPlaced(effective, m) && pluginRow(effective, id) === undefined;
    });
}

// The user-file change that places every widget firstPresence names, each
// at the end of its default section (placeWidget). Returns the new user
// object; the caller writes it when firstPresence names any.
function withFirstPresence(user, manifests, effective) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = CONFIG_VERSION;
    firstPresence(manifests, effective).forEach(function (id) { placeWidget(out, manifests[id], effective); });
    return out;
}

// Why `value` may not be written to setting `key` of this plugin, or "".
// Only a key the manifest's schema declares is writable, and only with a
// value of its type. The reply is one keyed line.
function settingRefusal(manifest, key, value) {
    if (manifest.hyprland !== undefined && manifest.hyprland.monitors === key) {
        var badMonitors = MonitorLogic.rulesError(value, null);
        return badMonitors === "" ? "" : badMonitors.replace("refused: monitors", "refused: setting=" + key);
    }
    if (!hasOwn(manifest.schema, key))
        return "refused: setting=" + key + " undeclared";
    var bad = settingError(manifest.schema[key], value);
    return bad === "" ? "" : "refused: setting=" + key + " " + bad;
}

// Why shortcut `shortcut` of this plugin may not take `key`, or "". Only a
// shortcut the manifest's `hyprland.binds` declares has a key. A key string
// or non-empty list of strings hyprlandKey accepts rebinds it, null unbinds
// it, and undefined removes the plugins row's entry so the manifest's key
// applies. The reply is one keyed line.
function keyRefusal(manifest, shortcut, key) {
    var binds = manifest.hyprland === undefined ? [] : manifest.hyprland.binds;
    var bind = binds.filter(function (row) { return row.shortcut === shortcut; })[0];
    if (bind === undefined && !Pads.isPadShortcut(manifest.hyprland, shortcut, NAME_PATTERN))
        return "refused: key=" + shortcut + " undeclared";
    if (key === undefined || key === null)
        return "";
    if (typeof key !== "string" && !Array.isArray(key))
        return "refused: key=" + shortcut + " want=string-list-or-null";
    var bad = keyValueError(key, "refused: key=" + shortcut, bind !== undefined && bind.tap === true);
    return bad;
}

// The user-file change that sets one shortcut's key in the plugin's plugins
// row `keys`: one normalised key as a string, several normalised keys as a
// list, null to unbind, or, for undefined, no entry, so the manifest's key
// applies; a `keys` left empty is removed. The row is seeded from the
// effective one, since a user row replaces the shipped row whole; a reset
// the effective row does not need changes nothing. The caller checks the
// key with keyRefusal first.
function withKey(user, manifest, shortcut, key, effective) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = CONFIG_VERSION;
    var row = pluginRow(out, manifest.id);
    if (row === undefined) {
        var shippedRow = pluginRow(effective, manifest.id);
        var needed = key !== undefined || (shippedRow !== undefined && isPlainObject(shippedRow.keys) && hasOwn(shippedRow.keys, shortcut));
        if (!needed)
            return out;
        row = shippedRow !== undefined ? clone(shippedRow) : { id: manifest.id };
        out.plugins = (Array.isArray(out.plugins) ? out.plugins : []).concat([row]);
    }
    if (key === undefined) {
        if (isPlainObject(row.keys)) {
            delete row.keys[shortcut];
            if (Object.keys(row.keys).length === 0) delete row.keys;
        }
        return out;
    }
    if (!isPlainObject(row.keys)) row.keys = {};
    row.keys[shortcut] = keyRowValue(key);
    return out;
}

// The Keys rows the plugin manager shows for a plugin: one per shortcut its
// manifest and pads declare, in order, as { shortcut, key, keys, default,
// description, info }: the keys hyprlandSection puts in effect, the first
// key or null when unbound, the manifest's key or list of keys by shortcut,
// null for a pad, the description the plugin registered for
// `<id>:<shortcut>` in `descriptions`, "" while none is registered, and the
// manifest's explanation of the shortcut, "" for a pad or a bind that
// declares none.
function bindRows(config, manifest, descriptions) {
    var defaults = manifest.hyprland === undefined ? [] : manifest.hyprland.binds;
    var defaultsByShortcut = Object.create(null);
    var infoByShortcut = Object.create(null);
    defaults.forEach(function (bind) {
        defaultsByShortcut[bind.shortcut] = bind.key;
        if (bind.info !== undefined) infoByShortcut[bind.shortcut] = bind.info;
    });
    var rows = [];
    var byShortcut = Object.create(null);
    hyprlandSection(config, manifest).binds.forEach(function (bind) {
        var row = byShortcut[bind.shortcut];
        if (row === undefined) {
            var name = manifest.id + ":" + bind.shortcut;
            row = { shortcut: bind.shortcut, keys: [], "default": hasOwn(defaultsByShortcut, bind.shortcut) ? defaultsByShortcut[bind.shortcut] : null, description: hasOwn(descriptions, name) ? descriptions[name] : "", info: hasOwn(infoByShortcut, bind.shortcut) ? infoByShortcut[bind.shortcut] : "" };
            byShortcut[bind.shortcut] = row;
            rows.push(row);
        }
        if (bind.key !== null) row.keys.push(bind.key);
    });
    return rows.map(function (row) {
        return { shortcut: row.shortcut, key: row.keys.length === 0 ? null : row.keys[0], keys: row.keys, "default": row["default"], description: row.description, info: row.info };
    });
}

// The icon a plugin is listed with: its manifest's, else DEFAULT_ICON.
function pluginIcon(manifest) {
    return typeof manifest.icon === "string" ? manifest.icon : DEFAULT_ICON;
}

// The configuration entries a plugin's instances read their settings from,
// one per settingTargetOf(kind) over its kinds, "layout" only while a
// widget is placed in the bar. The plugin manager, and a pane or a service
// through configure, write every entry the plugin reads; any other running
// instance writes only the entry it reads.
function settingTargets(config, manifest) {
    var wanted = manifest.kinds.map(settingTargetOf);
    return SETTING_TARGETS.filter(function (target) {
        if (wanted.indexOf(target) === -1) return false;
        return target !== "layout" || isPlaced(config, manifest);
    });
}

// The configuration entries an instance of KIND writes through the
// configure capability. A pane or a service writes every entry its plugin
// reads, the same contract as the manager, so a setting it flips reads the
// same on the Settings page while the plugin's widget is placed; other
// kinds write the one entry they read.
function configureTargets(config, manifest, kind) {
    return kind === "pane" || kind === "service" ? settingTargets(config, manifest) : [settingTargetOf(kind)];
}

// Pane rows for the exclusive panes holder: every enabled plugin of kind
// `pane`, grouped and ordered by its manifest's `pane` key, with placement
// from the same rule the manager reads. The row is data for the holder; it
// does not build a pane.
function paneRows(config, manifests, defaultBarId) {
    return Object.keys(manifests).filter(function (id) {
        return manifests[id].kinds.indexOf("pane") !== -1 && isEnabled(config, manifests[id], defaultBarId);
    }).map(function (id) {
        var manifest = manifests[id];
        return {
            id: id,
            name: manifest.name,
            icon: pluginIcon(manifest),
            group: manifest.pane.group,
            order: manifest.pane.order,
            placed: isPlaced(config, manifest),
            hasWidget: manifest.kinds.indexOf("bar-widget") !== -1
        };
    }).sort(function (a, b) {
        if (a.group !== b.group) return a.group < b.group ? -1 : 1;
        if (a.order !== b.order) return a.order - b.order;
        if (a.name !== b.name) return a.name < b.name ? -1 : 1;
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });
}

// The enabled window plugin that holds the panes capability, or "". The
// capability is exclusive at build time; this picks the deterministic
// candidate own-pane summon targets before any holder is built.
function panesHolderId(config, manifests, defaultBarId) {
    var ids = Object.keys(manifests).filter(function (id) {
        var manifest = manifests[id];
        return manifest.capabilities.indexOf("panes") !== -1 && isEnabled(config, manifest, defaultBarId);
    }).sort();
    return ids.length === 0 ? "" : ids[0];
}

// The user-file change that sets one setting of one plugin in each of
// `targets`. "layout" sets the key on every layout entry with the plugin's
// id, or with `locator` { section, nth } on the nth such entry of that
// section alone, seeding the user `bar` key first (seedUserBar); "plugins"
// sets it on the plugin's plugins[] row, seeding that row from the
// effective one, since a user row replaces the shipped row whole. The
// caller checks the value with settingRefusal first.
function withSetting(user, manifest, key, value, effective, targets, locator) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = CONFIG_VERSION;
    if (targets.indexOf("layout") !== -1) {
        seedUserBar(out, effective);
        var layout = isPlainObject(out.bar.layout) ? out.bar.layout : {};
        SECTIONS.forEach(function (section) {
            if (isPlainObject(locator) && locator.section !== section) return;
            var seen = 0;
            (Array.isArray(layout[section]) ? layout[section] : []).forEach(function (entry, index) {
                if (entry.id !== manifest.id) return;
                if (!isPlainObject(locator) || seen === locator.nth) {
                    entry = copyEntrySettings({}, entry, manifest, true);
                    entry[key] = clone(value);
                    layout[section][index] = entry;
                }
                seen += 1;
            });
        });
    }
    if (targets.indexOf("plugins") !== -1) {
        var plugins = Array.isArray(out.plugins) ? out.plugins : [];
        var row = pluginRow(out, manifest.id);
        if (row === undefined) {
            var shippedRow = pluginRow(effective, manifest.id);
            row = shippedRow !== undefined ? shippedRow : { id: manifest.id };
            plugins.push(row);
        }
        var index = plugins.indexOf(row);
        row = copyEntrySettings({}, row, manifest, true);
        row[key] = clone(value);
        plugins[index] = row;
        out.plugins = plugins;
    }
    return out;
}

// The user-file change that removes one setting of one plugin from each of
// `targets`, so the plugin reads its manifest's default again and the
// Hyprland layer stops writing the option the setting maps to. "layout"
// removes the key from the user file's layout entries with the plugin's id,
// or with `locator` from that one entry; "plugins" removes it from the
// user file's plugins[] row. An entry the user file does not hold is not
// seeded.
function withoutSetting(user, manifest, key, targets, locator) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = CONFIG_VERSION;
    if (targets.indexOf("layout") !== -1 && isPlainObject(out.bar) && isPlainObject(out.bar.layout)) {
        SECTIONS.forEach(function (section) {
            if (isPlainObject(locator) && locator.section !== section) return;
            var seen = 0;
            (Array.isArray(out.bar.layout[section]) ? out.bar.layout[section] : []).forEach(function (entry, index) {
                if (entry.id !== manifest.id) return;
                if (!isPlainObject(locator) || seen === locator.nth) {
                    entry = copyEntrySettings({}, entry, manifest, true);
                    delete entry[key];
                    out.bar.layout[section][index] = entry;
                }
                seen += 1;
            });
        });
    }
    var row = targets.indexOf("plugins") !== -1 ? pluginRow(out, manifest.id) : undefined;
    if (row !== undefined) {
        var index = out.plugins.indexOf(row);
        row = copyEntrySettings({}, row, manifest, true);
        delete row[key];
        out.plugins[index] = row;
    }
    return out;
}

// Why this plugin may not be built while `held` maps each exclusive
// capability to the plugin holding it, or "". A plugin may hold what it
// already holds, so its second instance builds.
function lendRefusal(held, manifest) {
    for (var i = 0; i < manifest.capabilities.length; i++) {
        var name = manifest.capabilities[i];
        if (EXCLUSIVE_CAPABILITIES.indexOf(name) === -1) continue;
        if (hasOwn(held, name) && held[name] !== manifest.id)
            return "refused: capability=" + name + " held-by=" + held[name];
    }
    return "";
}

// Judge the argument of shell.notify.send: an object with a non-blank
// string `title`, an optional string `message`, `tone` from NOTIFY_TONES,
// `icon` a Lucide name, `urgency` from NOTIFY_URGENCIES and a boolean
// `transient`, a notification left out of History. Answers { ok: true,
// value } with every key present, or { ok: false, error } whose first word
// is the offending key.
function notifyOptions(raw) {
    if (!isPlainObject(raw))
        return { ok: false, error: "options want=object" };
    var keys = Object.keys(raw);
    for (var i = 0; i < keys.length; i++)
        if (NOTIFY_KEYS.indexOf(keys[i]) === -1)
            return { ok: false, error: keys[i] + " unknown" };
    if (typeof raw.title !== "string" || raw.title.trim() === "" || raw.title.length > NOTIFY_TITLE_MAX)
        return { ok: false, error: "title want=string of 1 to " + NOTIFY_TITLE_MAX + " characters" };
    if (raw.message !== undefined && (typeof raw.message !== "string" || raw.message.length > NOTIFY_MESSAGE_MAX))
        return { ok: false, error: "message want=string of at most " + NOTIFY_MESSAGE_MAX + " characters" };
    if (raw.tone !== undefined && NOTIFY_TONES.indexOf(raw.tone) === -1)
        return { ok: false, error: "tone want=" + NOTIFY_TONES.join("|") };
    if (raw.icon !== undefined && !(typeof raw.icon === "string" && raw.icon.length <= NOTIFY_ICON_MAX && NOTIFY_ICON.test(raw.icon)))
        return { ok: false, error: "icon want=Lucide name of at most " + NOTIFY_ICON_MAX + " characters" };
    if (raw.urgency !== undefined && NOTIFY_URGENCIES.indexOf(raw.urgency) === -1)
        return { ok: false, error: "urgency want=" + NOTIFY_URGENCIES.join("|") };
    if (raw.transient !== undefined && typeof raw.transient !== "boolean")
        return { ok: false, error: "transient want=boolean" };
    return { ok: true, value: { title: raw.title, message: raw.message === undefined ? "" : raw.message, tone: raw.tone === undefined ? "" : raw.tone, icon: raw.icon === undefined ? "" : raw.icon, urgency: raw.urgency === undefined ? "normal" : raw.urgency, transient: raw.transient === true } };
}

// The notify-send argv for JUDGED, notifyOptions' value, sent as APP_NAME
// by plugin PLUGIN_ID. A plugin's message opens no window and offers no
// action, so a click only dismisses it. The x-vgs-plugin hint names the
// sender, so a critical plugin message shows under Silence. The
// notification server reads a body as markup, so the message's `&`, `<`
// and `>` are escaped and plain text shows as typed.
function notifyArgv(pluginId, appName, judged) {
    var argv = ["notify-send", "--app-name=" + appName, "--urgency=" + judged.urgency, "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:" + pluginId];
    if (judged.tone !== "") argv.push("--hint=string:x-vgs-tone:" + judged.tone);
    if (judged.icon !== "") argv.push("--hint=string:x-vgs-icon:" + judged.icon);
    if (judged.transient) argv.push("--transient");
    var message = judged.message.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    return argv.concat(["--", judged.title, message]);
}

// The surface a summon of KIND builds: `window`, a Hyprland toplevel, for
// kind `window` whatever the anchor, since a toplevel is never placed by
// the shell; `popup` under an ANCHORED summon's item; `layer` otherwise.
function summonSurface(kind, anchored) {
    if (SUMMONABLE_KINDS.indexOf(kind) === -1)
        throw new Error("summonSurface: kind " + JSON.stringify(kind) + " is not summonable");
    if (kind === "window") return "window";
    return anchored ? "popup" : "layer";
}

// Whether an unanchored summon of KIND is a full-screen overlay whose
// layer must own the keyboard until it closes. Anchored popups already
// take their own grab, and application windows are Hyprland toplevels.
function capturesOverlayKeyboard(kind, anchored) {
    if (SUMMONABLE_KINDS.indexOf(kind) === -1)
        throw new Error("capturesOverlayKeyboard: kind " + JSON.stringify(kind) + " is not summonable");
    return kind === "overlay" && !anchored;
}

// The WlrKeyboardFocus variant a layer summon uses, as a string the host
// maps to the Quickshell enum.
function layerKeyboardFocus(kind, anchored) {
    return capturesOverlayKeyboard(kind, anchored) ? "exclusive" : "on-demand";
}

// Whether a layer summon of KIND catches a press beside it and closes, as
// an anchored popup's grab does: it covers its screen and places the plugin
// inside. An overlay already covers its screen with the plugin and catches
// nothing. A kind built as no layer is refused.
function layerCatchesOutside(kind) {
    if (summonSurface(kind, false) !== "layer")
        throw new Error("layerCatchesOutside: kind " + JSON.stringify(kind) + " is never a layer summon");
    return !capturesOverlayKeyboard(kind, false);
}

// Layer placement for a summon without an item anchor. Popups delegate
// anchored placement to the compositor. Unknown user placement falls back
// to center and returns an error for the host to report. A centred panel or
// menu ignores reserved space, so it sits on the middle of the whole
// monitor; every other placement keeps clear of it.
function surfacePlacement(kind, settings, gap) {
    var zero = { top: 0, bottom: 0, left: 0, right: 0 };
    var layer = kind === "panel" ? "top" : "overlay";
    if (kind === "overlay")
        return { anchors: { top: true, bottom: true, left: true, right: true }, margins: zero, exclusion: "ignore", layer: layer, placement: "fill", error: "" };
    var asked = isPlainObject(settings) ? settings.placement : undefined;
    var known = asked === undefined || PLACEMENTS.indexOf(asked) !== -1;
    var placement = asked !== undefined && known ? asked : "center";
    var anchors = { top: false, bottom: false, left: false, right: false };
    var margins = { top: 0, bottom: 0, left: 0, right: 0 };
    var parts = placement.split("-");
    parts.forEach(function (edge) {
        if (edge === "center") return;
        anchors[edge] = true;
        margins[edge] = gap;
    });
    return { anchors: anchors, margins: margins, exclusion: placement === "center" ? "ignore" : "normal", layer: layer, placement: placement, error: known ? "" : "placement=" + JSON.stringify(asked) + " unknown" };
}

// The longest idle watch the `idle` capability takes, one day in seconds.
var IDLE_WATCH_MAX_SECONDS = 86400;

// "" when an idle watch of SECONDS calling ONCHANGE is valid, else its
// keyed refusal: a whole number of seconds from 1 to IDLE_WATCH_MAX_SECONDS
// and a function.
function idleWatchRefusal(seconds, onChange) {
    if (typeof seconds !== "number" || !Number.isInteger(seconds) || seconds < 1 || seconds > IDLE_WATCH_MAX_SECONDS)
        return "refused: idle-timeout=" + JSON.stringify(seconds) + " want=1.." + IDLE_WATCH_MAX_SECONDS;
    if (typeof onChange !== "function") return "refused: idle-handler=not-a-function";
    return "";
}
