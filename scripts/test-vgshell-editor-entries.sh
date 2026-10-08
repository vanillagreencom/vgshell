#!/usr/bin/env bash
# The editor targets on the entry wiring, helix and zed, through
# `vgshell theme apply`: each renders its hand-written lines with its encoder
# into a document its application parses, is skipped when its command is not
# on PATH, keeps its links in its application's theme directory, takes a package's curated file where the target accepts it, and
# helix runs its reload hook. Every command is a stub on the rows' PATH, sh
# included, under a temporary HOME and XDG_RUNTIME_DIR, so no row signals an
# editor or reaches the developer's session. The controls at the end apply a
# tree copy whose target.json lacks one rule and require the row's
# assertion to turn.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
theme_tree helix zed
live="$state/theme"; hook_args="$tmp/sh-args"

# Detection never runs a command: helix and zeditor, Arch's names,
# and hx and zed, the upstream builds' names, record a run and exit 1. sh,
# the helix hook's command, records its arguments one per line. $upstream
# holds hx, zed and sh, and no Arch name.
upstream="$tmp/stubs-upstream"; mkdir -p "$upstream"
for stub in helix zeditor hx zed; do
  dir="$stubs"; [[ $stub == hx || $stub == zed ]] && dir="$upstream"
  printf '#!/bin/sh\n: >"%s/ran-$(basename "$0")"\nexit 1\n' "$tmp" >"$dir/$stub"
  chmod +x "$dir/$stub"
done
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s"\n' "$hook_args" >"$stubs/sh"
chmod +x "$stubs/sh"
ln -s -- "$stubs/sh" "$upstream/sh"
with_stubs="$stubs:$theme_path"; with_upstream="$upstream:$theme_path"

# `dusk` and `nord` carry no terminal.json, so every slot is the shipped vgs
# slot: color1 #f43f5e, color2 #b4c96f. `curated` ships a file for each
# editor.
theme_pkg "$tree/themes/dusk" '{ "schemaVersion": 1, "name": "dusk", "tokens": { "palette": { "accent": "#111111" } } }'
theme_pkg "$tree/themes/nord" '{ "schemaVersion": 1, "name": "nord", "tokens": { "palette": { "accent": "#222222" } } }'
theme_pkg "$tree/themes/dawn" '{ "schemaVersion": 1, "name": "dawn", "tokens": { "palette": { "accent": "#333333" } } }'
theme_pkg "$tree/themes/curated" '{ "schemaVersion": 1, "name": "curated", "tokens": {} }'
mkdir -p "$tree/themes/curated/targets"
printf '"ui.background" = { bg = "#123456" }\n' >"$tree/themes/curated/targets/helix.toml"
printf '{ "name": "mine", "author": "me", "themes": [] }\n' >"$tree/themes/curated/targets/zed.json"
# flexoki-light, a light package: the tree copy's catalog package, copied
# beside the shipped packages so every tree copy below can apply it.
cp -R -- "$tree/themes/catalog/flexoki-light" "$tree/themes/flexoki-light"

cfg="$tmp/cfg-editors"; mkdir -p "$cfg/vgshell"
helix_link="$cfg/helix/themes/vgs.toml"; zed_link="$cfg/zed/themes/vgs.json"
result() { # HELIX ZED: each `state` or `state:reason`
  local out="" t s
  for t in helix:"$1" zed:"$2"; do
    s="${t#*:}"
    if [[ $s == *:* ]]; then s="\"state\":\"${s%%:*}\",\"reason\":\"${s#*:}\""; else s="\"state\":\"$s\",\"reason\":null"; fi
    out+="${out:+,}{\"name\":\"${t%%:*}\",$s,\"dropped\":[]}"
  done
  printf '{"state":"applied","shell":"applied","targets":[%s],"theme":"%s","reason":null}' "$out" "$3"
}
links_to() { [[ -L $1 && "$(readlink -- "$1")" == "$2" ]]; } # PATH TARGET
# Every colour of a document: each `"#..."` string in it.
colours() { grep -oE '"#[^"]*"' -- "$1"; }
colours_are() { # FILE REGEX: every colour matches, and there is one
  local found
  found="$(colours "$1")" || return 1
  ! grep -qvxE "\"#$2\"" <<<"$found"
}
toml_parses() { python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1"; }
json_value() { # FILE PYTHON_EXPR_ON_d WANT
  local got
  got="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2" 2>/dev/null)" || return 1
  [[ $got == "$3" ]]
}
hook_ran_pinned() {
  [[ "$(cat -- "$hook_args")" == "-c"$'\n'"pkill -USR1 -x -u \"\$(id -u)\" 'hx|helix'; [ \$? -le 1 ]" ]]
}

tinst "an apply with no editor on PATH skips both" "$cfg" "$rt_empty" 0 "$(result skipped:not-detected skipped:not-detected dusk)" "" theme apply --json dusk
check "an undetected helix runs no hook" test ! -e "$hook_args"

THEME_PATH="$with_stubs" tinst "both editors land" "$cfg" "$rt_empty" 0 "$(result written written nord)" "" theme apply --json nord
check "helix's link names its state file" links_to "$helix_link" "$live/helix.toml"
check "zed's link names its state file" links_to "$zed_link" "$live/zed.json"
check "helix's theme is TOML" toml_parses "$helix_link"
check "helix takes the accent as #rrggbb" grep -qxF 'special = "#222222"' "$helix_link"
check "helix takes the background token" grep -qxF '"ui.background" = { bg = "#000000" }' "$helix_link"
check "helix takes the shipped slots" grep -qxF 'string = "#b4c96f"' "$helix_link"
check "every helix colour is #rrggbb" colours_are "$helix_link" '[0-9a-f]{6}'
check "zed's theme family names vgs" json_value "$zed_link" 'd["themes"][0]["name"]' vgs
check "zed takes the accent as #rrggbbaa" json_value "$zed_link" 'd["themes"][0]["style"]["text.accent"]' '#222222ff'
check "zed takes the shipped slots" json_value "$zed_link" 'd["themes"][0]["style"]["terminal.ansi.red"]' '#f43f5eff'
check "every zed colour is #rrggbbaa" colours_are "$zed_link" '[0-9a-f]{8}'
check "helix's hook signals Helix and tolerates none running" hook_ran_pinned
rm -f -- "$hook_args"
THEME_PATH="$with_stubs" tinst "unchanged bytes" "$cfg" "$rt_empty" 0 "ok theme=nord state=unchanged shell=unchanged" "" theme apply nord
check "unchanged bytes run no helix hook" test ! -e "$hook_args"

THEME_PATH="$with_stubs" tinst "a package's curated editor files land" "$cfg" "$rt_empty" 0 "$(result written written curated)" "" theme apply --json curated
check "helix takes the curated theme byte for byte" cmp -s -- "$tree/themes/curated/targets/helix.toml" "$helix_link"
check "zed takes the curated theme byte for byte" cmp -s -- "$tree/themes/curated/targets/zed.json" "$zed_link"

# Each package marks both editors' themes with its scheme.mode: vgs dark,
# flexoki-light light.
THEME_PATH="$with_stubs" tinst "the flexoki-light package lands" "$cfg" "$rt_empty" 0 "$(result written written flexoki-light)" "" theme apply --json flexoki-light
check "flexoki-light marks zed's theme light" json_value "$zed_link" 'd["themes"][0]["appearance"]' light
THEME_PATH="$with_stubs" tinst "the shipped vgs package lands" "$cfg" "$rt_empty" 0 "$(result written written vgs)" "" theme apply --json vgs
check "vgs marks zed's theme dark" json_value "$zed_link" 'd["themes"][0]["appearance"]' dark

# A theme of the user's at helix's link path is kept and skips the target.
rm -- "$helix_link"; printf 'mine\n' >"$helix_link"
THEME_PATH="$with_stubs" tinst "a user's vgs.toml" "$cfg" "$rt_empty" 0 "$(result skipped:entry-occupied written dusk)" "" theme apply --json dusk
check "the user's vgs.toml is kept" test "$(cat -- "$helix_link")" == mine
check "detection ran no editor" test ! -e "$tmp/ran-helix" -a ! -e "$tmp/ran-zeditor"

# An upstream build's command alone detects its editor: hx for helix, zed
# for zed. `dawn` is new here, so helix's bytes change and its hook runs.
cfg="$tmp/cfg-upstream"; mkdir -p "$cfg/vgshell"; helix_link="$cfg/helix/themes/vgs.toml"; zed_link="$cfg/zed/themes/vgs.json"
rm -f -- "$hook_args"
THEME_PATH="$with_upstream" tinst "hx and zed alone detect helix and zed" "$cfg" "$rt_empty" 0 "$(result written written dawn)" "" theme apply --json dawn
check "an hx-detected helix's link names its state file" links_to "$helix_link" "$live/helix.toml"
check "a zed-detected zed's link names its state file" links_to "$zed_link" "$live/zed.json"
check "an hx-detected helix's hook signals Helix" hook_ran_pinned
check "detection ran no upstream editor" test ! -e "$tmp/ran-hx" -a ! -e "$tmp/ran-zed"

# Controls: each mutant target.json drops one rule, and the assertion that
# pins it must turn. The rows above use the same assertions.
control_cfg() { cfg="$tmp/cfg-$1"; mkdir -p "$cfg/vgshell"; rm -f -- "$hook_args"; helix_link="$cfg/helix/themes/vgs.toml"; zed_link="$cfg/zed/themes/vgs.json"; }
turned() { test "$("$@"; echo $?)" == 1; } # CMD...: the assertion fails
tree_control helix-encoder themes/targets/helix/target.json '"encoder": "hex6"' '"encoder": "hex8"'
control_cfg helix-encoder
THEME_PATH="$with_stubs" tinst "the helix hex8 mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the helix hex8 mutant's theme is linked" test -s "$helix_link"
check "the helix hex8 mutant's colours are not #rrggbb" turned colours_are "$helix_link" '[0-9a-f]{6}'
tree_control zed-encoder themes/targets/zed/target.json '"encoder": "hex8"' '"encoder": "hex6"'
control_cfg zed-encoder
THEME_PATH="$with_stubs" tinst "the zed hex6 mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the zed hex6 mutant's theme is linked" test -s "$zed_link"
check "the zed hex6 mutant's colours are not #rrggbbaa" turned colours_are "$zed_link" '[0-9a-f]{8}'
tree_control zed-appearance themes/targets/zed/zed.json '"appearance": "@{scheme.mode}"' '"appearance": "dark"'
control_cfg zed-appearance
THEME_PATH="$with_stubs" tinst "the fixed-appearance zed mutant applies flexoki-light" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply flexoki-light
check "the fixed-appearance zed mutant's theme is linked" test -s "$zed_link"
check "the fixed-appearance zed mutant does not mark flexoki-light light" turned json_value "$zed_link" 'd["themes"][0]["appearance"]' light
tree_control helix-arch-only themes/targets/helix/target.json '"detect": [["helix", "hx"]]' '"detect": ["helix"]'
control_cfg helix-arch-only
THEME_PATH="$with_upstream" tinst "the Arch-only helix mutant applies under hx" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dawn
check "the Arch-only helix mutant links no theme under hx" turned links_to "$helix_link" "$live/helix.toml"
tree_control zed-arch-only themes/targets/zed/target.json '"detect": [["zeditor", "zed"]]' '"detect": ["zeditor"]'
control_cfg zed-arch-only
THEME_PATH="$with_upstream" tinst "the Arch-only zed mutant applies under zed" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dawn
check "the Arch-only zed mutant links no theme under zed" turned links_to "$zed_link" "$live/zed.json"
judge_control apply-all-of 'render.detected(target.detect, onPath)' 'target.detect.flat().every(onPath)'
control_cfg apply-all-of
THEME_PATH="$with_upstream" tinst "the all-of apply mutant applies under hx" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dawn
check "the all-of apply mutant links no theme under hx" turned links_to "$helix_link" "$live/helix.toml"
tree_control helix-hook themes/targets/helix/target.json '; [ $? -le 1 ]' ''
control_cfg helix-hook
# The state directory is shared, so the package changes to change bytes.
THEME_PATH="$with_stubs" tinst "the no-helix-tolerance mutant applies changed bytes" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the no-helix-tolerance mutant's hook ran" test -s "$hook_args"
check "the no-helix-tolerance mutant's hook is not the pinned argv" turned hook_ran_pinned
unset THEME_BIN

rows_done test-vgshell-editor-entries
