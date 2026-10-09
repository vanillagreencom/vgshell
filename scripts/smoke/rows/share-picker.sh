# xdph selections, live previews and public ScreenCast application requests
# run in the nested compositor with an isolated bus and device-free PipeWire.
# No latency ceiling. State readbacks poll every 200 ms through expect_poll.
# inputs: shell/plugins/vgs.capture/* shell/plugins/vgs.settings/* shell/Core/qmldir shell/Core/ScreencopyPreview.qml shell/Core/Capabilities.qml shell/Core/IpcRegistry.qml shell/Hosts/AppWindow.qml shell/Hosts/SummonHost.qml shell/Hosts/PluginSlot.qml shell/Commons/* shell/Ui/* bin/vgshell-share-picker bin/vgshell bin/lib/ipc-reply.sh scripts/smoke/fixtures/share-picker/* scripts/smoke/fixtures/plugins/acme.screencopy/* scripts/smoke/toplevel/* themes/catalog/flexoki-light/theme.json
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
share_tabs_span() {
  ipc smoke descendantGeometry window vgs.capture | py_reply 'import json,sys
rows=json.load(sys.stdin); strip=next(r for r in rows if r["type"]=="Tabs"); tabs=[r for r in rows if r["type"] in ("TabButton","QQuickTabButton")]
hint=next(r for r in rows if r["type"]=="Label" and r.get("role")=="hint" and r["visible"])
print(len(tabs)==3 and abs(strip["box"][2]-hint["box"][2])<1 and all(abs(t["box"][2]-tabs[0]["box"][2])<1 for t in tabs) and abs(tabs[-1]["box"][0]+tabs[-1]["box"][2]-strip["box"][0]-strip["box"][2])<1)'
}
share_tabs_width_check() { expect "the page tabs fill the content width equally" True share_tabs_span; }
share_area_fits() {
  local rows scroll aspect current window monitor border
  rows="$(ipc smoke descendantGeometry window vgs.capture)" || return
  scroll="$(ipc smoke itemValues window vgs.capture ScrollArea contentY,contentHeight,height)" || return
  aspect="$(share_read previewRect)" || return
  current="$(share_read current)" || return
  window="$(surface_box window:Capture)" || return
  monitor="$(hypr -j monitors)" || return
  border="$(window_border_size)" || return
  python3 - "$rows" "$scroll" "$aspect" "$current" "$window" "$monitor" "$border" <<'PY'
import json,sys
rows,scroll,aspect,current,window,monitors,border=map(json.loads,sys.argv[1:])
monitor=next(m for m in monitors if m['name']==current['name'])
left,top,right,bottom=monitor['reserved']
room=[monitor['x']+left,monitor['y']+top,monitor['width']/monitor['scale']-left-right,monitor['height']/monitor['scale']-top-bottom]
frame=[window[0]-border,window[1]-border,window[2]+2*border,window[3]+2*border]
preview=next(r for r in rows if r['type']=='ScreencopyPreview')
image_index=rows[preview['parent']]['parent']; image=rows[image_index]
viewport=next(r for r in rows if r['type']=='ScrollArea' and r['visible'])
actions=[r for r in rows if r['type']=='Button' and r.get('text') in ('Cancel','Share') and r['visible']]
sliders=[r for r in rows if r['type']=='Slider' and r['visible']]
selection=[r for r in rows if r['parent']==image_index and r['type']=='QQuickRectangle' and r['visible']]
hint=next(r for r in rows if r['type']=='Label' and r.get('role')=='hint' and r['visible'])
def inside(a,b):
    x,y,w,h=a; X,Y,W,H=b
    return w>0 and h>0 and x>=X-1 and y>=Y-1 and x+w<=X+W+1 and y+h<=Y+H+1
print(len(actions)==2 and len(sliders)==4 and len(selection)==1
      and inside(frame,room)
      and actions[0]['parent']==actions[1]['parent'] and inside(rows[actions[0]['parent']]['box'],rows[0]['box'])
      and all(inside(r['box'],rows[0]['box']) for r in [image,hint,*actions,*sliders])
      and all(inside(r['box'],viewport['box']) for r in [image,hint,*sliders])
      and inside(selection[0]['box'],image['box'])
      and aspect['width']>0 and aspect['height']>0
      and abs(aspect['width']/aspect['height']-current['width']/current['height'])<0.01
      and len(scroll)==1 and scroll[0]['contentY']==0 and scroll[0]['contentHeight']<=scroll[0]['height']+1)
PY
}
share_area_check() { expect "Area keeps the full preview, selection, sliders and actions without scrolling" True share_area_fits; }
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
# Count the request and preview objects VGS owns, separately from the
# compositor's managed sessions, which have no public count API.
share_owner_counts() {
  local request previews
  request="$(ipc smoke readDescendant service vgs.capture ShareSession session)" || return
  previews="$(ipc smoke itemValues window vgs.capture ScreencopyPreview hasContent)" || return
  python3 - "$request" "$previews" <<'PY'
import json,sys
try:
    request=json.loads(sys.argv[1]); previews=[] if sys.argv[2]=="absent" else json.loads(sys.argv[2])
except ValueError:
    print("unreadable"); raise SystemExit
if not (request is None or isinstance(request,dict)) or not isinstance(previews,list):
    print("unreadable"); raise SystemExit
print(json.dumps({"pickerRequests":int(request is not None),"previewOwners":len(previews)},sort_keys=True))
PY
}
share_owner_released() { expect_poll "$1: VGS releases its request and preview" '{"pickerRequests": 0, "previewOwners": 0}' share_owner_counts; }
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
expect_poll "Settings offers the sharing setup action" true ipc smoke readMatchingDescendant window vgs.settings RowAction text "Set up screen sharing" enabled
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
# Keep the shared toplevel fixture neutral; this second source has its own
# independently known colour and dimensions in the disposable sandbox.
python3 - "$repo/scripts/smoke/toplevel/toplevel.c" "$share_world/other.c" <<'PY'
import pathlib,sys
text=pathlib.Path(sys.argv[1]).read_text(); old='pixels[i] = 0xff336699;'
assert text.count(old)==1
pathlib.Path(sys.argv[2]).write_text(text.replace(old,'pixels[i] = 0xff993366;',1))
PY
cc -Wall -Wextra -Werror "$share_world/other.c" "$sandbox/xdg-shell-protocol.c" -I"$sandbox" -o "$share_world/other" $(pkg-config --cflags --libs wayland-client)
spawn "$share_world/other.log" "${shell_env[@]}" "$share_world/other" smoke.share-other "Other share target"
share_other_pid="$spawn_pid"
share_other_mapped() { hypr -j clients | py_reply 'import json,sys; print(any(c["class"]=="smoke.share-other" and c["mapped"] for c in json.load(sys.stdin)))'; }
expect_poll "the other preview source is live at the same time" True share_other_mapped
share_other_address="$(toplevel_address "$share_other_pid")"
expect "the other preview source floats" ok hypr dispatch "hl.dsp.window.float({ action = \"enable\", window = \"address:$share_other_address\" })"
expect "the other preview source has an independent size" ok hypr dispatch "hl.dsp.window.resize({ x = 240, y = 180, relative = false, window = \"address:$share_other_address\" })"
expect "the other preview source stays beside the target" ok hypr dispatch "hl.dsp.window.move({ x = 680, y = 100, relative = false, window = \"address:$share_other_address\" })"
share_other_geometry() { hypr -j clients | py_reply 'import json,sys; d=next(c for c in json.load(sys.stdin) if c["class"]=="smoke.share-other"); print(d["floating"] and d["size"]==[240,180] and d["at"]==[680,100])'; }
expect_poll "the second live source has the known frame" True share_other_geometry
expect "the first live source has the known pixels" 336699 pixel 120 140
expect "the second live source has different pixels" 993366 pixel 720 140
share_other_decimal="$(python3 -c 'import sys; print(int(sys.argv[1],16))' "$share_other_address")"
share_window_list+="74[HC>]smoke.share-other[HT>]Other share target[HE>]${share_other_decimal}[HA>]"
share_preview_size() { ipc smoke readDescendant window vgs.capture ScreencopyPreview sourceSize | py_reply 'import json,sys; s=sys.stdin.read().strip(); d=json.loads(s) if s.startswith("{") else {}; print([d.get("width"),d.get("height")])'; }
share_preview_identity() { expect "the selected window preview has its independent dimensions" '[480, 320]' share_preview_size; }
share_dismiss_notice() {
  if [[ $(notice_shown) != null ]]; then
    expect_poll "the restarted shell's requirement notice has focus" true ipc smoke noticeFocused
    type_keys -k Escape || fail "share-picker: declining restarted tool setup failed"
    expect_poll "the restarted shell's requirement notice closes" null notice_shown
  fi
}
share_control_start() { stop_shell || :; start_shell "$sandbox/tree-$1" "$share_world/$1-shell.log"; expect_poll "the $1 Capture service builds" True record_exists vgs.capture; share_dismiss_notice; }
share_control_restore() { stop_shell || :; start_shell "$repo" "$share_world/$1-restored.log"; expect_poll "the restored Capture service builds" True record_exists vgs.capture; share_dismiss_notice; }
copy_tree share-tabs-width-control
edit_tree share-tabs-width-control shell/plugins/vgs.capture/Window.qml $'width: pane.contentWidth\n            model: ["Screens", "Windows", "Area"]' $'width: Math.min(pane.contentWidth, Theme.control.maxWidth)\n            model: ["Screens", "Windows", "Area"]'
share_control_start share-tabs-width-control
share_launch control-tabs-width
expect_poll "the capped-tabs control maps" True share_mapped
share_tabs_width_control() { (failures=0 behaviour_failures=0; share_tabs_width_check >"$share_world/tabs-width-control.log"; echo "$failures"); }
expect "control: capped page tabs fail the same content-width assertion" 1 share_tabs_width_control
cat -- "$share_world/tabs-width-control.log"
share_click Button Cancel
expect_poll "the capped-tabs control caller cancels" True share_cancelled control-tabs-width
share_control_restore share-tabs-width-control
share_drag_plan() {
  local rows box current
  rows="$(ipc smoke descendantGeometry window vgs.capture)" || return
  box="$(surface_box window:Capture)" || return
  current="$(share_read current)" || return
  python3 - "$rows" "$box" "$current" "$share_world/drag-plan.json" <<'PY'
import json,math,pathlib,sys
rows,window,screen=map(json.loads,sys.argv[1:4])
preview=next(r for r in rows if r['type']=='ScreencopyPreview')
image=rows[rows[preview['parent']]['parent']]['box']; origin=rows[0]['box']
ox=window[0]+image[0]-origin[0]; oy=window[1]+image[1]-origin[1]
w,h=screen['width'],screen['height']; scale=min(image[2]/w,image[3]/h)
left=ox+(image[2]-w*scale)/2; top=oy+(image[3]-h*scale)/2
assert (image[2]-w*scale)/2>1 or (image[3]-h*scale)/2>1, 'preview must have fitted margins'
# This rectangle crosses the independently placed target's left/top edges.
# Integer virtual-pointer positions quantize it to the nearest output pixels.
points=[round(left+48*scale),round(top+68*scale),round(left+192*scale),round(top+220*scale)]
x,y,x2,y2=points
region=dict(x=math.floor((x-left)/scale),y=math.floor((y-top)/scale),width=math.floor((x2-x)/scale),height=math.floor((y2-y)/scale))
assert region['x']>0 and region['y']>0 and region['x']<80<region['x']+region['width'] and region['y']<100<region['y']+region['height']
pathlib.Path(sys.argv[4]).write_text(json.dumps(dict(points=points,expected=region,image=image,fitted=[left,top,w*scale,h*scale],screen=[w,h])))
print(*points)
PY
}
share_drag() {
  local plan x y x2 y2
  expect_poll "the fitted Area preview has content before pointer input" true share_read previewReady
  plan="$(share_drag_plan)" || { fail "share-picker: independent pointer plan failed"; return 1; }
  read -r x y x2 y2 <<<"$plan"
  drag "$x" "$y" "$x2" "$y2" || { fail "share-picker: the Area pointer drag failed"; return 1; }
}
share_drag_matches() { share_read region | py_reply 'import json,pathlib,sys; s=sys.stdin.read().strip(); d=json.loads(s) if s.startswith("{") else {}; print(d==json.loads(pathlib.Path(sys.argv[1]).read_text())["expected"])' "$share_world/drag-plan.json"; }
share_drag_check() { expect "the pointer drag selects the independent output rectangle" True share_drag_matches; }
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
copy_tree share-preview-control
edit_tree share-preview-control shell/Core/ScreencopyPreview.qml \
  'item.address === root.address.replace(/^0x/, "")' "item.address === \"${share_other_address#0x}\""
share_control_start share-preview-control
share_launch control-preview
share_arg switchTab 1
expect_poll "the wrong-window control maps a live preview" true share_read previewReady
expect_poll "the wrong-window control captures the other live fixture" '[240, 180]' share_preview_size
expect "the wrong-window control picker maps" True share_mapped
share_preview_control() { (failures=0 behaviour_failures=0; share_preview_identity >"$share_world/preview-control.log"; echo "$failures"); }
expect "control: the wrong live window fails the same preview identity assertion" 1 share_preview_control
cat -- "$share_world/preview-control.log"
share_click Button Cancel
expect_poll "the preview control caller cancels" True share_cancelled control-preview
share_control_restore share-preview-control
share_launch preview-identity
share_arg switchTab 1
expect_poll "the primary window preview has its independent dimensions" '[480, 320]' share_preview_size
share_preview_identity
share_arg select 1
expect_poll "selection changes to the other live window's dimensions" '[240, 180]' share_preview_size
share_arg select 0
expect_poll "selection returns to the primary window's dimensions" '[480, 320]' share_preview_size
share_preview_identity
share_click Button Cancel
expect_poll "the preview identity request cancels" True share_cancelled preview-identity
copy_tree share-drag-control
edit_tree share-drag-control shell/plugins/vgs.capture/Window.qml 'if (!pressed) return;' 'if (true || !pressed) return;'
share_control_start share-drag-control
share_launch control-drag
share_arg switchTab 2
expect_poll "the disabled-drag control picker maps" True share_mapped
share_drag
share_drag_control() { (failures=0 behaviour_failures=0; share_drag_check >"$share_world/drag-control.log"; echo "$failures"); }
expect "control: disabling drag mapping fails the same output rectangle assertion" 1 share_drag_control
cat -- "$share_world/drag-control.log"
share_click Button Cancel
expect_poll "the drag control caller cancels" True share_cancelled control-drag
share_control_restore share-drag-control
share_launch pointer-drag
share_arg switchTab 2
share_drag
expect_poll "the real pointer drag reaches the independent output rectangle" True share_drag_matches
share_drag_check
share_click Button Share
expect_poll "the pointer-selected executable succeeds" 0 share_exit pointer-drag
share_drag_stdout() { python3 - "$share_world/drag-plan.json" "$share_output" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))['expected']
print('[SELECTION]/region:'+sys.argv[2]+'@'+','.join(str(r[k]) for k in ('x','y','width','height')))
PY
}
share_pointer_expected="$(share_drag_stdout)"
expect "xdph receives the rectangle selected by pointer input" "$share_pointer_expected" share_stdout pointer-drag
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
expect_poll "the held picker has a live preview" true share_read previewReady
share_held_owner_control() { (failures=0 behaviour_failures=0; share_owner_released held-picker >"$share_world/held-owner-control.log"; echo "$failures"); }
expect "control: a retained picker fails the same request and preview release check" 1 share_held_owner_control
cat -- "$share_world/held-owner-control.log"
expect "control: an old request cannot satisfy a new caller" False share_new_request "$share_current_id" fixture
rest_pointer || fail "share-picker: parking pointer for keyboard failed"
expect_poll "the page tabs have the keyboard" true ipc smoke readDescendant window vgs.capture Tabs activeFocus
share_tabs_width_check
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
share_owner_released picker-closed
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
  share_owner_released "$share_choice-finished"
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
    expect "$share_mode $share_tab tabs span the content width" True share_tabs_span
    rest_pointer || fail "share-picker: parking pointer failed"
    shot "$share_mode-$share_tab" || fail "share-picker: After $share_mode $share_tab failed"
    if [[ $share_tab == area ]]; then
      share_area_check
      shot "$share_mode-area-controls" || fail "share-picker: After $share_mode Area controls failed"
    fi
  done
  share_arg switchTab 0
  type_keys -k Tab || fail "share-picker: picture Tab failed"
  type_keys -M shift -k Tab -m shift || fail "share-picker: picture Shift+Tab failed"
  share_shot_tab=0
  shot "$share_mode-keyboard-focus" || fail "share-picker: keyboard focus $share_mode failed"
  share_click Button Cancel
  expect_poll "the pictured request cancels" True share_cancelled "$share_mode-shots"
done
unset SHOT_CHROME_READER SHOT_CHROME_REQUIRE
python3 "$share_fixture/sheets.py" "$share_evidence" || fail "share-picker: picture labels failed"
# Reconstruct the pre-fix layout in a disposable tree. The same geometry
# assertion must reject its fixed-height request before the fit evidence.
copy_tree share-area-height-control
python3 - "$sandbox/tree-share-area-height-control/shell/plugins/vgs.capture/Window.qml" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); assert not p.is_symlink(); s=p.read_text()
old='implicitHeight: sharing ? sharingHeight - (compactArea ? 2 * (Theme.row.height + Theme.stack.row) : 0) : Theme.size.panel.maxHeight'
assert s.count(old)==1
s=s.replace(old,'implicitHeight: Theme.size.panel.maxHeight',1)
old='height: Math.min(Theme.size.panel.sm, width * 9 / 16)'
assert s.count(old)==1
s=s.replace(old,'height: Math.min(Theme.size.panel.sm, width * 9 / 16, Math.max(Theme.size.control.lg, pane.bodyRoom - hint.implicitHeight - sources.height - Theme.stack.group * 2))',1)
s=s.replace('Grid {\n                id: areaControls','Column {\n                id: areaControls',1)
s=s.replace('                columns: root.compactArea ? 2 : 1\n','',1)
s=s.replace('width: (areaControls.width - (areaControls.columns - 1) * areaControls.spacing) / areaControls.columns','width: areaControls.width',1)
assert s!=p.read_text(); p.write_text(s)
PY
share_area_evidence="$source_repo/tmp/ui-shots/VGS-1164"
SHOT_DIR="$(shot_dir_under "$source_repo" "$share_area_evidence")"
share_original_mode="$(first_mode)"
share_area_settle() { take_mode "$share_output" "$share_mode_size" 1 >/dev/null && rest_pointer; }
for share_size in standard minimum; do
  if [[ $share_size == standard ]]; then
    share_mode_size=1755x933
  else
    share_mode_size="$share_minimum_mode"
  fi
  hold_mode "Area evidence output" "$share_output" "$share_mode_size"
  for share_version in before after; do
    if [[ $share_version == before ]]; then share_control_start share-area-height-control; else share_control_restore share-area-height-control; fi
    for share_mode in dark light; do
      if [[ $share_mode == dark ]]; then
        printf '{"schemaVersion":1,"name":"vgs","tokens":{}}\n' >"$share_theme.next"; share_theme_name=vgs
      else
        cp -- "$repo/themes/catalog/flexoki-light/theme.json" "$share_theme.next"; share_theme_name=flexoki-light
      fi
      mv -T -- "$share_theme.next" "$share_theme"
      expect_poll "Area evidence publishes $share_mode" "$share_theme_name" ipc smoke themeName
      share_area_settle || { fail "share-picker: the Area output did not settle"; return 0; }
      share_launch "area-$share_size-$share_version-$share_mode"
      share_arg switchTab 2; share_set_region
      expect_poll "Area evidence preview builds" true share_read previewReady
      if [[ $share_version == before ]]; then
        share_area_control() { (failures=0 behaviour_failures=0; share_area_check >"$share_world/area-control-$share_size-$share_mode.log"; echo "$failures"); }
        expect "control: the old fixed height fails the same Area geometry assertion" 1 share_area_control
        cat -- "$share_world/area-control-$share_size-$share_mode.log"
        ipc smoke scrollTo window vgs.capture 100000 >/dev/null
      else
        share_area_check
        # Move each real slider with the keyboard and read all rectangles again.
        rest_pointer || fail "share-picker: parking Area pointer failed"
        type_keys -k Tab -k Tab || fail "share-picker: reaching Area sliders failed"
        for share_slider in x y width height; do
          type_keys -k Up || fail "share-picker: moving $share_slider failed"
          share_moved_value() { share_read region | py_reply 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$share_slider"; }
          case $share_slider in x) share_slider_value=33;; y) share_slider_value=49;; width) share_slider_value=161;; height) share_slider_value=121;; esac
          expect "the $share_slider slider moves its region edge" "$share_slider_value" share_moved_value
          share_area_check
          type_keys -k Tab || fail "share-picker: reaching the next slider failed"
        done
        if [[ $share_size == standard && $share_mode == dark ]]; then
          share_minimum_mode="$(share_read sharingHeight | py_reply 'import math,sys; gutter=2*float(sys.argv[3]); bar=float(sys.argv[5].split()[2]); margin=max(gutter,bar+2*float(sys.argv[6])); print("%dx%d" % (math.ceil(float(sys.argv[4])+gutter),math.ceil(float(sys.stdin.read())-2*(float(sys.argv[1])+float(sys.argv[2]))+margin)))' "$(ipc smoke themeValue row.height)" "$(ipc smoke themeValue stack.row)" "$(ipc smoke themeValue size.window.gutter)" "$(ipc smoke themeValue size.window.width)" "$(monitor_size)" "$(window_border_size)")"
          printf 'share-picker: minimum-output=%s full-area-height=%s\n' "$share_minimum_mode" "$(share_read sharingHeight)"
        fi
      fi
      ipc smoke descendantGeometry window vgs.capture >"$share_area_evidence/$share_size-$share_version-$share_mode-geometry.json"
      ipc smoke itemValues window vgs.capture ScrollArea contentY,contentHeight,height >"$share_area_evidence/$share_size-$share_version-$share_mode-scroll.json"
      rest_pointer || fail "share-picker: parking evidence pointer failed"
      shot_held "$share_size-$share_version-$share_mode" held_mode_state share_area_settle || fail "share-picker: Area evidence failed"
      type_keys -k Escape || fail "share-picker: closing Area evidence failed"
      expect_poll "Area evidence caller cancels" True share_cancelled "area-$share_size-$share_version-$share_mode"
    done
  done
  release_mode "Area evidence restores output" "$share_output" "$share_original_mode"
done
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
  share_app_pid="$spawn_pid"
}
# Isolated PipeWire has no device discovery. These are the portal's video
# source nodes, not Hyprland's retained managed screenshare sessions.
share_stream_count() { "${share_portal_env[@]}" pw-dump | py_reply 'import json,sys; rows=json.load(sys.stdin); print(sum(r.get("type")=="PipeWire:Interface:Node" and (r.get("info") or {}).get("props",{}).get("media.class")=="Video/Source" for r in rows))'; }
share_stream_released() { expect_poll "$1: the portal releases its video-source nodes" 0 share_stream_count; }
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
      expect_poll "the application-selected window has the matching preview" '[480, 320]' share_preview_size
      share_preview_identity
      share_app_w=480; share_app_h=320; share_app_type=2;;
    area)
      share_arg switchTab 2
      share_drag
      expect_poll "the application's pointer drag selects the independent output rectangle" True share_drag_matches
      share_drag_check
      share_app_size="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["expected"]; print(r["width"],r["height"])' "$share_world/drag-plan.json")"
      read -r share_app_w share_app_h <<<"$share_app_size"; share_app_type=4;;
    cancel) share_click Button Cancel;;
  esac
  if [[ $share_app == cancel ]]; then expect_poll "the app receives cancellation" cancelled share_app_phase "$share_app"; else
    share_click Button Share
    expect_poll "the app consumes the $share_app frame" complete share_app_phase "$share_app"
    expect "the app receives $share_app type and dimensions" True share_app_source "$share_app" "$share_app_type" "$share_app_w" "$share_app_h"
    if [[ $share_app == window ]]; then expect "the window stream contains the target frame" True share_app_pixels "$share_app"; fi
    if [[ $share_app == area ]]; then
      expect "the dragged area contains target pixels beyond its edge" True share_app_pixels "$share_app"
      expect "the dragged area contains output pixels before the target edge" False share_app_pixels "$share_app" 8 8
    fi
    if [[ $share_app == screen ]]; then
      expect "the screen stream names the selected output" True share_mapping
      read -r share_screen_x share_screen_y <<<"$(share_target_local)"
      expect "the screen stream contains the selected output's target" True share_app_pixels "$share_app" "$share_screen_x" "$share_screen_y"
      expect "the screen stream keeps the output outside the target" False share_app_pixels "$share_app" 40 140
    fi
  fi
  share_owner_released "app-$share_app"
  share_stream_released "app-$share_app"
done
share_has_token() { python3 -c 'import json,pathlib,sys; p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text()) if p.exists() else {}; print(isinstance(d.get("restore_token"),str) and bool(d["restore_token"]))' "$share_world/app-screen.json"; }
expect "Remember returns a restore token" True share_has_token
if [[ $(share_has_token) == True ]]; then
  share_app_start restore "$share_world/app-screen.json"
  expect_poll "the app reuses the remembered screen" complete share_app_phase restore
  share_picker_count() { hypr -j clients | py_reply 'import json,sys; print(sum(c["mapped"] and c["title"]=="Capture" for c in json.load(sys.stdin)))'; }
  expect "the remembered source opens no picker" 0 share_picker_count
  expect_poll "the remembered share releases its portal video source" 0 share_stream_count
fi
# A held application keeps the real portal session open after its frame.
# The same zero-count reading must detect this planted lifetime defect.
share_app_start quit --hold
expect_poll "the quit test opens a fresh picker" True share_new_request "$share_previous"
share_click Button Share
expect_poll "the application holds its screen-share session" sharing share_app_phase quit
expect_poll "control: an open portal session retains its video source" 1 share_stream_count
share_held_stream_control() { (failures=0 behaviour_failures=0; share_stream_released held-app >"$share_world/held-stream-control.log"; echo "$failures"); }
expect "control: the held app fails the same video-source release check" 1 share_held_stream_control
cat -- "$share_world/held-stream-control.log"
share_owner_released selected-before-app-quit
kill -TERM -- -"$share_app_pid"
wait "$share_app_pid" 2>/dev/null || true
share_stream_released app-quit
share_owner_released app-quit
share_app_start closed
expect_poll "the close test opens a fresh picker" True share_new_request "$share_previous"
type_keys -k Escape || fail "share-picker: closing the application picker failed"
expect_poll "the app receives picker-close cancellation" cancelled share_app_phase closed
share_stream_released picker-closed
share_owner_released app-picker-closed
cp -R -- "$share_world/." "$share_evidence/runtime"
for share_process in "$share_frontend_pid" "$share_backend_pid" "$share_permissions_pid" "$share_pipewire_pid"; do kill -TERM -- -"$share_process" 2>/dev/null || true; wait "$share_process" 2>/dev/null || true; done
close_toplevel "$share_target_pid" "the share target closes"
close_toplevel "$share_other_pid" "the other share target closes"
rm -rf -- "${home:?}/.config/qt6ct" "${home:?}/.config/xdg-desktop-portal"
rm -f -- "${home:?}/.config/hypr/xdph.conf"
if [[ -f $share_world/theme.saved ]]; then cp -- "$share_world/theme.saved" "$share_theme.next"; mv -T -- "$share_theme.next" "$share_theme"; else rm -f -- "${share_theme:?}"; fi
expect_poll "the picture theme restores its original file state" "$share_theme_initial_state" ipc smoke themeValue fileState
expect_poll "the picture theme restores its original name" "$share_theme_initial_name" ipc smoke themeName
expect_poll "the picture theme restores Hyprland's border" "$share_border_initial" share_border
cp -- "$share_world/shell.saved" "$home/.config/vgshell/shell.json.next"
mv -T -- "$home/.config/vgshell/shell.json.next" "$home/.config/vgshell/shell.json"
