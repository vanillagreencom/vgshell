#!/usr/bin/env node
// The package-manager table, shell/Core/PackageManagers.js (D034). Every
// expected value below was written by hand from the managers' own argv,
// never read from the table.
//
// - The shipped table is judged: unique ids, known roles and placeholders,
//   no step names an elevation command, and no pacman-family step refreshes
//   the databases without upgrading (`-Sy` alone).
// - Detection runs over os-release texts and sets of commands on PATH.
// - Plans pin each manager's argv for install, remove and upgrade, and the
//   pickers each manager's list and preview queries; a preview word holds
//   no fzf placeholder. The elevation commands, their order and the choice
//   a run makes over them are pinned; bin/vgshell-pkg's `run` and pickers are
//   scripts/test-vgshell-pkg-run.sh's.
// - packageFor picks a requirement's package for a detected system, and
//   installGroups groups the picks by manager with the arguments
//   `vgshell pkg run install` takes for each.
// - Each update parser reads the canned outputs under scripts/fixtures/pkg/
//   and inline odd lines; each manager's update query and the meaning of
//   its exit statuses are pinned. No row touches the network.
// - The owner and installed queries pin each manager's argv and read each
//   manager's output, written from its documentation, into a name or a
//   version; the removable query pins its dry-run argv.
//
// The controls at the end edit a copy of the table, one rule at a time,
// and require this suite to fail on each copy.
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const { TABLE, FIXTURES } = require("./vgshell-pkg-shared.js");
const ELEVATORS = ["sudo", "doas", "run0", "pkexec", "su"];
const PLACEHOLDERS = ["{bin}", "{names}", "{names@latest}", "{name}", "{path}"];
const NAMED = ["install", "reinstall", "update", "remove"];
const EXIT_MEANINGS = ["updates", "none", "rows"];

// The table's own defects, one string each; empty for a sound table.
function tableErrors(t) {
    const errors = [];
    if (JSON.stringify(t.managerRow("apt").engineArchive) !== JSON.stringify(["install", "--"])) errors.push("apt engine archive argv");
    if (t.managerRow("nix").engineArchive !== undefined) errors.push("Nix engine archive action");
    const ids = t.MANAGERS.map(row => row.id);
    if (t.MANAGERS.length < 7) errors.push("table: fewer than seven managers; the loader read no table");
    if (new Set(ids).size !== ids.length) errors.push("ids: not unique");
    for (const row of t.MANAGERS) {
        const where = "manager " + row.id;
        if (!["primary", "overlay", "source"].includes(row.role)) errors.push(where + ": role " + row.role);
        if ((row.role === "primary") !== (row.family.length > 0)) errors.push(where + ": a family belongs to a primary alone");
        if (row.requires !== null && !t.MANAGERS.some(o => o.id === row.requires && o.role === "primary")) errors.push(where + ": requires names no primary");
        if (row.binaries.length === 0) errors.push(where + ": no binary");
        const pacmanFamily = row.binaries.some(b => ["pacman", "paru", "yay"].includes(b));
        const templates = [];
        for (const action of t.ACTIONS) if (row[action] !== null) for (const step of row[action]) templates.push([action, step]);
        for (const query of t.QUERIES) {
            if (row[query] === null) continue;
            templates.push([query, row[query].argv]);
            if (query !== "removable" && row[query].roots !== true && Object.prototype.toString.call(row[query].read) !== "[object RegExp]") errors.push(where + " " + query + ": read is no pattern");
            if (query !== "owner" && row[query].roots === true) errors.push(where + " " + query + ": roots belongs to the owner query");
        }
        for (const action of ["install", "remove"]) {
            const spec = row.picker[action];
            if (spec === null) continue;
            templates.push(["list", spec.list], ["preview", spec.preview]);
            // fzf substitutes every brace expression in a preview string, so
            // a preview word that is no placeholder the table fills holds none.
            for (const token of spec.preview) if (!PLACEHOLDERS.includes(token) && /[{}]/.test(token)) errors.push(where + " picker " + action + ": brace in preview word " + token);
        }
        if (row.check !== null && (!Array.isArray(row.check) || row.check.length === 0)) errors.push(where + ": check is neither null nor a list of queries");
        else if (row.check !== null) row.check.forEach((c, i) => {
            const at = where + " check " + i;
            templates.push(["check", c.argv]);
            if (c.binary !== null && !row.binaries.includes(c.binary)) errors.push(at + ": binary " + c.binary + " is not one of the row's");
            if (!Object.prototype.hasOwnProperty.call(t.PARSERS, c.parser)) errors.push(at + ": parser " + c.parser);
            if (!Number.isInteger(c.timeout) || c.timeout <= 0) errors.push(at + ": timeout " + c.timeout);
            if (Object.keys(c.exits).length === 0) errors.push(at + ": no exit status");
            for (const [code, meaning] of Object.entries(c.exits))
                if (!/^[0-9]+$/.test(code) || !EXIT_MEANINGS.includes(meaning)) errors.push(at + ": exit " + code + "=" + meaning);
        });
        for (const [action, step] of templates) {
            if (step.length === 0) errors.push(where + " " + action + ": empty step");
            for (const token of step) {
                if (token.startsWith("{") && !PLACEHOLDERS.includes(token)) errors.push(where + " " + action + ": placeholder " + token);
                if (ELEVATORS.includes(token)) errors.push(where + " " + action + ": elevation command " + token);
                if (pacmanFamily && /^-[A-Za-z]*S[A-Za-z]*$/.test(token) && token.includes("y") && !token.includes("u"))
                    errors.push(where + " " + action + ": partial upgrade " + token);
            }
            const names = step.filter(token => token === "{names}" || token === "{names@latest}").length;
            if (NAMED.includes(action)) { if (names > 1) errors.push(where + " " + action + ": {names} twice"); }
            else if (names > 0) errors.push(where + " " + action + ": {names} outside install, update and remove");
            if (step.includes("{names@latest}") && action !== "update") errors.push(where + " " + action + ": {names@latest} belongs to an update");
            if (step.includes("{path}") !== (action === "owner" && row.owner.roots !== true)) errors.push(where + " " + action + ": {path} belongs to the owner query");
            if (step.includes("{name}") !== (action === "installed" || action === "removable" || action === "preview")) errors.push(where + " " + action + ": {name} belongs to the installed and removable queries and a picker's preview");
        }
        for (const action of NAMED)
            if (row[action] !== null && !row[action].some(step => step.includes("{names}") || step.includes("{names@latest}"))) errors.push(where + " " + action + ": no step takes the names");
        // PluginLogic.noticeView offers an update wherever a group installs.
        if ((row.install === null) !== (row.update === null)) errors.push(where + ": update steps belong to a row with install steps, and to no other");
    }
    return errors;
}

// Debian 14's os-release, as docker.io/library/debian:forky holds it.
const DEBIAN_14 = "PRETTY_NAME=\"Debian GNU/Linux forky/sid\"\nNAME=\"Debian GNU/Linux\"\nVERSION_CODENAME=forky\nID=debian\n";

// Detection rows: name, os-release text, the commands on PATH, the answer.
const pacman = { id: "pacman", binary: "pacman" };
const DETECT_ROWS = [
    ["Arch with paru, flatpak and mise", "NAME=\"Arch Linux\"\nID=arch\n", ["pacman", "paru", "flatpak", "mise"],
        { primary: pacman, overlays: [{ id: "aur", binary: "paru" }, { id: "flatpak", binary: "flatpak" }], sources: [{ id: "mise", binary: "mise" }] }],
    ["an Arch derivative through ID_LIKE, with yay", "ID=cachyos\nID_LIKE=arch\n", ["pacman", "yay"],
        { primary: pacman, overlays: [{ id: "aur", binary: "yay" }], sources: [] }],
    ["paru is preferred to yay", "ID=endeavouros\nID_LIKE=arch\n", ["pacman", "yay", "paru"],
        { primary: pacman, overlays: [{ id: "aur", binary: "paru" }], sources: [] }],
    ["Debian 14", DEBIAN_14, ["apt-get", "flatpak"],
        { primary: { id: "apt", binary: "apt-get" }, overlays: [{ id: "flatpak", binary: "flatpak" }], sources: [] }],
    ["Debian 13 has no primary", "ID=debian\nVERSION_ID=\"13\"\nVERSION_CODENAME=trixie\n", ["apt-get", "flatpak"],
        { primary: null, overlays: [{ id: "flatpak", binary: "flatpak" }], sources: [] }],
    ["Debian with no release field has no primary", "ID=debian\n", ["apt-get"], { primary: null, overlays: [], sources: [] }],
    ["Ubuntu has no primary", "ID=ubuntu\nID_LIKE=debian\nVERSION_ID=\"26.04\"\nVERSION_CODENAME=resolute\n", ["apt-get"], { primary: null, overlays: [], sources: [] }],
    ["a derivative of Debian 14 has no primary", "ID=acme\nID_LIKE=\"other debian\"\nVERSION_CODENAME=forky\n", ["apt-get"], { primary: null, overlays: [], sources: [] }],
    ["Fedora prefers dnf5; an AUR helper without pacman is no overlay", "ID=fedora\n", ["dnf5", "dnf", "paru"],
        { primary: { id: "dnf", binary: "dnf5" }, overlays: [], sources: [] }],
    ["a Fedora derivative with dnf alone", "ID=\"rocky\"\nID_LIKE=\"rhel centos fedora\"\n", ["dnf"],
        { primary: { id: "dnf", binary: "dnf" }, overlays: [], sources: [] }],
    ["NixOS", "ID=nixos\n", ["nix"], { primary: { id: "nix", binary: "nix" }, overlays: [], sources: [] }],
    ["a binary alone makes no primary", "ID=arch\n", ["apt-get"], { primary: null, overlays: [], sources: [] }],
    ["no os-release keeps overlays and sources", "", ["pacman", "paru", "flatpak", "mise"],
        { primary: null, overlays: [{ id: "flatpak", binary: "flatpak" }], sources: [{ id: "mise", binary: "mise" }] }],
    ["an unknown family has no primary", "ID=opensuse-tumbleweed\nID_LIKE=\"opensuse suse\"\n", ["zypper"], { primary: null, overlays: [], sources: [] }],
    ["a single-quoted ID", "ID='arch'\n", ["pacman"], { primary: pacman, overlays: [], sources: [] }],
    ["the last assignment wins; a comment assigns nothing", "# ID=fedora\nID=debian\nID=arch\n", ["pacman", "apt-get"], { primary: pacman, overlays: [], sources: [] }],
    ["a CRLF file", "ID=arch\r\nNAME=x\r\n", ["pacman"], { primary: pacman, overlays: [], sources: [] }]
];

// os-release identifier rows: name, text, the identifiers in order.
const ID_ROWS = [
    ["ID then each ID_LIKE token", "ID=a\nID_LIKE=\"b  c\"\n", ["a", "b", "c"]],
    ["an escaped quote inside double quotes", "ID=\"a\\\"b\"\n", ["a\"b"]],
    ["ID_LIKE without ID", "ID_LIKE=arch\n", ["arch"]],
    ["an empty file", "", []]
];

// Plan rows: name, manager, action, names, the commands on PATH, and the
// plan's binary, elevate and steps, or the refusal's first line.
const PLAN_ROWS = [
    ["pacman install", "pacman", "install", ["gum", "fzf"], ["pacman"], { binary: "pacman", elevate: true, steps: [["pacman", "-S", "--needed", "--", "gum", "fzf"]] }],
    ["pacman update takes the install step, which skips only an up-to-date target", "pacman", "update", ["gum"], ["pacman"], { binary: "pacman", elevate: true, steps: [["pacman", "-S", "--needed", "--", "gum"]] }],
    ["pacman reinstalls an installed package", "pacman", "reinstall", ["vgshell"], ["pacman"], { binary: "pacman", elevate: true, steps: [["pacman", "-S", "--", "vgshell"]] }],
    ["aur paru reinstalls an installed package", "aur", "reinstall", ["vgshell"], ["paru", "yay"], { binary: "paru", elevate: false, steps: [["paru", "-S", "--", "vgshell"]] }],
    ["aur yay reinstalls an installed package", "aur", "reinstall", ["vgshell"], ["yay"], { binary: "yay", elevate: false, steps: [["yay", "-S", "--", "vgshell"]] }],
    ["apt reinstalls an installed package", "apt", "reinstall", ["vgshell"], ["apt-get"], { binary: "apt-get", elevate: true, steps: [["apt-get", "install", "--reinstall", "vgshell"]] }],
    ["dnf5 reinstalls an installed package", "dnf", "reinstall", ["vgshell"], ["dnf5", "dnf"], { binary: "dnf5", elevate: true, steps: [["dnf5", "reinstall", "vgshell"]] }],
    ["dnf reinstalls an installed package", "dnf", "reinstall", ["vgshell"], ["dnf"], { binary: "dnf", elevate: true, steps: [["dnf", "reinstall", "vgshell"]] }],
    ["nix reinstall is unsupported", "nix", "reinstall", ["vgshell"], ["nix"], "manager=nix action=reinstall reason=unsupported"],
    ["flatpak reinstall is unsupported", "flatpak", "reinstall", ["vgshell"], ["flatpak"], "manager=flatpak action=reinstall reason=unsupported"],
    ["mise reinstall is unsupported", "mise", "reinstall", ["vgshell"], ["mise"], "manager=mise action=reinstall reason=unsupported"],
    ["pacman remove", "pacman", "remove", ["gum"], ["pacman"], { binary: "pacman", elevate: true, steps: [["pacman", "-Rns", "--", "gum"]] }],
    ["pacman upgrade is a full -Syu", "pacman", "upgrade", [], ["pacman"], { binary: "pacman", elevate: true, steps: [["pacman", "-Syu"]] }],
    ["aur install through paru", "aur", "install", ["gum-bin"], ["paru", "yay"], { binary: "paru", elevate: false, steps: [["paru", "-S", "--needed", "--", "gum-bin"]] }],
    ["aur install through yay", "aur", "install", ["gum-bin"], ["yay"], { binary: "yay", elevate: false, steps: [["yay", "-S", "--needed", "--", "gum-bin"]] }],
    ["aur update", "aur", "update", ["gum-bin"], ["paru"], { binary: "paru", elevate: false, steps: [["paru", "-S", "--needed", "--", "gum-bin"]] }],
    ["aur remove", "aur", "remove", ["gum-bin"], ["paru"], { binary: "paru", elevate: false, steps: [["paru", "-Rns", "--", "gum-bin"]] }],
    ["aur upgrade", "aur", "upgrade", [], ["paru"], { binary: "paru", elevate: false, steps: [["paru", "-Sua"]] }],
    ["apt install", "apt", "install", ["gum"], ["apt-get"], { binary: "apt-get", elevate: true, steps: [["apt-get", "install", "gum"]] }],
    ["apt update of a package is its install", "apt", "update", ["gum"], ["apt-get"], { binary: "apt-get", elevate: true, steps: [["apt-get", "install", "gum"]] }],
    ["apt remove", "apt", "remove", ["gum"], ["apt-get"], { binary: "apt-get", elevate: true, steps: [["apt-get", "remove", "gum"]] }],
    ["apt upgrade refreshes, then upgrades", "apt", "upgrade", [], ["apt-get"], { binary: "apt-get", elevate: true, steps: [["apt-get", "update"], ["apt-get", "full-upgrade"]] }],
    ["dnf install through dnf5", "dnf", "install", ["gum"], ["dnf5", "dnf"], { binary: "dnf5", elevate: true, steps: [["dnf5", "install", "gum"]] }],
    ["dnf update upgrades the named package", "dnf", "update", ["gum"], ["dnf"], { binary: "dnf", elevate: true, steps: [["dnf", "upgrade", "gum"]] }],
    ["dnf remove through dnf", "dnf", "remove", ["gum"], ["dnf"], { binary: "dnf", elevate: true, steps: [["dnf", "remove", "gum"]] }],
    ["dnf upgrade", "dnf", "upgrade", [], ["dnf"], { binary: "dnf", elevate: true, steps: [["dnf", "upgrade"]] }],
    ["flatpak install", "flatpak", "install", ["org.gnome.Loupe"], ["flatpak"], { binary: "flatpak", elevate: false, steps: [["flatpak", "install", "org.gnome.Loupe"]] }],
    ["flatpak update of one ref", "flatpak", "update", ["org.gnome.Loupe"], ["flatpak"], { binary: "flatpak", elevate: false, steps: [["flatpak", "update", "org.gnome.Loupe"]] }],
    ["flatpak remove", "flatpak", "remove", ["org.gnome.Loupe"], ["flatpak"], { binary: "flatpak", elevate: false, steps: [["flatpak", "uninstall", "org.gnome.Loupe"]] }],
    ["flatpak upgrade", "flatpak", "upgrade", [], ["flatpak"], { binary: "flatpak", elevate: false, steps: [["flatpak", "update"]] }],
    ["mise install", "mise", "install", ["npm:@anthropic-ai/claude-code"], ["mise"], { binary: "mise", elevate: false, steps: [["mise", "use", "--global", "npm:@anthropic-ai/claude-code"]] }],
    ["mise update names the latest version of each tool and waives the release-age cooldown", "mise", "update", ["pi", "npm:agent-browser"], ["mise"], { binary: "mise", elevate: false, steps: [["env", "MISE_MINIMUM_RELEASE_AGE=0", "mise", "use", "--global", "pi@latest", "npm:agent-browser@latest"]] }],
    ["mise remove", "mise", "remove", ["node"], ["mise"], { binary: "mise", elevate: false, steps: [["mise", "unuse", "--global", "node"]] }],
    ["mise upgrade waives the release-age cooldown", "mise", "upgrade", [], ["mise"], { binary: "mise", elevate: false, steps: [["env", "MISE_MINIMUM_RELEASE_AGE=0", "mise", "upgrade"]] }],
    ["nix install is unsupported", "nix", "install", ["gum"], ["nix"], "manager=nix action=install reason=unsupported"],
    ["nix update is unsupported", "nix", "update", ["gum"], ["nix"], "manager=nix action=update reason=unsupported"],
    ["nix remove is unsupported", "nix", "remove", ["gum"], ["nix"], "manager=nix action=remove reason=unsupported"],
    ["nix upgrade is unsupported", "nix", "upgrade", [], ["nix"], "manager=nix action=upgrade reason=unsupported"],
    ["an unknown manager", "zypper", "install", ["gum"], ["zypper"], "manager=zypper reason=unknown"],
    ["a manager whose binary is absent", "dnf", "install", ["gum"], [], "manager=dnf reason=absent binaries=dnf5,dnf"],
    ["a name that starts with a dash", "pacman", "install", ["-Sy"], ["pacman"], "name=\"-Sy\" reason=grammar"],
    ["a name with a space", "pacman", "install", ["gum fzf"], ["pacman"], "name=\"gum fzf\" reason=grammar"],
    ["an empty name", "pacman", "install", [""], ["pacman"], "name=\"\" reason=grammar"],
    ["a name past 256 characters", "pacman", "install", ["a".repeat(257)], ["pacman"], "name=\"" + "a".repeat(257) + "\" reason=grammar"]
];

// Upgrade rows that keep packages out: name, manager, the packages kept
// out, the commands on PATH, and the plan's steps or the refusal. Every
// manager with upgrade steps and no row here must refuse a kept package
// (verifyTable reads the managers from the table).
const IGNORE_ROWS = [
    ["pacman keeps two packages out of -Syu", "pacman", ["foo", "bar"], ["pacman"], [["pacman", "-Syu", "--ignore", "foo", "--ignore", "bar"]]],
    ["paru keeps an AUR package out of -Sua", "aur", ["tool-bin"], ["paru"], [["paru", "-Sua", "--ignore", "tool-bin"]]],
    ["yay keeps an AUR package out of -Sua", "aur", ["tool-bin"], ["yay"], [["yay", "-Sua", "--ignore", "tool-bin"]]],
    ["no package kept out leaves the upgrade as it is", "pacman", [], ["pacman"], [["pacman", "-Syu"]]],
    ["a kept package that starts with a dash", "pacman", ["-Sy"], ["pacman"], "name=\"-Sy\" reason=grammar"],
    ["apt keeps no package out", "apt", ["foo"], ["apt-get"], "manager=apt option=ignore reason=unsupported"]
];

// planOwed rows: name, manager, the missing packages, the outdated ones,
// the commands on PATH, and the plan's steps or the refusal. A row whose
// install and update steps are the same takes both lists in one step; any
// other installs first, then updates.
const OWED_ROWS = [
    ["pacman installs and updates in one step", "pacman", ["gum"], ["pi"], ["pacman"], [["pacman", "-S", "--needed", "--", "pi", "gum"]]],
    ["paru installs and updates in one step", "aur", ["gum-git"], ["pi-bin"], ["paru"], [["paru", "-S", "--needed", "--", "pi-bin", "gum-git"]]],
    ["dnf installs, then upgrades", "dnf", ["gum"], ["pi"], ["dnf"], [["dnf", "install", "gum"], ["dnf", "upgrade", "pi"]]],
    ["mise installs, then names the latest version of the outdated tool", "mise", ["node"], ["pi"], ["mise"], [["mise", "use", "--global", "node"], ["env", "MISE_MINIMUM_RELEASE_AGE=0", "mise", "use", "--global", "pi@latest"]]],
    ["nix plans neither", "nix", ["gum"], ["pi"], ["nix"], "manager=nix action=install reason=unsupported"],
    ["an unknown manager", "zypper", ["gum"], ["pi"], ["zypper"], "manager=zypper reason=unknown"],
    ["a missing name that starts with a dash", "pacman", ["-Sy"], ["pi"], ["pacman"], "name=\"-Sy\" reason=grammar"],
    ["an outdated name that starts with a dash, after an install step", "dnf", ["gum"], ["-y"], ["dnf"], "name=\"-y\" reason=grammar"]
];

// pickerFor rows: name, manager, action, the commands on PATH, `{ list,
// preview }` or the refusal.
const PICKER_ROWS = [
    ["pacman install lists the sync databases", "pacman", "install", ["pacman"], { list: ["pacman", "-Slq"], preview: ["pacman", "-Sii", "{name}"] }],
    ["pacman remove lists the explicit packages", "pacman", "remove", ["pacman"], { list: ["pacman", "-Qqe"], preview: ["pacman", "-Qi", "{name}"] }],
    ["aur install through the helper", "aur", "install", ["yay"], { list: ["yay", "-Slqa"], preview: ["yay", "-Siia", "{name}"] }],
    ["aur remove is pacman's", "aur", "remove", ["paru"], "manager=aur picker=remove reason=unsupported"],
    ["apt install", "apt", "install", ["apt-get"], { list: ["apt-cache", "pkgnames"], preview: ["apt-cache", "show", "{name}"] }],
    ["apt remove lists the manual packages", "apt", "remove", ["apt-get"], { list: ["apt-mark", "showmanual"], preview: ["dpkg", "-s", "{name}"] }],
    ["dnf install", "dnf", "install", ["dnf5"], { list: ["dnf5", "-q", "repoquery", "--available", "--queryformat", "%{name}\\n"], preview: ["dnf5", "info", "{name}"] }],
    ["dnf remove lists the user's packages", "dnf", "remove", ["dnf"], { list: ["dnf", "-q", "repoquery", "--userinstalled", "--queryformat", "%{name}\\n"], preview: ["rpm", "-qi", "{name}"] }],
    ["flatpak offers no picker", "flatpak", "install", ["flatpak"], "manager=flatpak picker=install reason=unsupported"],
    ["an absent manager", "pacman", "install", [], "manager=pacman reason=absent binaries=pacman"]
];

// elevator rows: name, packages.elevate or undefined, the commands on PATH,
// `{ ok: true, command }` or the refusal.
const ELEVATOR_ROWS = [
    ["sudo first", undefined, ["run0", "doas", "sudo"], "sudo"],
    ["doas without sudo", undefined, ["run0", "doas"], "doas"],
    ["run0 alone", undefined, ["run0"], "run0"],
    ["none found", undefined, ["pkexec", "su"], "elevate=none candidates=sudo,doas,run0"],
    ["the configured command over sudo", "run0", ["sudo", "run0"], "run0"],
    ["a configured command that is absent", "doas", ["sudo"], "elevate=doas reason=absent source=packages.elevate"]
];

// packageFor rows: name, a requirement's packages, detect's answer, the pick.
const PACMAN = { id: "pacman", binary: "pacman" };
const PARU = { id: "aur", binary: "paru" };
const MISE = { id: "mise", binary: "mise" };
const PACKAGE_FOR_ROWS = [
    ["the primary's package wins over an overlay's", { aur: "gum-bin", pacman: "gum" }, { primary: PACMAN, overlays: [PARU], sources: [] }, { manager: "pacman", name: "gum" }],
    ["an overlay serves what the primary does not map", { aur: "vsys" }, { primary: PACMAN, overlays: [PARU], sources: [] }, { manager: "aur", name: "vsys" }],
    ["an overlay wins over a source", { mise: "node", aur: "nodejs-bin" }, { primary: PACMAN, overlays: [PARU], sources: [MISE] }, { manager: "aur", name: "nodejs-bin" }],
    ["a source serves last", { mise: "node" }, { primary: PACMAN, overlays: [], sources: [MISE] }, { manager: "mise", name: "node" }],
    ["an overlay serves a system with no primary", { flatpak: "org.gnome.Loupe" }, { primary: null, overlays: [{ id: "flatpak", binary: "flatpak" }], sources: [] }, { manager: "flatpak", name: "org.gnome.Loupe" }],
    ["a source holding the command wins over the first listed manager", { pacman: "agent-browser-bin", mise: "npm:agent-browser" }, { primary: PACMAN, overlays: [PARU], sources: [MISE] }, { manager: "mise", name: "npm:agent-browser" }, { path: "/home/method/.local/bin/agent-browser", owners: { pacman: null, mise: "npm:agent-browser" } }],
    ["a holder with another package name does not win", { pacman: "agent-browser-bin", mise: "npm:agent-browser" }, { primary: PACMAN, overlays: [PARU], sources: [MISE] }, { manager: "pacman", name: "agent-browser-bin" }, { path: "/home/method/.local/bin/agent-browser", owners: { pacman: null, mise: "other-tool" } }],
    ["an AUR package holding the command wins over the primary", { pacman: "tool", aur: "tool-bin" }, { primary: PACMAN, overlays: [PARU], sources: [] }, { manager: "aur", name: "tool-bin" }, { path: "/usr/bin/tool", owners: { pacman: null, aur: "tool-bin" } }],
    ["a command no listed manager holds keeps the first listed package", { pacman: "tool", mise: "tool" }, { primary: PACMAN, overlays: [], sources: [MISE] }, { manager: "pacman", name: "tool" }, { path: "/opt/tool/bin/tool", owners: { pacman: null, mise: null } }],
    ["no present manager is mapped", { apt: "gum", dnf: "gum" }, { primary: PACMAN, overlays: [PARU], sources: [] }, null],
    ["no package is mapped at all", {}, { primary: PACMAN, overlays: [], sources: [] }, null]
];

// installGroups rows: name, the rows' packages, detect's answer, the picks
// as manager/name or null, then each group as [manager, primary, names,
// installs, the arguments after `vgshell pkg run install` or null].
const NIX = { id: "nix", binary: "nix" };
const FLATPAK = { id: "flatpak", binary: "flatpak" };
const INSTALL_GROUP_ROWS = [
    ["one primary package", [{ pacman: "gum" }], { primary: PACMAN, overlays: [PARU], sources: [] },
        ["pacman/gum"], [["pacman", true, ["gum"], true, ["gum"]]]],
    ["an overlay's install names its manager, after the primary's", [{ aur: "vsys" }, { pacman: "gum" }], { primary: PACMAN, overlays: [PARU], sources: [] },
        ["aur/vsys", "pacman/gum"], [["pacman", true, ["gum"], true, ["gum"]], ["aur", false, ["vsys"], true, ["--manager", "aur", "vsys"]]]],
    ["a package two commands share is installed once", [{ pacman: "coreutils" }, { pacman: "coreutils" }, { pacman: "gum" }], { primary: PACMAN, overlays: [], sources: [] },
        ["pacman/coreutils", "pacman/coreutils", "pacman/gum"], [["pacman", true, ["coreutils", "gum"], true, ["coreutils", "gum"]]]],
    ["a source comes after the overlays", [{ mise: "node" }, { aur: "vsys" }], { primary: PACMAN, overlays: [PARU], sources: [MISE] },
        ["mise/node", "aur/vsys"], [["aur", false, ["vsys"], true, ["--manager", "aur", "vsys"]], ["mise", false, ["node"], true, ["--manager", "mise", "node"]]]],
    ["a held source updates through its own manager", [{ pacman: "agent-browser-bin", mise: "npm:agent-browser" }], { primary: PACMAN, overlays: [PARU], sources: [MISE], holders: { "agent-browser": { path: "/home/method/.local/bin/agent-browser", owners: { pacman: null, mise: "npm:agent-browser" } } } },
        ["mise/npm:agent-browser"], [["mise", false, ["npm:agent-browser"], true, ["--manager", "mise", "npm:agent-browser"]]], ["agent-browser"]],
    ["a held AUR package updates through the overlay", [{ pacman: "vgs-smoke-old-pkg", aur: "vgs-smoke-old-aur" }], { primary: PACMAN, overlays: [PARU], sources: [], holders: { "vgs-smoke-old": { path: "/usr/bin/vgs-smoke-old", owners: { pacman: null, aur: "vgs-smoke-old-aur" } } } },
        ["aur/vgs-smoke-old-aur"], [["aur", false, ["vgs-smoke-old-aur"], true, ["--manager", "aur", "vgs-smoke-old-aur"]]], ["vgs-smoke-old"]],
    ["a row no present manager maps is picked by none", [{ apt: "gum" }, { pacman: "fzf" }], { primary: PACMAN, overlays: [], sources: [] },
        [null, "pacman/fzf"], [["pacman", true, ["fzf"], true, ["fzf"]]]],
    ["nix installs nothing through vgshell", [{ nix: "gum" }, { flatpak: "org.flat" }], { primary: NIX, overlays: [FLATPAK], sources: [] },
        ["nix/gum", "flatpak/org.flat"], [["nix", true, ["gum"], false, null], ["flatpak", false, ["org.flat"], true, ["--manager", "flatpak", "org.flat"]]]],
    ["no row", [], { primary: PACMAN, overlays: [], sources: [] }, [], []]
];

// Parser rows: name, parser, the text (a string, or { fixture } under
// scripts/fixtures/pkg/), and the packages as [name, old, new] or the
// parser's error. Fixture origins: checkupdates, paru and mise were captured
// from the real commands on CachyOS on 2026-09-28; the others are written
// from the format each tool's own source prints: yay print.go
// printUpdateList and text FormatAgeTag, apt apt-private private-list.cc and
// private-output.cc ListSingleVersion, dnf 4 dnf/cli/output.py fmtColumns
// and cli.py check_updates, dnf5 libdnf5-cli package_list_sections.cpp
// print_json, flatpak app/flatpak-table-printer.c.
const fixture = name => ({ fixture: name });
const PARSE_ROWS = [
    ["checkupdates", "arrow", fixture("checkupdates.txt"), [["bpf", "7.2.7-1", "7.2.8-1"], ["coreutils", "9.11-2.1", "9.12-2.1"],
        ["python-cattrs", "26.2.0-1", "26.2.1-1"], ["python-dbus", "1.4.0-2", "1.5.0-1"], ["shellcheck", "0.11.0-140", "0.11.0-142"],
        ["sunshine", "2026.922.203725-1", "2026.928.163558-1"]]],
    ["paru's devel update", "arrow", fixture("paru.txt"), [["kendex-git", "1:r1621.bf9bed514-1", "latest-commit"]]],
    ["yay's age tags", "arrow", fixture("yay.txt"), [["yay", "12.4.2-1", "12.5.0-1"], ["go-task-bin", "3.40.0-1", "3.41.0-1"], ["zen-browser-bin", "1.7b-1", "1.8b-1"]]],
    ["arrow: no output", "arrow", "", []],
    ["arrow: an ignored package is not counted", "arrow", "linux 6.9-1 -> 6.10-1 [ignored]\nbash 5.2-1 -> 5.3-1\n", [["bash", "5.2-1", "5.3-1"]]],
    ["arrow: an unknown tag", "arrow", "bash 5.2-1 -> 5.3-1 [soon]\n", "unparseable line=1"],
    ["arrow: an error line", "arrow", "bash 5.2-1 -> 5.3-1\nerror: failed to synchronize all databases\n", "unparseable line=2"],
    ["arrow: a coloured line", "arrow", "\u001b[1mbash\u001b[0m 5.2-1 -> 5.3-1\n", "unparseable line=1"],
    ["arrow: no arrow", "arrow", "bash 5.2-1 5.3-1\n", "unparseable line=1"],
    ["apt", "apt", fixture("apt.txt"), [["bash", "5.3-4", "5.3-5"], ["libssl3t64", "3.6.2-1", "3.6.2-2"]]],
    ["apt: the progress line alone", "apt", "Listing... Done\n", []],
    ["apt: its CLI warning on stdout", "apt", "Listing...\nWARNING: apt does not have a stable CLI interface. Use with caution in scripts.\n", "unparseable line=2"],
    ["apt: an installed package", "apt", "Listing...\nbash/now 5.2 amd64 [installed,local]\n", "unparseable line=2"],
    ["dnf 4, a long name wrapped and the obsoletes left out", "dnf", fixture("dnf.txt"), [["bash", null, "5.2.26-3.fc40"],
        ["python3-sphinxcontrib-applehelp-doc-extra", null, "2.0.0-1.fc40"], ["dnf-plugins-core", null, "4.9.0-1.fc40"]]],
    ["dnf 4: no output", "dnf", "", []],
    ["dnf 4: the blank line alone", "dnf", "\n", []],
    ["dnf 4: the metadata notice -q removes", "dnf", "Last metadata expiration check: 0:01:02 ago on Mon 28 Sep 2026.\n\nbash.x86_64 5.2-1.fc40 updates\n", "unparseable line=1"],
    ["dnf 4: a row cut short", "dnf", "\nbash.x86_64 5.2-1.fc40\n", "unparseable line=2"],
    ["dnf5 JSON, the obsoletes left out", "dnf5", fixture("dnf5.json"), [["bash", null, "5.3.0-2.fc44"], ["dnf5", null, "5.4.6.0-1.fc44"]]],
    ["dnf5: no section", "dnf5", "{}\n", []],
    ["dnf5: text before the JSON", "dnf5", "Updating and loading repositories:\n{}\n", "unparseable json"],
    ["dnf5: an unknown section", "dnf5", "{\"upgradeable_packages\":[]}\n", "unparseable key=upgradeable_packages"],
    ["dnf5: an entry without a version", "dnf5", "{\"upgrades\":[{\"name\":\"bash\",\"arch\":\"x86_64\"}]}\n", "unparseable entry=0"],
    ["flatpak", "flatpak", fixture("flatpak.txt"), [["org.gnome.Loupe", null, "stable"], ["org.gnome.Platform", null, "47"], ["org.freedesktop.Platform.GL.default", null, "24.08"]]],
    ["flatpak: no output", "flatpak", "", []],
    ["flatpak: a title row", "flatpak", "Application ID\tBranch\n", "unparseable line=1"],
    ["flatpak: a third column", "flatpak", "org.gnome.Loupe\tstable\tflathub\n", "unparseable line=1"],
    ["mise", "mise", fixture("mise.json"), [["aqua:google-antigravity/antigravity-cli", "1.2.11", "1.2.12"], ["claude", "2.1.283", "2.1.284"], ["npm:vercel", "60.1.1", "60.1.3"]]],
    ["mise: nothing outdated", "mise", "{}\n", []],
    ["mise: a tool not yet installed", "mise", "{\"node\":{\"current\":null,\"latest\":\"22.1.0\"}}\n", [["node", null, "22.1.0"]]],
    ["mise: a tool without a latest version", "mise", "{\"node\":{\"current\":\"22.0.0\"}}\n", "unparseable tool=node"],
    ["mise: an array", "mise", "[]\n", "unparseable json"]
];

// Query rows: name, manager, binary, and the query or why it is skipped.
const q = (argv, exits, parser, timeout) => ({ check: { argv, exits, parser, timeout } });
const ROWS = { "0": "rows" };
const CHECK_ROWS = [
    ["pacman runs checkupdates", "pacman", "pacman", q(["checkupdates"], { "0": "updates", "2": "none" }, "arrow", 120)],
    ["aur runs its helper", "aur", "yay", { ...q(["yay", "-Qua"], { "0": "updates", "1": "none" }, "arrow", 120), origin: "aur" }],
    ["apt lists the upgradable packages", "apt", "apt-get", q(["apt", "list", "--upgradable"], ROWS, "apt", 120)],
    ["dnf5 answers in JSON", "dnf", "dnf5", q(["dnf5", "check-upgrade", "--json"], ROWS, "dnf5", 120)],
    ["dnf 4 answers in columns", "dnf", "dnf", q(["dnf", "-q", "check-update"], { "0": "none", "100": "updates" }, "dnf", 120)],
    ["nix has no query", "nix", "nix", { skipped: "no-check" }],
    ["flatpak lists its updates", "flatpak", "flatpak", q(["flatpak", "remote-ls", "--updates", "--columns=application,branch"], ROWS, "flatpak", 120)],
    ["mise waives the release-age cooldown", "mise", "mise", q(["env", "MISE_MINIMUM_RELEASE_AGE=0", "mise", "outdated", "--json"], ROWS, "mise", 120)]
];

// Outcome rows: name, manager, binary, exit status, stdout, and the
// packages as [name, old, new] or the check's error, then stderr.
const OUTCOME_ROWS = [
    ["checkupdates 2 is none", "pacman", "pacman", 2, "", []],
    ["checkupdates 1 is a failure", "pacman", "pacman", 1, "", "exit=1"],
    ["checkupdates 0 reads the rows", "pacman", "pacman", 0, "bpf 7.2.7-1 -> 7.2.8-1\n", [["bpf", "7.2.7-1", "7.2.8-1"]]],
    ["yay 1 is none", "aur", "yay", 1, "", []],
    ["paru 1 without diagnostics is none", "aur", "paru", 1, "", [], ""],
    ["paru 1 with a failed request is an error", "aur", "paru", 1, "", "exit=1 stderr=error: failed to get aur packages", "error: failed to get aur packages\n"],
    ["yay 1 with a failed request is an error", "aur", "yay", 1, "", "exit=1 stderr=Get https://aur.archlinux.org/rpc: network is unreachable", "Get https://aur.archlinux.org/rpc: network is unreachable\n"],
    ["an unlisted failure retains its diagnostic", "aur", "paru", 2, "", "exit=2 stderr=error: failed to initialize alpm library", "error: failed to initialize alpm library\n"],
    ["a successful probe can print warnings", "aur", "paru", 0, "tool 1 -> 2\n", [["tool", "1", "2"]], "warning: tool is orphaned\n"],
    ["dnf 100 reads the rows", "dnf", "dnf", 100, "\nbash.x86_64 5.2-1.fc40 updates\n", [["bash", null, "5.2-1.fc40"]]],
    ["dnf 0 is none", "dnf", "dnf", 0, "", []],
    ["dnf 1 is a failure", "dnf", "dnf", 1, "", "exit=1"],
    ["dnf5's JSON query never exits 100", "dnf", "dnf5", 100, "{}\n", "exit=100"],
    ["dnf5 before 5.4.0 refuses --json with 2", "dnf", "dnf5", 2, "", "exit=2"],
    ["an unreadable line fails the check", "flatpak", "flatpak", 0, "Application ID\tBranch\n", "unparseable line=1"],
    ["flatpak 1 is a failure", "flatpak", "flatpak", 1, "", "exit=1"]
];

// Query rows: name, manager, query, the value, the commands on PATH, and
// the argv, or the refusal's first line.
const QUERY_ROWS = [
    ["pacman owner", "pacman", "owner", "/usr/share/vgshell/VERSION", ["pacman"], ["pacman", "-Qoq", "/usr/share/vgshell/VERSION"]],
    ["pacman installed", "pacman", "installed", "vgshell-git", ["pacman"], ["pacman", "-Q", "--", "vgshell-git"]],
    ["apt owner through dpkg", "apt", "owner", "/usr/share/vgshell/VERSION", ["apt-get"], ["dpkg", "-S", "/usr/share/vgshell/VERSION"]],
    ["apt installed through dpkg-query", "apt", "installed", "vgshell", ["apt-get"], ["dpkg-query", "-W", "--showformat=${Version}\n", "--", "vgshell"]],
    ["dnf owner through rpm names the package alone", "dnf", "owner", "/usr/share/vgshell/VERSION", ["dnf5"], ["rpm", "-qf", "--queryformat", "%{NAME}\n", "/usr/share/vgshell/VERSION"]],
    ["dnf installed through rpm", "dnf", "installed", "vgshell", ["dnf5"], ["rpm", "-q", "--queryformat", "%{VERSION}\n", "--", "vgshell"]],
    ["aur owner through pacman", "aur", "owner", "/usr/share/vgshell/VERSION", ["paru"], ["pacman", "-Qoq", "/usr/share/vgshell/VERSION"]],
    ["mise owner lists every installed tool", "mise", "owner", "/home/method/.local/bin/tool", ["mise"], ["mise", "ls", "--installed", "--json"]],
    ["pacman removable is a dry run of the removal", "pacman", "removable", "vgshell-git", ["pacman"], ["pacman", "-Rs", "--print", "--", "vgshell-git"]],
    ["apt asks no removable query", "apt", "removable", "vgshell", ["apt-get"], "manager=apt query=removable reason=unsupported"],
    ["a removable name keeps the name grammar", "pacman", "removable", "-Rdd", ["pacman"], "name=\"-Rdd\" reason=grammar"],
    ["aur asks no installed query", "aur", "installed", "vgshell", ["paru"], "manager=aur query=installed reason=unsupported"],
    ["aur still needs no helper binary for its owner query", "aur", "owner", "/usr/share/vgshell/VERSION", [], ["pacman", "-Qoq", "/usr/share/vgshell/VERSION"]],
    ["an owner path must be absolute", "pacman", "owner", "VERSION", ["pacman"], "path=\"VERSION\" reason=relative"],
    ["an installed name keeps the name grammar", "pacman", "installed", "-Qi", ["pacman"], "name=\"-Qi\" reason=grammar"],
    ["a query whose binary is absent", "pacman", "owner", "/usr/share/vgshell/VERSION", [], "manager=pacman reason=absent binaries=pacman"]
];

// Answer rows: name, manager, query, what the query printed, the answer.
const ANSWER_ROWS = [
    ["pacman -Qoq prints the name", "pacman", "owner", "vgshell-git\n", "vgshell-git"],
    ["pacman -Q drops the epoch and the pkgrel", "pacman", "installed", "vgshell-git 1:0.1.0.r40.gabc1234-2\n", "0.1.0.r40.gabc1234"],
    ["pacman -Q without an epoch", "pacman", "installed", "vgshell 0.1.0-1\n", "0.1.0"],
    ["dpkg -S names the package before its colon", "apt", "owner", "vgshell: /usr/share/vgshell/VERSION\n", "vgshell"],
    ["dpkg -S with an architecture qualifier", "apt", "owner", "vgshell:amd64: /usr/share/vgshell/VERSION\n", "vgshell"],
    ["a Debian version drops the epoch and the revision", "apt", "installed", "1:0.1.0-3\n", "0.1.0"],
    ["a Debian upstream version may hold a dash", "apt", "installed", "1.2-3-1\n", "1.2-3"],
    ["a native Debian version has no revision", "apt", "installed", "0.1.0\n", "0.1.0"],
    ["rpm prints the name", "dnf", "owner", "vgshell\n", "vgshell"],
    ["rpm prints the version", "dnf", "installed", "0.1.0^40.gitabc1234\n", "0.1.0^40.gitabc1234"],
    ["a message is no answer", "pacman", "owner", "error: No package owns /x\n", null],
    ["the first line alone is read", "pacman", "installed", "\nvgs 0.1.0-1\n", null]
];

// Owner answer rows for a roots owner: name, manager, stdout, command path,
// real path, binary path, the realpath map, and answer.
const OWNER_ANSWER_ROWS = [
    ["mise install root holds the real command path", "mise", JSON.stringify({ "npm:agent-browser": [{ install_path: "/mise/installs/npm-agent-browser/0.38.2" }] }), "/mise/installs/npm-agent-browser/latest/bin/agent-browser", "/mise/installs/npm-agent-browser/0.38.2/bin/agent-browser", "/usr/bin/mise", {}, "npm:agent-browser"],
    ["mise realpaths a symlinked latest directory", "mise", JSON.stringify({ "npm:agent-browser": [{ install_path: "/mise/installs/npm-agent-browser/latest" }] }), "/mise/installs/npm-agent-browser/latest/bin/agent-browser", "/mise/installs/npm-agent-browser/0.38.2/bin/agent-browser", "/usr/bin/mise", { "/mise/installs/npm-agent-browser/latest": "/mise/installs/npm-agent-browser/0.38.2" }, "npm:agent-browser"],
    ["mise roots do not hold an outside command", "mise", JSON.stringify({ "npm:agent-browser": [{ install_path: "/mise/installs/npm-agent-browser/0.38.2" }] }), "/home/method/.local/bin/agent-browser", "/home/method/.local/bin/agent-browser", "/usr/bin/mise", {}, null],
    ["mise malformed JSON owns nothing", "mise", "[]", "/mise/installs/npm-agent-browser/0.38.2/bin/agent-browser", "/mise/installs/npm-agent-browser/0.38.2/bin/agent-browser", "/usr/bin/mise", {}, null],
    ["a Unix mise shim is owned by the matching tool", "mise", JSON.stringify({ "npm:agent-browser": [{ install_path: "/mise/installs/npm-agent-browser/0.38.2" }] }), "/home/method/.local/share/mise/shims/agent-browser", "/usr/bin/mise", "/usr/bin/mise", {}, "npm:agent-browser"]
];

const realpathOf = map => file => Object.prototype.hasOwnProperty.call(map, file) ? map[file] : file;

const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const triples = packages => packages.map(p => [p.name, p.old, p.new]);

function verifyTable(t) {
    const failures = tableErrors(t);
    const onPathOf = list => command => list.includes(command);
    for (const [name, text, commands, want] of DETECT_ROWS) {
        const got = t.detect(text, onPathOf(commands));
        if (!same(got, want)) failures.push("detect: " + name + ": got " + JSON.stringify(got));
    }
    for (const [name, text, want] of ID_ROWS) {
        const got = t.osReleaseIds(text);
        if (!same(got, want)) failures.push("os-release: " + name + ": got " + JSON.stringify(got));
    }
    const covered = new Set();
    for (const [name, manager, action, names, commands, want] of PLAN_ROWS) {
        const got = t.plan(manager, action, names, onPathOf(commands));
        const expected = typeof want === "string" ? { ok: false, error: want } : { ok: true, plan: { manager, binary: want.binary, action, elevate: want.elevate, steps: want.steps } };
        if (!same(got, expected)) failures.push("plan: " + name + ": got " + JSON.stringify(got));
        covered.add(manager + " " + action);
    }
    for (const row of t.MANAGERS) for (const action of t.ACTIONS)
        if (!covered.has(row.id + " " + action)) failures.push("plan: no row for " + row.id + " " + action);
    for (const [name, manager, missing, outdated, commands, want] of OWED_ROWS) {
        const got = t.planOwed(manager, missing, outdated, onPathOf(commands));
        const steps = got.ok ? got.plan.steps : got.error;
        if (!same(steps, want)) failures.push("owed: " + name + ": got " + JSON.stringify(got));
    }
    const ignoring = new Set();
    for (const [name, manager, ignored, commands, want] of IGNORE_ROWS) {
        const got = t.plan(manager, "upgrade", [], onPathOf(commands), ignored);
        const binary = commands[0];
        const expected = typeof want === "string" ? { ok: false, error: want } : { ok: true, plan: { manager, binary, action: "upgrade", elevate: manager === "pacman", steps: want } };
        if (!same(got, expected)) failures.push("ignore: " + name + ": got " + JSON.stringify(got));
        if (typeof want !== "string" && ignored.length > 0) ignoring.add(manager);
    }
    for (const required of ["pacman", "aur"]) if (!ignoring.has(required)) failures.push("ignore: no row keeps a package out of a " + required + " upgrade");
    for (const row of t.MANAGERS) {
        if (row.upgrade === null || ignoring.has(row.id)) continue;
        const got = t.plan(row.id, "upgrade", [], () => true, ["foo"]);
        if (!same(got, { ok: false, error: "manager=" + row.id + " option=ignore reason=unsupported" })) failures.push("ignore: " + row.id + " keeps a package out: got " + JSON.stringify(got));
    }
    const queried = new Set();
    for (const [name, manager, query, value, commands, want] of QUERY_ROWS) {
        const got = t.queryArgv(manager, query, value, onPathOf(commands));
        const expected = typeof want === "string" ? { ok: false, error: want } : { ok: true, argv: want };
        if (!same(got, expected)) failures.push("query: " + name + ": got " + JSON.stringify(got));
        queried.add(manager + " " + query);
    }
    for (const row of t.MANAGERS) for (const query of t.QUERIES)
        if (row[query] !== null && !queried.has(row.id + " " + query)) failures.push("query: no row for " + row.id + " " + query);
    for (const [name, manager, query, stdout, want] of ANSWER_ROWS) {
        const got = t.queryAnswer(manager, query, stdout);
        if (got !== want) failures.push("answer: " + name + ": got " + JSON.stringify(got));
    }
    for (const [name, manager, stdout, commandPath, realPath, binaryPath, map, want] of OWNER_ANSWER_ROWS) {
        const got = t.ownerAnswer(manager, stdout, commandPath, realPath, binaryPath, realpathOf(map));
        if (got !== want) failures.push("ownerAnswer: " + name + ": got " + JSON.stringify(got));
    }
    for (const [name, manager, action, commands, want] of PICKER_ROWS) {
        const got = t.pickerFor(manager, action, onPathOf(commands));
        const expected = typeof want === "string" ? { ok: false, error: want } : Object.assign({ ok: true }, want);
        if (!same(got, expected)) failures.push("picker: " + name + ": got " + JSON.stringify(got));
    }
    if (!same(t.ELEVATORS, ["sudo", "doas", "run0"])) failures.push("elevators: got " + JSON.stringify(t.ELEVATORS));
    for (const [name, configured, commands, want] of ELEVATOR_ROWS) {
        const got = t.elevator(configured, onPathOf(commands));
        const expected = want.includes("=") ? { ok: false, error: want } : { ok: true, command: want };
        if (!same(got, expected)) failures.push("elevator: " + name + ": got " + JSON.stringify(got));
    }
    for (const [name, packages, found, want, holder] of PACKAGE_FOR_ROWS) {
        const got = t.packageFor(packages, found, holder);
        if (!same(got, want)) failures.push("packageFor: " + name + ": got " + JSON.stringify(got));
    }
    for (const [name, rows, found, picks, groups, names] of INSTALL_GROUP_ROWS) {
        const plan = t.installGroups(rows.map((packages, index) => ({ packages, name: names === undefined ? undefined : names[index] })), found);
        const gotPicks = plan.picks.map(p => p === null ? null : p.manager + "/" + p.name);
        const gotGroups = plan.groups.map(g => [g.manager, g.primary, g.names, g.installs, g.installs ? t.installArgs(g) : null]);
        if (!same(gotPicks, picks)) failures.push("installGroups: " + name + ": picks " + JSON.stringify(gotPicks));
        if (!same(gotGroups, groups)) failures.push("installGroups: " + name + ": groups " + JSON.stringify(gotGroups));
    }
    const refusal = (() => { try { t.installArgs({ manager: "nix", primary: true, names: ["gum"], installs: false }); return "answered"; } catch (e) { return e.message; } })();
    if (refusal !== "installArgs: manager nix has no install steps") failures.push("installArgs: a manager without install steps: got " + JSON.stringify(refusal));

    const parsed = new Set();
    for (const [name, parser, input, want] of PARSE_ROWS) {
        const text = typeof input === "string" ? input : fs.readFileSync(path.join(FIXTURES, input.fixture), "utf8");
        const r = t.PARSERS[parser](text);
        const got = r.ok ? triples(r.packages) : r.error;
        if (!same(got, want)) failures.push("parse: " + name + ": got " + JSON.stringify(got));
        parsed.add(parser);
    }
    const parsers = Object.keys(t.PARSERS);
    if (parsers.length < 6) failures.push("parse: fewer than six parsers; the loader read no PARSERS");
    for (const parser of parsers) if (!parsed.has(parser)) failures.push("parse: no row for parser " + parser);

    const checked = new Set();
    for (const [name, manager, binary, want] of CHECK_ROWS) {
        const got = t.checkFor(manager, binary);
        if (!same(got, want)) failures.push("check: " + name + ": got " + JSON.stringify(got));
        checked.add(manager);
    }
    for (const row of t.MANAGERS) if (!checked.has(row.id)) failures.push("check: no row for " + row.id);

    failures.push(...verifyOutcomes(t));
    return failures;
}

function verifyOutcomes(t) {
    const failures = [];
    for (const [name, manager, binary, status, stdout, want, stderr = ""] of OUTCOME_ROWS) {
        const found = t.checkFor(manager, binary);
        const r = found.check === undefined ? { error: "no query" } : t.checkOutcome(found.check, status, stdout, stderr);
        const got = r.error === undefined ? triples(r.packages) : r.error;
        if (!same(got, want)) failures.push("outcome: " + name + ": got " + JSON.stringify(got));
    }
    return failures;
}

// Each control removes one rule's behaviour from a copy. A `rule:` copy
// plants a defect in the table and must meet that rule of tableErrors,
// since its plan rows would fail on any edited argv; a `table` copy is
// judged by the whole table suite; a `cli` copy runs the CLI rows from a
// tree whose other files are the repository's own. A sixth column names
// text one of the copy's failures must hold, for a control that proves one
// particular assertion can fail.
const CONTROLS = [
    ["table", "an up-to-date package is skipped during repair", TABLE, 'reinstall: [["{bin}", "install", "--reinstall", "{names}"]],', 'reinstall: [["{bin}", "install", "{names}"]],'],
    ["rule:partial upgrade", "a pacman upgrade refreshes without upgrading", TABLE, "upgrade: [[\"{bin}\", \"-Syu\"]],", "upgrade: [[\"{bin}\", \"-Sy\"]],"],
    ["rule:elevation command", "a step elevates", TABLE, "[\"{bin}\", \"full-upgrade\"]", "[\"sudo\", \"{bin}\", \"full-upgrade\"]"],
    ["rule:brace", "a preview word holds an fzf placeholder", TABLE, "preview: [\"{bin}\", \"-Sii\", \"{name}\"]", "preview: [\"{bin}\", \"-Sii\", \"--x={q}\", \"{name}\"]"],
    ["rule:elevation command", "a picker's list elevates", TABLE, "list: [\"{bin}\", \"-Slq\"]", "list: [\"sudo\", \"{bin}\", \"-Slq\"]"],
    ["table", "a manager whose steps differ updates a package it must install", TABLE, "row.update !== null && JSON.stringify(row.update) === JSON.stringify(row.install))", "row.update !== null)"],
    ["table", "an owed plan drops its install steps", TABLE, "update.plan.steps = install.plan.steps.concat(update.plan.steps);", ""],
    ["table", "an owed plan of one step drops the missing packages", TABLE, "return plan(id, \"update\", outdated.concat(missing), onPath, undefined, config);", "return plan(id, \"update\", outdated, onPath, undefined, config);"],
    ["table", "an upgrade drops the packages it keeps out", TABLE, "for (var k = 0; k < kept.length; k++) argv.push(row.ignore, kept[k]);", ""],
    ["table", "a manager without the option keeps a package out", TABLE, "if (kept.length > 0 && found.row.ignore === null) return", "if (false) return"],
    ["table", "a kept package's name is not judged", TABLE, "var all = names.concat(kept);", "var all = names;"],
    ["table", "a picker keeps the binary placeholder", TABLE, "var fill = function (token) { return token === \"{bin}\" ? found.binary : token; };", "var fill = function (token) { return token; };"],
    ["table", "the elevation order changes", TABLE, "var ELEVATORS = [\"sudo\", \"doas\", \"run0\"];", "var ELEVATORS = [\"doas\", \"sudo\", \"run0\"];"],
    ["table", "a configured elevation command is ignored", TABLE, "        if (onPath(configured)) return { ok: true, command: configured };\n", ""],
    ["table", "ID_LIKE is ignored", TABLE, "    if (like !== null) {", "    if (false) {"],
    ["table", "a row with a release serves every release", TABLE, "    if (row.release === null) return true;", "    return true;"],
    ["table", "a row with a release serves through ID_LIKE", TABLE, "return token === osReleaseValue(text, \"ID\") && osReleaseValue(", "return osReleaseValue("],
    ["table", "a row with a release ignores the release's value", TABLE, " && osReleaseValue(text, row.release.key) === row.release.value;", ";"],
    ["table", "apt serves another Debian release", TABLE, "release: { key: \"VERSION_CODENAME\", value: \"forky\" }", "release: { key: \"VERSION_CODENAME\", value: \"trixie\" }"],
    ["table", "an overlay ignores the primary it requires", TABLE, "if (other.requires !== null && (primary === null || primary.id !== other.requires)) continue;", ""],
    ["table", "a name may start with a dash", TABLE, " && name.charAt(0) !== \"-\"", ""],
    ["table", "the first binary wins even when absent", TABLE, "if (onPath(row.binaries[i])) return row.binaries[i];", "return row.binaries[i];"],
    ["table", "a requirement's package ignores the primary's rank", TABLE, "return (found.primary === null ? [] : [found.primary]).concat(found.overlays, found.sources);", "return found.overlays.concat(found.sources, found.primary === null ? [] : [found.primary]);"],
    ["table", "a holder is ignored and the first listed manager wins", TABLE, "if (holder !== undefined && holder !== null && holder.path !== null && holder.owners !== undefined) {", "if (false) {"],
    ["table", "a holder matches the wrong package name", TABLE, "holder.owners[heldBy] === packages[heldBy]", "holder.owners[heldBy] !== null"],
    ["table", "a requirement's package is picked for an unmapped manager", TABLE, "if (Object.prototype.hasOwnProperty.call(packages, order[i].id))", "if (true)"],
    ["table", "a package two commands share is installed twice", TABLE, " && names.indexOf(picks[j].name) === -1) names.push", ") names.push"],
    ["table", "the primary's install names its manager", TABLE, "return (group.primary ? [] : [\"--manager\", group.manager]).concat(group.names);", "return [\"--manager\", group.manager].concat(group.names);"],
    ["table", "an overlay's install omits its manager", TABLE, "return (group.primary ? [] : [\"--manager\", group.manager]).concat(group.names);", "return group.names;"],
    ["table", "apt engine loses its argv boundary", TABLE, 'engineArchive: ["install", "--"]', 'engineArchive: ["install"]'],
    ["table", "nix is offered an install", TABLE, "installs: managerRow(order[i].id).install !== null", "installs: true"],
    ["table", "a mise update keeps the installed version", TABLE, "else if (step[j] === \"{names@latest}\") argv.push.apply(argv, names.map(function (name) { return name + \"@latest\"; }));", "else if (step[j] === \"{names@latest}\") argv.push.apply(argv, names);"],
    ["rule:update steps", "a manager that installs has no update", TABLE, "update: [[\"{bin}\", \"upgrade\", \"{names}\"]],", "update: null,"],
    ["table", "a removable name may start with a dash", TABLE, "if (query !== \"owner\" && !validName(value))", "if (query === \"installed\" && !validName(value))"],
    ["table", "a query's answer ignores its pattern", TABLE, "return m === null ? null : m[1];", "return stdout.split(\"\\n\")[0];"],
    ["table", "mise roots never hold a command", TABLE, "if (pathHolds(root, realPath)) return names[i];", "if (false) return names[i];"],
    ["outcomes", "a failed probe discards its diagnostic", TABLE, 'var diagnostic = stderr.trim();', 'var diagnostic = "";'],
    ["outcomes", "an unlisted exit status is read as output", TABLE, "meaning === undefined || ", ""],
    ["table", "a query runs for a binary it does not name", TABLE, "if (c.binary !== null && c.binary !== binary) continue;", ""],
    ["table", "paru's ignored package is counted", TABLE, "if (f[4] === \"[ignored]\") continue;", "if (f[4] === \"[ignored]\") { packages.push({ name: f[0], old: f[1], new: f[3] }); continue; }"],
    ["table", "apt skips a line it cannot read", TABLE, "if (m === null) return unreadable(i);\n        packages.push({ name: m[1], old: m[3], new: m[2] });", "if (m === null) continue;\n        packages.push({ name: m[1], old: m[3], new: m[2] });"],
    ["table", "dnf 4 counts the obsoleting section", TABLE, "if (rows[i] === \"Obsoleting Packages\") break;", ""],
    ["table", "dnf5 accepts an unknown section", TABLE, "if (key !== \"upgrades\" && key !== \"obsoleting_packages\") return { ok: false, error: \"unparseable key=\" + key };", ""],
    ["table", "flatpak reads a title row", TABLE, " || /\\s/.test(f[0] + f[1])", ""],
    ["table", "mise accepts a tool without a latest version", TABLE, "typeof t.latest !== \"string\" || ", ""],
];

let failed = false;
const report = (label, failures) => {
    for (const f of failures) console.log("  FAIL  " + label + ": " + f);
    if (failures.length > 0) failed = true;
};

function runControl(tmp, control, index) {
    const [kind, label, file, needle, replacement] = control;
    const source = fs.readFileSync(file, "utf8");
    const count = source.split(needle).length - 1;
    if (count !== 1) {
        report("control", [label + ": the text to replace occurs " + count + " times, not once"]);
        return;
    }
    const mutant = path.join(tmp, index + "-PackageManagers.js");
    fs.writeFileSync(mutant, source.replace(needle, () => replacement));
    const failures = kind === "outcomes" ? verifyOutcomes(load(mutant)) : kind === "table" ? verifyTable(load(mutant)) : tableErrors(load(mutant)).filter(f => f.includes(kind.slice("rule:".length)));
    if (failures.length === 0) report("control", [label + ": the suite passed on a copy without that rule"]);
}

function main() {
    const tmp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "vgshell-pkg-table-")));
    try {
        report("table", verifyTable(load(TABLE)));
        CONTROLS.forEach((control, index) => runControl(tmp, control, index));
        if (failed) process.exitCode = 1;
        else console.log("test-vgshell-pkg-table: ok detect=" + DETECT_ROWS.length + " ids=" + ID_ROWS.length + " plans=" + PLAN_ROWS.length + " ignores=" + IGNORE_ROWS.length + " queries=" + QUERY_ROWS.length + " answers=" + ANSWER_ROWS.length + " pickers=" + PICKER_ROWS.length + " elevators=" + ELEVATOR_ROWS.length + " picks=" + PACKAGE_FOR_ROWS.length + " groups=" + INSTALL_GROUP_ROWS.length + " parses=" + PARSE_ROWS.length + " checks=" + CHECK_ROWS.length + " outcomes=" + OUTCOME_ROWS.length + " controls=" + CONTROLS.length);
    } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
    }
}

main();
