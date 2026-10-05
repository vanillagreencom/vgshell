#!/usr/bin/env bash
# Controls for the login screen's compositor configuration,
# config/system/greeter/hyprland.lua: the keyboard layout it reads from
# /etc/vconsole.conf. Each row runs the file
# under the system's lua with a stand-in `hl` that prints the `input`
# table it is handed, and with io.open answering a fixture for
# /etc/vconsole.conf; nothing reads the real file or starts Hyprland. Each
# control runs the rows against a copy of the file missing one rule, and
# the rows must fail.
set -euo pipefail

# shellcheck source=scripts/vgshell-rows.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
suite=test-greeter-compositor
config="$repo/config/system/greeter/hyprland.lua"
lua_bin="$(command -v lua)" || { echo "$suite: status=not-measured missing=lua"; exit 77; }

# The stand-in: io.open reads $VCONSOLE for /etc/vconsole.conf, and
# hl.config prints `layout|variant|model|options`.
cat >"$tmp/stand-in.lua" <<'EOF'
local real_open = io.open
io.open = function(path, mode)
  if path == "/etc/vconsole.conf" then path = os.getenv("VCONSOLE") end
  return real_open(path, mode)
end
hl = {
  config = function(t)
    local i = t.input
    print(i.kb_layout .. "|" .. i.kb_variant .. "|" .. i.kb_model .. "|" .. i.kb_options)
  end,
  on = function() end,
}
dofile(arg[1])
EOF

# rows: label | /etc/vconsole.conf's text, `-` for no file | the input line.
declare -a ROWS=(
  "no vconsole.conf types us|-|us|||"
  "the XKB keys set the layout, variant, model and options|KEYMAP=de-latin1\nXKBLAYOUT=de\nXKBVARIANT=nodeadkeys\nXKBMODEL=pc105\nXKBOPTIONS=caps:escape\n|de|nodeadkeys|pc105|caps:escape"
  "quotes and a trailing comment are read off|XKBLAYOUT=\"fr\" # AZERTY\nXKBVARIANT='oss'\n|fr|oss||"
  "an empty layout types us|XKBLAYOUT=\n|us|||"
  "a non-Latin layout puts us first with Left Alt + Right Alt|XKBLAYOUT=ru\nXKBVARIANT=phonetic\n|us,ru|,phonetic||grp:alts_toggle"
  "a non-Latin layout keeps its options|XKBLAYOUT=gr\nXKBOPTIONS=caps:escape\n|us,gr|,||caps:escape,grp:alts_toggle"
)
# run_rows FILE QUIET: every row against FILE; prints ok/FAIL lines unless
# QUIET and returns the number that failed.
run_rows() {
  local file="$1" quiet="$2" row name text want got red=0
  for row in "${ROWS[@]}"; do
    IFS='|' read -r name text want <<<"$row"
    want="${row#"$name|$text|"}"
    rm -f -- "$tmp/vconsole.conf"
    [[ $text == - ]] || printf "$text" >"$tmp/vconsole.conf"
    got="$(env -i VCONSOLE="$tmp/vconsole.conf" "$lua_bin" "$tmp/stand-in.lua" "$file" 2>&1)" || got="exit=$? $got"
    if [[ $got == "$want" ]]; then
      [[ $quiet == quiet ]] || ok "$name"
    else
      red=$((red + 1))
      [[ $quiet == quiet ]] || fail "$name: got=[$got] want=[$want]"
    fi
  done
  return "$red"
}
run_rows "$config" loud || true

# controls: label, the text and its replacement, three entries each.
declare -a CONTROLS=(
  "the layout comes from vconsole.conf" 'local file = io.open("/etc/vconsole.conf", "r")' 'local file = nil'
  "the model comes from vconsole.conf" 'local kb_model = value_of("XKBMODEL") or ""' 'local kb_model = ""'
  "the options come from vconsole.conf" 'local kb_options = value_of("XKBOPTIONS") or ""' 'local kb_options = ""'
  "a non-Latin layout puts us first" 'if non_latin_layouts:find(' 'if false and non_latin_layouts:find('
  "a non-Latin layout keeps its options" 'kb_options = kb_options == "" and "grp:alts_toggle" or kb_options .. ",grp:alts_toggle"' 'kb_options = "grp:alts_toggle"'
)
for ((i = 0; i < ${#CONTROLS[@]}; i += 3)); do
  copy_with "control-$((i / 3))" "$config" "${CONTROLS[i + 1]}" "${CONTROLS[i + 2]}"
  if run_rows "$copy" quiet; then fail "control: ${CONTROLS[i]}: the rows pass without the rule"; else ok "control: the rows fail without the rule: ${CONTROLS[i]}"; fi
done

rows_done "$suite"
