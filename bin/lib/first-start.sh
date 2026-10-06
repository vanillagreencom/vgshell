#!/usr/bin/env bash
# Start VGS in running Hyprland sessions after a package's first-install scriptlet.
set -euo pipefail

runtime_root="${1:-/run/user}"
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
vgshell="$(cd -- "$(dirname -- "$self")/.." && pwd -P)/vgshell"
handoff_timeout=10s

[[ -d $runtime_root && ! -L $runtime_root ]] || exit 0

passwd_entry() { # UID
  local line name _ uid _gid _gecos home _shell
  if command -v getent >/dev/null 2>&1 && line="$(getent passwd "$1")" && [[ -n $line ]]; then
    IFS=: read -r name _ uid _gid _gecos home _shell <<<"$line"
    [[ $uid == "$1" && -n $name && -n $home ]] || return 1
    printf '%s:%s\n' "$name" "$home"
    return 0
  fi
  while IFS=: read -r name _ uid _gid _gecos home _shell; do
    if [[ $uid == "$1" && -n $name && -n $home ]]; then
      printf '%s:%s\n' "$name" "$home"
      return 0
    fi
  done </etc/passwd
  return 1
}

for user_dir in "$runtime_root"/*; do
  [[ -d $user_dir && ! -L $user_dir ]] || continue
  uid="${user_dir##*/}"
  [[ $uid =~ ^[0-9]+$ ]] || continue
  [[ "$(stat -c '%u' -- "$user_dir" 2>/dev/null || :)" == "$uid" ]] || continue
  account="$(passwd_entry "$uid")" || continue
  user="${account%%:*}"
  home="${account#*:}"
  for socket in "$user_dir"/hypr/*/.socket.sock; do
    [[ -S $socket && ! -L $socket ]] || continue
    [[ "$(stat -c '%u' -- "$socket" 2>/dev/null || :)" == "$uid" ]] || continue
    signature="${socket%/.socket.sock}"
    signature="${signature##*/}"
    if ! timeout "$handoff_timeout" runuser -u "$user" -- env -i \
      HOME="$home" PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR="$user_dir" \
      HYPRLAND_INSTANCE_SIGNATURE="$signature" "$vgshell" start; then
      printf 'first-start: start=failed uid=%s signature=%s\n' "$uid" "$signature" >&2
    fi
  done
done

exit 0
