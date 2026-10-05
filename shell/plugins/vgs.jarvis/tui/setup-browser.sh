#!/usr/bin/env bash
# The core opens this script from the plugin's published snapshot.
# Every refusal and the missing-driver notice print one keyed line on stderr
# first, `jarvis: browser-setup=<key> ...`; one the user can act on then
# prints a plain sentence.
set -euo pipefail
source "$VGS_TUI_LIB"
refuse() { # STATUS KEY_LINE SENTENCE
  printf 'jarvis: browser-setup=%s\n' "$2" >&2
  [[ -z $3 ]] || vgs_tui_error "$3"
  exit "$1"
}
[[ $# == 0 ]] || refuse 2 arguments ""
command -v node >/dev/null || refuse 77 "missing command=node" ""
vgs_tui_lock jarvis-browser-setup
vgs_tui_header "Set up Jarvis browser" "Verifies a private browser on a blank page." "Jarvis does not use your signed-in browser."

# The driver is an optional requirement, so it may be absent. Its package
# for this system comes from the core's requirement judge, and the core's
# package runner installs it and rescans, as the requirement notice does.
install_driver() {
  printf 'jarvis: browser-setup=missing command=agent-browser\n' >&2
  vgs_tui_warn "Jarvis needs agent-browser to drive its private browser. It is not installed."
  vgs_tui_confirm "Install agent-browser now?" || exit 130
  local lib="$VGS_TUI_LIB" tree rows package manager name
  tree="${lib%/bin/lib/tui.sh}"
  [[ $tree != "$lib" && -n ${VGS_PLUGIN_ID:-} ]] ||
    refuse 2 "tui=missing" "Open this setup from Jarvis in Settings or the launcher."
  rows="$("$tree/bin/vgsh" plugin requirements --json "$VGS_PLUGIN_ID")"
  package="$(node -e '
const row = JSON.parse(process.argv[1]).find(entry => entry.command === "agent-browser");
if (row === undefined) { process.stderr.write("jarvis: browser-setup=undeclared command=agent-browser\n"); process.exit(1); }
process.stdout.write(row.package === null ? "" : row.package.manager + " " + row.package.name);
' "$rows")"
  [[ -n $package ]] || refuse 1 "no-package command=agent-browser" "VGS has no agent-browser package for this system."
  read -r manager name <<<"$package"
  "$tree/bin/vgsh" pkg run install --manager "$manager" "$name"
  command -v agent-browser >/dev/null ||
    refuse 1 "still-missing command=agent-browser" "agent-browser is installed, but this terminal cannot find it."
  vgs_tui_step "agent-browser installed"
}
command -v agent-browser >/dev/null || install_driver

program="$VGS_PLUGIN_DIR/backend/browser-setup.js"
result=0
node "$program" verify || result=$?
case "$result" in
  0) vgs_tui_step "Private browser ready" ;;
  69)
    vgs_tui_confirm "Download a private Chrome browser for Jarvis?" || exit 130
    node "$program" download
    node "$program" verify
    vgs_tui_step "Private browser ready" ;;
  *) exit "$result" ;;
esac
