#!/usr/bin/env bash
# The shipped VPN import script with private fake gum, nmcli and busctl.
# No run can resolve a host NetworkManager command, bus or authentication
# tool, and the explicit environment holds no display variable.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$repo" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile
repo = pathlib.Path(sys.argv[1])
script = repo / 'shell/plugins/vgs.vpn/tui/import.sh'
PLUGIN = 'org.freedesktop.NetworkManager.openvpn'
with tempfile.TemporaryDirectory(prefix='vpn-import-') as directory:
    root = pathlib.Path(directory)
    tools = root / 'tools'
    tools.mkdir()
    (tools / 'bash').symlink_to(shutil.which('bash'))
    # busctl models two buses: the system bus holds the row's names, any
    # other bus only the bus driver. Without --json=short it prints busctl's
    # text form, which the JSON reader must not accept.
    fake = '#!' + sys.executable + '\n' + '''import json, os, pathlib, sys
root = pathlib.Path(os.environ['FAKE_ROOT'])
config = json.loads((root / 'config.json').read_text())
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps([name, args]) + '\\n')
if name == 'gum':
    if args[0] == 'file':
        print(config['path'])
        sys.exit(config['picker'])
    print(args[-1])
elif name == 'busctl':
    bus = config['bus']
    if bus == 'fail':
        print('Failed to connect to bus: No such file or directory', file=sys.stderr)
        sys.exit(1)
    names = ['org.freedesktop.DBus']
    if '--system' in args:
        if args[-1] == 'ListNames' and bus == 'owned':
            names.append(PLUGIN)
        if args[-1] == 'ListActivatableNames' and bus == 'activatable':
            names.append(PLUGIN)
    if '--json=short' in args:
        print(json.dumps({'type': 'as', 'data': [names]}, separators=(',', ':')))
    else:
        print('as ' + str(len(names)) + ' ' + ' '.join('"' + n + '"' for n in names))
else:
    print(config['reply'])
    sys.exit(config['exit'])
'''.replace('PLUGIN', repr(PLUGIN))
    for name in ('gum', 'nmcli', 'busctl'):
        (tools / name).write_text(fake)
        (tools / name).chmod(0o755)
    private = root / 'private key files'
    conf = str(private / 'Home tunnel.conf')
    ovpn = str(private / 'Office VPN.ovpn')
    secret = 'PrivateKey = PRIVATE-FIXTURE-NEVER-SHOW'
    added = "Connection '{}' (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee) successfully added."
    # name, picker status, picked path, OpenVPN plugin on the bus, nmcli
    # status, nmcli reply, nmcli import type or None, exit status, names
    # the output must show.
    rows = [
        ('cancel', 1, conf, 'absent', 0, '', None, 0, []),
        ('interrupt', 130, conf, 'absent', 0, '', None, 0, []),
        ('empty', 0, '', 'absent', 0, '', None, 0, []),
        ('wireguard', 0, conf, 'absent', 0, added.format('Home tunnel'), 'wireguard', 0, ['Home tunnel']),
        ('wireguard-refusal', 0, conf, 'absent', 10, conf + '\n' + secret, 'wireguard', 10, []),
        ('path-as-name', 0, conf, 'absent', 0, added.format(conf), 'wireguard', 0, []),
        ('openvpn-owned', 0, ovpn, 'owned', 0, added.format('Office VPN'), 'openvpn', 0, ['Office VPN']),
        ('openvpn-activatable', 0, ovpn, 'activatable', 0, added.format('Office VPN'), 'openvpn', 0, ['Office VPN']),
        ('openvpn-refusal', 0, ovpn, 'owned', 1, "Error: failed to import '" + ovpn + "': " + secret, 'openvpn', 1, []),
        ('openvpn-plugin-absent', 0, ovpn, 'absent', 0, '', None, 69, []),
        ('openvpn-bus-unread', 0, ovpn, 'fail', 0, '', None, 1, []),
        ('other-extension', 0, str(private / 'Office VPN.txt'), 'owned', 0, '', None, 69, []),
        ('upper-case-conf', 0, str(private / 'Home tunnel.CONF'), 'owned', 0, '', None, 69, []),
        ('extension-on-directory', 0, str(private / 'tunnels.conf' / 'home'), 'owned', 0, '', None, 69, []),
    ]
    def suite(target):
        outputs = {}
        for name, picker, selected, bus, code, reply, kind, status, identity in rows:
            (root / 'config.json').write_text(json.dumps({'picker': picker, 'path': selected, 'bus': bus, 'exit': code, 'reply': reply}))
            (root / 'calls.jsonl').write_text('')
            result = subprocess.run([str(tools / 'bash'), str(target)], env={
                'PATH': str(tools), 'HOME': str(root), 'VGS_TUI_LIB': str(repo / 'bin/lib/tui.sh'),
                'FAKE_ROOT': str(root), 'LC_ALL': 'C', 'VGS_TEST_RUN': '1'
            }, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)
            calls = [json.loads(line) for line in (root / 'calls.jsonl').read_text().splitlines()]
            imports = [argv for tool, argv in calls if tool == 'nmcli']
            expected = [] if kind is None else [['connection', 'import', 'type', kind, 'file', selected]]
            assert imports == expected, (name, imports)
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
        ('plugin-absent-imports', '  return 1\n}', '  return 0\n}'),
        ('activatable-unread', 'for method in ListNames ListActivatableNames; do', 'for method in ListNames; do'),
        ('session-bus', 'busctl --system', 'busctl --user'),
        ('text-reply-read', ' --json=short call', ' call'),
        ('bus-failure-as-absent', '2>/dev/null)" || return 2', '2>/dev/null)" || return 1'),
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
