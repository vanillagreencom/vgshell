#!/usr/bin/env node
// Recipe fixture stand-in for pacman, paru, claude and codex in the
// pkg-review world (world.js): it answers the calls that carry one recipe
// fixture, RECIPE_FIXTURE (scripts/fixtures/pkg-review/recipes/<name>), and
// hands every other call to the world's command.js unchanged.
//   paru|pacman -Qua         the fixture's pending update, old -> new
//   pacman -Q -- NAME        not installed (exit 1) for a fixture with no old
//                            version, else NAME OLD
//   paru|pacman -G -- NAME   the fixture's build/ files, as <pkgbase>/
//   claude|codex PROMPT      copies the review directory the prompt names to
//                            RECIPE_OUT/evidence, then writes `verdict clean`
// The agent's clean verdict leaves the installer's own install-script
// risks as the only concerns the owner asks about.
"use strict";
const fs = require("node:fs"), path = require("node:path");
const name = path.basename(process.argv[1]), args = process.argv.slice(2);
const fixture = process.env.RECIPE_FIXTURE, out = process.env.RECIPE_OUT;
const meta = JSON.parse(fs.readFileSync(path.join(fixture, "fixture.json"), "utf8"));

if (name === "claude" || name === "codex") {
    const review = /The review directory is `([^`]+)`/.exec(args.at(-1))?.[1];
    if (!review) throw new Error("recipe fixture: the prompt names no review directory");
    fs.cpSync(review, path.join(out, "evidence"), { recursive: true, verbatimSymlinks: true });
    fs.writeFileSync(path.join(review, "verdict"), "verdict clean\n", { mode: 0o600 });
    process.exit(0);
}
if ((name === "paru" || name === "pacman") && args.includes("-Qua")) {
    process.stdout.write(`${meta.package} ${meta.old} -> ${meta.new}\n`);
    process.exit(0);
}
if (name === "pacman" && args.includes("-Q") && args.includes("--")) {
    if (meta.old === null) process.exit(1);
    process.stdout.write(`${meta.package} ${meta.old}\n`);
    process.exit(0);
}
if ((name === "paru" || name === "pacman") && args.includes("-G")) {
    fs.cpSync(path.join(fixture, "build"), path.join(process.cwd(), meta.pkgbase), { recursive: true });
    process.exit(0);
}
require("./command.js");
