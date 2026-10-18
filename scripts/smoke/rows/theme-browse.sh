# The theme capability's members for the theme and wallpaper browsers:
# catalog, install, images, set and wallpapers, driven through the fixture
# service and read back from what its callbacks received, from `last` and
# from the core's lending record. catalog, install, images and set, one
# screen's and every screen's included, run the sandbox's real runner on
# the shipped catalog and on an installed package with two images.
# wallpapers runs on the download lane: the real runner for a refusal, a
# stand-in for a slow download, since the sandbox reaches no network, and
# a stand-in that records the arguments of the update form. The stand-in prints two progress lines, then polls
# its gate every 50 ms for at most 30 s, long enough for an apply and a
# rebuild of the fixture to finish behind it. rows/themes.sh defines the
# helpers used here and leaves vgs applied, Black current and the fixture
# disabled; this file leaves them so.
# inputs: scripts/smoke/fixtures/plugins/acme.probe/* shell/Core/ThemeRunner.qml bin/vgshell bin/vgshell-theme-judge bin/lib/theme-* themes/catalog/* themes/vgs/* scripts/smoke/rows/themes.sh scripts/smoke/rows/capabilities.sh scripts/smoke/rows/plugins.sh scripts/smoke/fixtures/theme-image.jpg
set -euo pipefail
theme_browse_controls=""
theme_browse_saved=""
theme_browse_download_gate=""
theme_browse_keep_state() {
  local saved i status enabled
  enabled="$(plugin_enabled acme.probe)" || return
  case "$enabled" in
    True) theme_browse_fixture_before=true ;;
    False) theme_browse_fixture_before=false ;;
    *) fail "theme-browse: fixture-state=$enabled"; return 1 ;;
  esac
  saved="$(mktemp -d "$sandbox/theme-browse-state.XXXXXX")" || return
  theme_browse_paths=("$installed/browse" "$installed/nord" "$bg_state/backgrounds.json" "$bg_state/background")
  for i in "${!theme_browse_paths[@]}"; do
    if [[ -e ${theme_browse_paths[i]} || -L ${theme_browse_paths[i]} ]]; then
      if cp -a -- "${theme_browse_paths[i]}" "$saved/$i"; then :; else
        status=$?
        rm -rf -- "${saved:?}"
        return "$status"
      fi
    fi
  done
  theme_browse_saved="$saved"
}
theme_browse_controls_cleanup() {
  ipc smoke runnerDrop >/dev/null 2>&1 || true
  if [[ -n $theme_browse_controls ]]; then
    rm -rf -- "${theme_browse_controls:?}"
    theme_browse_controls=""
  fi
}
theme_browse_cleanup() {
  local i target
  if [[ -n $theme_browse_download_gate ]]; then touch -- "$theme_browse_download_gate"; fi
  restore_vgshell
  theme_browse_controls_cleanup
  if [[ -n $theme_browse_saved ]]; then
    expect "the browse row restores its fixture enablement" ok ipc shell setPluginEnabled acme.probe "$theme_browse_fixture_before"
    expect "the browse row's theme jobs finish before restoration" idle theme_idle
    for i in "${!theme_browse_paths[@]}"; do
      target="${theme_browse_paths[i]}"
      rm -rf -- "${target:?}"
      if [[ -e $theme_browse_saved/$i || -L $theme_browse_saved/$i ]]; then
        cp -a -- "$theme_browse_saved/$i" "$target"
      fi
    done
    rm -rf -- "${theme_browse_saved:?}"
    theme_browse_saved=""
  fi
  if [[ -n $theme_browse_download_gate ]]; then
    rm -f -- "${theme_browse_download_gate:?}"
    theme_browse_download_gate=""
  fi
}
theme_browse_cleanup_control() (
  unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
  local mode="$1" control status=0
  control="$(mktemp -d "$sandbox/theme-browse-control.XXXXXX")" || return
  trap 'rm -rf -- "${control:?}"' EXIT
  sandbox="$control"
  installed="$control/world/packages"
  bg_state="$control/world/backgrounds"
  mkdir -p -- "$installed" "$bg_state" "$control/stubs"
  export PATH="$control/stubs:$PATH"
  printf 'false\n' >"$control/world/fixture"
  if [[ $mode != empty ]]; then
    printf 'original\n' >"$bg_state/backgrounds.json"
    ln -s -- original "$bg_state/background"
  fi
  if [[ $mode == packages ]]; then
    mkdir -p -- "$installed/browse" "$installed/nord"
    printf 'original\n' >"$installed/browse/theme.json"
    printf 'original\n' >"$installed/nord/theme.json"
    printf 'true\n' >"$control/world/fixture"
  fi
  cp -a -- "$control/world" "$control/before"
  plugin_enabled() { case "$(cat "$control/world/fixture")" in true) echo True ;; false) echo False ;; esac; }
  ipc() {
    if [[ $1 == shell && $2 == setPluginEnabled ]]; then printf '%s\n' "$4" >"$control/world/fixture"; fi
    echo ok
  }
  restore_vgshell() { :; }
  theme_idle() { echo idle; }
  theme_browse_saved="" theme_browse_download_gate=""
  theme_browse_controls="$control/runner-controls"
  mkdir -- "$theme_browse_controls"
  if [[ $mode == copy-fails ]]; then
    cat >"$control/stubs/cp" <<'SH'
#!/usr/bin/env bash
printf 'partial\n' >"${@: -1}"
exit 23
SH
    chmod 755 -- "$control/stubs/cp"
    hash -r
    theme_browse_keep_state || status=$?
    [[ $status == 23 && -z $theme_browse_saved ]] || return 1
    diff -r --no-dereference -- "$control/before" "$control/world" || return
    echo restored
    return 0
  fi
  theme_browse_keep_state || return
  mkdir -p -- "$installed/browse" "$installed/nord"
  printf 'planted\n' >"$installed/browse/theme.json"
  printf 'planted\n' >"$installed/nord/theme.json"
  printf 'planted\n' >"$bg_state/backgrounds.json"
  rm -f -- "${bg_state:?}/background"
  ln -s -- planted "$bg_state/background"
  printf 'true\n' >"$control/world/fixture"
  theme_browse_cleanup >"$control/cleanup.log"
  [[ ! -e $control/runner-controls && -z $theme_browse_saved ]] || return 1
  diff -r --no-dereference -- "$control/before" "$control/world" || return
  echo restored
)
for theme_browse_control_mode in empty background packages copy-fails; do
  expect "browse cleanup preserves the $theme_browse_control_mode state" restored theme_browse_cleanup_control "$theme_browse_control_mode"
done
theme_browse_keep_state
smoke_row_abandon=(theme_browse_cleanup)
browse="$installed/browse"
# What VERB's callback last received, as JSON: its call count, then the
# result's value of each KEY; `none` before the first call.
answer() { # VERB KEY...
  read_service themeAnswers | py_reply 'import json,sys; a=json.load(sys.stdin).get(sys.argv[1]); print("none" if a is None else json.dumps([a["count"]] + [a["result"][k] for k in sys.argv[2:]]))' "$@"
}
answers() { read_service themeAnswers | py_reply 'import json,sys; a=json.load(sys.stdin).get(sys.argv[1]); print(0 if a is None else a["count"])' "$1"; }
# The last catalog's entry NAME: [installed, imageryInstalled].
catalog_entry() { read_service themeAnswers | py_reply 'import json,sys; e=[e for e in json.load(sys.stdin)["catalog"]["result"]["entries"] if e["name"]==sys.argv[1]]; print(json.dumps([e[0]["installed"], e[0]["imageryInstalled"]]) if len(e)==1 else "entries=%d" % len(e))' "$1"; }
# The last image list's images of package NAME: [background, path] rows.
images_of() { read_service themeAnswers | py_reply 'import json,sys; r=json.load(sys.stdin)["images"]["result"]; print(json.dumps([[i["background"], i["path"]] for i in r["images"] if i["theme"]==sys.argv[1]]))' "$1"; }
image_count() { read_service themeAnswers | py_reply 'import json,sys; print(len(json.load(sys.stdin)["images"]["result"]["images"]))'; }
# The download lane's job in the lending record: [verb, name, waiters], or
# null.
# The state file's `screens` map as JSON, {} for a file without it.
bg_screens() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])).get("screens", {})))' "$bg_state/backgrounds.json"; }
theme_download() { ipc shell lent | py_reply 'import json,sys; d=json.load(sys.stdin)["theme"]["download"]; print("null" if d is None else json.dumps([d["verb"], d["name"], d["waiters"]]))'; }

expect "enabling the fixture for the browse rows is allowed" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the fixture service is back for the browse rows" True service_built

# catalog and install, on the sandbox copy's shipped catalog.
expect "the fixture asks for the catalog" ok probe theme-catalog
expect_poll "the catalog reaches the fixture" '[1, null]' answer catalog reason
expect "the catalog names nord, not installed" '[false, false]' catalog_entry nord
expect "a malformed name's install is refused at once" 'refused: theme="../x" reason=malformed-name' probe theme-install ../x
expect "the fixture installs the catalog's nord" ok probe theme-install nord
expect_poll "the install's result reaches the fixture" '[1, "ok", "nord", "'"$installed/nord"'", null]' answer install state theme path reason
expect "the fixture asks for the catalog after the install" ok probe theme-catalog
expect_poll "the second catalog reaches the fixture" '[2, null]' answer catalog reason
expect "the catalog names nord installed" '[true, false]' catalog_entry nord
expect "a second install of nord is accepted" ok probe theme-install nord
expect_poll "the runner's refusal reaches the fixture as the result" '[2, "failed", "nord", null, "installed"]' answer install state theme path reason

# images and set, on an installed package with two images.
mkdir -p -- "$browse/backgrounds"
printf '%s\n' '{ "schemaVersion": 1, "name": "browse", "tokens": {} }' >"$browse/theme.json"
cp -- "$repo/scripts/smoke/fixtures/theme-image.jpg" "$browse/backgrounds/a.jpg"
cp -- "$repo/scripts/smoke/fixtures/theme-image.jpg" "$browse/backgrounds/b.jpg"
expect "a malformed scope is refused at once" 'refused: images="some" reason=malformed-scope' probe theme-images some
expect "the fixture lists every source's images" ok probe theme-images all
expect_poll "the full image list reaches the fixture" '[1, "ok", null]' answer images state reason
expect "the full list names both of browse's images" '[["a.jpg", "'"$browse/backgrounds/a.jpg"'"], ["b.jpg", "'"$browse/backgrounds/b.jpg"'"]]' images_of browse
expect "the fixture lists the applied package's images" ok probe theme-images applied
expect_poll "the applied image list reaches the fixture" '[2, "ok", null]' answer images state reason
expect "the applied image list holds one image" 1 image_count
expect "vgs, applied, holds Black" '[["black.png", "'"$repo/themes/vgs/backgrounds/black.png"'"]]' images_of vgs

expect "a relative path is refused at once" 'refused: set="a.jpg" reason=malformed-path' probe theme-set a.jpg
expect "a path with a .. segment is refused at once" 'refused: set="'"$browse"'/../browse/backgrounds/a.jpg" reason=malformed-path' probe theme-set "$browse/../browse/backgrounds/a.jpg"
expect "a malformed output name is refused at once" 'refused: set="../x" reason=malformed-screen' probe theme-set "$browse/backgrounds/a.jpg|../x"
expect "the fixture sets browse's b.jpg" ok probe theme-set "$browse/backgrounds/b.jpg"
expect_poll "the set's result reaches the fixture" '[1, "ok", "b.jpg", "browse", "'"$browse/backgrounds/b.jpg"'", null, null]' answer set state background theme path screen reason
expect "the set made b.jpg current" "\"$browse/backgrounds/b.jpg\"" bg_current
expect "the fixture sets a.jpg on the first screen" ok probe theme-set "$browse/backgrounds/a.jpg|$screen_name"
expect_poll "the screen's set reaches the fixture" '[2, "ok", "a.jpg", "'"$screen_name"'", null]' answer set state background screen reason
expect "a set for one screen keeps the current image" "\"$browse/backgrounds/b.jpg\"" bg_current
expect "the fixture sets a.jpg on every screen" ok probe theme-set "$browse/backgrounds/a.jpg|*"
expect_poll "the every-screen set reaches the fixture" '[3, "ok", "a.jpg", "*", null]' answer set state background screen reason
expect "an every-screen set makes a.jpg current" "\"$browse/backgrounds/a.jpg\"" bg_current
expect "an every-screen set clears the screen's own image" '{}' bg_screens
expect "a path no source holds is accepted" ok probe theme-set /nowhere/a.jpg
expect_poll "the runner's refusal reaches the fixture as the result" '[4, "failed", "outside"]' answer set state reason
rm -- "$bg_state/backgrounds.json" "$bg_state/background"

# wallpapers on the download lane: a real refusal, then a slow download
# behind a gate.
expect "a malformed name's download is refused at once" 'refused: wallpapers="../x" reason=malformed-name' probe theme-wallpapers ../x
expect "the fixture downloads a package that is no catalog install" ok probe theme-wallpapers browse
expect_poll "the runner's refusal reaches the fixture as the result" '[1, "failed", "browse", "not-catalog"]' answer wallpapers state theme reason
expect "no download runs after the refusal" null last_part downloading

download_gate="$(mktemp "$sandbox/theme-download-gate.XXXXXX")"
theme_browse_download_gate="$download_gate"
rm -- "$download_gate"
slow_download="$sandbox/slow-download"
cat >"$slow_download" <<SH
#!/usr/bin/env bash
# vgshell theme wallpapers --json NAME: two progress lines, the gate, a result.
printf '%s\n' '{"state":"downloading","bytes":0,"total":2000}' '{"state":"downloading","bytes":1000,"total":2000}'
for _ in \$(seq 1 600); do [[ -e $(printf %q "$download_gate") ]] && break; sleep 0.05; done
printf '{"state":"ok","theme":"%s","wallpapers":"installed","images":2,"sha256":null,"reason":null}\n' "\$4"
SH
chmod 755 -- "$slow_download"
stand_in_vgshell "[[ \${2:-} == wallpapers ]] && exec $(printf %q "$slow_download") \"\$@\""
# apply_during_download APPLIES DOWNLOADS: after a download started and an
# apply was asked for, poll every 200 ms for up to 5 s until APPLIES, a
# count of apply answers, rises: `answered` while DOWNLOADS, a count of
# download answers, has not, `download-ended` when it has, and `waiting`
# when the apply never answered.
apply_during_download() {
  local applies_before downloads_before
  applies_before="$1"; downloads_before="$2"; shift 2
  for _ in $(seq 1 25); do
    if [[ $("$1") -gt $applies_before ]]; then
      if [[ $("$2") -gt $downloads_before ]]; then echo download-ended; else echo answered; fi
      return
    fi
    sleep 0.2
  done
  echo waiting
}
fixture_downloads() { answers wallpapers; }
expect "the fixture starts a slow download" ok probe theme-wallpapers nord
expect_poll "the download's progress reaches last" '{"name": "nord", "state": "downloading", "bytes": 1000, "total": 2000}' last_part downloading
expect "a second download while one runs is refused at once" "refused: wallpapers=browse reason=busy" probe theme-wallpapers browse
expect "the lending record holds the download with the fixture waiting" '["wallpapers", "nord", 1]' theme_download
expect "the queue holds no job beside the download" '[]' theme_jobs
before_applies="$(applies)"; before_downloads="$(fixture_downloads)"
expect "an apply while the download runs is accepted" ok probe theme-apply vgs
expect "an apply completes while a slow download runs" answered apply_during_download "$before_applies" "$before_downloads" applies fixture_downloads
expect "the apply's result is the runner's" "unchanged unchanged vgs None" applied
expect "disabling the fixture during the download is allowed" ok ipc shell setPluginEnabled acme.probe false
expect_poll "the destroyed instance's download callback is dropped" '["wallpapers", "nord", 0]' theme_download
expect "re-enabling the fixture during the download is allowed" ok ipc shell setPluginEnabled acme.probe true
expect_poll "the fixture service is rebuilt during the download" True service_built
expect "the rebuilt instance reads the running download's progress" '{"name": "nord", "state": "downloading", "bytes": 1000, "total": 2000}' last_part downloading
touch -- "$download_gate"
expect_poll "the download completes without its instance" null theme_download
expect "last holds no download once it ends" null last_part downloading
expect "the rebuilt instance received no download callback" none answer wallpapers state

# The core directory was listed at startup. Put both controls in a fresh
# directory before loading either, so Qt's cached listing includes them.
runner_qml="$repo/shell/Core/ThemeRunner.qml"
theme_browse_controls="$(mktemp -d "$repo/shell/Core/ThemeBrowseControls.XXXXXX")"
update_copy="$theme_browse_controls/ThemeRunnerNoUpdate.qml"
runner_copy="$theme_browse_controls/ThemeRunnerQueuedDownloads.qml"
python3 - "$runner_qml" "$update_copy" "$runner_copy" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
relative_import = 'import "../Commons/ThemeLogic.js" as ThemeLogic'
assert source.count(relative_import) == 1
source = source.replace(relative_import, 'import "../../Commons/ThemeLogic.js" as ThemeLogic')
for path, old, new in [
    (sys.argv[2], 'return ["wallpapers", "--json", name].concat(extra);', 'return ["wallpapers", "--json", name];'),
    (sys.argv[3], '        startDownload(job);', '        enqueue(job);'),
]:
    assert source.count(old) == 1
    changed = source.replace(old, new)
    assert changed != source
    with Path(path).open("x") as file:
        file.write(changed)
PY
# Control: a copy whose wallpapers member queues the download on the
# queue, driven through the same row, holds its apply behind the download.
# Its lending record shows the apply queued behind the download, and
# apply_during_download, which the real runner answers `answered`, polls
# its 5 s out on the copy.
if [[ -f $runner_copy ]]; then
  copy_applies() { ipc smoke runnerAnswered apply; }
  copy_downloads() { ipc smoke runnerAnswered wallpapers; }
  copy_queue() { ipc smoke runnerRecord | py_reply 'import json,sys; d=json.load(sys.stdin); print(json.dumps([[j["verb"] for j in d["jobs"]], d["download"]]))'; }
  rm -- "$download_gate"
  expect "the queued-downloads copy differs from the runner" 1 bash -c 'cmp -s -- "$1" "$2"; echo $?' _ "$runner_qml" "$runner_copy"
  expect "the smoke probe builds the queued-downloads copy" ok ipc smoke runnerLoad "$runner_copy"
  expect "the copy starts a slow download" ok ipc smoke runnerCall wallpapers nord
  expect "the copy accepts an apply while its download runs" ok ipc smoke runnerCall apply vgs
  expect_poll "the copy queues its apply behind its download" '[["wallpapers", "apply"], null]' copy_queue
  expect "the copy's apply waits behind its download" waiting apply_during_download 0 0 copy_applies copy_downloads
  touch -- "$download_gate"
  expect_poll "the copy's download ends once the gate opens" 1 copy_downloads
  expect_poll "the copy's apply ends after its download" 1 copy_applies
  expect "the smoke probe drops the copy" ok ipc smoke runnerDrop
  rm -- "$runner_copy"
fi

# The update form: `{ update: true }` after the callback reaches the runner
# as --update, and options no runner call can take are refused at once. A
# stand-in records each download's arguments and answers at once.
download_argv="$sandbox/download-argv"
stand_in_vgshell "if [[ \${2:-} == wallpapers ]]; then
  printf '%s\n' \"\$*\" >$(printf %q "$download_argv")
  printf '{\"state\":\"ok\",\"theme\":\"%s\",\"wallpapers\":\"updated\",\"images\":2,\"sha256\":null,\"reason\":null}\n' \"\$4\"
  exit 0
fi"
expect "malformed download options are refused at once" 'refused: wallpapers={"update":"yes"} reason=malformed-options' probe theme-wallpapers-with 'nord|{"update":"yes"}'
expect "the update form is accepted" ok probe theme-wallpapers-with 'nord|{"update":true}'
expect_poll "the update's result reaches the fixture" '[1, "ok", "updated"]' answer wallpapers state wallpapers
expect "the update form runs the runner with --update" "theme wallpapers --json nord --update" cat "$download_argv"
expect "the form without update is accepted" ok probe theme-wallpapers-with 'nord|{}'
expect_poll "the plain download's result reaches the fixture" '[2, "ok"]' answer wallpapers state
expect "the form without update runs the runner without --update" "theme wallpapers --json nord" cat "$download_argv"
# Control: the copy of the runner whose wallpapers command drops its
# options' arguments runs the update form without --update.
if [[ -f $update_copy ]]; then
  rm -f -- "$download_argv"
  expect "the no-update copy differs from the runner" 1 bash -c 'cmp -s -- "$1" "$2"; echo $?' _ "$runner_qml" "$update_copy"
  expect "the smoke probe builds the no-update copy" ok ipc smoke runnerLoad "$update_copy"
  expect "the no-update copy accepts the update form" ok ipc smoke runnerCallWith wallpapers nord '{"update":true}'
  expect_poll "the no-update copy's download ends" 1 ipc smoke runnerAnswered wallpapers
  expect "the no-update copy runs the update form without --update" "theme wallpapers --json nord" cat "$download_argv"
  expect "the smoke probe drops the no-update copy" ok ipc smoke runnerDrop
  rm -- "$update_copy"
fi
theme_browse_controls_path="$theme_browse_controls"
theme_browse_controls_cleanup
expect "the runner controls release their private directory" absent bash -c '[[ -e $1 ]] && echo present || echo absent' _ "$theme_browse_controls_path"
rm -f -- "$download_argv"
restore_vgshell

# A runner that prints no result answers each member as a failure of its
# own shape.
stand_in_vgshell 'echo "no result"; exit 2'
expected_errors+=(
  'theme: vgshell theme catalog reason=output-unreadable exit=2 '
  'theme: vgshell theme install reason=output-unreadable name=nord exit=2 '
  'theme: vgshell theme images reason=output-unreadable name=all exit=2 '
  'theme: vgshell theme set reason=output-unreadable name=/nowhere/a.jpg exit=2 '
  'theme: vgshell theme wallpapers reason=output-unreadable name=nord exit=2 '
)
expect "a catalog whose runner prints no result is accepted" ok probe theme-catalog
expect_poll "the unreadable catalog is a failure with its reason" '[1, null, "output-unreadable"]' answer catalog entries reason
expect "an install whose runner prints no result is accepted" ok probe theme-install nord
expect_poll "the unreadable install is a failure with its reason" '[1, "failed", "nord", null, "output-unreadable"]' answer install state theme path reason
expect "an image list whose runner prints no result is accepted" ok probe theme-images all
expect_poll "the unreadable image list is a failure with its reason" '[1, "failed", null, "output-unreadable"]' answer images state images reason
expect "a set whose runner prints no result is accepted" ok probe theme-set /nowhere/a.jpg
expect_poll "the unreadable set is a failure with its reason" '[1, "failed", null, null, "output-unreadable"]' answer set state path screen reason
expect "a download whose runner prints no result is accepted" ok probe theme-wallpapers nord
expect_poll "the unreadable download is a failure with its reason" '[3, "failed", "nord", null, "output-unreadable"]' answer wallpapers state theme wallpapers reason
restore_vgshell

theme_browse_cleanup
smoke_row_abandon=()
