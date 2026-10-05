#!/usr/bin/env bash
# The vgs.polkit floating TUI behind the status row's Stop: ends each other
# polkit agent and records its program, so VGS ends it again in a later
# session, and changes no package. bin/agents states the step and its
# refusals; bin/vgsh-tui runs this from a private copy of the plugin's
# snapshot, so the script is under VGS_PLUGIN_DIR and the VGS tree is the
# one VGS_TUI_LIB lies in.
#
# `polkit: refused: tui=missing`, exit 2, outside the presenter.
set -euo pipefail

lib="${VGS_TUI_LIB:-}"
tree="${lib%/bin/lib/tui.sh}"
if [[ -z $lib || $tree == "$lib" || -z ${VGS_PLUGIN_DIR:-} ]]; then
  printf 'polkit: refused: tui=missing\nrun this through the vgs.polkit floating TUI, which sets VGS_TUI_LIB and VGS_PLUGIN_DIR\n' >&2
  exit 2
fi
exec "$VGS_PLUGIN_DIR/bin/agents" --tree "$tree" stop
