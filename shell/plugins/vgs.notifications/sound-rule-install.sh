#!/usr/bin/env bash
# SoundRule supplies the generated fragments and owns activation/status.
set -euo pipefail
refuse() { printf 'unsupported:%s\n' "$1"; exit 0; }
[[ $# -ge 5 ]] || refuse arguments
action=$1
config_root=$2
data_root=$3
state_root=$4
owner_home=$5
shift 5
script_path=$data_root/wireplumber/scripts/vgs-notification-sounds.lua
conf_path=$config_root/wireplumber/wireplumber.conf.d/90-vgs-notification-sounds.conf
hold_path=$config_root/pipewire/pipewire.conf.d/90-vgs-notification-hold.conf
marker_path=$state_root/vgshell/notifications/sound-rule-store-restarted
old_marker=$state_root/vgshell/notifications/sound-rule-restarted
script_head="-- VGS notifications: an app's own notification sound held silent from its"
conf_head="# VGS notifications: holds an app's own notification sound silent while"
hold_head="# VGS notifications: daemon-owned notification hold"
check_path() {
  local path=$1 parent=$1
  [[ $path == /* ]] || refuse path
  while [[ $parent != / ]]; do
    [[ ! -L $parent ]] || refuse symlink
    if [[ -e $parent ]]; then
      [[ -r $parent ]] || refuse unreadable
      if [[ $parent != "$path" ]]; then [[ -d $parent && -x $parent ]] || refuse directory; fi
    fi
    parent=${parent%/*}
    [[ -n $parent ]] || parent=/
  done
  if [[ -e $path ]]; then [[ -f $path && -O $path && -w $path ]] || refuse ownership; fi
}
check_owned() {
  local path=$1 head=$2 first
  check_path "$path"
  if [[ -e $path ]]; then
    IFS= read -r first <"$path" || refuse unreadable
    [[ $first == "$head" ]] || refuse foreign-file
  fi
}
check_owned "$script_path" "$script_head"
check_owned "$conf_path" "$conf_head"
check_owned "$hold_path" "$hold_head"
for marker in "$marker_path" "$old_marker"; do
  check_path "$marker"
  if [[ -e $marker ]]; then
    IFS= read -r value <"$marker" || refuse marker
    if [[ $marker == "$marker_path" ]]; then
      [[ $value =~ ^hold-store-v1\ v[0-9a-f]{8}$ ]] || refuse foreign-marker
    else
      [[ $value =~ ^v[0-9a-f]{8}$ ]] || refuse foreign-marker
    fi
  fi
done
if [[ $action == remove ]]; then
  rm -f -- "$script_path" "$conf_path" "$hold_path" "$marker_path" "$old_marker"
  echo removed
  exit
fi
[[ $action == install || $action == mark ]] || refuse action
atomic_text() {
  local path=$1 value=$2 temporary current
  while [[ $value == *$'\n' ]]; do value=${value%$'\n'}; done
  if [[ -f $path ]]; then
    current=$(cat -- "$path") || refuse unreadable
    [[ $current != "$value" ]] || return 0
  fi
  mkdir -p -- "${path%/*}"
  [[ -O ${path%/*} && -w ${path%/*} ]] || refuse directory
  temporary=$(mktemp "${path}.XXXXXX") || refuse temporary
  trap 'rm -f -- "${temporary:?}"' EXIT
  if ! printf '%s\n' "$value" >"$temporary" || ! mv -T -- "$temporary" "$path"; then
    refuse write
  fi
  trap - EXIT
}
if [[ $action == mark ]]; then
  [[ $# == 1 && $1 =~ ^v[0-9a-f]{8}$ ]] || refuse version
  atomic_text "$marker_path" "hold-store-v1 $1"
  echo marked
  exit
fi
[[ $# == 4 ]] || refuse arguments
shipped=$1
version=$2
fragment=$3
hold_fragment=$4
[[ $version =~ ^v[0-9a-f]{8}$ ]] || refuse version
[[ $fragment == "$conf_head"$'\n'* && $hold_fragment == "$hold_head"$'\n'* ]] || refuse fragment
[[ -f $shipped && ! -L $shipped && -r $shipped ]] || refuse shipped
script=$(cat -- "$shipped") || refuse shipped
[[ $script == "$script_head"$'\n'* ]] || refuse shipped
# Only a default user daemon can consume this home drop-in automatically.
if [[ ! -e $marker_path ]]; then
  command -v systemctl >/dev/null 2>&1 || refuse manager
  for unit in pipewire.service wireplumber.service; do
    properties=$(systemctl --user show "$unit" --property=LoadState,ActiveState,CanStart,CanStop,RefuseManualStart,RefuseManualStop,MainPID) || refuse unit
    for expected in LoadState=loaded ActiveState=active CanStart=yes CanStop=yes RefuseManualStart=no RefuseManualStop=no; do
      [[ $'\n'$properties$'\n' == *$'\n'"$expected"$'\n'* ]] || refuse unit
    done
    if [[ $unit == pipewire.service ]]; then
      pid=0
      while IFS= read -r line; do [[ $line != MainPID=* ]] || pid=${line#MainPID=}; done <<<"$properties"
      [[ $pid =~ ^[1-9][0-9]*$ && -O /proc/$pid ]] || refuse daemon
      executable=$(readlink -- "/proc/$pid/exe") || refuse daemon
      [[ ${executable##*/} == pipewire ]] || refuse daemon
      argv=()
      mapfile -d '' -t argv <"/proc/$pid/cmdline" || refuse daemon
      [[ ${#argv[@]} == 1 ]] || refuse config
      daemon_home= daemon_config=
      while IFS= read -r -d '' entry; do
        case $entry in
          HOME=*) daemon_home=${entry#HOME=} ;;
          XDG_CONFIG_HOME=*) daemon_config=${entry#XDG_CONFIG_HOME=} ;;
          PIPEWIRE_CONFIG_DIR=*|PIPEWIRE_CONFIG_NAME=*|PIPEWIRE_CONFIG_PREFIX=*) refuse config ;;
        esac
      done <"/proc/$pid/environ"
      [[ $daemon_home == "$owner_home" && ${daemon_config:-$daemon_home/.config} == "$config_root" ]] || refuse config
    fi
  done
  [[ ! -e $config_root/pipewire/pipewire.conf && ! -e /etc/pipewire/pipewire.conf ]] || refuse config
fi
atomic_text "$script_path" "$script"
atomic_text "$conf_path" "$fragment"
atomic_text "$hold_path" "$hold_fragment"
rm -f -- "$old_marker"
echo installed
