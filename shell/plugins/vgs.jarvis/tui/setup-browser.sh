#!/usr/bin/env bash
# The core opens this script from the plugin's published snapshot.
# Every refusal and the missing-driver notice add one keyed line,
# `jarvis: browser-setup=<key> ...`, to the Jarvis setup log, with the
# helpers' keyed and vendor lines; the screen shows a plain sentence.
set -euo pipefail
source "$VGS_TUI_LIB"
log="${XDG_STATE_HOME:-$HOME/.local/state}/vgshell/jarvis/setup.log"
[[ $# == 0 ]] ||
  vgs_tui_refuse "$log" 2 "jarvis: browser-setup=arguments" \
    "Open Set up browser from the Jarvis page in Settings." || exit
command -v node >/dev/null || vgs_tui_refuse "$log" 77 "jarvis: browser-setup=missing command=node" \
  "Install the requirements on the Jarvis page in Plugins first." || exit
vgs_tui_lock jarvis-browser-setup
vgs_tui_header "Set up Jarvis browser" "Jarvis gets a private browser of its own and checks it on a blank page." \
  "Jarvis does not use your own browser or its sign-ins."

# The driver is an optional requirement, so it may be absent. Its package
# for this system comes from the core's requirement judge, and the core's
# package runner installs it and rescans, as the requirement notice does.
install_driver() {
  vgs_tui_note "$log" "jarvis: browser-setup=missing command=agent-browser" || :
  vgs_tui_warn "Jarvis needs agent-browser to drive its private browser. It is not installed."
  vgs_tui_confirm "Install agent-browser now?" || exit 130
  local lib="$VGS_TUI_LIB" tree rows package manager name
  tree="${lib%/bin/lib/tui.sh}"
  [[ $tree != "$lib" && -n ${VGS_PLUGIN_ID:-} ]] ||
    vgs_tui_refuse "$log" 2 "jarvis: browser-setup=tui=missing" \
      "Open this setup from Jarvis in Plugins or the launcher." || exit
  rows="$(vgs_tui_logged "$log" "$tree/bin/vgshell" plugin requirements --json "$VGS_PLUGIN_ID")" ||
    vgs_tui_refuse "$log" 1 "jarvis: browser-setup=requirements-unreadable" \
      "VGS could not read the Jarvis requirements." "Close this window and try again." || exit
  package="$(vgs_tui_logged "$log" node -e '
const row = JSON.parse(process.argv[1]).find(entry => entry.name === "agent-browser");
if (row === undefined) { process.stderr.write("jarvis: browser-setup=undeclared command=agent-browser\n"); process.exit(1); }
process.stdout.write(row.package === null ? "" : row.package.manager + " " + row.package.name);
' "$rows")" || { vgs_tui_failed "$log" "VGS could not find agent-browser for this system."; exit 1; }
  [[ -n $package ]] || vgs_tui_refuse "$log" 1 "jarvis: browser-setup=no-package command=agent-browser" \
    "VGS has no agent-browser package for this system." || exit
  read -r manager name <<<"$package"
  "$tree/bin/vgshell" pkg run install --manager "$manager" "$name" ||
    vgs_tui_refuse "$log" 1 "jarvis: browser-setup=install-failed command=agent-browser" \
      "agent-browser is not installed." "Read the messages above, then try again." || exit
  command -v agent-browser >/dev/null ||
    vgs_tui_refuse "$log" 1 "jarvis: browser-setup=still-missing command=agent-browser" \
      "agent-browser is installed, but this terminal cannot find it." "Close this window and try again." || exit
  vgs_tui_step "agent-browser installed"
}
command -v agent-browser >/dev/null || install_driver

program="$VGS_PLUGIN_DIR/backend/browser-setup.js"
browser() { vgs_tui_logged "$log" node "$program" "$@"; }
not_ready=("Jarvis could not open its private browser." "Update agent-browser on the Jarvis page in Plugins, then try again.")
result=0
browser verify || result=$?
case "$result" in
  0) vgs_tui_step "Private browser ready" ;;
  69)
    vgs_tui_confirm "Download a private Chrome browser for Jarvis?" || exit 130
    browser download ||
      { vgs_tui_failed "$log" "Jarvis could not download the private browser." "Check your internet connection, then try again."; exit 1; }
    browser verify || { result=$?; vgs_tui_failed "$log" "${not_ready[@]}"; exit "$result"; }
    vgs_tui_step "Private browser ready" ;;
  *) vgs_tui_failed "$log" "${not_ready[@]}"; exit "$result" ;;
esac
