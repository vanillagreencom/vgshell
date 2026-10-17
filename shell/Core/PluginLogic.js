.pragma library
.import "ConfigLogic.js" as ConfigLogic
.import "../Commons/SettingValues.js" as SettingValues
.import "../Ui/icons/Lucide.js" as Lucide
.import "PackageManagers.js" as PackageManagers
.import "HyprlandLayer.js" as HyprlandLayer
.import "Pads.js" as Pads
.import "MonitorLogic.js" as MonitorLogic
.import "../Commons/PageReference.js" as PageReference

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
var CAPABILITIES = ["compositor", "configure", "idle", "ipc", "lock", "session", "notifications", "polkit", "run", "screens", "screencopy", "shortcut", "surfaces", "builtins", "manager", "panes", "notify", "theme", "layers", "status", "tui", "system", "requirements", "doctor", "secrets", "hyprland", "bluetoothAgent", "monitors", "sudo", "appearance", "sounds", "soundSettings", "dictation"];

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
// carry. `presets`, `separator`, `allowCustom`, `format` and `unit` choose the Settings
// editor, `allowCustom` a Custom… row after a presets or `optionsFrom`
// select's choices; `separator` joins independently checked string presets,
// with custom values preserved; `min`, `max` and `step` bound a number's control;
// `group` names the section heading the entry is drawn under;
// `placeholder` is what an `optionsFrom` select reads while its value is
// "", which then means nothing is chosen; `hideEmpty` leaves an
// `optionsFrom` field off the page while nothing is offered for it;
// `shownWhen` names a `presence` status entry of the same plugin and
// places the field only while that entry reads present; `link`
// makes part of the description open an https address or another plugin's
// page; `tooltip` is the few words a label that is not plain needs, shown
// on hover and keyboard focus of the label. Pads.js judges a
// `list`.
var SETTING_TYPES = ["string", "number", "boolean", "enum", "list"];
var SCHEMA_ENTRY_KEYS = ["type", "label", "description", "info", "tooltip", "link", "options", "optionsFrom", "presets", "separator", "allowCustom", "format", "unit", "min", "max", "step", "group", "shownWhen", "items", "defaults", "placeholder", "hideEmpty"];
var NUMBER_BOUND_KEYS = ["min", "max", "step"];
var PRESET_KEYS = ["value", "label"];
var OPTION_KEYS = ["value", "label"];
var PRESET_LABEL_MAX = 40;
// A schema entry's `link`: the words of its description that open `url`,
// or `pane`, the id of the plugin whose page the panes holder opens.
// The address is https with a host of letters, digits, dots and hyphens,
// an optional port, and a path, query or fragment of printable ASCII, so
// the desktop open route hands the browser nothing else: no other scheme,
// no user part, no space and no control character.
var LINK_KEYS = ["text", "url"];
var LINK_TEXT_MAX = 60;
var LINK_URL_MAX = 2048;
var LINK_URL_PATTERN = /^https:\/\/[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*(:[0-9]{1,5})?([/?#][!-~]*)?$/;

// The icon a plugin without a manifest `icon` is listed with.
var DEFAULT_ICON = "package";

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

// A manifest's `sounds` key: the events the plugin has a sound for, each a
// ConfigLogic.NAME_PATTERN name over SOUND_EVENT_KEYS. `label` names the event on the
// Sounds page and `description` says when it sounds. `default` is what the
// event plays until the user chooses: an id of SOUNDS, or SOUND_OFF for
// none. An event with `own` is one the plugin sounds itself, through an
// audio path the core's player cannot serve; `own` names that sound in the
// page's picker, and such an event's value is SOUND_OWN or SOUND_OFF. An
// own event with `held` is one whose value another program's file holds:
// shell.json stores no choice for it and it takes no `default`; the plugin
// states the value it read there and applies the page's choice (capability
// `sounds`, `hold` and `report`), so the page shows what will sound.
var SOUND_EVENT_KEYS = ["label", "description", "default", "own", "held"];
var SOUND_OFF = "";
var SOUND_OWN = "own";
var SOUND_OFF_LABEL = "Off";
// The sounds the core ships, each shell/assets/sounds/<file>, in the order
// the Sounds page offers them. A manifest's default and the user's choice
// name one by `id`.
var SOUNDS = [
    { id: "chime", label: "Chime", file: "chime.wav" },
    { id: "ping", label: "Ping", file: "ping.wav" },
    { id: "pop", label: "Pop", file: "pop.wav" }
];

// Every key a manifest may carry. An unknown key is refused, so a misspelt
// key fails loudly instead of being carried and ignored.
var MANIFEST_KEYS = ["schemaVersion", "id", "formerIds", "name", "version", "author", "description", "license", "icon", "kinds", "entryPoints", "capabilities", "capabilityKinds", "systemSteps", "settings", "schema", "defaultSection", "pane", "appearance", "hyprland", "requirements", "status", "tui", "menu", "secrets", "sounds", "alwaysOn"];

// What one entry of a manifest's `requirements`, and of the core's own
// config/requirements.json, may carry: an external command the plugin runs
// or a D-Bus name it reaches, the package that provides it per manager id of
// PackageManagers.js, whether the plugin works without it, and one line
// saying what it is for, for a command the `floor`, the lowest version
// the plugin works with, and `install`, how the package recipes carry its
// package. The states a probed requirement is reported in.
var REQUIREMENT_KEYS = ["command", "dbus", "packages", "optional", "purpose", "floor", "install"];
// The one `install` value: the requirement stays required, and its package
// is an optional dependency of every recipe, which its plugin's
// Requirements section installs (scripts/check-packaging.js).
var REQUIREMENT_ON_REQUEST = "on-request";
// A D-Bus requirement's `label` is the short name a page lists it by,
// since its name is a bus path and its `purpose` a sentence.
var REQUIREMENT_DBUS_KEYS = ["bus", "name", "label"];
var REQUIREMENT_LABEL_MAX = 40;
var REQUIREMENT_BUSES = ["system", "session"];
var REQUIREMENT_PURPOSE_MAX = 120;
var REQUIREMENT_STATES = ["present", "missing", "outdated"];
// A `floor`: three dotted numbers, none with a leading zero.
var REQUIREMENT_FLOOR = /^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$/;
// The version in the line a command's `--version` printed: its first three
// dotted numbers, whatever names the program before them (`tool 1.2.3`) or
// marks a pre-release after them (`1.2.3-rc1`).
var VERSION_IN_LINE = /(?:^|[^0-9.])([0-9]{1,6})\.([0-9]{1,6})\.([0-9]{1,6})(?![0-9])/;
// A purpose is one printable line: no C0 or C1 control character.
var CONTROL_CHARACTER = /[\u0000-\u001f\u007f-\u009f]/;
var DBUS_NAME_PART = /^[A-Za-z_-][A-Za-z0-9_-]*$/;


// Plugin status: the runtime values a plugin publishes through its `status`
// capability, each declared in the manifest's `status` key with one of these
// types. `data` is structured JSON only the plugin's own instances read; the
// Settings window draws every other type unless the entry is `hidden`;
// `choices` feeds a setting's Select instead of a Status row; `rows` is a
// list a page draws full width under its label, each row with its own
// actions.
var STATUS_TYPES = ["presence", "presenceList", "state", "text", "count", "time", "data", "choices", "launcherRows", "rows"];
var STATUS_ENTRY_KEYS = ["type", "label", "group", "hint", "info", "link", "hidden", "action", "actions", "aside", "setup", "setting", "step", "settings", "icon", "rowActions"];
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
// A label's tooltip is one short sentence: longer help goes in `info`.
var TOOLTIP_MAX = 120;
// A setting's label draws in the label column in the `label` role and wraps
// there, never elided (FormRow). At the default theme a line of that column
// holds LABEL_LINE_CHARACTERS characters, and INFO_LABEL_LINE_CHARACTERS
// beside an info mark, which takes an `sm` icon button and `space.xs` of
// it; a label holds at most LABEL_LINES lines. tst_settingfield.qml holds
// both counts and labelLines to the drawn label.
var LABEL_LINE_CHARACTERS = 17;
var INFO_LABEL_LINE_CHARACTERS = 13;
var LABEL_LINES = 2;
// The ceiling on one plugin's published values: the UTF-8 bytes of their
// JSON. A write that would pass it is refused and the values stay.
var STATUS_MAX_BYTES = 65536;
// A `presence` value, and the badge tone Settings draws it with: the thing is
// stored and readable; not stored; stored but locked, so a background probe
// cannot read it without prompting; its store cannot be asked; stored where
// another user can read it; an account that is there but signed out.
var STATUS_PRESENCE_TONES = { present: "success", absent: "warning", locked: "info", unavailable: "neutral", unsafe: "danger", "signed-out": "warning" };
// A `state` value's `tone`, and the badge tone Settings draws it with.
var STATUS_STATE_TONES = { ok: "success", info: "info", warning: "warning", danger: "danger" };
// The keys a `state` value carries. `action` is its writer's to decide
// (D061): true when the entry's declared `action` applies to this value,
// the name of the one of the entry's declared `actions` that does, or, on
// a required step of a plugin with a required tool, STATUS_TOOLS_ACTION
// while a missing or outdated required tool blocks the step, whose page
// then offers Review all missing or outdated tools on the step's row.
// `available: false` says a required step that is not done offers the
// user no action and does not wait on the user, so its page reads it Not
// available and raises no Setup needed; its `hint`, which it must carry,
// says why and what will change that.
// `lines` is the further printable lines a state that names several things
// draws under `text`, at most STATUS_LIST_MAX. `hint` is bounded plain
// guidance for this state; without it, the declaration's hint applies.
// A value of `hidden: true` alone (statusStateHidden) keeps the entry's
// row off the page while its writer finds nothing to show. `aside` is its
// writer's too: true when the entry's declared `aside` applies to this
// value. `info` is this state's own explanation, judged as an entry's
// (infoError), such as why a limit holds for the cause its writer found;
// while present it stands in the entry's info (statusRows). `file` is the
// path a file action declared `file: true` opens, a path editArgs admits,
// carried exactly while the value offers such an action
// (statusDeclarationFits): the writer, not the manifest, knows a path the
// user chose, such as a file in a folder picked in Settings. A folder's
// path ends in `/`, as editRoute reads it; any other path opens in the
// editor, which refuses a folder.
var STATUS_STATE_KEYS = ["tone", "text", "lines", "hint", "action", "aside", "available", "info", "file"];
// The `action` a required step's value names for the one install action,
// which no entry declares: it names that action over a declared action of
// the same name.
var STATUS_TOOLS_ACTION = "tools";
// A `presenceList` value is a list of at most STATUS_LIST_MAX items, each
// carrying these keys: a printable `label` and a `presence` value, with an
// optional printable `hint`, an optional `info`, the item's own explanation,
// judged as an entry's (infoError), and an optional `secret`, the account of
// the plugin's declared `secrets` the item is the presence of.
var STATUS_LIST_MAX = 64;
var STATUS_LIST_ITEM_KEYS = ["label", "value", "hint", "info", "secret"];
// Choice values are stable ids, not their display labels. Empty string is
// reserved for a setting that follows the first offered value.
var STATUS_CHOICE_KEYS = ["label", "value"];
// A `rows` value is a list of at most STATUS_LIST_MAX rows, each carrying
// these keys: an `id`, unique in the list, which a row action hands its
// TUI as its one argument, so it is one argument tuiArgsValid admits; a
// printable `label` of at most STATUS_LABEL_MAX characters; an optional
// printable `secondary` line of at most STATUS_TEXT_MAX; an optional
// `state`, STATUS_ROW_STATE_KEYS, a tone of STATUS_STATE_TONES and a
// printable `text` of at most STATUS_LABEL_MAX; and optional `actions`,
// the names of the entry's `rowActions` this row offers, each once.
var STATUS_ROW_KEYS = ["id", "label", "secondary", "state", "actions"];
var STATUS_ROW_STATE_KEYS = ["tone", "text"];
// The tones of a row's state that need the user: a page draws such a state
// as a chip, and every other tone as plain text.
var STATUS_ROW_CHIP_TONES = ["warning", "danger"];
// A plugin-published launcher provider can expose a category of dynamic
// rows. The ceiling admits a 150-row catalog with growth room and keeps
// search work bounded.
var LAUNCHER_ROWS_MAX = 256;
var LAUNCHER_ROW_KEYS = ["id", "label", "icon", "description", "aliases", "menu"];

// A status entry's `action` (D061): the one-click setup step the Settings
// page draws as a button beside the entry. It carries a printable `label`
// and exactly one route, STATUS_ACTION_ROUTES: `tui`, a name of the
// manifest's own `tui` key the core opens in a floating terminal;
// `system`, a step of the manifest's own `systemSteps` the core applies in
// its `core/system` TUI (D081); `undo`, such a step the core undoes there;
// `dictation`, `setup` for a holder of that capability; or `file`, a
// path the core opens as a cited file is opened (editRoute): a file in the
// core editor TUI, whose run is the plugin's own, read in its
// `shell.tui.state` under STATUS_FILE_TUI, and a folder, ending in `/`, in
// the default file manager, which no run tracks. A `state` entry's file
// action may declare `file: true` instead of a path: the value that offers
// it supplies the path in its own `file`. No route
// installs a requirement: Review all missing or outdated tools, which opens
// the requirement notice, is the one install action, offered by Setup's
// Tools step, by Details' Tools section and by a required step whose value
// names STATUS_TOOLS_ACTION. An entry of a
// type in STATUS_ACTION_TYPES takes one. A `state`
// entry whose step differs by what its writer found declares `actions`
// instead: two or more such steps by name, a STATUS_KEY_PATTERN
// identifier, of which a value names at most one. An action that removes
// what the user set up, such as a sign-out, carries `tone`, one of
// STATUS_ACTION_TONES, and a page draws it in the danger style, led by the
// trash mark, or by the mark its `icon` names, a name of the shipped Lucide
// set, for one that removes no item, such as a sign-out's `log-out`. A `state`
// entry with a step may declare `aside`, one more action its row draws
// beside the step, such as Remove key beside Add key: an action of route
// `tui` whose script has an `entry`, since the page opens it as a listed
// screen, offered while its value carries `aside: true`. A `rows` entry's
// `action` acts on the whole list, such as Add, offered while the list is
// reported, and its `rowActions` act on one row each: each of route `tui`,
// whose script the core opens with the row's `id` as its one argument,
// offered on a row whose `actions` name it.
var STATUS_ACTION_ROUTES = ["tui", "system", "undo", "dictation", "file"];
// The name a plugin's file action runs the core editor under, `<plugin
// id>/edit`, and the name its end reads under in the plugin's
// `shell.tui.state` (tuiStateNames). A manifest that declares a file
// action declares no script of that name, so the two never share a state.
var STATUS_FILE_TUI = "edit";
var STATUS_ACTION_KEYS = ["label", "tone", "icon"].concat(STATUS_ACTION_ROUTES);
var STATUS_ACTION_TONES = ["danger"];
var STATUS_ACTION_TYPES = ["presence", "state", "rows"];
// The refusal reasons of the `manager` capability's `act`: `row-changed`
// for a row action whose row no longer offers it.
var STATUS_ACTION_REASONS = ["undeclared", "disabled", "not-offered", "row-changed"];

// The system steps (D081): the closed table bin/vgshell-system holds, which a
// manifest's `systemSteps` names from, in the order `vgshell-system status`
// prints them, and the states a probe reads each one in. The script is the
// table's owner; scripts/test-vgshell-system.sh reads its status back against
// this list.
var SYSTEM_STEPS = ["apple-displays", "i2c-dev", "service-bluetooth", "service-tailscaled", "service-cups", "tailscale-operator", "greeter", "bandwhich-capture", "reboot-notice", "voxtype-engine"];
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
// its presence: `connect`, Add key, while nothing is stored; `disconnect`,
// Replace and Remove, while something is; and nothing
// while the store cannot be asked. A signed-out account takes a new
// credential, so it offers Add key. SECRET_VERBS names the accesses that
// offer each write: a store also replaces a stored key, since a store whose
// attributes match an item updates that item (libsecret
// secret_password_store).
var SECRET_ACCESS = { absent: "connect", present: "disconnect", locked: "disconnect", unsafe: "disconnect", unavailable: "", "signed-out": "connect" };
var SECRET_VERBS = { store: ["connect", "disconnect"], clear: ["disconnect"] };
var SECRET_REASONS = ["undeclared", "disabled", "unlisted", "not-offered", "value", "busy"];

// What a manifest's `hyprland` key may hold: binds of the plugin's own
// shortcuts, blur rules for the core's layer namespaces, the theme
// appearance switches, the input options its settings set and one monitor
// rule setting. Data only;
// the core renders it (HyprlandLayer.js), so no plugin text reaches the
// compositor's Lua.
var HYPRLAND_KEYS = ["binds", "layerRules", "appearance", "options", "pads", "monitors"];
var HYPRLAND_BIND_KEYS = ["shortcut", "key", "hold", "tap", "info"];
var HYPRLAND_RULE_KEYS = ["namespace", "blur", "ignoreAlpha"];
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

// A value a Settings or Keys control hands the manager, with each array or
// object made plain: on Qt 6.12 a JavaScript array sent through a `var`
// signal argument arrives as a list wrapper Array.isArray refuses, and an
// object as a reference wrapper. A string, number, boolean, null or
// undefined passes as it came, so the judge still sees a non-finite number.
function controlValue(value) {
    return value !== null && typeof value === "object" ? clone(value) : value;
}

function presetValues(entry) {
    return Array.isArray(entry.presets) ? entry.presets.map(function (preset) { return preset.value; }) : [];
}

// The values an enum entry stores, in its options' order.
function optionValues(entry) {
    return entry.options.map(function (option) { return option.value; });
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
    if (entry.type === "enum") return optionValues(entry).indexOf(value) !== -1 ? "" : "want=one-of:" + optionValues(entry).join("|");
    if (entry.type === "list") return Pads.listValueError(entry, value, settingError, ConfigLogic.NAME_PATTERN);
    throw new Error("settingError: schema entry type " + JSON.stringify(entry.type) + " passed validation but has no rule");
}

// The first defect of a settings schema, or "". Every entry names a type
// from SETTING_TYPES and a label; an enum entry lists its options, each the
// stored `value` and the `label` the Settings page draws for it; a number
// entry may bound its control with finite `min` below finite `max` and a
// positive `step`, which no other type carries; `unit` names a number's
// words; `group`, when present, is a non-empty string; every entry has a
// default of its type, inside its bounds, in `settings`, so a form always
// has a value to show. A string declares `presets` or `optionsFrom`.
// optionsFrom connects a string to a declared choices status, never to
// another plugin. Presets declare the picker values; `allowCustom`, beside
// presets or optionsFrom, lets another fitting value write.
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
        if (entry.description !== undefined && !hintFits(entry.description))
            return at + ".description" + HINT_RULE;
        var schemaInfo = infoError(entry.info, at);
        if (schemaInfo !== "")
            return schemaInfo;
        // A list's label is its section's title, which draws no tooltip and
        // has the page's width.
        if (entry.tooltip !== undefined) {
            if (entry.type === "list")
                return at + ".tooltip needs a flat setting";
            if (!isPrintableLine(entry.tooltip, TOOLTIP_MAX))
                return at + ".tooltip must be a printable line of 1 to " + TOOLTIP_MAX + " characters when present";
        }
        var lineCharacters = entry.info === undefined ? LABEL_LINE_CHARACTERS : INFO_LABEL_LINE_CHARACTERS;
        if (entry.type !== "list" && labelLines(entry.label, lineCharacters) > LABEL_LINES)
            return at + ".label must fit " + LABEL_LINES + " lines of " + lineCharacters + " characters";
        var schemaLink = linkError(entry, at, "description");
        if (schemaLink !== "")
            return schemaLink;
        var listBad = Pads.listEntryError(entry, at, status, schemaError);
        if (listBad !== "")
            return listBad;
        if (entry.type === "enum") {
            if (!Array.isArray(entry.options) || entry.options.length === 0)
                return at + ".options must be a non-empty array for type enum";
            var seenOptions = [];
            for (var o = 0; o < entry.options.length; o++) {
                var option = entry.options[o];
                var optionAt = at + ".options." + o;
                if (!isPlainObject(option))
                    return optionAt + " must be an object";
                var optionKeys = Object.keys(option);
                for (var ok = 0; ok < optionKeys.length; ok++) {
                    if (OPTION_KEYS.indexOf(optionKeys[ok]) === -1)
                        return optionAt + " has unknown key " + JSON.stringify(optionKeys[ok]);
                }
                if (typeof option.value !== "string" || option.value.length === 0)
                    return optionAt + ".value must be a non-empty string";
                if (!isPrintableLine(option.label, PRESET_LABEL_MAX))
                    return optionAt + ".label must be a printable line of 1 to " + PRESET_LABEL_MAX + " characters";
                if (seenOptions.indexOf(option.value) !== -1)
                    return at + ".options must hold distinct values";
                seenOptions.push(option.value);
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
        if (entry.placeholder !== undefined) {
            if (entry.optionsFrom === undefined)
                return at + ".placeholder needs optionsFrom";
            if (!isPrintableLine(entry.placeholder, STATUS_LABEL_MAX))
                return at + ".placeholder must be a printable line of 1 to " + STATUS_LABEL_MAX + " characters";
        }
        if (entry.hideEmpty !== undefined) {
            if (entry.optionsFrom === undefined)
                return at + ".hideEmpty needs optionsFrom";
            if (typeof entry.hideEmpty !== "boolean")
                return at + ".hideEmpty must be a boolean";
        }
        // A list draws as a section of its own, which no field gate places.
        if (entry.shownWhen !== undefined) {
            if (entry.type === "list")
                return at + ".shownWhen needs a flat setting";
            if (typeof entry.shownWhen !== "string" || !hasOwn(status, entry.shownWhen) || status[entry.shownWhen].type !== "presence")
                return at + ".shownWhen must name a presence status entry";
        }
        if (entry.presets !== undefined && entry.optionsFrom !== undefined)
            return at + " must not declare both presets and optionsFrom";
        if (entry.allowCustom !== undefined && entry.presets === undefined && entry.optionsFrom === undefined)
            return at + ".allowCustom needs presets or optionsFrom";
        if (entry.format !== undefined && entry.presets === undefined)
            return at + ".format needs presets";
        if (entry.type === "string" && entry.presets === undefined && entry.optionsFrom === undefined)
            return at + " with type string must declare presets or optionsFrom";
        if (entry.separator !== undefined) {
            if (entry.type !== "string" || entry.presets === undefined || entry.optionsFrom !== undefined)
                return at + ".separator needs static string presets";
            if (typeof entry.separator !== "string" || entry.separator.length === 0 || SettingValues.CONTROL_OR_SEPARATOR.test(entry.separator))
                return at + ".separator must be a non-empty printable string";
            // Joined selections and existing custom strings use the same value judge.
            if (entry.allowCustom !== true || entry.format !== undefined)
                return at + ".separator needs allowCustom true and no format";
        }
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
                if (entry.separator !== undefined && (preset.value.length === 0 || preset.value.indexOf(entry.separator) !== -1))
                    return presetAt + ".value must be non-empty and contain no separator";
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

// The refusal of a text hintFits refuses, after the text's key.
var HINT_RULE = " must end with no full stop when it is one sentence, and end each sentence with one when it is longer";

// The sentences of hint `text`: each ends where a full stop, a question
// mark or an exclamation mark meets a space, and keeps its mark, which the
// split's capture group hands back.
function hintSentences(text) {
    var parts = text.split(/([.?!]) +/);
    var sentences = [];
    for (var i = 0; i < parts.length; i += 2)
        sentences.push(i + 1 < parts.length ? parts[i] + parts[i + 1] : parts[i]);
    return sentences;
}

// Whether hint `text` keeps the copy rule (docs/architecture/design-system.md
// § Copy): a hint of one sentence ends with no full stop, and each sentence
// of a longer hint ends with one. It judges every declared text a Settings
// page draws as a hint: a schema entry's description, a status entry's
// hint, a sound event's description and a requirement's purpose.
function hintFits(text) {
    var sentences = hintSentences(text);
    if (sentences.length === 1)
        return !/\.$/.test(text);
    return sentences.every(function (sentence) { return /[.?!]$/.test(sentence); });
}

// How many lines of `perLine` characters `text` wraps to, or Infinity when
// a word is longer than a line. Like Qt's line breaking (Unicode UAX #14),
// a line breaks after a run of spaces, which takes no room at the line's
// end, and after a hyphen no digit follows (rule LB25 keeps "-1" whole);
// each line holds as many words as fit. tst_settingfield.qml holds the
// count to the drawn label.
function labelLines(text, perLine) {
    var segments = text.match(/(?:[^ -]|-(?=[0-9]))*(?:-| +|$)/g).filter(function (segment) { return segment !== ""; });
    var lines = 1;
    var used = 0;
    for (var i = 0; i < segments.length; i++) {
        var ink = segments[i].replace(/ +$/, "").length;
        if (ink > perLine)
            return Infinity;
        if (used > 0 && used + ink > perLine) {
            lines += 1;
            used = 0;
        }
        used += segments[i].length;
    }
    return lines;
}

function infoError(info, at) {
    return info === undefined || isPrintableLine(info, INFO_MAX) ? "" : at + ".info must be a printable line of 1 to " + INFO_MAX + " characters when present";
}

// The first defect of an entry's optional `link`, or "": an object of
// `text`, words the entry's FIELD holds, a flat schema entry's
// `description` or a status entry's `hint`, and `url`, an address
// LINK_URL_PATTERN admits. A VGS page uses a page reference in the text.
function linkError(entry, at, field) {
    var link = entry.link;
    if (link === undefined)
        return "";
    if (!isPlainObject(link))
        return at + ".link must be an object";
    var linkKeys = Object.keys(link);
    for (var k = 0; k < linkKeys.length; k++) {
        if (LINK_KEYS.indexOf(linkKeys[k]) === -1)
            return at + ".link has unknown key " + JSON.stringify(linkKeys[k]);
    }
    if (entry.type === "list")
        return at + ".link needs a flat setting";
    if (!isPrintableLine(link.text, LINK_TEXT_MAX))
        return at + ".link.text must be a printable line of 1 to " + LINK_TEXT_MAX + " characters";
    if (typeof entry[field] !== "string" || entry[field].indexOf(link.text) === -1)
        return at + ".link.text must be words of its " + field;
    if (typeof link.url !== "string" || link.url.length > LINK_URL_MAX || !LINK_URL_PATTERN.test(link.url))
        return at + ".link.url must be an https address of at most " + LINK_URL_MAX + " characters";
    return "";
}

// The first defect of a manifest's `status` key, or "". An object keyed by
// status key (STATUS_KEY_PATTERN), each entry naming a type from
// STATUS_TYPES and a printable `label`, with an optional printable `group`
// and `hint`, an optional `link` linkError admits, words of the hint that
// open an https address, an optional `action` statusActionError admits, and
// an optional boolean `hidden`. A `state` entry may declare `actions` in
// place of `action`: an object of two or more named actions; with either
// it may declare `aside`, a `tui` action of a listed screen. A `rows` entry
// may declare `icon` and `rowActions` (statusRowsEntryError). A `data`
// entry is never drawn, so it carries none of `group`, `hint`, `link`,
// `hidden`, `action`, `actions` or `aside`. A plugin publishes status
// only through its `status` capability, so the key needs the capability,
// and the capability needs at least one entry. TUI is the manifest's `tui`
// key or undefined, SYSTEM its judged `systemSteps` or undefined.
function statusError(status, capabilities, tui, system) {
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
        if (entry.hint !== undefined && !hintFits(entry.hint))
            return at + ".hint" + HINT_RULE;
        var statusInfo = infoError(entry.info, at);
        if (statusInfo !== "")
            return statusInfo;
        var statusLink = linkError(entry, at, "hint");
        if (statusLink !== "")
            return statusLink;
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
            var badAction = statusActionError(entry.type, declared[a].action, at + declared[a].at, tui, system, capabilities);
            if (badAction !== "")
                return badAction;
        }
        if (entry.type === "data" || entry.type === "launcherRows") {
            var drawn = ["group", "hint", "info", "link", "hidden", "action", "actions", "aside"];
            for (var d = 0; d < drawn.length; d++) {
                if (entry[drawn[d]] !== undefined)
                    return at + "." + drawn[d] + " needs a type Settings draws; " + entry.type + " is never drawn";
            }
        }
        var badRows = statusRowsEntryError(entry, at, tui, system, capabilities);
        if (badRows !== "")
            return badRows;
        var badAside = statusAsideError(entry, at, tui, system, capabilities);
        if (badAside !== "")
            return badAside;
    }
    return "";
}

// The actions status entry ENTRY declares, each { name, at, action }: its
// one `action`, NAME null and AT `.action`, or each of its `actions` by
// NAME, AT `.actions.<name>`; none for an entry without either. A `rows`
// entry's `rowActions` are not among them: each acts on one row
// (statusActionRequest).
function statusEntryActions(entry) {
    if (entry.action !== undefined)
        return [{ name: null, at: ".action", action: entry.action }];
    if (!isPlainObject(entry.actions))
        return [];
    return Object.keys(entry.actions).map(function (name) {
        return { name: name, at: ".actions." + name, action: entry.actions[name] };
    });
}

// The first defect of status entry ENTRY's rows keys, AT its path, or "":
// `icon` and `rowActions` only on a `rows` entry, which takes no `group`,
// since its label heads a section of its own. `icon` names the mark of
// the shipped Lucide set each row leads with. `rowActions` is an object of
// one or more actions by STATUS_KEY_PATTERN name, each one
// statusActionError admits whose route is `tui`, naming a script with no
// `entry`: a row action opens its own declared script with the row's `id`
// as its one argument, and a listed screen opens with none.
function statusRowsEntryError(entry, at, tui, system, capabilities) {
    if (entry.type !== "rows") {
        if (entry.icon !== undefined)
            return at + ".icon needs type rows, whose rows it leads";
        if (entry.rowActions !== undefined)
            return at + ".rowActions needs type rows, whose rows offer them";
        return "";
    }
    if (entry.group !== undefined)
        return at + ".group cannot be on a rows entry; its label heads a section of its own";
    if (entry.icon !== undefined && (typeof entry.icon !== "string" || !hasOwn(Lucide.ICONS, entry.icon)))
        return at + ".icon must name an icon of the shipped set, shell/Ui/icons/Lucide.js, got " + JSON.stringify(entry.icon);
    if (entry.rowActions === undefined)
        return "";
    if (!isPlainObject(entry.rowActions) || Object.keys(entry.rowActions).length === 0)
        return at + ".rowActions must be an object of one or more actions";
    var names = Object.keys(entry.rowActions);
    for (var i = 0; i < names.length; i++) {
        var actionAt = at + ".rowActions." + names[i];
        if (!STATUS_KEY_PATTERN.test(names[i]))
            return at + ".rowActions key " + JSON.stringify(names[i]) + " must match " + STATUS_KEY_PATTERN.source;
        var badAction = statusActionError(entry.type, entry.rowActions[names[i]], actionAt, tui, system, capabilities);
        if (badAction !== "")
            return badAction;
        if (entry.rowActions[names[i]].tui === undefined)
            return actionAt + " must name a tui; a row action opens its script with the row's id";
        if (isPlainObject(tui[entry.rowActions[names[i]].tui].entry))
            return actionAt + ".tui must name a script with no entry; a listed screen opens with no row id";
    }
    return "";
}

// The first defect of status entry ENTRY's `aside`, AT the entry's path, or
// "": absent, or on a `state` entry that declares `action` or `actions`, an
// action statusActionError admits whose route is `tui`, naming a script
// with an `entry`, which the page opens as a listed screen.
function statusAsideError(entry, at, tui, system, capabilities) {
    if (entry.aside === undefined)
        return "";
    if (entry.type !== "state")
        return at + ".aside needs type state, whose value says when it applies";
    if (entry.action === undefined && entry.actions === undefined)
        return at + ".aside needs the entry's action or actions, beside which the page draws it";
    var badAction = statusActionError(entry.type, entry.aside, at + ".aside", tui, system, capabilities);
    if (badAction !== "")
        return badAction;
    if (entry.aside.tui === undefined)
        return at + ".aside must name a tui; the page opens it as a listed screen";
    if (!isPlainObject(tui[entry.aside.tui].entry))
        return at + ".aside.tui must name a script with an entry, got " + JSON.stringify(entry.aside.tui);
    return "";
}

// The first defect of ACTION, one action of a status entry of type TYPE,
// AT its path, or "": an object of STATUS_ACTION_KEYS on an entry whose
// type is in STATUS_ACTION_TYPES, a printable `label` of at most STATUS_LABEL_MAX
// characters, an optional `tone` of STATUS_ACTION_TONES, an optional
// `icon` on a danger action, the name of its mark in the shipped Lucide set,
// since only a danger action draws one, and exactly one
// of STATUS_ACTION_ROUTES: `tui`, a name the
// manifest's TUI key declares; `system` or `undo`, a step the manifest's
// SYSTEM, its `systemSteps`, declares; `dictation`; or `file`, a path
// editArgs admits, absolute, under `~/` or relative to the configuration
// directory, or, on a `state` entry, `true`, a path its value supplies,
// on a manifest whose TUI names no script STATUS_FILE_TUI. An
// unknown key names the keys an action takes, so an `install` list reads
// as no route.
function statusActionError(type, action, at, tui, system, capabilities) {
    if (STATUS_ACTION_TYPES.indexOf(type) === -1)
        return at + " needs a type whose value says when it applies, one of " + STATUS_ACTION_TYPES.join(", ");
    if (!isPlainObject(action))
        return at + " must be an object";
    var keys = Object.keys(action);
    for (var i = 0; i < keys.length; i++) {
        if (STATUS_ACTION_KEYS.indexOf(keys[i]) === -1)
            return at + " has unknown key " + JSON.stringify(keys[i]) + "; an action takes " + STATUS_ACTION_KEYS.join(", ");
    }
    if (!isPrintableLine(action.label, STATUS_LABEL_MAX))
        return at + ".label must be a printable line of 1 to " + STATUS_LABEL_MAX + " characters";
    if (action.tone !== undefined && STATUS_ACTION_TONES.indexOf(action.tone) === -1)
        return at + ".tone must be one of " + STATUS_ACTION_TONES.join(", ") + ", got " + JSON.stringify(action.tone);
    if (action.icon !== undefined && action.tone !== "danger")
        return at + ".icon needs tone danger; only a danger action draws a mark";
    if (action.icon !== undefined && (typeof action.icon !== "string" || !hasOwn(Lucide.ICONS, action.icon)))
        return at + ".icon must name an icon of the shipped set, shell/Ui/icons/Lucide.js, got " + JSON.stringify(action.icon);
    if (STATUS_ACTION_ROUTES.filter(function (route) { return action[route] !== undefined; }).length !== 1)
        return at + " must name exactly one of " + STATUS_ACTION_ROUTES.join(", ");
    if (action.dictation !== undefined) {
        if (action.dictation !== "setup")
            return at + ".dictation must be setup";
        if (capabilities.indexOf("dictation") === -1)
            return at + ".dictation needs capability dictation";
        return "";
    }
    if (action.file !== undefined) {
        if (action.file === true) {
            if (type !== "state")
                return at + ".file true needs type state, whose value supplies the path";
        } else if (typeof action.file !== "string" || !editArgs(action.file).ok)
            return at + ".file must be true or a path with no control character and no .. segment, got " + JSON.stringify(action.file);
        if (isPlainObject(tui) && hasOwn(tui, STATUS_FILE_TUI))
            return at + ".file needs no tui script named " + STATUS_FILE_TUI + "; a file action's run reads under that name";
        return "";
    }
    var stepRoute = action.system !== undefined ? "system" : action.undo !== undefined ? "undo" : null;
    if (stepRoute !== null) {
        if (typeof action[stepRoute] !== "string" || !Array.isArray(system) || system.indexOf(action[stepRoute]) === -1)
            return at + "." + stepRoute + " must name a step of the manifest's systemSteps, got " + JSON.stringify(action[stepRoute]);
        return "";
    }
    if (typeof action.tui !== "string" || !isPlainObject(tui) || !hasOwn(tui, action.tui))
        return at + ".tui must name a script of the manifest's tui key, got " + JSON.stringify(action.tui);
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

// The longest timed grant the core TUI `sudo-grant` takes, in minutes;
// bin/vgshell-sudo-grant judges the same bound again.
var SUDO_MINUTES_MAX = 1440;

// Whether DURATION is a grant the core TUI `sudo-grant` takes: a string of
// whole minutes from 1 to SUDO_MINUTES_MAX with no leading zero, or
// `indefinite`.
function sudoDurationValid(duration) {
    if (duration === "indefinite")
        return true;
    return typeof duration === "string" && /^[1-9][0-9]{0,3}$/.test(duration) && Number(duration) <= SUDO_MINUTES_MAX;
}

// What the SudoGrant owner holds after one run of `bin/vgshell-sudo-grant
// status`, COMPLETION { code, status } or null for a run that never
// started, STDOUT and STDERR its output: { state, until, rootHalf, line }.
// `state` is `unknown` before a read answers and after one fails, `absent`
// while the grant's root half is not installed, `inactive`, `active`, or
// `nixos`, where the system configuration holds every sudo rule; `until`
// is an active grant's ISO deadline or `indefinite`, else ""; `rootHalf`
// is `current`, `stale` or `absent`, "" for nixos and unknown. A run that
// prints no status line reads `unknown`, and `line` is the log line naming
// why: `sudo: read=unstarted`, `sudo: read=failed exit=<code>
// status=<status> <first stderr line>`, or `sudo: read=malformed
// line=<first line as JSON>`; `line` is "" otherwise.
function sudoReport(completion, stdout, stderr) {
    var failed = function (line) { return { state: "unknown", until: "", rootHalf: "", line: line }; };
    if (completion === null)
        return failed("sudo: read=unstarted");
    if (completion.status !== 0 || completion.code !== 0)
        return failed("sudo: read=failed exit=" + completion.code + " status=" + completion.status + " " + String(stderr).split("\n")[0]);
    var text = String(stdout).replace(/\n$/, "");
    if (text === "sudo-grant=skipped=nixos-config")
        return { state: "nixos", until: "", rootHalf: "", line: "" };
    if (text === "sudo-grant=inactive root-half=absent")
        return { state: "absent", until: "", rootHalf: "absent", line: "" };
    var inactive = /^sudo-grant=inactive root-half=(current|stale)$/.exec(text);
    if (inactive !== null)
        return { state: "inactive", until: "", rootHalf: inactive[1], line: "" };
    var active = /^sudo-grant=active until=(indefinite|[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) root-half=(current|stale)$/.exec(text);
    if (active !== null)
        return { state: "active", until: active[1], rootHalf: active[2], line: "" };
    return failed("sudo: read=malformed line=" + JSON.stringify(text.split("\n")[0]));
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

// The entry of SOUNDS with ID, or null.
function soundOf(id) {
    for (var i = 0; i < SOUNDS.length; i++)
        if (SOUNDS[i].id === id) return SOUNDS[i];
    return null;
}

// The values the sound event ENTRY takes, as the Sounds page offers them:
// [{ value, label, playable }], SOUND_OFF first, then SOUND_OWN under the
// plugin's name for it for an event the plugin sounds itself, else every
// sound of SOUNDS. `playable` marks a sound the core's player has a file
// for, which the page's Test plays.
function soundOffers(entry) {
    var off = [{ value: SOUND_OFF, label: SOUND_OFF_LABEL, playable: false }];
    if (entry.own !== undefined)
        return off.concat([{ value: SOUND_OWN, label: entry.own, playable: false }]);
    return off.concat(SOUNDS.map(function (sound) { return { value: sound.id, label: sound.label, playable: true }; }));
}

// Whether VALUE is one the sound event ENTRY takes: one of soundOffers.
function soundValueFits(entry, value) {
    return soundOffers(entry).some(function (offer) { return offer.value === value; });
}

// Whether EVENT of MANIFEST is one whose value the plugin holds.
function soundHeld(manifest, event) {
    return hasOwn(manifest.sounds, event) && manifest.sounds[event].held === true;
}

// The first defect of a manifest's `sounds` key, or "": a non-empty object
// of events, each named by ConfigLogic.NAME_PATTERN and holding only SOUND_EVENT_KEYS,
// with a printable `label`, an optional printable `description` and `own`,
// and a `default` the event takes (soundValueFits). `held` is `true` when
// present, needs `own` and takes no `default`. The key needs capability
// `sounds`, which hands the plugin its events' choices and the core's
// player, and the capability needs the key.
function soundsError(sounds, capabilities) {
    if (!isPlainObject(sounds) || Object.keys(sounds).length === 0)
        return "sounds must be a non-empty object";
    if (capabilities.indexOf("sounds") === -1)
        return "sounds needs capability sounds";
    var names = Object.keys(sounds);
    for (var i = 0; i < names.length; i++) {
        var name = names[i];
        var at = "sounds." + name;
        var event = sounds[name];
        if (!ConfigLogic.NAME_PATTERN.test(name))
            return "sounds has malformed event name " + JSON.stringify(name);
        if (!isPlainObject(event))
            return at + " must be an object";
        var keys = Object.keys(event);
        for (var k = 0; k < keys.length; k++) {
            if (SOUND_EVENT_KEYS.indexOf(keys[k]) === -1)
                return at + " has unknown key " + JSON.stringify(keys[k]);
        }
        if (!isPrintableLine(event.label, STATUS_LABEL_MAX))
            return at + ".label must be a printable line of 1 to " + STATUS_LABEL_MAX + " characters";
        if (event.description !== undefined && !isPrintableLine(event.description, STATUS_HINT_MAX))
            return at + ".description must be a printable line of 1 to " + STATUS_HINT_MAX + " characters when present";
        if (event.description !== undefined && !hintFits(event.description))
            return at + ".description" + HINT_RULE;
        if (event.own !== undefined && !isPrintableLine(event.own, STATUS_LABEL_MAX))
            return at + ".own must be a printable line of 1 to " + STATUS_LABEL_MAX + " characters when present";
        if (event.held !== undefined) {
            if (event.held !== true)
                return at + ".held must be true when present";
            if (event.own === undefined)
                return at + ".held needs own";
            if (event["default"] !== undefined)
                return at + ".default must be absent beside held: the plugin states the value";
            continue;
        }
        if (typeof event["default"] !== "string" || !soundValueFits(event, event["default"]))
            return at + ".default must be " + (event.own !== undefined ? JSON.stringify(SOUND_OWN) : "a sound of the core's set") + " or \"\", got " + JSON.stringify(event["default"]);
    }
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
// with a tone of STATUS_STATE_TONES, a printable text, a boolean or named
// `action` and a boolean `aside` when present; `text` a printable line; `count`
// a whole number from 0; `time` a whole number of milliseconds since the
// Unix epoch, from 0; `data` plain JSON; `choices` a bounded list of labeled,
// distinct, non-empty string ids; `rows` a list statusRowFits admits row by
// row, at most STATUS_LIST_MAX long, no id twice.
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
        if (statusStateHidden(value)) return true;
        var keys = Object.keys(value);
        for (var i = 0; i < keys.length; i++)
            if (STATUS_STATE_KEYS.indexOf(keys[i]) === -1) return false;
        return typeof value.tone === "string" && hasOwn(STATUS_STATE_TONES, value.tone) && isPrintableLine(value.text, STATUS_TEXT_MAX)
            && (value.lines === undefined || (Array.isArray(value.lines) && value.lines.length > 0 && value.lines.length <= STATUS_LIST_MAX
                && value.lines.every(function (line) { return isPrintableLine(line, STATUS_TEXT_MAX); })))
            && (value.hint === undefined || isPrintableLine(value.hint, STATUS_HINT_MAX))
            && infoError(value.info, "") === ""
            && (value.file === undefined || (typeof value.file === "string" && editArgs(value.file).ok))
            && (value.action === undefined || typeof value.action === "boolean" || typeof value.action === "string")
            && (value.aside === undefined || typeof value.aside === "boolean")
            && (value.available === undefined || value.available === false);
    }
    if (type === "text") return isPrintableLine(value, STATUS_TEXT_MAX);
    if (type === "count" || type === "time") return typeof value === "number" && isFinite(value) && value >= 0 && Math.floor(value) === value && value <= Number.MAX_SAFE_INTEGER;
    if (type === "data") return isPlainJson(value);
    if (type === "rows") {
        if (!Array.isArray(value) || value.length > STATUS_LIST_MAX) return false;
        var rowIds = [];
        for (var w = 0; w < value.length; w++) {
            if (!statusRowFits(value[w]) || rowIds.indexOf(value[w].id) !== -1) return false;
            rowIds.push(value[w].id);
        }
        return true;
    }
    throw new Error("statusValueFits: status type " + JSON.stringify(type) + " passed validation but has no rule");
}

// Whether ROW is one row of a `rows` value: plain JSON holding only
// STATUS_ROW_KEYS, an `id` the core may hand a TUI as one argument
// (tuiArgsValid), a printable `label` of at most STATUS_LABEL_MAX, and when
// present a printable `secondary` of at most STATUS_TEXT_MAX, a `state` of
// STATUS_ROW_STATE_KEYS with a tone of STATUS_STATE_TONES and a printable
// `text` of at most STATUS_LABEL_MAX, and `actions`, a list of distinct
// STATUS_KEY_PATTERN names. Unique ids are a list-level rule in
// statusValueFits; that each action is declared, statusDeclarationFits'.
function statusRowFits(row) {
    if (!isPlainObject(row) || !isPlainJson(row)) return false;
    if (Object.keys(row).some(function (key) { return STATUS_ROW_KEYS.indexOf(key) === -1; })) return false;
    var state = row.state;
    return typeof row.id === "string" && tuiArgsValid([row.id])
        && isPrintableLine(row.label, STATUS_LABEL_MAX)
        && (row.secondary === undefined || isPrintableLine(row.secondary, STATUS_TEXT_MAX))
        && (state === undefined || (isPlainObject(state) && Object.keys(state).every(function (key) { return STATUS_ROW_STATE_KEYS.indexOf(key) !== -1; })
            && typeof state.tone === "string" && hasOwn(STATUS_STATE_TONES, state.tone) && isPrintableLine(state.text, STATUS_LABEL_MAX)))
        && (row.actions === undefined || (Array.isArray(row.actions) && row.actions.every(function (name, index) {
            return typeof name === "string" && STATUS_KEY_PATTERN.test(name) && row.actions.indexOf(name) === index;
        })));
}

// Whether VALUE, a plain `state` object, is the hidden value:
// `hidden: true` and no other key.
function statusStateHidden(value) {
    return Object.keys(value).length === 1 && value.hidden === true;
}

// Whether `item` is one item of a `presenceList` value: plain JSON holding
// only STATUS_LIST_ITEM_KEYS, a printable `label` of at most
// STATUS_LABEL_MAX characters, a `value` of STATUS_PRESENCE_TONES, and when
// present a printable `hint` of at most STATUS_HINT_MAX, an `info` infoError
// admits and a `secret` of SECRET_ACCOUNT_PATTERN.
function statusListItemFits(item) {
    if (!isPlainObject(item) || !isPlainJson(item)) return false;
    var keys = Object.keys(item);
    for (var i = 0; i < keys.length; i++)
        if (STATUS_LIST_ITEM_KEYS.indexOf(keys[i]) === -1) return false;
    return isPrintableLine(item.label, STATUS_LABEL_MAX)
        && typeof item.value === "string" && hasOwn(STATUS_PRESENCE_TONES, item.value)
        && (item.hint === undefined || isPrintableLine(item.hint, STATUS_HINT_MAX))
        && infoError(item.info, "") === ""
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
// for an entry that declares an action, a name only for an entry whose
// `actions` hold it, STATUS_TOOLS_ACTION only for a required step of a
// manifest that declares a required tool, `aside` only for an entry that
// declares one and `available: false` only for a required step that is
// not done, offers no action or aside, and carries its own `hint`, since
// the declaration's hint names the action the step offers elsewhere, a
// `presenceList` item carries `secret` only for a manifest that declares
// `secrets`, and a `rows` row names in `actions` only the entry's
// `rowActions`. A `state` value carries `file` exactly while the action it
// offers is a file action declared `file: true`, whose path it is.
function statusDeclarationFits(manifest, entry, value) {
    if (entry.type === "state") {
        if (entry.setup === true && statusStateHidden(value)) return false;
        if (value.aside !== undefined && entry.aside === undefined) return false;
        if (value.available === false && (entry.setup !== true || value.tone === "ok" || (value.action !== undefined && value.action !== false) || value.aside === true
            || value.hint === undefined)) return false;
        if ((value.file !== undefined) !== statusValueOffersFile(entry, value)) return false;
        if (value.action === STATUS_TOOLS_ACTION) return entry.setup === true && manifest.requirements.some(function (row) { return !row.optional; });
        if (value.action === undefined) return true;
        if (typeof value.action === "string") return entry.actions !== undefined && hasOwn(entry.actions, value.action);
        return entry.action !== undefined;
    }
    if (entry.type === "presenceList") return manifest.secrets !== undefined || value.every(function (item) { return item.secret === undefined; });
    if (entry.type === "rows") return value.every(function (row) {
        return row.actions === undefined || row.actions.every(function (name) { return entry.rowActions !== undefined && hasOwn(entry.rowActions, name); });
    });
    return true;
}

// Whether `state` VALUE offers a file action of ENTRY declared `file:
// true`, whose path the value must then carry: `action: true` with such
// an `action`, or the name of such one of its `actions`.
function statusValueOffersFile(entry, value) {
    var offered = value.action === true ? entry.action
        : typeof value.action === "string" && entry.actions !== undefined && hasOwn(entry.actions, value.action) ? entry.actions[value.action] : undefined;
    return offered !== undefined && offered.file === true;
}

// Whether the Settings window draws status entry `entry`: every type but
// `data` and `choices`, unless the entry is `hidden`. Choices feed editors.
function statusDisplayable(entry) {
    return entry.type !== "data" && entry.type !== "choices" && entry.type !== "launcherRows" && entry.hidden !== true;
}

// Select models keyed by string setting name. Only accepted status enters
// here. Neither a new list nor an absent configured id writes settings.
// Each offer is listed once. The first offer stands for the unset value:
// its entry carries "" unless its own id is configured. A configured id no
// offer holds is listed as unavailable under the entry's label, never the
// id, which a user cannot read, unless the entry declares
// `allowCustom`, whose field shows it under Custom… instead. An entry that
// declares `placeholder` has no unset offer: "" means nothing is chosen.
// An entry that declares `hideEmpty` has an empty model while nothing is
// offered, whatever is configured, and the page then draws no field.
// Settings choices: docs/architecture/design-system.md § Settings pages.
function settingChoices(manifest, values, settings) {
    var out = {};
    var choices = function (entry, configured) {
        var offered = hasOwn(values, entry.optionsFrom) ? values[entry.optionsFrom] : [];
        var model = offered.map(function (choice, index) {
            var unset = entry.placeholder === undefined && index === 0 && configured !== choice.value;
            return { label: choice.label, value: unset ? "" : choice.value };
        });
        if (entry.hideEmpty === true && offered.length === 0) return model;
        if (entry.allowCustom !== true && configured !== "" && !offered.some(function (choice) { return choice.value === configured; }))
            model.push({ label: entry.label + " (unavailable)", value: configured });
        return model;
    };
    Object.keys(manifest.schema).forEach(function (key) {
        var entry = manifest.schema[key];
        if (entry.type === "list") out[key] = Pads.listChoices(entry, settings[key], choices);
        else if (entry.optionsFrom !== undefined) out[key] = choices(entry, settings[key]);
    });
    return frozenJson(out);
}

// The keys of MANIFEST's schema fields that declare `shownWhen` and whose
// presence entry does not read present in VALUES, the plugin's published
// status. An unreported entry withholds its field too: before the service's
// first publish, and while the plugin is off, since PluginStatus drops the
// record of a disabled plugin, the page draws no field for hardware it has
// not seen.
function withheldFields(manifest, values) {
    return Object.keys(manifest.schema).filter(function (key) {
        var entry = manifest.schema[key];
        return entry.shownWhen !== undefined && !(hasOwn(values, entry.shownWhen) && values[entry.shownWhen] === "present");
    });
}

// The badge tone Settings draws a reported status value with: the
// presence's or the state's tone, "" for a type drawn as text, for a
// `presenceList`, whose items carry their own, and for `rows`, whose rows
// do (statusRowValue).
function statusTone(type, value) {
    if (type === "presence") return STATUS_PRESENCE_TONES[value];
    if (type === "state") return STATUS_STATE_TONES[value.tone];
    return "";
}

// A reported VALUE of status entry ENTRY as a Status row carries it: a
// `presenceList`'s items each as { label, value, hint, info, tone, secret,
// access }, `hint`, `info` and `secret` "" when the item omits them, `tone`
// its presence's, and `access` what the page offers for its secret,
// SECRET_ACCESS by its presence, "" for an item without one; a `rows`
// value's rows each as { id, label, secondary, state, tone, chip, actions },
// `secondary` and `state`, the state's text, "" when the row omits them,
// `tone` the state's badge tone, "" for none, `chip` whether the state
// needs the user, a tone of STATUS_ROW_CHIP_TONES, which a page draws as a
// chip and any other state as text, and `actions` each row action it
// offers, in its own order, as { name, label, tone, icon }, `tone` and
// `icon` as statusActionTone and statusActionIcon read them; any other
// value as published.
function statusRowValue(entry, value) {
    if (entry.type === "rows") return value.map(function (row) {
        var tone = row.state === undefined ? "" : row.state.tone;
        return {
            id: row.id,
            label: row.label,
            secondary: row.secondary === undefined ? "" : row.secondary,
            state: row.state === undefined ? "" : row.state.text,
            tone: tone === "" ? "" : STATUS_STATE_TONES[tone],
            chip: STATUS_ROW_CHIP_TONES.indexOf(tone) !== -1,
            actions: (row.actions === undefined ? [] : row.actions).map(function (name) {
                var action = entry.rowActions[name];
                return { name: name, label: action.label, tone: statusActionTone(action), icon: statusActionIcon(action) };
            })
        };
    });
    if (entry.type !== "presenceList") return value;
    return value.map(function (item) {
        return {
            label: item.label,
            value: item.value,
            hint: item.hint === undefined ? "" : item.hint,
            info: item.info === undefined ? "" : item.info,
            tone: STATUS_PRESENCE_TONES[item.value],
            secret: item.secret === undefined ? "" : item.secret,
            access: item.secret === undefined ? "" : SECRET_ACCESS[item.value]
        };
    });
}

// The action of status entry ENTRY that applies to its published VALUE, or
// null: its declared `action` for a `presence` while nothing is there,
// `absent`, and for a `state` while its writer says so, `action: true`; the
// one of its declared `actions` a `state` value names (D061), none for
// STATUS_TOOLS_ACTION, whose Review opens the requirement notice and no
// declared action; and for a `rows` entry, its `action` on the whole list,
// such as Add, whenever the list is reported.
function statusActionOffered(entry, value) {
    switch (entry.type) {
    case "presence": return value === "absent" ? entry.action : null;
    case "state":
        if (value.action === STATUS_TOOLS_ACTION) return null;
        if (entry.actions !== undefined) return typeof value.action === "string" ? entry.actions[value.action] : null;
        return value.action === true ? entry.action : null;
    case "rows": return entry.action;
    }
    throw new Error("statusActionOffered: status type " + JSON.stringify(entry.type) + " takes no action");
}

// What a Status row carries of ENTRY's step for its published VALUE, null
// while unreported: null for an entry that declares none, else { label,
// icon, offered, tui, tone }, the label of the action that applies, or of the
// entry's one `action` while none does, "" for `actions` none of which
// applies, `offered` false while none applies, `tui` the plugin's own TUI
// the offered action opens, "" while none is offered or it opens none, so a
// page can draw that TUI's button as the step, and `tone` the labelled
// action's, "" or one of STATUS_ACTION_TONES, and `icon` its mark's name,
// "" for none (statusActionIcon). An offered action whose
// script lacks a command stays offered: its press raises the requirement
// notice for that script's commands and starts it once they are found
// (tuiRunFor).
function statusRowAction(entry, value) {
    if (entry.action === undefined && entry.actions === undefined) return null;
    var offered = value === null ? null : statusActionOffered(entry, value);
    if (offered !== null) return { label: offered.label, icon: statusActionIcon(offered), tone: statusActionTone(offered), offered: true, tui: offered.tui === undefined ? "" : offered.tui };
    return { label: entry.action === undefined ? "" : entry.action.label, icon: entry.action === undefined ? "" : statusActionIcon(entry.action),
        tone: entry.action === undefined ? "" : statusActionTone(entry.action), offered: false, tui: "" };
}

// The declared TUI screens a status entry may open, its `aside`'s, then its
// `rowActions`', last, in manifest order and without duplicates.
function statusDeclaredTuis(entry) {
    var seen = Object.create(null);
    var out = [];
    var actions = statusEntryActions(entry).map(function (declared) { return declared.action; });
    if (entry.aside !== undefined) actions.push(entry.aside);
    if (entry.rowActions !== undefined) Object.keys(entry.rowActions).forEach(function (name) { actions.push(entry.rowActions[name]); });
    actions.forEach(function (action) {
        var tui = action.tui;
        if (typeof tui === "string" && !seen[tui]) {
            seen[tui] = true;
            out.push(tui);
        }
    });
    return out;
}

// What a Status row carries of ENTRY's `aside` for its published VALUE, null
// while unreported: null for an entry that declares none, else { label,
// icon, tone, tui, offered }, `offered` while VALUE carries `aside: true`, as an
// action is offered whatever its script lacks (statusRowAction).
function statusRowAside(entry, value) {
    if (entry.aside === undefined) return null;
    return { label: entry.aside.label, icon: statusActionIcon(entry.aside), tone: statusActionTone(entry.aside), tui: entry.aside.tui, offered: value !== null && value.aside === true };
}

// The tone a page draws declared ACTION in: its `tone`, else "".
function statusActionTone(action) {
    return action.tone === undefined ? "" : action.tone;
}

// The mark a page leads declared danger ACTION with: its `icon`, else "",
// which draws the trash mark.
function statusActionIcon(action) {
    return action.icon === undefined ? "" : action.icon;
}

// The Status rows the plugin manager shows for a plugin: one per entry
// statusDisplayable admits whose `state` value is not hidden (statusStateHidden),
// in manifest key order, as { key, type, label,
// group, setup, setting, step, settings, icon, hint, info, link, secrets,
// declaredTuis, systemStep, action, aside, report, value, tone }. `group`, `hint`,
// `info` and `icon` are "" when the manifest omits them; a reported
// `state` value's own `hint` and `info` stand in the entry's.
// `link`, the words of the declared hint that open an https address, is
// null when the manifest omits it. `settings` holds for a `rows` entry the Settings tab draws
// (pagePlacementError). `secrets` holds for the entry that lists the plugin's stored keys,
// a `presenceList` of a manifest that declares `secrets`, which a page
// draws with its setup. `declaredTuis` is each TUI the entry's actions may
// open, in declaration order. `systemStep` holds for an entry an action of
// which runs or undoes a core system step: its plugin reads the step
// through capability `system`, which lends it no reading until the core's
// first probe ends, so its wait while unreported ends. `action` is
// statusRowAction's: null for an entry without one, else { label, tone, offered, tui },
// `offered` false while unreported, and `aside` statusRowAside's. `report` is `reported` with the published `value`
// (statusRowValue) and its `tone`, or `unreported` with `value` null and
// `tone` "" while `values` holds nothing for the key.
function statusRows(manifest, values) {
    return Object.keys(manifest.status).filter(function (key) {
        var entry = manifest.status[key];
        return statusDisplayable(entry) && !(entry.type === "state" && hasOwn(values, key) && statusStateHidden(values[key]));
    }).map(function (key) {
        var entry = manifest.status[key];
        var reported = hasOwn(values, key);
        var value = reported ? values[key] : null;
        var hint = entry.type === "state" && value !== null && value.hint !== undefined
            ? value.hint : entry.hint === undefined ? "" : entry.hint;
        var info = entry.type === "state" && value !== null && value.info !== undefined
            ? value.info : entry.info === undefined ? "" : entry.info;
        return {
            key: key,
            type: entry.type,
            label: entry.label,
            group: entry.group === undefined ? "" : entry.group,
            setup: entry.setup === true,
            setting: entry.setting === undefined ? "" : entry.setting,
            step: entry.step === undefined ? "" : entry.step,
            settings: entry.settings === true,
            icon: entry.icon === undefined ? "" : entry.icon,
            hint: hint,
            info: info,
            link: entry.link === undefined ? null : { text: entry.link.text, url: entry.link.url },
            secrets: entry.type === "presenceList" && manifest.secrets !== undefined,
            declaredTuis: statusDeclaredTuis(entry),
            systemStep: statusEntryActions(entry).some(function (declared) { return declared.action.system !== undefined || declared.action.undo !== undefined; }),
            action: statusRowAction(entry, value),
            aside: statusRowAside(entry, value),
            report: reported ? "reported" : "unreported",
            value: reported ? statusRowValue(entry, value) : null,
            tone: reported ? statusTone(entry.type, value) : ""
        };
    });
}

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

// Every request for a plugin's own script, TuiRunner's run and runFor, keeps
// tuiRun's refusal and focus rules, with ARGS after the script as tuiRun takes
// them. A valid request whose script lacks a required command MISSING holds
// answers { ok: true, kind: "install", commands }, COMMANDS those it lacks,
// the requirement notice's list.
function tuiRunFor(manifest, enabled, sourceDir, runner, name, missing, args) {
    var request = tuiRun(manifest, enabled, sourceDir, runner, name, args);
    if (!request.ok && request.action === "none") return request;
    var lacking = tuiMissingRequirements(manifest, name, missing);
    if (lacking.length > 0) return { ok: true, kind: "install", commands: lacking };
    return request;
}

// What the `manager` capability's `act(id, key, row, rowAction)` does for
// status entry KEY of plugin MANIFEST, null for an id no plugin has,
// ENABLED and VALUES its published values: { ok: true, kind: "tui", name } to open the plugin's own
// TUI NAME, { ok: true, kind: "system", args } to open the core TUI
// `core/system` with ARGS, `apply` or `undo` and its declared step,
// { ok: true, kind: "file", path } to open PATH (editRoute) as the
// plugin's own run, the action's declared path or, for `file: true`, the
// published value's `file`, or { ok: false,
// answer } with `unknown: <id>` or statusActionRefusal's line: `undeclared`
// for an entry without an action, `disabled` for a disabled plugin and
// `not-offered` while the published value does not call for it. With ROW,
// the act is ROW_ACTION, a name of the `rows` entry's `rowActions`, on the
// published row whose `id` is ROW: { ok: true, kind: "tui", name, args },
// ARGS [ROW], the row's id as the script's one argument, `undeclared` for
// a name the entry's `rowActions` lack, and `row-changed` while no
// published row of that id names it.
function statusActionRequest(manifest, id, enabled, values, key, row, rowAction) {
    if (manifest === null)
        return { ok: false, answer: "unknown: " + tuiLabel(id) };
    if (row !== undefined) {
        var rowsEntry = typeof key === "string" && hasOwn(manifest.status, key) ? manifest.status[key] : null;
        if (rowsEntry === null || rowsEntry.rowActions === undefined || typeof rowAction !== "string" || !hasOwn(rowsEntry.rowActions, rowAction))
            return { ok: false, answer: statusActionRefusal(key, "undeclared") };
        if (!enabled)
            return { ok: false, answer: statusActionRefusal(key, "disabled") };
        var offering = (hasOwn(values, key) ? values[key] : []).some(function (published) {
            return published.id === row && published.actions !== undefined && published.actions.indexOf(rowAction) !== -1;
        });
        if (!offering)
            return { ok: false, answer: statusActionRefusal(key, "row-changed") };
        return { ok: true, kind: "tui", name: rowsEntry.rowActions[rowAction].tui, args: [row] };
    }
    if (typeof key !== "string" || !hasOwn(manifest.status, key) || statusEntryActions(manifest.status[key]).length === 0)
        return { ok: false, answer: statusActionRefusal(key, "undeclared") };
    if (!enabled)
        return { ok: false, answer: statusActionRefusal(key, "disabled") };
    var action = hasOwn(values, key) ? statusActionOffered(manifest.status[key], values[key]) : null;
    if (action === null)
        return { ok: false, answer: statusActionRefusal(key, "not-offered") };
    if (action.dictation !== undefined)
        return { ok: true, kind: "core", name: "dictation-setup" };
    if (action.system !== undefined)
        return { ok: true, kind: "system", args: ["apply", action.system] };
    if (action.undo !== undefined)
        return { ok: true, kind: "system", args: ["undo", action.undo] };
    if (action.file !== undefined)
        return { ok: true, kind: "file", path: action.file === true ? values[key].file : action.file };
    return { ok: true, kind: "tui", name: action.tui };
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
// and only a verb its access offers (SECRET_VERBS): `store` while the store
// can be asked and `clear` while something is stored. { ok: true, argv,
// input } with the secret-tool argv and the
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
    if (SECRET_VERBS[verb].indexOf(SECRET_ACCESS[item.value]) === -1)
        return refused("not-offered");
    var attributes = ["service", manifest.secrets.service, "account", account];
    if (verb === "clear")
        return { ok: true, argv: ["secret-tool", "clear"].concat(attributes), input: null };
    if (!secretValueValid(secret))
        return refused("value");
    return { ok: true, argv: ["secret-tool", "store", "--label=" + manifest.secrets.label + " " + account].concat(attributes), input: secret };
}

// The key capture control's key table: a Qt 6 `Qt::Key` value
// (qnamespace.h) and the keysym name ConfigLogic.hyprlandKey writes for it. A key
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
// Each of ConfigLogic.HYPRLAND_MODIFIERS as a `Qt::KeyboardModifier` flag. Qt reports
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
// ConfigLogic.hyprlandKey writes, so a captured combo is the string the text entry
// stores for the same keys; { kind: "held", modifiers } while only
// modifiers are down, in ConfigLogic.HYPRLAND_MODIFIERS order; { kind: "text" } for a
// key that types or edits text with no modifier but SHIFT, which a global
// bind would take from every text field; or { kind: "unnamed" } for a key
// neither table names.
function capturedKey(key, modifiers) {
    var held = ConfigLogic.HYPRLAND_MODIFIERS.filter(function (mod) {
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
    return { kind: "key", key: ConfigLogic.hyprlandKey(held.concat([names[key]]).join("+")).key };
}

// Who else asks for KEY, the key a capture or the text entry gives
// shortcut SHORTCUT of plugin ID: { plugins: [{ id, shortcut }], user },
// the plugins, by id, from the key each bind of SECTIONS asks for, whether
// or not the layer's first-by-id rule (HyprlandLayer.resolveBinds) gives it
// the key, so a key that would take another plugin's bind names it; and
// whether FOREIGN, the keys something other than the layer binds
// (HyprlandState.foreignBinds), holds it. A hint: nothing refuses the key.
function keyConflicts(key, sections, foreign, id, shortcut) {
    var parsed = ConfigLogic.hyprlandKey(key);
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

function keyValues(value) {
    return (Array.isArray(value) ? value : [value]).map(function (item) { return ConfigLogic.hyprlandKey(item).key; });
}

function keyWriteValue(value) {
    var keys = keyValues(value);
    return keys.length === 1 ? keys[0] : keys;
}

function keyRowValue(value) {
    return value === null ? null : keyWriteValue(value);
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
// how the theme reaches Hyprland. Options need no capability: the core
// writes them from the manifest, and a plugin names `hyprland` only to read
// Hyprland's values back. Monitors need the `monitors` capability and name a
// plugin settings key without a schema row, so the Settings page does not
// draw it.
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
        if (typeof bind.shortcut !== "string" || !ConfigLogic.NAME_PATTERN.test(bind.shortcut))
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
        var keyBad = ConfigLogic.keyValueError(bind.key, at + ".key", false);
        if (keyBad !== "")
            return keyBad;
        var values = keyValues(bind.key);
        for (var v = 0; v < values.length; v++) {
            var keyAt = Array.isArray(bind.key) ? at + ".key." + v : at + ".key";
            if (bind.tap === true && ConfigLogic.keyHasModifiers(values[v]))
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
        var offered = optionValues(entry);
        for (var o = 0; o < offered.length; o++) {
            if (row.choices.indexOf(offered[o]) === -1)
                return "offers " + JSON.stringify(offered[o]) + ", not one of " + row.choices.join(", ");
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
    if (!isPrintableLine(requirement.dbus.label, REQUIREMENT_LABEL_MAX))
        return { ok: false, error: at + ".dbus.label must be a printable line of 1 to " + REQUIREMENT_LABEL_MAX + " characters" };
    return { ok: true, at: at + ".dbus.name", name: requirement.dbus.name };
}

// The first defect of a `requirements` list, or "": a manifest's key and
// the core's own config/requirements.json both pass through here. Each
// entry is an object of REQUIREMENT_KEYS and names exactly one identity:
// `command`, a bare command name PackageManagers.validCommand accepts, or
// `dbus`, a well-known name on the system or session bus with the `label`
// a page lists it by, one printable line of 1 to REQUIREMENT_LABEL_MAX
// characters. The identity is
// declared once, and never names a plugin (D005). `packages`, when present,
// is an object whose keys are manager ids of PackageManagers.MANAGERS and
// whose values are package names PackageManagers.validName accepts;
// `optional`, when present, is a boolean; `purpose` is one printable line
// of 1 to REQUIREMENT_PURPOSE_MAX characters that hintFits accepts;
// `floor`, when present, is a version REQUIREMENT_FLOOR accepts, on a
// `command` alone, since a bus name prints none. `install`, when present,
// is REQUIREMENT_ON_REQUEST, on a required entry with `packages` and no
// `floor`: an optional entry's package is an optional dependency already,
// an entry with no package has none to carry, and a floor is checked at
// start, before any Requirements section can install the package.
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
        if (!hintFits(requirement.purpose))
            return at + ".purpose" + HINT_RULE;
        if (requirement.floor !== undefined && requirement.command === undefined)
            return at + ".floor needs a command, whose version the scan reads";
        if (requirement.floor !== undefined && (typeof requirement.floor !== "string" || !REQUIREMENT_FLOOR.test(requirement.floor)))
            return at + ".floor must be a version of three dotted numbers, got " + JSON.stringify(requirement.floor);
        if (requirement.install !== undefined) {
            if (requirement.install !== REQUIREMENT_ON_REQUEST)
                return at + ".install must be " + JSON.stringify(REQUIREMENT_ON_REQUEST) + " when present, got " + JSON.stringify(requirement.install);
            if (requirement.optional === true)
                return at + ".install needs a required entry: an optional one's package is an optional dependency already";
            if (requirement.packages === undefined)
                return at + ".install needs packages, the package the recipes carry on request";
            if (requirement.floor !== undefined)
                return at + ".install cannot stand beside a floor, which is checked before the package can be installed on request";
        }
    }
    return "";
}

// A `requirements` list requirementsError accepted, each entry with every
// key: `name`, `title`, the command or the D-Bus `label` a page lists it
// by, `bus`, `packages` {}, `optional` false, `floor` null and `onRequest`
// false when absent.
function normalRequirements(requirements) {
    return requirements.map(function (entry) {
        return { name: requirementName(entry), title: entry.dbus === undefined ? entry.command : entry.dbus.label, bus: entry.dbus === undefined ? null : entry.dbus.bus, packages: entry.packages === undefined ? {} : clone(entry.packages), optional: entry.optional === true, purpose: entry.purpose, floor: entry.floor === undefined ? null : entry.floor, onRequest: entry.install === REQUIREMENT_ON_REQUEST };
    });
}

// The state, one of REQUIREMENT_STATES, of ENTRY, one normalized
// requirement: "missing" when MISSING, the requirement names the last scan
// did not find, names its identity; "outdated" when it declares a floor and
// VERSIONS, command -> the line its `--version` printed at the last scan,
// holds a version below it; else "present". A command the scan read no
// version of, and a line that holds none, say nothing about the floor, so
// the command stays present: Registry logs each read that failed.
function requirementState(entry, missing, versions) {
    if (missing.indexOf(entry.name) !== -1) return "missing";
    var read = entry.floor !== null && typeof versions[entry.name] === "string" ? VERSION_IN_LINE.exec(versions[entry.name]) : null;
    if (read === null) return "present";
    var floor = entry.floor.split(".");
    for (var i = 0; i < 3; i++) {
        var part = Number(read[i + 1]);
        var least = Number(floor[i]);
        if (part < least) return "outdated";
        if (part > least) break;
    }
    return "present";
}

// The versions `bin/vgshell-scan --versions` answered a scan with, from its
// COMPLETION, { code, status } or null for a run that never started, and
// its STDOUT: { ok: true, versions }, each command it was asked for mapped
// to the line it printed or to null, or { ok: false, line }, the log line
// naming why there is none.
function versionsRead(completion, stdout) {
    if (completion === null)
        return { ok: false, line: "plugins: versions=unstarted" };
    if (completion.status !== 0 || completion.code !== 0)
        return { ok: false, line: "plugins: versions=failed exit=" + completion.code + " status=" + completion.status };
    var read;
    try {
        read = JSON.parse(stdout);
    } catch (e) {
        return { ok: false, line: "plugins: versions=unparseable" };
    }
    if (!isPlainObject(read) || !Object.keys(read).every(function (command) { return read[command] === null || typeof read[command] === "string"; }))
        return { ok: false, line: "plugins: versions=malformed" };
    return { ok: true, versions: read };
}

// The word and badge tone a requirement in STATE draws with, OPTIONAL when
// its owner marks it optional, on its Settings Requirements row and on the
// requirement notice alike, so one tool reads at one urgency in both:
// Present in the success tone, Missing in the danger tone, Optional in the
// info tone for a missing optional one, and Outdated in the warning tone,
// optional or not.
function requirementBadge(state, optional) {
    switch (state) {
    case "present": return { text: "Present", tone: "success" };
    case "missing": return optional ? { text: "Optional", tone: "info" } : { text: "Missing", tone: "danger" };
    case "outdated": return { text: "Outdated", tone: "warning" };
    }
    throw new Error("requirementBadge: no rule for requirement state " + JSON.stringify(state));
}

// The rows a plugin's requirements are reported as: each normalized entry
// of MANIFEST's `requirements`, in order, with `state` as requirementState
// reads it from MISSING and VERSIONS and `badge` as requirementBadge draws
// that state.
function requirementRows(manifest, missing, versions) {
    return manifest.requirements.map(function (entry) {
        var row = clone(entry);
        row.state = requirementState(entry, missing, versions);
        row.badge = requirementBadge(row.state, row.optional);
        return row;
    });
}

// The commands whose version a scan reads, each once and sorted: every
// command with a floor that the core's owner and the ENABLED plugins of
// OWNERS declare and MISSING, owner id -> the names the scan did not find,
// does not hold. A disabled plugin's commands run nowhere, its version
// read included.
function versionCommands(owners, missing, enabled) {
    var out = [];
    Object.keys(owners).forEach(function (id) {
        if (id !== CORE_OWNER && enabled.indexOf(id) === -1) return;
        var lacking = hasOwn(missing, id) ? missing[id] : [];
        owners[id].requirements.forEach(function (entry) {
            if (entry.floor !== null && lacking.indexOf(entry.name) === -1 && out.indexOf(entry.name) === -1) out.push(entry.name);
        });
    });
    return out.sort();
}

// The requirement notice, shell/Core/Notices.qml
// (docs/architecture/commands-are-data.md § Consent). At most NOTICE_QUEUE_MAX plugins hold a notice at once, the
// first shown and the rest waiting. After the user answers a plugin's
// notice Not now, the offers the plugin raises on its own, `suggested`, are
// refused for NOTICE_OFFER_REST_MS; every other trigger is the user's own
// act, which no rest refuses. An offer names 1 to NOTICE_OFFER_MAX
// commands. Core policy, like the notify run ceiling.
var NOTICE_QUEUE_MAX = 8;
var NOTICE_OFFER_REST_MS = 600000;
var NOTICE_OFFER_MAX = 16;
// What raises a notice: `installed`, the pluginInstalled IPC function
// `vgshell plugin add` calls; `enabled`, setPluginEnabled turning a plugin on;
// `offered`, the `requirements` capability's offer, a user's press on the
// plugin's own control, and the notice a plugin's own script request raises
// in place of itself (noticeHeld); `suggested`, the same capability's suggest, an offer
// the plugin raises with no press, the one trigger a rest refuses. The
// capability member a plugin calls is how the core tells the two apart: the
// core sees no press itself. `requested`, the
// `manager` capability's installRequirements, the Settings window's
// Install; `chosen`, a user's press asking for the core's or an enabled
// plugin's requirements: the `doctor` capability, a view of every owner's
// requirements.
var NOTICE_TRIGGERS = ["installed", "enabled", "offered", "suggested", "requested", "chosen"];
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
// owner, whose requirements the last scan read as MISSING and VERSIONS say
// (requirementRows): { answer, commands, required }, `commands` the
// requirement names the notice lists and `required` those that keep it open
// while missing or outdated. `answer` is "ok",
// "satisfied" when `required` is empty and no notice is due, or a refusal.
// The install and enable triggers list every missing requirement and require
// those the plugin does not mark optional, so a plugin lacking only optional
// requirements raises none. Neither lists an outdated one: both judge
// before the version read they start has returned, so a plugin whose only
// lack is an outdated command raises no notice by them, and its page offers
// the update. A request lists and requires every missing or outdated
// requirement, optional ones included, since the user asked to install
// them. An offer, a suggestion and a choice list and require each of COMMANDS still
// missing or outdated, and is refused as
// `refused: requirements=malformed` for anything but a list of 1 to
// NOTICE_OFFER_MAX strings, then as `refused: requirement=<name>
// reason=undeclared` for the first command MANIFEST does not declare, so a
// notice never names a package its owner did not declare.
function noticeRequest(manifest, missing, versions, trigger, commands) {
    var rows = requirementRows(manifest, missing, versions);
    var lacking = rows.filter(function (row) { return row.state !== "present"; });
    var listed;
    var required;
    switch (trigger) {
    case "installed":
    case "enabled":
    case "requested":
        listed = trigger === "requested" ? lacking : lacking.filter(function (row) { return row.state === "missing"; });
        required = trigger === "requested" ? listed : listed.filter(function (row) { return !row.optional; });
        break;
    case "offered":
    case "suggested":
    case "chosen":
        if (!Array.isArray(commands) || commands.length === 0 || commands.length > NOTICE_OFFER_MAX || !commands.every(function (c) { return typeof c === "string"; }))
            return { answer: "refused: requirements=malformed", commands: [], required: [] };
        var declared = rows.map(function (row) { return row.name; });
        var undeclared = commands.filter(function (c) { return declared.indexOf(c) === -1; });
        if (undeclared.length > 0)
            return { answer: "refused: requirement=" + tuiLabel(undeclared[0]) + " reason=undeclared", commands: [], required: [] };
        return noticeListing(rows, commands);
    default:
        throw new Error("notices: trigger " + JSON.stringify(trigger) + " is not one of " + NOTICE_TRIGGERS.join(", "));
    }
    var nameOf = function (row) { return row.name; };
    return { answer: required.length === 0 ? "satisfied" : "ok", commands: listed.map(nameOf), required: required.map(nameOf) };
}

// The notice that lists and requires each of COMMANDS that ROWS,
// requirementRows' answer, read missing or outdated, in declaration order,
// answered as noticeRequest answers.
function noticeListing(rows, commands) {
    var listed = rows.filter(function (row) {
        return row.state !== "present" && commands.indexOf(row.name) !== -1;
    }).map(function (row) { return row.name; });
    return { answer: listed.length === 0 ? "satisfied" : "ok", commands: listed, required: listed.slice() };
}

// The notice a plugin's own script request raises in place of itself
// (Notices.raiseHeld) for COMMANDS, the lacking requirements tuiRunFor or
// tuiOpen answered: listed and required as an offer's, with no offer
// bound. The core names COMMANDS from MANIFEST, not the plugin, and a
// script that declares no `requires` needs every requirement its plugin
// does not mark optional, more than NOTICE_OFFER_MAX for Jarvis.
function noticeHeld(manifest, missing, versions, commands) {
    return noticeListing(requirementRows(manifest, missing, versions), commands);
}

// QUEUE, the notices held, each { id, commands, required }, the first
// shown, after REQUEST, an "ok" noticeRequest for plugin ID raised by
// TRIGGER at NOW, in ms since the epoch: { answer, queue }. A plugin
// holding a notice gets REQUEST's commands merged into it, after those it
// holds, and answers "ok" whatever the trigger, since the user sees one
// notice either way. Otherwise a suggestion while REST, plugin id -> the end
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
    if (trigger === "suggested" && hasOwn(rest, id) && rest[id] > now)
        return { answer: "refused: requirements=" + id + " reason=resting retry-ms=" + (rest[id] - now), queue: queue };
    if (queue.length >= NOTICE_QUEUE_MAX)
        return { answer: "refused: notices=full limit=" + NOTICE_QUEUE_MAX, queue: queue };
    return { answer: "ok", queue: queue.concat([{ id: id, commands: request.commands.slice(), required: request.required.slice() }]) };
}

// What NOTICE, { commands, required }, shows for plugin MANIFEST after the
// last scan, which read its requirements as MISSING and VERSIONS say, on a
// system whose managers are FOUND, detect's answer, or null when detection
// has no answer: { satisfied, rows, drawn, run, byHand }.
// `satisfied` holds once no requirement of `required` is missing or
// outdated. `rows` are the listed requirements still missing or outdated,
// in declaration order, each { name, purpose, optional, state, package },
// the package PackageManagers.installGroups picks, null with FOUND null or
// when no present manager maps one. `run` is the step one press runs, or
// null when no manager here installs a listed package: { manager, action,
// args, installs, updates }, one manager's packages, `updates` those noticeGroups
// marks `update` and `installs` its others. The manager is the first of
// installGroups' that installs and holds an update, else the first that
// installs, so an outdated command never waits on the installs of optional
// ones. `action` is `install`, with PackageManagers.installArgs' arguments
// after `vgshell pkg run install`, when `updates` is empty; else `update`,
// with those arguments over `updates` after `vgshell pkg run update`, then
// `--install` and `installs` when both are owed. `drawn` is every entry
// the notice draws, each a noticeGroups entry with `later`: first the
// entries `run` handles, every one when it is null, `later` false; then
// the entries the presses after this one offer, once a rescan finds these
// installed or updated, `later` true, in the order those presses take
// their managers: the other managers that install, the ones holding an
// update first, then installGroups' order, as `run` picks its own.
// noticeSettle closes the notice once `required` is found, and a closed
// notice offers nothing, so the later entries stop at the last of those
// managers that holds a lacking requirement of `required`, and there are
// none when no such manager does. A lacking requirement of `required` that
// no manager here installs keeps the notice open past every press, so then
// they hold every other manager that installs. An entry `drawn` does not
// hold is neither drawn nor promised.
// `byHand` is each group whose manager installs nothing through vgshell,
// nix, as { manager, names }.
function noticeView(manifest, missing, versions, notice, found) {
    var lacking = requirementRows(manifest, missing, versions).filter(function (row) { return row.state !== "present"; });
    var rows = lacking.filter(function (row) { return notice.commands.indexOf(row.name) !== -1; });
    var satisfied = !notice.required.some(function (c) { return lacking.some(function (row) { return row.name === c; }); });
    var plan = found === null ? { picks: rows.map(function () { return null; }), groups: [] } : PackageManagers.installGroups(rows, found);
    var shown = rows.map(function (row, i) { return { name: row.name, purpose: row.purpose, optional: row.optional, state: row.state, package: plan.picks[i] }; });
    var entries = noticeGroups(shown);
    var updatesOf = function (group) {
        return group.names.filter(function (name) { return entries.some(function (e) { return e.manager === group.manager && e.chip === name && e.update; }); });
    };
    var runs = plan.groups.filter(function (g) { return g.installs; });
    var order = runs.filter(function (g) { return updatesOf(g).length > 0; }).concat(runs.filter(function (g) { return updatesOf(g).length === 0; }));
    var pressed = order[0];
    var run = null;
    if (pressed !== undefined) {
        var updates = updatesOf(pressed);
        var installs = pressed.names.filter(function (name) { return updates.indexOf(name) === -1; });
        run = updates.length === 0
            ? { manager: pressed.manager, action: "install", args: PackageManagers.installArgs(pressed), installs: installs, updates: updates }
            : { manager: pressed.manager, action: "update", args: PackageManagers.installArgs(Object.assign({}, pressed, { names: updates })).concat(installs.length === 0 ? [] : ["--install"].concat(installs)), installs: installs, updates: updates };
    }
    var handled = run === null ? entries : entries.filter(function (e) { return e.manager === pressed.manager; });
    var owed = shown.filter(function (row) { return notice.required.indexOf(row.name) !== -1; });
    var unreached = owed.some(function (row) { return row.package === null || !runs.some(function (g) { return g.manager === row.package.manager; }); });
    var next = order.slice(1);
    var reach = 0;
    next.forEach(function (g, i) {
        if (owed.some(function (row) { return row.package !== null && row.package.manager === g.manager; })) reach = i + 1;
    });
    var reached = next.slice(0, unreached ? next.length : reach).map(function (g) { return g.manager; });
    var waiting = reached.reduce(function (held, manager) { return held.concat(entries.filter(function (e) { return e.manager === manager; })); }, []);
    return {
        satisfied: satisfied,
        rows: shown,
        drawn: handled.map(function (e) { return Object.assign({}, e, { later: false }); }).concat(waiting.map(function (e) { return Object.assign({}, e, { later: true }); })),
        run: run,
        byHand: plan.groups.filter(function (g) { return !g.installs; }).map(function (g) { return { manager: g.manager, names: g.names }; })
    };
}

// The title of OWNER's notice over VIEW, noticeView's answer: "<OWNER>
// needs one package" or "<OWNER> needs N packages", counting the entries
// VIEW draws whose chip reads Missing or Outdated, so the count is the
// number of needed entries the user sees and a missing optional package,
// drawn Optional, is never called needed; "<OWNER> can use N packages"
// when every entry reads Optional; requirements when no counted entry has
// a package, and updates when every counted entry is one.
function noticeTitle(owner, view) {
    var needed = view.drawn.filter(function (e) { return e.update || !e.optional; });
    var counted = needed.length === 0 ? view.drawn : needed;
    var noun = counted.every(function (e) { return e.update; }) ? "update" : counted.some(function (e) { return e.packaged; }) ? "package" : "requirement";
    return owner + (needed.length === 0 ? " can use " : " needs ") + (counted.length === 1 ? "one " + noun : counted.length + " " + noun + "s");
}

// ROWS, noticeView's, as the user installs them: one entry per package,
// keyed by its manager and name, or per requirement when no package is
// known, keyed by the requirement's name, in first-appearance order, each
// { chip, packaged, manager, update, optional, purposes, badge }, `manager`
// the package's or null, `update` while every requirement of the entry is
// outdated, so its step is an update, `optional` while every one is
// optional, and `badge` the state requirementBadge draws beside the chip:
// Outdated for an update, else Missing or Optional. Two requirements one
// package provides
// read as one thing to install, and a package is never merged with a
// requirement of its name.
function noticeGroups(rows) {
    var out = [];
    rows.forEach(function (row) {
        var packaged = row.package !== null;
        var chip = packaged ? row.package.name : row.name;
        var manager = packaged ? row.package.manager : null;
        var update = row.state === "outdated";
        var held = out.filter(function (g) { return g.manager === manager && g.chip === chip; })[0];
        if (held === undefined) out.push({ chip: chip, packaged: packaged, manager: manager, update: update, optional: row.optional, purposes: [row.purpose] });
        else {
            held.update = held.update && update;
            held.optional = held.optional && row.optional;
            held.purposes.push(row.purpose);
        }
    });
    return out.map(function (g) { return Object.assign(g, { badge: requirementBadge(g.update ? "outdated" : "missing", g.optional) }); });
}

// What a run of RAN left as it was, or null when it left nothing: RAN is
// noticeView's `run` of the press on NOTICE that ran to code 0, and the
// other arguments are noticeView's, read once the version read after the
// run returned. Each package of the press is judged alone, since one run
// can install one and leave another: a package manager with nothing newer
// ends an update with code 0, and so does one that installs a copy behind
// the one PATH finds first. The answer is { kind: "unchanged", left },
// `left` every package of RAN's manager that RAN's `updates` still leave
// outdated or its `installs` still leave missing, once each by its package
// name, the name its chip draws, in the order its first listed requirement
// is declared: { kind: "missing", name, optional }, `optional` while every
// requirement the package provides is optional, or { kind: "outdated",
// name, version, floor }, `version` the three numbers the command of that
// first requirement printed and `floor` the one its owner needs. A package the
// press installed below its floor changed, and is not named.
function noticeUnchanged(manifest, missing, versions, notice, found, ran) {
    var judged = function (names, state) {
        return function (r) { return r.state === state && names.indexOf(r.package.name) !== -1; };
    };
    var stillOutdated = judged(ran.updates, "outdated");
    var stillMissing = judged(ran.installs, "missing");
    var owed = noticeView(manifest, missing, versions, notice, found).rows.filter(function (r) { return r.package !== null && r.package.manager === ran.manager && (stillOutdated(r) || stillMissing(r)); });
    var left = owed.filter(function (row, i) { return !owed.slice(0, i).some(function (r) { return r.package.name === row.package.name; }); }).map(function (row) {
        var named = { kind: row.state, name: row.package.name };
        if (row.state === "missing") return Object.assign(named, { optional: owed.every(function (r) { return r.package.name !== row.package.name || r.optional; }) });
        var floor = manifest.requirements.filter(function (entry) { return entry.name === row.name; })[0].floor;
        return Object.assign(named, { version: VERSION_IN_LINE.exec(versions[row.name]).slice(1, 4).join("."), floor: floor });
    });
    return left.length === 0 ? null : { kind: "unchanged", left: left };
}

// QUEUE after a scan, the notices of OWNERS, the core's owner and each
// plugin's manifest by id, whose missing requirements MISSING, owner id ->
// requirement names, now holds, beside the VERSIONS it read: a notice whose owner went is dropped, and so is one noticeView finds satisfied, except the
// notice of INSTALLING, the plugin id whose install runs or "". That notice
// stays until the scan after its run ended, however the run's own steps
// asked for a rescan first, so no waiting notice comes to the front while
// its terminal still holds the install's key.
function noticeSettle(queue, owners, missing, versions, installing) {
    return queue.filter(function (n) {
        if (!hasOwn(owners, n.id))
            return false;
        if (n.id === installing)
            return true;
        return !noticeView(owners[n.id], hasOwn(missing, n.id) ? missing[n.id] : [], versions, n, null).satisfied;
    });
}

// The managers `bin/vgshell-pkg detect --json` answered the notice with, from
// its COMPLETION, { code, status } or null for a run that never started,
// its STDOUT and its STDERR: { ok: true, found }, detect's { primary,
// overlays, sources, holders? } with each entry a known manager and
// holders, when present, a command-to-owner map, or { ok: false,
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
    var knownOwner = function (owners, key) {
        return PackageManagers.managerRow(key) !== null && (owners[key] === null || typeof owners[key] === "string");
    };
    var holder = function (h) {
        return isPlainObject(h) && (h.path === null || typeof h.path === "string") && isPlainObject(h.owners)
            && (h.path !== null || Object.keys(h.owners).length === 0)
            && Object.keys(h.owners).every(function (key) { return knownOwner(h.owners, key); });
    };
    var holders = found !== null && found !== undefined && found.holders !== undefined ? found.holders : {};
    if (!isPlainObject(found) || !(found.primary === null || entry(found.primary)) || !Array.isArray(found.overlays) || !found.overlays.every(entry) || !Array.isArray(found.sources) || !found.sources.every(entry) || !isPlainObject(holders) || !Object.keys(holders).every(function (command) { return PackageManagers.validCommand(command) && holder(holders[command]); }))
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

// KEY, a key as ConfigLogic.hyprlandKey writes it, as people read it: each modifier and
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
// ConfigLogic.NAME_PATTERN name: the script, the window's title, its size class and
// presentation, and, when present, the row shell.tui.entries lists it with.
// `script` is a path under the plugin's `tui/` directory, the one
// bin/vgshell-tui copies out of the published snapshot and runs from; each
// segment starts with a letter, a digit or `_`, so none is `.`, `..` or
// hidden. The sizes are the size classes of HyprlandLayer.TUI_WINDOWS, the
// table the layer's window rules and the launcher's app-ids come from, and
// the presentations are bin/vgshell-tui's. A title, a label and a group are one
// printable line of at most TUI_TEXT_MAX characters. `settings` marks a
// configuration screen, the bottom More settings link of Settings.
var TUI_KEYS = ["script", "title", "size", "presentation", "entry", "requires"];
var TUI_ENTRY_KEYS = ["label", "icon", "group", "settings"];
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
// `edit`, `requirements-install`, `requirements-update`, `dictation-setup`, `system`,
// `plugin-update`, `plugin-remove` and `sudo-revoke` are not listed. The
// first opens a cited file from a surface, the requirement notice opens the
// install and update rows with
// the arguments PluginLogic.noticeView names, the `manager` capability's
// act opens `system` with `apply <step>` for a status action that names a
// system step (D081) or `dictation-setup` for a holder of `dictation`,
// the plugin manager opens update and remove with one
// plugin id (MANAGER_TUIS), and the `sudo` capability opens `sudo-grant`
// with a duration and `sudo-revoke`, which asks nothing while a grant is
// active, so its terminal closes by itself. A plugin update shows its
// incoming diff, so it opens wide.
var CORE_TUIS = coreTuiTable({
    "dictation-setup": {
        argv: ["vgshell", "dictation", "setup"],
        title: "Set up dictation",
        size: "default",
        presentation: "full",
        entry: null
    },
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
    "requirements-update": {
        argv: ["vgshell", "pkg", "run", "update"],
        title: "Update requirements",
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
    },
    "sudo-revoke": {
        argv: ["vgshell", "sudo", "revoke"],
        title: "Passwordless sudo",
        size: "default",
        presentation: "plain",
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

// The launch key of plugin ID's own TUI NAME, `<plugin id>/<name>`, whatever
// its arguments, so one run of a script is live at a time.
function tuiOwnKey(id, name) {
    return id + "/" + name;
}

// Whether two argument lists of a TUI request are the same, an absent list
// being none.
function tuiArgsSame(a, b) {
    return JSON.stringify(a === undefined ? [] : a) === JSON.stringify(b === undefined ? [] : b);
}

// What a request for launch KEY with ARGS answers, ANSWER being start's and
// LABEL the name its refusals carry: tuiShownAnswer's, but for a busy key
// whose live run the shell started with other arguments, which answers
// `refused: tui=<label> reason=busy-other` while the runner still shows
// that run's window, so a press on one row's action, or a link to one
// file, never answers with another row's or file's window. A plugin
// script's request no instance made and every editor request take it,
// since their arguments name what they open. STARTED maps each key to the
// arguments of the latest run the shell started for it; a key it lacks, a
// run that outlived an earlier shell, counts as a run with none.
function tuiArgsShownAnswer(key, label, answer, args, started) {
    if (answer !== tuiRefusal(label, "busy").answer) return answer;
    return tuiArgsSame(hasOwn(started, key) ? started[key] : [], args) ? "ok" : tuiRefusal(label, "busy-other").answer;
}

// Why HELD, a request for a plugin's own script made while a command it
// needs is missing, may not take the place of BEFORE, the request that
// plugin's notice holds, null for none: `refused: tui=<name>
// reason=busy-other` while BEFORE is a request for the same script with
// other arguments, so a press on a second row never drops the first row's
// request in silence; "" otherwise.
function tuiHeldRefusal(before, held) {
    return before !== null && before.name === held.name && !tuiArgsSame(before.args, held.args) ? tuiRefusal(held.name, "busy-other").answer : "";
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
// one script, each named by ConfigLogic.NAME_PATTERN and holding only TUI_KEYS; `script`
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
        if (!ConfigLogic.NAME_PATTERN.test(name))
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
// TUI_ENTRY_KEYS holding a tuiText `label` and `group`, an `icon` of the
// shipped set and, when present, a boolean `setup`.
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
    if (entry.settings !== undefined && typeof entry.settings !== "boolean")
        return at + ".entry.settings must be a boolean when present";
    return "";
}

// The first defect of the core's own TUI NAME, ROW, or "": NAME matches
// ConfigLogic.NAME_PATTERN; ROW holds every key of CORE_TUI_KEYS and no other; `argv`
// is a CORE_TUI_COMMAND followed by arguments tuiArgsValid accepts; the
// window passes tuiWindowError with a `size` and `presentation` set; and
// `entry` is null or passes tuiEntryError.
function coreTuiError(name, row) {
    var at = "core/" + name;
    if (!ConfigLogic.NAME_PATTERN.test(name))
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

// The control characters `vgshell edit` refuses in a path, U+0000 to
// U+001F and U+007F, the CLI's own list (bin/vgshell edit_controls).
var EDIT_CONTROL = /[\u0000-\u001f\u007f]/;

// The arguments for the core file editor, judged as `vgshell edit` judges
// them, which judges them again before it opens anything: PATH is absolute
// or relative to the user's configuration directory, holds no control
// character, which the refusal never echoes, since a newline in it could
// forge a line of the answer, and no `..` segment; LINE, when present, is
// a positive integer.
function editArgs(path, line) {
    if (typeof path !== "string" || path.length === 0)
        return { ok: false, answer: "refused: edit=path reason=empty" };
    if (EDIT_CONTROL.test(path))
        return { ok: false, answer: "refused: edit=path reason=control" };
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

// How the core opens PATH, a cited file or folder, at LINE: a leading
// `~/` is the home folder HOME, then editArgs judges the path. A path that
// ends in `/` names a folder, which opens in the default file manager,
// { ok: true, kind: "folder", path }, PATH made absolute under
// CONFIG_HOME, the configuration directory, when it is relative, and
// takes no line (`line=<line> reason=folder`); any other path opens in
// the core editor TUI, { ok: true, kind: "file", args }, editArgs' args.
// The shell cannot read whether a path is a folder, so the `/` says it:
// the editor refuses a folder it is handed (`vgshell edit`), and the core
// opens a folder path only once `test -d` finds a folder there
// (TuiRunner.openFolder).
function editRoute(path, line, home, configHome) {
    if (typeof home !== "string" || home.charAt(0) !== "/")
        throw new Error("editRoute: home " + JSON.stringify(home) + " is not an absolute path");
    var expanded = typeof path === "string" && path.indexOf("~/") === 0 ? home + path.slice(1) : path;
    var judged = editArgs(expanded, line);
    if (!judged.ok)
        return judged;
    if (expanded.charAt(expanded.length - 1) !== "/")
        return { ok: true, kind: "file", args: judged.args };
    if (judged.args.length > 1)
        return { ok: false, answer: "refused: line=" + judged.args[1] + " reason=folder" };
    return { ok: true, kind: "folder", path: expanded.charAt(0) === "/" ? expanded : configHome + "/" + expanded };
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
    var key = tuiOwnKey(manifest.id, name);
    var refusal = tuiRunnerRefusal(runner, name, key);
    if (refusal !== null)
        return refusal;
    var row = manifest.tui[name];
    var plugin = { id: manifest.id, dir: sourceDir + "/" + manifest.__revision };
    return { ok: true, key: key, run: runner.run, argv: tuiArgv(row, plugin, key, runner.run, [row.script].concat(args === undefined ? [] : args)) };
}

// The launch key and refusal label of core TUI NAME run for OWNER, a
// plugin id, or for the core while OWNER is undefined: `core/<name>` named
// so, or the plugin's own `<plugin id>/<name>` named `<name>`, as tuiCore
// keys and refuses it.
function tuiCoreNamed(name, owner) {
    if (owner === undefined) return { key: "core/" + name, label: "core/" + name };
    return { key: tuiOwnKey(owner, name), label: name };
}

// The core's own TUI NAME of CORE, the CORE_TUIS table, listed or not,
// with ARGS after its argv, its command resolved under CORE_BIN, the core's
// bin/ directory, for RUNNER: answers as tuiRun, keyed `core/<name>`, with
// `reason=undeclared` for a name CORE lacks, `reason=args` for arguments
// tuiArgsValid refuses, then `reason=busy` or `reason=launcher-missing` as
// tuiRunnerRefusal decides. The core alone calls it; tuiOpen opens a
// listed row with no arguments through it. With OWNER, a plugin id, the
// run is that plugin's, keyed `<plugin id>/<name>` and named `<name>` in
// its refusals, as its own script's run is, so the plugin reads its end in
// its `shell.tui.state` (tuiStateNames): the core editor a plugin's file
// action opens (STATUS_FILE_TUI).
function tuiCore(core, coreBin, runner, name, args, owner) {
    var named = tuiCoreNamed(name, owner);
    var key = named.key;
    var label = named.label;
    if (typeof name !== "string" || !hasOwn(core, name))
        return tuiRefusal(label, "undeclared");
    if (!tuiArgsValid(args))
        return tuiRefusal(label, "args");
    var refusal = tuiRunnerRefusal(runner, label, key);
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
// { ok: true, kind: "install", id, name, commands } in their place, as
// tuiRunFor does, so every route that opens a listed script raises the same
// notice.
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
    var lacking = tuiMissingRequirements(manifests[owner], name, hasOwn(missing, owner) ? missing[owner] : []);
    if (lacking.length > 0)
        return { ok: true, kind: "install", id: owner, name: name, commands: lacking };
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

// The listed screens of plugin MANIFEST, for its manager row: each `tui`
// script with an `entry`, in manifest order, as { name, label, icon, settings }.
// The bottom Settings link owns configuration screens.
function listedTuis(manifest) {
    return Object.keys(manifest.tui).filter(function (name) { return manifest.tui[name].entry !== null; }).map(function (name) {
        return { name: name, label: manifest.tui[name].entry.label, icon: manifest.tui[name].entry.icon, settings: manifest.tui[name].entry.settings === true };
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
    return (owner === "core" || ID_PATTERN.test(owner)) && ConfigLogic.NAME_PATTERN.test(key.slice(slash + 1));
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

// The names a plugin's `shell.tui.state` holds for MANIFEST: each script
// of its `tui` key, and STATUS_FILE_TUI while a status entry declares a
// file action, whose core editor runs as the plugin's (tuiCore).
function tuiStateNames(manifest) {
    var names = Object.keys(isPlainObject(manifest.tui) ? manifest.tui : {});
    var status = isPlainObject(manifest.status) ? manifest.status : {};
    var files = Object.keys(status).some(function (key) {
        return statusEntryActions(status[key]).some(function (declared) { return declared.action.file !== undefined; });
    });
    return files ? names.concat([STATUS_FILE_TUI]) : names;
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

// SCREENS is Quickshell.screens, a QML list: it has length and indexes, but
// Array.isArray answers false for it (a run's Wayland trace on 2026-10-08
// showed every cover asking for no keyboard under that test).
function perScreenLayerTakesKeyboard(kind, screens, screen) {
    return kind === "cover" && screens.length > 0 && screen !== null && screens[0].name === screen.name;
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
            if (typeof item.shortcut !== "string" || !ConfigLogic.NAME_PATTERN.test(item.shortcut))
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
        var settings = settingsFor(config, manifest);
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

// The first defect of a manifest's `capabilityKinds`, or "". It maps a
// capability `capabilities` lists to the kinds whose instances hold it,
// for a capability only some kinds read; a capability it leaves out is
// held by every kind (instanceCapabilities). A list names each kind once,
// only declared kinds, and never all of them, which is leaving it out.
// The panes capability stays with the window, the kind that mounts panes.
function capabilityKindsError(capabilityKinds, capabilities, kinds) {
    if (!isPlainObject(capabilityKinds))
        return "capabilityKinds must be an object";
    var names = Object.keys(capabilityKinds);
    for (var n = 0; n < names.length; n++) {
        var name = names[n];
        var at = "capabilityKinds." + name;
        if (capabilities.indexOf(name) === -1)
            return at + " names a capability capabilities does not list";
        var held = capabilityKinds[name];
        if (!Array.isArray(held) || held.length === 0)
            return at + " must be a non-empty list of kinds";
        for (var k = 0; k < held.length; k++) {
            if (kinds.indexOf(held[k]) === -1)
                return at + " names " + JSON.stringify(held[k]) + ", a kind the manifest does not declare";
            if (held.indexOf(held[k]) !== k)
                return at + " lists kind " + held[k] + " twice";
        }
        if (held.length === kinds.length)
            return at + " lists every kind; leave it out";
        if (name === "panes" && held.indexOf("window") === -1)
            return at + " must list kind window";
    }
    return "";
}

// The capabilities an instance of KIND holds: the manifest's
// `capabilities`, less each one `capabilityKinds` gives only other kinds.
// Capabilities.providersFor builds exactly these.
function instanceCapabilities(manifest, kind) {
    return manifest.capabilities.filter(function (name) {
        return !hasOwn(manifest.capabilityKinds, name) || manifest.capabilityKinds[name].indexOf(kind) !== -1;
    });
}

// The rename map of a scan, MANIFESTS being its id to manifest map in
// scan order and SOURCE_OF naming where a manifest was found, `bundled` or
// `installed` as Registry.sourceOf names it. Returns { renames, ignored }:
// RENAMES maps each former id a bundled manifest declares in `formerIds` to
// that manifest's id, and IGNORED holds one { id, reason, formerIds } entry
// for each claim the map leaves out, by reason:
// - `installed`: an installed manifest's formerIds rename nothing, one entry
//   per manifest, since the opt-in a user gives at `plugin add` judges the
//   plugin's own id and a claim would carry a removed plugin's row onto it;
// - `scanned`: a claim of a former id that a scanned plugin holds, since the
//   user file's row, disable and placement under that id are that plugin's;
// - `claimed`: a later claim in scan order of a former id already mapped.
// A left-out claim does not refuse its manifest. bin/lib/check-manifests.js
// holds the shipped manifests to one claimant per former id and no former
// id that a shipped plugin holds. Registry logs IGNORED and hands RENAMES
// to Config.adoptRenames, which renames the user file by it
// (ConfigLogic.renamePlugins).
function formerIdClaims(manifests, sourceOf) {
    var renames = {}, ignored = [];
    Object.keys(manifests).forEach(function (id) {
        var formerIds = manifests[id].formerIds;
        if (!Array.isArray(formerIds)) return;
        if (sourceOf(manifests[id]) !== "bundled") {
            ignored.push({ id: id, reason: "installed", formerIds: formerIds.slice() });
            return;
        }
        formerIds.forEach(function (former) {
            if (hasOwn(manifests, former))
                ignored.push({ id: id, reason: "scanned", formerIds: [former] });
            else if (hasOwn(renames, former))
                ignored.push({ id: id, reason: "claimed", formerIds: [former] });
            else
                renames[former] = id;
        });
    });
    return { renames: renames, ignored: ignored };
}

// Validate one manifest object. Returns { ok: true, manifest } with the
// normalized manifest, or { ok: false, error } naming the first defect.
// `sourceDir` is recorded on the manifest so entry points resolve later.
// A normalized manifest always carries `capabilities` and `requirements`
// (arrays, the latter's entries normalRequirements' shape),
// `capabilityKinds` (an object, {} when undeclared), `settings`,
// `schema`, `status`, `sounds` and `tui` (objects, `tui` normalTui's shape),
// `menu` (an object, {} when undeclared), `fieldRows` (fieldRows'),
// `defaultSection` only when declared, and
// `hyprland` only when declared, as { binds, layerRules, appearance,
// options } with every bind's key normalised by ConfigLogic.hyprlandKey.
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
    // The ids the plugin shipped under before, each a converter step a
    // user file is renamed by (formerIdClaims, ConfigLogic.renamePlugins).
    if (raw.formerIds !== undefined) {
        if (!Array.isArray(raw.formerIds) || raw.formerIds.length === 0)
            return { ok: false, error: "formerIds must be a non-empty list of plugin ids" };
        for (var f = 0; f < raw.formerIds.length; f++) {
            var former = raw.formerIds[f];
            if (typeof former !== "string" || !ID_PATTERN.test(former))
                return { ok: false, error: "formerIds." + f + " must be dotted and author-namespaced, got " + JSON.stringify(former) };
            if (former === raw.id)
                return { ok: false, error: "formerIds." + f + " is the plugin's own id" };
            if (raw.formerIds.indexOf(former) !== f)
                return { ok: false, error: "formerIds lists " + former + " twice" };
        }
    }
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
    var capabilityKinds = raw.capabilityKinds === undefined ? {} : raw.capabilityKinds;
    var badCapabilityKinds = capabilityKindsError(capabilityKinds, capabilities, raw.kinds);
    if (badCapabilityKinds !== "")
        return { ok: false, error: badCapabilityKinds };
    var settings = raw.settings === undefined ? {} : raw.settings;
    if (!isPlainObject(settings))
        return { ok: false, error: "settings must be an object" };
    if (hasOwn(settings, "id"))
        return { ok: false, error: "settings must not carry an id key" };
    if (hasOwn(settings, "keys"))
        return { ok: false, error: "settings must not carry a keys key: a plugins row's keys are its Hyprland keys" };
    if (hasOwn(settings, "placement") && PLACEMENTS.indexOf(settings.placement) === -1)
        return { ok: false, error: "settings.placement must be one of " + PLACEMENTS.join(", ") + ", got " + JSON.stringify(settings.placement) };
    // The requirements first: a TUI's `requires` names them.
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
        var badStatus = statusError(raw.status, capabilities, raw.tui, raw.systemSteps);
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
        if (ConfigLogic.SECTIONS.indexOf(raw.defaultSection) === -1)
            return { ok: false, error: "defaultSection must be one of " + ConfigLogic.SECTIONS.join(", ") + ", got " + JSON.stringify(raw.defaultSection) };
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
    if (raw.sounds !== undefined) {
        var badSounds = soundsError(raw.sounds, capabilities);
        if (badSounds !== "")
            return { ok: false, error: badSounds };
    } else if (capabilities.indexOf("sounds") !== -1) {
        return { ok: false, error: "capability sounds needs a sounds declaration" };
    }
    var badPlacement = pagePlacementError(raw.status || {}, schema, raw.secrets !== undefined);
    if (badPlacement !== "") return { ok: false, error: badPlacement };
    var manifest = clone(raw);
    manifest.capabilities = capabilities.slice();
    manifest.capabilityKinds = clone(capabilityKinds);
    manifest.requirements = normalRequirements(requirements);
    manifest.tui = normalTui(raw.tui === undefined ? {} : raw.tui);
    manifest.menu = raw.menu === undefined ? {} : clone(raw.menu);
    manifest.settings = clone(settings);
    manifest.schema = clone(schema);
    manifest.status = raw.status === undefined ? {} : clone(raw.status);
    manifest.sounds = raw.sounds === undefined ? {} : clone(raw.sounds);
    if (raw.pane !== undefined) manifest.pane = clone(raw.pane);
    manifest.systemSteps = raw.systemSteps === undefined ? [] : raw.systemSteps.slice();
    manifest.fieldRows = fieldRows(manifest.schema, manifest.status);
    var badRows = pageRowsError(manifest.fieldRows, manifest.schema, manifest.status, manifest.tui);
    if (badRows !== "") return { ok: false, error: badRows };
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

// The layout entries of one section, in order; [] when the section or the
// layout is absent. Both files passed ConfigLogic.configError, so every entry is an
// object with a string id.
function sectionEntries(config, section) {
    var layout = config && config.bar && isPlainObject(config.bar.layout) ? config.bar.layout : {};
    return Array.isArray(layout[section]) ? layout[section] : [];
}

// Ids placed in the bar layout, in section order.
function layoutIds(config) {
    var ids = [];
    ConfigLogic.SECTIONS.forEach(function (section) {
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

// The position of LOCATOR, `{ section, nth }`, for plugin ID in CONFIG, or
// null. `nth` counts entries with ID in one section, the same locator
// withMoved receives from a mounted widget's drag.
function layoutPositionOf(config, id, locator) {
    if (isPlainObject(locator) && ConfigLogic.SECTIONS.indexOf(locator.section) !== -1 && Number.isInteger(locator.nth) && locator.nth >= 0) {
        var seen = 0;
        var entries = sectionEntries(config, locator.section);
        for (var i = 0; i < entries.length; i++) {
            if (entries[i].id !== id) continue;
            if (seen === locator.nth) return { section: locator.section, index: i, nth: locator.nth, entry: entries[i] };
            seen += 1;
        }
        return null;
    }
    for (var s = 0; s < ConfigLogic.SECTIONS.length; s++) {
        var section = ConfigLogic.SECTIONS[s];
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

// The settings every instance of plugin MANIFEST receives, whatever its
// kind, and the plugin manager shows: its manifest's `settings` under its
// plugins[] row in CONFIG, the one place a plugin's settings live. Keys the
// row sets win, but for the keys ENTRY_RESERVED_KEYS names, which are no
// setting. The result holds only declared settings and is a fresh object.
function settingsFor(config, manifest) {
    var out = {};
    Object.keys(manifest.settings).forEach(function (k) { out[k] = manifest.settings[k]; });
    return copyEntrySettings(clone(out), pluginRow(config, manifest.id), manifest, false);
}

// Copy declared settings without reading undeclared values. Stored entries
// also keep their reserved keys; runtime settings exclude them. Values are
// copied so TARGET and ENTRY share nothing.
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
// appearance, and its row's names all unknown. CONFIG passed ConfigLogic.configError, so
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
            var key = ConfigLogic.hyprlandKey(value);
            if (!key.ok)
                throw new Error("hyprlandSection: key of " + manifest.id + ":" + bind.shortcut + " passed its judge but " + key.error);
            var result = Object.assign({}, bind, { key: key.key });
            if (bind.tap === true && ConfigLogic.keyHasModifiers(key.key))
                result.error = "tap key must be a lone key with no modifiers";
            binds.push(result);
        });
    });
    var names = declared.binds.map(function (bind) { return bind.shortcut; });
    var settings = settingsFor(config, manifest);
    var appearance = {};
    Object.keys(declared.appearance || {}).forEach(function (group) {
        var setting = declared.appearance[group];
        appearance[group] = { setting: setting, enabled: settings[setting] === true };
    });
    var pads = Pads.expand(declared.pads, manifest.schema, settings, keys, ConfigLogic.hyprlandKey, settingError);
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
        unknownKeys: Object.keys(keys).filter(function (name) { return names.indexOf(name) === -1 && !Pads.isPadShortcut(declared, name, ConfigLogic.NAME_PATTERN); }).sort()
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

// The family of registration NAME, `<family>-<n>` with FAMILY one of
// FAMILIES and n a positive integer, or "" for any other name. A bar draws
// one builtin per placed member, such as one gap per gap entry.
function builtinFamilyOf(name, families) {
    var match = /^([a-z][a-z0-9]*)-([1-9][0-9]*)$/.exec(name);
    return match !== null && Array.isArray(families) && families.indexOf(match[1]) !== -1 ? match[1] : "";
}

// The member names of FAMILIES under bar BARID that CONFIG's layout places,
// each once, in section order. With a bar's fixed names they make the
// catalogue builtinOwner reads.
function placedFamilyNames(config, barId, families) {
    var prefix = barId + "/";
    var out = [];
    layoutIds(config).forEach(function (id) {
        var name = id.slice(0, prefix.length) === prefix ? id.slice(prefix.length) : "";
        if (builtinFamilyOf(name, families) !== "" && out.indexOf(name) === -1) out.push(name);
    });
    return out;
}

// The member of FAMILY under bar BARID that CONFIG places nowhere: one past
// the highest placed number, so a removed member's name is not reused while
// a later one stands.
function nextFamilyName(config, barId, family) {
    var highest = 0;
    placedFamilyNames(config, barId, [family]).forEach(function (name) {
        highest = Math.max(highest, Number(name.slice(family.length + 1)));
    });
    return family + "-" + (highest + 1);
}

// One section order for enabled plugin widgets and advertised builtins.
// A registration has one object, so only its first placement is drawn.
function effectiveLayout(config, manifests, defaultBarId, builtinNames) {
    var out = {};
    var seenBuiltins = [];
    ConfigLogic.SECTIONS.forEach(function (section) {
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
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
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
// entry, `{ id }`, at the end of its default section, `center` when the
// manifest names none. The one placement rule; enabling and placing both
// call it.
// Builtins restore their shipped section beside a remaining declared
// neighbour, or at the declared index when those neighbours are absent.
function placeWidget(out, manifest, effective, id, shipped) {
    id = id === undefined ? manifest.id : id;
    seedUserBar(out, effective);
    if (!isPlainObject(out.bar.layout)) out.bar.layout = { left: [], center: [], right: [] };
    var declared = id === manifest.id || shipped === undefined ? null : layoutPositionOf(shipped, id, null);
    var section = declared !== null ? declared.section : typeof manifest.defaultSection === "string" ? manifest.defaultSection : "center";
    if (!Array.isArray(out.bar.layout[section])) out.bar.layout[section] = [];
    var entries = out.bar.layout[section];
    var at = entries.length;
    if (declared !== null) {
        var defaults = sectionEntries(shipped, section);
        at = Math.min(declared.index, entries.length);
        for (var next = declared.index + 1; next < defaults.length; ++next) {
            var following = entries.findIndex(function (entry) { return entry.id === defaults[next].id; });
            if (following !== -1) { at = following; break; }
        }
        if (next === defaults.length) {
            for (var previous = declared.index - 1; previous >= 0; --previous) {
                var preceding = entries.findIndex(function (entry) { return entry.id === defaults[previous].id; });
                if (preceding !== -1) { at = preceding + 1; break; }
            }
        }
    }
    entries.splice(at, 0, { id: id });
}

// Why MANIFEST's ordinary widget ID may not be placed or unplaced under CONFIG,
// or "": a plugin without kind bar-widget has no widget, and a disabled
// plugin is refused, as its setting is. The reply is one keyed line.
function placedRefusal(config, manifest, defaultBarId, builtinNames, id) {
    id = id === undefined ? manifest.id : id;
    var builtin = builtinOwner(config, { [manifest.id]: manifest }, defaultBarId, builtinNames, id) !== null;
    if (!builtin && manifest.kinds.indexOf("bar-widget") === -1)
        return "refused: placed=" + id + " reason=no-bar-widget";
    if (!isEnabled(config, manifest, defaultBarId))
        return "refused: placed=" + id + " reason=disabled";
    return "";
}

// Why plugin MANIFEST's widget may not be moved under CONFIG to SECTION at
// INDEX, or "". Moving keeps the existing layout entry, so it needs a
// placed and enabled widget. SECTION and INDEX are the persisted
// layout address, not pixel geometry.
function moveRefusal(config, manifest, section, index, defaultBarId, builtinNames, id) {
    id = id === undefined ? manifest.id : id;
    var builtin = builtinOwner(config, { [manifest.id]: manifest }, defaultBarId, builtinNames, id) !== null;
    var placed = layoutPositionOf(config, id, null) !== null;
    if (!builtin && manifest.kinds.indexOf("bar-widget") === -1)
        return "refused: moved=" + id + " reason=no-bar-widget";
    if (placed && !isEnabled(config, manifest, defaultBarId))
        return "refused: moved=" + id + " reason=disabled";
    if (!placed)
        return "refused: moved=" + id + " reason=unplaced";
    if (ConfigLogic.SECTIONS.indexOf(section) === -1)
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

// The user-file change that shows or hides an ordinary widget ID in the
// bar. disabledPlugins is never read or written. Returns the new user
// object; the caller checks placedRefusal first and writes it.
//
// Placing an unplaced widget is placeWidget. Unplacing seeds the user `bar`
// and removes every layout entry with the plugin's id from every section.
// It lists a plugin with no plugins[] row there as `{ id }`: the row is the
// record firstPresence reads
// as the user's choice, so a hidden widget stays hidden, and a "row" plugin
// (enablementRule), enabled only by its placement, stays enabled through
// it. A "widget" plugin has nothing left once unplaced: it reads as
// disabled until enabling places it again. A widget already as asked
// changes nothing but the version stamp. A builtin ID differs from its
// owner's manifest ID and creates no independent plugins row or settings.
function withPlaced(user, manifest, placed, effective, id, shipped) {
    id = id === undefined ? manifest.id : id;
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
    if (placed === (layoutPositionOf(effective, id, null) !== null))
        return out;
    if (placed) {
        placeWidget(out, manifest, effective, id, shipped);
        return out;
    }
    seedUserBar(out, effective);
    if (id === manifest.id && pluginRow(effective, id) === undefined) {
        out.plugins = (Array.isArray(out.plugins) ? out.plugins : []).concat([{ id: id }]);
    }
    ConfigLogic.SECTIONS.forEach(function (section) {
        var entries = out.bar.layout[section];
        if (Array.isArray(entries))
            out.bar.layout[section] = entries.filter(function (entry) { return entry.id !== id; });
    });
    return out;
}

// The user-file change that moves plugin MANIFEST's widget. FROM is
// `{ section, nth }` or null for the first entry in section order. INDEX is
// the target section's entry index after the source entry has been removed.
function withMoved(user, manifest, from, section, index, effective, id) {
    id = id === undefined ? manifest.id : id;
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
    seedUserBar(out, effective);
    if (!isPlainObject(out.bar.layout)) out.bar.layout = { left: [], center: [], right: [] };
    for (var s = 0; s < ConfigLogic.SECTIONS.length; s++)
        if (!Array.isArray(out.bar.layout[ConfigLogic.SECTIONS[s]])) out.bar.layout[ConfigLogic.SECTIONS[s]] = [];
    var source = layoutPositionOf(out, id, from);
    if (source === null) return out;
    var entry = out.bar.layout[source.section].splice(source.index, 1)[0];
    var target = out.bar.layout[section];
    var at = Math.max(0, Math.min(index, target.length));
    target.splice(at, 0, entry);
    return out;
}

// The user-file change that adds a new layout entry for builtin ID at
// INDEX of SECTION, the target section's entry index, as barDropIndex
// answers it with no source entry. The caller checks placedRefusal and
// that no entry holds ID first.
function withBuiltinAt(user, id, section, index, effective) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
    seedUserBar(out, effective);
    if (!isPlainObject(out.bar.layout)) out.bar.layout = { left: [], center: [], right: [] };
    if (!Array.isArray(out.bar.layout[section])) out.bar.layout[section] = [];
    var target = out.bar.layout[section];
    target.splice(Math.max(0, Math.min(index, target.length)), 0, { id: id });
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
// excluded. A section the bar scrolls adds `view`, `{ x, width }`, the box
// it draws in, and `shown`, the part of it that shows whole widgets.
// X over a section's view picks that section; elsewhere the bar's thirds
// do. In a section with `shown`, the slot is chosen among the widgets
// shown whole, so a drop past the last shown one lands beside it, never
// beside a widget the section hides.
function barDropTarget(width, x, sections) {
    var section = x < width / 3 ? "left" : x < 2 * width / 3 ? "center" : "right";
    ["left", "right"].forEach(function (side) {
        var view = isPlainObject(sections) && isPlainObject(sections[side]) ? sections[side].view : null;
        if (isPlainObject(view) && view.width > 0 && x >= view.x && x < view.x + view.width) section = side;
    });
    var info = isPlainObject(sections) && isPlainObject(sections[section]) ? sections[section] : { x: 0, width: width, widgets: [] };
    var widgets = Array.isArray(info.widgets) ? info.widgets : [];
    var next = null;
    if (isPlainObject(info.shown)) {
        var low = info.shown.x - 1, high = info.shown.x + info.shown.width + 1;
        var after = widgets.filter(function (widget) { return widget.x + widget.width > high; });
        next = after.length > 0 ? after[0] : null;
        widgets = widgets.filter(function (widget) { return widget.x >= low && widget.x + widget.width <= high; });
    }
    var slot = 0;
    while (slot < widgets.length && widgets[slot].x + widgets[slot].width / 2 < x) slot += 1;
    var target = slot < widgets.length ? widgets[slot] : next;
    var before = target !== null ? clone(target.locator) : null;
    var markerX;
    if (slot < widgets.length) markerX = widgets[slot].x;
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
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
    firstPresence(manifests, effective).forEach(function (id) { placeWidget(out, manifests[id], effective); });
    return out;
}

// Why `value` may not be written to setting `key` of this plugin, or "".
// A key the manifest's schema declares takes a value of its type. A key
// `settings` declares with no schema entry is a choice the plugin keeps
// from one of its own surfaces, which the Settings page draws no field
// for: it takes a value of its default's type. No other key is writable.
// The reply is one keyed line.
function settingRefusal(manifest, key, value) {
    value = controlValue(value);
    if (manifest.hyprland !== undefined && manifest.hyprland.monitors === key) {
        var badMonitors = MonitorLogic.rulesError(value, null);
        return badMonitors === "" ? "" : badMonitors.replace("refused: monitors", "refused: setting=" + key);
    }
    if (!hasOwn(manifest.schema, key)) {
        if (!hasOwn(manifest.settings, key))
            return "refused: setting=" + key + " undeclared";
        var want = keptType(manifest.settings[key]);
        return keptType(value) === want ? "" : "refused: setting=" + key + " want=" + want;
    }
    var bad = settingError(manifest.schema[key], value);
    return bad === "" ? "" : "refused: setting=" + key + " " + bad;
}

// The JSON type of VALUE, as settingRefusal names it for a setting with no
// schema entry. NaN and the infinities, which JSON cannot hold, are no
// number.
function keptType(value) {
    if (value === null) return "null";
    if (Array.isArray(value)) return "list";
    if (typeof value === "number" && !isFinite(value)) return "non-finite";
    return typeof value;
}

// Why shortcut `shortcut` of this plugin may not take `key`, or "". Only a
// shortcut the manifest's `hyprland.binds` declares has a key. A key string
// or non-empty list of strings ConfigLogic.hyprlandKey accepts rebinds it, null unbinds
// it, and undefined removes the plugins row's entry so the manifest's key
// applies. The reply is one keyed line.
function keyRefusal(manifest, shortcut, key) {
    key = controlValue(key);
    var binds = manifest.hyprland === undefined ? [] : manifest.hyprland.binds;
    var bind = binds.filter(function (row) { return row.shortcut === shortcut; })[0];
    if (bind === undefined && !Pads.isPadShortcut(manifest.hyprland, shortcut, ConfigLogic.NAME_PATTERN))
        return "refused: key=" + shortcut + " undeclared";
    if (key === undefined || key === null)
        return "";
    if (typeof key !== "string" && !Array.isArray(key))
        return "refused: key=" + shortcut + " want=string-list-or-null";
    var bad = ConfigLogic.keyValueError(key, "refused: key=" + shortcut, bind !== undefined && bind.tap === true);
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
    key = controlValue(key);
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
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

// The user-file change that sets one setting of one plugin in its
// plugins[] row, which every instance of the plugin reads, seeding that row
// from the effective one, since a user row replaces the shipped row whole.
// The caller checks the value with settingRefusal first.
function withSetting(user, manifest, key, value, effective) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
    var plugins = Array.isArray(out.plugins) ? out.plugins : [];
    var row = pluginRow(out, manifest.id);
    if (row === undefined) {
        var shippedRow = pluginRow(effective, manifest.id);
        row = shippedRow !== undefined ? shippedRow : { id: manifest.id };
        plugins.push(row);
    }
    var index = plugins.indexOf(row);
    row = copyEntrySettings({}, row, manifest, true);
    row[key] = controlValue(value);
    plugins[index] = row;
    out.plugins = plugins;
    return out;
}

// The user-file change that sets the user's Appearance value KEY to VALUE,
// or removes it when VALUE is undefined, so the theme's applies again. The
// user `appearance` key replaces the shipped one whole, so it is seeded
// from EFFECTIVE's; an object left empty is removed. The caller judges KEY
// and VALUE with ThemeLogic.appearanceRefusal first.
function withAppearance(user, effective, key, value) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
    var appearance = isPlainObject(out.appearance) ? out.appearance
        : isPlainObject(effective) && isPlainObject(effective.appearance) ? clone(effective.appearance) : {};
    if (value === undefined) delete appearance[key];
    else appearance[key] = clone(value);
    if (Object.keys(appearance).length > 0) out.appearance = appearance;
    else delete out.appearance;
    return out;
}

// What EVENT of MANIFEST, one the core stores, sounds under CONFIG: the
// user's choice, config.sounds[<id>][<event>], where it is one the event
// takes, else the manifest's default. A stored id the core's set no longer
// holds reads as the default, as an Appearance member the theme refuses
// reads as Set by theme: one stale choice silences no event and blocks no
// other key.
function soundValue(config, manifest, event) {
    var entry = manifest.sounds[event];
    var chosen = isPlainObject(config) && isPlainObject(config.sounds) && isPlainObject(config.sounds[manifest.id])
        ? config.sounds[manifest.id][event] : undefined;
    return soundValueFits(entry, chosen) ? chosen : entry["default"];
}

// The events of MANIFEST the core stores, under CONFIG, { event: value }:
// what capability `sounds` lends the plugin, so one that sounds an event
// itself reads whether the user turned it off. A held event is absent: its
// plugin reads the value where it lives.
function soundChoices(config, manifest) {
    var out = {};
    Object.keys(manifest.sounds).forEach(function (event) {
        if (!soundHeld(manifest, event)) out[event] = soundValue(config, manifest, event);
    });
    return out;
}

// A plugin's statement of the value of its held EVENT, shell.sounds.report:
// { ok: true, state } with the { value, problem } the page reads, or
// { ok: false, answer }. VALUE is one the event takes, or null while the
// plugin cannot read it; PROBLEM is one printable line the row shows, the
// reason the value is unread or a choice did not take effect, or "".
function soundReport(manifest, event, value, problem) {
    if (typeof event !== "string" || !hasOwn(manifest.sounds, event))
        return { ok: false, answer: soundRefusal(event, "undeclared") };
    if (!soundHeld(manifest, event))
        return { ok: false, answer: soundRefusal(event, "stored") };
    if (value !== null && !soundValueFits(manifest.sounds[event], value))
        return { ok: false, answer: soundRefusal(event, "value") };
    if (problem !== "" && !isPrintableLine(problem, STATUS_HINT_MAX))
        return { ok: false, answer: soundRefusal(event, "problem") };
    return { ok: true, state: { value: value, problem: problem } };
}

// The Sounds page's rows: every event of every enabled plugin, plugins by
// name then id, a plugin's events in its manifest's order. Each row is
// { id, plugin, event, label, description, value, offers, testable,
// problem }: `value` what the event sounds now, `offers` the values it
// takes (soundOffers), `testable` whether one of them is a sound Test
// plays. A held event reads HELD, { <id>: { <event>: { value, problem } } },
// what its plugin last stated: its `value` is null until then and while
// the plugin cannot read it, and `problem` is the plugin's line, "" for
// every other event.
function soundRows(config, manifests, defaultBarId, held) {
    var rows = [];
    Object.keys(manifests).filter(function (id) {
        return Object.keys(manifests[id].sounds).length > 0 && isEnabled(config, manifests[id], defaultBarId);
    }).sort(function (a, b) {
        var left = manifests[a].name, right = manifests[b].name;
        if (left !== right) return left < right ? -1 : 1;
        return a < b ? -1 : a > b ? 1 : 0;
    }).forEach(function (id) {
        var manifest = manifests[id];
        Object.keys(manifest.sounds).forEach(function (event) {
            var entry = manifest.sounds[event];
            var offers = soundOffers(entry);
            var stated = soundHeld(manifest, event) && hasOwn(held, id) && hasOwn(held[id], event) ? held[id][event] : null;
            rows.push({
                id: id, plugin: manifest.name, event: event, label: entry.label,
                description: entry.description === undefined ? "" : entry.description,
                value: !soundHeld(manifest, event) ? soundValue(config, manifest, event) : stated === null ? null : stated.value,
                offers: offers,
                testable: offers.some(function (offer) { return offer.playable; }),
                problem: stated === null ? "" : stated.problem
            });
        });
    });
    return rows;
}

// The one keyed line a refused sound request answers:
// `refused: sound=<event> reason=<reason>`, a name ConfigLogic.NAME_PATTERN does not
// admit written as JSON so the line stays one line.
function soundRefusal(event, reason) {
    return "refused: sound=" + (typeof event === "string" && ConfigLogic.NAME_PATTERN.test(event) ? event : JSON.stringify(event)) + " reason=" + reason;
}

// A plugin's play of its own EVENT under CONFIG: { ok: true, sound } with
// the id of SOUNDS to play, or { ok: false, answer }: `off` when the user,
// or the manifest's default, sets none, `reason=undeclared` for an event
// the manifest does not declare and `reason=own` for one the plugin sounds
// itself, which the core has no file for.
function soundRequest(config, manifest, event) {
    if (typeof event !== "string" || !hasOwn(manifest.sounds, event))
        return { ok: false, answer: soundRefusal(event, "undeclared") };
    if (manifest.sounds[event].own !== undefined)
        return { ok: false, answer: soundRefusal(event, "own") };
    var value = soundValue(config, manifest, event);
    return value === SOUND_OFF ? { ok: false, answer: "off" } : { ok: true, sound: value };
}

// The Sounds page's choice of VALUE for EVENT of MANIFEST, null for an id
// no enabled plugin has: { ok: true, user } with the user file to write,
// { ok: true, held: true } for a held event, whose plugin applies the
// choice and the user file takes none, or { ok: false, answer }. A value
// equal to the manifest's default removes
// the choice, so the user file holds only what the user changed. The user
// `sounds` key replaces the shipped one whole, so it is seeded from
// EFFECTIVE's; a plugin's object left empty is removed, and the key with
// the last one.
function soundEdit(user, effective, manifest, id, event, value) {
    if (manifest === null)
        return { ok: false, answer: "unknown: " + id };
    if (typeof event !== "string" || !hasOwn(manifest.sounds, event))
        return { ok: false, answer: soundRefusal(event, "undeclared") };
    if (!soundValueFits(manifest.sounds[event], value))
        return { ok: false, answer: soundRefusal(event, "value") };
    if (soundHeld(manifest, event))
        return { ok: true, held: true };
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
    var sounds = isPlainObject(out.sounds) ? out.sounds
        : isPlainObject(effective) && isPlainObject(effective.sounds) ? clone(effective.sounds) : {};
    var own = isPlainObject(sounds[id]) ? sounds[id] : {};
    if (value === manifest.sounds[event]["default"]) delete own[event];
    else own[event] = value;
    if (Object.keys(own).length > 0) sounds[id] = own;
    else delete sounds[id];
    if (Object.keys(sounds).length > 0) out.sounds = sounds;
    else delete out.sounds;
    return { ok: true, user: out };
}

// The player's argv for SOUND, an id of SOUNDS, whose file is under
// DIRECTORY: pw-play with the Notification media role, so the session's
// policy treats it as an event sound and not as music. null for an id the
// set does not hold.
function soundArgv(directory, sound) {
    var entry = soundOf(sound);
    return entry === null ? null : ["pw-play", "--media-role", "Notification", directory + "/" + entry.file];
}

// The user-file change that removes one setting of one plugin from the
// user file's plugins[] row, so the plugin reads its manifest's default
// again and the Hyprland layer stops writing the option the setting maps
// to. A row the user file does not hold is not seeded.
function withoutSetting(user, manifest, key) {
    var out = isPlainObject(user) ? clone(user) : {};
    if (out.version === undefined) out.version = ConfigLogic.CONFIG_VERSION;
    var row = pluginRow(out, manifest.id);
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
// sender, so a critical plugin message shows under Silence. The body holds
// a page reference's words in its place (PageReference.plain), so every
// server shows the words; a reference that names a page also goes whole
// in the x-vgs-page hint, from which a server that draws links reads the
// words, the page and the tab. The notification server reads a body as
// markup, so the body's `&`, `<` and `>` are escaped and plain text shows
// as typed.
function notifyArgv(pluginId, appName, judged) {
    var argv = ["notify-send", "--app-name=" + appName, "--urgency=" + judged.urgency, "--hint=string:x-vgs-click:none", "--hint=string:x-vgs-plugin:" + pluginId];
    if (judged.tone !== "") argv.push("--hint=string:x-vgs-tone:" + judged.tone);
    if (judged.icon !== "") argv.push("--hint=string:x-vgs-icon:" + judged.icon);
    var reference = PageReference.parse(judged.message);
    if (reference.page !== "") argv.push("--hint=string:x-vgs-page:" + reference.reference);
    if (judged.transient) argv.push("--transient");
    var message = reference.text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
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

// The first defect of where STATUS's entries draw on a plugin page, or ""
// (docs/architecture/design-system.md § Settings pages). `setup` makes a
// displayed state or presence a required step of Setup, and `step` puts a
// key list beside its step there. Settings holds only values the user
// changes, so `setting` takes only a stored key list, the presenceList of
// a manifest that declares `secrets` (SECRETS), whose masked field is one,
// beside a field of SCHEMA, and `settings: true` only a displayed `rows`
// entry the user changes through its `action` or its `rowActions`, such
// as a list of folder pairs with Add and Remove. Every other entry, with
// its action, is a fact of Details.
function pagePlacementError(status, schema, secrets) {
    var keys = Object.keys(status);
    for (var i = 0; i < keys.length; i++) {
        var entry = status[keys[i]], at = "status." + keys[i];
        if (entry.setup !== undefined && typeof entry.setup !== "boolean") return at + ".setup must be a boolean";
        if (entry.setup === true && (entry.hidden === true || ["state", "presence"].indexOf(entry.type) === -1)) return at + ".setup needs a displayed state or presence";
        if (typeof entry.settings !== "boolean" && entry.settings !== undefined) return at + ".settings must be a boolean";
        if (entry.settings === true) {
            if (entry.type !== "rows" || (entry.action === undefined && entry.rowActions === undefined)) return at + ".settings needs a rows entry the user changes through its action or rowActions; Settings draws only values the user changes";
            if (entry.hidden === true) return at + ".settings needs a displayed status";
        }
        if (entry.setting !== undefined) {
            if (entry.type !== "presenceList" || !secrets) return at + ".setting needs a stored key list; Settings draws only values the user changes";
            if (typeof entry.setting !== "string" || !hasOwn(schema, entry.setting)) return at + ".setting must name a schema field";
            if (entry.hidden === true) return at + ".setting needs a displayed status";
        }
        if (entry.step !== undefined) {
            if (typeof entry.step !== "string" || !hasOwn(status, entry.step) || status[entry.step].setup !== true) return at + ".step must name a required Setup step";
            if (entry.type !== "presenceList") return at + ".step needs a key list";
        }
        if ((entry.setup === true ? 1 : 0) + (entry.setting !== undefined ? 1 : 0) + (entry.step !== undefined ? 1 : 0) > 1) return at + " declares more than one page placement";
    }
    return "";
}

// The rows a plugin's Settings page draws for SCHEMA, one per field in
// schema order, from the normalized STATUS: { key, section, list,
// keyLists }. `section` is the field's group, "" for none, and `list`
// whether it is a list, which draws as a section of its own. `keyLists`
// are the stored key lists placed beside the field (pagePlacementError).
function fieldRows(schema, status) {
    return Object.keys(schema).map(function (key) {
        return {
            key: key,
            section: schema[key].group === undefined ? "" : schema[key].group,
            list: schema[key].type === "list",
            keyLists: Object.keys(status).filter(function (name) { return status[name].setting === key; })
        };
    });
}

// The first row a Settings page could not draw truly, of ROWS, fieldRows'
// over SCHEMA and STATUS, and of the More settings rows of TUI, or "":
// `schema.<key> page-row=<rule>`, `status.<key> page-row=<rule>` or
// `tui.<name>.entry page-row=<rule>`, then why. `duplicate-label`, a label
// drawn twice in one section, a list's own included, ignoring case, or a
// second configuration screen, whose More settings row would repeat the
// first's. `page-label`, a label of the rows the page draws itself
// (SettingValues.PAGE_LABELS).
function pageRowsError(rows, schema, status, tui) {
    var own = Object.keys(SettingValues.PAGE_LABELS).map(function (name) { return SettingValues.PAGE_LABELS[name].toLowerCase(); });
    var declared = [];
    Object.keys(status).forEach(function (key) { declared = declared.concat(statusDeclaredTuis(status[key])); });
    var configuring = Object.keys(tui).filter(function (name) { return tui[name].entry !== null && tui[name].entry.settings === true && declared.indexOf(name) === -1; });
    if (configuring.length > 1)
        return "tui." + configuring[1] + ".entry page-row=duplicate-label: " + JSON.stringify(SettingValues.PAGE_LABELS.moreSettings) + " is drawn for " + configuring[0] + " already; list one configuration screen";
    var drawn = Object.create(null);
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i], spec = schema[row.key], at = "schema." + row.key;
        var scope = row.list ? "list " + row.key : "section " + row.section;
        if (drawn[scope] === undefined) drawn[scope] = [];
        var labels = (row.list ? [] : [[at, spec.label]]).concat(row.keyLists.map(function (key) { return ["status." + key, status[key].label]; }));
        for (var l = 0; l < labels.length; l++) {
            var label = String(labels[l][1]).toLowerCase();
            if (own.indexOf(label) !== -1)
                return labels[l][0] + " page-row=page-label: the page draws " + JSON.stringify(labels[l][1]) + " itself";
            if (drawn[scope].indexOf(label) !== -1)
                return labels[l][0] + " page-row=duplicate-label: " + JSON.stringify(labels[l][1]) + " is drawn twice in one section";
            drawn[scope].push(label);
        }
    }
    return "";
}
