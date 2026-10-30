"use strict";
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");

// Exit 77 distinguishes unreadable evidence from a known publication gap.
// The landing workflow and validate consume the same JSON record.
function outcome(status, channel, need, reason, step) {
    return { status, channel, need, reason, step };
}
function unavailable(channel, need, reason) {
    const step = channel === "installed" ? "Restore the executor's local engine executable and package ownership probe, then check again." : "Read the channel's publication evidence again after restoring access.";
    throw outcome("unreadable", channel, need, reason, step);
}
function missing(channel, need, reason, step) {
    throw outcome("refuse", channel, need, reason, step);
}
function packageCurrent(engine, manager, version, channel, need) {
    try { return engine.packageCurrent(manager, version); }
    catch { unavailable(channel, need, `package-version=${version}`); }
}
function command(file, args, channel, need, input) {
    const run = cp.spawnSync(file, args, { encoding: "utf8", input, timeout: 30000, maxBuffer: 64 * 1024 * 1024 });
    if (run.error || run.status !== 0) unavailable(channel, need, `command=${path.basename(file)} exit=${run.status} error=${run.error?.code || "none"} diagnostic=${JSON.stringify(run.stderr?.trim() || "")}`);
    return run.stdout;
}
function get(url, channel, need, head = false) {
    const run = cp.spawnSync("curl", [...(head ? ["--head"] : []), "--silent", "--show-error", "--location", "--max-time", "20", "--max-filesize", "67108864", "--write-out", "\n%{http_code}", "--", url], { timeout: 25000, maxBuffer: 64 * 1024 * 1024 });
    if (run.error || run.status !== 0) unavailable(channel, need, `transport=${run.error?.code || run.status} url=${url}`);
    const code = Number(run.stdout.subarray(-3).toString());
    if (code === 404) return null;
    if (code !== 200) unavailable(channel, need, `http=${code} url=${url}`);
    return run.stdout.subarray(0, -4);
}
function json(url, channel, need) {
    const bytes = get(url, channel, need);
    if (bytes === null) return null;
    try { return JSON.parse(bytes.toString()); }
    catch { unavailable(channel, need, `json=${url}`); }
}

// ElementTree owns XML parsing; use the repository's existing Python runtime
// rather than interpreting RPM metadata with regular expressions.
const XML = String.raw`
import gzip, hashlib, io, json, sys, xml.etree.ElementTree as E
mode = sys.argv[1]
raw = sys.stdin.buffer.read()
if mode == "primary":
    with gzip.GzipFile(fileobj=io.BytesIO(raw)) as stream:
        raw = stream.read(64 * 1024 * 1024 + 1)
    if len(raw) > 64 * 1024 * 1024:
        raise ValueError("primary metadata too large")
root = E.fromstring(raw)
if mode == "repomd":
    ns = "{http://linux.duke.edu/metadata/repo}"
    if root.tag != ns + "repomd":
        raise ValueError("not repomd")
    records = root.findall(ns + "data[@type='primary']")
    if len(records) != 1:
        raise ValueError("primary record missing or repeated")
    row = records[0]
    checksum = row.find(ns + "checksum")
    if checksum.attrib["type"] != "sha256":
        raise ValueError("unsupported metadata checksum")
    print(json.dumps({"href": row.find(ns + "location").attrib["href"], "checksum": checksum.text}))
else:
    ns = "{http://linux.duke.edu/metadata/common}"
    if root.tag != ns + "metadata":
        raise ValueError("not primary metadata")
    packages = root.findall(ns + "package")
    if int(root.attrib["packages"]) != len(packages):
        raise ValueError("incomplete package collection")
    rows = []
    for package in packages:
        if package.findtext(ns + "name") == "vgshell-quickshell":
            rows.append({**package.find(ns + "version").attrib, "arch": package.findtext(ns + "arch"), "href": package.find(ns + "location").attrib["href"]})
    print(json.dumps(rows))
`;
function xml(bytes, mode, channel, need) {
    try { return JSON.parse(command("python3", ["-I", "-c", XML, mode], channel, need, bytes)); }
    catch (error) { if (error.status) throw error; unavailable(channel, need, `xml=${mode}`); }
}

function aur(engine) {
    const channel = "aur", need = engine.PACKAGE_FLOORS.pacman;
    const data = json("https://aur.archlinux.org/rpc/v5/info?arg[]=vgshell-quickshell", channel, need);
    if (!data || data.version !== 5 || data.type !== "multiinfo" || !Array.isArray(data.results) || data.resultcount !== data.results.length)
        unavailable(channel, need, "rpc=collection");
    if (data.results.length > 1 || data.results.some(row => row?.Name !== "vgshell-quickshell")) unavailable(channel, need, "rpc=package-identity");
    const row = data.results[0];
    if (!row) missing(channel, need, "package=absent", "Publish vgshell-quickshell with scripts/publish-aur.sh from the committed engine candidate.");
    if (typeof row.Version !== "string") unavailable(channel, need, "rpc=version");
    if (!packageCurrent(engine, "pacman", row.Version, channel, need)) missing(channel, need, `have=${row.Version}`, "Publish vgshell-quickshell with scripts/publish-aur.sh from the committed engine candidate.");
}
function copr(engine, root) {
    const channel = "copr", need = engine.PACKAGE_FLOORS.dnf;
    const declaration = fs.readFileSync(path.join(root, "packaging/fedora/copr-project"), "utf8");
    const projects = [...declaration.matchAll(/^project (\S+\/\S+)$/gm)];
    const targets = [...declaration.matchAll(/^chroot ([a-z0-9_-]+)$/gm)].map(match => match[1]);
    if (projects.length !== 1 || targets.length === 0 || new Set(targets).size !== targets.length) unavailable(channel, need, "targets=unreadable");
    for (const target of targets) {
        const base = `https://download.copr.fedorainfracloud.org/results/${projects[0][1]}/${target}/`;
        const step = `Build the committed engine candidate in COPR ${projects[0][1]} for ${target} and publish its repository metadata.`;
        const index = get(base + "repodata/repomd.xml", channel, need);
        if (index === null) missing(channel, need, `target=${target} repository=absent`, step);
        const metadata = xml(index, "repomd", channel, need);
        if (!/^repodata\/[a-zA-Z0-9._-]+\.xml\.gz$/.test(metadata.href) || !/^[a-f0-9]{64}$/.test(metadata.checksum)) unavailable(channel, need, `target=${target} primary=location`);
        const primary = get(base + metadata.href, channel, need);
        if (primary === null) unavailable(channel, need, `target=${target} primary=missing`);
        if (require("node:crypto").createHash("sha256").update(primary).digest("hex") !== metadata.checksum) unavailable(channel, need, `target=${target} primary=checksum`);
        const rows = xml(primary, "primary", channel, need);
        const arch = target.slice(target.lastIndexOf("-") + 1);
        const row = rows.find(row => row.arch === arch && packageCurrent(engine, "dnf", row.epoch + ":" + row.ver + "-" + row.rel, channel, need));
        if (!row)
            missing(channel, need, `target=${target} package=below-floor`, step);
        if (typeof row.href !== "string" || !/^[a-zA-Z0-9_./+-]+\.rpm$/.test(row.href) || row.href.split("/").includes("..")) unavailable(channel, need, `target=${target} package=location`);
        if (get(base + row.href, channel, need, true) === null) missing(channel, need, `target=${target} rpm=absent`, step);
    }
}
function debian(engine, root) {
    const channel = "debian", need = engine.debianAsset("amd64");
    const api = "https://api.github.com/repos/vanillagreencom/vgshell/releases/";
    const version = fs.readFileSync(path.join(root, "VERSION"), "utf8").trim();
    if (!/^\d+\.\d+\.\d+$/.test(version)) unavailable(channel, need, "version=unreadable");
    // Checkout install/update runs the incoming tree's prepare-engine and
    // asks for this tag. Tagged/latest installers use their own tag's judge.
    for (const selected of ["tags/v" + version]) {
        const release = json(api + selected, channel, need);
        const step = `Publish a normal signed VGS release containing ${need} through scripts/release; the ${selected} selection must supply it.`;
        if (release === null) missing(channel, need, `release=${selected} absent=true`, step);
        if (release.tag_name !== "v" + version || release.draft !== false || release.prerelease !== false || typeof release.assets_url !== "string") unavailable(channel, need, `release=${selected} schema=unreadable`);
        if (!release.assets_url.startsWith(api) || !/^https:\/\/api.github.com\/repos\/vanillagreencom\/vgshell\/releases\/[0-9]+\/assets$/.test(release.assets_url)) unavailable(channel, need, "assets=url");
        const names = new Map();
        for (let page = 1; ; ++page) {
            const assets = json(`${release.assets_url}?per_page=100&page=${page}`, channel, need);
            if (!Array.isArray(assets)) unavailable(channel, need, `release=${selected} assets=unreadable`);
            for (const asset of assets) {
                if (!asset || typeof asset.name !== "string" || typeof asset.browser_download_url !== "string" || asset.state !== "uploaded" || !(asset.size > 0)) unavailable(channel, need, `release=${selected} asset=schema`);
                names.set(asset.name, asset.browser_download_url);
            }
            if (assets.length < 100) break;
        }
        for (const name of [need, "release-key.asc", "SHA256SUMS", "SHA256SUMS.asc"]) {
            if (!names.has(name)) missing(channel, need, `release=${selected} asset=${name}`, step);
            const url = names.get(name);
            if (!url.startsWith("https://github.com/vanillagreencom/vgshell/releases/download/")) unavailable(channel, need, `release=${selected} asset=${name} url=unreadable`);
            if (get(url, channel, need, true) === null) missing(channel, need, `release=${selected} asset=${name} absent=true`, step);
        }
    }
}
function nix(engine, root, ref) {
    const channel = "nix", need = engine.RELEASE;
    const api = "https://api.github.com/repos/vanillagreencom/vgshell/";
    const flake = fs.readFileSync(path.join(root, "flake.nix"), "utf8");
    const patches = [...flake.matchAll(/\.\/(packaging\/arch\/vgshell-quickshell\/[a-zA-Z0-9._-]+\.patch)/g)].map(match => match[1]);
    if (!patches.length) unavailable(channel, need, "source=patches");
    const files = ["flake.nix", "flake.lock", ...new Set(patches)];
    // A later check-only commit need not be public yet. The last commit of
    // the exact Nix inputs identifies the engine candidate before main moves.
    if (ref === null) ref = command("git", ["-C", root, "log", "-1", "--format=%H", "--", ...files], channel, need).trim();
    if (!ref) unavailable(channel, need, "source=uncommitted");
    const commit = json(api + "commits/" + encodeURIComponent(ref), channel, need);
    const step = "Push the coherent committed engine candidate with its flake lock and shared patches to the public VGS repository.";
    if (commit === null) missing(channel, need, `source=${ref} absent=true`, step);
    if (!commit || typeof commit.sha !== "string" || !/^[a-f0-9]{40}$/.test(commit.sha) || (/^[a-f0-9]{40}$/.test(ref) && commit.sha !== ref)) unavailable(channel, need, "source=identity");
    for (const file of files) {
        const bytes = get(`${api}contents/${file}?ref=${commit.sha}`, channel, need);
        if (bytes === null) missing(channel, need, `source=${commit.sha} file=${file} absent=true`, step);
        let data;
        try { data = JSON.parse(bytes.toString()); } catch { unavailable(channel, need, `source=${commit.sha} content=json`); }
        if (data?.type !== "file" || data.encoding !== "base64" || typeof data.content !== "string" || !Number.isSafeInteger(data.size)) unavailable(channel, need, `source=${commit.sha} file=${file} schema=unreadable`);
        const content = Buffer.from(data.content, "base64");
        if (content.length !== data.size) unavailable(channel, need, `source=${commit.sha} file=${file} content=incomplete`);
        if (!content.equals(fs.readFileSync(path.join(root, file)))) missing(channel, need, `source=${commit.sha} file=${file} differs=true`, step);
    }
    return commit.sha;
}

function installed(engine, root, executable) {
    const channel = "installed", need = engine.RELEASE;
    const pkg = path.join(root, "bin/vgshell-pkg");
    const step = "Have the fleet owner install the published vgshell-quickshell engine on this executor before nested validation.";
    const file = executable || require(path.join(root, "bin/lib/judge-files.js")).commandFile("qs");
    if (file === null) missing(channel, need, "executable=absent", step);
    if (!path.isAbsolute(file)) unavailable(channel, need, "executable=not-absolute");
    // Nix's selected executable is immutable. Every other selected path
    // uses owner(), whose query errors do not collapse into a null holder.
    if (!fs.realpathSync(file).startsWith("/nix/store/")) {
        let owner;
        try { owner = JSON.parse(command(process.execPath, [pkg, "owner", file], channel, need)); }
        catch (error) { if (error.status) throw error; unavailable(channel, need, "owner=json"); }
        if (typeof owner?.manager !== "string" || typeof owner.package !== "string") unavailable(channel, need, "owner=schema");
        if (owner?.package !== "vgshell-quickshell") missing(channel, need, "owner=vgshell-quickshell-missing", step);
        if (owner.manager === "apt" && !packageCurrent(engine, "apt", owner.version, channel, need)) missing(channel, need, "package=below-floor", step);
    }
    const text = command(file, ["--version"], channel, need);
    const have = engine.classify(text);
    if (!engine.current(text)) missing(channel, need, `have=${have.kind === "stock" ? "stock" : have.release ?? "unknown"}`, step);
}
function main(args, codeRoot) {
    const operation = args.shift();
    let root = codeRoot, ref = null, executable = null;
    while (args.length) {
        const option = args.shift(), value = args.shift();
        const allowed = operation === "--installed-engine" ? ["--root", "--executable"] : ["--root", "--source-ref"];
        if (!value || !allowed.includes(option)) { console.error("check-packaging: argument=" + option); process.exitCode = 2; return; }
        if (option === "--root") root = path.resolve(value);
        else if (option === "--source-ref") ref = value;
        else executable = value;
    }
    let result, release = null;
    try {
        const engine = require(path.join(root, "bin/lib/engine.js"));
        release = engine.RELEASE;
        if (operation === "--installed-engine") {
            installed(engine, root, executable);
            result = outcome("pass", "installed", engine.RELEASE, "available", "none");
        } else {
            // Read every consumer even when one has a known gap. Otherwise
            // an accepted release refusal could conceal an unreadable channel.
            const checks = [];
            for (const [channel, read] of [["aur", () => aur(engine)], ["copr", () => copr(engine, root)], ["debian", () => debian(engine, root)], ["nix", () => nix(engine, root, ref)]]) {
                try {
                    const source = read();
                    checks.push(outcome("pass", channel, engine.RELEASE, source ? "source=" + source : "available", "none"));
                } catch (error) {
                    checks.push(["refuse", "unreadable"].includes(error?.status) ? error : outcome("unreadable", channel, engine.RELEASE, String(error.message), "Restore readable publication inputs."));
                }
            }
            result = { ...(checks.find(check => check.status === "unreadable") || checks.find(check => check.status === "refuse") || outcome("pass", "publication", engine.RELEASE, "available", "none")), checks };
        }
    } catch (error) {
        result = ["refuse", "unreadable"].includes(error?.status) ? error : operation === "--installed-engine" ? outcome("unreadable", "installed", release, String(error.message), "Restore the executor's local engine executable and package ownership probe, then check again.") : outcome("unreadable", "input", null, String(error.message), "Restore readable engine publication inputs.");
    }
    console.log(JSON.stringify({ ...result, release }));
    process.exitCode = { pass: 0, refuse: 1, unreadable: 77 }[result.status];
}
module.exports = { main };
