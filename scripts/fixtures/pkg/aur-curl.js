// Smoke's curl boundary: AUR reads use the neutral recipe fixture.
// Non-AUR requests reach only the row-owned curl delegate, when present.
// argv: <delegate path> <curl argv...>. There is no network transport.
"use strict";
const childProcess = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const [delegate, ...args] = process.argv.slice(2);
const at = args.indexOf("--url");
let url;
try { url = new URL(at === -1 ? args[args.length - 1] : args[at + 1]); } catch (_) { url = null; }
const refuse = () => {
    process.stderr.write("aur-curl-fixture: refused unsupported-request\n");
    process.exitCode = 70;
};
if (url !== null && url.hostname === "aur.archlinux.org") {
    if (url.protocol !== "https:") refuse();
    else if (url.pathname === "/rpc/v5/info") {
        const names = [...new Set(url.searchParams.getAll("arg[]"))];
        if (names.length === 0) refuse();
        else process.stdout.write(JSON.stringify({
            type: "multiinfo", resultcount: names.length,
            results: names.map(name => ({ Name: name, PackageBase: name }))
        }) + "\n");
    } else if (url.pathname === "/cgit/aur.git/plain/.SRCINFO") {
        const name = url.searchParams.get("h");
        if (name === null || name === "") refuse();
        else {
            let recipe = fs.readFileSync(path.join(__dirname, "aur-any.SRCINFO"), "utf8");
            for (const [needle, replacement] of [
                ["pkgbase = need-two-base\n", "pkgbase = " + name + "\n"],
                ["pkgname = need-two\n", "pkgname = " + name + "\n"]
            ]) {
                if (recipe.split(needle).length !== 2) throw new Error("neutral recipe identity must occur once");
                recipe = recipe.replace(needle, () => replacement);
            }
            process.stdout.write(recipe);
        }
    } else refuse();
} else if (delegate !== undefined && fs.existsSync(delegate)) {
    // Transparent fixture delegation preserves the row's argv, environment,
    // output and exit status; it never invokes a real curl.
    const result = childProcess.spawnSync(delegate, args, { stdio: "inherit", env: process.env });
    process.exitCode = result.error || result.status === null ? 70 : result.status;
} else refuse();
