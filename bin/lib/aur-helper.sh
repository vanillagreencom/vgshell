#!/usr/bin/env bash
# Paru's upstream installation builds the AUR recipe as the user. Plain
# Arch has no paru repository package; use the same route on CachyOS.
# https://github.com/Morganamilo/paru#installation
# vgshell-pkg owns terminal admission and passes its VGS command as argv.
set -euo pipefail

build="$(mktemp -d)" || exit 1
[[ -d $build && ! -L $build ]] || exit 1
build="$(cd -- "$build" && pwd -P)" || exit 1
trap 'rm -rf -- "${build:?}"' EXIT
"$1" pkg run install --manager pacman base-devel git
git clone -- https://aur.archlinux.org/paru.git "$build/paru"
cd -- "$build/paru"
makepkg -si
command -v paru >/dev/null
