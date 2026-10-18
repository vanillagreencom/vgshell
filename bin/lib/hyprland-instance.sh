# Resolve a session signature, or select the sole instance when none is
# supplied. The runner uses the count and signature; the reboot check
# requires the supplied session's PID. A process name never identifies it.
vgs_hyprland_instance() { # [SIGNATURE]
  local signature="${1:-}" instances selected pid
  vgs_hyprland_count=0 vgs_hyprland_signature= vgs_hyprland_pid=
  # Hyprland's CCompositor::createLockFile writes PID, then Wayland socket:
  # https://github.com/hyprwm/Hyprland/blob/main/src/Compositor.cpp
  if [[ -n $signature && -n ${XDG_RUNTIME_DIR:-} ]] &&
    IFS= read -r pid 2>/dev/null <"$XDG_RUNTIME_DIR/hypr/$signature/hyprland.lock" &&
    [[ $pid =~ ^[123456789][0123456789]*$ ]]; then
    vgs_hyprland_count=1 vgs_hyprland_signature="$signature" vgs_hyprland_pid="$pid"
    return 0
  fi
  instances="$(hyprctl instances -j 2>/dev/null)" || return 1
  selected="$(python3 -c 'import json,sys
try:
    rows=json.loads(sys.stdin.read())
except (ValueError, TypeError):
    raise SystemExit(1)
if not isinstance(rows, list):
    raise SystemExit(1)
signature=sys.argv[1]
if signature:
    rows=[row for row in rows if isinstance(row, dict) and row.get("instance") == signature]
sig=pid=""
if len(rows) == 1:
    row=rows[0]
    sig=row.get("instance") if isinstance(row, dict) else None
    if not isinstance(sig, str) or not sig:
        raise SystemExit(1)
    value=row.get("pid")
    if type(value) is int and value > 0:
        pid=str(value)
    if signature and not pid:
        raise SystemExit(1)
elif signature:
    raise SystemExit(1)
print(str(len(rows))+"|"+sig+"|"+pid)
' "$signature" <<<"$instances")" || return 1
  IFS='|' read -r vgs_hyprland_count vgs_hyprland_signature vgs_hyprland_pid <<<"$selected"
}
