#!/usr/bin/env node
// Row-owned audio fixture: generate the same files SoundRule installs.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../../../bin/lib/qml-library.js");
const [plugin, home] = process.argv.slice(2);
if (!plugin || !home || process.argv.length !== 4) throw new Error("expected PLUGIN_DIR HOME");
const commons = { "qs.Commons 1.0": { PageReference: load(path.join(__dirname, "../../../shell/Commons/PageReference.js")) } };
const logic = load(path.join(plugin, "NotificationLogic.js"), commons);
const script = fs.readFileSync(path.join(plugin, "wireplumber/vgs-notification-sounds.lua"), "utf8");
const version = logic.soundRuleVersion(script);
const copy = path.join(home, ".local/share/wireplumber/scripts/vgs-notification-sounds.lua");
for (const [file, text] of [
    [copy, script],
    [path.join(home, ".config/wireplumber/wireplumber.conf.d/90-vgs-notification-sounds.conf"), logic.soundRuleFragment(copy, version)],
    [path.join(home, ".config/pipewire/pipewire.conf.d/90-vgs-notification-hold.conf"), logic.soundHoldFragment()]
]) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
}
process.stdout.write(version + "\n");
