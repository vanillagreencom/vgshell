#!/usr/bin/env bash
# Controls for the login screen's compositor configuration,
# config/system/greeter/hyprland.lua: the keyboard layout it reads from
# /etc/vconsole.conf, and the private fonts passed by its actual
# hyprland.start callback. Each row runs the file
# under the system's lua with a stand-in `hl` that prints the `input`
# table it is handed, and with io.open answering a fixture for
# /etc/vconsole.conf; nothing reads the real file or starts Hyprland. Each
# start runs bin/vgshell with a recording qs and a no-op hyprctl in a
# disposable install tree. Controls run copies missing each rule; today's
# installed-font start must fail the copy assertion. No compositor starts.
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
local start
io.popen = function(command, mode)
  local helper = os.getenv("VGS_GREETER_ROOT") .. "/bin/vgshell-greeter-layout"
  assert(command == "'" .. helper:gsub("'", "'\\''") .. "' render")
  assert(mode == "r")
  return assert(real_open(os.getenv("MONITOR_LUA"), "r"))
end
io.open = function(path, mode)
  if path == "/etc/vconsole.conf" then path = os.getenv("VCONSOLE") end
  return real_open(path, mode)
end
hl = {
  config = function(t)
    if os.getenv("START_CAPTURE") then return end
    local i = t.input
    print(i.kb_layout .. "|" .. i.kb_variant .. "|" .. i.kb_model .. "|" .. i.kb_options)
  end,
  on = function(event, callback)
    assert(event == "hyprland.start")
    start = callback
  end,
  exec_cmd = function(command) assert(os.execute(command)) end,
  monitor = function(m)
    print(m.output .. "|" .. m.mode .. "|" .. m.position .. "|" .. m.scale .. "|" .. m.transform)
  end,
}
dofile(arg[1])
if os.getenv("START_CAPTURE") then assert(start)() end
EOF
: >"$tmp/monitors.lua"

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
    got="$(env -i VGS_GREETER_ROOT=/fixture MONITOR_LUA="$tmp/monitors.lua" VCONSOLE="$tmp/vconsole.conf" "$lua_bin" "$tmp/stand-in.lua" "$file" 2>&1)" || got="exit=$? $got"
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

# Use the production renderer, then execute its output inside the actual
# greeter config. No fixture starts a compositor or reads a system file.
"$node_bin" - "$repo/bin/lib/greeter-layout.js" >"$tmp/monitors.lua" <<'JS'
const { judge } = require(process.argv[2]);
const data = { outputs: {
  "DP-2": { mode: { width: 5120, height: 2880, refresh: 60 }, position: { x: 0, y: 0 }, scale: 2, transform: 1 },
  "DP-1": { mode: { width: 6016, height: 3384, refresh: 60 }, position: { x: 1440, y: 620 }, scale: 2, transform: 0 }
}, primaryOutput: "DP-1" };
process.stdout.write(judge(JSON.stringify(data)).lines.join("\n"));
JS
monitor_rows() {
  local got
  got="$(env -i VGS_GREETER_ROOT=/fixture MONITOR_LUA="$tmp/monitors.lua" VCONSOLE="$tmp/no-vconsole" "$lua_bin" "$tmp/stand-in.lua" "$1")" || return
  [[ $got == $'DP-1|6016x3384@60|1440x620|2|0\nDP-2|5120x2880@60|0x0|2|1\nus|||' ]]
}
check "the compositor applies the rotated two-monitor saved layout" monitor_rows "$config"
copy_with no-monitors "$config" 'local rendered = pipe:close()' 'pipe:close(); local rendered = false'
if monitor_rows "$copy" 2>/dev/null; then fail "control: the compositor still applies no monitor layout"; else ok "control: missing layout application fails the compositor assertion"; fi

# Capture qs at the production launch boundary. Spaces and a quote in the
# install path remain data through Lua's shell command and the runner.
font_tree="$tmp/install tree's"
mkdir -p -- "$font_tree/bin/lib" "$font_tree/shell/assets/fonts" "$tmp/start-bin"
cp -- "$repo/bin/vgshell" "$font_tree/bin/"
cp -- "$repo/bin/lib/ipc-reply.sh" "$font_tree/bin/lib/"
cat >"$tmp/start-bin/qs" <<'PY'
#!/usr/bin/python3
import json, os, sys
with open(os.environ["FONT_CAPTURE"], "w") as out:
    json.dump({"argv": sys.argv[1:], "fonts": {
        key: os.environ.get(key) for key in ("VGSHELL_FONT_SANS", "VGSHELL_FONT_MONO")
    }}, out)
PY
printf '#!/usr/bin/bash\nexit 0\n' >"$tmp/start-bin/hyprctl"
chmod +x -- "$tmp/start-bin/qs" "$tmp/start-bin/hyprctl"

# One contract table: a failed font copy clears that variable even if an
# installed path was inherited; the other font still copies independently.
start_rows() { # CONFIG QUIET [MODE]
  local file="$1" quiet="$2" mode dir status red=0
  local modes=(both missing-sans missing-mono unavailable-directory)
  [[ $# == 2 ]] || modes=("$3")
  for mode in "${modes[@]}"; do
    dir="$tmp/start-$mode"
    mkdir -p -- "$dir/state/other" "$dir/runtime/other" "$dir/home"
    printf 'state\n' >"$dir/state/other/keep"
    printf 'runtime\n' >"$dir/runtime/other/keep"
    cp -- "$repo/shell/assets/fonts/InterVariable.ttf" "$repo/shell/assets/fonts/JetBrainsMono-Variable.ttf" "$font_tree/shell/assets/fonts/"
    case "$mode" in
      missing-sans) rm -- "$font_tree/shell/assets/fonts/InterVariable.ttf" ;;
      missing-mono) rm -- "$font_tree/shell/assets/fonts/JetBrainsMono-Variable.ttf" ;;
    esac
    if [[ $mode == unavailable-directory ]]; then
      : >"$dir/state/fonts"
    else
      mkdir -p -- "$dir/state/fonts"
      printf 'obsolete\n' >"$dir/state/fonts/obsolete.ttf"
    fi
    rm -f -- "$dir/capture.json"
    status=0
    env -i PATH="$tmp/start-bin:/usr/bin" HOME="$dir/home" VGS_TEST_RUN=1 \
      VGS_GREETER_ROOT="$font_tree" XDG_STATE_HOME="$dir/state" XDG_RUNTIME_DIR="$dir/runtime" \
      VGSHELL_FONT_SANS="$font_tree/shell/assets/fonts/InterVariable.ttf" \
      VGSHELL_FONT_MONO="$font_tree/shell/assets/fonts/JetBrainsMono-Variable.ttf" \
      MONITOR_LUA="$tmp/monitors.lua" VCONSOLE="$tmp/no-vconsole" START_CAPTURE=1 FONT_CAPTURE="$dir/capture.json" \
      "$lua_bin" "$tmp/stand-in.lua" "$file" >"$dir/start.log" 2>&1 || status=$?
    if [[ $status == 0 ]] && python3 - "$dir" "$font_tree" "$repo" "$mode" <<'PY'
import hashlib, json, pathlib, stat, sys
directory, tree, repo = map(pathlib.Path, sys.argv[1:4])
mode = sys.argv[4]
record = json.loads((directory / "capture.json").read_text())
assert record["argv"] == ["-p", str(tree / "shell/greeter.qml")]
assert (directory / "state/other/keep").read_text() == "state\n"
assert (directory / "runtime/other/keep").read_text() == "runtime\n"
assert not (directory / "runtime/vgshell/fonts").exists()
destination = directory / "state/fonts"
kept = set()
for key, name, missing in (
    ("VGSHELL_FONT_SANS", "InterVariable.ttf", "missing-sans"),
    ("VGSHELL_FONT_MONO", "JetBrainsMono-Variable.ttf", "missing-mono"),
):
    value = record["fonts"][key]
    if mode in (missing, "unavailable-directory"):
        assert value is None, (mode, key, value)
    else:
        content = (repo / "shell/assets/fonts" / name).read_bytes()
        expected = destination / (hashlib.sha256(content).hexdigest() + ".ttf")
        assert value == str(expected), (key, value, str(expected))
        assert expected.read_bytes() == content
        assert stat.S_IMODE(expected.stat().st_mode) == 0o600
        kept.add(expected.name)
if mode != "unavailable-directory":
    assert {p.name for p in destination.iterdir()} == kept
PY
    then
      [[ $quiet == quiet ]] || ok "hyprland.start passes only private content-named font copies: $mode"
    else
      red=$((red + 1))
      [[ $quiet == quiet ]] || fail "hyprland.start font copies: mode=$mode status=$status log=$dir/start.log"
    fi
  done
  return "$red"
}
start_rows "$config" loud || true
copy_with installed-font-start "$config" \
  '    hl.exec_cmd("\"$VGS_GREETER_ROOT/bin/vgshell\" greeter; hyprctl dispatch '\''hl.dsp.exit()'\''")' \
  '    hl.exec_cmd("VGSHELL_FONT_SANS=\"$VGS_GREETER_ROOT/shell/assets/fonts/InterVariable.ttf\" VGSHELL_FONT_MONO=\"$VGS_GREETER_ROOT/shell/assets/fonts/JetBrainsMono-Variable.ttf\" qs -p \"$VGS_GREETER_ROOT/shell/greeter.qml\"; hyprctl dispatch '\''hl.dsp.exit()'\''")'
if start_rows "$copy" quiet both 2>/dev/null; then
  fail "control: today's installed-font handler passes the copy assertion"
else
  # A control counts only after the actual callback reached the recording
  # qs with both installed paths, never on a failed launch or missing read.
  if python3 - "$tmp/start-both/capture.json" "$font_tree" <<'PY'
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text())
fonts = pathlib.Path(sys.argv[2]) / "shell/assets/fonts"
assert record["fonts"] == {
    "VGSHELL_FONT_SANS": str(fonts / "InterVariable.ttf"),
    "VGSHELL_FONT_MONO": str(fonts / "JetBrainsMono-Variable.ttf"),
}
PY
  then
    ok "control: today's hyprland.start fails the private font assertion"
  else
    fail "control: today's hyprland.start did not reach qs with installed fonts"
  fi
fi

rows_done "$suite"
