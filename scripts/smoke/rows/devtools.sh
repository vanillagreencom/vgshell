# Dev Tools, vgs.devtools. The plugin runs over harness.sh's
# devtools_stand_ins in the shell's own PATH directory: a mise whose
# installs are one key per line of a file the row writes, a docker and a
# podman that hold no container, and a pacman that owns no file, so every
# probe the engine and the core's
# commands make reaches a stand-in or reads the host's PATH. The row picks
# an agent whose command that PATH does not hold, so it lists absent on any
# host. harness.sh's stand-in terminal records the argv of every run and
# runs the install TUI as `true`, never the plugin's script
# (scripts/test-devtools.sh runs it), so a run ends at once; the row
# writes the key mise then holds itself, before the click.
# Rows: the service publishes the status its manifest declares; IPC open
# summons the window, which is read as every application window is
# (app_window_rows, scripts/smoke/app-window.sh, floated by the `vgs:window`
# rule rows/hyprland-consent.sh's Connect wires) and, opened again, draws
# the VGS section and every catalog section from the published catalog; a
# launcher row's summon focuses its row, and a second summon for that row
# focuses it again after Tab moved the keyboard off it; a click on the
# agent's Install records the install TUI's argv, and the list is read
# again once that run ended; the window's switch writes
# writeLaunchers, whose launcher verb writes and then removes the agent's
# launcher; the VGS section lists a fixture's missing
# requirement once the core's scan reports it, and its Install raises the
# core's requirement notice; the doctor capability answers for the core's
# commands and refuses a disabled or unknown owner; the Settings page reads
# the status rows back; on a narrow monitor the VGS row's own Details
# opens its clipped error while database rows a failing docker the row
# plants leaves unknown draw Details too; and, as the controls, a copy
# whose rows focus only on a change of the target row leaves the second
# summon unfocused, and a copy of the plugin whose service ignores a run's
# end and a change of the scan's missing commands leaves the list as it
# was after each.
# The keyboard install reading also reports host CPU pressure over its
# timed idle read as run_end_contention.cpu_some_pct (null if unavailable).
# The ceiling and 0.2 s poll interval remain expect_run_end's in harness.sh.
# inputs: shell/plugins/vgs.devtools/* shell/plugins/vgs.launcher/* shell/plugins/vgs.settings/* shell/Commons/Reply.js scripts/smoke/fixtures/plugins/acme.requires/* shell/Core/Notices.qml shell/Core/PluginStatus.qml shell/Core/PackageManagers.js shell/Core/TuiRunner.qml shell/Core/ShortcutRegistry.qml shell/Hosts/AppWindow.qml bin/vgshell VERSION config/requirements.json bin/lib/qml-library.js scripts/smoke/rows/status.sh bin/vgshell-tui scripts/smoke/rows/settings.sh scripts/smoke/rows/hyprland-consent.sh shell/Ui/layout/Pane.qml shell/Ui/layout/ScrollArea.qml shell/Commons/ClearingInset.qml shell/Commons/Inset.js shell/Ui/controls/RowAction.qml
set -euo pipefail
devtools_stand_ins
requires_dir="$home/.config/vgshell/plugins/acme.requires"
mkdir -p "$requires_dir"
cp -R "$repo/scripts/smoke/fixtures/plugins/acme.requires/." "$requires_dir/"
shell_path="$(tr '\0' '\n' <"/proc/$shell_qs_pid/environ" | sed -n 's/^PATH=//p')"
[[ -n $shell_path ]] || fail "the shell's PATH is unreadable"
in_shell_env() { "${shell_env[@]}" PATH="$shell_path" "$@"; }

# The first agent built for this machine whose command the shell's PATH
# does not hold and that has no exec file, as
# `<id>\t<name>\t<command>\t<key>\t<launch argv as JSON>`.
absent_agent() { node - "$repo" "$shell_path" <<'JS'
const fs = require("fs"), path = require("path");
const [repo, PATH] = process.argv.slice(2);
const Catalog = require(path.join(repo, "bin/lib/qml-library.js")).load(path.join(repo, "shell/plugins/vgs.devtools/CatalogLogic.js"));
const catalog = JSON.parse(fs.readFileSync(path.join(repo, "shell/plugins/vgs.devtools/catalog.json"), "utf8"));
const machine = process.arch === "arm64" ? "aarch64" : "x86_64";
const onPath = command => PATH.split(":").some(dir => { try { fs.accessSync(path.join(dir, command), fs.constants.X_OK); return true; } catch (e) { return false; } });
const row = catalog.agents.find(r => r.exec === undefined && Catalog.availableOn(r, machine) && !onPath(r.command));
if (row === undefined) process.exit(1);
console.log([row.id, row.name, row.command, Catalog.specKey(row.package), JSON.stringify(row.launch || [row.command])].join("\t"));
JS
}
IFS=$'\t' read -r agent_id agent_name agent_command agent_key agent_launch < <(absent_agent) || fail "no agent's command is absent from the shell's PATH"

terminal_row() { node - "$repo" <<'JS'
const fs = require("fs"), path = require("path");
const catalog = JSON.parse(fs.readFileSync(path.join(process.argv[2], "shell/plugins/vgs.devtools/catalog.json"), "utf8"));
const row = catalog.terminals.find(r => Array.isArray(r.launch) || r.command);
if (!row) process.exit(1);
console.log([row.id, row.name, row.command || row.id, row.package || row.id].join("\t"));
JS
}
language_row() { node - "$repo" <<'JS'
const fs = require("fs"), path = require("path");
const catalog = JSON.parse(fs.readFileSync(path.join(process.argv[2], "shell/plugins/vgs.devtools/catalog.json"), "utf8"));
const row = catalog.envs.find(r => r.launch === undefined && r.exec === undefined);
if (!row) process.exit(1);
console.log([row.id, row.name, row.command || row.id].join("\t"));
JS
}
IFS=$'\t' read -r terminal_id terminal_name terminal_command terminal_key < <(terminal_row) || fail "no terminal catalog row is available"
IFS=$'\t' read -r language_id language_name language_command < <(language_row) || fail "no language catalog row is available"

devtools() { ipc vgs.devtools invoke "$1" "${2:-}"; }
# Its arguments as one JSON list, written as row_texts writes one.
texts() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1:], ensure_ascii=False))' "$@"; }
dev_lent() { ipc shell lent | py_reply 'import json,sys; r=json.load(sys.stdin)["status"].get("vgs.devtools"); print(json.dumps(r if r is None else r["keys"]))'; }
window_shown() { [[ $(ipc smoke instanceGeometry window vgs.devtools) != absent ]] && echo shown || echo hidden; }
section_titles() { ipc smoke itemTexts window vgs.devtools SectionHeader | py_reply 'import json,sys; print(json.dumps([t[0] for t in json.load(sys.stdin) if t]))'; }
# The texts the first row drawing NAME draws, as JSON, or null.
row_texts() { ipc smoke itemTexts window vgs.devtools ToolRow | py_reply 'import json,sys; r=[t for t in json.load(sys.stdin) if t and t[0] == sys.argv[1]]; print(json.dumps(r[0] if r else None, ensure_ascii=False))' "$1"; }
devtools_vgs_button_count() {
  ipc smoke itemTexts window vgs.devtools ToolRow | py_reply 'import json,sys; rows=[row for row in json.load(sys.stdin) if row and row[0]=="VGS"]; assert len(rows)==1, "one VGS ToolRow required"; print(rows[0].count(sys.argv[1]))' "$1"
}
vgs_code_lines() { ipc smoke itemTexts window vgs.devtools CodeLine | py_reply 'import json,sys; print(len([row for row in json.load(sys.stdin) if row]))'; }
# The ended record the presenter of KEY's last run wrote, by file name, or
# `none`: the presenter writes it when it exits and keeps only the newest.
ended_record() { local stem="${1/\//@}" f found=none; for f in "$rt_dir/vgshell/tui/$stem@"*.ended.json; do [[ -e $f ]] && found="${f##*/}"; done; echo "$found"; }
# ended_record_moved KEY BEFORE: `moved` once KEY's ended record is another
# than BEFORE, so the presenter of the run a click started has exited and
# expect_run_end times only the core's reading of it.
ended_record_moved() { [[ $(ended_record "$1") != "$2" ]] && echo moved || echo waiting; }
# reveal_row NAME: the window scrolled so the first row drawing NAME sits a
# third of the way down its view, whatever height the monitor gives it.
reveal_row() {
  local shown
  shown="$(ipc smoke revealScopedText window vgs.devtools ToolRow "$1" Label "$1")" || return
  [[ $shown =~ ^[0-9.]+$ ]] && echo revealed || echo "$shown"
}
scroll_bottom() { local r; r="$(ipc smoke scrollTo window vgs.devtools 100000)" || return; [[ $r == \[* ]] && echo scrolled || echo "$r"; }
launcher_state() { [[ -f $home/.local/bin/$1 ]] && sed -n 2p "$home/.local/bin/$1" || echo absent; }
devtools_tui_state() { ipc shell lent | py_reply 'import json,sys; t=json.load(sys.stdin)["tui"]; print("present" if any(k.startswith("vgs.devtools/") for k in list(t["runs"].keys()) + t["pending"]) else "absent")'; }
devtools_focus_moved_from_search() {
  ipc smoke focused window vgs.devtools | py_reply 'import json,sys; row=json.load(sys.stdin); print("search" if row == ["TextField", "Search tools", False, False, True] else "moved")'
}
select_devtools_tab() {
  local wanted="$1" n
  devtools open >/dev/null || return 1
  case "$wanted" in
    Catalog) n=0 ;;
    Settings) n=1 ;;
    Info) n=2 ;;
    *) return 1 ;;
  esac
  while ((n > 0)); do
    type_keys -M ctrl -k Tab -m ctrl || return 1
    n=$((n - 1))
  done
  printf '[\n'
}
click_field_switch() {
  local label="$1" box x y
  box="$(ipc smoke descendantGeometry window vgs.devtools | py_reply 'import json,sys
items=json.load(sys.stdin); label=sys.argv[1]
def ancestors(i):
    out=[]
    p=items[i].get("parent", -1)
    while isinstance(p, int) and p >= 0:
        out.append(p)
        p=items[p].get("parent", -1)
    return out
fields=[i for i,it in enumerate(items) if it.get("type")=="Field" and it.get("visible")]
target=None
for f in fields:
    desc=[i for i in range(len(items)) if f in ancestors(i)]
    if any(items[i].get("text")==label and items[i].get("visible") for i in desc):
        for i in desc:
            if items[i].get("type")=="Switch" and items[i].get("visible"):
                target=items[i]["box"]
                break
    if target is not None:
        break
print(json.dumps(target) if target is not None else "absent")' "$label")" || return 1
  [[ $box == \[* ]] || { echo "click_field_switch: no switch for $label: $box" >&2; return 1; }
  read -r x y < <(at_centre "window:Dev Tools" "$box") || return 1
  click "$x" "$y"
}
launcher() { ipc vgs.launcher invoke "$1" "${2:-}"; }
launcher_rows() { ipc smoke launcherRows overlay vgs.launcher | py_reply 'import json,sys; t=sys.stdin.read(); print(json.dumps(json.loads(t)) if t.startswith("[") else t.strip())'; }
launcher_has_row() { launcher_rows | py_reply 'import json,sys; print(any(r[0] == sys.argv[1] and r[1] == sys.argv[2] for r in json.load(sys.stdin)))' "$1" "$2"; }
launcher_row_count() { launcher_rows | py_reply 'import json,sys; print(sum(1 for r in json.load(sys.stdin) if r[0] == sys.argv[1] and r[1] == sys.argv[2]))' "$1" "$2"; }
row_index() { launcher_rows | py_reply 'import json,sys; r=[i for i, x in enumerate(json.load(sys.stdin)) if x[0] == sys.argv[1] and x[1] == sys.argv[2]]; print(r[0] if r else "none")' "$1" "$2"; }
launcher_focused() { expect_poll "the launcher holds the keyboard for Dev Tools" true ipc smoke activeFocusIn overlay vgs.launcher; }
pick_launcher_row() {
  local kind="$1" label="$2" index n keys=()
  index="$(row_index "$kind" "$label")" || return 1
  [[ $index =~ ^[0-9]+$ ]] || { fail "no launcher row $kind $label to pick: $index"; return 1; }
  for ((n = 0; n < index; n++)); do keys+=(-k Down); done
  if ((index > 0)); then type_keys "${keys[@]}" || return 1; fi
  type_keys -k Return
}
launcher_section_titles() { launcher_rows | py_reply 'import json,sys; print(json.dumps([r[1] for r in json.load(sys.stdin) if r[0] == "menu" and r[1] in ["Agents","Apps","Command-line tools","Languages","Editors","Databases","Terminals"]]))'; }

rescan "rescan after adding the requirement fixture answers ok"
expect_poll "the requirement fixture is discovered" True plugin_known acme.requires
expect "enabling Dev Tools is allowed" ok ipc shell setPluginEnabled vgs.devtools true
expect_poll "the Dev Tools service is built" True record_exists vgs.devtools
expect_poll "the service publishes every status its manifest declares" '["catalog", "checks", "installed", "launcherRows", "mise", "missingRequirements", "outdated"]' dev_lent

# The window: IPC open summons it, a Hyprland window like any other, and
# opened again it draws the published catalog.
expect "IPC open summons the window" ok devtools open
app_window_rows "Dev Tools" vgs.devtools
expect "IPC open summons the window again" ok devtools open
expect_poll "the window is shown" shown window_shown
expect_poll "the window opens on Catalog search without a focus ring" '["TextField","Search tools",false,false,true]' ipc smoke focused window vgs.devtools
forget_record
type_keys -k Return -k Tab || fail "Return and Tab on the Dev Tools search failed"
expect_poll "Tab after Return is processed by the Dev Tools window" moved devtools_focus_moved_from_search
expect "control: Return on the Dev Tools search runs no TUI" absent devtools_tui_state
devtools_keyboard_install() {
  local seen=() focus label
  for _ in $(seq 1 80); do
    type_keys -k Tab || return 1
    focus="$(ipc smoke focused window vgs.devtools)" || return 1
    if [[ $focus != \[* ]]; then printf 'focus=%s\n' "$focus"; return; fi
    if python3 - "$focus" <<'PY'
import json, sys
row = json.loads(sys.argv[1])
sys.exit(0 if row[0] == "ScrollArea" and not row[3] else 1)
PY
    then continue; fi
    if ! python3 - "$focus" <<'PY'
import json, sys
row = json.loads(sys.argv[1])
if len(row) != 5 or not (row[2] and row[3] and row[4]):
    print("bad-focus=" + json.dumps(row))
    sys.exit(1)
PY
    then return 1; fi
    label="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[1])' "$focus")" || return 1
    seen+=("$label")
    if [[ $label == Install ]]; then
      type_keys -k Return || return 1
      printf 'ok\n'
      return 0
    fi
  done
  printf 'missing-install seen=%s\n' "$(IFS=,; echo "${seen[*]}")"
}
# keyboard_back: true while the shell reads the Dev Tools window holding
# the keyboard, else its reading and the window the compositor names active.
keyboard_back() {
  local held
  held="$(window_keyboard vgs.devtools)" || return
  if [[ $held == true ]]; then echo true; else echo "$held active=$(active_window)"; fi
}
install_before="$(ended_record vgs.devtools/install)"
forget_record
# The stand-in's run ends at once, so its terminal would take the keyboard
# and give it back before the shell read the leave, which Qt's Wayland
# client can drop. The run is held
# live, as a user's TUI is, until the shell reads the keyboard gone.
hold_runs
expect "the Dev Tools Tab tour reveals each focused action and Return reaches Install" ok devtools_keyboard_install
expect_poll "Return on the focused Install hands the install TUI the row's id" "$(words vgs.devtools/install tui/install.sh "$agent_id")" recorded_tail
expect_poll "the shell reads the Dev Tools window without the keyboard while the run's terminal holds it" false window_keyboard vgs.devtools
release_runs
expect_poll "the keyboard install run's presenter exits" moved ended_record_moved vgs.devtools/install "$install_before"
devtools_idle_cpu_start="$(cpu_some_us)"
devtools_idle_start="$(now_ms)"
expect_run_end "the keyboard install run ends" vgs.devtools/install
devtools_idle_ms=$(( $(now_ms) - devtools_idle_start ))
devtools_idle_cpu_pct="$(cpu_some_pct "$devtools_idle_cpu_start" "$(cpu_some_us)" "$devtools_idle_ms")"
printf '  run_end_contention={"cpu_some_pct":%s}\n' "${devtools_idle_cpu_pct/unmeasured/null}"
# The run's terminal took the keyboard; Escape waits until Hyprland hands
# it back to the window, or it reaches whatever holds it meanwhile.
expect_poll "the Dev Tools window holds the keyboard again after the run" true keyboard_back
type_keys -k Escape || fail "Escape after the Dev Tools keyboard path failed"
expect "Escape closes the Dev Tools window after the keyboard path" hidden window_shown
expect_poll "the Dev Tools window is gone after Escape-equivalent hide" hidden window_shown
expect "IPC open summons the window again after the keyboard path" ok devtools open
expect_poll "the window is shown again after the keyboard path" shown window_shown
expect_poll "the Catalog tab is first and draws every catalog section in order" \
  '["VGS", "Agents", "Apps", "Command-line tools", "Languages", "Editors", "Databases", "Terminals", "Other tools"]' section_titles
expect "the window switches to Info for the VGS section" '[' select_devtools_tab Info
# The error fits at the window's width, so no Details button is drawn.
# This wide reading controls the narrow disclosure check below.
expect_poll "the wide VGS row offers no Details for its unclipped error" 0 devtools_vgs_button_count Details
expect "the wide VGS row keeps its detail folded" 0 vgs_code_lines
# The window's insets: the content starts, at the VGS section's heading,
# the same distance in from the window's left side as the VGS row's last
# chip ends from its right side, within one pixel. The control moves the
# chip 8 px left in a copy of the same reading, which the check refuses.
# `[]` is the pass.
devtools_insets() {
  python3 - "$(ipc smoke shownWindowGeometry window vgs.devtools SectionHeader VGS)" "$(ipc smoke scopedWindowGeometry window vgs.devtools ToolRow VGS Badge Unknown)" "$(ipc smoke readInstance window vgs.devtools width)" "${1:-}" <<'PY'
import json, sys
head, chip, width, plant = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "narrow"
if not head.startswith("[") or not chip.startswith("[") or not width.replace(".", "", 1).isdigit():
    print(json.dumps(["heading=%s chip=%s width=%s" % (head, chip, width)])); sys.exit()
head, chip, width = json.loads(head), json.loads(chip), json.loads(width)
left, right = head[0], width - (chip[0] + chip[2] - (8 if plant else 0))
print(json.dumps([] if abs(left - right) <= 1 else ["left=%.2f right=%.2f" % (left, right)]))
PY
}
devtools_insets_planted() { devtools_insets narrow | py_reply 'import json,sys; print(any(e.startswith("left=") for e in json.load(sys.stdin)))'; }
geometry expect_poll "the content sits the same distance in from both window sides" '[]' devtools_insets
expect "control: a row narrowed on one side is refused" True devtools_insets_planted
expect "the window returns to Catalog for tool rows" '[' select_devtools_tab Catalog
expect_poll "the absent agent draws Not installed and Install" "$(texts "$agent_name" "Not installed" "Not installed" Install)" row_texts "$agent_name"
expect_poll "the other mise tool draws its version and its actions" "$(texts github:acme/extra 1.0.0 Installed Update Remove)" row_texts github:acme/extra
expect "enabling Launcher for Dev Tools launcher rows is allowed" ok ipc shell setPluginEnabled vgs.launcher true
expect_poll "the launcher service is built for Dev Tools rows" True record_exists vgs.launcher
expect "the launcher opens for Dev Tools categories" ok launcher summon '{}'
launcher_focused
type_keys -M ctrl -k b -m ctrl || fail "showing Dev Tools launcher categories failed"
expect_poll "the launcher's Dev Tools category appears" True launcher_has_row menu "Dev Tools"
pick_launcher_row menu "Dev Tools" || fail "opening the Dev Tools launcher category failed"
expect_poll "the Dev Tools launcher category lists catalog sections" '["Agents", "Apps", "Command-line tools", "Languages", "Editors", "Databases", "Terminals"]' launcher_section_titles
pick_launcher_row menu "Agents" || fail "opening the Dev Tools Agents launcher category failed"
expect_poll "the Dev Tools launcher category lists the absent agent row" True launcher_has_row plugin "$agent_name"
expect "the launcher closes after the category read" ok ipc shell hide overlay vgs.launcher
expect_poll "the category read launcher closed" 0 layer_count vgs:overlay
expect "the launcher searches for the absent agent command" ok ipc shell summon overlay vgs.launcher "{\"query\":\"$agent_command\"}"
launcher_focused
expect_poll "the root search finds the absent agent by command" True launcher_has_row plugin "$agent_name"
expect "the searched launcher closes" ok ipc shell hide overlay vgs.launcher
expect_poll "the searched launcher closed" 0 layer_count vgs:overlay
expect "the window switches to Settings for showInLauncher off" '[' select_devtools_tab Settings
click_field_switch "Show full catalog in launcher" || fail "the click on the show-in-launcher switch failed"
expect "the launcher opens after showInLauncher off" ok launcher summon '{}'
launcher_focused
type_keys -M ctrl -k b -m ctrl || fail "showing launcher categories with Dev Tools hidden failed"
expect_poll "showInLauncher off removes the Dev Tools category" False launcher_has_row menu "Dev Tools"
expect "the launcher searches while showInLauncher is off" ok ipc shell summon overlay vgs.launcher "{\"query\":\"$agent_command\"}"
expect_poll "showInLauncher off removes search rows" 0 launcher_row_count plugin "$agent_name"
expect "the launcher closes after the showInLauncher off read" ok ipc shell hide overlay vgs.launcher
expect_poll "the launcher after showInLauncher off closed" 0 layer_count vgs:overlay
expect "the window switches to Settings for showInLauncher on" '[' select_devtools_tab Settings
click_field_switch "Show full catalog in launcher" || fail "the second click on the show-in-launcher switch failed"
expect "the launcher opens after showInLauncher on" ok launcher summon '{}'
launcher_focused
type_keys -M ctrl -k b -m ctrl || fail "showing launcher categories with Dev Tools restored failed"
expect_poll "showInLauncher on restores the Dev Tools category" True launcher_has_row menu "Dev Tools"
expect "the launcher closes after the showInLauncher on read" ok ipc shell hide overlay vgs.launcher
expect_poll "the launcher after showInLauncher on closed" 0 layer_count vgs:overlay
expect "the window returns to Catalog" '[' select_devtools_tab Catalog
forget_record
expect "the launcher opens to install-launch the absent agent" ok ipc shell summon overlay vgs.launcher "{\"query\":\"$agent_command\"}"
launcher_focused
install_launch_before="$(ended_record vgs.devtools/install-launch)"
# The run is held live until its record is read: its end launches the
# agent, whose terminal record replaces it.
hold_runs
pick_launcher_row plugin "$agent_name" || fail "picking the not-installed Dev Tools launcher row failed"
expect_poll "the launcher install path records install-launch with the plain row id" "$(words vgs.devtools/install-launch tui/devtools.sh install-launch "$agent_id")" recorded_tail
release_runs
expect_poll "the install-launch run ends" moved ended_record_moved vgs.devtools/install-launch "$install_launch_before"
expect_poll "the install-launch success launches the agent in a terminal" "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])))' "$agent_launch")" recorded
printf '%s\n' "$terminal_key" >>"$dev_state/installed"
expect "refresh after planting terminal install answers ok" ok devtools refresh
forget_record
expect "the launcher opens to the installed terminal row" ok launcher summon '{}'
launcher_focused
type_keys -M ctrl -k b -m ctrl || fail "showing categories for the terminal row failed"
pick_launcher_row menu "Dev Tools" || fail "opening Dev Tools for the terminal row failed"
pick_launcher_row menu "Terminals" || fail "opening Terminals for the terminal row failed"
pick_launcher_row plugin "$terminal_name" || fail "picking the installed terminal Dev Tools launcher row failed"
expect_poll "the installed terminal launcher row records a terminal launch" "$(words "$terminal_command")" recorded
expect "the launcher opens the language row" ok launcher summon '{}'
launcher_focused
type_keys -M ctrl -k b -m ctrl || fail "showing categories for the language row failed"
pick_launcher_row menu "Dev Tools" || fail "opening Dev Tools for the language row failed"
pick_launcher_row menu "Languages" || fail "opening Languages for the language row failed"
pick_launcher_row plugin "$language_name" || fail "picking the language Dev Tools launcher row failed"
expect_poll "the language row opens Dev Tools" shown window_shown
# The focused item's type and the row key the window was summoned for.
language_focus() {
  local focused target
  focused="$(ipc smoke focused window vgs.devtools | py_reply 'import json,sys; row=json.load(sys.stdin); print(row[0] if isinstance(row,list) and row else row)')" || return
  target="$(ipc smoke readInstance window vgs.devtools targetRow | py_reply 'import json,sys; t=sys.stdin.read().strip(); print(json.loads(t) if t.startswith("\"") else t)')" || return
  printf '%s %s\n' "$focused" "$target"
}
expect_poll "the language row payload focuses its Catalog row" "ToolRow envs/$language_id" language_focus
# A second summon for the row the window already targets leaves targetRow
# as it was, and still focuses the row after Tab moved the keyboard off it.
language_payload="{\"row\":\"envs/$language_id\"}"
# `row` while a ToolRow holds the keyboard, else `moved`, then the target.
language_focus_place() { local f; f="$(language_focus)" || return; [[ ${f%% *} == ToolRow ]] && echo "row ${f#* }" || echo "moved ${f#* }"; }
type_keys -k Tab || fail "Tab off the language row failed"
expect_poll "Tab moves the keyboard off the language row" "moved envs/$language_id" language_focus_place
expect "a second summon for the language row answers ok" ok ipc shell summon window vgs.devtools "$language_payload"
expect_poll "the second summon focuses the language row again" "row envs/$language_id" language_focus_place
forget_record
expect "the language window hides after launcher read" ok ipc shell hide window vgs.devtools
expect_poll "the language window is gone" hidden window_shown
expect "IPC open summons the window again after launcher reads" ok devtools open
expect_poll "the window is shown again after launcher reads" shown window_shown
expect "the window returns to Catalog after launcher reads" '[' select_devtools_tab Catalog

# A row's actions stand beside its text while they take at most half the
# text's room, and move under it past that, so a narrow window never
# starves the name: the other mise tool's Update and Remove sit beside its
# name in the window at its own width, and under it in a window on a
# monitor 360 logical pixels wide. The wide reading is the narrow check's
# control: the same reader answers `beside` there.
actions_place() { # ROW BUTTON
  python3 - "$(ipc smoke scopedWindowGeometry window vgs.devtools ToolRow "$1" Label "$1")" "$(ipc smoke scopedWindowGeometry window vgs.devtools ToolRow "$1" RowAction "$2")" <<'PY'
import json, sys
name, button = sys.argv[1], sys.argv[2]
if not name.startswith("[") or not button.startswith("["):
    print("unread name=%s button=%s" % (name, button)); sys.exit()
name, button = json.loads(name), json.loads(button)
print("under" if button[1] >= name[1] + name[3] else "beside")
PY
}
expect_poll "the other mise tool's actions sit beside its name at the window's width" beside actions_place github:acme/extra Update
expect "the window hides before the narrow monitor" ok ipc shell hide window vgs.devtools
expect_poll "the window is gone before the narrow monitor" hidden window_shown
narrow_monitor="$(first_name)" || fail "the monitor is unreadable"
narrow_main_mode="$(first_mode)" || fail "the monitor's mode is unreadable"
narrow_saved_w="$mon_w" narrow_saved_h="$mon_h"
hold_mode "the nested compositor makes its monitor narrower than the window" "$narrow_monitor" 360x720
mon_w=360 mon_h=720
expect_poll "the monitor is 360 logical pixels wide" 360 first_width
# Other tool rows with a clipped error draw their own Details. The row
# plants them: a docker whose container list fails leaves every database
# row docker serves at State unknown, and that error line is longer than
# the VGS row's, so it clips wherever the VGS line does. The open below
# lists again over it.
cp -- "$shim/docker" "$dev_state/docker.saved"
printf '#!/bin/sh\necho "docker: planted failure" >&2\nexit 1\n' >"$shim/docker.next"
chmod 755 "$shim/docker.next"
mv -T -- "$shim/docker.next" "$shim/docker"
# The names of the database rows docker serves, as JSON.
docker_rows="$(python3 -c 'import json,sys; print(json.dumps([r["name"] for r in json.load(open(sys.argv[1]))["databases"] if "docker" in r["container"]["runtimes"]]))' "$repo/shell/plugins/vgs.devtools/catalog.json")" || fail "the catalog's database rows are unreadable"
[[ $docker_rows != "[]" ]] || fail "no catalog database row is served by docker"
# How many of those rows draw a Details button; a row the host or an
# earlier row leaves with a clipped error of its own does not count.
planted_details() {
  ipc smoke itemTexts window vgs.devtools ToolRow | py_reply 'import json,sys; names=json.loads(sys.argv[1]); print(sum(1 for row in json.load(sys.stdin) if row and row[0] in names and "Details" in row))' "$docker_rows"
}
expect "IPC open summons the window on the narrow monitor" ok devtools open
expect_poll "the window is shown on the narrow monitor" shown window_shown
expect_poll "the other mise tool's actions move under its name on a narrow monitor" under actions_place github:acme/extra Update
expect "the narrow window switches to Info for the VGS Details row" '[' select_devtools_tab Info
# The same error clips here. Details must expose a copyable line.
expect_poll "the narrow VGS row offers Details for its clipped error" 1 devtools_vgs_button_count Details
expect "the narrow VGS row keeps its detail folded" 0 vgs_code_lines
expect "the narrow window switches to Catalog for planted database rows" '[' select_devtools_tab Catalog
# The narrow header can put Details below the body viewport. Reveal that
# exact row's button, then press in the application window's coordinates.
# Other narrow tool rows can also draw Details. Only VGS owns this click.
devtools_any_button_count() {
  ipc smoke itemTexts window vgs.devtools RowAction | py_reply 'import json,sys; print(sum(1 for row in json.load(sys.stdin) if sys.argv[1] in row))' "$1"
}
devtools_old_button_guard() { [[ $1 == 1 ]] && echo accepted || echo refused; }
devtools_details_global="$(devtools_any_button_count Details)"
expect "control: each planted database row draws its own Details button" "$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$docker_rows")" planted_details
expect "control: the old any-action count refuses the planted Details buttons" refused devtools_old_button_guard "$devtools_details_global"
mv -T -- "$dev_state/docker.saved" "$shim/docker"
expect "the narrow window switches back to Info for VGS Details" '[' select_devtools_tab Info
expect "the VGS ToolRow owns exactly one Details button" 1 devtools_vgs_button_count Details
devtools_details_press() {
  local shown count
  count="$(devtools_vgs_button_count "$1")" || return 1
  [[ $count == 1 ]] || { echo "devtools_details_press: buttons=$count label=$1" >&2; return 1; }
  shown="$(ipc smoke revealScopedText window vgs.devtools ToolRow VGS RowAction "$1")" || return 1
  [[ $shown =~ ^[0-9.]+$ ]] || { echo "devtools_details_press: reveal=$shown label=$1" >&2; return 1; }
  click_scoped_in "window:Dev Tools" window vgs.devtools ToolRow VGS RowAction "$1"
}
devtools_details_press Details || fail "the click on the VGS row's Details failed"
expect_poll "Details expands one copyable error line" 1 vgs_code_lines
expect_poll "the expanded VGS row offers Hide details" 1 devtools_vgs_button_count "Hide details"
devtools_details_press "Hide details" || fail "the click on the VGS row's Hide details failed"
expect_poll "Hide details folds the error line again" 0 vgs_code_lines
expect_poll "the folded narrow VGS row offers Details again" 1 devtools_vgs_button_count Details
expect "the narrow window hides" ok ipc shell hide window vgs.devtools
expect_poll "the narrow window is gone" hidden window_shown
release_mode "the nested compositor restores its monitor's mode" "$narrow_monitor" "$narrow_main_mode"
mon_w="$narrow_saved_w" mon_h="$narrow_saved_h"
expect_poll "the monitor has its width back" "$mon_w" first_width
expect "IPC open summons the window again at its width" ok devtools open
expect_poll "the window is shown again" shown window_shown
expect "the window returns to Catalog after the narrow monitor" '[' select_devtools_tab Catalog
expect_poll "the database rows list again once docker answers" "$(texts MySQL "Not installed" "Not installed" Install)" row_texts MySQL

# A click on Install opens the install TUI with the row's id; the list is
# read again when the run ends, so the key mise now holds shows.
# IPC open lists again and puts the keyboard on the Catalog search, which
# narrows the list to the agent. The run is held live from the click; the
# key mise then holds is planted while it is, once every list the open
# started has ended, so only the run's end can show it.
grep -vxF -- "$agent_key" "$dev_state/installed" >"$dev_state/installed.next" || true
mv -f -- "$dev_state/installed.next" "$dev_state/installed"
catalog_ended() { ipc smoke readInstance service vgs.devtools ended | py_reply 'import json,sys; t=sys.stdin.read().strip(); d=json.loads(t) if t.startswith("{") else {}; print(d.get("catalog", "none"))'; }
catalog_before="$(catalog_ended)"
expect "IPC open summons the window on its search for the install path" ok devtools open
expect_poll "the search holds the keyboard for the install path without an initial ring" '["TextField","Search tools",false,false,true]' ipc smoke focused window vgs.devtools
catalog_moved() { [[ $(catalog_ended) != "$catalog_before" ]] && echo moved || echo waiting; }
expect_poll "the open's list ended before the install path" moved catalog_moved
# A list asked for while one runs runs once more after it (Query.qml), so
# the lists have settled once the last end holds still for a second.
catalog_settled() { local first; first="$(catalog_ended)" || return; sleep 1; [[ $(catalog_ended) == "$first" ]] && echo settled || echo moving; }
expect_poll "the open's lists have settled before the install path" settled catalog_settled
type_keys "$agent_command" || fail "typing the agent's command into the Catalog search failed"
expect "the agent lists absent before the click" "$(texts "$agent_name" "Not installed" "Not installed" Install)" row_texts "$agent_name"
install_before="$(ended_record vgs.devtools/install)"
forget_record
hold_runs
expect "the Dev Tools Tab tour reaches the agent Install again" ok devtools_keyboard_install
expect_poll "the click hands the install TUI the row's id" "$(words vgs.devtools/install tui/install.sh "$agent_id")" recorded_tail
echo "$agent_key" >>"$dev_state/installed"
expect "no list runs before a trigger" "$(texts "$agent_name" "Not installed" "Not installed" Install)" row_texts "$agent_name"
release_runs
expect_poll "the install run's presenter exits" moved ended_record_moved vgs.devtools/install "$install_before"
expect_poll "the install run ended in the core record" moved ended_record_moved vgs.devtools/install "$install_before"
expect_poll "the list read after the run shows the agent installed" "$(texts "$agent_name" 1.0.0 Installed Update Remove Version Pin)" row_texts "$agent_name"
cat >"$shim/mise" <<EOF
#!/usr/bin/env bash
case "\$1" in
  --version) echo "2026.9.9 linux-x64 (stub)" ;;
  ls)
    first=1
    printf '{'
    while IFS= read -r key; do
      [[ -n \$key ]] || continue
      [[ \$first == 1 ]] || printf ','
      first=0
      if [[ \$key == "$agent_key" ]]; then
        printf '"%s":[{"version":"1.0.0","installed":true,"active":true},{"version":"0.9.0","installed":true,"active":false}]' "\$key"
      else
        printf '"%s":[{"version":"1.0.0","installed":true,"active":true}]' "\$key"
      fi
    done <"$dev_state/installed"
    printf '}\n' ;;
  which) printf 'mise ERROR %s is not a mise bin. Perhaps you need to install it first.\n' "\$2" >&2; exit 1 ;;
  outdated) echo '{}' ;;
  *) exit 0 ;;
esac
EOF
chmod 755 "$shim/mise"
expect "refresh after adding an older installed version answers ok" ok devtools refresh
for action in Pin Version "Roll back"; do
  forget_record
  expect "the agent row scrolls into view for $action" revealed reveal_row "$agent_name"
  click_scoped_in "window:Dev Tools" window vgs.devtools ToolRow "$agent_name" RowAction "$action" || fail "the click on $action failed"
  verb="$(python3 -c 'import sys; print({"Pin":"pin","Version":"version","Roll back":"rollback"}[sys.argv[1]])' "$action")"
  verb_before="$(ended_record "vgs.devtools/$verb")"
  expect_poll "$action hands the Dev Tools TUI its argv" "$(words vgs.devtools/$verb tui/devtools.sh "$verb" "$agent_id")" recorded_tail
  expect_poll "$action run ends" moved ended_record_moved "vgs.devtools/$verb" "$verb_before"
done

# The window's switch writes writeLaunchers; the service runs the launcher
# verb it picks, so the agent's launcher is written and then removed.
expect "the window switches to Settings for launchers on" '[' select_devtools_tab Settings
expect "the window scrolls to its switch" scrolled scroll_bottom
click_field_switch "Add tool commands to the terminal" || fail "the click on the launcher switch failed"
expect_poll "turning launchers on writes the agent's launcher" "# vgs.devtools launcher" launcher_state "$agent_command"
expect "the window switches to Settings for launchers off" '[' select_devtools_tab Settings
expect "the window scrolls to its switch again" scrolled scroll_bottom
click_field_switch "Add tool commands to the terminal" || fail "the second click on the launcher switch failed"
expect_poll "turning launchers off removes it" absent launcher_state "$agent_command"

# The VGS section: a plugin's missing requirement, listed once enabling
# the fixture moves the core scan's missing commands, which the service
# follows through the doctor capability with no refresh. The fixture marks
# it optional, so enabling it raises no core requirement notice. Install
# raises the core's notice for it, which Escape closes.
expect "a refresh answers ok" ok devtools refresh
expect "enabling the requirement fixture is allowed" ok ipc shell setPluginEnabled acme.requires true
has_fixture_missing() { ipc smoke doctorMissing service vgs.devtools | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([d.get("acme.requires"), "core" in d]))'; }
expect_poll "the doctor capability reports the fixture's missing command and the core's list" '[["vgs-smoke-devtool"], true]' has_fixture_missing
expect "the window switches to Info for the fixture requirement" '[' select_devtools_tab Info
expect_poll "the VGS section lists the fixture's missing requirement with Install" \
  "$(texts vgs-smoke-devtool "acme.requires · A command no sandbox has, which a package names" Missing Optional Install)" row_texts vgs-smoke-devtool
expect_poll "the requirement's row scrolls into view" revealed reveal_row vgs-smoke-devtool
click_scoped_in "window:Dev Tools" window vgs.devtools ToolRow vgs-smoke-devtool RowAction Install || fail "the click on the requirement's Install failed"
expect_poll "Install raises the core's notice for the fixture's command" '["acme.requires", ["vgs-smoke-devtool"], ["vgs-smoke-devtool"], false]' notice_shown
expect_poll "the notice maps" 1 layer_count vgs:notice
expect_poll "the notice holds the keyboard" true ipc smoke noticeFocused
type_keys -k Escape || fail "sending Escape to the notice failed"
expect_poll "Escape closes the notice" 0 layer_count vgs:notice
# The doctor capability's other owners: the core's commands the scan
# finds, and a disabled or unknown plugin.
scans="$(log_lines 'plugins: scan complete changed=')" || fail "the instance log is unreadable before the core request"
expect "the doctor capability takes a core command and scans first" ok ipc smoke doctorOffer service vgs.devtools core git
expect_log "the request's scan ends" "$((scans + 1))" 'plugins: scan complete changed='
expect "a core command the scan finds raises no notice" 0 layer_count vgs:notice
expect "the doctor capability refuses a command the core does not declare" "refused: requirement=vgs-smoke-nope reason=undeclared" ipc smoke doctorOffer service vgs.devtools core vgs-smoke-nope
expect "the doctor capability refuses a disabled plugin" "refused: owner=acme.status reason=disabled" ipc smoke doctorOffer service vgs.devtools acme.status token
expect "the doctor capability refuses an unknown owner" "refused: owner=acme.gone reason=unknown" ipc smoke doctorOffer service vgs.devtools acme.gone x

# Settings reads the status rows back, read-only.
installed_count() { in_shell_env node "$repo/shell/plugins/vgs.devtools/bin/devtools" --tree "$repo" list --json | py_reply 'import json,sys; d=json.load(sys.stdin); print(sum(1 for rows in d["sections"].values() for r in rows if r["installed"] is True) + sum(1 for r in d["other"] if r["installed"] is True))'; }
missing_count() { in_shell_env "$repo/bin/vgshell" doctor --json | py_reply 'import json,sys; d=json.load(sys.stdin); print(sum(1 for rows in [d["core"]] + list(d["plugins"].values()) for r in rows if r["state"] == "missing"))'; }
expect "Settings opens the Dev Tools page" ok ipc vgs.settings invoke open '{"plugin":"vgs.devtools"}'
expect_poll "the Settings window shows the Dev Tools page" '"vgs.devtools"' ipc smoke readInstance window vgs.settings page
settings_details
# The sandbox's tree is no install VGS knows, so the self-status the
# service reads reports its method unknown, and Checks reports a failure.
checks_text="Checks failed"
if dev_installed="$(installed_count)" && dev_missing="$(missing_count)"; then
  expect_poll "the manager row carries the published status" \
    "$(python3 -c 'import json,sys; print(json.dumps([["Tool manager", "reported", {"tone": "ok", "text": "2026.9.9"}, "success"], ["Checks", "reported", {"tone": "warning", "text": sys.argv[3]}, "warning"], ["Tools installed", "reported", int(sys.argv[1]), ""], ["Tool updates", "reported", 0, ""], ["Missing tools", "reported", int(sys.argv[2]), ""]]))' "$dev_installed" "$dev_missing" "$checks_text")" status_of vgs.devtools
  expect_poll "the page draws each status row, the catalog data not" \
    "$(python3 -c 'import json,sys; print(json.dumps([["Tool manager", "2026.9.9", "mise manages the developer tools"], ["Checks", sys.argv[3], "Open Dev Tools again after 10 minutes to retry all checks."], ["Tools installed", sys.argv[1]], ["Tool updates", "0"], ["Missing tools", sys.argv[2], "Install these tools from the VGS section in Dev Tools"]]))' "$dev_installed" "$dev_missing" "$checks_text")" drawn_status
  expect "no Dev Tools status row takes an edit" '[[],[],[],[],[]]' ipc smoke statusRowInputs window vgs.settings
  # Install mise, D061: the entry declares the action, which a present
  # mise does not call for, so the page draws no button and the manager
  # refuses the act, the control. The absent case's button is the shared
  # install action rows/settings.sh presses on the status fixture.
  expect_poll "a present mise offers no Install mise" '[["mise", "Install mise", false]]' offered_actions vgs.devtools
  expected_errors+=('settings: vgs\.devtools/mise refused: action=mise reason=not-offered')
  expect "the manager refuses Install mise while mise is present" "refused: action=mise reason=not-offered" settings_act vgs.devtools mise
  expect "the refused act raised no notice" null notice_shown
else
  fail "the list or the doctor report is unreadable for the status counts"
fi
expect "the Settings window is hidden after its rows" ok ipc shell hide window vgs.settings
expect_poll "the Settings window is gone after its rows" 0 window_count Plugins

# Control: a copy whose launcher rows ignore showInLauncher keeps the
# category visible after the setting is turned off.
control_dir="$home/.config/vgshell/plugins/vgs.devtools"
cp -R "$repo/shell/plugins/vgs.devtools" "$control_dir"
launcher_line='values.launcherRows = ViewLogic.launcherRows(answers.catalog === undefined ? null : answers.catalog.value, showInLauncher, values.catalog);'
if [[ $(grep -c -F -- "$launcher_line" "$control_dir/Service.qml") == 1 ]]; then
  python3 -c 'import sys; p, old = sys.argv[1:]; text = open(p).read(); open(p, "w").write(text.replace(old, old.replace("showInLauncher", "true")))' "$control_dir/Service.qml" "$launcher_line"
  expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: .*vgs\.devtools')
  rescan "rescan after adding the launcher visibility control copy answers ok"
  expect_poll "the launcher visibility control service publishes" '["catalog", "checks", "installed", "launcherRows", "mise", "missingRequirements", "outdated"]' dev_lent
  expect "the control window opens" ok devtools open
  expect "the control window switches to Settings" '[' select_devtools_tab Settings
  click_field_switch "Show full catalog in launcher" || fail "the control click on showInLauncher failed"
  expect "the launcher opens under the launcher visibility control" ok launcher summon '{}'
  launcher_focused
  type_keys -M ctrl -k b -m ctrl || fail "showing launcher categories under the control failed"
  expect_poll "control: launcherRows ignoring showInLauncher keeps the category" True launcher_has_row menu "Dev Tools"
  expect "the launcher hides after the visibility control" ok ipc shell hide overlay vgs.launcher
  expect "the control window hides" ok ipc shell hide window vgs.devtools
  rm -rf -- "${control_dir:?}"
  rescan "rescan after removing the launcher visibility control copy answers ok"
else
  fail "the launcher visibility control line occurs once in the Dev Tools service"
fi

# Control: a copy whose rows focus on a change of targetRow instead of on
# each summon. Summoned twice for the language row with Tab between, the
# keyboard stays where Tab moved it.
control_dir="$home/.config/vgshell/plugins/vgs.devtools"
cp -R "$repo/shell/plugins/vgs.devtools" "$control_dir"
summon_line='                                    function onSummoned() { toolRow.focusIfTarget(); }'
if [[ $(grep -c -F -- "$summon_line" "$control_dir/Window.qml") == 1 ]]; then
  python3 -c 'import sys; p, old = sys.argv[1:]; text = open(p).read(); open(p, "w").write(text.replace(old, old.replace("onSummoned", "onTargetRowChanged")))' "$control_dir/Window.qml" "$summon_line"
  expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: .*vgs\.devtools')
  rescan "rescan after adding the summon focus control copy answers ok"
  expect_poll "the summon focus control service publishes" '["catalog", "checks", "installed", "launcherRows", "mise", "missingRequirements", "outdated"]' dev_lent
  expect "the summon focus control's first summon answers ok" ok ipc shell summon window vgs.devtools "$language_payload"
  expect_poll "the summon focus control's first summon focuses the language row" "row envs/$language_id" language_focus_place
  type_keys -k Tab || fail "Tab off the language row under the summon focus control failed"
  expect_poll "Tab moves the keyboard off the language row under the summon focus control" "moved envs/$language_id" language_focus_place
  expect "the summon focus control's second summon answers ok" ok ipc shell summon window vgs.devtools "$language_payload"
  # The summon ran open() before it answered, and a row's focus waits for
  # one Qt.callLater, which runs once the engine returns to its event loop,
  # before that loop takes the next IPC call.
  expect "control: rows focused on a targetRow change leave a second summon unfocused" "moved envs/$language_id" language_focus_place
  expect "the summon focus control window hides" ok ipc shell hide window vgs.devtools
  rm -rf -- "${control_dir:?}"
  rescan "rescan after removing the summon focus control copy answers ok"
else
  fail "the summon focus line occurs once in the Dev Tools window"
fi

# Control: a copy of the plugin whose service ignores a run's end, in the
# user directory, where it hides the shipped one. A run of its install TUI
# ends and the list stays as it was.
control_dir="$home/.config/vgshell/plugins/vgs.devtools"
cp -R "$repo/shell/plugins/vgs.devtools" "$control_dir"
relist_line='        if (finished.length > 0) trigger("tui");'
scan_line='        trigger("scan");'
if [[ $(grep -c -F -- "$relist_line" "$control_dir/Service.qml") == 1 && $(grep -c -F -- "$scan_line" "$control_dir/Service.qml") == 1 ]]; then
  python3 -c 'import sys; p, a, b = sys.argv[1:]; text = open(p).read(); marker = "    id: root\n"; assert text.count(marker) == 1, "root id must occur once"; text = text.replace(marker, marker + "    property int smokeControlTriggers: 0\n", 1); open(p, "w").write(text.replace(a, "        if (finished.length > 0) smokeControlTriggers += 1;").replace(b, "        smokeControlTriggers += 1;"))' "$control_dir/Service.qml" "$relist_line" "$scan_line"
  expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: .*vgs\.devtools')
  # The scan has landed when rescan returns; its log line says whether it
  # replaced the plugin set, which the landing does not.
  scans="$(log_lines 'plugins: scan complete changed=true')" || fail "the instance log is unreadable before the control copy"
  rescan "rescan after adding the control copy answers ok"
  expect_log "the rescan publishes the control copy" "$((scans + 1))" 'plugins: scan complete changed=true'
  expect_poll "the control copy's service publishes" '["catalog", "checks", "installed", "launcherRows", "mise", "missingRequirements", "outdated"]' dev_lent
  devtools_control_trigger_after() { local now; now="$(ipc smoke readInstance service vgs.devtools smokeControlTriggers)" || return; [[ $now =~ ^[0-9]+$ && $now -gt $1 ]] && echo fired || echo "$now"; }
  grep -vxF -- "$agent_key" "$dev_state/installed" >"$dev_state/installed.next" || true
  mv -f -- "$dev_state/installed.next" "$dev_state/installed"
  expect "the control's summon answers ok" ok devtools open
  expect_poll "a refresh lists the agent absent again" "$(texts "$agent_name" "Not installed" "Not installed" Install)" row_texts "$agent_name"
  echo "$agent_key" >>"$dev_state/installed"
  install_before="$(ended_record vgs.devtools/install)"
  expect_poll "the control's agent row scrolls into view" revealed reveal_row "$agent_name"
  forget_record
  control_trigger_before="$(ipc smoke readInstance service vgs.devtools smokeControlTriggers)" || fail "the control's trigger marker is readable before the install run"
  click_scoped_in "window:Dev Tools" window vgs.devtools ToolRow "$agent_name" RowAction Install || fail "the control's click on Install failed"
  expect_poll "the control's click hands the install TUI the row's id" "$(words vgs.devtools/install tui/install.sh "$agent_id")" recorded_tail
  expect_poll "the control's install run's presenter exits" moved ended_record_moved vgs.devtools/install "$install_before"
  expect_run_end "the control's install run ends" vgs.devtools/install
  expect_poll "the control copy observed the ended install run" fired devtools_control_trigger_after "$control_trigger_before"
  expect "the control copy leaves the list as it was after the run" "$(texts "$agent_name" "Not installed" "Not installed" Install)" row_texts "$agent_name"
  control_trigger_before="$(ipc smoke readInstance service vgs.devtools smokeControlTriggers)" || fail "the control's trigger marker is readable before the scan change"
  expect "disabling the requirement fixture under the control copy is allowed" ok ipc shell setPluginEnabled acme.requires false
  expect_poll "the doctor capability drops the disabled fixture" '[null, true]' has_fixture_missing
  expect_poll "the control copy observed the scan change" fired devtools_control_trigger_after "$control_trigger_before"
  expect "the control copy keeps the disabled fixture's requirement" "$(texts vgs-smoke-devtool "acme.requires · A command no sandbox has, which a package names" Missing Optional Install)" row_texts vgs-smoke-devtool
  rm -rf -- "$control_dir"
  rescan "rescan after removing the control copy answers ok"
else
  fail "the control's lines occur once each in the Dev Tools service"
fi

expect "hiding the window answers ok" ok ipc shell hide window vgs.devtools
expect "disabling Dev Tools is allowed" ok ipc shell setPluginEnabled vgs.devtools false
expect "disabling Launcher after Dev Tools rows is allowed" ok ipc shell setPluginEnabled vgs.launcher false
expect_poll "a disabled Dev Tools holds no status record" null dev_lent
expect "disabling the requirement fixture is allowed" ok ipc shell setPluginEnabled acme.requires false
rm -f -- "$shim/mise" "$shim/docker" "$shim/podman" "$shim/pacman"
