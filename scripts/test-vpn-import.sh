#!/usr/bin/env bash
# The shipped VPN import script with private fake gum, nmcli and the core's
# requirement reader. Scanner tests own the .name file layouts. Each TUI
# run gets only the fake tools and node on PATH, and no display variables.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$repo" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile
repo = pathlib.Path(sys.argv[1])
script = repo / 'shell/plugins/vgs.vpn/tui/import.sh'
with tempfile.TemporaryDirectory(prefix='vpn-import-') as directory:
    root = pathlib.Path(directory)
    tools = root / 'tools'
    tools.mkdir()
    (tools / 'bash').symlink_to(shutil.which('bash'))
    node = subprocess.check_output([shutil.which('node'), '-p', 'process.execPath'],
                                   env={'PATH': os.environ.get('PATH', '')}, text=True).strip()
    (tools / 'node').symlink_to(node)
    lib = root / 'bin/lib'
    lib.mkdir(parents=True)
    (lib / 'tui.sh').symlink_to(repo / 'bin/lib/tui.sh')
    fake = '#!' + sys.executable + '\n' + '''import json, os, pathlib, sys
root = pathlib.Path(os.environ['FAKE_ROOT'])
config = json.loads((root / 'config.json').read_text())
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([name, args]) + '\\n')
if name == 'vgshell':
    assert args == ['plugin', 'requirements', '--json', 'vgs.vpn'], args
    state = config['plugin']
    if state == 'unreadable':
        sys.exit(1)
    if state == 'malformed':
        print('{')
    else:
        print(json.dumps([] if state == 'undeclared' else [{
            'name': 'org.freedesktop.NetworkManager.openvpn', 'state': state
        }]))
elif name == 'gum':
    if args[0] == 'file':
        print(config['path'])
        sys.exit(config['picker'])
    print(args[-1])
else:
    print(config['reply'])
    sys.exit(config['exit'])
'''
    for name in ('gum', 'nmcli'):
        (tools / name).write_text(fake)
        (tools / name).chmod(0o755)
    (root / 'bin/vgshell').write_text(fake)
    (root / 'bin/vgshell').chmod(0o755)
    private = root / 'private key files'
    conf = str(private / 'Home tunnel.conf')
    ovpn = str(private / 'Office VPN.ovpn')
    secret = 'PrivateKey = PRIVATE-FIXTURE-NEVER-SHOW'
    added = "Connection '{}' (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee) successfully added."
    # name, picker status, picked path, core plugin state, nmcli status,
    # nmcli reply, nmcli import type or None, exit status, names the output
    # must show. An installed plugin is idle: nothing answers on any bus.
    rows = [
        ('cancel', 1, conf, 'missing', 0, '', None, 0, []),
        ('interrupt', 130, conf, 'missing', 0, '', None, 0, []),
        ('empty', 0, '', 'missing', 0, '', None, 0, []),
        ('wireguard', 0, conf, 'missing', 0, added.format('Home tunnel'), 'wireguard', 0, ['Home tunnel']),
        ('wireguard-refusal', 0, conf, 'missing', 10, conf + '\n' + secret, 'wireguard', 10, []),
        ('path-as-name', 0, conf, 'missing', 0, added.format(conf), 'wireguard', 0, []),
        ('openvpn-installed', 0, ovpn, 'present', 0, added.format('Office VPN'), 'openvpn', 0, ['Office VPN']),
        ('openvpn-refusal', 0, ovpn, 'present', 1, "Error: failed to import '" + ovpn + "': " + secret, 'openvpn', 1, []),
        ('openvpn-plugin-absent', 0, ovpn, 'missing', 0, '', None, 69, []),
        ('core-read-failed', 0, ovpn, 'unreadable', 0, '', None, 69, []),
        ('core-read-malformed', 0, ovpn, 'malformed', 0, '', None, 69, []),
        ('core-requirement-undeclared', 0, ovpn, 'undeclared', 0, '', None, 69, []),
        ('other-extension', 0, str(private / 'Office VPN.txt'), 'present', 0, '', None, 69, []),
        ('upper-case-conf', 0, str(private / 'Home tunnel.CONF'), 'present', 0, '', None, 69, []),
        ('extension-on-directory', 0, str(private / 'tunnels.conf' / 'home'), 'present', 0, '', None, 69, []),
    ]
    def suite(target):
        outputs = {}
        for name, picker, selected, plugin, code, reply, kind, status, identity in rows:
            (root / 'config.json').write_text(json.dumps({'picker': picker, 'path': selected, 'exit': code, 'reply': reply, 'plugin': plugin}))
            (root / 'calls.jsonl').write_text('')
            result = subprocess.run([str(tools / 'bash'), str(target)], env={
                'PATH': str(tools), 'HOME': str(root), 'VGS_TUI_LIB': str(lib / 'tui.sh'),
                'FAKE_ROOT': str(root), 'LC_ALL': 'C', 'VGS_TEST_RUN': '1'
            }, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            imports = [argv for tool, argv in calls if tool == 'nmcli']
            expected = [] if kind is None else [['connection', 'import', 'type', kind, 'file', selected]]
            assert imports == expected, (name, imports, result.returncode, result.stdout, result.stderr)
            assert result.returncode == status, (name, result.returncode)
            output = result.stdout + result.stderr
            assert str(private) not in output and secret not in output, name
            for value in identity:
                assert value in result.stdout, (name, 'missing imported identity')
            outputs[name] = output.strip()
        # The two refusals tell the user different things.
        assert outputs['openvpn-plugin-absent'] and outputs['other-extension'], 'empty refusal'
        assert outputs['openvpn-plugin-absent'] != outputs['other-extension'], 'one refusal for two causes'
    suite(script)
    source = script.read_text()
    controls = [
        ('unquoted-path', 'file "$file" 2>&1', 'file $file 2>&1'),
        ('private-refusal-output', 'vgs_tui_error "NetworkManager could not import this file."', 'vgs_tui_error "$reply"'),
        ('profile-identity', 'vgs_tui_success "Imported: $name"', 'vgs_tui_success "Imported"'),
        ('openvpn-type', 'type=openvpn', 'type=wireguard'),
        ('plugin-absent-imports', '[[ $plugin_state == present ]]', '[[ true ]]'),
        ('case-blind-conf', '  *.conf) type=wireguard ;;', '  *.[cC][oO][nN][fF]) type=wireguard ;;'),
        ('other-extension-imports', 'files."; exit 69 ;;', 'files."; type=wireguard ;;'),
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
