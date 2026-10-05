# The theme capability, driven through the fixture service and read back
# from what its callbacks received, from its `shell.theme` members, from
# Theme itself and from the core's lending record. rows/theme.sh ends at
# the defaults; the first apply is the vgs package all the same.
# `done` can run before ThemeSource reloads the file, so `current` and
# `revision` are polled after it. A later block installs a copy of the
# catalog's flexoki-light, a light package, applies it and reads one colour
# of each gallery section back as a property, then applies vgs so later
# rows start from the defaults. The vgs.themes
# block and its wallpaper block close the file, each delimited by its own
# markers.
# inputs: shell/plugins/vgs.themes/* shell/plugins/vgs.settings/* shell/Commons/Reply.js shell/plugins/vgs.gallery/* scripts/smoke/fixtures/plugins/acme.probe/* shell/Core/ThemeRunner.qml shell/Commons/Theme.qml shell/Commons/ThemeSource.qml bin/vgshell bin/vgshell-theme-judge bin/lib/theme-* themes/* shell/Commons/ThemeLogic.js shell/Commons/Tokens.js bin/lib/qml-library.js scripts/smoke/rows/theme.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh scripts/smoke/rows/hyprland-consent.sh bin/vgshell-tui shell/Hosts/BarHost.qml
set -euo pipefail
installed="$home/.config/vgshell/themes"
# What the fixture's last apply callback received: state, shell, theme and
# reason, a null reason printed as None.
applied() { read_service themeApplied | py_reply 'import json,sys; r=json.loads(json.load(sys.stdin)); print(r["state"], r["shell"], r["theme"], r["reason"])'; }
# The [name, state, reason] rows of that result's targets whose name starts
# with PREFIX.
applied_targets() { read_service themeApplied | py_reply 'import json,sys; r=json.loads(json.load(sys.stdin)); print(json.dumps([[t["name"], t["state"], t["reason"]] for t in r["targets"] if t["name"].startswith(sys.argv[1])]))' "$1"; }
# What the fixture's last list callback received: `packages` as
# [name, source, state, reason] rows, `current` the rows marked current,
# `file` its state, name and modified flag, `reason` the list's own.
listed() {
  read_service themeListed | py_reply '
import json, sys
r = json.loads(json.load(sys.stdin))
part = sys.argv[1]
if part == "packages": print(json.dumps(sorted([p["name"], p["source"], p["state"], p["reason"]] for p in r["packages"])))
elif part == "current": print(json.dumps(sorted(p["name"] for p in r["packages"] if p["current"])))
elif part == "file": print(r["file"]["state"], r["file"]["name"], r["file"]["modified"])
else: print(r["reason"])' "$1"
}
applies() { read_service themeApplies; }
lists() { read_service themeLists; }
theme_member() { probe theme "$1"; }
last_part() { probe theme last | py_reply 'import json,sys; v=json.load(sys.stdin)
for k in sys.argv[1].split("."): v=v.get(k) if isinstance(v, dict) else None
print(json.dumps(v))' "$1"; }
swatch_accent() { probe theme "swatch=$1" | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["accent"]))'; }
revision_rose() { local now; now="$(theme_member revision)" && [[ $now -gt $revision_before ]] && echo rose || echo same; }
# The sandbox copy's vgshell runs BODY for a theme command and the real
# runner for everything else, so the rows' own ipc calls keep working.
cp -p -- "$repo/bin/vgshell" "$repo/bin/vgshell.real"
stand_in_vgshell() {
  printf '#!/usr/bin/env bash\nif [[ ${1:-} == theme ]]; then\n%s\nfi\nexec %q "$@"\n' "$1" "$repo/bin/vgshell.real" >"$repo/bin/vgshell.next" \
    && chmod 755 -- "$repo/bin/vgshell.next" && mv -T -- "$repo/bin/vgshell.next" "$repo/bin/vgshell"
}

# Preserve the fixture placements and plugin enablement for the panel block.
expect_poll "configuration saves settle before the core snapshot" true ipc smoke configSettled
cp -p -- "$home/.config/vgshell/shell.json" "$sandbox/theme-core-shell.json"
restore_theme_core_config() {
  local restore_home="${1:-$home}" restore_sandbox="${2:-$sandbox}"
  expect_poll "queued configuration saves settle before restoration" true ipc smoke configSettled
  cp -p -- "$restore_sandbox/theme-core-shell.json" "$restore_home/.config/vgshell/shell.json.next"
  mv -T -- "$restore_home/.config/vgshell/shell.json.next" "$restore_home/.config/vgshell/shell.json"
  expect "the shell reads the restored configuration" ok ipc shell reloadConfig
  expect_poll "the restored configuration settles" true ipc smoke configSettled
}
# A queued writer overwrites an external restore unless that restore waits.
# Run this row's actual helper against a private file and an IPC stand-in.
restore_config_case() (
  local source="$1" case_root="$sandbox/restore-config-$2"
  mkdir -p -- "$case_root/home/.config/vgshell" "$case_root/sandbox"
  local restore_case_home="$case_root/home" restore_case_sandbox="$case_root/sandbox"
  printf '%s\n' '{"disabledPlugins":[]}' >"$restore_case_sandbox/theme-core-shell.json"
  printf '%s\n' '{"disabledPlugins":["vgs.themes"]}' >"$restore_case_home/.config/vgshell/shell.json"
  touch "$restore_case_sandbox/queued-save"
  ipc() {
    if [[ $* == 'smoke configSettled' || $* == 'shell reloadConfig' ]]; then
      if [[ -e $restore_case_sandbox/queued-save ]]; then
        printf '%s\n' '{"disabledPlugins":["vgs.themes"]}' >"$restore_case_home/.config/vgshell/shell.json"
        rm -- "${restore_case_sandbox:?}/queued-save"
      fi
      if [[ $1 == smoke ]]; then printf 'true\n'; else printf 'ok\n'; fi
      return
    fi
    printf 'restore-config: ipc=unknown call=%s\n' "$*" >&2
    return 1
  }
  eval "$source"
  restore_theme_core_config "$restore_case_home" "$restore_case_sandbox"
  cmp -s -- "$restore_case_sandbox/theme-core-shell.json" "$restore_case_home/.config/vgshell/shell.json"
)
restore_source="$(declare -f restore_theme_core_config)" || return 1
printf '%s\n' "$restore_source" >"$sandbox/restore-config-source.sh"
python3 - "$sandbox/restore-config-source.sh" "$sandbox/restore-config-control.sh" <<'PYCONTROL'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = 'expect_poll "queued configuration saves settle before restoration" true ipc smoke configSettled'
assert source.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, ':'))
PYCONTROL
if restore_config_case "$restore_source" settled; then ok "a settled queued save cannot overwrite the restored configuration"; else fail "the restored configuration was overwritten after settlement"; fi
restore_control="$(cat -- "$sandbox/restore-config-control.sh")" || return 1
if restore_config_case "$restore_control" queued; then fail "control: restoration without settlement survived a queued write"; else ok "control: removing settlement lets a queued write overwrite restoration"; fi
theme_core_previous_error_trap="$(trap -p ERR)"
trap 'restore_theme_core_config' ERR
expect "enabling the fixture for the theme rows is allowed" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the fixture service is back for the theme rows" True service_built
expect_poll "the rebuilt fixture has applied nothing" 0 applies

# These core queue and waiter assertions exercise the fixture alone. The
# retained browser service normally refreshes behind theme publications.
expect "the browser service pauses during core queue assertions" ok ipc shell setPluginEnabled vgs.themes false
expect "browser refreshes settle before core queue assertions" idle theme_idle

revision_before="$(theme_member revision)"
expect "the fixture applies the vgs package" ok probe theme-apply vgs
expect_poll "the vgs apply's result reaches the fixture" 1 applies
expect "the vgs apply wrote the shell's file" "applied applied vgs None" applied
expect "the sandbox copy ships no target, so no hook reaches a host application" '[]' applied_targets ""
expect_poll "current follows the vgs apply" '"vgs"' theme_member current
expect_poll "revision rose after the vgs apply" rose revision_rose
expect "last holds the vgs result with no apply running" '"applied"' last_part result.state

mkdir -p -- "$installed/smoke" "$installed/mismatch"
printf '%s\n' '{ "schemaVersion": 1, "name": "smoke", "tokens": { "palette": { "accent": "#12ab34" } } }' >"$installed/smoke/theme.json"
printf '%s\n' '{ "schemaVersion": 1, "name": "other", "tokens": {} }' >"$installed/mismatch/theme.json"
expect "the fixture asks for the list" ok probe theme-list
expect_poll "the list reaches the fixture" 1 lists
expect "the list names every package with its source and state" '[["mismatch", "installed", "refused", "name-mismatch"], ["smoke", "installed", "ok", null], ["vgs", "shipped", "ok", null]]' listed packages
expect "the list marks the vgs package current" '["vgs"]' listed current
expect "the list reads the file loaded and unmodified" "loaded vgs False" listed file
expect "modified follows the last list" false theme_member modified
expect "fileState follows the shell's file" '"loaded"' theme_member fileState
expect "a swatch is the package's palette, alpha first" '"#ff12ab34"' swatch_accent smoke
expect "a refused package has no swatch" null theme_member swatch=mismatch
expect "an unknown package has no swatch" null theme_member swatch=nosuch

revision_before="$(theme_member revision)"
expect "the fixture applies an installed package" ok probe theme-apply smoke
expect_poll "the installed package's result reaches the fixture" 2 applies
expect "the installed package's apply wrote the shell's file" "applied applied smoke None" applied
expect_poll "current follows the installed package" '"smoke"' theme_member current
expect_poll "revision rose after the installed package's apply" rose revision_rose
expect "the shell draws the installed package's accent" '"#ff12ab34"' ipc smoke themeValue palette.accent
expect "applying the same package again is accepted" ok probe theme-apply smoke
expect_poll "the repeat apply's result reaches the fixture" 3 applies
expect "the repeat apply leaves the file unchanged" "unchanged unchanged smoke None" applied
# The runner refuses an unknown package with exit 1 and its JSON result.
expect "an unknown package's apply is accepted" ok probe theme-apply nosuch
expect_poll "the unknown package's result reaches the fixture" 4 applies
expect "the refusal's output is the result, not discarded" "failed unchanged nosuch unknown" applied
expect "a malformed name is refused at once" 'refused: theme="../x" reason=malformed-name' probe theme-apply ../x
expect "a malformed name queues nothing" '[]' theme_jobs

# A real partial apply: two fixture targets in the sandbox copy, which ships
# no target of its own, always detected, one naming no token. The shell takes the
# theme, the other target lands, and the result and its exit 3 reach the
# fixture whole.
fixture_targets="$repo/themes/targets"
fixture_target() { # NAME TEMPLATE_TEXT [RUNS_CODE]
  mkdir -p -- "$fixture_targets/$1"
  printf '{ "app": "%s", "runsCode": %s, "encoder": "hex8", "files": [{ "template": "%s.conf", "destination": "%s.conf" }], "detect": [], "wiring": { "file": "%s/%s.conf", "line": "include=@{state}/%s.conf", "create": true }, "reload": null }\n' "$1" "${3:-false}" "$1" "$1" "$1" "$1" "$1" >"$fixture_targets/$1/target.json"
  printf '%s\n' "$2" >"$fixture_targets/$1/$1.conf"
}
fixture_target smoke-fails 'accent=@{palette.nope}'
fixture_target smoke-lands 'accent=@{palette.accent}'
expect "an apply a fixture target fails in is accepted" ok probe theme-apply vgs
expect_poll "the partial result reaches the fixture" 5 applies
expect "the shell takes the theme in a partial apply" "partial applied vgs None" applied
expect "the partial result names each fixture target's state" '[["smoke-fails", "failed", "placeholder"], ["smoke-lands", "written", null]]' applied_targets smoke-
expect "last holds the partial result" '"partial"' last_part result.state
expect "the landed fixture target's file is rendered into the state directory" "accent=ff5a36ff" cat "$home/.local/state/vgshell/theme/smoke-lands.conf"
expect "the landed fixture target's include line is wired" "include=$home/.local/state/vgshell/theme/smoke-lands.conf" cat "$home/.config/smoke-lands/smoke-lands.conf"
rm -r -- "$fixture_targets/smoke-fails" "$fixture_targets/smoke-lands"

write_theme '{ "schemaVersion": 1, "name": "smoke", "tokens": { "palette": { "accent": "#12ab35" } } }'
expect_poll "the shell takes a hand edit" '"#ff12ab35"' ipc smoke themeValue palette.accent
expect "the fixture lists after the hand edit" ok probe theme-list
expect_poll "the second list reaches the fixture" 2 lists
expect "a hand edit is modified" true theme_member modified
write_theme '{ nope'
expect_poll "fileState follows a refused edit" '"refused"' theme_member fileState
expect "a refused edit keeps current" '"smoke"' theme_member current

# The gate holds a theme command until the row creates it, polling every
# 50 ms for at most 10 s, so the apply is still running while the row
# reads it, and the instance that asked is destroyed under it.
gate="$sandbox/theme-gate"
stand_in_vgshell "for _ in \$(seq 1 200); do [[ -e $(printf %q "$gate") ]] && break; sleep 0.05; done"
expect "an apply starts behind the gate" ok probe theme-apply vgs
expect "a second apply while one runs is refused at once" "refused: theme=smoke reason=busy" probe theme-apply smoke
expect "a list asked for during the apply is accepted" ok probe theme-list
expect "last names the running apply" '"vgs"' last_part applying
expect "the lending record holds both jobs with the fixture waiting on each" '[["apply", "vgs", 1], ["list", null, 1]]' theme_jobs
expect "disabling the fixture during the apply is allowed" ok ipc shell setPluginEnabled acme.probe false
expect_poll "the destroyed instance's callbacks are dropped" '[["apply", "vgs", 0], ["list", null, 0]]' theme_jobs
touch -- "$gate"
expect_poll "the apply and the list complete without their instance" '[]' theme_jobs
expect "the core kept the result" '"applied"' lent theme.last.result.state
expect "re-enabling the fixture is allowed" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the fixture service is rebuilt" True service_built
expect_poll "the rebuilt instance reads the result from last" '"applied"' last_part result.state
expect "the result in last names the apply" '"vgs"' last_part result.theme
expect "the rebuilt instance received no callback" 0 applies
expect_poll "current follows the apply that outlived its instance" '"vgs"' theme_member current

expected_errors+=('theme: vgshell theme apply reason=output-unreadable name=smoke exit=2 ' 'theme: vgshell theme list reason=output-unreadable exit=2 ')
stand_in_vgshell 'echo "no result"; exit 2'
expect "an apply whose runner prints no result is accepted" ok probe theme-apply smoke
expect_poll "the unreadable apply reaches the fixture" 1 applies
expect "an apply with no result is a failed shell with its reason" "failed failed smoke output-unreadable" applied
expect "a list whose runner prints no result is accepted" ok probe theme-list
expect_poll "the unreadable list reaches the fixture" 1 lists
expect "a list with no result carries its reason" output-unreadable listed reason
expect "a failed list leaves no modified answer" null theme_member modified
expect "a failed list leaves no swatch" null theme_member swatch=smoke

# A runner that cannot start: the rows reach the shell through qs itself,
# since the sandbox's vgshell is the file that cannot start.
qs_call() { "${shell_env[@]}" qs ipc --pid "$shell_qs_pid" call "$@" 2>>"$sandbox/ipc.log" | tail -n 1; }
expected_errors+=('theme: vgshell theme apply reason=start-failed name=smoke')
chmod 000 -- "$repo/bin/vgshell"
expect "an apply whose runner cannot start is accepted" ok qs_call acme.probe invoke theme-apply smoke
expect_poll "the failed start reaches the fixture" 2 qs_call smoke readInstance service acme.probe themeApplies
chmod 755 -- "$repo/bin/vgshell"
expect "a failed start is a failed shell with its reason" "failed failed smoke start-failed" applied
expect_log "the failed start is logged" 1 'theme: vgshell theme apply reason=start-failed name=smoke'
expect "no job waits after a failed start" '[]' theme_jobs

mv -T -- "$repo/bin/vgshell.real" "$repo/bin/vgshell"
expect "the fixture applies vgs with the real runner again" ok probe theme-apply vgs
expect_poll "the last apply's result reaches the fixture" 3 applies
expect "the vgs package is applied again" "unchanged unchanged vgs None" applied

# The catalog's flexoki-light, a light package installed as a copy of its
# catalog files, restyles every section of the gallery, not the bar alone.
# Each section's example is read back as a property, never a drawn frame,
# and compared with the token the shell's own judge resolves from the
# package file under node, which must differ from the vgs default, so a
# read that always matches fails. vgs is applied after it and the copy is
# removed, so later rows start from the defaults.
# One example per section of the gallery: SECTION TYPE PROPERTY TOKEN.
gallery_colours=(
  "Surfaces Surface color surface.level.base.background"
  "Typography Label color text.display.color"
  "Buttons Button fill button.variant.primary.background"
  "Choices Switch indicator.color toggle.off"
  "Inputs TextField background.color textField.background"
  "Feedback Badge color badge.tone.neutral.background"
  "Lists Divider color divider.color"
)
# The colour ThemeLogic.accept resolves for TOKEN from the package in DIR,
# a directory of the sandbox tree such as themes/vgs, as `#rrggbbaa`.
resolved_token() { # DIR TOKEN
  node -e '
const fs = require("fs"), path = require("path");
const [repo, dir, token] = process.argv.slice(1);
const { load } = require(path.join(repo, "bin", "lib", "qml-library.js"));
const logic = load(path.join(repo, "shell", "Commons", "ThemeLogic.js"));
const { TOKENS } = load(path.join(repo, "shell", "Commons", "Tokens.js"));
const result = logic.accept(TOKENS, fs.readFileSync(path.join(repo, dir, "theme.json"), "utf8"));
if (!result.ok) { process.stderr.write("resolved_token: " + logic.refusalLine(result) + "\n"); process.exit(1); }
let value = result.values;
for (const key of token.split(".")) value = value === undefined ? undefined : value[key];
if (typeof value !== "string") { process.stderr.write("resolved_token: absent token=" + token + "\n"); process.exit(1); }
console.log(value);' "$repo" "$1" "$2"
}
gallery_colour() { ipc smoke galleryColour window vgs.gallery "$@"; }
# A copy of the catalog's flexoki-light package in DIR/NAME, NAME being
# flexoki-light unless given. Another NAME is written into theme.json's
# name field, since the judge refuses a package whose name is not its
# folder's.
plant_flexoki_light() { # DIR [NAME]
  local name="${2:-flexoki-light}" source="$repo/themes/catalog/flexoki-light"
  mkdir -p -- "$1/$name" && cp -- "$source/theme.json" "$source/terminal.json" "$1/$name/" || return
  if [[ $name != flexoki-light ]]; then
    python3 -c '
import json, sys
path, name = sys.argv[1:]
with open(path) as f: data = json.load(f)
if data.get("name") != "flexoki-light": sys.exit("plant_flexoki_light: name=%r path=%s\nthe copied theme.json does not carry the name flexoki-light" % (data.get("name"), path))
data["name"] = name
with open(path, "w") as f: json.dump(data, f, indent=2); f.write("\n")
with open(path) as f:
    if json.load(f).get("name") != name: sys.exit("plant_flexoki_light: rename-failed path=%s\nthe name field was not rewritten to %s" % (path, name))
' "$1/$name/theme.json" "$name"
  fi
}

plant_flexoki_light "$installed" || fail "the flexoki-light copy could not be installed"
revision_before="$(theme_member revision)"
expect "the fixture applies the light package" ok probe theme-apply flexoki-light
expect_poll "the light apply's result reaches the fixture" 4 applies
expect "the light apply wrote the shell's file" "applied applied flexoki-light None" applied
expect_poll "current follows the light apply" '"flexoki-light"' theme_member current
expect_poll "revision rose after the light apply" rose revision_rose
expect "the gallery summons under the light package" ok ipc shell summon window vgs.gallery '{}'
expect_poll "the light gallery maps one window" 1 window_count "VGS Components"
for row in "${gallery_colours[@]}"; do
  read -r section type property token <<<"$row"
  if ! light="$(resolved_token themes/catalog/flexoki-light "$token")" || ! default="$(resolved_token themes/vgs "$token")"; then
    fail "the judge resolves $token for the light and vgs packages"
    continue
  fi
  if [[ $light == "$default" ]]; then fail "the light package's $token differs from vgs: both $light"; else ok "the light package's $token differs from vgs"; fi
  expect_poll "the gallery's $section example draws the light package's $token" "$light" gallery_colour "$section" "$type" "$property"
done
expect "hiding the light gallery is allowed" ok ipc shell hide window vgs.gallery
expect_poll "the light gallery's window is gone" 0 window_count "VGS Components"

revision_before="$(theme_member revision)"
expect "the fixture applies vgs after the light package" ok probe theme-apply vgs
expect_poll "the vgs apply after the light package reaches the fixture" 5 applies
expect "the vgs apply after the light package wrote the shell's file" "applied applied vgs None" applied
expect_poll "current follows the vgs apply after the light package" '"vgs"' theme_member current
expect_poll "revision rose after the vgs apply after the light package" rose revision_rose
rm -rf -- "${installed:?}/flexoki-light"

# Every scan ends with a follow, which applies the applied package again
# once it changed under an unedited theme file. The installed smoke
# package's accent changes, a rescan re-applies it, and the package's own
# bytes come back with vgs applied after it. The core loads once per
# sandbox, so no ThemeRunner copy without the follow can stand in as a
# control; a shell that never follows fails the accent row.
expect "the fixture applies smoke for the follow rows" ok probe theme-apply smoke
expect "the smoke apply for the follow rows ends" idle theme_idle
cp -- "$installed/smoke/theme.json" "$sandbox/smoke-theme.json"
printf '%s\n' '{ "schemaVersion": 1, "name": "smoke", "tokens": { "palette": { "accent": "#12ab37" } } }' >"$installed/smoke/theme.json"
rescan "a rescan for the follow is accepted"
expect_poll "the follow re-applies the changed package" '"#ff12ab37"' ipc smoke themeValue palette.accent
expect "the follow ends" idle theme_idle
expect "last holds the follow's re-apply" '"reapplied"' last_part result.follow
cp -- "$sandbox/smoke-theme.json" "$installed/smoke/theme.json"
expect "the fixture applies vgs after the follow rows" ok probe theme-apply vgs
expect "the vgs apply after the follow rows ends" idle theme_idle

expect "disabling the fixture after the theme rows is allowed" ok ipc shell setPluginEnabled acme.probe false
restore_theme_core_config
expect_poll "the browser service restores before its panel rows" false ipc smoke readInstance service vgs.themes setupPending
trap - ERR
if [[ -n $theme_core_previous_error_trap ]]; then eval "$theme_core_previous_error_trap"; fi

# ---- vgs.themes: the themes panel ----------------------------------------
# The first-party themes plugin: its shortcut opens an unanchored panel,
# and a click on a row applies that package. The panel is read back
# through what it draws: each
# ThemeRow's visible texts (name, source, badges, then one line per
# problem of the last result) and its swatch colours. An installed copy of
# dawn, a renamed copy of the catalog's flexoki-light under a name no
# catalog lists, shadows a copy the block plants among the sandbox tree's
# shipped packages, beside the installed `smoke` and the
# refused `mismatch` the rows above left. A fixture target that fails gives
# the result a failed target, one that runs code a file the apply dropped
# from `smoke`, and a stand-in runner a target state the panel names
# nowhere. The block leaves vgs applied for the wallpaper block after it,
# which disables the plugin.
theme_rows() { ipc smoke itemTexts panel vgs.themes ThemeRow | py_reply 'import json,sys; print(json.dumps(sorted(json.load(sys.stdin))))'; }
# The rows whose name is NAME, in tree order.
theme_row() { ipc smoke itemTexts panel vgs.themes ThemeRow | py_reply 'import json,sys; print(json.dumps([r for r in json.load(sys.stdin) if r[0]==sys.argv[1]]))' "$1"; }
# The swatch of the one row named NAME whose secondary line is SECONDARY:
# its chip count and whether a chip draws COLOUR, as `#rrggbbaa`.
theme_swatch() {
  local texts colours
  texts="$(ipc smoke itemTexts panel vgs.themes ThemeRow)" && colours="$(ipc smoke itemColours panel vgs.themes ThemeRow Surface)" || return
  python3 -c 'import json,sys; t,c=json.loads(sys.argv[1]),json.loads(sys.argv[2]); m=[c[i] for i,r in enumerate(t) if r[:2]==sys.argv[3:5]]; print(json.dumps([len(m[0]), sys.argv[5] in m[0]]) if len(m)==1 else "rows=%d" % len(m))' "$texts" "$colours" "$1" "$2" "$3"
}
# The unanchored layer starts below the reserved bar. Qt reports an
# item's box inside that layer; add the compositor's layer position.
themes_item_box() {
  local rect layer
  rect="$(ipc smoke windowGeometry panel vgs.themes "$1" "$2")" || return 1
  if [[ $rect == absent ]]; then echo absent; return; fi
  layer="$(surface_box vgs:panel)" || return 1
  python3 -c 'import json,sys; l=json.loads(sys.argv[1]); r=json.loads(sys.argv[2]); print(json.dumps([l[0] + r[0], l[1] + r[1], r[2], r[3]]))' "$layer" "$rect"
}
# Keep point_item's moving-box and hover checks with the layer's position.
# The lookup override stays inside this click and cannot affect later rows.
themes_click_item() {
  (
    control_box() { themes_item_box "$3" "$4"; }
    click_item panel vgs.themes "$@"
  )
}
# click_row NAME: one click_item on the enabled list item NAME, which is
# waited for for up to 5 s while a running apply disables the rows.
click_row() {
  local _
  for _ in $(seq 1 25); do
    [[ $(ipc smoke itemGeometry panel vgs.themes ListItem "$1") != absent ]] && break
    ipc smoke revealText panel vgs.themes ListItem "$1" >/dev/null || true
    sleep 0.2
  done
  ipc smoke revealText panel vgs.themes ListItem "$1" >/dev/null || true
  themes_click_item ListItem "$1"
}
# Whether the panel draws a label reading TEXT: True or False.
panel_label() { ipc smoke itemTexts panel vgs.themes Label | py_reply 'import json,sys; print([sys.argv[1]] in json.load(sys.stdin))' "$1"; }
panel_open() { [[ $(ipc smoke readInstance panel vgs.themes packages) != absent ]] && echo open || echo closed; }
scroll_themes() { ipc smoke scrollTo panel vgs.themes "$1" >/dev/null; }
# click_button TEXT: one click_item on the enabled button TEXT, which is
# waited for for up to 5 s while a running action disables the buttons.
click_button() {
  local _
  for _ in $(seq 1 25); do
    [[ $(ipc smoke itemGeometry panel vgs.themes Button "$1") != absent ]] && break
    sleep 0.2
  done
  themes_click_item Button "$1"
}
# A click the panel does not cover: the lower-left quarter of the screen,
# away from the right section the panel opens under.
click_outside() { click "$((mon_w / 4))" "$((mon_h * 3 / 4))"; }

expect "the themes panel is enabled as first-party" True plugin_enabled vgs.themes
expect "the unanchored themes panel summons" ok ipc shell summon panel vgs.themes '{}'
expect_poll "the unanchored themes panel maps one panel surface" 1 layer_count vgs:panel
expect "hiding the unanchored themes panel is allowed" ok ipc shell hide panel vgs.themes
expect_poll "the unanchored themes panel's surface is gone" 0 layer_count vgs:panel
# A user file can retain the former bar entry. The bar skips it while the
# panel and service stay enabled, and a configuration reload preserves it.
expect_poll "configuration saves settle before the former bar entry" true ipc smoke configSettled
cp -p -- "$home/.config/vgshell/shell.json" "$sandbox/themes-bar-shell.json"
python3 - "$home/.config/vgshell/shell.json" <<'PYENTRY'
import json, os, sys
path = sys.argv[1]
with open(path) as source: doc = json.load(source)
layout = doc["bar"]["layout"]
assert all(entry["id"] != "vgs.themes" for entries in layout.values() for entry in entries)
layout["right"].append({"id": "vgs.themes"})
with open(path + ".next", "w") as output: json.dump(doc, output)
os.replace(path + ".next", path)
PYENTRY
cp -p -- "$home/.config/vgshell/shell.json" "$sandbox/themes-bar-entry.json"
former_themes_entry() { ipc shell listShellConfig | py_reply 'import json,sys; print(any(e["id"] == "vgs.themes" for entries in json.load(sys.stdin)["bar"]["layout"].values() for e in entries))'; }
former_entry_preserved() { cmp -s -- "$sandbox/themes-bar-entry.json" "$home/.config/vgshell/shell.json" && echo same || echo differs; }
widget_absent() { bar_widget_ids | py_reply 'import json,sys; rows=json.load(sys.stdin); print(bool(rows) and all(sys.argv[1] not in ids for ids in rows))' "$1"; }
expect "the shell reads the former themes bar entry" ok ipc shell reloadConfig
expect_poll "the effective configuration retains the former themes bar entry" True former_themes_entry
expect_poll "every bar holds no themes widget with its former entry present" True widget_absent vgs.themes
widget_absence_control() { (failures=0 behaviour_failures=0; expect "the mounted fixture is absent" True widget_absent acme.tick >"$sandbox/themes-widget-absence-control.log"; echo "$failures"); }
expect "control: the no-widget assertion rejects a mounted fixture" 1 widget_absence_control
expect "the themes service stays built with its former bar entry" True record_exists vgs.themes
expect "reloading preserves the user's former themes bar entry" same former_entry_preserved
expect_poll "configuration saves settle before the bar entry restoration" true ipc smoke configSettled
cp -p -- "$sandbox/themes-bar-shell.json" "$home/.config/vgshell/shell.json.next"
mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
expect "the shell reads the restored bar entries" ok ipc shell reloadConfig
expect_poll "the former themes bar entry is removed from the fixture configuration" False former_themes_entry
themes_panel_bind() { hypr -j binds | py_reply 'import json,sys; print(json.dumps([[b["modmask"], b["key"]] for b in json.load(sys.stdin) if b["description"] == "vgs.themes:panel" and b.get("submap", "") in ("", "default")]))'; }
expect_poll "the nested instance binds SUPER+CTRL+J to the themes panel" '[[68, "J"]]' themes_panel_bind
# Every vgs.themes instance a rescan rebuilds with the panel closed: the
# background on every screen, and the service.
themes_instances=$((monitors + 1))

terminal_stand_in
expect_poll "the themes TUI probe is not running" false lent tui.probing
if [[ "$(lent tui.launcher)" == '"missing"' ]]; then
  expect "a setup theme-add open answers launcher-missing" "refused: tui=core/theme-add reason=launcher-missing" ipc shell openTui core/theme-add
fi
expect_poll "the themes TUI launcher is present" '"present"' lent tui.launcher


# Install browser theming, D061: the service publishes what `vgshell theme
# setup` says of the Chromium-family writer. The sandbox tree ships no
# target, so the row reads not shipped until the row copies the chromium
# target in and the service starts again. qml-smoke.sh hides the host's
# writer from every sandbox shell, and the row stands a chromium in the
# shell's own directory that runs nothing, so on any host the Settings page
# then offers Install browser theming, whose button opens the plugin's
# browser-policy TUI. The stand-in terminal runs no plugin script
# (scripts/test-themes-browser-policy-tui.sh runs this one), and the
# sandbox tree's bin/vgshell-browser-policy stays the harness's sentinel. The
# row holds the run live, reads the argv the press handed the terminal,
# then puts a stand-in writer on the shell's PATH itself, the state the
# run's end reads, and releases the run. The run's end then reads
# Installed and withdraws the button. The control: the manager refuses the
# act while the tree ships no target and once the writer is there. Then
# Settings itself: each open asks for a scan, so a writer that arrives
# with no scan of the row's own reads installed once the window opens
# again, and a Settings copy whose open() asks for none leaves the row
# offering the install. The target leaves the tree before any apply.
browser_theming() { status_row vgs.themes browserTheming | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps([r["report"], r["tone"], r["action"]["offered"]]))'; }
browser_text() { status_row vgs.themes browserTheming | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps(r["value"]["text"] if r["value"] else None))'; }
themes_source_dir() { ipc shell listPlugins | py_reply 'import json,sys; print(next((p["dir"] for p in json.load(sys.stdin)["plugins"] if p["id"] == "vgs.themes"), "absent"))'; }
expected_errors+=('settings: vgs\.themes/browserTheming refused: action=browserTheming reason=not-offered')
settings_page_open vgs.themes
settings_details
expect_poll "a tree that ships no target reads browser theming not shipped" '"This version of VGS does not support browser themes"' browser_text
expect "the manager refuses the install while no target ships" "refused: action=browserTheming reason=not-offered" settings_act vgs.themes browserTheming
printf '#!/bin/sh\nexit 1\n' >"$shim/chromium"
chmod 755 "$shim/chromium"
expect "chromium resolves to the row's stand-in on the shell's PATH" "$shim/chromium" shell_resolves chromium
expect "the browser-policy writer is absent from the shell's PATH" none shell_resolves vgshell-browser-policy
cp -R -- "$source_repo/themes/targets/chromium" "$repo/themes/targets/chromium"
expect "the themes plugin is disabled to read the shipped target" ok ipc shell setPluginEnabled vgs.themes false
expect_poll "the themes service is gone" False record_exists vgs.themes
expect "the themes plugin is enabled again with the target shipped" ok ipc shell setPluginEnabled vgs.themes true
expect_poll "the themes service is built again" True record_exists vgs.themes
# Each change of the plugin set queues a scan and a follow, which holds the
# theme lock; the rows below apply only once it ends.
expect "the follow after the themes restart ends" idle theme_idle
expect_poll "the service reads the shipped target's setup" '"Browser themes are not installed"' browser_text
first_setup="$(browser_theming)" || first_setup=unreadable
case $first_setup in
  '["reported", "warning", true]')
    forget_record
    hold_runs
    settings_press "Install browser theming" || fail "the click on Install browser theming failed"
    expect_poll "Install browser theming hands the terminal the browser-policy TUI" "$(words vgs.themes/browser-policy tui/browser-policy.sh)" recorded_tail
    expect_poll "the browser-policy run is live under the hold" busy key_idle vgs.themes/browser-policy
    printf '#!/bin/sh\nexit 0\n' >"$shim/vgshell-browser-policy"
    chmod 755 "$shim/vgshell-browser-policy"
    expect "the writer resolves to the row's stand-in on the shell's PATH" "$shim/vgshell-browser-policy" shell_resolves vgshell-browser-policy
    release_runs
    expect_run_end "the browser-policy run ends" vgs.themes/browser-policy
    expect_poll "the run's end asks again: the writer reads installed, offering nothing" '["reported", "success", false]' browser_theming
    forget_record
    expect "the manager refuses the install once the writer is there" "refused: action=browserTheming reason=not-offered" settings_act vgs.themes browserTheming
    expect "the refused install started no terminal" absent recorded
    unlink -- "${shim:?}/vgshell-browser-policy"
    rescan "a browser theming rescan after the writer goes away is accepted"
    expect_poll "the requirements revision makes browser theming read missing again" '["reported", "warning", true]' browser_theming
    expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.themes')
    mutant="$home/.config/vgshell/plugins/vgs.themes"
    mkdir -p -- "$(dirname -- "$mutant")"
    cp -R -- "$repo/shell/plugins/vgs.themes" "$mutant"
    service_qml="$mutant/Service.qml"
    cp -- "$service_qml" "$sandbox/vgs.themes-Service.qml.orig"
    if python3 - "$service_qml" <<'PY'
import sys
path = sys.argv[1]
old = "    onRequirementsRevisionChanged: if (registeredWith !== null) checkSetup()\n"
text = open(path).read()
if text.count(old) != 1:
    sys.exit("requirements revision handler occurs %d times" % text.count(old))
open(path, "w").write(text.replace(old, "    onRequirementsRevisionChanged: if (false) checkSetup()\n"))
PY
    then ok "the browser rescan control drops the requirements revision handler"; else fail "the browser rescan control could not drop the requirements revision handler"; fi
    # The scan has landed when rescan returns; its log line says whether it
    # replaced the plugin set, which the landing does not.
    scans="$(log_lines 'plugins: scan complete changed=true')" || fail "the instance log is unreadable before the mutant themes copy"
    rescan "the mutant themes plugin rescan is accepted"
    expect_log "the mutant themes copy is published" "$((scans + 1))" 'plugins: scan complete changed=true'
    expect_poll "the mutant themes copy is the discovered source" "$mutant" themes_source_dir
    expect_poll "the mutant themes service reads the missing writer at build" '["reported", "warning", true]' browser_theming
    printf '#!/bin/sh\nexit 0\n' >"$shim/vgshell-browser-policy"
    chmod 755 "$shim/vgshell-browser-policy"
    expect "the control writer resolves on the shell's PATH" "$shim/vgshell-browser-policy" shell_resolves vgshell-browser-policy
    scans="$(log_lines 'plugins: scan complete changed=false')" || fail "the instance log is unreadable before the control rescan"
    rescan "the control rescan is accepted"
    expect_log "the control rescan ends without a rebuild" "$((scans + 1))" 'plugins: scan complete changed=false'
    expect "control: without requirements revision the browser row stays stale" '["reported", "warning", true]' browser_theming
    rm -rf -- "$mutant"
    scans="$(log_lines 'plugins: scan complete changed=true')" || fail "the instance log is unreadable before the bundled themes restore"
    rescan "the real themes plugin rescan is accepted"
    expect_log "the bundled themes plugin is published" "$((scans + 1))" 'plugins: scan complete changed=true'
    expect_poll "the real requirements revision reads the installed writer" '["reported", "success", false]' browser_theming
    unlink -- "${shim:?}/vgshell-browser-policy"
    scans="$(log_lines 'plugins: scan complete changed=false')" || fail "the instance log is unreadable before the positive requirements rescan"
    rescan "the positive requirements revision rescan is accepted"
    expect_log "the positive requirements revision rescan ends without a rebuild" "$((scans + 1))" 'plugins: scan complete changed=false'
    expect_poll "the bundled themes service reads the missing writer after a rescan" '["reported", "warning", true]' browser_theming
    settings_source_dir() { ipc shell listPlugins | py_reply 'import json,sys; print(next((p["dir"] for p in json.load(sys.stdin)["plugins"] if p["id"] == "vgs.settings"), "absent"))'; }
    reopen_settings() { # LABEL
      expect "$1: the Settings window is hidden" ok ipc shell hide window vgs.settings
      expect "$1: Settings is summoned on the themes page again" ok ipc shell summon window vgs.settings '{"plugin":"vgs.themes"}'
      expect_poll "$1: the Settings window shows the themes page" '"vgs.themes"' ipc smoke readInstance window vgs.settings page
    }
    printf '#!/bin/sh\nexit 0\n' >"$shim/vgshell-browser-policy"
    chmod 755 "$shim/vgshell-browser-policy"
    expect "the writer for the reopen resolves on the shell's PATH" "$shim/vgshell-browser-policy" shell_resolves vgshell-browser-policy
    expect "before the reopen the row still offers the install" '["reported", "warning", true]' browser_theming
    scans="$(log_lines 'plugins: scan complete')" || fail "the instance log is unreadable before the Settings reopen"
    reopen_settings "the writer's arrival"
    expect_log "reopening Settings starts a scan" "$((scans + 1))" 'plugins: scan complete'
    expect_poll "reopening Settings reads the writer installed, offering nothing" '["reported", "success", false]' browser_theming
    expected_errors+=('plugins: hidden by a higher-precedence plugin with the same id: vgs\.settings')
    settings_mutant="$home/.config/vgshell/plugins/vgs.settings"
    bundled_settings="$(settings_source_dir)" || fail "the bundled Settings source is unreadable"
    mkdir -p -- "$(dirname -- "$settings_mutant")"
    cp -R -- "$repo/shell/plugins/vgs.settings" "$settings_mutant"
    if python3 - "$settings_mutant/Window.qml" <<'PY'
import sys
path = sys.argv[1]
old = "        shell.manager.rescan();\n"
text = open(path).read()
if text.count(old) != 1:
    sys.exit("the open rescan occurs %d times" % text.count(old))
open(path, "w").write(text.replace(old, "        if (false) shell.manager.rescan();\n"))
PY
    then ok "the Settings reopen control drops the open rescan"; else fail "the Settings reopen control could not drop the open rescan"; fi
    scans="$(log_lines 'plugins: scan complete changed=true')" || fail "the instance log is unreadable before the mutant Settings copy"
    rescan "the mutant Settings rescan is accepted"
    expect_log "the mutant Settings copy is published" "$((scans + 1))" 'plugins: scan complete changed=true'
    expect_poll "the mutant Settings copy is the discovered source" "$settings_mutant" settings_source_dir
    unlink -- "${shim:?}/vgshell-browser-policy"
    scans="$(log_lines 'plugins: scan complete changed=false')" || fail "the instance log is unreadable before the control's missing-writer rescan"
    rescan "the control's missing-writer rescan is accepted"
    expect_log "the control's missing-writer rescan ends" "$((scans + 1))" 'plugins: scan complete changed=false'
    reopen_settings "the control's start"
    expect_poll "the control starts with the install offered" '["reported", "warning", true]' browser_theming
    printf '#!/bin/sh\nexit 0\n' >"$shim/vgshell-browser-policy"
    chmod 755 "$shim/vgshell-browser-policy"
    expect "the control writer for the reopen resolves on the shell's PATH" "$shim/vgshell-browser-policy" shell_resolves vgshell-browser-policy
    scans="$(log_lines 'plugins: scan complete')" || fail "the instance log is unreadable before the control reopen"
    reopen_settings "the control"
    # No line marks a scan not asked for, so the control waits the 5 s
    # window expect_log gives the real reopen's scan, then looks.
    for _ in $(seq 1 25); do
      now="$(log_lines 'plugins: scan complete')" || { fail "the instance log is unreadable after the control reopen"; break; }
      [[ $now == "$scans" ]] || break
      sleep 0.2
    done
    expect "control: the copy's reopen starts no scan" "$scans" log_lines 'plugins: scan complete'
    expect "control: without the open rescan the row still offers the install" '["reported", "warning", true]' browser_theming
    rm -rf -- "${settings_mutant:?}"
    scans="$(log_lines 'plugins: scan complete changed=true')" || fail "the instance log is unreadable before the bundled Settings restore"
    rescan "the bundled Settings rescan is accepted"
    expect_log "the bundled Settings plugin is published" "$((scans + 1))" 'plugins: scan complete changed=true'
    expect_poll "the bundled Settings is the discovered source again" "$bundled_settings" settings_source_dir
    unlink -- "${shim:?}/vgshell-browser-policy"
    scans="$(log_lines 'plugins: scan complete changed=false')" || fail "the instance log is unreadable before the last missing-writer rescan"
    rescan "the last missing-writer rescan is accepted"
    expect_log "the last missing-writer rescan ends" "$((scans + 1))" 'plugins: scan complete changed=false'
    reopen_settings "the bundled Settings"
    expect_poll "the bundled Settings reads the missing writer" '["reported", "warning", true]' browser_theming
    ;;
  *)
    fail "the browser theming row reads $first_setup, so Install browser theming was not pressed"
    ;;
esac
unlink -- "${shim:?}/chromium"
rm -r -- "${repo:?}/themes/targets/chromium"
settings_page_close vgs.themes

# ---- vgs.themes panel keyboard-only path ----------------------------------
expect "the themes panel opens from its global shortcut" ok hypr dispatch 'hl.dsp.global("vgs.themes:panel")'
expect_poll "the shortcut opens the themes panel" open panel_open
expect_poll "the panel list takes the keyboard" true ipc smoke activeFocusIn panel vgs.themes
expect_poll "the panel starts on the displayed row" '"installed:shipped/vgs"' ipc smoke readInstance panel vgs.themes currentKey
type_keys -k Up || fail "sending Up in the themes panel failed"
expect_poll "Up moves the theme panel cursor to smoke" '"installed:installed/smoke"' ipc smoke readInstance panel vgs.themes currentKey
expect_poll "the displayed badge stays on vgs while the cursor moves" '[["vgs", "shipped", "Displayed"]]' theme_row vgs
type_keys -k Space || fail "sending Space on the selected theme row failed"
expect_poll "Space applies the selected theme row" '"smoke"' lent theme.last.result.theme
expect_poll "the shell displays the keyboard-applied theme" smoke ipc smoke themeName
type_keys -k Escape || fail "closing the themes panel from the keyboard failed"
expect_poll "Escape closes the keyboard-opened themes panel" closed panel_open
expect "the keyboard-applied theme ends" idle theme_idle
expect "the fixture applies vgs after the panel keyboard path" "ok theme=vgs state=applied shell=applied" "${shell_env[@]}" "$repo/bin/vgshell" theme apply vgs
expect "the vgs apply after the panel keyboard path ends" idle theme_idle

cp -p -- "$repo/bin/vgshell" "$repo/bin/vgshell.real"
catalog_installed="$sandbox/catalog-smoke-installed"
catalog_wallpapers="$sandbox/catalog-smoke-wallpapers"
catalog_wallpapers_gate="$sandbox/catalog-smoke-wallpapers-gate"
catalog_row_installed="$sandbox/catalog-row-smoke-installed"
catalog_installed_state() { [[ -e $catalog_installed ]] && echo installed || echo absent; }
catalog_wallpapers_state() { [[ -e $catalog_wallpapers ]] && echo installed || echo absent; }
catalog_row_installed_state() { [[ -e $catalog_row_installed ]] && echo installed || echo absent; }
wait_catalog_installed() { local _; for _ in $(seq 1 100); do [[ $(catalog_installed_state) == installed ]] && { echo installed; return; }; sleep 0.2; done; catalog_installed_state; }
wait_catalog_wallpapers() { local _; for _ in $(seq 1 100); do [[ $(catalog_wallpapers_state) == installed ]] && { echo installed; return; }; sleep 0.2; done; catalog_wallpapers_state; }
wait_catalog_row_installed() { local _; for _ in $(seq 1 100); do [[ $(catalog_row_installed_state) == installed ]] && { echo installed; return; }; sleep 0.2; done; catalog_row_installed_state; }
stand_in_vgshell "
case \${2:-} in
  catalog)
    installed=false; imagery=false
    row_installed=false
    [[ -e $(printf %q "$catalog_installed") ]] && installed=true
    [[ -e $(printf %q "$catalog_wallpapers") ]] && imagery=true
    [[ -e $(printf %q "$catalog_row_installed") ]] && row_installed=true
    printf '{\"entries\":[{\"name\":\"catalog-row-smoke\",\"mode\":\"light\",\"thumbnail\":null,\"palette\":{\"background\":\"#ffffffff\",\"foreground\":\"#111111ff\",\"accent\":\"#aa55ffff\",\"success\":\"#22aa22ff\",\"warning\":\"#ddaa00ff\",\"danger\":\"#cc2222ff\",\"info\":\"#3399ccff\"},\"imagery\":null,\"installed\":%s,\"imageryInstalled\":false,\"imageryUpdate\":false,\"definitionUpdate\":false},{\"name\":\"catalog-smoke\",\"mode\":\"dark\",\"thumbnail\":null,\"palette\":{\"background\":\"#101010ff\",\"foreground\":\"#eeeeeeff\",\"accent\":\"#3366ffff\",\"success\":\"#22aa22ff\",\"warning\":\"#ddaa00ff\",\"danger\":\"#cc2222ff\",\"info\":\"#3399ccff\"},\"imagery\":{\"repo\":\"https://example.invalid/themes\",\"release\":\"themes\",\"archive\":\"catalog-smoke.tar.gz\",\"size\":12582912,\"sha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"},\"installed\":%s,\"imageryInstalled\":%s,\"imageryUpdate\":false,\"definitionUpdate\":false}]}\n' \"\$row_installed\" \"\$installed\" \"\$imagery\"
    exit 0
    ;;
  install)
    if [[ \${4:-} == catalog-smoke ]]; then
      touch -- $(printf %q "$catalog_installed")
      printf '{\"state\":\"ok\",\"theme\":\"catalog-smoke\",\"path\":\"%s\",\"shadows\":null,\"reason\":null}\n' $(printf %q "$installed/catalog-smoke")
      exit 0
    fi
    if [[ \${4:-} == catalog-row-smoke ]]; then
      touch -- $(printf %q "$catalog_row_installed")
      printf '{\"state\":\"ok\",\"theme\":\"catalog-row-smoke\",\"path\":\"%s\",\"shadows\":null,\"reason\":null}\n' $(printf %q "$installed/catalog-row-smoke")
      exit 0
    fi
    ;;
  apply)
    if [[ \${4:-} == catalog-row-smoke ]]; then
      printf '{\"state\":\"applied\",\"shell\":\"applied\",\"targets\":[],\"theme\":\"catalog-row-smoke\",\"reason\":null}\n'
      exit 0
    fi
    ;;
  wallpapers)
    if [[ \${4:-} == catalog-smoke ]]; then
      printf '{\"state\":\"downloading\",\"bytes\":3000000,\"total\":12582912}\n'
      for _ in \$(seq 1 100); do [[ -e $(printf %q "$catalog_wallpapers_gate") ]] && break; sleep 0.2; done
      touch -- $(printf %q "$catalog_wallpapers")
      printf '{\"state\":\"ok\",\"theme\":\"catalog-smoke\",\"wallpapers\":\"installed\",\"images\":1,\"sha256\":\"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\",\"reason\":null}\n'
      exit 0
    fi
    ;;
esac"
plant_flexoki_light "$repo/themes" dawn || fail "the shipped dawn copy could not be planted"
plant_flexoki_light "$installed" dawn || fail "the installed dawn copy could not be planted"
expect "the shortcut opens the themes panel" ok hypr dispatch 'hl.dsp.global("vgs.themes:panel")'
expect_poll "the shortcut opens the themes panel for its content checks" open panel_open
expect_poll "the panel lists every package with its source and badges" '[["catalog-row-smoke", "light, no wallpapers", "Install"], ["catalog-smoke", "dark, wallpapers 13 MB", "Install"], ["dawn", "installed"], ["dawn", "shipped", "Hidden by another copy"], ["mismatch", "installed, The theme name does not match its folder. Choose another theme.", "Unavailable"], ["smoke", "installed"], ["vgs", "shipped", "Displayed"]]' theme_rows
expect "an accepted package's row draws its palette" '[7, true]' theme_swatch smoke installed '#12ab34ff'
expect "a refused package's row draws no swatch" '[0, false]' theme_swatch mismatch "installed, The theme name does not match its folder. Choose another theme." '#12ab34ff'
expect "a shadowed package's row draws no swatch" '[0, false]' theme_swatch dawn shipped '#12ab34ff'
expect_poll "the panel lists a catalog row with its mode, wallpaper size and install action" '[["catalog-smoke", "dark, wallpapers 13 MB", "Install"]]' theme_row catalog-smoke
expect "the catalog row draws its palette" '[7, true]' theme_swatch catalog-smoke "dark, wallpapers 13 MB" '#3366ffff'
expect_poll "an uninstalled catalog row can install from a row click" '[["catalog-row-smoke", "light, no wallpapers", "Install"]]' theme_row catalog-row-smoke
scroll_themes 10000
click_row catalog-row-smoke || fail "the click on the uninstalled catalog row failed"
expect "the uninstalled catalog row click reaches install" installed wait_catalog_row_installed
expect_poll "the installed catalog row loses its install action" '[["catalog-row-smoke", "light, no wallpapers", "Installed"]]' theme_row catalog-row-smoke
click_row catalog-row-smoke || fail "the click on the installed catalog row failed"
expect_poll "the installed catalog row click applies that package" '"catalog-row-smoke"' lent theme.last.result.theme

panel_qml="$repo/shell/plugins/vgs.themes/ThemesPanel.qml"
cp -p -- "$panel_qml" "$sandbox/ThemesPanel.qml.real"
# panel_source LABEL FILE: close the panel, install FILE as its source,
# rescan, and open the panel the rescan built; false when any step failed.
panel_source() {
  local before
  click_outside || { fail "$1: the click closing the themes panel failed"; return 1; }
  expect_poll "the themes panel closes before $1" closed panel_open
  cp -p -- "$2" "$panel_qml.tmp" && mv -T -- "$panel_qml.tmp" "$panel_qml" || { fail "$1: $2 could not be installed"; return 1; }
  before="$(builds)" || { fail "$1: buildCount unreadable"; return 1; }
  rescan "a rescan builds $1"
  expect_poll "$1 rebuilds every vgs.themes instance" "$((before + themes_instances))" builds
  expect "the follow the rescan for $1 queued ends" idle theme_idle
  expect "$1: the shortcut opens the themes panel" ok hypr dispatch 'hl.dsp.global("vgs.themes:panel")'
  expect_poll "$1 opens" open panel_open
}
step() {
  local message="$1"
  shift
  "$@" || { fail "$message"; return 1; }
}
install_call='const reply = shell.theme.install(name, result => {'
if [[ $(grep -c -F -- "$install_call" "$panel_qml") == 1 ]]; then
  if python3 -c 'import sys; p, q, old = sys.argv[1:]; open(q, "w").write(open(p).read().replace(old, "const reply = \"ok\"; if (false) shell.theme.install(name, result => {"))' "$sandbox/ThemesPanel.qml.real" "$sandbox/ThemesPanel.qml.catalog-mutant" "$install_call"; then
    panel_source "the catalog install control" "$sandbox/ThemesPanel.qml.catalog-mutant" \
      && expect "the catalog install control invokes the install path" ok ipc smoke invokeInstance panel vgs.themes installCatalog catalog-smoke \
      && expect "the catalog install control leaves the catalog uninstalled" absent catalog_installed_state
    panel_source "the restored catalog install action" "$sandbox/ThemesPanel.qml.real" \
      && expect_poll "the restored catalog install action lists the row" '[["catalog-smoke", "dark, wallpapers 13 MB", "Install"]]' theme_row catalog-smoke
  else
    fail "the catalog install control could not be written"
  fi
else
  fail "the catalog install control's text occurs once in $panel_qml"
fi

scroll_themes 10000
click_button "Install" || fail "the click on the catalog Install button failed"
expect "the catalog Install button reaches the theme capability" installed wait_catalog_installed
expect_poll "the panel is open after catalog install" open panel_open
expect_poll "the catalog install changes the row to an installed catalog theme without wallpapers" '[["catalog-smoke", "dark, wallpapers 13 MB", "Installed", "Download wallpapers"]]' theme_row catalog-smoke


scroll_themes 10000
click_button "Download wallpapers" || fail "the click on the catalog Download wallpapers button failed"
expect_poll "the clicked catalog wallpaper download shows the browser progress text" '[["catalog-smoke", "dark, wallpapers 13 MB", "Installed", "Downloading 3 of 13 MB", "Download wallpapers"]]' theme_row catalog-smoke
touch -- "$catalog_wallpapers_gate"
expect "the clicked catalog Download wallpapers button reaches the theme capability" installed wait_catalog_wallpapers
expect_poll "the clicked catalog wallpaper download removes the download action" '[["catalog-smoke", "dark, wallpapers 13 MB", "Installed"]]' theme_row catalog-smoke
rm -f -- "$catalog_wallpapers" "$catalog_wallpapers_gate"
# This stand-in stores imagery outside the watched package directory.
# Notify the service when its synthetic filesystem state changes.
expect "the synthetic wallpaper removal refreshes the retained catalog" '' ipc smoke invokeInstance service vgs.themes refreshData ''
click_outside || fail "the click closing the themes panel after clicked wallpaper download failed"
expect_poll "the themes panel closes after clicked wallpaper download" closed panel_open
expect "the shortcut opens the themes panel" ok hypr dispatch 'hl.dsp.global("vgs.themes:panel")'
expect_poll "the themes panel reopens after removing the clicked wallpaper fixture" open panel_open
expect_poll "the catalog wallpaper row offers Download wallpapers again" '[["catalog-smoke", "dark, wallpapers 13 MB", "Installed", "Download wallpapers"]]' theme_row catalog-smoke
scroll_themes 10000
type_keys "catalog-smoke" || fail "typing to the catalog wallpaper row failed"
expect_poll "type-ahead selects the catalog wallpaper row" '"catalog:catalog-smoke"' ipc smoke readInstance panel vgs.themes currentKey
type_keys -M alt -k d -m alt || fail "sending Alt+D on the catalog wallpaper row failed"
expect_poll "the catalog wallpaper download shows the browser progress text" '[["catalog-smoke", "dark, wallpapers 13 MB", "Installed", "Downloading 3 of 13 MB", "Alt", "D", "Download wallpapers"]]' theme_row catalog-smoke
click_outside || fail "the click closing the themes panel during wallpaper download failed"
expect_poll "the themes panel closes during wallpaper download" closed panel_open
expect "the shortcut opens the themes panel" ok hypr dispatch 'hl.dsp.global("vgs.themes:panel")'
expect_poll "the themes panel reopens during wallpaper download" open panel_open
expect_poll "the reopened panel reads the wallpaper download progress" '[["catalog-smoke", "dark, wallpapers 13 MB", "Installed", "Downloading 3 of 13 MB", "Download wallpapers"]]' theme_row catalog-smoke
touch -- "$catalog_wallpapers_gate"
expect "the catalog Download wallpapers button reaches the theme capability" installed wait_catalog_wallpapers
expect_poll "the panel is open after catalog wallpaper download" open panel_open
expect_poll "the catalog wallpaper download removes the download action" '[["catalog-smoke", "dark, wallpapers 13 MB", "Installed"]]' theme_row catalog-smoke
scroll_themes 0
forget_record
click_button "Add from URL" || fail "the click on Add from URL failed"
expect_poll "Add from URL opens the core theme add TUI" \
  "$(core_words core/theme-add "Add a theme" org.vgs.tui theme add)" recorded
expect_run_end "the theme add core run ends before later rows" core/theme-add
mv -T -- "$repo/bin/vgshell.real" "$repo/bin/vgshell"

fixture_target smoke-fails 'accent=@{palette.nope}'
click_row smoke || fail "the click on the smoke row failed"
expect_poll "a click on a row applies its package" '"smoke"' lent theme.last.result.theme
expect_poll "the shell displays the package the row applied" smoke ipc smoke themeName
expect_poll "the applied row is displayed and shows its failed target" '[["smoke", "installed", "Displayed", "smoke-fails: The theme action failed. Try again or choose another theme."]]' theme_row smoke
# The panel's layout, one finding per broken rule, `[]` the pass: the
# title, each section heading and each row's box start on one content
# edge, as far in from the panel's left side as a row's box ends from its
# right (`edge`); the smoke row's failure line starts at the row's text
# column, where its name is drawn (`column`); and Add from URL lies inside
# the panel, below the scrolling body (`footer`). Each holds within one
# pixel and reads containment, so a theme with a larger font still
# passes. panel_geometry reads the panel and keeps the reading;
# panel_planted RULE judges that kept reading with one box moved, so each
# rule's control requires its own finding on the reading the rule passed
# and reads the panel no second time. One reading of the panel is paged,
# and takes seconds once the panel lists the whole catalog.
panel_kept="$sandbox/themes-panel-reading"
panel_geometry() {
  local width offset reading
  width="$(ipc smoke themeValue focusRing.width)" && offset="$(ipc smoke themeValue focusRing.offset)" || return
  reading="$(ipc smoke descendantGeometry panel vgs.themes)" || return
  printf '%s %s\n%s\n' "$width" "$offset" "$reading" >"$panel_kept.tmp" && mv -T -- "$panel_kept.tmp" "$panel_kept" || return
  panel_judge "$width" "$offset" "" <<<"$reading"
}
panel_judge() { # RING_WIDTH RING_OFFSET PLANT, the reading on stdin
  py_reply '
import json, sys
rows, ring, plant = json.load(sys.stdin), float(sys.argv[1]) + float(sys.argv[2]), sys.argv[3]
out = []
def shown(r): return r["box"][2] > 0 and r["box"][3] > 0
def inside(j, i):
    while j != -1:
        if j == i: return True
        j = rows[j]["parent"]
    return False
panel = rows[0]["box"]
title = [r["box"][:] for r in rows if r["type"] == "Label" and r.get("role") == "h3" and r.get("text") == "Themes" and shown(r)]
heads = [r["box"][:] for r in rows if r["type"] == "SectionHeader" and shown(r)]
items = [i for i, r in enumerate(rows) if r["type"] == "ListItem" and shown(r)]
smoke = [i for i in items if rows[i].get("text") == "smoke"]
scroll = [r["box"] for r in rows if r["type"] == "ScrollArea" and shown(r)]
add = [r["box"][:] for r in rows if r["type"] == "Button" and r.get("text") == "Add from URL" and shown(r)]
if len(title) != 1 or len(heads) != 3 or len(smoke) != 1 or len(scroll) != 1 or len(add) != 1:
    print(json.dumps(["rows title=%d heads=%d smoke=%d scroll=%d add=%d" % (len(title), len(heads), len(smoke), len(scroll), len(add))])); sys.exit()
title, row = title[0], rows[smoke[0]]["box"][:]
name = [rows[j]["box"][:] for j in range(len(rows)) if rows[j]["type"] == "Label" and rows[j].get("text") == "smoke" and inside(j, smoke[0])]
line = [r["box"][:] for r in rows if r["type"] == "Label" and r.get("text") == "smoke-fails: The theme action failed. Try again or choose another theme." and shown(r)]
if plant == "edge": row[2] -= 8
if plant == "column" and line: line[0][0] += 8
if plant == "footer": add[0][1] -= 40
edge = title[0]
for b in heads + [row]:
    if abs(b[0] - edge) > 1: out.append("edge x=%.2f title=%.2f" % (b[0], edge))
if abs((edge - panel[0]) - (panel[0] + panel[2] - row[0] - row[2])) > 1: out.append("edge left=%.2f right=%.2f" % (edge - panel[0], panel[0] + panel[2] - row[0] - row[2]))
if len(name) != 1 or len(line) != 1: out.append("column name=%d line=%d" % (len(name), len(line)))
elif abs(line[0][0] - name[0][0]) > 1: out.append("column line=%.2f name=%.2f" % (line[0][0], name[0][0]))
b, s = add[0], scroll[0]
if b[0] < panel[0] - 1 or b[0] + b[2] > panel[0] + panel[2] + 1 or b[1] + b[3] > panel[1] + panel[3] + 1: out.append("footer box=%s panel=%s" % (b, panel))
if b[1] < s[1] + s[3] - ring - 1: out.append("footer top=%.2f body.bottom=%.2f" % (b[1], s[1] + s[3] - ring))
print(json.dumps(out))' "$1" "$2" "$3"
}
panel_planted() { # RULE
  local width offset
  { read -r width offset && panel_judge "$width" "$offset" "$1"; } <"$panel_kept" \
    | py_reply 'import json,sys; print(any(e.startswith(sys.argv[1] + " ") for e in json.load(sys.stdin)))' "$1"
}
geometry expect_poll "the themes panel keeps one content edge, the text column and its footer" '[]' panel_geometry
for rule in edge column footer; do
  expect "control: the themes panel's $rule rule refuses its planted box" True panel_planted "$rule"
done
expect "the previously displayed row loses its badge" '[["vgs", "shipped"]]' theme_row vgs
rm -r -- "$fixture_targets/smoke-fails"
click_row smoke || fail "the second click on the smoke row failed"
expect "the second smoke apply ends" idle theme_idle
expect_poll "a later apply of that package that succeeds clears its failed target" '[["smoke", "installed", "Displayed"]]' theme_row smoke

# A control that moves after point_item first read its box, as a catalog
# row does when the panel's list grows under a scroll position set before
# it. planted_click MODE TEXT runs click_item on the list item TEXT with
# the list at its top; its first pointer move first scrolls the list down
# by twice the vgs item's height and writes the item's box before and
# after the scroll to $click_plant. With MODE `real`, click_item follows
# the item and clicks it. With MODE `single-read`, click_item runs on a
# copy of point_item that reads the box once, the form that clicked before
# the list settled: it hovers where the item was, never finds it under the
# pointer and clicks nothing. The vgs item is the target: the scroll
# leaves it drawn whole, and a click on it applies vgs.
click_plant="$sandbox/click-plant"
planted_click() {
  scroll_themes 0 || return 1
  rm -f -- "$click_plant" || return 1
  (
    source "$sandbox/planted-hover.sh" || exit 1
    case "$1" in
      real) ;;
      single-read) source "$sandbox/point-item-single-read.sh" || exit 1 ;;
      *) echo "planted_click: refused: mode=$1" >&2; exit 1 ;;
    esac
    hover() {
      if [[ ! -e $click_plant ]]; then
        local first offset second
        first="$(ipc smoke itemGeometry panel vgs.themes ListItem vgs)" \
          && offset="$(python3 -c 'import json,sys; print(int(2 * json.loads(sys.argv[1])[3]) + 1)' "$first")" \
          && scroll_themes "$offset" \
          && second="$(ipc smoke itemGeometry panel vgs.themes ListItem vgs)" \
          && printf '%s\n%s\n' "$first" "$second" >"$click_plant.tmp" \
          && mv -T -- "$click_plant.tmp" "$click_plant" || return 1
      fi
      planted_hover "$@"
    }
    themes_click_item ListItem "$2"
  )
}
# Whether the plant moved the vgs item by more than its own height: True
# or False, or the plant file's lines when it holds no two boxes.
plant_moved() { python3 -c 'import json,sys; b=[json.loads(l) for l in open(sys.argv[1]).read().splitlines()]; print(abs(b[1][1]-b[0][1]) > b[0][3] if len(b)==2 else b)' "$click_plant"; }
single_read_needle='rect="$(control_box "${lookup[@]}")" || return 1'
point_item_def="$(declare -f point_item)"
point_item_rest="${point_item_def//"$single_read_needle"/}"
if [[ $(( (${#point_item_def} - ${#point_item_rest}) / ${#single_read_needle} )) == 1 ]] \
  && single_read_def="${point_item_def/"$single_read_needle"/"[[ \$i -gt 1 ]] || $single_read_needle"}" \
  && [[ $single_read_def != "$point_item_def" ]] \
  && printf '%s\n' "$single_read_def" >"$sandbox/point-item-single-read.sh" \
  && printf 'planted_%s\n' "$(declare -f hover)" >"$sandbox/planted-hover.sh"; then
  if planted_click single-read vgs; then
    fail "click_item on the single-read point_item clicked for the vgs item the plant moved"
  else
    expect "the plant moved the vgs item under the single-read point_item" True plant_moved
    expect "no apply runs after the single-read point_item" idle theme_idle
    expect "click_item on the single-read point_item clicked nothing" '"smoke"' lent theme.last.result.theme
  fi
  planted_click real vgs || fail "click_item did not click the vgs item the plant moved"
  expect "the plant moved the vgs item under click_item" True plant_moved
  expect_poll "click_item's click on the moved vgs item applies vgs" '"vgs"' lent theme.last.result.theme
  expect "the planted vgs apply ends" idle theme_idle
  scroll_themes 0
  click_row smoke || fail "the click applying smoke after the plant failed"
  expect_poll "smoke is applied again after the plant" '"smoke"' lent theme.last.result.theme
  expect "the smoke apply after the plant ends" idle theme_idle
  expect_poll "the shell displays smoke again after the plant" smoke ipc smoke themeName
else
  fail "the single-read point_item copy could not be written"
fi

# Control: click_item aimed at the vgs row's centre, a stand-in for a
# panel surface the compositor has not yet placed where the probe reads
# it, never finds the smoke row under the pointer, so it clicks nothing.
# The aim is the vgs row's centre as an offset from the smoke row's corner.
if vgs_rect="$(ipc smoke itemGeometry panel vgs.themes ListItem vgs)" && [[ $vgs_rect != absent ]] \
  && smoke_rect="$(ipc smoke itemGeometry panel vgs.themes ListItem smoke)" && [[ $smoke_rect != absent ]]; then
  read -r vx vy < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); sx,sy=json.loads(sys.argv[2])[:2]; print(int(x+w/2-sx), int(y+h/2-sy))' "$vgs_rect" "$smoke_rect")
  if themes_click_item ListItem smoke "$vx" "$vy"; then
    fail "click_item clicked for the smoke row at the vgs row's centre"
  else
    ok "click_item clicks nothing at a point the smoke row does not report the pointer over"
  fi
else
  fail "the rows' geometry is unreadable for the click control: vgs=${vgs_rect:-failed} smoke=${smoke_rect:-failed}"
fi

# An installed package's own file for a target that runs code is dropped
# and the template renders in its place: the target is written and the row
# names the file.
fixture_target smoke-drop 'accent=@{palette.accent}' true
mkdir -p -- "$installed/smoke/targets"
printf 'accent=hand\n' >"$installed/smoke/targets/smoke-drop.conf"
click_row smoke || fail "the click applying the smoke row with a dropped file failed"
expect "the dropped-file smoke apply ends" idle theme_idle
expect_poll "the row names the file its apply dropped" '[["smoke", "installed", "Displayed", "smoke-drop uses the VGS settings for smoke-drop.conf"]]' theme_row smoke

# Control: a sandbox copy of the panel that reads no `dropped` names no
# file for the same result, which a panel built after the apply reads from
# `last`; the restored panel names it again.
drop_read='target.dropped === undefined ? [] : target.dropped'
if [[ $(grep -c -F -- "$drop_read" "$panel_qml") == 1 ]]; then
  if python3 -c 'import sys; p, q, old = sys.argv[1:]; open(q, "w").write(open(p).read().replace(old, "[]"))' "$sandbox/ThemesPanel.qml.real" "$sandbox/ThemesPanel.qml.mutant" "$drop_read"; then
    panel_source "the dropless control" "$sandbox/ThemesPanel.qml.mutant" \
      && expect_poll "the dropless control names no dropped file" '[["smoke", "installed", "Displayed"]]' theme_row smoke
  else
    fail "the dropless control could not be written"
  fi
  panel_source "the restored panel" "$sandbox/ThemesPanel.qml.real" \
    && expect_poll "the restored panel names the dropped file from last" '[["smoke", "installed", "Displayed", "smoke-drop uses the VGS settings for smoke-drop.conf"]]' theme_row smoke
else
  fail "the dropless control's text occurs once in $panel_qml"
fi
rm -r -- "$fixture_targets/smoke-drop" "$installed/smoke/targets"
click_row smoke || fail "the click applying the smoke row with nothing dropped failed"
expect "the no-drop smoke apply ends" idle theme_idle
expect_poll "a later apply that drops nothing clears the line" '[["smoke", "installed", "Displayed"]]' theme_row smoke
# A hand edit that keeps the package's name marks its row Modified while
# the panel stays open, and a click on the row applies the package again
# and clears the badge.
write_theme '{ "schemaVersion": 1, "name": "smoke", "tokens": { "palette": { "accent": "#12ab36" } } }'
expect_poll "a hand edit of the displayed package marks its row modified" '[["smoke", "installed", "Displayed", "Modified"]]' theme_row smoke
click_row smoke || fail "the click reapplying the modified smoke row failed"
expect_poll "reapplying the modified package clears its badge" '[["smoke", "installed", "Displayed"]]' theme_row smoke

# The gate holds every theme command, polling every 50 ms for at most
# 10 s, so the panel closes while its apply runs.
cp -p -- "$repo/bin/vgshell" "$repo/bin/vgshell.real"
panel_gate="$sandbox/themes-panel-gate"
stand_in_vgshell "for _ in \$(seq 1 200); do [[ -e $(printf %q "$panel_gate") ]] && break; sleep 0.05; done"
click_row dawn || fail "the click on the installed dawn row failed"
expect_poll "the row shows the apply running" '[["dawn", "installed", "Applying"], ["dawn", "shipped", "Hidden by another copy"]]' theme_row dawn
click_outside || fail "the click outside the themes panel failed"
expect_poll "a click outside closes the panel during the apply" closed panel_open
touch -- "$panel_gate"
expect_poll "the apply completes with the panel closed" '[]' theme_jobs
expect "the shortcut opens the themes panel" ok hypr dispatch 'hl.dsp.global("vgs.themes:panel")'
expect_poll "the reopened panel shows the apply's result" '[["dawn", "installed", "Displayed"], ["dawn", "shipped", "Hidden by another copy"]]' theme_row dawn
expect "the theme changed while the panel was closed" dawn ipc smoke themeName

# A panel reopened while its apply runs reads the apply from last, and the
# result it waits for carries a target state no code of the panel names.
# The same gate holds the stand-in.
novel_gate="$sandbox/themes-novel-gate"
novel='{"state":"partial","shell":"unchanged","targets":[{"name":"smoke-novel","state":"smoke-state","reason":"smoke-reason"}],"theme":"vgs","reason":null}'
stand_in_vgshell "for _ in \$(seq 1 200); do [[ -e $(printf %q "$novel_gate") ]] && break; sleep 0.05; done
if [[ \${2:-} == apply ]]; then printf '%s\\n' $(printf %q "$novel"); exit 3; fi"
click_row vgs || fail "the click on the vgs row failed"
expect_poll "the vgs row shows its apply running" '[["vgs", "shipped", "Applying"]]' theme_row vgs
click_outside || fail "the click outside the themes panel failed"
expect_poll "the panel closes during the vgs apply" closed panel_open
expect "the shortcut opens the themes panel" ok hypr dispatch 'hl.dsp.global("vgs.themes:panel")'
expect_poll "the panel reopened during the apply reads it from last" True panel_label "Applying vgs"
touch -- "$novel_gate"
expect_poll "the reopened panel shows a target state it names nowhere" '[["vgs", "shipped", "smoke-novel: The theme action failed. Try again or choose another theme."]]' theme_row vgs
expect "the panel drops the running apply once it ends" False panel_label "Applying vgs"

mv -T -- "$repo/bin/vgshell.real" "$repo/bin/vgshell"
click_row vgs || fail "the click on the vgs row with the real runner failed"
expect_poll "the vgs row applied by the real runner is displayed with no problem" '[["vgs", "shipped", "Displayed"]]' theme_row vgs
expect_poll "the vgs package is displayed again" vgs ipc smoke themeName
rm -rf -- "${installed:?}/dawn" "${repo:?}/themes/dawn"
click_outside || fail "the click closing the themes panel failed"
expect_poll "the themes panel closes" closed panel_open
# ---- end vgs.themes ---------------------------------------------------------

# ---- vgs.themes wallpaper: the theme's background image ------------------
# The background kind of vgs.themes, built on every screen since the
# harness started, and the panel's wallpaper section. An installed package
# ships three generated images: a.png, larger than any nested screen, b.png
# and c.png. What the background draws is read back from its Image on the
# first screen through the probe's `images`, and the surface the host maps
# from the compositor: none while no image is drawn, one per screen while
# one is. The panel is read back through the labels it draws and clicked
# through its icon buttons. The first screen, at scale 1, requests its
# logical size, the mode the compositor reports; rows/hidpi.sh reads the
# request at scale 2 on a shell started there. A headless second monitor
# draws an image set on it alone while the first screen draws `current`. A
# copy of the shared state reader that ignores `screens`, one that never
# reloads the state file and a copy of the background that is always shown
# are the block's controls.
# The block leaves vgs applied with no current image and the plugin
# disabled, so later rows see the bar they saw before the vgs.themes block.
scenic="$installed/scenic"
mkdir -p -- "$scenic/backgrounds"
printf '%s\n' '{ "schemaVersion": 1, "name": "scenic", "tokens": {} }' >"$scenic/theme.json"
solid_png "$scenic/backgrounds/a.png" 4000 2000 200 40 40
solid_png "$scenic/backgrounds/b.png" 64 36 40 40 200
solid_png "$scenic/backgrounds/c.png" 48 48 40 200 40
vgshell_theme() { "${shell_env[@]}" "$repo/bin/vgshell" theme "$@"; }
# What the first screen's background draws, as background_image_on in
# harness.sh reads it. background_covers: whether the image decoded to
# cover its box and smaller than the 4000x2000 file.
background_image() { background_image_on "$screen_name"; }
background_covers() { ipc smoke images "background:$screen_name" vgs.themes | py_reply 'import json,sys; _,_,box,size,*_=json.load(sys.stdin)[0]; print(box[0] > 0 and size[0] >= box[0] and size[1] >= box[1] and size[0] < 4000)'; }
background_link() { if [[ -L $bg_state/background ]]; then readlink -- "$bg_state/background"; else echo absent; fi; }
# The drawn image's decoded width over its height, to one decimal place;
# `images=<n>` while the background draws other than one image.
background_ratio() { ipc smoke images "background:$screen_name" vgs.themes | py_reply 'import json,sys; r=json.load(sys.stdin); print("%.1f" % (r[0][3][0] / r[0][3][1]) if len(r)==1 else "images=%d" % len(r))'; }
screen_listed() { hypr -j monitors | py_reply 'import json,sys; print(any(m["name"] == sys.argv[1] for m in json.load(sys.stdin)))' "$1"; }
# The state file's current image and the image it remembers for scenic, as
# JSON, null for none or no file.
bg_current() { if [[ -e $bg_state/backgrounds.json ]]; then python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["current"]))' "$bg_state/backgrounds.json"; else echo null; fi; }
bg_remembered() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["themes"].get("scenic")))' "$bg_state/backgrounds.json"; }
# Whether the panel's icon button LABEL can be clicked: enabled or disabled.
wallpaper_button() { [[ $(ipc smoke labelledGeometry panel vgs.themes IconButton "$1") != absent ]] && echo enabled || echo disabled; }
# click_wallpaper LABEL: one click on the centre of the panel's icon button
# LABEL, polled for up to 5 s while a running step disables it.
click_wallpaper() {
  local rect=absent cx cy
  for _ in $(seq 1 25); do
    ipc smoke revealText panel vgs.themes IconButton "$1" >/dev/null
    rect="$(themes_item_box IconButton "$1")" && [[ $rect != absent ]] && break
    sleep 0.2
  done
  [[ $rect != absent ]] || return 1
  read -r cx cy < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$rect")
  [[ $cx -ge 0 && $cy -ge 0 && $cx -lt $mon_w && $cy -lt $mon_h ]] || return 1
  click "$cx" "$cy"
}

expect "the vgs.themes background is built with vgs applied" "- null" background_image
expect "the host maps no surface without an image" 0 layer_count vgs:background
expect "a package with backgrounds applies" "ok theme=scenic state=applied shell=applied" vgshell_theme apply scenic
expect "the apply links the package's first image" "$scenic/backgrounds/a.png" background_link
expect_poll "the background draws the applied package's first image" "$scenic/backgrounds/a.png ready" background_image
expect_poll "the host maps one surface per screen once the image is drawn" "$monitors" layer_count vgs:background
expect "the image is decoded to cover the screen, not at the file's size" True background_covers
# The first screen's mode at scale 1 is its logical size, which the
# background requests. The mode comes from the compositor, so a screen Qt
# reads as 0x0 cannot pass.
screen_mode="$(unscaled_mode_of "$screen_name")" || { fail "the first screen reads no sized mode at scale 1"; screen_mode=unread; }
expect_poll "the scale-1 screen requests its logical size" "$screen_mode" background_source_size "$screen_name"

# Each screen draws its own entry in `screens`, else `current`: an image
# from the user folder set on a second monitor alone, which a step of
# `current` leaves in place. A screen whose own image cannot be read draws
# `current`: the image is removed and the monitor comes back, so a new
# background decodes the entry that `screens` keeps. The second monitor is
# a headless output: these rows read which image it draws, not its size.
# Control: a sandbox copy of the state reader that ignores `screens` draws
# `current` on the second monitor.
second_output=SMOKE-SECOND
# second_bar_listed: whether the build records hold the second monitor's
# bar. A removal the compositor lists is not yet one the shell handled, so
# each removal below waits for the bar's records to go before the row goes
# on; the reading with the monitor present is that wait's control.
second_bar_listed() { ipc shell built | py_reply 'import json,sys; print(("bar:" + sys.argv[1]) in json.load(sys.stdin))' "$second_output"; }
expect "the nested compositor adds a second monitor" ok hypr output create headless "$second_output"
expect_poll "the second monitor is listed" True screen_listed "$second_output"
expect_poll "the second monitor's bar is in the build records" True second_bar_listed
expect_poll "the second monitor gets a background" "$scenic/backgrounds/a.png ready" background_image_on "$second_output"
expect_poll "the host maps the second monitor's background with the others" "$((monitors + 1))" layer_count vgs:background
user_bg="$home/.config/vgshell/backgrounds"
mkdir -p -- "$user_bg"
cp -- "$scenic/backgrounds/c.png" "$user_bg/own.png"
expect "set --screen gives the second monitor its own image" "ok background=own.png theme=- path=$user_bg/own.png screen=$second_output" vgshell_theme background set "$user_bg/own.png" --screen "$second_output"
expect_poll "the second monitor draws its own image" "$user_bg/own.png ready" background_image_on "$second_output"
expect "the first screen draws the current image beside it" "$scenic/backgrounds/a.png ready" background_image
expect "next moves the current image under a screen's own" "ok background=b.png theme=scenic path=$scenic/backgrounds/b.png" vgshell_theme background next
expect_poll "the first screen follows next" "$scenic/backgrounds/b.png ready" background_image
expect "the second monitor keeps its own image through next" "$user_bg/own.png ready" background_image_on "$second_output"
expect "previous moves the current image back" "ok background=a.png theme=scenic path=$scenic/backgrounds/a.png" vgshell_theme background previous
expect_poll "the first screen follows previous" "$scenic/backgrounds/a.png ready" background_image
state_qml="$repo/shell/plugins/vgs.themes/WallpaperState.qml"
cp -p -- "$state_qml" "$sandbox/WallpaperState.qml.screens.real"
python3 - "$sandbox/WallpaperState.qml.screens.real" "$state_qml.tmp" <<'PY'
import pathlib, sys
src, dst = map(pathlib.Path, sys.argv[1:])
text = src.read_text()
old = "return Object.prototype.hasOwnProperty.call(screens, name) ? screens[name] : source;"
assert text.count(old) == 1, f"screens control must match once: {old}"
dst.write_text(text.replace(old, "return source;"))
assert dst.read_text() != text, "screens control must change the file"
PY
mv -T -- "$state_qml.tmp" "$state_qml"
rescan "a rescan builds the control that ignores screens"
expect_poll "the control draws the current image on the second monitor" "$scenic/backgrounds/a.png ready" background_image_on "$second_output"
cp -p -- "$sandbox/WallpaperState.qml.screens.real" "$state_qml.tmp" && mv -T -- "$state_qml.tmp" "$state_qml"
rescan "a rescan restores the reader of screens"
expect_poll "the restored plugin draws the second monitor's own image" "$user_bg/own.png ready" background_image_on "$second_output"
expect "the follow after the screens rescans ends" idle theme_idle
expected_errors+=('background: file://.*/own\.png\?.* unreadable' 'Background\.qml.*Cannot open: file://.*/own\.png')
rm -- "$user_bg/own.png"
expect "the nested compositor removes the second monitor over its removed image" ok hypr output remove "$second_output"
expect_poll "the second monitor is gone before it comes back" False screen_listed "$second_output"
expect_poll "the second monitor's bar left the build records before it comes back" False second_bar_listed
expect "the nested compositor adds the second monitor back" ok hypr output create headless "$second_output"
expect_poll "a screen whose own image cannot be read draws the current image" "$scenic/backgrounds/a.png ready" background_image_on "$second_output"
expect_log "the background logs the unreadable own image" 1 'background: file://.*/own\.png\?.* unreadable'
# A screen's own entry that names the current image under the same stamp
# fails with it, and the screen follows the next readable `current`.
cp -- "$scenic/backgrounds/c.png" "$user_bg/same.png"
expected_errors+=('background: file://.*/same\.png\?.* unreadable' 'Background\.qml.*Cannot open: file://.*/same\.png')
expect "set makes a user-folder image current" "ok background=same.png theme=- path=$user_bg/same.png" vgshell_theme background set "$user_bg/same.png"
expect "set --screen gives the second monitor the current image as its own" "ok background=same.png theme=- path=$user_bg/same.png screen=$second_output" vgshell_theme background set "$user_bg/same.png" --screen "$second_output"
expect_poll "the second monitor draws its own entry that names the current image" "$user_bg/same.png ready" background_image_on "$second_output"
rm -- "$user_bg/same.png"
expect "the nested compositor removes the second monitor over its removed current image" ok hypr output remove "$second_output"
expect_poll "the second monitor is gone before it comes back again" False screen_listed "$second_output"
expect_poll "the second monitor's bar left the build records before it comes back again" False second_bar_listed
expect "the nested compositor adds the second monitor back again" ok hypr output create headless "$second_output"
expect_poll "an own entry equal to an unreadable current draws nothing" "$user_bg/same.png error" background_image_on "$second_output"
expect "set makes a readable package image current" "ok background=a.png theme=scenic path=$scenic/backgrounds/a.png" vgshell_theme background set "$scenic/backgrounds/a.png"
expect_poll "a screen whose failed own entry named the old current draws the new current" "$scenic/backgrounds/a.png ready" background_image_on "$second_output"
expect "the nested compositor removes the second monitor" ok hypr output remove "$second_output"
expect_poll "the second monitor's background surface is gone" "$monitors" layer_count vgs:background
expect_poll "the removed second monitor is gone" False screen_listed "$second_output"
expect_poll "the second monitor's bar left the build records" False second_bar_listed
expect "next moves to the package's second image" "ok background=b.png theme=scenic path=$scenic/backgrounds/b.png" vgshell_theme background next
expect_poll "the background follows next" "$scenic/backgrounds/b.png ready" background_image
expect "previous moves back to the package's first image" "ok background=a.png theme=scenic path=$scenic/backgrounds/a.png" vgshell_theme background previous
expect_poll "the background follows previous" "$scenic/backgrounds/a.png ready" background_image
expect "next moves to the second image again" "ok background=b.png theme=scenic path=$scenic/backgrounds/b.png" vgshell_theme background next
expect "a package without backgrounds applies" "ok theme=vgs state=applied shell=applied" vgshell_theme apply vgs
expect "the link goes with a package without backgrounds" absent background_link
expect_poll "the background draws no image for it" "- null" background_image
expect_poll "the surface goes with the image" 0 layer_count vgs:background

# The panel's wallpaper section: the current image's name and a step to
# the next or the previous one through the theme capability, disabled
# while no image is current. It follows the CLI as well as its own clicks.
expect "the shortcut opens the themes panel" ok hypr dispatch 'hl.dsp.global("vgs.themes:panel")'
expect_poll "the themes panel opens for the wallpaper rows" open panel_open
expect_poll "the panel names no wallpaper while none is current" True panel_label None
expect "Next is disabled while no wallpaper is current" disabled wallpaper_button "Next wallpaper"
expect "Previous is disabled while no wallpaper is current" disabled wallpaper_button "Previous wallpaper"
expect "the package with backgrounds applies again under the open panel" "ok theme=scenic state=applied shell=applied" vgshell_theme apply scenic
expect_poll "the background draws the image next remembered" "$scenic/backgrounds/b.png ready" background_image
expect_poll "the surface comes back with the image" "$monitors" layer_count vgs:background
expect_poll "the panel follows the apply to the remembered wallpaper" True panel_label b.png
expect_poll "Next is enabled once a wallpaper is current" enabled wallpaper_button "Next wallpaper"
click_wallpaper "Next wallpaper" || fail "the click on Next wallpaper failed"
expect_poll "a click on Next draws the next wallpaper" "$scenic/backgrounds/c.png ready" background_image
expect_poll "the panel names the wallpaper Next moved to" True panel_label c.png
click_wallpaper "Previous wallpaper" || fail "the click on Previous wallpaper failed"
expect_poll "a click on Previous draws the wallpaper before" "$scenic/backgrounds/b.png ready" background_image
expect_poll "the panel names the wallpaper Previous moved to" True panel_label b.png
expect "the panel's step remembers its wallpaper for the package" '"b.png"' bg_remembered
# A step the runner refuses is shown as the panel's problem line: the row
# holds the theme lock, so the runner answers busy, and the wallpaper stays.
exec {wallpaper_lock}>>"$home/.config/vgshell/theme.lock"
flock "$wallpaper_lock"
click_wallpaper "Next wallpaper" || fail "the click on Next wallpaper under the held lock failed"
expect_poll "a refused step shows its reason" True panel_label "The wallpaper could not be changed. Another theme action is running. Wait for it to finish."
expect "a refused step leaves the wallpaper" "$scenic/backgrounds/b.png ready" background_image
exec {wallpaper_lock}>&-
click_outside || fail "the click closing the themes panel after the wallpaper rows failed"
expect_poll "the themes panel closes after the wallpaper rows" closed panel_open

# The capability's background step, driven through the fixture: a step
# that is neither next nor previous is refused at once, a step's result is
# the runner's JSON line, and a runner that prints no result is answered as
# a failure.
stepped() { read_service themeStepped | py_reply 'import json,sys; r=json.loads(json.load(sys.stdin)); print(r["state"], r["background"], r["theme"], r["reason"])'; }
expect "enabling the fixture for the wallpaper step rows is allowed" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the fixture service is back for the wallpaper step rows" True service_built
expect "background browser reads settle before the malformed step" idle theme_idle
expect "a malformed step is refused at once" 'refused: background="sideways" reason=malformed-step' probe theme-background sideways
expect "a malformed step queues nothing" '[]' theme_jobs
expect "the fixture steps to the next wallpaper" ok probe theme-background next
expect_poll "the step's result reaches the fixture" 1 read_service themeSteps
expect "the step's result is the runner's" "ok c.png scenic None" stepped
expect_poll "the background follows the fixture's step" "$scenic/backgrounds/c.png ready" background_image
expected_errors+=('theme: vgshell theme background reason=output-unreadable name=previous exit=2 ')
cp -p -- "$repo/bin/vgshell" "$repo/bin/vgshell.real"
stand_in_vgshell 'echo "no result"; exit 2'
expect "a step whose runner prints no result is accepted" ok probe theme-background previous
expect_poll "the unreadable step reaches the fixture" 2 read_service themeSteps
expect "a step with no result is a failure with its reason" "failed None None output-unreadable" stepped
mv -T -- "$repo/bin/vgshell.real" "$repo/bin/vgshell"
expect "disabling the fixture after the wallpaper step rows is allowed" ok ipc shell setPluginEnabled acme.probe false

# A state file the runner did not write is logged and draws nothing.
expected_errors+=('background: .*/backgrounds\.json malformed')
printf '{ nope\n' >"$bg_state/backgrounds.json.tmp" && mv -T -- "$bg_state/backgrounds.json.tmp" "$bg_state/backgrounds.json"
expect_poll "a malformed state file draws no image" "- null" background_image
expect_poll "a malformed state file maps no surface" 0 layer_count vgs:background
expect_log "the background logs the malformed state file" 1 'background: .*/backgrounds\.json malformed'
rm -- "$bg_state/backgrounds.json"
expect "the package applies over a removed state file" "ok theme=scenic state=unchanged shell=unchanged" vgshell_theme apply scenic
expect_poll "the rewritten state file draws the first image again" "$scenic/backgrounds/a.png ready" background_image

# Control: a sandbox copy of the state reader that never reads on a change
# keeps drawing the image it read when it was built after next moves on.
# The real reader followed next within expect_poll's first polls above, so
# two seconds is ample for it.
state_qml="$repo/shell/plugins/vgs.themes/WallpaperState.qml"
cp -p -- "$state_qml" "$sandbox/WallpaperState.qml.real"
if [[ $(grep -c -F 'onChanged: read()' -- "$state_qml") == 1 ]]; then
  python3 -c 'import sys; p, q = sys.argv[1:]; open(q, "w").write(open(p).read().replace("onChanged: read()", "onChanged: {}"))' "$sandbox/WallpaperState.qml.real" "$state_qml.tmp" && mv -T -- "$state_qml.tmp" "$state_qml"
  control_builds="$(builds)" || { fail "buildCount unreadable before the unwatched control"; control_builds=0; }
  rescan "a rescan builds the unwatched control"
  expect_poll "the control rebuilds every vgs.themes instance" "$((control_builds + themes_instances))" builds
  expect "the follow the rescan queued ends before the row's theme command" idle theme_idle
  expect "the control draws the current image when built" "$scenic/backgrounds/a.png ready" background_image
  expect "next moves on under the control" "ok background=b.png theme=scenic path=$scenic/backgrounds/b.png" vgshell_theme background next
  sleep 2
  expect "the unwatched control keeps drawing the image it was built with" "$scenic/backgrounds/a.png ready" background_image
  cp -p -- "$sandbox/WallpaperState.qml.real" "$state_qml.tmp" && mv -T -- "$state_qml.tmp" "$state_qml"
  rescan "a rescan restores the plugin"
  expect_poll "the restored plugin draws the current image" "$scenic/backgrounds/b.png ready" background_image
  expect "the follow the restoring rescan queued ends" idle theme_idle
else
  fail "the unwatched control's text occurs once in $state_qml"
fi

# Two state changes that land back to back draw the later one. The row
# does not force the second change into the first one's read; it pins that
# the last state wins.
bg_state_names "$scenic/backgrounds/a.png"; bg_state_names "$scenic/backgrounds/c.png"
expect_poll "back-to-back state changes draw the later image" "$scenic/backgrounds/c.png ready" background_image
# An image replaced under its name is decoded again once its package
# applies again: the 2:1 a.png becomes a 16:9 image.
expect "the package applies over the hand-written state" "ok theme=scenic state=unchanged shell=unchanged" vgshell_theme apply scenic
expect_poll "the package's first image is drawn at its 2:1 shape" 2.0 background_ratio
cp -- "$scenic/backgrounds/b.png" "$scenic/backgrounds/a.png.tmp" && mv -T -- "$scenic/backgrounds/a.png.tmp" "$scenic/backgrounds/a.png"
expect "the package applies over its replaced image" "ok theme=scenic state=unchanged shell=unchanged" vgshell_theme apply scenic
expect_poll "the replaced image is decoded again at its 16:9 shape" 1.8 background_ratio

# Control: a sandbox copy of the background that is always shown maps the
# host's surface, drawing only its colour, when no image is current.
plugin_qml="$repo/shell/plugins/vgs.themes/Background.qml"
cp -p -- "$plugin_qml" "$sandbox/Background.qml.real"
if [[ $(grep -c -F 'readonly property bool shown: drawn' -- "$plugin_qml") == 1 ]]; then
  python3 -c 'import sys; p, q = sys.argv[1:]; open(q, "w").write(open(p).read().replace("readonly property bool shown: drawn", "readonly property bool shown: true"))' "$sandbox/Background.qml.real" "$plugin_qml.tmp" && mv -T -- "$plugin_qml.tmp" "$plugin_qml"
  control_builds="$(builds)" || { fail "buildCount unreadable before the always-shown control"; control_builds=0; }
  rescan "a rescan builds the always-shown control"
  expect_poll "the always-shown control rebuilds every vgs.themes instance" "$((control_builds + themes_instances))" builds
  expect "the follow the always-shown rescan queued ends" idle theme_idle
  expect "vgs applies under the always-shown control" "ok theme=vgs state=applied shell=applied" vgshell_theme apply vgs
  expect_poll "the always-shown control draws no image" "- null" background_image
  expect "the always-shown control maps a surface with no image" "$monitors" layer_count vgs:background
  cp -p -- "$sandbox/Background.qml.real" "$plugin_qml.tmp" && mv -T -- "$plugin_qml.tmp" "$plugin_qml"
  rescan "a rescan restores the plugin after the always-shown control"
  expect_poll "the restored plugin maps no surface with no image" 0 layer_count vgs:background
  # A rescan queues follow; the read-only prefix row applies vgs next and can meet the theme lock while follow still runs.
  expect "the follow after the restored plugin rescan queued ends" idle theme_idle
else
  fail "the always-shown control's text occurs once in $plugin_qml"
fi

expect "no current wallpaper is left for later rows" null bg_current
expect "vgshell plugin disable takes the themes panel and background away" ok "${shell_env[@]}" "$repo/bin/vgshell" plugin disable vgs.themes
expect_poll "every vgs.themes instance is gone" False record_exists vgs.themes
# Disabling the plugin queues a scan and follow; the next row's apply must not race that theme lock.
expect "the follow after disabling the themes plugin ends" idle theme_idle
rm -r -- "$scenic"
# ---- end vgs.themes wallpaper -----------------------------------------------
