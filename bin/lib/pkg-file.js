// bin/lib/pkg-file.js: the user's side of a file row of
// shell/Core/PackageManagers.js. A verified file: the repository's database
// is unsigned, so it only names the file; the package's own signature, tied
// to the pinned key, is the trust. A release file: the pinned SHA-256 of
// the release asset is the trust, and the package file must name the
// package, version and architecture pinned. Each refusal comes before any
// root step.
"use strict";
const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { refuse } = require("./judge-files.js");

const tree = path.join(__dirname, "..", "..");
const table = require("./qml-library.js").load(path.join(tree, "shell", "Core", "PackageManagers.js"));
// repo-add's file name, `<name>-<version>-<arch>.pkg.tar.<ext>`; it goes into
// root's argv and a path under the scratch folder, so it holds no slash.
const FILENAME = /^[A-Za-z0-9@_+][A-Za-z0-9@._+:-]*\.pkg\.tar\.(?:zst|xz|gz)$/;

function spawn(argv) {
    return childProcess.spawnSync(argv[0], argv.slice(1), { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, cwd: process.env.HOME || "/", env: Object.assign({}, process.env, { LC_ALL: "C" }) });
}

// ARGV's stdout. Refuses as KEY, with DETAIL in plain words, when it does
// not run or exits non-zero, and with 128 plus the signal's number when a
// signal ended it, as a Ctrl-C in the terminal ends curl.
function tool(argv, key, detail) {
    const r = spawn(argv);
    const said = detail + "\n" + (r.stderr || "");
    if (r.signal !== null && r.signal !== undefined) refuse(key + " signal=" + r.signal, undefined, 128 + os.constants.signals[r.signal], said);
    if (r.error !== undefined || r.status !== 0) refuse(key + " exit=" + (r.error !== undefined ? r.error.code : r.status), undefined, 1, said);
    return r.stdout;
}

function download(url, file, what) {
    tool(["curl", "--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https", "--max-time", "600", "--output", file, url], "download=failed url=" + url,
        "VGS could not download " + what + ", so it installed nothing. Check the network connection and try again later.");
    return file;
}

// The private folders this process made, removed when it exits normally,
// by refusal or by SIGINT, SIGTERM or SIGHUP: a default-disposition signal
// ends node without its exit event. The signal handlers hold only until
// released: the root steps after a fetch keep the process alive through
// bin/vgshell-pkg's own handlers, and the exit event still removes them.
const SIGNALS = ["SIGINT", "SIGTERM", "SIGHUP"];
const folders = [];
const removeFolders = () => { for (const dir of folders) fs.rmSync(dir, { recursive: true, force: true }); };
const onSignal = signal => { removeFolders(); process.exit(128 + os.constants.signals[signal]); };
function scratch() {
    if (!process.env.XDG_RUNTIME_DIR) refuse("runtime-dir=unset", undefined, 1, "VGS has no runtime folder to fetch into, so it installed nothing. Sign in to a desktop session and try again.");
    const parent = path.join(process.env.XDG_RUNTIME_DIR, "vgshell");
    fs.mkdirSync(parent, { recursive: true, mode: 0o700 });
    if (folders.length === 0) {
        process.on("exit", removeFolders);
        for (const signal of SIGNALS) process.on(signal, onSignal);
    }
    folders.push(fs.mkdtempSync(path.join(parent, "pkgfile-")));
    return folders[folders.length - 1];
}
function releaseSignals() {
    for (const signal of SIGNALS) process.removeListener(signal, onSignal);
}

// Each release file format's reads: the system's architecture as its
// release assets name it, the package file's name, version and
// architecture as one line, the installed version of a package, and the
// format's own version comparison, whose versions a refusal holds to the
// characters a version of that format takes.
const FORMATS = {
    // dpkg(1) --print-architecture; dpkg-deb(1) --field prints each field
    // as `Field: value`; dpkg-query(1) exits 1 for a name it knows nothing
    // of, and its db:Status-Status is `installed` only for an installed
    // package, not one whose configuration files alone remain.
    deb: {
        arch: ["dpkg", "--print-architecture"],
        identity: file => ["dpkg-deb", "--field", file, "Package", "Version", "Architecture"],
        expected: (release, arch) => "Package: " + release.name + "\nVersion: " + release.version + "\nArchitecture: " + arch + "\n",
        installed: name => ["dpkg-query", "-W", "--showformat=${db:Status-Status} ${Version}\n", "--", name],
        read: (r, name) => {
            if (r.error === undefined && r.status === 1) return null;
            const found = r.status === 0 ? /^(\S+) (\S+)\n$/.exec(r.stdout) : null;
            if (found === null) return undefined;
            return found[1] === "installed" ? found[2] : null;
        },
        // deb-version(7): epoch, upstream version and revision, each
        // starting with a digit, so no version reads as an option; dpkg(1)
        // --compare-versions exits 0 for a true relation and 1 for a false one.
        version: /^[0-9][A-Za-z0-9.+~:-]*$/,
        newer: (a, b) => {
            const r = spawn(["dpkg", "--compare-versions", a, "gt", b]);
            if (r.error === undefined && (r.status === 0 || r.status === 1)) return r.status === 0;
            return refuse("compare=failed tool=dpkg", undefined, 1, "VGS could not compare the versions " + a + " and " + b + ", so it changed nothing.\n" + (r.stderr || ""));
        }
    },
    // rpm(8): -E evaluates a macro, -qp queries a package file, and -q exits
    // 1 for a package that is not installed.
    rpm: {
        arch: ["rpm", "-E", "%{_arch}"],
        identity: file => ["rpm", "-qp", "--queryformat", "%{NAME} %{VERSION} %{ARCH}\n", "--", file],
        expected: (release, arch) => release.name + " " + release.version + " " + arch + "\n",
        installed: name => ["rpm", "-q", "--queryformat", "%{VERSION}\n", "--", name],
        read: r => {
            if (r.error === undefined && r.status === 1) return null;
            const found = r.status === 0 ? /^(\S+)\n$/.exec(r.stdout) : null;
            return found === null ? undefined : found[1];
        },
        // rpm's own rpm.vercmp (rpm-lua(7)) prints 1, 0 or -1; the version
        // pattern keeps every quote out of the Lua string it is put in.
        version: /^[A-Za-z0-9._+~^]+$/,
        newer: (a, b) => {
            const said = tool(["rpm", "--eval", "%{lua:print(rpm.vercmp(\"" + a + "\",\"" + b + "\"))}"], "compare=failed tool=rpm",
                "VGS could not compare the versions " + a + " and " + b + ", so it changed nothing.").trim();
            if (!["1", "0", "-1"].includes(said)) refuse("compare=unreadable tool=rpm value=" + JSON.stringify(said), undefined, 1, "VGS could not compare the versions " + a + " and " + b + ", so it changed nothing.");
            return said === "1";
        }
    }
};

// Each kind of file row (PackageManagers.js `files.kind`): a verified file
// that a repository's database names, or a pinned release file.
const KINDS = ["verified", "release"];

// Manager ID's file row, its kind one of KINDS.
function fileRow(id) {
    const row = table.managerRow(id);
    const spec = row === null ? undefined : row.files;
    if (spec === undefined || !KINDS.includes(spec.kind)) refuse("manager=" + id + " reason=no-file-row", undefined, 1, "VGS takes no package files through " + id + ", so it changed nothing.");
    return spec;
}

// Whether version A is newer than B under manager ID's row: pacman's own
// vercmp for a verified file, the release format's comparison otherwise.
function newer(id, a, b) {
    const spec = fileRow(id);
    if (spec.kind === "verified")
        return Number(tool(["vercmp", a, b], "vercmp=failed", "VGS could not compare the versions " + a + " and " + b + ", so it changed nothing.")) > 0;
    const format = FORMATS[spec.format];
    for (const version of [a, b])
        if (!format.version.test(version)) refuse("version=unreadable value=" + JSON.stringify(version), undefined, 1, "VGS could not read the version " + version + ", so it changed nothing.");
    return format.newer(a, b);
}

// The installed version of NAME under manager ID's row, or null: pacman -Q
// exits 1 for a package it does not have; a release file's format reads
// its own.
function installed(id, name) {
    const spec = fileRow(id);
    if (spec.kind === "release") {
        const format = FORMATS[spec.format];
        const r = spawn(format.installed(name));
        const version = format.read(r, name);
        if (version === undefined) refuse("installed=unreadable name=" + name, undefined, 1, "VGS could not read the installed version of " + name + ", so it changed nothing.\n" + (r.stderr || ""));
        return version;
    }
    const r = spawn(["pacman", "-Q", "--", name]);
    if (r.error === undefined && r.status === 1) return null;
    const words = r.status === 0 ? r.stdout.trim().split(" ") : [];
    if (words.length !== 2 || words[0] !== name) refuse("installed=unreadable name=" + name, undefined, 1, "VGS could not read the installed version of " + name + ", so it changed nothing.\n" + (r.stderr || ""));
    return words[1];
}

// Fetches release-file manager ID's package NAME into DIR: `{ name,
// fetched, filename }` for PackageManagers.filePlan, once the asset's
// SHA-256 is the pinned one and the file names the pinned package, version
// and architecture.
function fetchRelease(id, name, dir) {
    const spec = fileRow(id);
    const release = spec.releases.find(r => r.name === name);
    if (release === undefined) refuse("manager=" + id + " name=" + name + " reason=unlisted", undefined, 1, "VGS takes no package named " + name + " from a pinned release, so it installed nothing.");
    const format = FORMATS[spec.format];
    const arch = tool(format.arch, "arch=unreadable", "VGS could not read this system's architecture, so it installed nothing.").trim();
    const asset = Object.prototype.hasOwnProperty.call(release.assets, arch) ? release.assets[arch] : undefined;
    if (asset === undefined) refuse("release=unsupported name=" + name + " arch=" + arch, undefined, 1, name + " publishes no package for this computer's architecture, " + arch + ", so VGS installed nothing.");
    const current = installed(id, name);
    if (current !== null && newer(id, current, release.version))
        refuse("version=older name=" + name + " installed=" + current + " offered=" + release.version, undefined, 1, "VGS offers " + name + " " + release.version + ", older than the installed " + current + ". VGS does not install an older version, so it installed nothing.");
    const url = release.url + asset.file;
    process.stderr.write("Fetching " + asset.file + " from " + release.url + ", then checking it against the digest VGS pins.\n");
    const fetched = download(url, path.join(dir, asset.file), name);
    const refused = "VGS refused it, so it installed nothing.";
    if (crypto.createHash("sha256").update(fs.readFileSync(fetched)).digest("hex") !== asset.sha256)
        refuse("sha256=mismatch name=" + name + " url=" + url, undefined, 1, "The downloaded " + name + " file differs from the release VGS pins. " + refused + " Try again later.");
    const other = "The downloaded " + name + " file is not the package, version and architecture VGS pins. " + refused;
    if (tool(format.identity(fetched), "identity=unreadable name=" + name, other) !== format.expected(release, arch))
        refuse("identity=mismatch name=" + name + " offered=" + release.version, undefined, 1, other);
    return { name, fetched, filename: asset.file };
}

// SOURCE's database entries by package name, each `{ filename, version,
// sha256, url }`. Every repo-add desc starts with %FILENAME%; each field is
// a `%KEY%` line with its value on the next.
function database(source, dir) {
    const arch = tool(["pacman-conf", "Architecture"], "arch=unreadable", "VGS could not read pacman's architecture, so it installed nothing.").split("\n")[0];
    const url = source.url.replace("{arch}", arch);
    const text = tool(["bsdtar", "-xOf", download(url, path.join(dir, "db"), source.name + "'s package list"), "*/desc"], "database=unreadable url=" + url,
        "VGS could not read " + source.name + "'s package list, so it installed nothing. Try again later.");
    const entries = {};
    for (const desc of text.split(/\n(?=%FILENAME%\n)/)) {
        const field = key => (new RegExp("^%" + key + "%\\n(.+)$", "m").exec(desc) || [])[1];
        entries[field("NAME")] = { filename: field("FILENAME"), version: field("VERSION"), sha256: field("SHA256SUM"), url: url.slice(0, url.lastIndexOf("/") + 1) + field("FILENAME") };
    }
    return entries;
}

// Whether pacman requires its own signature on a -U file. pacman-conf prints
// LocalFileSigLevel only when pacman.conf sets it; unset, libalpm takes
// SigLevel (pacman 7.1.0 src/pacman/conf.c:113,1405-1406,
// lib/libalpm/handle.c:914-921), which pacman-conf prints with its compiled
// default, Required (conf.c:112, pacman-conf.c:182-202).
function fileSignatureRequired() {
    const level = key => tool(["pacman-conf", key], "siglevel=unreadable", "VGS could not read pacman's signature setting, so it installed nothing.").split("\n").filter(line => line !== "");
    const local = level("LocalFileSigLevel");
    return (local.length > 0 ? local : level("SigLevel")).includes("PackageRequired");
}

function unlisted(name, source) {
    refuse("database=unlisted name=" + name + " repository=" + source.name, undefined, 1, source.name + " no longer lists " + name + ", so VGS cannot install or update it from there. Nothing was changed.");
}

// Fetches verified-file manager ID's package NAME and its signature into
// DIR: `{ name, fetched, fetchedSig, filename, key }` for
// PackageManagers.filePlan.
function fetch(id, name, dir) {
    if (fileRow(id).kind === "release") return fetchRelease(id, name, dir);
    const source = fileRow(id).repositories.find(r => r.packages.includes(name));
    if (source === undefined) refuse("manager=" + id + " name=" + name + " reason=unlisted", undefined, 1, "VGS takes no package named " + name + " from a verified source, so it installed nothing.");
    if (fileSignatureRequired())
        refuse("local-file-siglevel=required name=" + name, undefined, 1, "This system's pacman checks a package file's signature itself, which would need " + source.name + "'s key in the system keyring. VGS does not trust a key system-wide, so it cannot install " + name + " here.");
    const entry = database(source, dir)[name];
    if (entry === undefined) unlisted(name, source);
    if (!FILENAME.test(entry.filename || "") || !entry.filename.startsWith(name + "-" + entry.version + "-") || !/^[0-9a-f]{64}$/.test(entry.sha256 || ""))
        refuse("database=malformed name=" + name + " repository=" + source.name, undefined, 1, source.name + "'s package list describes " + name + " in a form VGS does not accept, so it installed nothing. Try again later.");
    const current = installed(id, name);
    if (current !== null && newer(id, current, entry.version))
        refuse("version=older name=" + name + " installed=" + current + " offered=" + entry.version, undefined, 1, source.name + " offers " + name + " " + entry.version + ", older than the installed " + current + ". VGS does not install an older version, so it installed nothing.");
    process.stderr.write("Fetching " + entry.filename + " and its signature from " + source.name + ", then checking them against the key VGS ships.\n");
    const fetched = download(entry.url, path.join(dir, entry.filename), name);
    const fetchedSig = download(entry.url + ".sig", path.join(dir, entry.filename + ".sig"), name + "'s signature");
    const refused = "VGS refused it, so it installed nothing.";
    if (crypto.createHash("sha256").update(fs.readFileSync(fetched)).digest("hex") !== entry.sha256)
        refuse("sha256=mismatch name=" + name, undefined, 1, "The downloaded " + name + " file differs from the one " + source.name + "'s package list names. " + refused + " Try again later.");
    const key = path.join(tree, source.key);
    // gpgv(1) --status-fd: `VALIDSIG <fpr> <date> <ts> <expire> <version>
    // <reserved> <pubkey-algo> <hash-algo> <class> <primary-fpr>`.
    const gpgv = spawn(["gpgv", "--keyring", key, "--status-fd", "1", "--", fetchedSig, fetched]);
    if (gpgv.status !== 0 || !gpgv.stdout.split("\n").some(line => /^\[GNUPG:\] VALIDSIG /.test(line) && line.split(" ")[11] === source.fingerprint))
        refuse("signature=invalid name=" + name + " fingerprint=" + source.fingerprint, undefined, 1, "The " + name + " file is not signed by " + source.name + "'s key that VGS ships. " + refused + "\n" + (gpgv.stderr || ""));
    // The signature covers the bytes, not the database's claim: the signed
    // .PKGINFO must name the package and version asked for, or another file
    // the key signed, an older one included, could stand in.
    const other = "The signed " + name + " file is not the package and version " + source.name + "'s package list names. " + refused;
    const info = "\n" + tool(["bsdtar", "-xOf", fetched, ".PKGINFO"], "pkginfo=unreadable name=" + name, other);
    if (!info.includes("\npkgname = " + name + "\n") || !info.includes("\npkgver = " + entry.version + "\n")) refuse("pkginfo=mismatch name=" + name + " offered=" + entry.version, undefined, 1, other);
    return { name, fetched, fetchedSig, filename: entry.filename, key };
}

// Manager ID's installed packages its repositories' databases or its
// pinned releases offer newer, each `{ name, installed, offered }`, or null
// when none of its packages is installed.
function outdated(id) {
    const found = [];
    let used = false;
    const spec = fileRow(id);
    if (spec.kind === "release") {
        for (const release of spec.releases) {
            const version = installed(id, release.name);
            if (version === null) continue;
            used = true;
            if (newer(id, release.version, version)) found.push({ name: release.name, installed: version, offered: release.version });
        }
        return used ? found : null;
    }
    for (const source of spec.repositories) {
        const have = source.packages.map(name => [name, installed(id, name)]).filter(pair => pair[1] !== null);
        if (have.length === 0) continue;
        used = true;
        const entries = database(source, scratch());
        for (const [name, version] of have) {
            if (entries[name] === undefined) unlisted(name, source);
            if (newer(id, entries[name].version, version)) found.push({ name, installed: version, offered: entries[name].version });
        }
    }
    return used ? found : null;
}

// `vgshell pkg file-check ID`: the `arrow` update lines of manager ID's
// installed packages, and the exit status its check row lists.
function check(id) {
    const found = outdated(id);
    if (found === null) return 2;
    process.stdout.write(found.map(p => p.name + " " + p.installed + " -> " + p.offered + "\n").join(""));
    return found.length > 0 ? 0 : 1;
}

module.exports = { fetch, check, outdated, scratch, releaseSignals };
