# xdph selections, live previews and public ScreenCast application requests
# run in the nested compositor with an isolated bus and device-free PipeWire.
# No latency ceiling. State readbacks poll every 200 ms through expect_poll.
# inputs: shell/plugins/vgs.capture/* shell/plugins/vgs.settings/* shell/Core/qmldir shell/Core/ScreencopyPreview.qml shell/Core/Capabilities.qml shell/Core/IpcRegistry.qml shell/Hosts/AppWindow.qml shell/Hosts/SummonHost.qml shell/Hosts/PluginSlot.qml shell/Commons/* shell/Ui/* bin/vgshell-share-picker bin/vgshell bin/lib/ipc-reply.sh scripts/smoke/fixtures/share-picker/* scripts/smoke/fixtures/plugins/acme.screencopy/* themes/catalog/flexoki-light/theme.json
set -euo pipefail
for share_required in /usr/lib/xdg-desktop-portal /usr/lib/xdg-desktop-portal-hyprland /usr/lib/xdg-permission-store /usr/bin/hyprland-share-picker /usr/bin/bwrap; do
  if [[ ! -x $share_required ]]; then not_measured share-picker missing="$share_required"; return 0; fi
done
if ! pkg-config --exists libpipewire-0.3 || ! python3 -c 'import gi; from gi.repository import Gio, GLib; from PIL import Image, ImageDraw, ImageFont' >/dev/null 2>&1; then
  not_measured share-picker missing=portal-client-libraries; return 0
fi
share_world="$sandbox/share-picker"
share_fixture="$source_repo/scripts/smoke/fixtures/share-picker"
share_evidence="$source_repo/tmp/share-picker-evidence"
mkdir -p -- "$share_world" "$share_evidence"
cp -- "$home/.config/vgshell/shell.json" "$share_world/shell.saved"
share_theme="$home/.config/vgshell/theme.json"
share_theme_initial_name="$(ipc smoke themeName)"
share_theme_initial_state="$(ipc smoke themeValue fileState)"
share_border() { hypr -j getoption general:col.inactive_border | py_reply 'import json,sys; print(json.load(sys.stdin)["gradient"])'; }
share_border_initial="$(share_border)"
[[ ! -f $share_theme ]] || cp -- "$share_theme" "$share_world/theme.saved"
share_read() { ipc smoke readInstance window vgs.capture "$1"; }
share_arg() { ipc smoke invokeInstance window vgs.capture "$1" "${2:-}" >/dev/null; }
share_args() { ipc smoke invokeInstanceArgs window vgs.capture "$1" "$2" >/dev/null; }
share_mapped() { ipc smoke instanceGeometry window vgs.capture | py_reply 'import json,sys; s=sys.stdin.read().strip(); print(s != "absent" and len(json.loads(s)) == 4)'; }
share_request_id() { share_read request | py_reply 'import json,sys; s=sys.stdin.read().strip(); d={} if s=="absent" else json.loads(s); print(d.get("id", ""))'; }
share_new_request() { share_read request | py_reply 'import json,sys; s=sys.stdin.read().strip(); d={} if s=="absent" else json.loads(s); print(isinstance(d.get("id"),str) and bool(d["id"]) and d["id"]!=sys.argv[1] and (len(sys.argv)==2 or any(w.get("id")=="73" for w in d.get("windows",[]))))' "$@"; }
share_exit() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(p.read_text() if p.exists() else "pending")' "$share_world/$1.exit"; }
share_stdout() { cat -- "$share_world/$1.out"; }
share_cancelled() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); e=p.with_suffix(".exit"); o=p.with_suffix(".out"); print(e.exists() and e.read_text() not in ("0","124") and o.exists() and o.read_bytes()==b"")' "$share_world/$1"; }
share_launch() { # NAME [--allow-token]
  share_previous="$(share_request_id)"
  spawn "$share_world/$1.log" "${shell_env[@]}" PATH="$shell_start_path" XDPH_WINDOW_SHARING_LIST="$share_window_list" python3 "$share_fixture/run-picker.py" "$share_world/$1" "$repo/bin/vgshell-share-picker" "${@:2}"
  expect_poll "$1: the executable opens a new VGS request" True share_new_request "$share_previous" fixture
}
share_set_region() {
  share_args setRegion '{"args":["x",32]}'; share_args setRegion '{"args":["y",48]}'
  share_args setRegion '{"args":["width",160]}'; share_args setRegion '{"args":["height",120]}'
}
share_click() { click_in window:Capture window vgs.capture "$1" "$2" || fail "share-picker: clicking $1 failed"; }
share_result() { ipc vgs.capture invoke share-result "{\"id\":\"$1\"}"; }
share_replacement_released() {
  if [[ $(share_result "$1") == cancelled && $(share_cancelled "$2") == True ]]; then echo True; else echo False; fi
}
share_replacement_check() { expect "ordinary Open releases the matching picker without a selection" True share_replacement_released "$1" "$2"; }
expect "capture enables for sharing" ok ipc shell setPluginEnabled vgs.capture true
expect_poll "capture's service is built" True record_exists vgs.capture
if [[ $(notice_shown) != null ]]; then
  expect_poll "the optional capture tools notice has the keyboard" true ipc smoke noticeFocused
  type_keys -k Escape || fail "share-picker: declining unrelated tool setup failed"
  expect_poll "the unrelated tools notice closes before sharing" null notice_shown
fi
share_unconfigured() { [[ ! -e $home/.config/hypr/xdph.conf ]] && echo absent || echo present; }
expect "enabling Capture leaves portal setup for the user's action" absent share_unconfigured
expect "Settings enables for the sharing setup path" ok ipc shell setPluginEnabled vgs.settings true
expect_poll "Settings is built for the setup path" True record_exists vgs.settings
expect "Settings opens Capture's page" ok ipc shell summon window vgs.settings '{"plugin":"vgs.capture"}'
expect_poll "Settings shows Capture's page" '"vgs.capture"' ipc smoke readInstance window vgs.settings page
expect_poll "Settings offers the sharing setup action" true ipc smoke readMatchingDescendant window vgs.settings Button text "Set up screen sharing" enabled
expect "Settings hides after its setup route assertion" ok ipc shell hide window vgs.settings
expect "ordinary Capture Open summons its controls" ok ipc shell summon window vgs.capture '{}'
expect_poll "ordinary Capture Open selects the capture controls" false share_read sharing
expect_poll "ordinary Capture Open exposes the screenshot action" true ipc smoke readMatchingDescendant window vgs.capture Button text "Take screenshot" enabled
expect "ordinary Capture Open hides" ok ipc shell hide window vgs.capture
open_toplevel "$share_world/target.log" smoke.share-target "Share target" || { fail "share-picker: target did not map"; return 0; }
share_target_pid="$toplevel_pid"
share_target_address="$(toplevel_address "$share_target_pid")"
expect "the target floats inside the selected output" ok hypr dispatch "hl.dsp.window.float({ action = \"enable\", window = \"address:$share_target_address\" })"
expect "the target gets a distinct frame size" ok hypr dispatch "hl.dsp.window.resize({ x = 480, y = 320, relative = false, window = \"address:$share_target_address\" })"
expect "the target moves away from the output origin" ok hypr dispatch "hl.dsp.window.move({ x = 80, y = 100, relative = false, window = \"address:$share_target_address\" })"
share_target_geometry() { hypr -j clients | py_reply 'import json,sys; d=next(c for c in json.load(sys.stdin) if c["class"]=="smoke.share-target"); print(d["floating"] and d["size"]==[480,320] and d["at"]==[80,100])'; }
expect_poll "the target frame is distinct from the whole output" True share_target_geometry
share_target_decimal="$(python3 -c 'import sys; print(int(sys.argv[1],16))' "$share_target_address")"
share_window_list="73[HC>]smoke.share-target[HT>]Share target[HE>]${share_target_decimal}[HA>]"
share_output="$(hypr -j monitors | py_reply 'import json,sys; print(next(m["name"] for m in json.load(sys.stdin) if m["width"]>0 and m["height"]>0))')"
share_preview_dir="$home/.config/vgshell/plugins/acme.screencopy"
mkdir -p -- "$share_preview_dir"
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.screencopy/." "$share_preview_dir/"
rescan "the preview fixture enters the registry"
expect "the preview fixture enables" ok ipc shell setPluginEnabled acme.screencopy true
expect "the core lends a screen preview" ok ipc shell summon window acme.screencopy "{\"output\":\"$share_output\"}"
expect_poll "the lent preview receives a frame" true ipc smoke readInstance window acme.screencopy hasContent
expect "the preview fixture hides" ok ipc shell hide window acme.screencopy
expect "the preview fixture disables" ok ipc shell setPluginEnabled acme.screencopy false
rm -rf -- "${share_preview_dir:?}"
rescan "the preview fixture leaves the registry"
# The control keeps the mapped request but prevents its replacement from
# notifying the request owner. It must build before the cancellation check.
cp -- "$repo/shell/plugins/vgs.capture/Window.qml" "$share_world/window.saved"
python3 - "$repo/shell/plugins/vgs.capture/Window.qml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); assert not p.is_symlink()
s=p.read_text(); a='if (sharing && request.id !== next.id) close();'
assert s.count(a)==1
changed=s.replace(a,'if (false && sharing && request.id !== next.id) close();',1)
assert changed != s
p.write_text(changed)
PY
rescan "the replacement control enters the registry"
share_launch control-replacement
share_replacement_id="$(share_request_id)"
expect_poll "the replacement control maps the picker" True share_mapped
expect "the replacement control is a sharing request" true share_read sharing
share_arg switchTab 1
expect "ordinary Open replaces the control picker" ok ipc shell summon window vgs.capture '{}'
expect_poll "ordinary Open leaves the control's normal capture controls visible" false share_read sharing
expect_poll "the control's normal screenshot action builds" true ipc smoke readMatchingDescendant window vgs.capture Button text "Take screenshot" enabled
expect "control: the matching request remains pending" pending share_result "$share_replacement_id"
share_replacement_control() {
  (failures=0 behaviour_failures=0
   share_replacement_check "$share_replacement_id" control-replacement >"$share_world/replacement-control.log"
   echo "$failures")
}
expect "control: omitting replacement cancellation fails the same release check" 1 share_replacement_control
cat -- "$share_world/replacement-control.log"
expect "the control's pending request is cancelled for cleanup" ok ipc vgs.capture invoke share-cancel "{\"id\":\"$share_replacement_id\"}"
expect_poll "the control's executable exits without a selection" True share_cancelled control-replacement
cp -- "$share_world/window.saved" "$repo/shell/plugins/vgs.capture/Window.qml"
rescan "the replacement cancellation is restored"
share_launch replacement
share_replacement_id="$(share_request_id)"
share_arg switchTab 1
expect "ordinary Open replaces the pending picker" ok ipc shell summon window vgs.capture '{}'
expect_poll "ordinary Open keeps the normal capture controls visible" false share_read sharing
expect_poll "ordinary Open keeps the screenshot action available" true ipc smoke readMatchingDescendant window vgs.capture Button text "Take screenshot" enabled
expect_poll "ordinary Open cancels the waiting executable without stdout" True share_cancelled replacement
share_replacement_check "$share_replacement_id" replacement
share_launch after-replacement
expect "the next request has a new identifier" True share_new_request "$share_replacement_id" fixture
share_click Button Cancel
expect_poll "the next request can cancel independently" True share_cancelled after-replacement
share_launch keyboard
share_current_id="$(share_request_id)"
expect "control: an old request cannot satisfy a new caller" False share_new_request "$share_current_id" fixture
rest_pointer || fail "share-picker: parking pointer for keyboard failed"
expect_poll "the tab control has the keyboard" true ipc smoke readDescendant window vgs.capture SegmentedControl activeFocus
type_keys -k Right || fail "share-picker: Right failed"
expect_poll "Right selects Windows" 1 share_read tab
type_keys -k Right || fail "share-picker: second Right failed"
expect_poll "Right selects Area" 2 share_read tab
type_keys -k Left || fail "share-picker: Left failed"
expect_poll "Left returns to Windows" 1 share_read tab
type_keys -k Left || fail "share-picker: second Left failed"
expect_poll "Left returns to Screens" 0 share_read tab
type_keys -k Right -k Right -k Tab -k Tab || fail "share-picker: reaching Area's first slider failed"
expect_poll "Tab reaches the first Area slider" true ipc smoke readDescendant window vgs.capture Slider activeFocus
type_keys -k Up || fail "share-picker: changing the Area slider failed"
share_region_x() { share_read region | py_reply 'import json,sys; print(json.load(sys.stdin)["x"])'; }
expect_poll "the keyboard changes the shared area's left edge" 1 share_region_x
type_keys -k Escape || fail "share-picker: keyboard cancellation failed"
expect_poll "the keyboard request cancels" True share_cancelled keyboard
for share_choice in screens windows area; do
  share_launch "$share_choice" --allow-token
  expect "the token flag checks Remember" true share_read remember
  case $share_choice in
    screens) share_expected="[SELECTION]r/screen:$share_output";;
    windows) share_arg switchTab 1; expect_poll "the window preview has content" true share_read previewReady; share_expected='[SELECTION]r/window:73';;
    area) share_arg switchTab 2; share_set_region; share_expected="[SELECTION]r/region:$share_output@32,48,160,120";;
  esac
  share_click Button Share
  expect_poll "$share_choice: the executable succeeds" 0 share_exit "$share_choice"
  expect "$share_choice: xdph receives the chosen source" "$share_expected" share_stdout "$share_choice"
done
share_launch remember-off
expect "Remember starts unchecked without a token flag" false share_read remember
share_click Checkbox "Remember this choice"
expect_poll "the user enables Remember" true share_read remember
share_click Checkbox "Remember this choice"
expect_poll "the user disables Remember" false share_read remember
share_click Button Share
expect_poll "the unchecked picker succeeds" 0 share_exit remember-off
expect "the unchecked choice has no remember flag" "[SELECTION]/screen:$share_output" share_stdout remember-off
for share_cancel in cancel escape; do
  share_launch "$share_cancel"
  if [[ $share_cancel == cancel ]]; then share_click Button Cancel; else type_keys -k Escape || fail "share-picker: Escape failed"; fi
  expect_poll "$share_cancel sends no selection" True share_cancelled "$share_cancel"
done
share_launch pending
spawn "$share_world/busy.log" "${shell_env[@]}" PATH="$shell_start_path" XDPH_WINDOW_SHARING_LIST="$share_window_list" python3 "$share_fixture/run-picker.py" "$share_world/busy" "$repo/bin/vgshell-share-picker"
expect_poll "a concurrent request receives no selection" True share_cancelled busy
expect "the first request stays open" True share_mapped
share_click Button Cancel
expect_poll "the first caller can cancel" True share_cancelled pending
# The disposable executable drops Remember. The same result assertion rejects it.
cp -- "$repo/bin/vgshell-share-picker" "$share_world/picker.saved"
python3 - "$repo/bin/vgshell-share-picker" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text(); a='("r" if choice["remember"] else "")'; assert s.count(a)==1; p.write_text(s.replace(a,'""',1))
PY
share_launch control-remember --allow-token
share_click Button Share
expect_poll "the control executable returns" 0 share_exit control-remember
share_matches() { [[ $(share_stdout "$1") == "$2" ]] && echo True || echo False; }
expect "control: dropping Remember fails the xdph assertion" False share_matches control-remember "[SELECTION]r/screen:$share_output"
cp -- "$share_world/picker.saved" "$repo/bin/vgshell-share-picker"
# The original picker sees private /tmp: upstream's QSettings path is fixed there.
SHOT_DIR="$(shot_dir_under "$source_repo" "$share_evidence")"
SHOT_SOCKET="$(shot_socket "$rt_dir" "$nested_socket" "$host_socket")"
SHOT_RUNTIME_DIR="$rt_dir"; SHOT_OUTPUT="$share_output"
mkdir -p -- "$home/.config/qt6ct"
share_before_count() { hypr -j clients | py_reply 'import json,os,sys
count=0
for client in json.load(sys.stdin):
    try:
        if client["mapped"] and os.getpgid(client["pid"])==int(sys.argv[1]): count+=1
    except ProcessLookupError: pass
print(count)' "$share_before_pid"; }
share_shot_state() {
  [[ $(notice_shown) == null ]] || { echo notice; return; }
  if [[ $share_shot_kind == before ]]; then
    [[ $(share_before_count) == 1 ]] && echo clear || echo absent
  else
    [[ $(share_read tab) == "$share_shot_tab" && $(share_read sharing) == true ]] && echo clear || echo wrong-tab
  fi
}
SHOT_CHROME_READER=share_shot_state; SHOT_CHROME_REQUIRE=clear
for share_mode in dark light; do
  if [[ $share_mode == dark ]]; then
    printf '{"schemaVersion":1,"name":"vgs","tokens":{}}\n' >"$share_theme.next"
    share_theme_name=vgs; share_qt_palette=darker
  else
    cp -- "$repo/themes/catalog/flexoki-light/theme.json" "$share_theme.next"
    share_theme_name=flexoki-light; share_qt_palette=simple
  fi
  mv -T -- "$share_theme.next" "$share_theme"
  expect_poll "the $share_mode picture theme publishes" "$share_theme_name" ipc smoke themeName
  printf '[Appearance]\ncolor_scheme_path=/usr/share/qt6ct/colors/%s.conf\ncustom_palette=true\nstyle=Fusion\n' "$share_qt_palette" >"$home/.config/qt6ct/qt6ct.conf"
  spawn "$share_world/$share_mode-before.log" "${shell_env[@]}" QT_QPA_PLATFORM=wayland QT_QPA_PLATFORMTHEME=qt6ct XDPH_WINDOW_SHARING_LIST="$share_window_list" bwrap --ro-bind / / --tmpfs /tmp --bind "$sandbox" "$sandbox" hyprland-share-picker --allow-token
  share_before_pid="$spawn_pid"
  expect_poll "the original picker maps in $share_mode" 1 share_before_count
  share_shot_kind=before
  shot "$share_mode-before" || fail "share-picker: Before $share_mode failed"
  kill -TERM -- -"$share_before_pid" 2>/dev/null || true
  wait "$share_before_pid" 2>/dev/null || true
  expect_poll "the original picker closes" 0 share_before_count
  share_launch "$share_mode-shots" --allow-token
  for share_tab in screens windows area; do
    case $share_tab in screens) share_shot_tab=0; share_arg switchTab 0;; windows) share_shot_tab=1; share_arg switchTab 1;; area) share_shot_tab=2; share_arg switchTab 2; share_set_region;; esac
    share_shot_kind=after
    expect_poll "$share_mode $share_tab has preview content" true share_read previewReady
    rest_pointer || fail "share-picker: parking pointer failed"
    shot "$share_mode-$share_tab" || fail "share-picker: After $share_mode $share_tab failed"
    if [[ $share_tab == area ]]; then
      share_scroll_bottom() { ipc smoke scrollTo window vgs.capture 100000 | py_reply 'import json,sys; s=sys.stdin.read().strip(); print(s.startswith("[") and len(json.loads(s))==3)'; }
      expect "the Area controls scroll into view" True share_scroll_bottom
      shot "$share_mode-area-controls" || fail "share-picker: After $share_mode Area controls failed"
    fi
  done
  share_click Button Cancel
  expect_poll "the pictured request cancels" True share_cancelled "$share_mode-shots"
done
unset SHOT_CHROME_READER SHOT_CHROME_REQUIRE
python3 "$share_fixture/sheets.py" "$share_evidence" || fail "share-picker: picture labels failed"
cc -Wall -Wextra -Werror "$share_fixture/consume.c" -o "$share_world/consume" $(pkg-config --cflags --libs libpipewire-0.3) || { fail "share-picker: consumer build failed"; return 0; }
mkdir -p -- "$home/.config/xdg-desktop-portal"
printf '[preferred]\ndefault=hyprland\n' >"$home/.config/xdg-desktop-portal/portals.conf"
printf 'screencopy {\n custom_picker_binary = %s\n force_shm = 1\n}\n' "$repo/bin/vgshell-share-picker" >"$home/.config/hypr/xdph.conf"
share_portal_env=("${shell_env[@]}" PATH="$shell_start_path" XDG_CURRENT_DESKTOP=Hyprland PIPEWIRE_RUNTIME_DIR="$rt_dir" PIPEWIRE_REMOTE=pipewire-0 PIPEWIRE_CONFIG_DIR="$share_fixture")
spawn "$share_world/pipewire.log" "${share_portal_env[@]}" pipewire -c "$share_fixture/pipewire.conf"
share_pipewire_pid="$spawn_pid"
share_pipewire_ready() { [[ -S $rt_dir/pipewire-0 ]] && echo ready || echo pending; }
expect_poll "isolated PipeWire owns its socket" ready share_pipewire_ready
spawn "$share_world/permission-store.log" "${share_portal_env[@]}" /usr/lib/xdg-permission-store
share_permissions_pid="$spawn_pid"
spawn "$share_world/backend.log" "${share_portal_env[@]}" /usr/lib/xdg-desktop-portal-hyprland
share_backend_pid="$spawn_pid"
share_name() { "${share_portal_env[@]}" gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.NameHasOwner "$1"; }
expect_poll "xdph owns the nested bus name" '(true,)' share_name org.freedesktop.impl.portal.desktop.hyprland
spawn "$share_world/portal.log" "${share_portal_env[@]}" /usr/lib/xdg-desktop-portal
share_frontend_pid="$spawn_pid"
expect_poll "the public portal owns the nested bus name" '(true,)' share_name org.freedesktop.portal.Desktop
share_app_phase() { python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); print(p.read_text() if p.exists() else "pending")' "$share_world/app-$1.phase"; }
share_app_start() {
  share_previous="$(share_request_id)"
  spawn "$share_world/app-$1.log" "${share_portal_env[@]}" timeout 90 python3 "$share_fixture/portal-client.py" "$share_world/app-$1" "$share_world/consume" "${@:2}"
}
share_app_source() { python3 - "$share_world/app-$1.json" "$2" "$3" "$4" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()) if p.exists() else {}; rows=d.get("streams",[])
print(d.get("response")==0 and len(rows)==1 and rows[0][1].get("source_type")==int(sys.argv[2]) and rows[0][1].get("size")==[int(sys.argv[3]),int(sys.argv[4])])
PY
}
share_app_pixels() { python3 - "$share_world/app-$1.ppm" "${2:-40}" "${3:-40}" <<'PY'
import pathlib,sys
from PIL import Image
p=pathlib.Path(sys.argv[1]); print(p.exists() and Image.open(p).convert("RGB").getpixel((int(sys.argv[2]),int(sys.argv[3])))==(51,102,153))
PY
}
share_target_local() { hypr -j clients | py_reply 'import json,sys; d=next(c for c in json.load(sys.stdin) if c["class"]=="smoke.share-target"); print(d["at"][0]+32,d["at"][1]+48)'; }
share_mapping() { python3 -c 'import json,pathlib,sys; p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()) if p.exists() else {}; r=d.get("streams",[]); print(len(r)==1 and r[0][1].get("mapping_id")==sys.argv[2])' "$share_world/app-screen.json" "$share_output"; }
for share_app in screen window area cancel; do
  share_app_start "$share_app"
  expect_poll "the app's $share_app request opens a new VGS request" True share_new_request "$share_previous"
  case $share_app in
    screen)
      share_click Checkbox "Remember this choice"
      share_app_size="$(share_read current | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["width"],d["height"])')"
      read -r share_app_w share_app_h <<<"$share_app_size"; share_app_type=1;;
    window)
      share_arg switchTab 1
      share_index="$(share_read rows | py_reply 'import json,sys; print(next((i for i,w in enumerate(json.load(sys.stdin)) if w["class"]=="smoke.share-target"),"absent"))')"
      [[ $share_index != absent ]] || { fail "share-picker: target absent from xdph list"; continue; }
      share_arg select "$share_index"
      share_app_size="$(hypr -j clients | py_reply 'import json,sys; d=next(c for c in json.load(sys.stdin) if c["class"]=="smoke.share-target"); print(*d["size"])')"
      read -r share_app_w share_app_h <<<"$share_app_size"; share_app_type=2;;
    area)
      share_arg switchTab 2
      read -r share_area_x share_area_y <<<"$(share_target_local)"
      share_args setRegion "{\"args\":[\"x\",$share_area_x]}"
      share_args setRegion "{\"args\":[\"y\",$share_area_y]}"
      share_args setRegion '{"args":["width",160]}'
      share_args setRegion '{"args":["height",120]}'
      share_app_w=160; share_app_h=120; share_app_type=4;;
    cancel) share_click Button Cancel;;
  esac
  if [[ $share_app == cancel ]]; then expect_poll "the app receives cancellation" cancelled share_app_phase "$share_app"; else
    share_click Button Share
    expect_poll "the app consumes the $share_app frame" complete share_app_phase "$share_app"
    expect "the app receives $share_app type and dimensions" True share_app_source "$share_app" "$share_app_type" "$share_app_w" "$share_app_h"
    if [[ $share_app == window ]]; then expect "the window stream contains the target frame" True share_app_pixels "$share_app"; fi
    if [[ $share_app == area ]]; then expect "the area stream contains the selected target pixels" True share_app_pixels "$share_app"; fi
    if [[ $share_app == screen ]]; then
      expect "the screen stream names the selected output" True share_mapping
      read -r share_screen_x share_screen_y <<<"$(share_target_local)"
      expect "the screen stream contains the selected output's target" True share_app_pixels "$share_app" "$share_screen_x" "$share_screen_y"
      expect "the screen stream keeps the output outside the target" False share_app_pixels "$share_app" 40 140
    fi
  fi
done
share_has_token() { python3 -c 'import json,pathlib,sys; p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()) if p.exists() else {}; print(isinstance(d.get("restore_token"),str) and bool(d["restore_token"]))' "$share_world/app-screen.json"; }
expect "Remember returns a restore token" True share_has_token
if [[ $(share_has_token) == True ]]; then
  share_app_start restore "$share_world/app-screen.json"
  expect_poll "the app reuses the remembered screen" complete share_app_phase restore
  share_picker_count() { hypr -j clients | py_reply 'import json,sys; print(sum(c["mapped"] and c["title"]=="Capture" for c in json.load(sys.stdin)))'; }
  expect "the remembered source opens no picker" 0 share_picker_count
fi
cp -R -- "$share_world/." "$share_evidence/runtime"
for share_process in "$share_frontend_pid" "$share_backend_pid" "$share_permissions_pid" "$share_pipewire_pid"; do kill -TERM -- -"$share_process" 2>/dev/null || true; wait "$share_process" 2>/dev/null || true; done
close_toplevel "$share_target_pid" "the share target closes"
rm -rf -- "${home:?}/.config/qt6ct" "${home:?}/.config/xdg-desktop-portal"
rm -f -- "${home:?}/.config/hypr/xdph.conf"
if [[ -f $share_world/theme.saved ]]; then cp -- "$share_world/theme.saved" "$share_theme.next"; mv -T -- "$share_theme.next" "$share_theme"; else rm -f -- "${share_theme:?}"; fi
expect_poll "the picture theme restores its original file state" "$share_theme_initial_state" ipc smoke themeValue fileState
expect_poll "the picture theme restores its original name" "$share_theme_initial_name" ipc smoke themeName
expect_poll "the picture theme restores Hyprland's border" "$share_border_initial" share_border
cp -- "$share_world/shell.saved" "$home/.config/vgshell/shell.json.next"
mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
