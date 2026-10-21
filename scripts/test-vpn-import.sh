#!/usr/bin/env bash
# The shipped VPN import script with private fake gum and nmcli. Each run
# goes through bubblewrap: read-only overlays of /usr and /etc show the
# row's stand-in plugin files at the two directories NetworkManager reads,
# over the host's own, and the host is left as it was. No run can resolve
# a host NetworkManager command, bus or authentication tool, and the
# explicit environment holds no display variable. Exit 77 when bubblewrap
# cannot build that view.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$repo" <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile
repo = pathlib.Path(sys.argv[1])
script = repo / 'shell/plugins/vgs.vpn/tui/import.sh'
bwrap = shutil.which('bwrap')
# networkmanager-openvpn 1.12.5's file, and one of another plugin.
OPENVPN = """[VPN Connection]
name=openvpn
service=org.freedesktop.NetworkManager.openvpn
program=/usr/lib/nm-openvpn-service
supports-multiple-connections=true

[libnm]
plugin=libnm-vpn-plugin-openvpn.so
"""
VPNC = """[VPN Connection]
name=vpnc
service=org.freedesktop.NetworkManager.vpnc
program=/usr/lib/nm-vpnc-service
"""
# Where each layout puts its files: lib is /usr/lib/NetworkManager/VPN,
# etc /etc/NetworkManager/VPN. `other` holds the OpenVPN file only under a
# name NetworkManager does not read.
LAYOUTS = {
    'none': {},
    'lib': {('lib', 'nm-openvpn-service.name'): OPENVPN},
    'etc': {('etc', 'nm-openvpn-service.name'): OPENVPN},
    'other': {('lib', 'nm-vpnc-service.name'): VPNC, ('lib', 'nm-openvpn-service.conf'): OPENVPN},
}
with tempfile.TemporaryDirectory(prefix='vpn-import-') as directory:
    root = pathlib.Path(directory)
    tools = root / 'tools'
    tools.mkdir()
    (tools / 'bash').symlink_to(shutil.which('bash'))
    # Mount points the overlays add where the host has no such directory.
    points = root / 'points'
    for point in ('usr/lib/NetworkManager/VPN', 'etc/NetworkManager/VPN'):
        (points / point).mkdir(parents=True)
    plugins = {'lib': root / 'plugins-lib', 'etc': root / 'plugins-etc'}
    view = [bwrap, '--dev-bind', '/', '/', '--unshare-all', '--die-with-parent',
            '--overlay-src', '/usr', '--overlay-src', str(points / 'usr'), '--ro-overlay', '/usr',
            '--overlay-src', '/etc', '--overlay-src', str(points / 'etc'), '--ro-overlay', '/etc',
            '--ro-bind', str(plugins['lib']), '/usr/lib/NetworkManager/VPN',
            '--ro-bind', str(plugins['etc']), '/etc/NetworkManager/VPN', '--']
    def plant(layout):
        for place in plugins.values():
            shutil.rmtree(place, ignore_errors=True)
            place.mkdir()
        for (place, name), text in LAYOUTS[layout].items():
            (plugins[place] / name).write_text(text)
    plant('lib')
    probe = subprocess.run(view + ['/usr/bin/test', '-f', '/usr/lib/NetworkManager/VPN/nm-openvpn-service.name'],
                           env={'PATH': '/usr/bin'}, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10) if bwrap else None
    if probe is None or probe.returncode != 0:
        print('vpn-import: bwrap=' + ('missing' if probe is None else 'refused'), file=sys.stderr)
        if probe is not None:
            print(probe.stderr.strip(), file=sys.stderr)
        sys.exit(77)
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
else:
    print(config['reply'])
    sys.exit(config['exit'])
'''
    for name in ('gum', 'nmcli'):
        (tools / name).write_text(fake)
        (tools / name).chmod(0o755)
    private = root / 'private key files'
    conf = str(private / 'Home tunnel.conf')
    ovpn = str(private / 'Office VPN.ovpn')
    secret = 'PrivateKey = PRIVATE-FIXTURE-NEVER-SHOW'
    added = "Connection '{}' (aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee) successfully added."
    # name, picker status, picked path, plugin file layout, nmcli status,
    # nmcli reply, nmcli import type or None, exit status, names the output
    # must show. An installed plugin is idle: nothing answers on any bus.
    rows = [
        ('cancel', 1, conf, 'none', 0, '', None, 0, []),
        ('interrupt', 130, conf, 'none', 0, '', None, 0, []),
        ('empty', 0, '', 'none', 0, '', None, 0, []),
        ('wireguard', 0, conf, 'none', 0, added.format('Home tunnel'), 'wireguard', 0, ['Home tunnel']),
        ('wireguard-refusal', 0, conf, 'none', 10, conf + '\n' + secret, 'wireguard', 10, []),
        ('path-as-name', 0, conf, 'none', 0, added.format(conf), 'wireguard', 0, []),
        ('openvpn-installed', 0, ovpn, 'lib', 0, added.format('Office VPN'), 'openvpn', 0, ['Office VPN']),
        ('openvpn-installed-etc', 0, ovpn, 'etc', 0, added.format('Office VPN'), 'openvpn', 0, ['Office VPN']),
        ('openvpn-refusal', 0, ovpn, 'lib', 1, "Error: failed to import '" + ovpn + "': " + secret, 'openvpn', 1, []),
        ('openvpn-plugin-absent', 0, ovpn, 'none', 0, '', None, 69, []),
        ('openvpn-other-plugin', 0, ovpn, 'other', 0, '', None, 69, []),
        ('other-extension', 0, str(private / 'Office VPN.txt'), 'lib', 0, '', None, 69, []),
        ('upper-case-conf', 0, str(private / 'Home tunnel.CONF'), 'lib', 0, '', None, 69, []),
        ('extension-on-directory', 0, str(private / 'tunnels.conf' / 'home'), 'lib', 0, '', None, 69, []),
    ]
    def suite(target):
        outputs = {}
        for name, picker, selected, layout, code, reply, kind, status, identity in rows:
            (root / 'config.json').write_text(json.dumps({'picker': picker, 'path': selected, 'exit': code, 'reply': reply}))
            (root / 'calls.jsonl').write_text('')
            plant(layout)
            result = subprocess.run(view + [str(tools / 'bash'), str(target)], env={
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
        ('etc-unread', ' /etc/NetworkManager/VPN/*.name /usr', ' /usr'),
        ('lib-unread', '*.name /usr/lib/NetworkManager/VPN/*.name; do', '*.name; do'),
        ('any-plugin', 'org\\.freedesktop\\.NetworkManager\\.openvpn[[:space:]]*$', '.*$'),
        ('any-file-name', '/usr/lib/NetworkManager/VPN/*.name;', '/usr/lib/NetworkManager/VPN/*;'),
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
