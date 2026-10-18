.pragma library

// The package managers VGS knows, one row each, and the pure decisions made
// over them: which managers a system has, the steps an install, an update, a
// removal or an upgrade takes, what a manager's update query printed, and the
// queries naming the package that owns a file and its installed version,
// and the dry run that says whether a package can be removed.
// No QML objects and no I/O, so bin/vgshell-pkg runs this file under node
// through bin/lib/qml-library.js, the one source D034 names, and
// PluginLogic.js imports it to judge a manifest's `requirements` (D035).
//
// A row:
//   id        the manager's name in every VGS file and command
//   role      "primary": the distribution's own manager, at most one per
//             system; "overlay": a second package source beside it;
//             "source": a user-level tool source
//   family    the os-release ID values a primary serves, matched against ID
//             and then each ID_LIKE token
//   release   null when the row serves every release of its family, else
//             { key, value }: the one release it serves, the os-release
//             assignment that release makes. Such a row matches ID alone,
//             never an ID_LIKE token, since a derivative's release field
//             names the derivative's own release.
//   requires  the primary an overlay only exists beside, or null
//   binaries  the commands that run the manager, preferred first; the first
//             one on PATH is the row's binary
//   elevate   whether install, update, remove and upgrade need root. No step names
//             an elevation command: `vgshell pkg run` puts one of ELEVATORS
//             before each step, in a terminal where the user answers the
//             prompt, and the shell process never elevates.
//   check     the unprivileged update queries, the first whose binary is
//             null or the row's binary answering: its argv, the meaning of
//             each exit status ("updates" or "rows": the parser's rows are
//             the updates; "none": there are none), the parser's name in
//             PARSERS and the seconds a run may take. An unlisted status is
//             a failure. null when no read-only query exists.
//   install, reinstall, update, remove, upgrade
//             the steps, each an argv template run in order; null when VGS
//             plans none for the manager. An update brings named packages
//             the manager already installed to its current version, and a
//             row has its steps exactly when it has install's.
//   ignore    the option that keeps one package out of an upgrade, put
//             with the package's name after each upgrade step once per
//             package; null when VGS keeps none out for the manager
//   owner     the query naming the package that owns a file, or null:
//             { argv, read }, argv a template taking "{path}" and read the
//             pattern whose first group is the package's name in the first
//             line the query prints; or { argv, roots: true } for a manager
//             that prints installed roots, which ownerAnswer matches to the
//             command path without I/O of its own
//   installed the query naming a package's installed version, or null when
//             VGS asks none of the manager: { argv, read }, argv a template
//             taking "{name}" and read the pattern whose first group is the
//             upstream version, with no epoch and no packaging revision, in
//             the first line the query prints
//   removable the dry run of removing one package, or null when VGS asks
//             none of the manager: { argv }, argv a template taking
//             "{name}". It changes nothing, needs no root, and exits 0 only
//             when the package is installed and no other installed package
//             requires it.
//   picker    what `vgshell pkg install` and `remove` offer in fzf when no name
//             is given: { install, remove }, each null when VGS offers no
//             picker for the action, else { list, preview }. list prints
//             the packages, one per line, the name first; preview prints
//             one package's details and takes "{name}". Both only read.
// In a template "{bin}" is the row's binary, "{names}" the package names,
// "{names@latest}" each of them followed by `@latest`, "{name}" one package
// name and "{path}" an absolute file path. A
// pacman-family sync that refreshes the databases always upgrades too:
// `-Syu`, never `-Sy` alone.
var MANAGERS = [
    {
        id: "pacman", role: "primary", family: ["arch"], release: null, requires: null, binaries: ["pacman"], elevate: true,
        check: [{ binary: null, argv: ["checkupdates"], exits: { "0": "updates", "2": "none" }, parser: "arrow", timeout: 120 }],
        install: [["{bin}", "-S", "--needed", "--", "{names}"]],
        // pacman(8): omitting --needed restores an up-to-date target.
        reinstall: [["{bin}", "-S", "--", "{names}"]],
        // pacman(8): --needed skips only a target that is up to date, so
        // the install step updates an older one to the version the
        // databases of the last upgrade hold.
        update: [["{bin}", "-S", "--needed", "--", "{names}"]],
        remove: [["{bin}", "-Rns", "--", "{names}"]],
        upgrade: [["{bin}", "-Syu"]],
        ignore: "--ignore",
        owner: { argv: ["{bin}", "-Qoq", "{path}"], read: /^(\S+)$/ },
        installed: { argv: ["{bin}", "-Q", "--", "{name}"], read: /^\S+ (?:[0-9]+:)?(\S+)-[^-\s]+$/ },
        removable: { argv: ["{bin}", "-Rs", "--print", "--", "{name}"] },
        picker: {
            install: { list: ["{bin}", "-Slq"], preview: ["{bin}", "-Sii", "{name}"] },
            remove: { list: ["{bin}", "-Qqe"], preview: ["{bin}", "-Qi", "{name}"] }
        }
    },
    {
        id: "aur", role: "overlay", family: [], release: null, requires: "pacman", binaries: ["paru", "yay"], elevate: false,
        check: [{ binary: null, argv: ["{bin}", "-Qua"], exits: { "0": "updates", "1": "none" }, parser: "arrow", timeout: 120 }],
        install: [["{bin}", "-S", "--needed", "--", "{names}"]],
        reinstall: [["{bin}", "-S", "--", "{names}"]],
        update: [["{bin}", "-S", "--needed", "--", "{names}"]],
        remove: [["{bin}", "-Rns", "--", "{names}"]],
        upgrade: [["{bin}", "-Sua"]],
        ignore: "--ignore",
        // AUR packages are pacman local database entries, so pacman, not
        // the AUR helper, owns the files they install.
        owner: { argv: ["pacman", "-Qoq", "{path}"], read: /^(\S+)$/ },
        installed: null,
        removable: null,
        // pacman's remove picker lists the AUR's packages too.
        picker: { install: { list: ["{bin}", "-Slqa"], preview: ["{bin}", "-Siia", "{name}"] }, remove: null }
    },
    // apt lists what the package lists held at the last `apt update`, which
    // needs root, so the check never refreshes them. Debian 14 is the one
    // Debian release whose repositories meet the floor; its os-release and
    // sid's both set VERSION_CODENAME=forky and no VERSION_ID (podman,
    // docker.io/library/debian:forky and :sid, 2026-10-13).
    {
        id: "apt", role: "primary", family: ["debian"], release: { key: "VERSION_CODENAME", value: "forky" }, requires: null, binaries: ["apt-get"], elevate: true,
        check: [{ binary: null, argv: ["apt", "list", "--upgradable"], exits: { "0": "rows" }, parser: "apt", timeout: 120 }],
        install: [["{bin}", "install", "{names}"]],
        reinstall: [["{bin}", "install", "--reinstall", "{names}"]],
        // apt-get(8): install is also the target that upgrades an installed
        // package without upgrading every package.
        update: [["{bin}", "install", "{names}"]],
        remove: [["{bin}", "remove", "{names}"]],
        upgrade: [["{bin}", "update"], ["{bin}", "full-upgrade"]],
        ignore: null,
        owner: { argv: ["dpkg", "-S", "{path}"], read: /^([a-z0-9][a-z0-9+.-]*)(?::[a-z0-9-]+)?: / },
        installed: { argv: ["dpkg-query", "-W", "--showformat=${Version}\n", "--", "{name}"], read: /^(?:[0-9]+:)?(\S+?)(?:-[^-\s]+)?$/ },
        removable: null,
        picker: {
            install: { list: ["apt-cache", "pkgnames"], preview: ["apt-cache", "show", "{name}"] },
            remove: { list: ["apt-mark", "showmanual"], preview: ["dpkg", "-s", "{name}"] }
        }
    },
    {
        id: "dnf", role: "primary", family: ["fedora"], release: null, requires: null, binaries: ["dnf5", "dnf"], elevate: true,
        check: [
            { binary: "dnf5", argv: ["{bin}", "check-upgrade", "--json"], exits: { "0": "rows" }, parser: "dnf5", timeout: 120 },
            { binary: "dnf", argv: ["{bin}", "-q", "check-update"], exits: { "0": "none", "100": "updates" }, parser: "dnf", timeout: 120 }
        ],
        install: [["{bin}", "install", "{names}"]],
        reinstall: [["{bin}", "reinstall", "{names}"]],
        // dnf(8): upgrade with a package updates that package to the latest
        // version.
        update: [["{bin}", "upgrade", "{names}"]],
        remove: [["{bin}", "remove", "{names}"]],
        upgrade: [["{bin}", "upgrade"]],
        ignore: null,
        owner: { argv: ["rpm", "-qf", "--queryformat", "%{NAME}\n", "{path}"], read: /^(\S+)$/ },
        installed: { argv: ["rpm", "-q", "--queryformat", "%{VERSION}\n", "--", "{name}"], read: /^(\S+)$/ },
        removable: null,
        // The format's `\n` is dnf's own escape: dnf5 prints only what the
        // format asks for, and dnf 4 adds a newline of its own, which leaves
        // a blank line the picker drops. -q keeps dnf 4's `Last metadata
        // expiration check` notice off stdout, where it would be listed.
        picker: {
            install: { list: ["{bin}", "-q", "repoquery", "--available", "--queryformat", "%{name}\\n"], preview: ["{bin}", "info", "{name}"] },
            remove: { list: ["{bin}", "-q", "repoquery", "--userinstalled", "--queryformat", "%{name}\\n"], preview: ["rpm", "-qi", "{name}"] }
        }
    },
    // A NixOS system changes through its own configuration, so VGS plans no
    // step and has no read-only update query for it.
    {
        id: "nix", role: "primary", family: ["nixos"], release: null, requires: null, binaries: ["nix"], elevate: false,
        check: null, install: null, reinstall: null, update: null, remove: null, upgrade: null, ignore: null, owner: null, installed: null, removable: null,
        picker: { install: null, remove: null }
    },
    {
        id: "flatpak", role: "overlay", family: [], release: null, requires: null, binaries: ["flatpak"], elevate: false,
        check: [{ binary: null, argv: ["{bin}", "remote-ls", "--updates", "--columns=application,branch"], exits: { "0": "rows" }, parser: "flatpak", timeout: 120 }],
        install: [["{bin}", "install", "{names}"]],
        reinstall: null,
        // flatpak-update(1): update with a ref updates that ref alone.
        update: [["{bin}", "update", "{names}"]],
        remove: [["{bin}", "uninstall", "{names}"]],
        upgrade: [["{bin}", "update"]],
        ignore: null,
        owner: null,
        installed: null,
        removable: null,
        picker: { install: null, remove: null }
    },
    // An upgrade is the user asking for current versions now, so it waives
    // mise's release-age cooldown; the check
    // waives it too, so it counts what the upgrade installs. An update is
    // the same ask for the named tools, and names `@latest`: `mise use
    // --global <tool>` answers `already installed` for a tool an older
    // version of which is installed, and `<tool>@latest` installs the
    // current one (`mise use --global --dry-run`, mise 2026.9.17 on host
    // cachy, 2026-10-10).
    {
        id: "mise", role: "source", family: [], release: null, requires: null, binaries: ["mise"], elevate: false,
        check: [{ binary: null, argv: ["env", "MISE_MINIMUM_RELEASE_AGE=0", "{bin}", "outdated", "--json"], exits: { "0": "rows" }, parser: "mise", timeout: 120 }],
        install: [["{bin}", "use", "--global", "{names}"]],
        reinstall: null,
        update: [["env", "MISE_MINIMUM_RELEASE_AGE=0", "{bin}", "use", "--global", "{names@latest}"]],
        remove: [["{bin}", "unuse", "--global", "{names}"]],
        upgrade: [["env", "MISE_MINIMUM_RELEASE_AGE=0", "{bin}", "upgrade"]],
        ignore: null,
        owner: { argv: ["{bin}", "ls", "--installed", "--json"], roots: true },
        installed: null,
        removable: null,
        picker: { install: null, remove: null }
    }
];

var ACTIONS = ["install", "reinstall", "update", "remove", "upgrade"];

// The commands `vgshell pkg run` may put before a step of a row whose elevate
// is true, in the order it looks for them on PATH. They live outside the
// rows, so the table's steps stay free of any elevation command, and
// ConfigLogic.configError judges shell.json's `packages.elevate` against
// this list.
var ELEVATORS = ["sudo", "doas", "run0"];

// A package name is printable ASCII with no space, and never starts with a
// dash, so no manager reads it as an option.
var NAME_PATTERN = /^[!-~]{1,256}$/;
// A command is a bare file name looked up on PATH, never a path.
var COMMAND_PATTERN = /^[A-Za-z0-9_+][A-Za-z0-9._+-]{0,127}$/;

function managerRow(id) {
    for (var i = 0; i < MANAGERS.length; i++)
        if (MANAGERS[i].id === id) return MANAGERS[i];
    return null;
}

function validName(name) {
    return typeof name === "string" && NAME_PATTERN.test(name) && name.charAt(0) !== "-";
}

function validCommand(command) {
    return typeof command === "string" && COMMAND_PATTERN.test(command);
}

// The value os-release(5) assigns KEY, or null. A value may be quoted with
// double or single quotes; inside double quotes a backslash escapes `\`,
// `"`, `$` and a backtick. The last assignment wins, as in a shell.
function osReleaseValue(text, key) {
    var value = null;
    var lines = text.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = /^([A-Z][A-Z0-9_]*)=(.*)$/.exec(lines[i].trim());
        if (m === null || m[1] !== key) continue;
        var raw = m[2];
        var quote = raw.charAt(0);
        if (raw.length >= 2 && (quote === "\"" || quote === "'") && raw.charAt(raw.length - 1) === quote) {
            raw = raw.slice(1, -1);
            if (quote === "\"") raw = raw.replace(/\\([\\"$`])/g, "$1");
        }
        value = raw;
    }
    return value;
}

// The system's os-release identifiers, most specific first: ID, then each
// ID_LIKE token in order. Empty for an empty or unknown file.
function osReleaseIds(text) {
    var out = [];
    var id = osReleaseValue(text, "ID");
    if (id !== null && id !== "") out.push(id);
    var like = osReleaseValue(text, "ID_LIKE");
    if (like !== null) {
        var tokens = like.split(/\s+/);
        for (var i = 0; i < tokens.length; i++)
            if (tokens[i] !== "" && out.indexOf(tokens[i]) < 0) out.push(tokens[i]);
    }
    return out;
}

// ROW's first binary ON_PATH answers true for, or null.
function binaryOf(row, onPath) {
    for (var i = 0; i < row.binaries.length; i++)
        if (onPath(row.binaries[i])) return row.binaries[i];
    return null;
}

// Whether primary ROW serves the system whose os-release text is TEXT
// through TOKEN, one of its identifiers: the row's family holds TOKEN, and
// a row with a release needs TOKEN to be the system's ID and the system to
// make the release's assignment.
function serves(row, text, token) {
    if (row.family.indexOf(token) < 0) return false;
    if (row.release === null) return true;
    return token === osReleaseValue(text, "ID") && osReleaseValue(text, row.release.key) === row.release.value;
}

// The system's managers: `{ primary, overlays, sources }`, each entry
// `{ id, binary }`, for the system whose os-release text is TEXT. The
// primary is the first row, taking the os-release identifiers in order,
// that serves one and whose binary is on PATH; null when none is. An
// overlay or source is present when its binary is, and an overlay that
// requires a primary only beside it.
function detect(text, onPath) {
    var osIds = osReleaseIds(text);
    var primary = null;
    for (var i = 0; i < osIds.length && primary === null; i++) {
        for (var j = 0; j < MANAGERS.length; j++) {
            var row = MANAGERS[j];
            if (row.role !== "primary" || !serves(row, text, osIds[i])) continue;
            var binary = binaryOf(row, onPath);
            if (binary !== null) {
                primary = { id: row.id, binary: binary };
                break;
            }
        }
    }
    var overlays = [];
    var sources = [];
    for (var k = 0; k < MANAGERS.length; k++) {
        var other = MANAGERS[k];
        if (other.role === "primary") continue;
        if (other.requires !== null && (primary === null || primary.id !== other.requires)) continue;
        var found = binaryOf(other, onPath);
        if (found === null) continue;
        (other.role === "overlay" ? overlays : sources).push({ id: other.id, binary: found });
    }
    return { primary: primary, overlays: overlays, sources: sources };
}

// The managers of FOUND, detect's answer, in the order a requirement's
// package is picked from them: the primary, then each overlay, then each
// source.
function managersInOrder(found) {
    return (found.primary === null ? [] : [found.primary]).concat(found.overlays, found.sources);
}

// The package that provides one requirement on this system, as `{ manager,
// name }`: when HOLDER, `vgshell-pkg detect --json --holders`'s fact for a
// command, says one present manager owns the command path and PACKAGES maps
// that manager to the same package, that manager wins. Otherwise the first
// manager of FOUND, detect's answer, taken primary, then each overlay, then
// each source, that PACKAGES maps to a name wins; null when it maps none of
// them. PACKAGES is a requirement's `packages`, manager ids to package
// names, as PluginLogic.requirementsError accepts it.
function packageFor(packages, found, holder) {
    var order = managersInOrder(found);
    if (holder !== undefined && holder !== null && holder.path !== null && holder.owners !== undefined) {
        for (var h = 0; h < order.length; h++) {
            var heldBy = order[h].id;
            if (Object.prototype.hasOwnProperty.call(packages, heldBy) && holder.owners[heldBy] === packages[heldBy])
                return { manager: heldBy, name: packages[heldBy] };
        }
    }
    for (var i = 0; i < order.length; i++)
        if (Object.prototype.hasOwnProperty.call(packages, order[i].id))
            return { manager: order[i].id, name: packages[order[i].id] };
    return null;
}

// The packages that provide ROWS on this system, rows carrying a
// requirement's `packages`: `{ picks, groups }`. `picks` holds packageFor's
// pick from FOUND for each row, in order. `groups` holds one `{ manager,
// primary, names, installs }` per manager a pick names, in FOUND's order,
// primary first, then overlays, then sources: `names` each package once in
// the order the rows first pick it, `primary` whether the manager is
// FOUND's primary, and `installs` whether its row has install steps, and so
// update steps. A manager without them, nix, changes the system through its
// own configuration, so its packages are added there by hand.
function installGroups(rows, found) {
    var holders = found.holders !== undefined ? found.holders : {};
    var picks = rows.map(function (row) { return packageFor(row.packages, found, row.name !== undefined && Object.prototype.hasOwnProperty.call(holders, row.name) ? holders[row.name] : null); });
    var order = managersInOrder(found);
    var groups = [];
    for (var i = 0; i < order.length; i++) {
        var names = [];
        for (var j = 0; j < picks.length; j++)
            if (picks[j] !== null && picks[j].manager === order[i].id && names.indexOf(picks[j].name) === -1) names.push(picks[j].name);
        if (names.length === 0) continue;
        groups.push({ manager: order[i].id, primary: order[i] === found.primary, names: names, installs: managerRow(order[i].id).install !== null });
    }
    return { picks: picks, groups: groups };
}

// The arguments after `vgshell pkg run install`, or `run update`, that
// install or update GROUP, one of installGroups' groups whose manager
// installs: `--manager <id>` for every manager but the primary, which
// `vgshell pkg run` takes by default, then the names.
function installArgs(group) {
    if (!group.installs)
        throw new Error("installArgs: manager " + group.manager + " has no install steps");
    return (group.primary ? [] : ["--manager", group.manager]).concat(group.names);
}

// Manager ID's row and the binary ON_PATH resolves: `{ ok: true, row,
// binary }`, or `{ ok: false, error }` for an unknown manager or one whose
// binaries are all absent.
function presentManager(id, onPath) {
    var row = managerRow(id);
    if (row === null) return { ok: false, error: "manager=" + id + " reason=unknown" };
    var binary = binaryOf(row, onPath);
    if (binary === null) return { ok: false, error: "manager=" + id + " reason=absent binaries=" + row.binaries.join(",") };
    return { ok: true, row: row, binary: binary };
}

// The steps ACTION takes for manager ID over NAMES, with the binary ON_PATH
// resolves: `{ ok: true, plan: { manager, binary, action, elevate, steps } }`
// or `{ ok: false, error }`, the error the keyed first line of a refusal.
// ACTION is one of ACTIONS and NAMES holds at least one name for install,
// reinstall, update and remove and none for upgrade; the caller refuses any other call as a
// bad invocation. IGNORED, absent or empty but for an upgrade, names the
// packages the upgrade keeps out, through the row's `ignore`: a manager
// without one refuses them as `manager=<id> option=ignore
// reason=unsupported`.
function plan(id, action, names, onPath, ignored) {
    var found = presentManager(id, onPath);
    if (!found.ok) return found;
    var template = found.row[action];
    if (template === null) return { ok: false, error: "manager=" + id + " action=" + action + " reason=unsupported" };
    var kept = ignored === undefined ? [] : ignored;
    if (kept.length > 0 && found.row.ignore === null) return { ok: false, error: "manager=" + id + " option=ignore reason=unsupported" };
    var all = names.concat(kept);
    for (var i = 0; i < all.length; i++)
        if (!validName(all[i])) return { ok: false, error: "name=" + JSON.stringify(all[i]) + " reason=grammar" };
    var binary = found.binary;
    var row = found.row;
    var steps = template.map(function (step) {
        var argv = [];
        for (var j = 0; j < step.length; j++) {
            if (step[j] === "{bin}") argv.push(binary);
            else if (step[j] === "{names}") argv.push.apply(argv, names);
            else if (step[j] === "{names@latest}") argv.push.apply(argv, names.map(function (name) { return name + "@latest"; }));
            else argv.push(step[j]);
        }
        for (var k = 0; k < kept.length; k++) argv.push(row.ignore, kept[k]);
        return argv;
    });
    return { ok: true, plan: { manager: id, binary: binary, action: action, elevate: row.elevate, steps: steps } };
}

// The steps that install MISSING and update OUTDATED for manager ID, each a
// list of one name or more, as plan answers: the update steps once over
// both lists where the row's install and update steps are the same, since
// such a step installs a package it does not find and brings one it finds
// to the current version; else the install steps over MISSING, then the
// update steps over OUTDATED, since an update step of dnf, flatpak or mise
// refuses or skips a package that is not installed.
function planOwed(id, missing, outdated, onPath) {
    var row = managerRow(id);
    if (row !== null && row.update !== null && JSON.stringify(row.update) === JSON.stringify(row.install))
        return plan(id, "update", outdated.concat(missing), onPath);
    var install = plan(id, "install", missing, onPath);
    if (!install.ok) return install;
    var update = plan(id, "update", outdated, onPath);
    if (!update.ok) return update;
    update.plan.steps = install.plan.steps.concat(update.plan.steps);
    return update;
}

// The elevation command a run puts before its steps: CONFIGURED, shell.json's
// `packages.elevate` as configError accepted it, or undefined when unset.
// `{ ok: true, command }` with CONFIGURED when ON_PATH finds it, or else the
// first of ELEVATORS it finds; `{ ok: false, error }` for a configured
// command that is absent or when none is found.
function elevator(configured, onPath) {
    if (configured !== undefined) {
        if (ELEVATORS.indexOf(configured) === -1)
            throw new Error("elevator: packages.elevate " + JSON.stringify(configured) + " passed configError but is not one of " + ELEVATORS.join(", "));
        if (onPath(configured)) return { ok: true, command: configured };
        return { ok: false, error: "elevate=" + configured + " reason=absent source=packages.elevate" };
    }
    for (var i = 0; i < ELEVATORS.length; i++)
        if (onPath(ELEVATORS[i])) return { ok: true, command: ELEVATORS[i] };
    return { ok: false, error: "elevate=none candidates=" + ELEVATORS.join(",") };
}

// Manager ID's picker for ACTION, install or remove, with "{bin}" the binary
// ON_PATH resolves: `{ ok: true, list, preview }`, preview keeping "{name}"
// for the caller to fill, or `{ ok: false, error }` for an unknown or absent
// manager and `manager=<id> picker=<action> reason=unsupported` for one the
// table offers no picker for.
function pickerFor(id, action, onPath) {
    var found = presentManager(id, onPath);
    if (!found.ok) return found;
    var spec = found.row.picker[action];
    if (spec === null) return { ok: false, error: "manager=" + id + " picker=" + action + " reason=unsupported" };
    var fill = function (token) { return token === "{bin}" ? found.binary : token; };
    return { ok: true, list: spec.list.map(fill), preview: spec.preview.map(fill) };
}

// The update parsers, one per output format a check's argv prints. Each maps
// the query's stdout to `{ ok: true, packages }`, each package
// `{ name, old, new }` with old null where the format names no installed
// version, or `{ ok: false, error }` naming the first line it cannot read.
// A line a format does not define is never skipped: a changed format fails
// the check rather than miscounting it.
var ANSI_FREE = /^[^\u001b]*$/;

function lines(text) {
    var out = text.split("\n");
    if (out.length > 0 && out[out.length - 1] === "") out.pop();
    return out;
}

function unreadable(index) {
    return { ok: false, error: "unparseable line=" + (index + 1) };
}

// `name old -> new`: checkupdates, `paru -Qua` and `yay -Qua`. paru marks a
// package pacman's IgnorePkg holds with ` [ignored]`, which the upgrade
// leaves alone, so it is not counted; yay adds the release's age as
// ` [3d4h]`.
function parseArrow(text) {
    var packages = [];
    var rows = lines(text);
    for (var i = 0; i < rows.length; i++) {
        var f = rows[i].split(" ");
        if (!ANSI_FREE.test(rows[i]) || f.length < 4 || f.length > 5 || f[2] !== "->" || f[0] === "" || f[1] === "" || f[3] === "")
            return unreadable(i);
        if (f.length === 5) {
            if (f[4] === "[ignored]") continue;
            if (!/^\[(?:\d+d(?:\d+h)?|\d+h(?:\d+m)?|\d+m)\]$/.test(f[4])) return unreadable(i);
        }
        packages.push({ name: f[0], old: f[1], new: f[3] });
    }
    return { ok: true, packages: packages };
}

// `apt list --upgradable`: a `Listing...` progress line, then
// `name/suite[,suite] new arch [upgradable from: old]`.
function parseApt(text) {
    var packages = [];
    var rows = lines(text);
    for (var i = 0; i < rows.length; i++) {
        if (/^Listing\.\.\.(?: Done)?$/.test(rows[i])) continue;
        var m = /^([^\s\/]+)\/\S+ (\S+) \S+ \[upgradable from: ([^\]\s]+)\]$/.exec(rows[i]);
        if (m === null) return unreadable(i);
        packages.push({ name: m[1], old: m[3], new: m[2] });
    }
    return { ok: true, packages: packages };
}

// `dnf -q check-update` (dnf 4): a blank line, then `name.arch evr repo`,
// where a name longer than its column pushes the rest of the row onto the
// next line. An `Obsoleting Packages` section may follow; its packages are
// already among the upgrades.
function parseDnf(text) {
    var packages = [];
    var rows = lines(text);
    var tokens = [];
    var first = -1;
    for (var i = 0; i < rows.length; i++) {
        if (rows[i] === "Obsoleting Packages") break;
        if (!ANSI_FREE.test(rows[i])) return unreadable(i);
        var words = rows[i].trim().split(/\s+/);
        if (words.length === 1 && words[0] === "") continue;
        for (var w = 0; w < words.length; w++) {
            if (tokens.length === 0) first = i;
            tokens.push(words[w]);
            if (tokens.length < 3) continue;
            var na = /^(.+)\.[^.]+$/.exec(tokens[0]);
            if (na === null) return unreadable(first);
            packages.push({ name: na[1], old: null, new: tokens[1] });
            tokens = [];
        }
    }
    if (tokens.length > 0) return unreadable(first);
    return { ok: true, packages: packages };
}

// `dnf5 check-upgrade --json` (dnf5 5.4.0 and later): an object whose
// `upgrades` array holds `{ name, arch, evr, repository }`. The
// `obsoleting_packages` section repeats upgrades, and an empty section is
// left out.
function parseDnf5(text) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { ok: false, error: "unparseable json" };
    }
    if (doc === null || typeof doc !== "object" || Array.isArray(doc)) return { ok: false, error: "unparseable json" };
    for (var key in doc)
        if (key !== "upgrades" && key !== "obsoleting_packages") return { ok: false, error: "unparseable key=" + key };
    var list = doc.upgrades === undefined ? [] : doc.upgrades;
    if (!Array.isArray(list)) return { ok: false, error: "unparseable key=upgrades" };
    var packages = [];
    for (var i = 0; i < list.length; i++) {
        var p = list[i];
        if (p === null || typeof p !== "object" || typeof p.name !== "string" || p.name === "" || typeof p.evr !== "string" || p.evr === "")
            return { ok: false, error: "unparseable entry=" + i };
        packages.push({ name: p.name, old: null, new: p.evr });
    }
    return { ok: true, packages: packages };
}

// `flatpak remote-ls --updates --columns=application,branch`: `app<TAB>branch`,
// with no title row when stdout is not a terminal. flatpak prints no
// version here, so the branch stands for the new one.
function parseFlatpak(text) {
    var packages = [];
    var rows = lines(text);
    for (var i = 0; i < rows.length; i++) {
        var f = rows[i].split("\t");
        if (f.length !== 2 || f[0] === "" || f[1] === "" || /\s/.test(f[0] + f[1])) return unreadable(i);
        packages.push({ name: f[0], old: null, new: f[1] });
    }
    return { ok: true, packages: packages };
}

// `mise outdated --json`: an object keyed by tool, each
// `{ current, latest, ... }`, current null for a tool not yet installed.
function parseMise(text) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { ok: false, error: "unparseable json" };
    }
    if (doc === null || typeof doc !== "object" || Array.isArray(doc)) return { ok: false, error: "unparseable json" };
    var packages = [];
    for (var tool in doc) {
        var t = doc[tool];
        if (t === null || typeof t !== "object" || typeof t.latest !== "string" || (t.current !== null && typeof t.current !== "string"))
            return { ok: false, error: "unparseable tool=" + tool };
        packages.push({ name: tool, old: t.current, new: t.latest });
    }
    return { ok: true, packages: packages };
}

var PARSERS = {
    arrow: parseArrow, apt: parseApt, dnf: parseDnf, dnf5: parseDnf5,
    flatpak: parseFlatpak, mise: parseMise
};

// The update query manager ID runs with BINARY, the row's binary:
// `{ check: { argv, exits, parser, timeout } }` with "{bin}" filled in, or
// `{ skipped: "no-check" }` when the row has no query for the binary.
function checkFor(id, binary) {
    var row = managerRow(id);
    var variants = row === null || row.check === null ? [] : row.check;
    for (var i = 0; i < variants.length; i++) {
        var c = variants[i];
        if (c.binary !== null && c.binary !== binary) continue;
        var argv = c.argv.map(function (token) { return token === "{bin}" ? binary : token; });
        return { check: { argv: argv, exits: c.exits, parser: c.parser, timeout: c.timeout } };
    }
    return { skipped: "no-check" };
}

// What CHECK's run printed means: `{ packages }` or `{ error }`. STATUS is
// the exit status and STDOUT the output. A status the check does not list
// is a failure, `exit=<status>`, whatever the output holds.
function checkOutcome(check, status, stdout) {
    var meaning = check.exits[String(status)];
    if (meaning === undefined) return { error: "exit=" + status };
    if (meaning === "none") return { packages: [] };
    var parsed = PARSERS[check.parser](stdout);
    if (!parsed.ok) return { error: parsed.error };
    return { packages: parsed.packages };
}

var QUERIES = ["owner", "installed", "removable"];

// The argv of manager ID's QUERY, one of QUERIES, over VALUE: an absolute
// file path for owner, one package name for installed and removable.
// `{ ok: true, argv }` or `{ ok: false, error }`, the error the keyed first
// line of a refusal.
// "{bin}" is the binary ON_PATH resolves.
function queryArgv(id, query, value, onPath) {
    var row = managerRow(id);
    if (row === null) return { ok: false, error: "manager=" + id + " reason=unknown" };
    var spec = row[query];
    if (spec === null) return { ok: false, error: "manager=" + id + " query=" + query + " reason=unsupported" };
    var placeholder = query === "owner" ? "{path}" : "{name}";
    if (query === "owner" && (typeof value !== "string" || value.charAt(0) !== "/"))
        return { ok: false, error: "path=" + JSON.stringify(value) + " reason=relative" };
    if (query !== "owner" && !validName(value)) return { ok: false, error: "name=" + JSON.stringify(value) + " reason=grammar" };
    var needsBinary = spec.argv.indexOf("{bin}") >= 0;
    var binary = needsBinary ? binaryOf(row, onPath) : null;
    if (needsBinary && binary === null)
        return { ok: false, error: "manager=" + id + " reason=absent binaries=" + row.binaries.join(",") };
    var argv = spec.argv.map(function (token) {
        if (token === "{bin}") return binary;
        if (token === placeholder) return value;
        return token;
    });
    return { ok: true, argv: argv };
}

function pathHolds(root, file) {
    if (typeof root !== "string" || root === "" || typeof file !== "string" || file === "") return false;
    var normalized = root.charAt(root.length - 1) === "/" ? root : root + "/";
    return file === root || file.indexOf(normalized) === 0;
}

function miseToolCommand(tool) {
    var slash = tool.lastIndexOf("/");
    var colon = tool.lastIndexOf(":");
    var cut = Math.max(slash, colon);
    return cut < 0 ? tool : tool.slice(cut + 1);
}

// What manager ID's owner query printed for COMMAND_PATH and REAL_PATH,
// read as a package or tool name, or null when it names no owner. REALPATHOF
// is injected by the caller so this table stays pure. For mise,
// `install_path` roots the real executables; Unix shims are symlinks to the
// mise binary (mise shims documentation, fetched 2026-10-10), so a command
// whose real path is the mise binary is held by the installed tool whose
// name matches the shim command.
function ownerAnswer(id, stdout, commandPath, realPath, binaryPath, realpathOf) {
    var spec = managerRow(id).owner;
    if (spec === null) return null;
    if (spec.roots !== true) return queryAnswer(id, "owner", stdout);
    var doc;
    try {
        doc = JSON.parse(stdout);
    } catch (e) {
        return null;
    }
    if (doc === null || typeof doc !== "object" || Array.isArray(doc)) return null;
    if (typeof realpathOf !== "function") return null;
    var command = typeof commandPath === "string" ? commandPath.split("/").pop() : "";
    var binaryReal = realpathOf(binaryPath);
    var names = Object.keys(doc);
    for (var i = 0; i < names.length; i++) {
        var rows = doc[names[i]];
        if (!Array.isArray(rows)) return null;
        for (var j = 0; j < rows.length; j++) {
            var installPath = rows[j] !== null && typeof rows[j] === "object" ? rows[j].install_path : null;
            if (typeof installPath !== "string") return null;
            var root = realpathOf(installPath);
            if (pathHolds(root, realPath)) return names[i];
            if (binaryReal !== null && realPath === binaryReal && (names[i] === command || miseToolCommand(names[i]) === command)) return names[i];
        }
    }
    return null;
}

// What manager ID's QUERY, owner or installed, printed, read: the first
// group of its pattern in the first line of STDOUT, or null when that line
// does not match. The removable query answers by its exit status alone.
function queryAnswer(id, query, stdout) {
    var spec = managerRow(id)[query];
    if (spec.read === undefined) return null;
    var m = spec.read.exec(stdout.split("\n")[0]);
    return m === null ? null : m[1];
}
