# The smoke rows restore shell.json while Config.qml watches it. Copy to an
# exclusively owned file beside it, then rename, so a read sees a whole file.
set -euo pipefail
user_config_restore() ( # BACKUP
  local destination="$home/.config/vgshell/shell.json" staged
  staged="$(mktemp "$home/.config/vgshell/.shell.json.XXXXXX")" || return
  trap 'rm -f -- "$staged"' EXIT
  cp -- "$1" "$staged" || return
  mv -T -- "$staged" "$destination"
)
