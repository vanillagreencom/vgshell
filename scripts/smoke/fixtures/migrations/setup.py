#!/usr/bin/env python3
"""Plant independent startup cases into a disposable shell tree and home."""
import json
import os
from pathlib import Path
import shutil
import sys

fixture, tree, home = map(Path, sys.argv[1:])
assert os.environ.get("VGS_TEST_RUN") == "1"
root = home / ".local/state/vgshell/migration-fixture"
if root.exists():
    shutil.rmtree(root)
root.mkdir(parents=True)
os.mkfifo(root / "release")
for suffix in ("service", "timer"):
    (root / ("old-sync." + suffix)).write_text("planted stand-in; never executed\n")

user = home / ".config/vgshell/plugins"
bundled = tree / "shell/plugins"
ids = ["acme.migrate-" + suffix for suffix in
       ("a-launch", "b-fail", "c-timeout", "d-clean", "d-late", "e-enabled", "f-user", "g-hidden", "h-absent")]
for plugin in ids:
    destination = (user if plugin.endswith("f-user") else bundled) / plugin
    shutil.copytree(fixture, destination, dirs_exist_ok=True)
    manifest = json.loads((destination / "manifest.json").read_text())
    manifest["id"] = plugin
    if plugin.endswith("d-clean"):
        manifest["formerIds"] = ["acme.migrate-former"]
    (destination / "manifest.json").write_text(json.dumps(manifest))
    if plugin.endswith("a-launch"):
        (destination / "migrate").write_text("#!/migration-fixture-no-interpreter\n")
    if plugin.endswith("h-absent"):
        (destination / "migrate").unlink()
    else:
        (destination / "migrate").chmod(0o755)
    if plugin.endswith("g-hidden"):
        shutil.copytree(destination, user / plugin, dirs_exist_ok=True)

config_path = home / ".config/vgshell/shell.json"
config = json.loads(config_path.read_text())
config["plugins"] = [row for row in config.get("plugins", []) if not row["id"].startswith("acme.migrate-")]
configured = lambda plugin: "acme.migrate-former" if plugin.endswith("d-clean") else plugin
config["plugins"].extend({"id": configured(plugin)} for plugin in ids)
# The production enablement judge uses disabledPlugins. A plugins[] row
# alone enables a third-party service; no per-row enabled field exists.
config["disabledPlugins"] = [plugin for plugin in config.get("disabledPlugins", [])
                             if not plugin.startswith("acme.migrate-")]
config["disabledPlugins"].extend(configured(plugin) for plugin in ids if not plugin.endswith("e-enabled"))
staged = config_path.with_suffix(".migration.json")
staged.write_text(json.dumps(config))
staged.replace(config_path)
