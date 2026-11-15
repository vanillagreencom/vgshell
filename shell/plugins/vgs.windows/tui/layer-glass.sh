#!/usr/bin/env bash
# hyprpm owns binaries and elevation; the core alone writes configuration.
set -euo pipefail
finish() { printf 'layer-glass: category=%s\n' "$1"; [[ $# == 1 ]] || printf '%s\n' "$2" >&2; exit "${3:-1}"; }
[[ $# == 1 && $1 =~ ^(prepare|rebuild|enable|disable)$ ]] || finish invalid-request 'Open Windows and try again.' 2
[[ -n ${VGS_TUI_LIB:-} ]] || finish presenter-missing 'Open this setup from Windows.' 2
root=${VGS_TUI_LIB%/bin/lib/tui.sh}
[[ $root != "$VGS_TUI_LIB" ]] || finish presenter-missing 'Open this setup from Windows.' 2
# shellcheck source=/dev/null
source "$VGS_TUI_LIB"
verb=$1
for tool in hyprpm hyprctl python3 node; do
  command -v "$tool" >/dev/null || finish missing-tool 'Install the offered tools, then try again.'
done
if [[ $verb == prepare || $verb == rebuild ]]; then
  for tool in cpio cmake pkg-config g++ gcc git; do
    command -v "$tool" >/dev/null || finish missing-tool 'Install the offered tools, then try again.'
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
    if 'hyprglass' in names and entries.get('hyprglass') not in ('enabled', 'disabled', 'failed'):
        raise ValueError('unmanaged-plugin')
    unrelated = any(n != 'HyprGlass' for n in repositories) or any(n != 'hyprglass' for n in entries)
    print(entries.get('hyprglass', 'absent'), 'loaded' if 'hyprglass' in names else 'unloaded', 'other' if unrelated else 'only')
except (ValueError, TypeError) as error:
    print('layer-glass: category=' + str(error), file=sys.stderr)
    sys.exit(1)
PY
  ) || finish preflight-refused 'The plugin manager could not check your plugins safely. Check its details above.'
  read -r managed observed inventory <<<"$parsed"
}
mutate() {
  local status=0
  snapshot
  # update has no repository argument (hyprpm v0.57.1 main.cpp). Never
  # rebuild, update or load another repository as part of this request.
  [[ $1 != update || $inventory == only ]] || finish unrelated-rebuild 'Hyprglass cannot be rebuilt without changing your other plugins. No plugins were updated.'
  [[ $1 != enable || $observed == loaded ]] || finish not-loaded 'Layer glass setup could not finish. Try On again in Windows.'
  vgs_tui_commands "hyprpm $*"
  hyprpm "$@" || status=$?
  [[ $status != 130 ]] || finish interrupted 'The plugin manager was interrupted. Check its state in Windows.' 130
  [[ $status == 0 ]] || finish manager-failed 'The plugin manager could not complete this step. Check its details above.'
  snapshot
}
snapshot
vgs_tui_header 'Layer glass'
if [[ $verb == disable ]]; then
  printf '%s\n' 'Turn off all hyprglass effects, including those configured outside VGS. The plugin stays installed.'
elif [[ $verb == enable ]]; then
  [[ $managed != absent && $observed == loaded ]] || finish not-loaded 'Layer glass setup could not finish. Try On again in Windows.'
  printf '%s\n' 'Finish turning on layer glass. Turning it off later also turns off hyprglass effects configured outside VGS.'
else
  printf '%s\n' 'Turn on glass for VGS panels. Turning it off later also turns off hyprglass effects configured outside VGS.'
fi
if [[ $verb == rebuild || ( $verb == prepare && ( $managed == absent || $managed == failed ) ) ]]; then
  [[ $inventory == only ]] || finish unrelated-rebuild 'Hyprglass cannot be rebuilt without changing your other plugins. No plugins were updated.'
  printf '%s\n' 'Hyprglass will be built for your version of Hyprland.'
fi
case $verb in
  prepare) question='Turn on layer glass?' ;;
  enable) question='Finish turning on layer glass?' ;;
  rebuild) question='Rebuild layer glass?' ;;
  disable) question='Turn off hyprglass?' ;;
esac
answer=0
vgs_tui_confirm "$question" --default=false || answer=$?
case $answer in
  0) ;;
  1) finish canceled 'No changes were requested.' 10 ;;
  130) finish interrupted 'Setup was interrupted. Check its state in Windows.' 130 ;;
  *) finish consent-unavailable 'Could not confirm this change.' ;;
esac
if [[ $verb == disable ]]; then
  if [[ $managed != absent ]]; then mutate disable hyprglass; fi
  [[ $observed == unloaded ]] || finish residual-load 'The plugin is still loaded. Off could not be confirmed.'
elif [[ $verb == enable ]]; then
  # Enabling reconciles every managed plugin. Only register a target the
  # core already loaded and configured; reconciliation then skips its load.
  [[ $managed != absent && $observed == loaded ]] || finish not-loaded 'Layer glass setup could not finish. Try On again in Windows.'
  if [[ $managed != enabled ]]; then mutate enable hyprglass; fi
  [[ $observed == loaded && $managed == enabled ]] || finish not-enabled 'The plugin manager could not confirm your choice. Check again in Windows.'
elif [[ $verb == rebuild || $managed == absent || $managed == failed ]]; then
  # update reconciles enabled entries, including a failed build's hidden
  # enabled flag. Disable every existing target before either update path.
  if [[ $managed != absent ]]; then
    mutate disable hyprglass
  fi
  [[ $observed == unloaded ]] || finish residual-load 'The plugin is still on. Try Off again in Windows.'
  if [[ $verb == rebuild ]]; then mutate update --force; else mutate update; fi
  if [[ $managed == absent ]]; then mutate add https://github.com/hyprnux/hyprglass; fi
  [[ $managed != failed && $managed != absent ]] || finish build-failed 'The plugin did not build. Check its details above before rebuilding.'
  [[ $managed == disabled && $observed == unloaded ]] || finish unexpected-load 'Layer glass setup could not finish. Check again in Windows.'
fi
finish manager-complete 'VGS will continue the layer-glass request.' 0
