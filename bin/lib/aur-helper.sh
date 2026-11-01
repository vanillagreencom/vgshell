#!/usr/bin/env bash
# Paru's upstream installation builds the AUR recipe as the user. Plain
# Arch has no paru repository package; use the same route on CachyOS.
# https://github.com/Morganamilo/paru#installation
#
#   aur-helper.sh VGSHELL TREE
#
# Installs the build prerequisites through VGSHELL, the VGS command, and
# clones the recipe into TREE, a path in a private directory the package
# owner made and removes. The owner then builds TREE with the table's
# PackageManagers.bootstrapBuild, so its failure evidence and its one
# retry without tests stay with the owner. vgshell-pkg owns terminal
# admission.
set -euo pipefail

[[ $# -eq 2 && $2 == /* && ! -e $2 && -d ${2%/*} && ! -L ${2%/*} && -O ${2%/*} ]] || {
  printf 'vgshell: refused: aur-helper=arguments\n' >&2
  exit 2
}
"$1" pkg run install --manager pacman base-devel git
git clone -- https://aur.archlinux.org/paru.git "$2"
