#!/usr/bin/env bash
# Controls for targets in `vgshell theme apply` beyond foot: a target whose
# wiring names a section keeps its include line in that section of its
# application's configuration file, one whose wiring names a Mozilla
# profiles.ini keeps it in the file of every profile the ini lists, each
# shipped terminal target lands its file, keeps its include line and runs its
# reload, and a target whose wiring is null lands with nothing kept outside
# the state directory. Every command a target detects with and the command a
# reload signals with are stubs on the rows' PATH, under a temporary HOME,
# XDG_CONFIG_HOME and XDG_RUNTIME_DIR, so no row reaches a real application
# or the developer's session.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
theme_tree alacritty foot ghostty kitty wezterm
export THEME_PATH="$stubs:$theme_path"
cfg="$tmp/cfg-targets"; mkdir -p "$cfg/vgshell"; live="$state/theme"
theme_pkg "$tree/themes/dusk" '{ "schemaVersion": 1, "name": "dusk", "tokens": { "palette": { "accent": "#111111" } } }'
theme_pkg "$tree/themes/nord" '{ "schemaVersion": 1, "name": "nord", "tokens": { "palette": { "accent": "#222222", "foreground": "#eeeeee" } } }'
target_state() { # NAME: the target's state in $tmp/apply.json
  python3 -c 'import json,sys; print([t["state"] for t in json.load(open(sys.argv[1]))["targets"] if t["name"] == sys.argv[2]][0])' "$tmp/apply.json" "$1"
}
target_verdict() { # NAME: the target's state and reason in $tmp/apply.json
  python3 -c 'import json,sys; print(*[(t["state"], t["reason"]) for t in json.load(open(sys.argv[1]))["targets"] if t["name"] == sys.argv[2]][0])' "$tmp/apply.json" "$1"
}
apply_json() { # NAME WANT_EXIT PACKAGE [WANT_FIRST_STDERR]: apply with --json into $tmp/apply.json
  tinst "$1" "$cfg" "$rt_empty" "$2" "$any_out" "${4:-}" theme apply --json "$3"
  tail -n 1 "$tmp/out" >"$tmp/apply.json"
}

# A section: the line goes after the first header of the section, a file
# without one takes the header and the line at its end, and the file's own
# text is kept.
mkdir -p "$tree/themes/targets/sect" "$cfg/sect"
printf '%s\n' '{ "app": "sect", "runsCode": false, "encoder": "hex6", "files": [{ "template": "sect.toml", "destination": "sect.toml" }], "detect": [], "wiring": { "file": "sect/sect.toml", "line": "import = [\"@{state}/sect.toml\"]", "create": true, "section": "general" }, "reload": null }' >"$tree/themes/targets/sect/target.json"
printf 'accent = "#@{palette.accent}"\n' >"$tree/themes/targets/sect/sect.toml"
sect_line="import = [\"$live/sect.toml\"]"
printf '[window]\nx = 1\n[general]\nlive = true\n' >"$cfg/sect/sect.toml"
apply_json "a target with a section applies" 0 dusk
check "the sectioned target is written" test "$(target_state sect)" == written
check "the include line goes after its section's header" test "$(cat "$cfg/sect/sect.toml")" == $'[window]\nx = 1\n[general]\n'"$sect_line"$'\nlive = true'
printf '[window]\nx = 1\n' >"$cfg/sect/sect.toml"
tinst "a file without the section is wired" "$cfg" "$rt_empty" 0 "ok theme=dusk state=unchanged shell=unchanged" "" theme apply dusk
check "a file without the section takes its header and the line at its end" test "$(cat "$cfg/sect/sect.toml")" == $'[window]\nx = 1\n[general]\n'"$sect_line"
rm -- "$cfg/sect/sect.toml"
tinst "an absent sectioned file is created" "$cfg" "$rt_empty" 0 "ok theme=dusk state=unchanged shell=unchanged" "" theme apply dusk
check "an absent file becomes the header and the line" test "$(cat "$cfg/sect/sect.toml")" == $'[general]\n'"$sect_line"
# The must-fail control: a judge copy that drops the section puts the line
# first, where a TOML file reads it outside its table.
printf '[general]\nlive = true\n' >"$cfg/sect/sect.toml"
judge_control section-dropped '"utf8").toString("latin1"), target.wiring.section, target.wiring.last);' '"utf8").toString("latin1"), undefined, target.wiring.last);'
tinst "the section-dropping mutant applies" "$cfg" "$rt_empty" 0 "ok theme=dusk state=unchanged shell=unchanged" "" theme apply dusk
check "the section-dropping mutant puts the line first" test "$(head -n 1 "$cfg/sect/sect.toml")" == "$sect_line"
unset THEME_BIN
rm -r -- "$tree/themes/targets/sect"

# A line that a removed target wired is taken back out on the next apply, and
# only that line is removed; the record keeps a failed removal so another
# apply can try again.
wired="$state/wired.json"
gone_target() { # NAME SECTION_JSON
  mkdir -p "$tree/themes/targets/$1"
  printf '{ "app": "%s", "runsCode": false, "encoder": "hex6", "files": [{ "template": "%s.conf", "destination": "%s.conf" }], "detect": [], "wiring": { "file": "%s/%s.conf", "line": "include = \\"@{state}/%s.conf\\"", "create": true%s }, "reload": null }\n' "$1" "$1" "$1" "$1" "$1" "$1" "$2" >"$tree/themes/targets/$1/target.json"
  printf 'accent = "#@{palette.accent}"\n' >"$tree/themes/targets/$1/$1.conf"
}
record_names() { python3 -c 'import json,sys,os; p=sys.argv[1]; print(",".join(r["target"] for r in json.load(open(p))["lines"]) if os.path.exists(p) else "")' "$wired"; }
gone_target gone ""
mkdir -p "$cfg/gone"; printf 'owner=true\n' >"$cfg/gone/gone.conf"; cp -- "$cfg/gone/gone.conf" "$tmp/gone-own"
gone_line="include = \"$live/gone.conf\""
apply_json "a removable target applies" 0 dusk
check "the removable target writes its line and record" test "$(head -n 1 "$cfg/gone/gone.conf")" == "$gone_line" -a "$(record_names)" == gone
rm -r -- "$tree/themes/targets/gone"
apply_json "a no-longer-shipped target is unwired" 0 dusk
check "a removed target leaves the owner's file byte for byte" cmp -s "$tmp/gone-own" "$cfg/gone/gone.conf"
check "a removed target leaves the wiring record" test "$(record_names)" == ""
gone_target gone ""
apply_json "the removable target applies for its control" 0 dusk
rm -r -- "$tree/themes/targets/gone"
judge_control removed-wiring-skipped 'const dropped = droppedWired(wiredBefore, new Set(targets.map(entry => entry.name)));' 'const dropped = { removed: [], kept: [], rows: [] };'
apply_json "the removed-wiring-skipped mutant applies" 0 dusk
check "the removed-wiring-skipped mutant keeps the removed target's line" grep -qxF -- "$gone_line" "$cfg/gone/gone.conf"
unset THEME_BIN

gone_target sectiongone ', "section": "general"'
python3 - "$tree/themes/targets/sectiongone/target.json" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path))
doc["wiring"]["line"] = "include = [\"@{state}/sectiongone.conf\"]"
open(path, "w").write(json.dumps(doc) + "\n")
PY
mkdir -p "$cfg/sectiongone"
printf '[general]\ninclude = ["owner.conf"] # owner\nkeep = true\n' >"$cfg/sectiongone/sectiongone.conf"
cp -- "$cfg/sectiongone/sectiongone.conf" "$tmp/sectiongone-own"
apply_json "a removable sectioned target applies" 0 dusk
check "the sectioned removable target merges its entry" grep -qxF -- "include = [\"$live/sectiongone.conf\", \"owner.conf\"] # owner" "$cfg/sectiongone/sectiongone.conf"
rm -r -- "$tree/themes/targets/sectiongone"
apply_json "a no-longer-shipped sectioned target is unwired" 0 dusk
check "a removed sectioned target leaves the owner's import byte for byte" cmp -s "$tmp/sectiongone-own" "$cfg/sectiongone/sectiongone.conf"

gone_target failgone ""
mkdir -p "$cfg/failgone"; printf 'owner=true\n' >"$cfg/failgone/failgone.conf"
apply_json "a removable target applies before a failed removal" 0 dusk
rm -r -- "$tree/themes/targets/failgone"
chmod a-w "$cfg/failgone"
apply_json "a no-longer-shipped target whose file cannot be changed fails partial" 3 dusk "vgshell: refused: target=failgone reason=unwritable path=$cfg/failgone/failgone.conf error=EACCES"
chmod u+w "$cfg/failgone"
check "a failed removal keeps the line and record" test "$(record_names)" == failgone -a "$(grep -cF -- "include = \"$live/failgone.conf\"" "$cfg/failgone/failgone.conf")" == 1
rm -- "$cfg/failgone/failgone.conf"
apply_json "an absent removed target file drops its record" 0 dusk
check "an absent removed target file leaves no record" test "$(record_names)" == ""
printf 'not json\n' >"$wired"
apply_json "a malformed wiring record refuses apply" 1 dusk "vgshell: refused: theme=dusk reason=malformed path=$wired"
rm -- "$wired"

# Profiles: `file` is relative to each profile directory the first of the
# inis under HOME that exists lists, a relative Path under the ini's own
# directory and an absolute one where it names; every listed profile whose
# directory exists is wired and unwired, and a section that names no profile
# is not one. The second ini is under HOME's .config while XDG_CONFIG_HOME
# names $cfg, so it is found by HOME alone.
home="$tmp/home"; ini="$home/.moz/profiles.ini"; ini2="$home/.config/moz/profiles.ini"
p0="$home/.moz/p0.default"; p1="$tmp/elsewhere/p1"; p2="$tmp/elsewhere/p2"
moz_target() { # CREATE
  mkdir -p "$tree/themes/targets/moz"
  printf '{ "app": "moz", "runsCode": false, "encoder": "hex6", "files": [{ "template": "moz.css", "destination": "moz.css" }], "detect": [], "wiring": { "file": "chrome/userChrome.css", "line": "@import url(\\"file://@{state}/moz.css\\");", "create": %s, "profiles": [".moz/profiles.ini", ".config/moz/profiles.ini"] }, "reload": null }\n' "$1" >"$tree/themes/targets/moz/target.json"
  printf ':root { --accent: #@{palette.accent}; }\n' >"$tree/themes/targets/moz/moz.css"
}
moz_ini() { # the first ini: a relative profile, an absolute one and an install section
  mkdir -p "$home/.moz"
  printf '[General]\nVersion=2\n\n[Profile0]\nName=default\nIsRelative=1\nPath=p0.default\n\n[Profile1]\nName=work\nIsRelative=0\nPath=%s\n\n[Install4F96D1932A9F858E]\nDefault=p0.default\nPath=%s\n' "$p1" "$tmp/install" >"$ini"
}
mkdir -p "$home/.config/moz"; printf '[Profile0]\nPath=%s\n' "$p2" >"$ini2"
moz_target true
moz_line="@import url(\"file://$live/moz.css\");"
apply_json "a profiles target whose one ini lists only absent profiles" 0 dusk
check "a profiles target with no listed profile directory is skipped" test "$(target_verdict moz)" == "skipped wiring-file-absent"
check "a skipped profiles target creates no profile" test ! -e "$p2" -a ! -e "$live/moz.css" -a ! -e "$cfg/chrome"
mkdir -p "$p2"
apply_json "a profiles target read from its second ini" 0 dusk
check "the second ini is read when the first is absent" test "$(cat "$p2/chrome/userChrome.css")" == "$moz_line"
rm -- "${p2:?}/chrome/userChrome.css"
mkdir -p "$p1/chrome"; printf '#nav-bar { order: 1 }\n' >"$p1/chrome/userChrome.css"
moz_ini
apply_json "a profiles target with its first ini" 0 nord
check "the profiles target is written" test "$(target_verdict moz)" == "written None"
check "a listed profile whose directory is absent is not created" test ! -e "$p0"
check "an absolute profile's file takes the line first and keeps its own text" test "$(cat "$p1/chrome/userChrome.css")" == "$moz_line"$'\n#nav-bar { order: 1 }'
check "the second ini is not read once the first exists" test ! -e "$p2/chrome/userChrome.css"
check "a section that names no profile is not wired" test ! -e "$tmp/install"
check "nothing is wired under the configuration home" test ! -e "$cfg/chrome"
mkdir -p "$p0"
apply_json "a profiles target once its relative profile exists" 0 nord
check "a relative profile's file is created holding the line" test "$(cat "$p0/chrome/userChrome.css")" == "$moz_line"
printf '{ "disabledTargets": ["moz"] }\n' >"$cfg/vgshell/shell.json"
apply_json "disabling the profiles target" 0 dusk
check "a disabled profiles target leaves every profile's file without the line" test "$(cat "$p0/chrome/userChrome.css")" == "" -a "$(cat "$p1/chrome/userChrome.css")" == "#nav-bar { order: 1 }"
rm -- "${cfg:?}/vgshell/shell.json"
moz_target false; rm -- "${p0:?}/chrome/userChrome.css"
apply_json "a profiles target with create false and one profile's file absent" 0 dusk
check "a profiles target with one file absent is skipped" test "$(target_verdict moz)" == "skipped wiring-file-absent"
check "a skipped profiles target leaves the other profile's file alone" test "$(cat "$p1/chrome/userChrome.css")" == "#nav-bar { order: 1 }"
moz_target true; mv -- "$ini" "$ini.saved"; mkdir -- "$ini"
apply_json "a profiles ini that cannot be read" 3 dusk "vgshell: refused: target=moz reason=unreadable path=$ini error=EISDIR"
check "an unreadable profiles ini fails its target" test "$(target_verdict moz)" == "failed unreadable"
printf '{ "disabledTargets": ["moz"] }\n' >"$cfg/vgshell/shell.json"
apply_json "disabling a profiles target whose ini cannot be read" 3 dusk "vgshell: refused: target=moz reason=unreadable path=$ini error=EISDIR"
check "a disabled profiles target whose ini cannot be read fails" test "$(target_verdict moz)" == "failed unreadable"
rm -- "${cfg:?}/vgshell/shell.json"
rmdir -- "$ini"; mv -- "$ini.saved" "$ini"
# Controls: each judge copy drops one rule, and the row that pins it turns.
# Each starts with no profile file wired.
moz_fresh() {
  rm -f -- "${p0:?}/chrome/userChrome.css" "${p1:?}/chrome/userChrome.css" "${p2:?}/chrome/userChrome.css" "${home:?}/p0.default/chrome/userChrome.css" "${cfg:?}/chrome/userChrome.css"
}
moz_fresh
judge_control profiles-ignored 'const selected = firstHomeRelative(wiring.profiles, readIfPresent);' 'return [path.join(configHome, wiring.file)];'
apply_json "the profiles-ignored mutant applies" 0 dusk
check "the profiles-ignored mutant wires the file under the configuration home" test -e "$cfg/chrome/userChrome.css" -a ! -e "$p0/chrome/userChrome.css"
moz_fresh; mkdir -p "$home/p0.default"
judge_control relative-under-home 'dir.relative ? path.join(path.dirname(selected.file), dir.path) : dir.path' 'dir.relative ? path.join(os.homedir(), dir.path) : dir.path'
apply_json "the relative-under-home mutant applies" 0 dusk
check "the relative-under-home mutant misses the ini's directory" test -e "$home/p0.default/chrome/userChrome.css" -a ! -e "$p0/chrome/userChrome.css"
moz_fresh
judge_control first-profile-only 'for (const file of files) {' 'for (const file of files.slice(0, 1)) {'
apply_json "the first-profile-only mutant applies" 0 dusk
check "the first-profile-only mutant leaves the second profile unwired" test -e "$p0/chrome/userChrome.css" -a ! -e "$p1/chrome/userChrome.css"
moz_fresh
judge_control last-ini-first 'for (const relative of relatives) {' 'for (const relative of relatives.slice().reverse()) {'
apply_json "the last-ini-first mutant applies" 0 dusk
check "the last-ini-first mutant wires the second ini's profile" test -e "$p2/chrome/userChrome.css" -a ! -e "$p0/chrome/userChrome.css"
moz_fresh; rmdir -- "$p0/chrome" "$p0"
judge_control stale-profile-created '.filter(isDirectory)' '.filter(dir => dir !== "")'
apply_json "the stale-profile-created mutant applies" 0 dusk
check "the stale-profile-created mutant creates an absent profile" test -e "$p0/chrome/userChrome.css"
moz_fresh; mv -- "$ini" "$ini.saved"; mv -- "$ini2" "$ini2.saved"
judge_control absent-ini-lands 'if (files.length === 0) return "wiring-file-absent";' 'if (false) return "wiring-file-absent";'
apply_json "the absent-ini-lands mutant applies" 0 nord
check "the absent-ini-lands mutant lands a target it wires nowhere" test "$(target_verdict moz)" == "written None"
mv -- "$ini.saved" "$ini"; mv -- "$ini2.saved" "$ini2"; moz_target false; printf 'x\n' >"$p1/chrome/userChrome.css"
judge_control every-file-absent 'files.some(file => fs.statSync(file, { throwIfNoEntry: false }) === undefined)' 'files.every(file => fs.statSync(file, { throwIfNoEntry: false }) === undefined)'
apply_json "the every-file-absent mutant applies" 3 dusk "vgshell: refused: target=moz reason=wiring-file-absent path=$p0/chrome/userChrome.css"
check "the every-file-absent mutant fails the target instead of skipping it" test "$(target_verdict moz)" == "failed wiring-file-absent"
unset THEME_BIN
rm -r -- "$tree/themes/targets/moz"

# The shipped terminal targets. Each is detected by a stub of its command,
# which records a run and exits 1, so detection never runs it. Their reload
# hooks run a real sh, id and touch; the signal command is a stub recording
# its arguments that exits with $tmp/signal-exit (1, no process matched,
# when absent), and touch reaches only this suite's HOME and configuration home. The
# targets are data: the judge rules these rows reach have their controls in
# test-vgshell.sh, test-vgshell-reload.sh and the section control above.
hook_tools="$tmp/hook-tools"; mkdir -p "$hook_tools"
for tool in sh id touch; do
  tool_bin="$(command -v "$tool")" || { echo "test-vgshell-targets: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$hook_tools/$tool"
done
for stub in alacritty ghostty kitty wezterm; do
  printf '#!/bin/sh\n: >"%s/ran-$(basename "$0")"\nexit 1\n' "$tmp" >"$stubs/$stub"
  chmod +x "$stubs/$stub"
done
signals="$tmp/signals"
cat >"$stubs/pkill" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$signals"
st=1
[ -f "$tmp/signal-exit" ] && read -r st <"$tmp/signal-exit"
exit "\$st"
EOF
chmod +x "$stubs/pkill"
export THEME_PATH="$stubs:$hook_tools:$theme_path"
uid="$(id -u)"
pending="$state/reload-pending.json"
cfg="$tmp/cfg-terminals"; mkdir -p "$cfg/vgshell" "$cfg/kitty" "$cfg/alacritty" "$cfg/wezterm"
printf 'font_size 11\n' >"$cfg/kitty/kitty.conf"
printf '[general]\nlive_config_reload = true\n\n[window]\nopacity = 0.9\n' >"$cfg/alacritty/alacritty.toml"
wezterm_own=$'local wezterm = require \'wezterm\'\nlocal config = wezterm.config_builder()\nconfig.font_size = 11\nreturn config'
wezterm_home_own=$'return { font_size = 13 }'
printf '%s\n' "$wezterm_own" >"$cfg/wezterm/wezterm.lua"
mkdir -p "$home"; printf '%s\n' "$wezterm_home_own" >"$home/.wezterm.lua"; touch -d @1000 -- "$home/.wezterm.lua"
terminals() { # ALACRITTY GHOSTTY KITTY WEZTERM: each a state and a JSON reason
  printf '[{"name":"alacritty","state":"%s","reason":%s,"dropped":[]},{"name":"foot","state":"skipped","reason":"not-detected","dropped":[]},{"name":"ghostty","state":"%s","reason":%s,"dropped":[]},{"name":"kitty","state":"%s","reason":%s,"dropped":[]},{"name":"wezterm","state":"%s","reason":%s,"dropped":[]}]' $1 $2 $3 $4
}
written="written null"
signalled() { # WANT: the signal command's argument lines since the last `: >"$signals"`
  [[ "$(cat "$signals")" == "$1" ]]
}
both_signals="-USR2 -x -u $uid ghostty"$'\n'"-USR1 -x -u $uid kitty"

: >"$signals"
tinst "the terminal targets land" "$cfg" "$rt_empty" 0 "{\"state\":\"applied\",\"shell\":\"applied\",\"targets\":$(terminals "$written" "$written" "$written" "$written"),\"theme\":\"dusk\",\"reason\":null}" "" theme apply --json dusk
# Each file with the hex6 encoder: dusk's accent is #111111, the table's
# foreground #d7d7d9 and the shipped slots' color1 #f43f5e.
while IFS='|' read -r file want; do
  check "$file holds: $want" grep -qxF -- "$want" "$live/$file"
done <<'EOF'
kitty.conf|url_color #111111
kitty.conf|foreground #d7d7d9
kitty.conf|color1 #f43f5e
ghostty.conf|foreground = #d7d7d9
ghostty.conf|palette = 1=#f43f5e
alacritty.toml|foreground = "#d7d7d9"
alacritty.toml|red = "#f43f5e"
wezterm.lua|        foreground = '#d7d7d9',
wezterm.lua|        ansi = { '#0b0b0b', '#f43f5e', '#b4c96f', '#ffb000', '#74a7f7', '#a855f7', '#06b6d4', '#d7d7d9' },
wezterm.lua|    config.color_scheme = 'vgs'
EOF
check "the rendered alacritty.toml is TOML with the colours in their tables" python3 -c 'import sys, tomllib; c = tomllib.load(open(sys.argv[1], "rb"))["colors"]; sys.exit(0 if (c["primary"]["foreground"], c["normal"]["red"], len(c["normal"]), len(c["bright"])) == ("#d7d7d9", "#f43f5e", 8, 8) else 1)' "$live/alacritty.toml"
check "kitty.conf takes the include line first" test "$(cat "$cfg/kitty/kitty.conf")" == "include $live/kitty.conf"$'\nfont_size 11'
check "an absent config.ghostty is created holding the config-file line" test "$(cat "$cfg/ghostty/config.ghostty")" == "config-file = ?$live/ghostty.conf"
check "alacritty.toml takes the import in its general table" test "$(cat "$cfg/alacritty/alacritty.toml")" == $'[general]\nimport = ["'"$live"$'/alacritty.toml"]\nlive_config_reload = true\n\n[window]\nopacity = 0.9'
check "the wired alacritty.toml is TOML importing the theme" python3 -c 'import sys, tomllib; c = tomllib.load(open(sys.argv[1], "rb")); sys.exit(0 if c["general"] == {"import": [sys.argv[2]], "live_config_reload": True} and c["window"] == {"opacity": 0.9} else 1)' "$cfg/alacritty/alacritty.toml" "$live/alacritty.toml"
check "wezterm.lua runs the theme first and keeps its own text" test "$(cat "$cfg/wezterm/wezterm.lua")" == "pcall(dofile, \"$live/wezterm.lua\")"$'\n'"$wezterm_own"
check "the config-home wezterm.lua wins over the HOME fallback" test "$(cat "$home/.wezterm.lua")" == "$wezterm_home_own" -a "$(stat -c %Y -- "$home/.wezterm.lua")" == 1000
check "the landed hooks signal ghostty and kitty by exact name for this user" signalled "$both_signals"
check "a signal that matched no process leaves nothing pending" test ! -e "$pending"
check "detection never ran a terminal" test -z "$(find "$tmp" -maxdepth 1 -name 'ran-*' -print)"

# Changed bytes touch the files alacritty and wezterm watch, whose wiring
# already stands; unchanged bytes touch and signal nothing.
touch -d @1000 -- "$cfg/alacritty/alacritty.toml" "$cfg/wezterm/wezterm.lua" "$home/.wezterm.lua"
: >"$signals"
tinst "a changed theme reloads the terminals" "$cfg" "$rt_empty" 0 "ok theme=nord state=applied shell=applied" "" theme apply nord
check "the alacritty hook touched alacritty.toml" test "$(stat -c %Y -- "$cfg/alacritty/alacritty.toml")" != 1000
check "the wezterm hook touched wezterm.lua" test "$(stat -c %Y -- "$cfg/wezterm/wezterm.lua")" != 1000
check "the wezterm hook left the HOME fallback untouched while config-home exists" test "$(stat -c %Y -- "$home/.wezterm.lua")" == 1000 -a "$(cat "$home/.wezterm.lua")" == "$wezterm_home_own"
check "a changed theme signals ghostty and kitty again" signalled "$both_signals"
touch -d @1000 -- "$cfg/alacritty/alacritty.toml" "$cfg/wezterm/wezterm.lua"
: >"$signals"
tinst "an unchanged theme reloads nothing" "$cfg" "$rt_empty" 0 "ok theme=nord state=unchanged shell=unchanged" "" theme apply nord
check "unchanged bytes touch neither watched file" test "$(stat -c %Y -- "$cfg/alacritty/alacritty.toml" "$cfg/wezterm/wezterm.lua" | tr '\n' ' ')" == "1000 1000 "
check "unchanged bytes signal nothing" signalled ""

# The user's terminal font, the `terminalFont` member of shell.json
# `appearance`: kitty and Ghostty write it and no other target changes; a
# follow renders it again when it changes; without one, each file holds the
# bytes it held before. Ghostty first clears the families its own
# configuration set.
cp -- "$live/kitty.conf" "$tmp/kitty-plain.conf"; cp -- "$live/ghostty.conf" "$tmp/ghostty-plain.conf"
record="$state/applied.json"
user_file="$cfg/vgshell/shell.json"
font_user() { printf '{ "appearance": { "terminalFont": %s } }\n' "$1" >"$user_file"; } # FONT_JSON
# The values FILE gives KEY, in order, as JSON; SEPARATOR ends the key.
font_values() { # FILE SEPARATOR KEY
  python3 -c 'import json,sys
rows = [line.partition(sys.argv[2]) for line in open(sys.argv[1]).read().split("\n") if line and not line.startswith("#")]
print(json.dumps([value.strip() for key, _, value in rows if key.strip() == sys.argv[3]]))' "$1" "$2" "$3"
}
recorded_font() { python3 -c 'import json,sys; d = json.load(open(sys.argv[1])); print(json.dumps(d.get("terminalFont")))' "$record"; }
font_follow() { # NAME OUTCOME STATE TARGETS_JSON
  tinst "$1" "$cfg" "$rt_empty" 0 "{\"state\":\"$3\",\"shell\":\"unchanged\",\"targets\":$4,\"theme\":\"nord\",\"reason\":null,\"follow\":\"$2\"}" "" theme follow --json
}
font_targets="$(terminals "unchanged null" "$written" "$written" "unchanged null")"
check "a record without a terminal font holds none" test "$(recorded_font)" == 'null'
font_user '"Fira Code"'
: >"$signals"
font_follow "a terminal font follows into kitty and Ghostty alone" reapplied applied "$font_targets"
check "kitty.conf sets the font family" test "$(font_values "$live/kitty.conf" ' ' font_family)" == '["Fira Code"]'
check "ghostty.conf clears the families before it and sets the font" test "$(font_values "$live/ghostty.conf" = font-family)" == '["\"\"", "\"Fira Code\""]'
check "the font leaves every other kitty line" test "$(grep -v '^font_family ' "$live/kitty.conf")" == "$(cat "$tmp/kitty-plain.conf")"
check "the font leaves every other Ghostty line" test "$(grep -v 'font-family\|^# An empty value' "$live/ghostty.conf")" == "$(cat "$tmp/ghostty-plain.conf")"
check "the font signals ghostty and kitty" signalled "$both_signals"
check "the record holds the font the targets were rendered with" test "$(recorded_font)" == '"Fira Code"'
font_follow "a follow with the recorded font is current" current unchanged "[]"
font_user '"Iosevka Term"'
font_follow "another font follows" reapplied applied "$font_targets"
check "kitty.conf sets the new font family" test "$(font_values "$live/kitty.conf" ' ' font_family)" == '["Iosevka Term"]'
tinst "an apply renders the font too" "$cfg" "$rt_empty" 0 "ok theme=dusk state=applied shell=applied" "" theme apply dusk
check "the applied package's kitty.conf sets the font family" test "$(font_values "$live/kitty.conf" ' ' font_family)" == '["Iosevka Term"]'
tinst "nord applies again with the font" "$cfg" "$rt_empty" 0 "ok theme=nord state=applied shell=applied" "" theme apply nord
# A value the judge refuses is no font: here one that would add a line of
# its own to kitty.conf.
font_user '"Fira Code\nmap ctrl+a launch sh"'
font_follow "a refused font follows as no font" reapplied applied "$font_targets"
check "a refused font leaves kitty.conf as it was without one" cmp -s -- "$tmp/kitty-plain.conf" "$live/kitty.conf"
check "a refused font leaves ghostty.conf as it was without one" cmp -s -- "$tmp/ghostty-plain.conf" "$live/ghostty.conf"
check "the record of a render without a font holds none" test "$(recorded_font)" == 'null'
# The must-fail controls, each from nord applied without a font.
judge_control font-unjudged 'return value !== undefined && logic.appearanceRefusal("terminalFont", value) === "" ? value : null;' 'return value !== undefined ? value : null;'
tinst "the font-unjudged mutant follows the refused font" "$cfg" "$rt_empty" 0 "$any_out" "" theme follow
check "the font-unjudged mutant writes the font's second line into kitty.conf" grep -qxF -- "map ctrl+a launch sh" "$live/kitty.conf"
unset THEME_BIN
# The mutant recorded that font, which the judge refuses in a record too:
# an apply writes a new one.
tinst "follow refuses the record the font-unjudged mutant wrote" "$cfg" "$rt_empty" 1 "" "vgshell: refused: follow=applied reason=malformed path=$record" theme follow
tinst "an apply takes the refused font back out" "$cfg" "$rt_empty" 0 "ok theme=nord state=applied shell=unchanged" "" theme apply nord
check "the apply leaves kitty.conf as it was without a font" cmp -s -- "$tmp/kitty-plain.conf" "$live/kitty.conf"
font_user '"Fira Code"'
judge_control font-unrendered 'installed: row.source === "installed", terminalFont: font });' 'installed: row.source === "installed" });'
tinst "the font-unrendered mutant follows the font" "$cfg" "$rt_empty" 0 "$any_out" "" theme follow
check "the font-unrendered mutant leaves kitty.conf without a font" cmp -s -- "$tmp/kitty-plain.conf" "$live/kitty.conf"
unset THEME_BIN
printf '{}\n' >"$user_file"
tinst "nord applies without a font for the follow control" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
font_user '"Fira Code"'
judge_control font-unfollowed 'if (samePackage && targetsDigest(key) === applied.targets && terminalFont(shellConfig(configDir, key)) === recordedFont) return settled("current");' 'if (samePackage) return settled("current");'
font_follow "the font-unfollowed mutant takes a new font as current" current unchanged "[]"
unset THEME_BIN
font_follow "the font follows for the record control" reapplied applied "$font_targets"
judge_control font-unrecorded 'if (font !== null) record.terminalFont = font;' ''
tinst "the font-unrecorded mutant applies nord" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
check "the font-unrecorded mutant's record holds no font" test "$(recorded_font)" == 'null'
unset THEME_BIN
tinst "nord applies with the font for the removal" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply nord
printf '{}\n' >"$user_file"
font_follow "a removed font follows" reapplied applied "$font_targets"
check "without a font kitty.conf holds the bytes it held before one" cmp -s -- "$tmp/kitty-plain.conf" "$live/kitty.conf"
check "without a font ghostty.conf holds the bytes it held before one" cmp -s -- "$tmp/ghostty-plain.conf" "$live/ghostty.conf"
font_follow "a follow without a font is current again" current unchanged "[]"

# A signal command that fails leaves both signalled targets pending, and
# `vgshell theme reload` runs them again.
printf '2\n' >"$tmp/signal-exit"
: >"$signals"
failed="reload-pending \"reload-failed\""
tinst "a failing signal leaves its targets reload-pending" "$cfg" "$rt_empty" 3 "{\"state\":\"partial\",\"shell\":\"applied\",\"targets\":$(terminals "$written" "$failed" "$failed" "$written"),\"theme\":\"dusk\",\"reason\":null}" "vgshell: refused: target=ghostty reason=reload-failed command=sh status=1" theme apply --json dusk
check "the failed reloads are pending" test "$(cat "$pending")" == '{"schemaVersion":1,"targets":["ghostty","kitty"]}'
rm -- "$tmp/signal-exit"
: >"$signals"
tinst "reload signals the pending terminals" "$cfg" "$rt_empty" 0 "ok reload state=reloaded" "" theme reload
check "reload signalled ghostty and kitty" signalled "$both_signals"
check "a reload that succeeds clears the pending terminals" test ! -e "$pending"

# WezTerm loads the first existing configuration file: the config-home
# wezterm.lua, HOME/.config/wezterm/wezterm.lua when XDG_CONFIG_HOME points
# elsewhere, then HOME/.wezterm.lua.
rm -- "$cfg/wezterm/wezterm.lua"
mkdir -p "$home/.config/wezterm"
printf '%s\n' "$wezterm_home_own" >"$home/.config/wezterm/wezterm.lua"; touch -d @1000 -- "$home/.config/wezterm/wezterm.lua"
printf '%s\n' "$wezterm_home_own" >"$home/.wezterm.lua"; touch -d @1000 -- "$home/.wezterm.lua"
apply_json "a HOME config wezterm.lua fallback applies wezterm" 0 nord
check "the HOME config wezterm.lua fallback is written" test "$(target_state wezterm)" == written
check "the include line goes into HOME/.config/wezterm/wezterm.lua" test "$(cat "$home/.config/wezterm/wezterm.lua")" == "pcall(dofile, \"$live/wezterm.lua\")"$'\n'"$wezterm_home_own"
check "the HOME config fallback wins over HOME/.wezterm.lua" test "$(cat "$home/.wezterm.lua")" == "$wezterm_home_own" -a "$(stat -c %Y -- "$home/.wezterm.lua")" == 1000
check "the HOME config wezterm.lua fallback hook touched the watched file" test "$(stat -c %Y -- "$home/.config/wezterm/wezterm.lua")" != 1000
printf '{"schemaVersion":1,"targets":["wezterm"]}\n' >"$pending"
touch -d @1000 -- "$home/.config/wezterm/wezterm.lua" "$home/.wezterm.lua"
tinst "reload touches a pending HOME config wezterm.lua" "$cfg" "$rt_empty" 0 "ok reload state=reloaded" "" theme reload
check "reload touched the HOME config wezterm.lua fallback" test "$(stat -c %Y -- "$home/.config/wezterm/wezterm.lua")" != 1000
check "reload left HOME/.wezterm.lua untouched" test "$(stat -c %Y -- "$home/.wezterm.lua")" == 1000 -a "$(cat "$home/.wezterm.lua")" == "$wezterm_home_own"
check "reload cleared the pending HOME config wezterm hook" test ! -e "$pending"

printf '%s\n' "$wezterm_home_own" >"$home/.config/wezterm/wezterm.lua"; touch -d @1000 -- "$home/.config/wezterm/wezterm.lua"
printf '%s\n' "$wezterm_home_own" >"$home/.wezterm.lua"; touch -d @1000 -- "$home/.wezterm.lua"
judge_control fallback-last-first 'for (const relative of relatives) {' 'for (const relative of relatives.slice().reverse()) {'
apply_json "the fallback-last-first mutant applies" 0 nord
check "the fallback-last-first mutant wires HOME/.wezterm.lua before HOME/.config/wezterm/wezterm.lua" test "$(cat "$home/.wezterm.lua")" == "pcall(dofile, \"$live/wezterm.lua\")"$'\n'"$wezterm_home_own" -a "$(cat "$home/.config/wezterm/wezterm.lua")" == "$wezterm_home_own"
unset THEME_BIN
rm -- "$home/.config/wezterm/wezterm.lua"; rmdir -- "$home/.config/wezterm"

printf '%s\n' "$wezterm_home_own" >"$home/.wezterm.lua"; touch -d @1000 -- "$home/.wezterm.lua"
apply_json "a HOME wezterm.lua fallback applies wezterm" 0 nord
check "the HOME wezterm.lua fallback is active" test "$(target_verdict wezterm)" == "unchanged None"
check "the include line goes into HOME/.wezterm.lua" test "$(cat "$home/.wezterm.lua")" == "pcall(dofile, \"$live/wezterm.lua\")"$'\n'"$wezterm_home_own"
check "a HOME wezterm.lua fallback leaves config-home absent" test ! -e "$cfg/wezterm/wezterm.lua"
check "the HOME wezterm.lua fallback hook touched the watched file" test "$(stat -c %Y -- "$home/.wezterm.lua")" != 1000
printf '{"schemaVersion":1,"targets":["wezterm"]}\n' >"$pending"
touch -d @1000 -- "$home/.wezterm.lua"
tinst "reload touches a pending HOME wezterm.lua" "$cfg" "$rt_empty" 0 "ok reload state=reloaded" "" theme reload
check "reload touched the HOME wezterm.lua fallback" test "$(stat -c %Y -- "$home/.wezterm.lua")" != 1000
check "reload cleared the pending wezterm hook" test ! -e "$pending"

printf '%s\n' "$wezterm_home_own" >"$home/.wezterm.lua"
judge_control fallbacks-ignored 'if (wiring.fallbacks === undefined || existingPath(configFile) !== undefined) return [configFile];' 'return [configFile]; if (false) return [configFile];'
apply_json "the fallbacks-ignored mutant applies" 0 dusk
check "the fallbacks-ignored mutant skips the HOME fallback" test "$(target_verdict wezterm)" == "skipped wiring-file-absent" -a ! -e "$cfg/wezterm/wezterm.lua"
unset THEME_BIN

printf '%s\n' "$wezterm_own" >"$cfg/wezterm/wezterm.lua"
printf '%s\n' "$wezterm_home_own" >"$home/.wezterm.lua"
judge_control fallback-before-file 'if (wiring.fallbacks === undefined || existingPath(configFile) !== undefined) return [configFile];' 'if (wiring.fallbacks === undefined) return [configFile];'
apply_json "the fallback-before-file mutant applies" 0 nord
check "the fallback-before-file mutant wires HOME instead of config-home" test "$(cat "$home/.wezterm.lua")" == "pcall(dofile, \"$live/wezterm.lua\")"$'\n'"$wezterm_home_own" -a "$(cat "$cfg/wezterm/wezterm.lua")" == "$wezterm_own"
unset THEME_BIN
rm -- "$cfg/wezterm/wezterm.lua"

printf '%s\n%s\n' "pcall(dofile, \"$live/wezterm.lua\")" "$wezterm_home_own" >"$home/.wezterm.lua"; touch -d @1000 -- "$home/.wezterm.lua"
touch -d @1000 -- "$live/wezterm.lua"
printf '{"schemaVersion":1,"targets":["wezterm"]}\n' >"$pending"
judge_control hook-not-wired-file 'render.reloadCommand(target, live, path.join(SHIPPED, TARGETS, name), wiring.path);' 'render.reloadCommand(target, live, path.join(SHIPPED, TARGETS, name), path.join(live, target.files[0].destination));'
tinst "the hook-not-wired-file mutant reloads" "$cfg" "$rt_empty" 0 "ok reload state=reloaded" "" theme reload
check "the hook-not-wired-file mutant touches the theme file instead of the wired HOME file" test "$(stat -c %Y -- "$home/.wezterm.lua")" == 1000 -a "$(stat -c %Y -- "$live/wezterm.lua")" != 1000
unset THEME_BIN

# With neither configuration file, wezterm.lua is never created: WezTerm
# reads its defaults without one.
rm -- "$home/.wezterm.lua"
tinst "an absent wezterm.lua skips wezterm" "$cfg" "$rt_empty" 0 "{\"state\":\"unchanged\",\"shell\":\"unchanged\",\"targets\":$(terminals 'unchanged null' 'unchanged null' 'unchanged null' 'skipped "wiring-file-absent"'),\"theme\":\"nord\",\"reason\":null}" "" theme apply --json nord
check "an absent wezterm.lua stays absent" test ! -e "$cfg/wezterm/wezterm.lua" -a ! -e "$home/.wezterm.lua"

# A one-line import array of the file's own in general takes the theme
# first, the rest of the file kept byte for byte; a second apply leaves it,
# and a disabled alacritty takes only its own entry back out.
printf '[general]\nimport = ["~/.config/alacritty/mine.toml"] # mine\nlive_config_reload = true\n' >"$cfg/alacritty/alacritty.toml"
cp -- "$cfg/alacritty/alacritty.toml" "$tmp/alacritty-own"
merged=$'[general]\nimport = ["'"$live"$'/alacritty.toml", "~/.config/alacritty/mine.toml"] # mine\nlive_config_reload = true'
apply_json "an alacritty.toml with its own import applies" 0 dusk
check "alacritty with its own import is written" test "$(target_state alacritty)" == written
check "the theme goes first in the file's own import array" test "$(cat "$cfg/alacritty/alacritty.toml")" == "$merged"
check "the merged alacritty.toml is TOML importing the theme before its own" python3 -c 'import sys, tomllib; c = tomllib.load(open(sys.argv[1], "rb")); sys.exit(0 if c["general"] == {"import": [sys.argv[2], "~/.config/alacritty/mine.toml"], "live_config_reload": True} else 1)' "$cfg/alacritty/alacritty.toml" "$live/alacritty.toml"
apply_json "a second apply over the merged import" 0 dusk
check "a second apply leaves the merged import" test "$(cat "$cfg/alacritty/alacritty.toml")" == "$merged"
printf '{ "disabledTargets": ["alacritty"] }\n' >"$cfg/vgshell/shell.json"
apply_json "a disabled alacritty over the merged import" 0 dusk
check "the disabled alacritty is skipped" test "$(target_state alacritty)" == skipped
check "a disabled alacritty leaves the file's own import byte for byte" cmp -s "$tmp/alacritty-own" "$cfg/alacritty/alacritty.toml"
# The must-fail control: a judge copy that hands the removal no section
# leaves the theme's entry in the file's own array.
rm -- "$cfg/vgshell/shell.json"
apply_json "alacritty merged again" 0 dusk
printf '{ "disabledTargets": ["alacritty"] }\n' >"$cfg/vgshell/shell.json"
judge_control unwire-sectionless 'live, render.unwiredText);' 'live, (text, line) => render.unwiredText(text, line));'
apply_json "the sectionless-unwiring mutant applies" 0 dusk
check "the sectionless-unwiring mutant keeps the theme's entry" test "$(cat "$cfg/alacritty/alacritty.toml")" == "$merged"
unset THEME_BIN
rm -- "$cfg/vgshell/shell.json"

# An import array that goes on past its line cannot take the theme without
# a second import key, which TOML refuses: alacritty fails and its file is
# left byte for byte.
printf '[general]\nimport = [\n  "~/.config/alacritty/mine.toml",\n]\n' >"$cfg/alacritty/alacritty.toml"
cp -- "$cfg/alacritty/alacritty.toml" "$tmp/alacritty-own"
conflict="vgshell: refused: target=alacritty reason=wiring-conflict path=$cfg/alacritty/alacritty.toml section=general key=import"
tinst "an alacritty.toml with a multi-line import fails alacritty" "$cfg" "$rt_empty" 3 "$any_out" "$conflict" theme apply --json dusk
tail -n 1 "$tmp/out" >"$tmp/apply.json"
check "the conflicting alacritty is failed wiring-conflict" json_is "$tmp/apply.json" 'd["state"] == "partial" and [t for t in d["targets"] if t["name"] == "alacritty"] == [{"name": "alacritty", "state": "failed", "reason": "wiring-conflict", "dropped": []}]'
check "a conflicting alacritty.toml is left byte for byte" cmp -s "$tmp/alacritty-own" "$cfg/alacritty/alacritty.toml"
# The must-fail control: a copy of the shared file helper,
# bin/lib/judge-files.js, that takes the refusal for a file already wired
# reports alacritty landed.
tree_control conflict-swallowed bin/lib/judge-files.js 'if (typeof next !== "string") return {' 'if (typeof next !== "string") return null; if (false) return {'
tinst "the conflict-swallowing mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json nord
tail -n 1 "$tmp/out" >"$tmp/apply.json"
check "the conflict-swallowing mutant reports alacritty landed" test "$(target_state alacritty)" == written
unset THEME_BIN

# A null wiring keeps nothing outside the state directory: the target lands
# its file, and disabled it only leaves theme/.
mkdir -p "$tree/themes/targets/bare"
printf '%s\n' '{ "app": "bare", "runsCode": false, "encoder": "hex6", "files": [{ "template": "bare.conf", "destination": "bare.conf" }], "detect": [], "wiring": null, "reload": null }' >"$tree/themes/targets/bare/target.json"
printf 'accent=@{palette.accent}\n' >"$tree/themes/targets/bare/bare.conf"
rm -- "$cfg/alacritty/alacritty.toml"
apply_json "a target with a null wiring applies" 0 nord
check "the unwired target is written" test "$(target_state bare)" == written
check "the unwired target's file lands in theme/" test "$(cat "$live/bare.conf")" == "accent=222222"
check "nothing outside the state directory names the unwired target" test -z "$(find "$cfg" "$tmp/home" -path "$state" -prune -o -name '*bare*' -print)"
printf '{ "disabledTargets": ["bare"] }\n' >"$cfg/vgshell/shell.json"
apply_json "a disabled target with a null wiring" 0 dusk
check "the disabled unwired target is skipped" test "$(target_state bare)" == skipped
check "the disabled unwired target's file leaves theme/" test ! -e "$live/bare.conf"
rm -- "$cfg/vgshell/shell.json"
# The must-fail control: a judge copy that plans a null wiring as absent
# skips the target.
judge_control none-skipped '        case "none":' '        case "none": return "wiring-file-absent";'
apply_json "the none-skipping mutant applies" 0 nord
check "the none-skipping mutant skips the unwired target" test "$(target_state bare)" == skipped
unset THEME_BIN
rm -r -- "$tree/themes/targets/bare"

# Every shipped target here runs code. An installed package's curated file
# on each is dropped, its template rendered in its place, and the result
# names the drop on the target's row, which keeps it when the target's
# wiring or reload then fails; a shipped package's curated file is taken.
# neovim joins the terminals, detected by a stub.
cp -R -- "$repo/themes/targets/neovim" "$tree/themes/targets/"
printf '#!/bin/sh\n: >"%s/ran-nvim"\nexit 1\n' "$tmp" >"$stubs/nvim"; chmod +x "$stubs/nvim"
curated_lua=$'-- curated\nos.execute("true")'
for pkg in "$cfg/vgshell/themes/mossy" "$tree/themes/fenlua"; do
  theme_pkg "$pkg" "{ \"schemaVersion\": 1, \"name\": \"${pkg##*/}\", \"tokens\": { \"palette\": { \"accent\": \"#333333\" } } }"
  mkdir -p "$pkg/targets"
  printf '%s\n' "$curated_lua" >"$pkg/targets/neovim.lua"
  printf 'shell /bin/sh\n' >"$pkg/targets/kitty.conf"
  printf '[terminal.shell]\nprogram = "/bin/sh"\n' >"$pkg/targets/alacritty.toml"
done
# ROW: NAME STATE REASON DROPPED, each of the last three as Python.
row_is() { json_is "$tmp/apply.json" "[t for t in d['targets'] if t['name'] == '$1'] == [{'name': '$1', 'state': $2, 'reason': $3, 'dropped': $4}]"; }
apply_json "an installed package with curated files on code targets applies" 0 mossy
check "the installed neovim.lua is dropped and named" row_is neovim "'written'" None "['neovim.lua']"
check "the installed kitty.conf is dropped and named" row_is kitty "'written'" None "['kitty.conf']"
check "a target the package curates nothing for names no drop" row_is ghostty "'written'" None "[]"
check "a skipped target names no drop" row_is foot "'skipped'" "'not-detected'" "[]"
check "neovim takes its render, not the installed file" grep -qF 'hl("Search", { fg = "#' "$live/neovim.lua"
# Grep's 1 alone is a pass: 2, an unreadable file, is not.
holds_none() { local st=0; grep -q -e 'os.execute' -e '/bin/sh' -- "$@" || st=$?; [[ $st == 1 ]]; }
check "no installed curated file lands" holds_none "$live/neovim.lua" "$live/kitty.conf" "$live/alacritty.toml"
tinst "text output names the dropped file" "$cfg" "$rt_empty" 0 "ok theme=mossy state=unchanged shell=unchanged" "" theme apply mossy
check "the text row names the drop" has_line "target=neovim state=unchanged dropped=neovim.lua"
check "a text row without a drop names none" has_line "target=ghostty state=unchanged"
# A wiring that fails and a reload that fails keep the row's drop.
printf '[general]\nimport = [\n  "~/mine.toml",\n]\n' >"$cfg/alacritty/alacritty.toml"
printf '2\n' >"$tmp/signal-exit"
apply_json "a shipped package changes every target's bytes first" 3 dusk "vgshell: refused: target=alacritty reason=wiring-conflict path=$cfg/alacritty/alacritty.toml section=general key=import"
apply_json "the installed package again, wiring and reload failing" 3 mossy "vgshell: refused: target=alacritty reason=wiring-conflict path=$cfg/alacritty/alacritty.toml section=general key=import"
check "a failed wiring keeps the drop" row_is alacritty "'failed'" "'wiring-conflict'" "['alacritty.toml']"
check "a failed reload keeps the drop" row_is kitty "'reload-pending'" "'reload-failed'" "['kitty.conf']"
rm -- "$tmp/signal-exit" "$cfg/alacritty/alacritty.toml"
apply_json "a shipped package with curated files on code targets applies" 0 fenlua
check "the shipped neovim.lua is taken and names no drop" row_is neovim "'written'" None "[]"
check "the shipped neovim.lua lands byte for byte" cmp -s -- "$tree/themes/fenlua/targets/neovim.lua" "$live/neovim.lua"
# The must-fail controls: a judge copy that takes every package as shipped
# lands the installed file; one that reports no drop, on the row or in text,
# leaves the row or the line without it.
judge_control installed-as-shipped 'installed: row.source === "installed", terminalFont: font });' 'installed: false, terminalFont: font });'
apply_json "the installed-as-shipped mutant applies" 0 mossy
check "the installed-as-shipped mutant lands the installed neovim.lua" cmp -s -- "$cfg/vgshell/themes/mossy/targets/neovim.lua" "$live/neovim.lua"
judge_control drop-unreported 'dropped: entry.dropped === undefined ? [] : entry.dropped })));' 'dropped: [] })));'
apply_json "the drop-unreported mutant applies" 0 mossy
check "the drop-unreported mutant names no drop" row_is neovim "'written'" None "[]"
judge_control drop-untold 't.dropped.length === 0 ? "" :' 'true ? "" :'
tinst "the drop-untold mutant applies" "$cfg" "$rt_empty" 0 "ok theme=mossy state=unchanged shell=unchanged" "" theme apply mossy
check "the drop-untold mutant's text row names no drop" has_line "target=neovim state=unchanged"
printf '2\n' >"$tmp/signal-exit"
judge_control reload-drops 'return Object.assign({}, row, { state: "reload-pending", reason });' 'return { name, state: "reload-pending", reason };'
apply_json "the reload-drops mutant applies" 3 fenlua "vgshell: refused: target=kitty reason=reload-failed command=sh status=1"
apply_json "the reload-drops mutant applies the installed package" 3 mossy "vgshell: refused: target=kitty reason=reload-failed command=sh status=1"
check "the reload-drops mutant's failed reload loses the drop" test "$(target_verdict kitty)" == "reload-pending reload-failed" -a "$(python3 -c 'import json,sys; print([t.get("dropped") for t in json.load(open(sys.argv[1]))["targets"] if t["name"] == "kitty"][0])' "$tmp/apply.json")" == None
rm -- "$tmp/signal-exit"
printf '[general]\nimport = [\n  "~/mine.toml",\n]\n' >"$cfg/alacritty/alacritty.toml"
judge_control wire-drops 'state: "failed", dropped: entry.dropped }, failure);' 'state: "failed" }, failure);'
apply_json "the wire-drops mutant applies" 3 mossy "vgshell: refused: target=alacritty reason=wiring-conflict path=$cfg/alacritty/alacritty.toml section=general key=import"
check "the wire-drops mutant's failed wiring loses the drop" test "$(python3 -c 'import json,sys; print([t["dropped"] for t in json.load(open(sys.argv[1]))["targets"] if t["name"] == "alacritty"][0])' "$tmp/apply.json")" == "[]"
unset THEME_BIN
rm -- "$cfg/alacritty/alacritty.toml"

# A target that does not say whether its files run code is refused.
mkdir -p "$tree/themes/targets/loose"
printf '%s\n' '{ "app": "loose", "encoder": "hex6", "files": [{ "template": "loose.conf", "destination": "loose.conf" }], "detect": [], "wiring": null, "reload": null }' >"$tree/themes/targets/loose/target.json"
printf 'accent=@{palette.accent}\n' >"$tree/themes/targets/loose/loose.conf"
apply_json "an unclassified target fails" 3 dusk "vgshell: refused: target=loose reason=target-schema missing=runsCode"
check "the unclassified target is failed target-schema" row_is loose "'failed'" "'target-schema'" "[]"
check "the unclassified target's file never lands" test ! -e "$live/loose.conf"
# The must-fail control: a renderer copy that does not require the key
# reaches the target only through its value, so the missing key goes
# unnamed.
tree_control unclassified bin/lib/theme-render.js 'if (!logic.hasOwn(document, key)) return' 'if (!logic.hasOwn(document, key) && key !== "runsCode") return'
apply_json "the unclassified mutant names no missing key" 3 dusk "vgshell: refused: target=loose reason=target-schema key=runsCode"
unset THEME_BIN
rm -r -- "$tree/themes/targets/loose" "$tree/themes/targets/neovim"

# Only these targets enter the new app fixture. All detected commands are
# stand-ins; the bat hook records argv and never reaches a native cache.
rm -r -- "$tree/themes/targets"
mkdir -p "$tree/themes/targets"
for app in starship yazi bat fastfetch television foot; do
  cp -R -- "$repo/themes/targets/$app" "$tree/themes/targets/"
done
for command in starship yazi fastfetch tv foot; do
  printf '#!/bin/sh\nexit 0\n' >"$stubs/$command"; chmod +x "$stubs/$command"
done
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >"%s/bat-cache-args"\n' "$tmp" >"$stubs/bat"; chmod +x "$stubs/bat"
cfg="$tmp/home/.config/terminal-apps"
terminal_app_seed() {
  rm -rf -- "$cfg"
  mkdir -p "$cfg/vgshell"
  python3 - "$cfg" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
def put(name,text):
 f=p/name; f.parent.mkdir(parents=True,exist_ok=True); f.write_text(text)
put('starship.toml', 'palette = "vgs"\nformat = "$directory$character"\n# keep prompt\n[directory]\nstyle = "bold #010203"\ntruncation_length = 7\n[character]\nsuccess_symbol = "[❯](#010203)"\n[palettes.vgs]\nred = "#ff0000"\n')
for name in ('yazi','yazi-scratchpad'):
 glyph='USER-GLYPH' if name=='yazi' else 'SCRATCH-GLYPH'
 put(name+'/theme.toml', '[flavor]\ndark = "owner"\nlight = "owner-light"\n[mgr]\ncwd = { fg = "#010203", bg = "#040506", bold = true }\n[icon]\nprepend_dirs = [\n { name = "Desktop", text = "'+glyph+'", fg = "#010203" },\n]\n[filetype]\nrules = [{ url = "*.mine", fg = "#010203" }]\n')
put('bat/config', '# keep bat\n--theme=ansi\n--wrap=character\n')
put('fastfetch/config.jsonc', json.dumps({'logo':{'color':{'1':'#010203'},'padding':{'left':7}},'display':{'color':'#010203'},'modules':[{'type':'custom','key':'{#31}USER-GLYPH','format':'{#38;2;1;2;3}fixture','keyColor':'#010203'}]})+'\n')
put('television/config.toml', '[ui]\ntheme = "default"\n[ui.input_bar]\nprompt = "sesh > "\n[ui.theme_overrides]\nbackground = "#040506"\ntext_fg = "#010203"\nselection_bg = "#040506"\nmatch_fg = "#010203"\n')
PY
}
terminal_app_pickup() {
  python3 - "$cfg" "$live" "$1" <<'PY'
import json,plistlib,sys,tomllib
from pathlib import Path
p,live,app=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3]
def toml(name): return tomllib.loads((p/name).read_text())
if app=='starship':
 d=toml('starship.toml'); assert 'palette' not in d and 'vgs' not in d.get('palettes',{}); assert d['directory']['style']=='bold black'; assert d['directory']['truncation_length']==7
 assert d['character']['success_symbol']=='[❯](black)'; assert '# keep prompt' in (p/'starship.toml').read_text()
elif app=='yazi':
 for name,destination,glyph in (('yazi','yazi.toml','USER-GLYPH'),('yazi-scratchpad','yazi.scratchpad.toml','SCRATCH-GLYPH')):
  d=toml(name+'/theme.toml'); assert d=={'flavor':{'dark':'vgs','light':'vgs'}}
  flavor=p/name/'flavors/vgs.yazi'; assert (flavor/'flavor.toml').samefile(live/destination); assert (flavor/'tmtheme.xml').samefile(live/'yazi.tmTheme')
  generated=tomllib.loads((flavor/'flavor.toml').read_text())
  assert generated['mgr']['cwd']=={'fg':'#ff5a36','bg':'#000000','bold':True}
  icon=generated['icon']['prepend_dirs'][0]; assert icon['text']==glyph and icon['fg']=='#ff5a36'
  assert generated['filetype']['rules'][0]=={'url':'*.mine','fg':'#d7d7d9'}
  assert generated['icon']['exts']
elif app=='bat':
 assert (p/'bat/config').read_text()=='# keep bat\n--theme=vgs\n--wrap=character\n'
 assert (p/'bat/themes/vgs.tmTheme').samefile(live/'bat.tmTheme')
 assert plistlib.loads((p/'bat/themes/vgs.tmTheme').read_bytes())['name']=='vgs'
elif app=='fastfetch':
 d=json.loads((p/'fastfetch/config.jsonc').read_text()); assert d['display']['color']=='black'
 assert d['modules'][0]['key']=='{#31}USER-GLYPH'; assert d['modules'][0]['format']=='{#30}fixture'; assert d['logo']['padding']['left']==7
elif app=='television':
 d=toml('television/config.toml'); assert d['ui']['theme']=='vgs' and 'theme_overrides' not in d['ui']
 assert d['ui']['input_bar']['prompt']=='sesh > '; assert (p/'television/themes/vgs.toml').samefile(live/'television.toml')
else: raise AssertionError(app)
PY
}
terminal_app_seed
apply_json "terminal app targets apply over local colours" 0 vgs
for app in starship yazi bat fastfetch television; do
  check "$app picks up the VGS colours and keeps its content" terminal_app_pickup "$app"
done
check "bat's target builds its native theme cache" test "$(cat "$tmp/bat-cache-args")" == "cache --build"
# Track only the user's settings. Generated themes stay outside the index.
g -C "$cfg" init -q
g -C "$cfg" add -- starship.toml fastfetch/config.jsonc yazi/theme.toml yazi-scratchpad/theme.toml bat/config television/config.toml
g -C "$cfg" commit -qm baseline
cp -- "$live/yazi.toml" "$tmp/first-yazi"
cp -- "$live/yazi.scratchpad.toml" "$tmp/first-scratchpad"
cp -- "$live/television.toml" "$tmp/first-television"
cp -- "$live/foot.ini" "$tmp/first-foot"
python3 - "$tree/themes" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
terminal=json.loads((p/'vgs/terminal.json').read_text())
terminal['slots']['color0']='#050505'
(p/'nord/terminal.json').write_text(json.dumps(terminal))
PY
apply_json "a second terminal app theme applies" 0 nord
check "all VGS-1812 user configs stay tracked and clean after a theme switch" test -z "$(g -C "$cfg" status --porcelain --untracked-files=no)"
check "generated flavors retain customizations and take the new colours" python3 - "$cfg" "$live" "$tmp" <<'PY'
import configparser,json,sys,tomllib
from pathlib import Path
p,live,tmp=map(Path,sys.argv[1:])
for name,file,glyph,before in (('yazi','yazi.toml','USER-GLYPH','first-yazi'),('yazi-scratchpad','yazi.scratchpad.toml','SCRATCH-GLYPH','first-scratchpad')):
 flavor=p/name/'flavors/vgs.yazi'/'flavor.toml'
 assert flavor.samefile(live/file)
 d=tomllib.loads(flavor.read_text())
 old=tomllib.loads((tmp/before).read_text())
 assert d['mgr']['cwd']['fg']!=old['mgr']['cwd']['fg'] and d['mgr']['cwd']['bold']
 assert d['icon']['prepend_dirs'][0]['text']==glyph
 assert d['icon']['prepend_dirs'][0]['fg']!=old['icon']['prepend_dirs'][0]['fg']
 assert d['filetype']['rules'][0]['url']=='*.mine'
assert (live/'television.toml').read_bytes()!=(tmp/'first-television').read_bytes()
assert (live/'foot.ini').read_bytes()!=(tmp/'first-foot').read_bytes()
terminal=configparser.ConfigParser(); terminal.read(live/'foot.ini')
assert terminal['colors-dark']['regular0']=='050505'
assert tomllib.loads((p/'starship.toml').read_text())['directory']['style']=='bold black'
assert json.loads((p/'fastfetch/config.jsonc').read_text())['display']['color']=='black'
PY
for app in starship yazi bat fastfetch television; do
  # The same pickup assertion must fail when that app's target is absent.
  # These are disposable fixture trees outside the repository.
  terminal_app_seed
  cp -R -- "$tree" "$tmp/no-$app"
  rm -r -- "$tmp/no-$app/themes/targets/$app"
  THEME_BIN="$tmp/no-$app/bin/vgshell"
  apply_json "$app's missing-target control applies" 0 vgs
  if terminal_app_pickup "$app" >"$tmp/pickup-control" 2>&1; then
    fail "$app's pickup assertion passed without its target"
  elif grep -q 'AssertionError' "$tmp/pickup-control"; then
    ok "$app's pickup assertion fails without its target"
  else
    fail "$app's pickup control failed outside its assertion"
  fi
  unset THEME_BIN
done

# Creation reaches the apply planner and atomic writer, so it belongs to
# this integration row and its writer/helper/configuration/theme inputs.
# The only target is synthetic bat, with no reload hook. Detection uses
# each child's private command directory and never the host PATH.
rm -r -- "${tree:?}/themes/targets"
mkdir -p "$tree/themes/targets"
target_dir bat '{ "app": "bat", "runsCode": false, "encoder": "hex6", "files": [{ "template": "bat.conf", "destination": "bat.conf" }], "detect": ["bat"], "wiring": null, "reload": null, "select": { "base": "config", "file": "bat/config", "format": "bat", "values": { "theme": "vgs" } } }' $'# test theme\n'
check "bat creates only the managed selection when detected" "$node_bin" - "$tree" "$tmp" <<'JS'
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const tree = process.argv[2];
const scratch = process.argv[3];

function verifyBatCreation(tree, scratch) {
    for (const detected of [true, false]) {
        const home = fs.mkdtempSync(path.join(scratch, "home-"));
        const commands = path.join(home, "commands");
        fs.mkdirSync(commands);
        if (detected) fs.writeFileSync(path.join(commands, "bat"), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
        const config = path.join(home, ".config");
        const state = path.join(home, "state");
        const result = spawnSync(process.execPath, [path.join(tree, "bin", "vgshell-theme-judge"), "apply", "json", path.join(config, "vgshell"), state, "held", "vgs"], {
            encoding: "utf8", timeout: 30000,
            env: { HOME: home, PATH: commands, XDG_CONFIG_HOME: config, XDG_CACHE_HOME: path.join(home, "cache"), XDG_DATA_HOME: path.join(home, "data"), XDG_STATE_HOME: path.join(home, "state-home"), XDG_RUNTIME_DIR: path.join(home, "runtime"), TMPDIR: scratch, VGS_TEST_RUN: "1", DBUS_SYSTEM_BUS_ADDRESS: "unix:path=" + path.join(home, "no-system-bus") }
        });
        assert.equal(result.status, 0, result.stderr);
        const row = JSON.parse(result.stdout.trim()).targets.find(row => row.name === "bat");
        const file = path.join(config, "bat", "config");
        if (detected) {
            assert.equal(fs.readFileSync(file, "utf8"), "--theme=vgs\n");
            assert.equal(row.state, "written");
        } else {
            assert.equal(fs.existsSync(file), false);
            assert.equal(row.reason, "not-detected");
        }
    }
}

verifyBatCreation(tree, scratch);
const judgeFile = path.join(tree, "bin", "vgshell-theme-judge");
const original = fs.readFileSync(judgeFile, "utf8");
for (const [needle, replacement] of [
    [' || selection.format === "bat"', ""],
    ['if (!render.detected(target.detect, onPath)) return "not-detected";', 'if (false) return "not-detected";']
]) {
    assert.equal(original.split(needle).length, 2);
    fs.writeFileSync(judgeFile, original.replace(needle, replacement));
    assert.throws(() => verifyBatCreation(tree, scratch));
}
JS

# Native precedence uses private HOME/XDG paths and no reload hooks. Pi's
# public extension boundary is injected; its settings merge and native ANSI
# output are also checked in the issue's no-prompt native evidence.
ghostty_native="$(command -v ghostty)" || { echo "test-vgshell-targets: status=not-measured missing=ghostty"; exit 77; }
nvim_native="$(command -v nvim)" || { echo "test-vgshell-targets: status=not-measured missing=nvim"; exit 77; }
check "native application precedence and stable selectors" "$node_bin" --experimental-vm-modules - "$repo" "$ghostty_native" "$nvim_native" <<'JS'
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { spawnSync } = require("node:child_process");
const [repo, ghostty, nvim] = process.argv.slice(2);
const root = fs.mkdtempSync(path.join(require("node:os").tmpdir(), "vgs-target-precedence-"));
const tree = path.join(root, "tree");

async function verify(control) {
    const home = fs.mkdtempSync(path.join(root, "home-"));
    const config = path.join(home, ".config");
    const state = path.join(home, ".local/state/vgshell");
    const commands = path.join(home, "commands");
    fs.mkdirSync(commands);
    for (const name of ["ghostty", "neovim", "pi"]) {
        const target = JSON.parse(fs.readFileSync(path.join(tree, "themes/targets", name, "target.json")));
        fs.writeFileSync(path.join(commands, target.detect[0]), "#!/bin/sh\nexit 1\n", { mode: 0o755 });
    }
    const env = { HOME: home, PATH: commands, XDG_CONFIG_HOME: config, XDG_DATA_HOME: path.join(home, "data"), XDG_CACHE_HOME: path.join(home, "cache"), XDG_STATE_HOME: path.join(home, ".local/state"), XDG_RUNTIME_DIR: path.join(home, "run"), TMPDIR: root, VGS_TEST_RUN: "1", TERM: "xterm-256color", LC_ALL: "C" };
    const write = (file, text) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text); };
    const ghostFile = path.join(config, "ghostty/config.ghostty");
    const localFile = path.join(config, "ghostty/local.conf");
    const include = "config-file = ?" + state + "/theme/ghostty.conf";
    write(localFile, "foreground = #010203\nbackground = #040506\n");
    const ownGhost = "foreground = #010203\nbackground = #040506\nfont-size = 13\nconfig-file = " + localFile + "\n";
    write(ghostFile, include + "\n" + ownGhost);
    const nvimDir = path.join(config, "nvim");
    const report = path.join(home, "neovim.json");
    write(path.join(nvimDir, "after/plugin/local.lua"), `vim.g.local_after_loaded = true
vim.api.nvim_set_hl(0, 'Normal', {fg=0x010203})
vim.api.nvim_create_autocmd('VimEnter', {callback=function() vim.api.nvim_set_hl(0, 'Normal', {fg=0x010203}) end})
vim.api.nvim_create_autocmd('ColorScheme', {callback=function() vim.api.nvim_set_hl(0, 'Normal', {fg=0x010203}) end})
`);
    write(path.join(nvimDir, "colors/local.vim"), "hi clear\nlet g:colors_name='local'\nhi Normal guifg=#010203 guibg=#040506\n");
    write(path.join(nvimDir, "init.lua"), `vim.api.nvim_create_autocmd('VimEnter', {callback=function() vim.schedule(function() vim.schedule(function() local startup=vim.api.nvim_get_hl(0,{name='Normal'}); vim.cmd.colorscheme('local'); vim.schedule(function() vim.fn.writefile({vim.json.encode({after=vim.g.local_after_loaded,startup=startup,second=vim.api.nvim_get_hl(0,{name='Normal'}),name=vim.g.colors_name})},${JSON.stringify(report)}); vim.cmd('qa!') end) end) end) end})\n`);
    const project = path.join(home, "project/.pi/settings.json");
    const projectText = '{"theme":"vgs-theme","defaultModel":"fixture"}\n';
    write(project, projectText);
    const accountRoots = [".pi/agent", ".spi/agent", ".1pi/agent"].map(dir => path.join(home, dir));
    for (const account of accountRoots) write(path.join(account, "settings.json"), '{"theme":"dark","defaultModel":"fixture"}\n');
    const selectors = [ghostFile, path.join(nvimDir, "plugin/vgs-theme.lua"), ...accountRoots.map(account => path.join(account, "settings.json"))];
    let stable;
    for (const [theme, fg, bg] of [["vgs", "d7d7d9", "000000"], ["flexoki-light", "100f0f", "fffcf0"], ["flexoki-light", "100f0f", "fffcf0"]]) {
        const applied = spawnSync(process.execPath, [path.join(tree, "bin/vgshell-theme-judge"), "apply", "json", path.join(config, "vgshell"), state, "held", theme], { env, encoding: "utf8", timeout: 30000 });
        assert.equal(applied.status, 0, applied.stderr);
        if (!control || control === "ghostty") {
            const result = spawnSync(ghostty, ["+show-config"], { env, encoding: "utf8", timeout: 10000 });
            assert.equal(result.status, 0, result.stderr);
            const colours = Object.fromEntries([...result.stdout.matchAll(/^(foreground|background) = #?([a-f0-9]+)$/gm)].map(match => [match[1], match[2]]));
            assert.deepEqual(colours, { foreground: fg, background: bg });
            assert.equal(fs.readFileSync(ghostFile, "utf8"), ownGhost + include + "\n");
        }
        if (!control || control === "neovim") {
            const result = spawnSync(nvim, ["--headless", "-i", "NONE"], { env, encoding: "utf8", timeout: 10000 });
            assert.equal(result.status, 0, result.stderr);
            const got = JSON.parse(fs.readFileSync(report));
            assert.equal(got.after, true);
            for (const phase of [got.startup, got.second]) assert.deepEqual(phase, { fg: parseInt(fg, 16), bg: parseInt(bg, 16) });
            assert.equal(got.name, "vgs");
        }
        if (!control || control === "pi") for (const account of accountRoots) {
            let selected = { colours: { text: "#010203" } };
            const extension = path.join(account, "extensions/vgs-theme.js");
            if (fs.existsSync(extension)) {
                const context = vm.createContext({});
                class Theme { constructor(colours) { this.colours = colours; } }
                const dependency = new vm.SyntheticModule(["getAgentDir", "Theme"], function () { this.setExport("getAgentDir", () => account); this.setExport("Theme", Theme); }, { context });
                const io = new vm.SyntheticModule(["readFileSync"], function () { this.setExport("readFileSync", fs.readFileSync); }, { context });
                const paths = new vm.SyntheticModule(["join"], function () { this.setExport("join", path.join); }, { context });
                const module = new vm.SourceTextModule(fs.readFileSync(extension, "utf8"), { context });
                await module.link(name => name === "node:fs" ? io : name === "node:path" ? paths : dependency);
                await module.evaluate();
                const events = new Map();
                module.namespace.default({ on: (name, callback) => events.set(name, callback) });
                const ui = { theme: { getColorMode: () => "truecolor" }, setTheme: value => { selected = value; return { success: true }; } };
                await events.get("session_start")({}, { mode: "tui", hasUI: true, ui });
                for (const [mode, hasUI] of [["rpc", true], ["json", false], ["print", false]]) {
                    const before = selected;
                    await events.get("session_start")({}, { mode, hasUI, ui });
                    assert.equal(selected, before, mode + ": no terminal theme request");
                }
            }
            assert.equal(selected.colours.text, "#" + fg);
            assert.deepEqual(JSON.parse(fs.readFileSync(path.join(account, "settings.json"))), { theme: "vgs", defaultModel: "fixture" });
            assert.equal(fs.readFileSync(project, "utf8"), projectText);
        }
        const now = selectors.map(file => fs.readFileSync(file, "utf8"));
        if (stable) assert.deepEqual(now, stable, "all theme changes and repeated applies preserve selectors byte for byte");
        stable = now;
    }
}

(async () => {
    try {
        fs.mkdirSync(path.join(tree, "themes/targets"), { recursive: true });
        for (const dir of ["bin", "shell", "config", "themes/vgs"]) fs.cpSync(path.join(repo, dir), path.join(tree, dir), { recursive: true });
        const installed = path.join(tree, "config-light");
        // Installed packages may omit their on-demand wallpaper assets.
        fs.cpSync(path.join(repo, "themes/catalog/flexoki-light"), installed, { recursive: true });
        for (const name of ["ghostty", "neovim", "pi"]) {
            fs.cpSync(path.join(repo, "themes/targets", name), path.join(tree, "themes/targets", name), { recursive: true });
            const file = path.join(tree, "themes/targets", name, "target.json");
            const target = JSON.parse(fs.readFileSync(file));
            target.reload = null;
            fs.writeFileSync(file, JSON.stringify(target));
        }
        // The fixture light package keeps its own palette and drops only the
        // background declaration, so it can be treated as shipped here.
        const light = JSON.parse(fs.readFileSync(path.join(installed, "theme.json")));
        delete light.backgrounds;
        fs.mkdirSync(path.join(tree, "themes/flexoki-light"));
        fs.writeFileSync(path.join(tree, "themes/flexoki-light/theme.json"), JSON.stringify(light));
        fs.copyFileSync(path.join(installed, "terminal.json"), path.join(tree, "themes/flexoki-light/terminal.json"));
        await verify();
        for (const name of ["ghostty", "neovim", "pi"]) {
            const file = path.join(tree, "themes/targets", name, name === "neovim" ? "neovim.lua" : "target.json");
            const original = fs.readFileSync(file, "utf8");
            if (name === "neovim") {
                const needle = "local group = vim.api.nvim_create_augroup";
                assert.equal(original.split(needle).length, 2);
                fs.writeFileSync(file, original.slice(0, original.indexOf(needle)) + 'if vim.v.vim_did_enter == 1 then apply() else vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = apply }) end\nreturn {}\n');
            } else {
                const target = JSON.parse(original);
                if (name === "ghostty") delete target.wiring.last;
                else { target.files = target.files.filter(file => file.destination !== "pi.js"); delete target.wiring.copies["extensions/vgs-theme.js"]; }
                fs.writeFileSync(file, JSON.stringify(target));
            }
            assert.notEqual(fs.readFileSync(file, "utf8"), original);
            await assert.rejects(() => verify(name), { code: "ERR_ASSERTION" }, name + ": original pickup must fail the same colour assertion");
            fs.writeFileSync(file, original);
        }
        const bridge = path.join(tree, "themes/targets/pi/pi.js");
        const original = fs.readFileSync(bridge, "utf8");
        const needle = 'if (ctx.mode !== "tui") return;';
        assert.equal(original.split(needle).length, 2);
        fs.writeFileSync(bridge, original.replace(needle, "if (!ctx.hasUI) return;"));
        assert.notEqual(fs.readFileSync(bridge, "utf8"), original);
        await assert.rejects(() => verify("pi"), { code: "ERR_ASSERTION" }, "RPC dialog availability must not enable terminal theme switching");
        fs.writeFileSync(bridge, original);
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
})().catch(error => { console.error(error); process.exitCode = 1; });
JS

check "editor and prompt stable selectors, startup precedence and original-behavior controls" "$node_bin" - "$repo" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const repo = process.argv[2];
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'vgs-editor-select-'));
try {
    const tree = path.join(scratch, 'tree');
    const names = ['helix', 'zed', 'obsidian', 'emacs', 'oh-my-posh'];
    for (const name of ['bin', 'shell', 'config', 'themes/vgs', ...names.map(name => 'themes/targets/' + name)])
        fs.cpSync(path.join(repo, name), path.join(tree, name), { recursive: true });
    const targets = new Map(names.map(name => [name, JSON.parse(fs.readFileSync(path.join(tree, 'themes/targets', name, 'target.json')))]));
    const commands = path.join(scratch, 'commands');
    fs.mkdirSync(commands);
    for (const name of ['hx', 'zed', 'obsidian', 'emacs', 'oh-my-posh', 'pkill', 'id', 'emacsclient'])
        fs.writeFileSync(path.join(commands, name), '#!/bin/sh\nprintf "%s\\n" "$@" >> "$HOOK_LOG"\n', { mode: 0o755 });
    fs.symlinkSync('/bin/sh', path.join(commands, 'sh'));
    fs.cpSync(path.join(tree, 'themes/vgs'), path.join(tree, 'themes/other'), { recursive: true });
    const otherFile = path.join(tree, 'themes/other/theme.json');
    const other = JSON.parse(fs.readFileSync(otherFile));
    other.name = 'other';
    other.tokens.palette = { ...other.tokens.palette, accent: '#abcdef' };
    fs.writeFileSync(otherFile, JSON.stringify(other));
    let caseNumber = 0;
    function world() {
        const home = path.join(scratch, 'home-' + caseNumber++);
        const config = path.join(home, 'settings');
        const state = path.join(home, 'state/vgshell');
        fs.mkdirSync(path.join(config, 'vgshell'), { recursive: true });
        const env = { HOME: home, PATH: commands, XDG_CONFIG_HOME: config, XDG_STATE_HOME: path.join(home, 'state'),
            XDG_RUNTIME_DIR: path.join(home, 'runtime'), TMUX_TMPDIR: path.join(home, 'tmux'), TMPDIR: scratch,
            VGS_TEST_RUN: '1', HOOK_LOG: path.join(home, 'hooks') };
        function run(verb, theme = 'vgs', status = 0) {
            const result = spawnSync(process.execPath, [path.join(tree, 'bin/vgshell-theme-judge'), verb, 'json', path.join(config, 'vgshell'), state,
                ...(verb === 'setup' ? [] : ['held', theme])], { env, encoding: 'utf8', timeout: 30000 });
            assert.equal(result.status, status, result.stderr + result.stdout);
            return JSON.parse(result.stdout);
        }
        function put(file, text) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text); }
        return { home, config, state, run, put };
    }
    const cases = [
        ['helix', 'helix/config.toml', 'theme = "old" # keep\n[editor]\nline-number = "relative"\n', 'theme = "vgs" # keep\n[editor]\nline-number = "relative"\n'],
        ['helix', 'helix/config.toml', undefined, 'theme = "vgs"\n'],
        ['zed', 'zed/settings.json', '{ // owner\n "theme": "old", "buffer_font_size": 13,\n}\n', '{ // owner\n "theme": "vgs", "buffer_font_size": 13,\n}\n'],
        ['zed', 'zed/settings.json', '{"theme":{"mode":"system", "light":"old", "dark":"old"},"keep":"café"}\n', '{"theme":{"mode":"system", "light":"vgs", "dark":"vgs"},"keep":"café"}\n'],
        ['zed', 'zed/settings.json', undefined, '{\n  "theme": "vgs"\n}\n']
    ];
    function verifyCase(row) {
        const [name, relative, before, expected] = row;
        const w = world();
        const file = path.join(w.config, relative);
        if (before !== undefined) w.put(file, before);
        w.run('apply');
        assert.equal(fs.readFileSync(file, 'utf8'), expected, name);
        const generated = fs.readFileSync(path.join(w.state, 'theme', name === 'helix' ? 'helix.toml' : 'zed.json'), 'utf8');
        const zedTheme = path.join(w.config, 'zed/themes/vgs.json');
        if (name === 'zed') {
            assert.ok(fs.lstatSync(zedTheme).isFile());
            assert.equal(fs.readFileSync(zedTheme, 'utf8'), generated);
            fs.unlinkSync(zedTheme);
            fs.symlinkSync(path.join(w.state, 'theme/zed.json'), zedTheme);
        }
        if (name === 'helix' && before !== undefined) {
            const hooks = fs.readFileSync(path.join(w.home, 'hooks'), 'utf8');
            w.put(file, before);
            w.run('apply');
            assert.equal(fs.readFileSync(file, 'utf8'), expected);
            assert.ok(fs.readFileSync(path.join(w.home, 'hooks'), 'utf8').slice(hooks.length).includes('hx|helix'));
        }
        w.run('apply', 'other');
        assert.equal(fs.readFileSync(file, 'utf8'), expected);
        assert.notEqual(fs.readFileSync(path.join(w.state, 'theme', name === 'helix' ? 'helix.toml' : 'zed.json'), 'utf8'), generated);
        if (name === 'zed') {
            assert.ok(fs.lstatSync(zedTheme).isFile());
            assert.equal(fs.readFileSync(zedTheme, 'utf8'), fs.readFileSync(path.join(w.state, 'theme/zed.json'), 'utf8'));
        }
    }
    function verifyVaults() {
        const w = world();
        const vaults = ['one', 'two', 'closed'].map(name => path.join(w.home, name));
        for (const vault of vaults.slice(0, 2)) w.put(path.join(vault, '.obsidian/appearance.json'), '{"cssTheme":"old", "accentColor":"#123456"}\n');
        w.put(path.join(w.config, 'obsidian/obsidian.json'), JSON.stringify({ vaults: Object.fromEntries(vaults.map((vault, i) => [i, { path: vault }])) }));
        fs.rmSync(path.join(vaults[1], '.obsidian/appearance.json'));
        w.run('apply');
        const expected = ['{"cssTheme":"vgs", "accentColor":"#123456"}\n', '{\n  "cssTheme": "vgs"\n}\n'];
        for (const [i, vault] of vaults.slice(0, 2).entries()) assert.equal(fs.readFileSync(path.join(vault, '.obsidian/appearance.json'), 'utf8'), expected[i]);
        w.run('apply', 'other');
        for (const [i, vault] of vaults.slice(0, 2).entries()) assert.equal(fs.readFileSync(path.join(vault, '.obsidian/appearance.json'), 'utf8'), expected[i]);
        assert.equal(fs.existsSync(vaults[2]), false);
    }
    function verifyEmacs() {
        verifyCompiledEmacs();
        for (const owned of [true, false]) {
            const w = world();
            const previous = path.join(w.config, 'emacs/vgs-theme.el');
            const generated = '(load "' + path.join(w.state, 'theme/emacs.el') + '" nil t)\n';
            const before = generated + (owned ? '' : '; owner edit\n');
            const init = path.join(w.config, 'emacs/init.el');
            const reference = '(load "' + previous + '" nil t)\n';
            w.put(previous, before);
            w.put(init, reference + '(setq keep t)\n');
            w.run('apply');
            const expected = (owned ? '' : reference) + '(setq keep t)\n' + generated;
            assert.equal(fs.readFileSync(init, 'utf8'), expected);
            assert.equal(fs.existsSync(previous), !owned);
            if (!owned) assert.equal(fs.readFileSync(previous, 'utf8'), before);
            w.run('apply', 'other');
            assert.equal(fs.readFileSync(init, 'utf8'), expected);
            assert.equal(fs.existsSync(previous), !owned);
        }
        const w = world();
        const previous = path.join(w.config, 'emacs/vgs-theme.el');
        const generated = '(load "' + path.join(w.state, 'theme/emacs.el') + '" nil t)\n';
        w.put(previous, generated);
        const init = path.join(w.home, '.emacs.el');
        fs.mkdirSync(path.join(w.home, '.emacs.d'));
        w.put(init, '(setq keep t)\n');
        w.put(path.join(w.home, '.emacs.elc'), 'compiled init\n');
        fs.chmodSync(path.dirname(previous), 0o500);
        try {
            const row = w.run('apply', 'vgs', 3).targets.find(row => row.name === 'emacs');
            assert.equal(row.state, 'failed');
            assert.equal(row.reason, 'unwritable');
            assert.equal(fs.readFileSync(previous, 'utf8'), generated);
            assert.equal(fs.readFileSync(init, 'utf8'), '(setq keep t)\n');
            assert.equal(fs.readFileSync(path.join(w.home, '.emacs.elc'), 'utf8'), 'compiled init\n');
        } finally { fs.chmodSync(path.dirname(previous), 0o700); }
        const unsafe = world();
        const helper = path.join(unsafe.config, 'emacs/vgs-theme.el');
        const initFile = path.join(unsafe.home, '.emacs.el');
        fs.mkdirSync(path.join(unsafe.home, '.emacs.d'));
        unsafe.put(helper, '(load "' + path.join(unsafe.state, 'theme/emacs.el') + '" nil t)\n');
        unsafe.put(initFile, '`(owner ,(load "' + helper + '"))\n');
        const saved = [helper, initFile].map(file => fs.readFileSync(file));
        const refused = unsafe.run('apply', 'vgs', 3).targets.find(row => row.name === 'emacs');
        assert.equal(refused.reason, 'wiring-conflict');
        for (const [index, file] of [helper, initFile].entries()) assert.deepEqual(fs.readFileSync(file), saved[index]);
    }
    function verifyCompiledEmacs() {
        // startup--xdg-or-homedot chooses the directory before legacy files.
        // The loaded .elc maps to .el source, then to the bare legacy file:
        // https://github.com/emacs-mirror/emacs/blob/emacs-30/lisp/startup.el
        // lread.c reaches native caches only through the matching .elc.
        for (const [files, directories, relative, owned = true, data = true] of [
            [['.emacs.el', '.emacs.elc', '.emacs', '.emacs.d/init.el', '.emacs.d/init.elc', 'settings/emacs/init.el', 'settings/emacs/init.elc'], [], '.emacs.el'],
            [['.emacs', '.emacs.elc', '.emacs.d/init.el', 'settings/emacs/init.el', 'settings/emacs/init.elc'], [], '.emacs'],
            [['.emacs.d/init.el', '.emacs.d/init.elc', 'settings/emacs/init.el', 'settings/emacs/init.elc'], [], '.emacs.d/init.el'],
            [['settings/emacs/init.el', 'settings/emacs/init.elc'], [], 'settings/emacs/init.el'],
            [['.emacs.el', '.emacs.elc', 'settings/emacs/init.el', 'settings/emacs/init.elc'], [], 'settings/emacs/init.el'],
            [['.emacs.elc', 'settings/emacs/init.el', 'settings/emacs/init.elc'], [], 'settings/emacs/init.el'],
            [['.emacs.el', '.emacs.elc'], [], 'settings/emacs/init.el'],
            [['.emacs.el', '.emacs.elc', 'settings/emacs/init.el', 'settings/emacs/init.elc'], ['.emacs.d'], '.emacs.el'],
            [['settings/emacs/init.el', 'settings/emacs/init.elc'], ['.emacs.d'], '.emacs.d/init.el'],
            [['.emacs.el', '.emacs.elc'], [], '.emacs.el', false],
            [['.emacs'], [], '.emacs', false],
            [['settings/emacs/init.el'], [], 'settings/emacs/init.el'],
            [['.emacs.el'], ['.emacs.d'], '.emacs.el', true, false],
            [[], [], '.emacs.d/init.el', false],
            [['.emacs.elc'], [], '.emacs.el', false],
            [['.emacs.d/init.elc'], [], '.emacs.d/init.el'],
            [['settings/emacs/init.elc', '.emacs.el', '.emacs.elc'], [], 'settings/emacs/init.el']
        ]) {
            const w = world();
            const init = path.join(w.home, relative);
            const compiled = init.replace(/\.el$/, '') + '.elc';
            const native = path.join(w.home, 'eln-cache/init.eln');
            const previous = path.join(w.config, 'emacs/vgs-theme.el');
            const loader = '(load "' + path.join(w.state, 'theme/emacs.el') + '" nil t)\n';
            const saved = '(setq saved-form \'(load "' + previous + '" nil t))\n';
            const before = (owned ? (data ? saved : '') + '(load "' + previous + '" nil t)\n' : '') + (data ? '(setq keep t)\n' : '');
            if (owned) w.put(previous, loader);
            for (const directory of directories) fs.mkdirSync(path.join(w.home, directory), { recursive: true });
            for (const file of files) w.put(path.join(w.home, file), file.endsWith('.elc') ? 'compiled owner bytes\n' : before);
            w.put(native, 'native owner bytes\n');
            const originals = new Map([...files, 'eln-cache/init.eln'].map(file => [file, fs.readFileSync(path.join(w.home, file))]));
            const sourceExists = files.includes(relative);
            const compiledOnly = !sourceExists && files.includes(path.relative(w.home, compiled));
            const result = w.run('apply', 'vgs', compiledOnly ? 3 : 0);
            if (compiledOnly) {
                const row = result.targets.find(row => row.name === 'emacs');
                assert.equal(row.state, 'failed');
                assert.equal(row.reason, 'wiring-source-absent');
                assert.equal(fs.existsSync(init), false);
                if (owned) assert.equal(fs.readFileSync(previous, 'utf8'), loader);
            } else {
                const expected = (sourceExists ? (owned && data ? saved : '') + (data ? '(setq keep t)\n' : '') : '') + loader;
                assert.equal(fs.readFileSync(init, 'utf8'), expected, relative);
                assert.equal(fs.existsSync(compiled), false, relative);
                assert.equal(fs.existsSync(previous), false);
                const generated = fs.readFileSync(path.join(w.state, 'theme/emacs.el'), 'utf8');
                assert.match(generated, /^\(mapc #'disable-theme custom-enabled-themes\)\r?$/m);
                assert.match(generated, /^\(deftheme vgs /m);
                assert.match(generated, /^\(enable-theme 'vgs\)\r?$/m);
                assert.ok(fs.readFileSync(path.join(w.home, 'hooks'), 'utf8').includes(loader.trim()));
                w.put(compiled, 'fresh compiled selector\n');
                const stat = fs.statSync(compiled);
                w.run('apply', 'other');
                assert.equal(fs.readFileSync(init, 'utf8'), expected);
                assert.equal(fs.readFileSync(compiled, 'utf8'), 'fresh compiled selector\n');
                assert.equal(fs.statSync(compiled).mtimeMs, stat.mtimeMs);
            }
            for (const [file, bytes] of originals) {
                const absolute = path.join(w.home, file);
                if (compiledOnly || (absolute !== init && absolute !== compiled))
                    assert.deepEqual(fs.readFileSync(absolute), bytes, relative + ': preserves ' + file);
            }
        }
        const w = world();
        const source = path.join(w.config, 'source.el');
        const init = path.join(w.home, '.emacs.el');
        fs.mkdirSync(path.join(w.home, '.emacs.d'));
        const compiled = path.join(w.home, '.emacs.elc');
        const previous = path.join(w.config, 'emacs/vgs-theme.el');
        const loader = '(load "' + path.join(w.state, 'theme/emacs.el') + '" nil t)\n';
        w.put(source, '(load "' + previous + '" nil t)\n');
        w.put(previous, loader);
        w.put(compiled, 'compiled old reference\n');
        fs.symlinkSync(source, init);
        w.put(path.join(w.home, 'hooks'), '');
        fs.mkdirSync(w.state, { recursive: true });
        const before = [source, compiled, previous].map(file => fs.readFileSync(file));
        fs.chmodSync(w.home, 0o500);
        try {
            const result = w.run('apply', 'vgs', 3);
            assert.deepEqual(result.targets.filter(row => row.state === 'failed').map(row => row.name), ['emacs']);
            const row = result.targets.find(row => row.name === 'emacs');
            assert.equal(row.state, 'failed');
            assert.equal(row.reason, 'unwritable');
            for (const [index, file] of [source, compiled, previous].entries()) assert.deepEqual(fs.readFileSync(file), before[index]);
            assert.equal(fs.readlinkSync(init), source);
        } finally { fs.chmodSync(w.home, 0o700); }
    }
    function verifyPosh() {
        for (const [before, reason] of [
            [undefined, 'no Oh My Posh init line'],
            ['export KEEP=1\neval "$(oh-my-posh init bash --config old.json)" # keep\n', null],
            ['eval "$(oh-my-posh init zsh --config old.json)"\n', null],
            ['# no prompt\nexport KEEP=1\n', 'no Oh My Posh init line'],
            ['eval "$(oh-my-posh init bash --config "$THEME")"\n', 'dynamic Oh My Posh init form'],
            ['if true; then eval "$(oh-my-posh init bash --config old.json)"; fi\n', 'complex Oh My Posh init form']
        ]) {
            const w = world();
            const file = path.join(w.home, '.bashrc');
            if (before !== undefined) w.put(file, before);
            w.run('apply');
            const expected = reason ? before : before.replace('old.json', "'" + path.join(w.config, 'oh-my-posh/vgs.omp.json') + "'");
            const contents = () => fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : undefined;
            assert.equal(contents(), expected);
            const rows = w.run('setup').wiring.filter(row => row.name === 'oh-my-posh');
            if (reason === 'no Oh My Posh init line') assert.deepEqual(rows.map(row => [row.file, row.state, row.line, row.reason]),
                ['.bashrc', '.bash_profile', '.profile', '.zshrc'].map(name => [path.join(w.home, name), 'not-wired', null, reason]));
            else if (reason) assert.ok(rows.some(row => row.state === 'not-wired' && row.file === file && row.reason === reason), JSON.stringify(rows));
            else assert.ok(rows.some(row => row.state === 'wired' && row.file === file));
            w.run('apply', 'other');
            assert.equal(contents(), expected);
        }
    }
    for (const row of cases) verifyCase(row);
    verifyVaults(); verifyEmacs(); verifyPosh();
    const zedFile = path.join(tree, 'themes/targets/zed/target.json');
    const zed = JSON.parse(JSON.stringify(targets.get('zed')));
    zed.wiring.links = zed.wiring.copies;
    delete zed.wiring.copies;
    fs.writeFileSync(zedFile, JSON.stringify(zed));
    assert.throws(() => verifyCase(cases.find(row => row[0] === 'zed')), { code: 'ERR_ASSERTION' });
    fs.writeFileSync(zedFile, JSON.stringify(targets.get('zed')));
    const emacsTemplate = path.join(tree, 'themes/targets/emacs/emacs.el');
    const template = fs.readFileSync(emacsTemplate, 'utf8');
    const activation = "(enable-theme 'vgs)";
    assert.equal(template.split(activation).length, 2);
    fs.writeFileSync(emacsTemplate, template.replace(activation, '; ' + activation));
    assert.throws(verifyEmacs, { code: 'ERR_ASSERTION' });
    fs.writeFileSync(emacsTemplate, template);
    const judgeFile = path.join(tree, 'bin/vgshell-theme-judge');
    const judge = fs.readFileSync(judgeFile, 'utf8');
    const missingInit = 'disconnected(path.join(baseDir(target.select.base, configHome), file), "no Oh My Posh init line")';
    assert.equal(judge.split(missingInit).length, 2);
    const homeReport = judge.replace(missingInit, 'disconnected(os.homedir(), "no Oh My Posh init line")');
    assert.notEqual(homeReport, judge);
    fs.writeFileSync(judgeFile, homeReport);
    assert.throws(verifyPosh, { code: 'ERR_ASSERTION' }, 'a home directory cannot stand for an init file');
    fs.writeFileSync(judgeFile, judge);
    const invalidation = 'writing(compiled, key, () => fs.unlinkSync(compiled));';
    assert.equal(judge.split(invalidation).length, 2);
    fs.writeFileSync(judgeFile, judge.replace(invalidation, 'void compiled;'));
    assert.throws(verifyCompiledEmacs, { code: 'ERR_ASSERTION' });
    fs.writeFileSync(judgeFile, judge);
    const directoryGuard = 'if (directory === old) {';
    assert.equal(judge.split(directoryGuard).length, 2);
    fs.writeFileSync(judgeFile, judge.replace(directoryGuard, 'if (true) {'));
    assert.throws(verifyCompiledEmacs, { code: 'ERR_ASSERTION' });
    fs.writeFileSync(judgeFile, judge);
    const helixFile = path.join(tree, 'themes/targets/helix/target.json');
    const helix = JSON.parse(JSON.stringify(targets.get('helix')));
    delete helix.reload.always;
    fs.writeFileSync(helixFile, JSON.stringify(helix));
    assert.throws(() => verifyCase(cases[0]), { code: 'ERR_ASSERTION' });
    fs.writeFileSync(helixFile, JSON.stringify(targets.get('helix')));
    for (const name of names) {
        const file = path.join(tree, 'themes/targets', name, 'target.json');
        const target = JSON.parse(JSON.stringify(targets.get(name)));
        if (name === 'emacs') target.wiring = { file: 'emacs/vgs-theme.el', line: target.wiring.line, create: true };
        else delete target.select;
        fs.writeFileSync(file, JSON.stringify(target));
        assert.throws(() => name === 'obsidian' ? verifyVaults() : name === 'emacs' ? verifyEmacs() : name === 'oh-my-posh' ? verifyPosh() : verifyCase(cases.find(row => row[0] === name)),
            { code: 'ERR_ASSERTION' }, name + ': original behavior must fail the same assertion');
        fs.writeFileSync(file, JSON.stringify(targets.get(name)));
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
JS

rows_done test-vgshell-targets
