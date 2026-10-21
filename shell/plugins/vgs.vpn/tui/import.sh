#!/usr/bin/env bash
# NetworkManager reads the selected file directly. Its output can repeat the
# private file path or key, so only a parsed profile name is shown.
set -euo pipefail
# shellcheck source=/dev/null
source "${VGS_TUI_LIB:?}"
[[ $# == 0 ]] || { vgs_tui_error "This import request is invalid."; exit 2; }
vgs_tui_header "Import a VPN file" "Choose a WireGuard (.conf) or OpenVPN (.ovpn) file."
status=0
file="$(gum file --file)" || status=$?
case "$status" in
  0) [[ -n $file ]] || exit 0 ;;
  1|130) exit 0 ;;
  *) vgs_tui_error "The file picker could not open."; exit "$status" ;;
esac

# Present when one of the plugin files NetworkManager reads declares the
# OpenVPN service. NetworkManager starts a VPN plugin itself from its
# file's program, and the plugin owns its bus name only while a connection
# is up, so no bus answers for an installed, idle plugin. The two
# directories are the ones the NetworkManager 1.58.1 daemon holds (strings
# /usr/bin/NetworkManager, run 2026-10-20); networkmanager-openvpn 1.12.5
# installs /usr/lib/NetworkManager/VPN/nm-openvpn-service.name.
openvpn_plugin() {
  local file line
  for file in /etc/NetworkManager/VPN/*.name /usr/lib/NetworkManager/VPN/*.name; do
    [[ -f $file && -r $file ]] || continue
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line =~ ^[[:space:]]*service[[:space:]]*=[[:space:]]*org\.freedesktop\.NetworkManager\.openvpn[[:space:]]*$ ]] && return 0
    done <"$file"
  done
  return 1
}

# Case-sensitive: libnm refuses a WireGuard file whose name does not end in
# ".conf" ("must be a valid interface name followed by .conf").
case "$file" in
  *.conf) type=wireguard ;;
  *.ovpn)
    type=openvpn
    openvpn_plugin || { vgs_tui_warn "This OpenVPN file needs NetworkManager's OpenVPN plugin."; exit 69; }
    ;;
  *) vgs_tui_warn "VGS imports WireGuard (.conf) and OpenVPN (.ovpn) files."; exit 69 ;;
esac

status=0
reply="$(LC_ALL=C nmcli connection import type "$type" file "$file" 2>&1)" || status=$?
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
  vgs_tui_success "VPN profile imported."
fi
