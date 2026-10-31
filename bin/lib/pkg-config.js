#!/usr/bin/env node
// The effective pacman configuration selected by a pacman-family command.
// Retains the former Updates adapter: argv wins, then helper configuration.
"use strict";
const fs = require("node:fs"), path = require("node:path");
let inputs = process.argv.slice(2), apply = null;
if (inputs[0] === "--apply") { apply = inputs[1]; inputs = inputs.slice(2); }
const [helper, ...argv] = inputs;
function refuse(reason) { process.stderr.write("package-review: refused: " + reason + "\n"); process.exit(1); }
if (!helper) refuse("config=helper-missing");
    let original;
    const words = [];
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === "--") { words.push(...argv.slice(i)); break; }
        if (argv[i] === "--config") {
            if (!argv[++i]) refuse("pacman-config=missing-value", 1);
            original = argv[i];
        } else if (argv[i].startsWith("--config=")) original = argv[i].slice(9);
        else words.push(argv[i]);
    }
    if (apply === null && original === undefined && path.basename(helper) === "yay") {
        // yay(8) exposes its effective settings through --currentconfig.
        const r = require("node:child_process").spawnSync(helper, ["--show", "--currentconfig"], { encoding: "utf8", cwd: process.env.HOME, timeout: 10000 });
        if (r.error || r.status !== 0) refuse("pacman-config=yay-unreadable", 1);
        try { original = JSON.parse(r.stdout).pacmanconf; } catch (_) { refuse("pacman-config=yay-unparseable", 1); }
        if (typeof original !== "string" || original === "") refuse("pacman-config=yay-missing-path", 1);
    }
    if (apply === null && original === undefined && path.basename(helper) === "paru") {
        // paru.conf(5), config.rs: Include reads an exact path and carries
        // the current section through it. [bin] PacmanConf is a program.
        const optional = file => {
            try { fs.statSync(file); return file; } catch (e) { if (e.code === "ENOENT") return null; throw e; }
        };
        const active = new Set();
        let section = "";
        const read = file => {
            const absolute = path.resolve(process.env.HOME, file);
            if (active.has(absolute)) refuse("pacman-config=paru-include-cycle", 1);
            active.add(absolute);
            for (const raw of fs.readFileSync(absolute, "utf8").split(/\r?\n/)) {
                const entry = raw.trim();
                if (!entry || entry.startsWith("#")) continue;
                const heading = /^\[([^\]]+)\]$/.exec(entry);
                if (heading) { section = heading[1]; continue; }
                const split = entry.indexOf("=");
                if (split === -1) continue;
                const key = entry.slice(0, split).trim(), value = entry.slice(split + 1).trim();
                if (key === "Include") read(value);
                else if (section === "options" && key === "PacmanConf") original = value;
            }
            active.delete(absolute);
        };
        try {
            const config = process.env.PARU_CONF !== undefined ? process.env.PARU_CONF
                : optional(path.join(process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, ".config"), "paru", "paru.conf")) || optional("/etc/paru.conf");
            if (config !== null) read(config);
        } catch (e) { refuse("pacman-config=paru-unreadable error=" + e.code, 1); }
    }
    original = original === undefined ? "/etc/pacman.conf" : original;
    if (!original || /[\u0000-\u001f\u007f]/.test(original)) refuse("pacman-config=invalid-path", 1);
    if (apply !== null) {
        if (!path.isAbsolute(apply)) refuse("config=apply-relative");
        const at = words.findIndex(word => word === "--" || word === "--ignore");
        words.splice(at === -1 ? words.length : at, 0, "--config", apply);
    }
    process.stdout.write(JSON.stringify({config: path.resolve(process.env.HOME, original), argv: words}) + "\n");
