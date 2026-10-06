#!/usr/bin/env bash
# Start VGS in each running Hyprland session, run as root by a package's
# first-install scriptlet. Each start runs as the session's user and asks
# that user's Hyprland to launch the shell, so the shell gets the session's
# environment. RUNTIME_ROOT, default /run/user, holds the users' runtime
# directories. No session, a socket another user owns or a failed start
# never fails the install: the script always exits 0.
set -euo pipefail

runtime_root="${1:-/run/user}"
self="$(readlink -f -- "${BASH_SOURCE[0]}")"
vgshell="$(cd -- "$(dirname -- "$self")/.." && pwd -P)/vgshell"
handoff_timeout=10s

[[ -d $runtime_root && ! -L $runtime_root ]] || exit 0

# getent ships with glibc on every channel's base system.
passwd_entry() { # UID
  local line name _ uid _gid _gecos home _shell
  line="$(getent passwd "$1")" || return 1
  IFS=: read -r name _ uid _gid _gecos home _shell <<<"$line"
  [[ $uid == "$1" && -n $name && -n $home ]] || return 1
  printf '%s:%s\n' "$name" "$home"
}

for user_dir in "$runtime_root"/*; do
  [[ -d $user_dir && ! -L $user_dir ]] || continue
  uid="${user_dir##*/}"
  [[ $uid =~ ^[0-9]+$ ]] || continue
  [[ "$(stat -c '%u' -- "$user_dir" 2>/dev/null || :)" == "$uid" ]] || continue
  account="$(passwd_entry "$uid")" || continue
  user="${account%%:*}"
  home="${account#*:}"
  # One hand-off per user: the instance lock allows one shell per runtime
  # directory, and a crashed Hyprland leaves its socket behind, so the
  # newest socket names the live session. It also bounds the install's
  # wait to one timeout per account, however many sockets a user makes.
  newest="" newest_time=-1
  for socket in "$user_dir"/hypr/*/.socket.sock; do
    [[ -S $socket && ! -L $socket ]] || continue
    owner_time="$(stat -c '%u %Y' -- "$socket" 2>/dev/null || :)"
    [[ ${owner_time% *} == "$uid" ]] || continue
    if ((${owner_time#* } > newest_time)); then
      newest="$socket" newest_time="${owner_time#* }"
    fi
  done
  [[ -n $newest ]] || continue
  signature="${newest%/.socket.sock}"
  signature="${signature##*/}"
  if ! timeout "$handoff_timeout" runuser -u "$user" -- env -i \
    HOME="$home" PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR="$user_dir" \
    HYPRLAND_INSTANCE_SIGNATURE="$signature" "$vgshell" start; then
    printf 'first-start: start=failed uid=%s signature=%s\n' "$uid" "$signature" >&2
  fi
done

exit 0
