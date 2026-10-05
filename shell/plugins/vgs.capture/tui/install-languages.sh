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
  refuse 2 "tui=missing" "Open this from Capture in Settings."
command -v tesseract >/dev/null || refuse 77 "missing command=tesseract" ""
vgs_tui_lock capture-languages
vgs_tui_header "Install text languages" "Adds the recognition data for the text languages Capture reads."

settings="$("$tree/bin/vgshell" plugin settings "$VGS_PLUGIN_ID")"
rows="$("$tree/bin/vgshell" plugin requirements --json "$VGS_PLUGIN_ID")"
installed="$(tesseract --list-langs)"
# One line: the manager that supplies Tesseract here, then each missing code.
plan="$(python3 -c '
import json, re, sys
settings, rows, listing = json.loads(sys.argv[1]), json.loads(sys.argv[2]), sys.argv[3]
languages = settings.get("ocrLanguages")
if not isinstance(languages, str) or not re.fullmatch(r"[A-Za-z_]+(\+[A-Za-z_]+)*", languages):
    sys.exit("capture: languages=invalid value=%r" % (languages,))
installed = {line.strip() for line in listing.splitlines()[1:] if line.strip()}
row = next((row for row in rows if row["command"] == "tesseract"), None)
if row is None or row["package"] is None:
    sys.exit("capture: languages=no-package command=tesseract")
missing = [code for code in dict.fromkeys(languages.split("+")) if code not in installed]
print(row["package"]["manager"], *missing)
' "$settings" "$rows" "$installed")" || refuse 1 "plan" "Capture cannot tell which language packages this system needs."
read -r manager codes <<<"$plan"
if [[ -z ${codes:-} ]]; then
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
installed="$(tesseract --list-langs)"
for code in "${codes[@]}"; do
  grep -qx -- "$code" <<<"$installed" ||
    refuse 1 "still-missing code=$code" "The $code data is installed, but Tesseract does not list it."
done
vgs_tui_step "Text languages installed"
