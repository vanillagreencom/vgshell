.pragma library
.import "PackageManagers.js" as PackageManagers

// The configuration judgement: the shape a shell.json layer must have
// (configError), the migration of a user file of the previous format
// version (migrateConfig), the rename of a plugin's former ids
// (renamePlugins), the merge of the two layers (effectiveConfig)
// and the key grammar a plugins row's `keys` is judged by (hyprlandKey).
// PluginLogic.js and the shell files that judge or read configuration
// import it, and the offline judges that read shell.json load it alone, so
// a judge reads shell.json with the shell's own rules without loading
// PluginLogic.js.

// Object helpers of its own, as Pads.js, MonitorLogic.js and ThemeLogic.js
// keep theirs, so it imports nothing from PluginLogic.js.
function hasOwn(obj, key) {
    return obj !== null && typeof obj === "object" && Object.prototype.hasOwnProperty.call(obj, key);
}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function clone(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

// The sections of a bar layout, in section order.
var SECTIONS = ["left", "center", "right"];

// A name a plugin registers a shortcut, an IPC target or a built-in widget
// under, the name a manifest's Hyprland bind gives its shortcut, and the name
// a manifest's `tui` key declares a script under.
// Capabilities.checkName refuses any other.
var NAME_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

// The modifiers a Hyprland key may hold, in the order a normalised key
// writes them, and the key name after them: a keysym name, which Hyprland
// looks up without regard to case.
var HYPRLAND_MODIFIERS = ["SUPER", "CTRL", "ALT", "SHIFT"];
var HYPRLAND_KEY_NAME = /^[A-Za-z0-9_]+$/;

// The version a configuration file declares. Each user-file edit of
// PluginLogic.js (`withEnabled`, `withPlaced`, `withSetting`, `withKey`,
// `withAppearance`) writes it into a user file that has none. Version 2
// keeps every setting of a plugin in its plugins[] row; migrateConfig
// rewrites a version 1 file.
var CONFIG_VERSION = 2;

// The first defect of a configuration file (shipped or user), or "". The
// file is an object; `version`, when present, is CONFIG_VERSION; `plugins`
// is a list of objects each with a string `id`, and a row's `keys`, when
// present, passes keysError; `disabledPlugins` and
// `disabledTargets` are lists of strings; `bar` is an object whose `id` is
// a string and whose `layout` holds, per section in SECTIONS, a list of
// objects each with a string `id` and no other key, since a layout entry
// places a widget and its settings live in the plugins[] row; `packages` is an object whose `elevate`,
// when present, is one of PackageManagers.ELEVATORS, the command
// `vgshell pkg run` elevates through; `welcome` is an object whose `keys` is
// a list of objects each with a string `id`, a string `shortcut` and a
// non-empty string `text`, the welcome's key lines (PluginLogic.consentSlotView);
// `manager` is an object whose `id` is a string (PluginLogic.managerId); `appearance`
// is an object, whose members ThemeLogic.appearanceRefusal judges where
// the theme resolves them, so one bad member shows as Set by theme and
// blocks no other key; `sounds` is an object of plugin ids, each an object
// of event names to strings, the user's sound choices, each judged where
// it is read (PluginLogic.soundValue). A key outside that set is carried untouched. Config.qml runs this judge
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
                if (config.bar.layout[section] === undefined)
                    continue;
                if ((bad = rows(config.bar.layout[section], "bar.layout." + section)) !== "")
                    return bad;
                for (var e = 0; e < config.bar.layout[section].length; e++) {
                    var extra = Object.keys(config.bar.layout[section][e]).filter(function (k) { return k !== "id"; });
                    if (extra.length > 0)
                        return "bar.layout." + section + "." + e + " has key " + JSON.stringify(extra[0]) + " beside its id; a setting belongs in its plugins[] row";
                }
            }
        }
    }
    if (config.manager !== undefined) {
        if (!isPlainObject(config.manager))
            return "manager must be an object";
        if (typeof config.manager.id !== "string")
            return "manager.id must be a string";
    }
    if (config.appearance !== undefined && !isPlainObject(config.appearance))
        return "appearance must be an object";
    if (config.sounds !== undefined) {
        if (!isPlainObject(config.sounds))
            return "sounds must be an object";
        var soundIds = Object.keys(config.sounds);
        for (var d = 0; d < soundIds.length; d++) {
            var chosen = config.sounds[soundIds[d]];
            if (!isPlainObject(chosen))
                return "sounds." + soundIds[d] + " must be an object";
            var events = Object.keys(chosen);
            for (var v = 0; v < events.length; v++) {
                if (typeof chosen[events[v]] !== "string")
                    return "sounds." + soundIds[d] + "." + events[v] + " must be a string";
            }
        }
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

// The user file CONFIG as this version stores it: { config, migrated }.
// Version 1 let a layout entry carry a widget's settings beside its id.
// Each such key, in every section of SECTIONS, moves into the plugins[]
// row with the entry's id, appended as { id } when the file has none: the
// row's value wins where the row sets the key, and of two entries with one
// id the first in section order wins. The entry keeps its id alone. No
// manifest is read, so the key of a plugin that is not installed moves the
// same way. A version 1 file takes this version; a file with no version,
// which configError reads as this version, is migrated only when an entry
// carries a key to move. Any other value comes back as it is, and a shape
// the move cannot read is left for configError to name. CONFIG is not
// changed.
function migrateConfig(config) {
    var same = { config: config, migrated: false };
    if (!isPlainObject(config) || (config.version !== 1 && config.version !== undefined))
        return same;
    var out = clone(config);
    var layout = isPlainObject(out.bar) && isPlainObject(out.bar.layout) ? out.bar.layout : {};
    var moved = false;
    SECTIONS.forEach(function (section) {
        if (!Array.isArray(layout[section])) return;
        layout[section] = layout[section].map(function (entry) {
            if (!isPlainObject(entry) || typeof entry.id !== "string") return entry;
            var keys = Object.keys(entry).filter(function (k) { return k !== "id"; });
            if (keys.length === 0) return entry;
            if (out.plugins === undefined) out.plugins = [];
            if (!Array.isArray(out.plugins)) return entry;
            var row = out.plugins.filter(function (r) { return isPlainObject(r) && r.id === entry.id; })[0];
            if (row === undefined) {
                row = { id: entry.id };
                out.plugins.push(row);
            }
            keys.forEach(function (k) {
                if (!hasOwn(row, k)) row[k] = entry[k];
            });
            moved = true;
            return { id: entry.id };
        });
    });
    if (config.version === undefined && !moved)
        return same;
    out.version = CONFIG_VERSION;
    return { config: out, migrated: true };
}

// The configuration CONFIG with each plugin id RENAMES maps, a former id
// to the id of the bundled plugin that declares it in its manifest's
// `formerIds` (PluginLogic.formerIdClaims), replaced by the new id:
// { config, renamed }. Each plugins[] row, disabledPlugins entry and
// bar.layout entry in SECTIONS with a mapped id takes the new id; no other
// key names a renamed plugin (D108). The map comes from the scan, so the
// core names no plugin (D003). A former id stays in its manifest for as
// long as the plugin ships, which makes this the converter step D107 asks
// for without a format version. A row or entry that is not an object with
// a string id is left for configError to name. CONFIG is not changed; with
// nothing renamed it comes back as it is.
function renamePlugins(config, renames) {
    var same = { config: config, renamed: false };
    if (!isPlainObject(config) || !isPlainObject(renames) || Object.keys(renames).length === 0)
        return same;
    var out = clone(config);
    var renamed = false;
    var renamedId = function (id) {
        if (typeof id !== "string" || !hasOwn(renames, id)) return id;
        renamed = true;
        return renames[id];
    };
    var renameRows = function (list) {
        if (!Array.isArray(list)) return;
        list.forEach(function (row) {
            if (isPlainObject(row) && typeof row.id === "string") row.id = renamedId(row.id);
        });
    };
    renameRows(out.plugins);
    if (Array.isArray(out.disabledPlugins)) out.disabledPlugins = out.disabledPlugins.map(renamedId);
    var layout = isPlainObject(out.bar) && isPlainObject(out.bar.layout) ? out.bar.layout : {};
    SECTIONS.forEach(function (section) { renameRows(layout[section]); });
    return renamed ? { config: out, renamed: true } : same;
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

// The first defect of a plugins row's `keys`, or "": an object whose names
// are shortcut names and whose values are keys hyprlandKey accepts, a
// non-empty list of those keys, or null for a shortcut the user unbinds. A
// name the plugin binds nothing under is no defect here; the Hyprland layer
// reports it (PluginLogic.hyprlandSection).
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
