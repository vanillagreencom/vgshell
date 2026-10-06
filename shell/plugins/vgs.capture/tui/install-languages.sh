#!/usr/bin/env bash
# The core opens this script from the plugin's published snapshot, from the
# languages status entry's Install languages. It installs the Tesseract data
# of each chosen text language Tesseract does not list, through the core's
# package runner. Every refusal prints one keyed line on stderr first,
# `capture: languages=<key> ...`; one the user can act on then prints a plain
# sentence.
set -euo pipefail
source "$VGS_TUI_LIB"
refuse() { # STATUS KEY_LINE SENTENCE
  printf 'capture: languages=%s\n' "$2" >&2
  [[ -z $3 ]] || vgs_tui_error "$3"
  exit "$1"
}
[[ $# == 0 ]] || refuse 2 arguments ""
lib="$VGS_TUI_LIB"
tree="${lib%/bin/lib/tui.sh}"
[[ $tree != "$lib" && -n ${VGS_PLUGIN_ID:-} ]] ||
  refuse 2 "tui=missing" "Open this from Capture in Plugins."
command -v tesseract >/dev/null || refuse 77 "missing command=tesseract" ""
vgs_tui_lock capture-languages
vgs_tui_header "Install text languages" "Adds the recognition data for the text languages Capture reads."

[[ -n ${VGS_PLUGIN_DIR:-} ]] || refuse 2 "plugin-dir=missing" "Open this from Capture in Plugins."
settings="$("$tree/bin/vgshell" plugin settings "$VGS_PLUGIN_ID")"
rows="$("$tree/bin/vgshell" plugin requirements --json "$VGS_PLUGIN_ID")"
# The helper's own probe judges the languages and names the missing ones.
request="$(python3 -c 'import json, sys; print(json.dumps({"action": "probe", "ocrLanguages": json.loads(sys.argv[1]).get("ocrLanguages")}))' "$settings")"
# missing: the helper's probe line read as the codes it names missing.
missing() {
  local probe
  probe="$(python3 "$VGS_PLUGIN_DIR/helper/capture.py" "$request")" || refuse 1 "probe" "Capture could not read the installed languages."
  python3 -c '
import json, sys
events = [json.loads(line) for line in sys.argv[1].splitlines()]
report = next((event["languages"] for event in events if event.get("event") == "probe"), {})
if "missing" not in report:
    sys.exit("capture: languages=unreadable report=%s" % json.dumps(report))
print(*report["missing"])
' "$probe"
}
codes="$(missing)" || refuse 1 "plan" "Capture cannot tell which languages are missing."
manager="$(python3 -c '
import json, sys
row = next((row for row in json.loads(sys.argv[1]) if row["name"] == "tesseract"), None)
if row is None or row["package"] is None:
    sys.exit("capture: languages=no-package command=tesseract")
print(row["package"]["manager"])
' "$rows")" || refuse 1 "plan" "Capture cannot tell which language packages this system needs."
if [[ -z $codes ]]; then
  vgs_tui_step "Every chosen language is installed"
  exit 0
fi
read -r -a codes <<<"$codes"
packages=()
case "$manager" in
  pacman) for code in "${codes[@]}"; do packages+=("tesseract-data-$code"); done ;;
  dnf) for code in "${codes[@]}"; do packages+=("tesseract-langpack-$code"); done ;;
  nix)
    # A NixOS system changes through its own configuration.
    printf 'capture: languages=by-hand manager=nix codes=%s\n' "${codes[*]}" >&2
    vgs_tui_warn "NixOS adds Tesseract languages through the system configuration. Add these there: ${codes[*]}."
    exit 1
    ;;
  *) refuse 1 "unsupported manager=$manager" "VGS has no language packages for this system." ;;
esac
vgs_tui_confirm "Install ${packages[*]}?" || exit 130
"$tree/bin/vgshell" pkg run install --manager "$manager" "${packages[@]}"
left="$(missing)" || refuse 1 "recheck" "Capture cannot tell whether the languages are installed."
[[ -z $left ]] || refuse 1 "still-missing codes=$left" "The language data is installed, but Tesseract does not list $left."
vgs_tui_step "Text languages installed"
