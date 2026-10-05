#!/usr/bin/env python3
# Stand-in `vgsh` for the browser setup TUI's driver install. Rows follow
# `vgsh plugin requirements --json`'s documented shape (bin/vgsh header) and
# the manifest's agent-browser entry. Logs argv; installs nothing: an install
# copies the fixture driver into the driverless PATH directory.
import json, pathlib, shutil, sys
root = pathlib.Path(__file__).resolve().parents[2]
mode_path = root / 'browser-mode.json'
mode = json.loads(mode_path.read_text()) if mode_path.exists() else {}
args = sys.argv[1:]
with (root / 'vgsh-calls.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\n')
if args == ['plugin', 'requirements', '--json', 'vgs.jarvis']:
    print(json.dumps([{
        'command': 'agent-browser', 'packages': {'aur': 'agent-browser-bin', 'mise': 'npm:agent-browser'},
        'optional': True, 'purpose': 'Drives a private Jarvis browser; requires version 0.38.1 or later',
        'state': 'missing', 'package': mode.get('driverPackage', {'manager': 'aur', 'name': 'agent-browser-bin'})}]))
    sys.exit(0)
if args[:3] == ['pkg', 'run', 'install']:
    if mode.get('driverReachable', True):
        target = root / 'driverless' / 'agent-browser'
        shutil.copyfile(root / 'standins' / 'agent-browser', target)
        target.chmod(0o700)
    sys.exit(0)
print('browser-vgsh: refused: argv=' + json.dumps(args), file=sys.stderr)
sys.exit(2)
