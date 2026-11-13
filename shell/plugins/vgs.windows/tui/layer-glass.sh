#!/usr/bin/env bash
# hyprpm owns binaries and elevation; the core alone writes configuration.
set -euo pipefail
finish() { printf 'layer-glass: category=%s\n' "$1"; [[ $# == 1 ]] || printf '%s\n' "$2" >&2; exit "${3:-1}"; }
[[ $# == 1 && $1 =~ ^(enable|disable|rebuild)$ ]] || finish invalid-request 'Open Windows and try again.' 2
[[ -n ${VGS_TUI_LIB:-} ]] || finish presenter-missing 'Open this setup from Windows.' 2
root=${VGS_TUI_LIB%/bin/lib/tui.sh}
[[ $root != "$VGS_TUI_LIB" ]] || finish presenter-missing 'Open this setup from Windows.' 2
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
verb=$1
for tool in hyprpm hyprctl python3 node; do
  command -v "$tool" >/dev/null || finish missing-tool 'Install the offered requirements, then try again.'
done
if [[ $verb != disable ]]; then
  for tool in cpio cmake pkg-config g++ gcc git; do
    command -v "$tool" >/dev/null || finish missing-tool 'Install the offered build requirements, then try again.'
  done
fi

# The public inventory grammar and enable/disable reconciliation are from
# https://github.com/hyprwm/Hyprland/blob/v0.57.1/hyprpm/src/core/PluginManager.cpp
# listAllPlugins / ensurePluginsLoadState. The latter touches every managed
# plugin, so unrelated enabled and loaded sets must already agree.
snapshot() {
  local manager loaded parsed
  manager=$(hyprpm list) || finish manager-unread 'Could not read the plugin manager. Try Check again.'
  loaded=$(hyprctl -j plugin list) || finish compositor-unread 'Could not read the running plugins. Try Check again.'
  loaded=$(node - "$root" "$loaded" <<'JS'
const path = require("path");
const root = process.argv[2];
const state = require(path.join(root, "bin/lib/qml-library.js")).load(path.join(root, "shell/Core/HyprlandState.js"));
const read = state.layerGlassRead("plugins", process.argv[3], "");
if (!read.ok) process.exit(1);
process.stdout.write(JSON.stringify(read.value.map(row => row.name)));
JS
  ) || finish compositor-format 'Could not read the running plugins. Try Check again.'
  parsed=$(python3 - "$manager" "$loaded" <<'PY'
import json, re, sys
try:
    lines = re.sub(r'\x1b\[[0-9;]*m', '', sys.argv[1]).splitlines()
    entries, pending, repository, repositories = {}, None, None, []
    if lines and lines[0] == "→ The hyprpm state store doesn't exist. Creating now...":
        lines = lines[1:]
    for line in lines:
        if not line:
            continue
        match = re.fullmatch(r'→ Repository (.+) \(by .+\):', line)
        if match:
            if pending is not None:
                raise ValueError('incomplete-entry')
            repository = match[1]
            repositories.append(repository)
        elif re.fullmatch(r'  │ Plugin [^\s]+', line) and repository is not None and pending is None:
            pending = line.removeprefix('  │ Plugin ')
            if pending in entries:
                raise ValueError('duplicate-manager-name')
        elif pending is not None and line in ('  └─ enabled: true', '  └─ enabled: false', '  └─ enabled: Plugin failed to build'):
            entries[pending] = {'  └─ enabled: true': 'enabled', '  └─ enabled: false': 'disabled', '  └─ enabled: Plugin failed to build': 'failed'}[line]
            if pending == 'hyprglass' and repository != 'HyprGlass':
                raise ValueError('foreign-repository')
            pending = None
        else:
            raise ValueError('manager-format')
    if pending is not None:
        raise ValueError('incomplete-entry')
    loaded = json.loads(sys.argv[2])
    names = set(loaded)
    if len(names) != len(loaded):
        raise ValueError('duplicate-loaded-name')
    unrelated_loaded = names - {'hyprglass'}
    unrelated_enabled = {n for n, state in entries.items() if state == 'enabled'} - {'hyprglass'}
    if unrelated_loaded != unrelated_enabled:
        raise ValueError('unrelated-plugin-conflict')
    if 'hyprglass' in names and entries.get('hyprglass') not in ('enabled', 'disabled'):
        raise ValueError('unmanaged-plugin')
    unrelated = any(n != 'HyprGlass' for n in repositories) or any(n != 'hyprglass' for n in entries)
    print(entries.get('hyprglass', 'absent'), 'loaded' if 'hyprglass' in names else 'unloaded', 'other' if unrelated else 'only')
except (ValueError, TypeError) as error:
    print('layer-glass: category=' + str(error), file=sys.stderr)
    sys.exit(1)
PY
  ) || finish preflight-refused 'The managed plugin state is unreadable or conflicts with another loaded plugin. No further changes were made.'
  read -r managed observed inventory <<<"$parsed"
}
mutate() {
  local status=0
  snapshot
  # update has no repository argument (hyprpm v0.57.1 main.cpp). Never
  # rebuild, update or load another repository as part of this request.
  [[ $1 != update || $inventory == only ]] || finish unrelated-rebuild 'Hyprpm cannot rebuild only hyprglass while other plugin repositories are installed. No update was started.'
  vgs_tui_commands "hyprpm $*"
  hyprpm "$@" || status=$?
  [[ $status != 130 ]] || finish interrupted 'The plugin manager was interrupted. Check its state in Windows.' 130
  [[ $status == 0 ]] || finish manager-failed 'The plugin manager could not complete this step. Check its details above.'
  snapshot
}
snapshot
vgs_tui_header 'Layer glass'
if [[ $verb == disable ]]; then
  printf '%s\n' 'This turns off the whole hyprglass plugin, including glass configured outside VGS. Packages and the repository stay installed.'
else
  printf '%s\n' 'This installs or enables hyprglass for VGS layers. Window glass stays off. Turning this off later unloads the whole plugin, including glass configured outside VGS.'
fi
if [[ $verb != disable && ( $verb == rebuild || $managed == absent || $managed == failed ) ]]; then
  [[ $inventory == only ]] || finish unrelated-rebuild 'Hyprpm cannot rebuild only hyprglass while other plugin repositories are installed. No update was started.'
  printf '%s\n' 'Hyprpm will prepare its headers and build hyprglass. No other plugin repository is installed.'
fi
answer=0
vgs_tui_confirm 'Continue?' --default=false || answer=$?
case $answer in
  0) ;;
  1) finish canceled 'No changes were requested.' 10 ;;
  130) finish interrupted 'Setup was interrupted. Check its state in Windows.' 130 ;;
  *) finish consent-unavailable 'Could not confirm this change.' ;;
esac
if [[ $verb == disable ]]; then
  if [[ $managed != absent ]]; then mutate disable hyprglass; fi
  [[ $observed == unloaded ]] || finish residual-load 'The plugin is still loaded. Off could not be confirmed.'
elif [[ $verb == rebuild || $managed == absent || $managed == failed ]]; then
  if [[ $verb == rebuild ]]; then
    # update replaces binaries but skips an already loaded enabled plugin.
    # Unload this target first so enable maps the newly built binary.
    if [[ $managed == enabled || $observed == loaded ]]; then mutate disable hyprglass; fi
    [[ $observed == unloaded ]] || finish residual-load 'The plugin is still loaded. Rebuild could not start.'
    mutate update --force
  else
    mutate update
  fi
  if [[ $managed == absent ]]; then mutate add https://github.com/hyprnux/hyprglass; fi
  [[ $managed != failed && $managed != absent ]] || finish build-failed 'The plugin did not build. Check its details above before rebuilding.'
  if [[ $managed != enabled || $observed != loaded ]]; then mutate enable hyprglass; fi
  [[ $observed == loaded ]] || finish not-loaded 'The plugin is not loaded in this session. Check its state in Windows.'
else
  if [[ $managed != enabled || $observed != loaded ]]; then mutate enable hyprglass; fi
  [[ $observed == loaded ]] || finish not-loaded 'The plugin is not loaded in this session. Try Rebuild.'
fi
finish manager-complete 'VGS will now verify the layer-glass configuration.' 0
