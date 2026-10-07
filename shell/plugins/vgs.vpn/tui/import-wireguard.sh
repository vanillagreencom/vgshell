#!/usr/bin/env bash
# NetworkManager reads the selected configuration directly. Its output can
# repeat the private file path or key, so only a parsed profile name is shown.
set -euo pipefail
# shellcheck source=/dev/null
source "${VGS_TUI_LIB:?}"
[[ $# == 0 ]] || { vgs_tui_error "This import request is invalid."; exit 2; }
vgs_tui_header "Import WireGuard" "Choose a WireGuard configuration file."
status=0
file="$(gum file --file)" || status=$?
case "$status" in
  0) [[ -n $file ]] || exit 0 ;;
  1|130) exit 0 ;;
  *) vgs_tui_error "The file picker could not open."; exit "$status" ;;
esac
status=0
reply="$(LC_ALL=C nmcli connection import type wireguard file "$file" 2>&1)" || status=$?
if [[ $status != 0 ]]; then
  vgs_tui_error "NetworkManager could not import this file."
  exit "$status"
fi
# nmcli --get-values queries an existing profile, but import exposes no
# documented identity field. Comparing inventories cannot identify this
# import if another client adds a profile at the same time.
# https://networkmanager.dev/docs/api/latest/nmcli.html
# libnm's nm_conn_wireguard_import returns an NMConnection before it is
# saved. This Bash TUI cannot receive the object from nmcli's process;
# using it would replace nmcli with a compiled or binding-based importer.
# https://networkmanager.dev/docs/libnm/latest/libnm-nm-conn-utils.html
pattern="^Connection '(.*)' \\([[:xdigit:]-]+\\) successfully added\\.$"
if [[ $reply =~ $pattern ]]; then
  name="${BASH_REMATCH[1]}"
  # A profile may use the file path as its name. Do not repeat that path.
  name="${name//"$file"/[private file]}"
  vgs_tui_success "Imported: $name"
else
  vgs_tui_success "WireGuard profile imported."
fi
