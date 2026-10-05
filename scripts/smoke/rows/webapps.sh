# Web Apps, vgs.webapps: a site made an app from the Settings window, found
# in the launcher by its name with its icon, opened in its own window and
# focused on the next selection, and removed with its entry and icon.
# The row's world lives under $sandbox/webapps and the sandbox's own home:
# a site python3's http.server serves on the loopback address, one page
# with a title and an icon link and one with neither; a stand-in browser
# that logs its arguments and runs the harness's toplevel helper with the
# class a Chromium-family browser gives a site opened with --app; its
# desktop entry, chromium.desktop, whose Exec names it by its path; and a
# mimeapps.list that makes it the https default. No real browser runs and
# no shell is started again: the PATH stays the harness's.
# Read back: the desktop entry the service writes, its Name the page's
# title and its Icon the page's icon, byte for byte; the launcher's row by
# that name with its icon drawn; one launch with --app=<address> and one
# window of the class; a second selection from the launcher that launches
# nothing and gives that window the keyboard; Remove taking the entry, the
# icon and the launcher's row away. The controls: a page with no icon,
# whose app takes the plugin's default icon, so the first icon reading
# cannot pass on the default; and a window of another class open before
# the first selection, which still launches.
# The row closes every window it opened or the stand-in browser mapped,
# stops the site, removes what it planted and leaves Web Apps, the
# launcher and Settings as it found them, and shell.json as it was.
# No latency is measured; each reading polls every 200 ms for up to 5 s.
# inputs: shell/plugins/vgs.webapps/* shell/plugins/vgs.settings/* shell/plugins/vgs.launcher/* shell/Hosts/SummonLayer.qml shell/Commons/DesktopLaunch.js shell/Core/Compositor.qml shell/Core/Dispatch.js
set -euo pipefail

wa_id=vgs.webapps
wa_dir="$sandbox/webapps"
wa_apps="$home/.local/share/applications"
wa_icons="$home/.config/vgshell/webapps/icons"
wa_user="$home/.config/vgshell/shell.json"
wa_mime="$home/.config/mimeapps.list"
wa_launches="$wa_dir/launches"

# wa_list VERB ARG: one of the probe's list verbs on the Web apps field.
wa_list() { ipc smoke invokeInstance window vgs.settings "$1" "$2"; }
wa_add() { wa_list listAdd "{\"id\":\"$wa_id\",\"key\":\"apps\"}"; }
wa_remove() { wa_list listRemove "{\"id\":\"$wa_id\",\"key\":\"apps\",\"name\":\"$1\"}"; }
wa_field() { wa_list listApply "{\"id\":\"$wa_id\",\"key\":\"apps\",\"name\":\"$1\",\"field\":\"$2\",\"value\":$3}"; }
wa_drawn() { wa_list listItems "{\"id\":\"$wa_id\",\"key\":\"apps\"}" | py_reply 'import json,sys; print(json.dumps([i["name"] for i in json.load(sys.stdin)]))'; }
# wa_entry NAME KEY: KEY's value in app NAME's desktop entry, or absent.
wa_entry() { python3 -c 'import sys
try: lines = open(sys.argv[1]).read().splitlines()
except FileNotFoundError: print("absent"); sys.exit()
v = [l.split("=", 1)[1] for l in lines if l.startswith(sys.argv[2] + "=")]
print(v[0] if v else "no-key")' "$wa_apps/vgs-webapp-$1.desktop" "$2"; }
# wa_same A B: `same` while files A and B hold the same bytes.
wa_same() { if cmp -s -- "$1" "$2"; then echo same; elif [[ -e $1 ]]; then echo differs; else echo absent; fi; }
# wa_planted: what the service keeps for the row's apps, as names.
wa_planted() { python3 -c 'import os,sys; print(" ".join(sorted([f for f in os.listdir(sys.argv[1]) if f.startswith("vgs-webapp-")] + (os.listdir(sys.argv[2]) if os.path.isdir(sys.argv[2]) else []))) or "none")' "$wa_apps" "$wa_icons"; }
wa_browser() { ipc smoke statusValues "$wa_id" | py_reply 'import json,sys; v=json.load(sys.stdin).get("browser"); print(json.dumps(v if v is None else [v["tone"], v["text"]]))'; }
wa_rows() { ipc smoke launcherRows overlay vgs.launcher | py_reply 'import json,sys; t=sys.stdin.read(); print(json.dumps(json.loads(t)) if t.startswith("[") else t.strip())'; }
wa_first_row() { wa_rows | py_reply 'import json,sys; r=json.load(sys.stdin); print(json.dumps(r[0][:2]) if r else "none")'; }
wa_has_row() { wa_rows | py_reply 'import json,sys; print(any(r[0] == "app" and r[1] == sys.argv[1] for r in json.load(sys.stdin)))' "$1"; }
# wa_icon_drawn PATH: the state of the launcher image drawn from PATH.
wa_icon_drawn() { ipc smoke images overlay vgs.launcher | py_reply 'import json,sys; s=[i[1] for i in json.load(sys.stdin) if i[0].endswith(sys.argv[1])]; print(s[0] if s else "none")' "$1"; }
wa_launch_count() { if [[ -f $wa_launches ]]; then wc -l <"$wa_launches"; else echo 0; fi; }
# wa_windows CLASS: how many mapped windows of CLASS Hyprland lists.
wa_windows() { hypr -j clients | py_reply 'import json,sys; print(sum(1 for c in json.load(sys.stdin) if c["class"] == sys.argv[1] and c["mapped"]))' "$1"; }
wa_active_class() { hypr -j activewindow | py_reply 'import json,sys; d=json.load(sys.stdin); print(d.get("class") or "none")'; }
wa_focused() { expect_poll "$1" true ipc smoke activeFocusIn overlay vgs.launcher; }
# wa_select TEXT LABEL: the launcher summoned with TEXT searched and
# Enter on its first row, which must be the app TEXT names.
wa_select() {
  expect "the launcher opens searching for $1 $2" ok ipc shell summon overlay vgs.launcher "{\"query\":\"$1\"}"
  wa_focused "the launcher holds the keyboard $2"
  expect_poll "the launcher ranks $1 first $2" "[\"app\", \"$1\"]" wa_first_row
  type_keys -k Return || fail "sending Return in the launcher $2 failed"
  expect_poll "the launcher closes on the selection $2" 0 layer_count vgs:overlay
}
# wa_close_class CLASS: every window of CLASS the stand-in browser mapped,
# closed by its pid once that pid is the toplevel helper's.
wa_close_class() {
  local pid
  local pids
  pids="$(hypr -j clients | py_reply 'import json,sys; print(" ".join(str(c["pid"]) for c in json.load(sys.stdin) if c["class"] == sys.argv[1]) or "none")' "$1")" || { fail "the clients of class $1 are unreadable"; return; }
  [[ $pids == none ]] && pids=""
  for pid in $pids; do
    if [[ "$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)" == "$sandbox/toplevel "* ]]; then
      kill -TERM -- "$pid" 2>/dev/null || true
    else
      fail "window of class $1 has pid $pid, which is no toplevel helper"
    fi
  done
  expect_poll "no window of class $1 is left" 0 wa_windows "$1"
}

# The world: the site, the stand-in browser, its entry and the default.
mkdir -p -- "$wa_dir/site/app" "$wa_dir/site/bare" "$wa_apps"
rm -f -- "$wa_launches"
printf '<!doctype html><html><head><title>Smoke Mail</title><link rel="stylesheet" href="style.css"><link rel="icon" href="icon.png" sizes="32x32"></head><body>mail</body></html>\n' >"$wa_dir/site/app/index.html"
printf '<!doctype html><html><head><title>Bare Site</title></head><body>bare</body></html>\n' >"$wa_dir/site/bare/index.html"
solid_png "$wa_dir/site/app/icon.png" 32 32 40 120 200
cat >"$wa_dir/chromium" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>$(printf '%q' "$wa_launches")
url=""
for word in "\$@"; do [[ \$word == --app=* ]] && url="\${word#--app=}"; done
class="\$(python3 -c 'import sys, urllib.parse; u = urllib.parse.urlsplit(sys.argv[1]); print("chrome-" + u.hostname + "_" + (u.path or "/").replace("/", "_") + "-Default")' "\$url")"
exec $(printf '%q' "$sandbox/toplevel") "\$class" "Web app"
EOF
chmod 755 "$wa_dir/chromium"
printf '[Desktop Entry]\nType=Application\nName=Smoke Browser\nExec=%s %%U\n' "$wa_dir/chromium" >"$wa_apps/chromium.desktop"
wa_mime_before=absent
if [[ -e $wa_mime ]]; then cp -p -- "$wa_mime" "$wa_dir/mimeapps.list.before"; wa_mime_before=kept; fi
printf '[Default Applications]\nx-scheme-handler/https=chromium.desktop\nx-scheme-handler/http=chromium.desktop\n' >"$wa_mime"
expect_poll "configuration saves settle before the row keeps shell.json" true ipc smoke configSettled
cp -p -- "$wa_user" "$wa_dir/shell.json.before"
spawn "$wa_dir/server.log" python3 -u -m http.server --bind 127.0.0.1 --directory "$wa_dir/site" 0
wa_server_pid="$spawn_pid"
wa_port=""
for _ in $(seq 1 25); do
  wa_port="$(sed -n 's/^Serving HTTP on 127\.0\.0\.1 port \([0-9]*\).*/\1/p' "$wa_dir/server.log")"
  [[ -n $wa_port ]] && break
  sleep 0.2
done
[[ -n $wa_port ]] || fail "the row's site serves on the loopback address"
wa_url="http://127.0.0.1:$wa_port/app/"
wa_bare="http://127.0.0.1:$wa_port/bare/"
wa_class="chrome-127.0.0.1__app_-Default"

wa_before="$(plugin_enabled "$wa_id")" || wa_before=unread
wa_launcher_before="$(plugin_enabled vgs.launcher)" || wa_launcher_before=unread
expect "Web Apps starts off in the sandbox" False printf '%s\n' "$wa_before"
expect "enabling Web Apps is allowed" ok ipc shell setPluginEnabled "$wa_id" true
expect_poll "the Web Apps service is built" True record_exists "$wa_id"
expect_poll "the service finds the stand-in browser as the default one" '["ok", "Smoke Browser"]' wa_browser

# Adding from Settings: the site's title names the entry and its icon draws it.
settings_page_open "$wa_id"
expect "the page draws no web app at first" '[]' wa_drawn
expect "the page's Add button is clicked" clicked wa_add
expect_poll "Add writes one web app named 1" '["1"]' wa_drawn
expect "the web app's Address editor takes the site" applied wa_field 1 url "\"$wa_url\""
expect_poll "the entry is named by the site's title" "Smoke Mail" wa_entry 1 Name
expect_poll "the entry's icon is the one the site names" "$wa_icons/1.png" wa_entry 1 Icon
expect "the icon is the site's icon, byte for byte" same wa_same "$wa_icons/1.png" "$wa_dir/site/app/icon.png"
# Control: a site with no icon takes the plugin's default icon.
expect "the page's Add button is clicked for the bare site" clicked wa_add
expect_poll "Add writes a second web app named 2" '["1", "2"]' wa_drawn
expect "the second web app's Address editor takes the bare site" applied wa_field 2 url "\"$wa_bare\""
expect_poll "control: the bare site's entry is named by its title" "Bare Site" wa_entry 2 Name
expect_poll "control: a site with no icon takes the default icon" "$wa_icons/2.svg" wa_entry 2 Icon
expect "control: the default icon is the plugin's own" same wa_same "$wa_icons/2.svg" "$repo/shell/plugins/vgs.webapps/fallback.svg"
expect "the Settings window is hidden" ok ipc shell hide window vgs.settings

# The launcher lists the web app by name with its icon.
if [[ $wa_launcher_before != True ]]; then
  expect "enabling the launcher is allowed" ok ipc shell setPluginEnabled vgs.launcher true
  expect_poll "the launcher's service is built" True record_exists vgs.launcher
fi
expect "the launcher opens searching for Smoke Mail" ok ipc shell summon overlay vgs.launcher '{"query":"Smoke Mail"}'
expect_poll "the launcher lists the web app by its name" '["app", "Smoke Mail"]' wa_first_row
expect_poll "the launcher draws the web app's icon" ready wa_icon_drawn "$wa_icons/1.png"
wa_focused "the launcher holds the keyboard before Escape"
type_keys -k Escape -k Escape || fail "sending Escape in the launcher failed"
expect_poll "Escape closes the launcher" 0 layer_count vgs:overlay

# Control: a window of another class open before the first selection.
open_toplevel "$wa_dir/other.log" smoke.webapps-other "Other window" || fail "the other class's window maps"
wa_other_pid="$toplevel_pid"
expect "no web app window is open before the first selection" 0 wa_windows "$wa_class"
wa_select "Smoke Mail" "for the first selection"
expect_poll "the first selection launches the browser once" 1 wa_launch_count
expect "the launch opens the site as an app" "--app=$wa_url" cat -- "$wa_launches"
expect_poll "one window of the web app's class maps" 1 wa_windows "$wa_class"

# A second selection focuses that window and launches nothing.
open_toplevel "$wa_dir/cover.log" smoke.webapps-cover "Cover window" || fail "the cover window maps"
wa_cover_pid="$toplevel_pid"
expect_poll "the cover window has the keyboard" smoke.webapps-cover wa_active_class
wa_select "Smoke Mail" "for the second selection"
expect_poll "the second selection gives the web app's window the keyboard" "$wa_class" wa_active_class
expect "the second selection launches nothing" 1 wa_launch_count
expect "the web app still has one window" 1 wa_windows "$wa_class"

# Remove takes the entry, the icon and the launcher's row away.
settings_page_open "$wa_id"
expect "web app 1's Remove button is clicked" clicked wa_remove 1
expect "web app 2's Remove button is clicked" clicked wa_remove 2
expect_poll "the page draws no web app after Remove" '[]' wa_drawn
expect_poll "Remove takes every entry and icon away" none wa_planted
expect "the Settings window is hidden after Remove" ok ipc shell hide window vgs.settings
# The stand-in browser's entry matches the search too, so the list is read
# once it is laid out, never while it is still empty.
expect "the launcher opens searching for the removed app" ok ipc shell summon overlay vgs.launcher '{"query":"Smoke"}'
expect_poll "the launcher lists the stand-in browser for the search" True wa_has_row "Smoke Browser"
expect "the launcher no longer lists the removed web app" False wa_has_row "Smoke Mail"
wa_focused "the launcher holds the keyboard after Remove"
type_keys -k Escape -k Escape || fail "sending Escape in the launcher after Remove failed"
expect_poll "Escape closes the launcher after Remove" 0 layer_count vgs:overlay

# What the row leaves: every window closed, the site stopped, what it
# planted removed, and each plugin and shell.json as it found them.
wa_close_class "$wa_class"
close_toplevel "$wa_cover_pid" "the cover window exits 0 on SIGTERM"
close_toplevel "$wa_other_pid" "the other class's window exits 0 on SIGTERM"
kill -TERM -- "$wa_server_pid" 2>/dev/null || true
wait "$wa_server_pid" 2>/dev/null || true
if [[ $wa_launcher_before != True ]]; then
  expect "the launcher is disabled again" ok ipc shell setPluginEnabled vgs.launcher false
  expect_poll "the launcher's service is gone" False record_exists vgs.launcher
fi
settings_page_close "$wa_id"
case "$wa_before" in
  True) ;;
  False)
    expect "Web Apps is disabled again" ok ipc shell setPluginEnabled "$wa_id" false
    expect_poll "the Web Apps service is gone" False record_exists "$wa_id"
    ;;
  *) fail "Web Apps' enabled state before the row: got $wa_before" ;;
esac
rm -f -- "$wa_apps/chromium.desktop"
if [[ $wa_mime_before == kept ]]; then mv -f -- "$wa_dir/mimeapps.list.before" "$wa_mime"; else rm -f -- "$wa_mime"; fi
rmdir -- "$wa_icons" "${wa_icons%/icons}" 2>/dev/null || true
expect "the row leaves no web app entry or icon" none wa_planted
# The plugins rows the enable and the list wrote go with the kept file.
expect_poll "configuration saves settle before the row puts shell.json back" true ipc smoke configSettled
cp -p -- "$wa_dir/shell.json.before" "$wa_user.next"
mv -T -- "$wa_user.next" "$wa_user"
expect "the shell reads the kept configuration" ok ipc shell reloadConfig
expect_poll "the kept configuration settles" true ipc smoke configSettled
expect "shell.json is as the row found it" same wa_same "$wa_user" "$wa_dir/shell.json.before"
expect "Web Apps is off as the row found it" False plugin_enabled "$wa_id"
rm -rf -- "${wa_dir:?}"
