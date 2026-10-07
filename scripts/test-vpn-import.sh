#!/usr/bin/env bash
# The shipped WireGuard import script with private fake gum and nmcli.
# No run can resolve a host NetworkManager command or authentication tool.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$repo" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile
repo = pathlib.Path(sys.argv[1])
script = repo / 'shell/plugins/vgs.vpn/tui/import-wireguard.sh'
with tempfile.TemporaryDirectory(prefix='vpn-import-') as directory:
    root = pathlib.Path(directory)
    tools = root / 'tools'
    tools.mkdir()
    (tools / 'bash').symlink_to(shutil.which('bash'))
    fake = '#!' + sys.executable + '\n' + '''import json, os, pathlib, sys
root = pathlib.Path(os.environ['FAKE_ROOT'])
config = json.loads((root / 'config.json').read_text())
name = pathlib.Path(sys.argv[0]).name
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([name, sys.argv[1:]]) + '\\n')
if name == 'gum':
    if sys.argv[1] == 'file':
        print(config['path'])
        sys.exit(config['picker'])
    print(sys.argv[-1])
else:
    print(config['reply'])
    sys.exit(config['exit'])
'''
    for name in ('gum', 'nmcli'):
        (tools / name).write_text(fake)
        (tools / name).chmod(0o755)
    private_path = str(root / 'private key files' / 'Home tunnel.conf')
    secret = 'PrivateKey = PRIVATE-FIXTURE-NEVER-SHOW'
    rows = [
        ('cancel', 1, private_path, 0, '', []),
        ('interrupt', 130, private_path, 0, '', []),
        ('empty', 0, '', 0, '', []),
        ('spaces', 0, private_path, 0, "Connection 'Home tunnel' (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee) successfully added.", ['Home tunnel']),
        ('refusal', 0, private_path, 10, private_path + '\n' + secret, []),
        ('path-as-name', 0, private_path, 0, "Connection '" + private_path + "' (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee) successfully added.", []),
    ]
    def suite(target):
        for name, picker, selected, code, reply, identity in rows:
            (root / 'config.json').write_text(json.dumps({'picker': picker, 'path': selected, 'exit': code, 'reply': reply}))
            (root / 'calls.jsonl').write_text('')
            result = subprocess.run([str(tools / 'bash'), str(target)], env={
                'PATH': str(tools), 'HOME': str(root), 'VGS_TUI_LIB': str(repo / 'bin/lib/tui.sh'),
                'FAKE_ROOT': str(root), 'LC_ALL': 'C', 'VGS_TEST_RUN': '1'
            }, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            imports = [argv for tool, argv in calls if tool == 'nmcli']
            expected = [] if picker or not selected else [['connection', 'import', 'type', 'wireguard', 'file', selected]]
            assert imports == expected, (name, imports)
            assert result.returncode == (code if expected else 0), (name, result.returncode)
            output = result.stdout + result.stderr
            assert private_path not in output and secret not in output, name
            for value in identity:
                assert value in result.stdout, (name, 'missing imported identity')
    suite(script)
    source = script.read_text()
    controls = [
        ('unquoted-path', 'file "$file" 2>&1', 'file $file 2>&1'),
        ('private-refusal-output', 'vgs_tui_error "NetworkManager could not import this file."', 'vgs_tui_error "$reply"'),
        ('profile-identity', 'vgs_tui_success "Imported: $name"', 'vgs_tui_success "Imported"'),
    ]
    for name, old, new in controls:
        assert source.count(old) == 1, name
        mutant = root / (name + '.sh')
        mutant.write_text(source.replace(old, new))
        try:
            suite(mutant)
        except AssertionError:
            print('vpn-import: control=' + name + ' red')
        else:
            raise AssertionError('surviving control: ' + name)
print('vpn-import: passed')
PY
