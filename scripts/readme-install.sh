#!/usr/bin/env bash
# Run the commands of README.md § Install, as written, in clean containers.
#
# Usage: scripts/readme-install.sh [--export DIR] [--channel NAME]...
#
# --channel selects named channels: aur, fedora, curl, nix, checkout,
# curl-debian and curl-nixos. Without it every channel runs. The last two
# repeat the README's curl block on Debian forky and the NixOS fixture.
#
# --export copies each version-checked install's resolved runtime tree to
# DIR/line-<n>-<channel>. Nix exports the installed command's store closure
# there as nix/store/. Copying it must leave 3 GB free for export and world.
# Each copy prints `readme-install: tree line=<n> channel=<c> path=<dir>`,
# with `store=<dir>/nix` for Nix. Exports survive this runner's cleanup.
# Before a block runs, its exact commands and export function pass bash -n
# in the same prepared image: `readme-install: syntax block=<n> image=<id>`.
#
# The release check of the README's install section, run by hand before a
# release like scripts/fedora-container.sh.
# The commands come from `node scripts/check-readme.js --commands` alone, so
# a README that check refuses is refused here first. Each command runs as
# the README prints it, so it installs from GitHub, the AUR, COPR and the
# Nix flake at their published state, never from this working tree: the
# curl, untagged nix and checkout commands read `main`.
#
# A command whose needs are unpublished is not measured: `release:<tag>`
# while `git ls-remote --tags` of the repository has no such tag,
# `aur:<pkg>` while the AUR RPC info query finds no such package,
# `copr:<owner>/<project>` while the COPR API answers 404 for the project,
# and `copr:<owner>/<project>/<pkg>` while it answers 404 for the package
# or the package has no succeeded build. The rest of its block still runs.
# A probe that fails is not measured either, never read as unpublished.
#
# Each bash fence of the section runs top to bottom in one fresh container,
# in the home directory, with an empty line on stdin for every prompt, so
# each prompt takes its default answer, except in the Fedora image. A command runs under pipefail, so a
# `curl ... | bash` whose download fails fails, though bash exits 0 on the
# empty script. Each fence is one alternative the README offers, in the
# image of its channel:
#   - aur, curl and checkout commands in an archlinux:latest image prepared
#     once per run: base-devel, git, sudo, hyprland, nodejs and
#     python, the unprivileged user `user` with passwordless sudo inside the
#     container alone, and the AUR helper named by the README when a curl,
#     checkout or aur command is measured. The commands run as `user`, with HOME and the
#     XDG_RUNTIME_DIR a login session sets, as a user's terminal has them:
#     `vgshell run` keeps its instance lock and runtime files in that
#     directory. script(1) supplies the controlling terminal for prompts.
#   - Nix commands in the same nonroot NixOS identity fixture as NixOS curl.
#     The fixture proves installation and version only, never NixOS graphics.
#   - fedora commands in a registry.fedoraproject.org/fedora:44 image
#     prepared once per run with sudo and the user `user`, with passwordless
#     sudo inside the container alone. The commands run as `user`, with the
#     same HOME and XDG_RUNTIME_DIR. dnf's prompts default to no, so every
#     prompt there gets `y`, the answer the README tells the user to give.
# A command passes on exit 0. A command whose vgshell arguments are `start`
# passes when it exits 69 refusing `hyprland=unreachable`, since no Hyprland
# session runs in a container.
#
# Each command is ended after `command_seconds`, a bound for a prompt the
# empty answers do not satisfy, not a budget. On 2026-09-29, with podman
# 6.1.2 on the owner's workstation, the slowest command this script
# measured took 5 s: the checkout's `git clone` and the curl `--git`
# install. The AUR figure is a yay measurement, not a paru one: a yay build
# and install of the AUR package shellcheck-bin in the same image, with the
# same empty answers, took under 20 s. No paru run has been timed.
#
# Nothing runs against the host's packages, /etc or the live session. The
# Apart from --export output, the script writes under this repository's tmp/:
# tmp/readme-install.<pid>/
# holds the logs and is removed on exit, and tmp/readme-install-cache/ holds
# the prepared Arch image's pacman downloads, kept so a rerun downloads no
# package it already has. The prepared images and every container are
# removed on exit.
#
# Output, one keyed line each: `readme-install: ok line=<n> channel=<c>
# exit=<status> seconds=<n>` per passing command, and last `readme-install:
# ok commands=<n>`, exit 0. `readme-install: refused: <key>=<value> ...`
# first, then the command's output, exit 1: a command failed, or
# check-readme refused the README. `readme-install: status=not-measured
# reason=<key> ...`, exit 77: podman-missing, image-pull, container-setup,
# container-start, release-probe, aur-probe, copr-probe, or `unpublished` with the
# command's line and needs, one line each and then a count; that is not a
# pass. Exit 2: an argument.
set -euo pipefail

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd -P)"
arch_image='docker.io/library/archlinux:latest'
nix_image='docker.io/nixos/nix:2.35.2'
nix_volume='vgs-validate-nix-2.35.2'
fedora_image='registry.fedoraproject.org/fedora:44'
debian_image='docker.io/library/debian:forky'
copr_api='https://copr.fedorainfracloud.org/api_3'
repo_url='https://github.com/vanillagreencom/vgshell'
command_seconds=1200

refuse() { # STATUS KEY [DETAIL...]
  local status="$1"
  printf 'readme-install: refused: %s\n' "$2"
  shift 2
  [[ $# -eq 0 ]] || printf '%s\n' "$@"
  exit "$status"
}
not_measured() { # REASON [DETAIL...]
  printf 'readme-install: status=not-measured reason=%s\n' "$1"
  shift
  [[ $# -eq 0 ]] || printf '%s\n' "$@"
  exit 77
}

export_dir=""
selected_channels=()
while (($#)); do
  case "$1" in
    --export)
      [[ $# -ge 2 && -n $2 ]] || refuse 2 "argument=--export"
      export_dir="$(realpath -m -- "$2")"; shift 2 ;;
    --channel)
      [[ $# -ge 2 && -n $2 ]] || refuse 2 "argument=--channel"
      selected_channels+=("$2"); shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$self"; exit 0 ;;
    *) refuse 2 "argument=$1" ;;
  esac
done

commands_out="$(node "$repo/scripts/check-readme.js" --commands)" || refuse 1 "check-readme=refused" "$commands_out"
# One tab-separated row per command: block, line, channel, needs, vgshell
# arguments (`-` for none), command.
rows_out="$(node -e '
const commands = require("fs").readFileSync(0, "utf8").split("\n").filter(Boolean).map(JSON.parse);
let next = Math.max(...commands.map(c => c.block));
for (const channel of ["curl-debian", "curl-nixos"]) {
    const blocks = new Map();
    for (const c of commands.filter(c => c.channel === "curl")) {
        if (!blocks.has(c.block)) blocks.set(c.block, ++next);
        commands.push({...c, block: blocks.get(c.block), channel});
    }
}
for (const c of commands) {
    console.log([c.block, c.line, c.channel, c.needs, c.vgshell === null ? "-" : c.vgshell, c.archHelpers.length === 0 ? "-" : c.archHelpers[0], c.command].join("\t"));
}' <<<"$commands_out")" || refuse 1 "commands=unreadable" "$commands_out"
mapfile -t rows <<<"$rows_out"
[[ ${#rows[@]} -gt 0 && -n ${rows[0]} ]] || refuse 1 "commands=none" "check-readme printed no command"
declare -A known_channels=()
for row in "${rows[@]}"; do
  IFS=$'\t' read -r _ _ channel _ <<<"$row"
  known_channels[$channel]=true
done
for channel in "${selected_channels[@]}"; do
  [[ -v known_channels[$channel] ]] || refuse 2 "channel=$channel reason=unknown"
done
if ((${#selected_channels[@]})); then
  selected_rows=()
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r _ _ channel _ <<<"$row"
    [[ " ${selected_channels[*]} " != *" $channel "* ]] || selected_rows+=("$row")
  done
  rows=("${selected_rows[@]}")
fi

command -v podman >/dev/null 2>&1 || not_measured podman-missing "install podman to run the README's commands in containers"

scratch="$repo/tmp/readme-install.$$"
cache="$repo/tmp/readme-install-cache"
prepared="localhost/vgs-readme-install:$$"
fedora_prepared="localhost/vgs-readme-install-fedora:$$"
debian_prepared="localhost/vgs-readme-install-debian:$$"
nixos_prepared="localhost/vgs-readme-install-nixos:$$"
containers=()
declare -A exported=()
prepared_made=false
fedora_prepared_made=false
debian_prepared_made=false
nixos_prepared_made=false
nixos_volume=""
cleanup() {
  local name
  local remove_args=(-f -t 0)
  # Before a volume handle is admitted, its owned container still owns
  # anonymous-volume cleanup. Podman keeps named caches under --volumes.
  [[ -n $nixos_volume ]] || remove_args+=(--volumes)
  for name in "${containers[@]}"; do podman rm "${remove_args[@]}" -- "$name" >/dev/null 2>&1 || true; done
  [[ $prepared_made == false ]] || podman rmi -f -- "$prepared" >/dev/null 2>&1 || true
  [[ $fedora_prepared_made == false ]] || podman rmi -f -- "$fedora_prepared" >/dev/null 2>&1 || true
  [[ $debian_prepared_made == false ]] || podman rmi -f -- "$debian_prepared" >/dev/null 2>&1 || true
  [[ $nixos_prepared_made == false ]] || podman rmi -f -- "$nixos_prepared" >/dev/null 2>&1 || true
  [[ -z $nixos_volume ]] || podman volume rm -- "$nixos_volume" >/dev/null 2>&1 || true
  rm -rf -- "$scratch" 2>/dev/null || podman unshare rm -rf -- "$scratch"
}
trap cleanup EXIT
rm -rf -- "$scratch"
mkdir -p -- "$scratch" "$cache"

# Whether each needs value is published: `yes` or `no`.
declare -A published=()
probe() { # NEEDS
  local out
  case "$1" in
    none) published[$1]=yes ;;
    release:*)
      out="$(GIT_TERMINAL_PROMPT=0 git ls-remote --tags -- "$repo_url" "refs/tags/${1#release:}" 2>&1)" ||
        not_measured "release-probe tag=${1#release:}" "$out"
      if [[ -n $out ]]; then published[$1]=yes; else published[$1]=no; fi ;;
    aur:*)
      out="$(curl -fsS --max-time 20 "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${1#aur:}" 2>&1)" ||
        not_measured "aur-probe package=${1#aur:}" "$out"
      out="$(node -e '
const [answer, name] = [JSON.parse(process.argv[1]), process.argv[2]];
if (!Array.isArray(answer.results)) throw new Error("no results list");
console.log(answer.results.some(r => r.Name === name) ? "yes" : "no");' "$out" "${1#aur:}" 2>&1)" ||
        not_measured "aur-probe package=${1#aur:}" "$out"
      published[$1]="$out" ;;
    copr:*)
      local spec="${1#copr:}" owner project pkg="" url
      owner="${spec%%/*}" project="${spec#*/}"
      if [[ $project == */* ]]; then pkg="${project#*/}" project="${project%%/*}"; fi
      if [[ -n $pkg ]]; then
        url="$copr_api/package?ownername=$owner&projectname=$project&packagename=$pkg&with_latest_succeeded_build=true"
      else
        url="$copr_api/project?ownername=$owner&projectname=$project"
      fi
      # The body, then the HTTP status on a line of its own.
      out="$(curl -sS --max-time 20 -w '\n%{http_code}' "$url" 2>&1)" || not_measured "copr-probe need=$1" "$out"
      case "${out##*$'\n'}" in
        404) published[$1]=no ;;
        200)
          out="$(node -e '
const [answer, pkg] = [JSON.parse(process.argv[1]), process.argv[2]];
if (pkg === "") {
    if (typeof answer.full_name !== "string") throw new Error("no project full_name");
    console.log("yes");
} else {
    if (answer.builds === null || typeof answer.builds !== "object" || !("latest_succeeded" in answer.builds)) throw new Error("no latest_succeeded field");
    console.log(answer.builds.latest_succeeded === null ? "no" : "yes");
}' "${out%$'\n'*}" "$pkg" 2>&1)" || not_measured "copr-probe need=$1" "$out"
          published[$1]="$out" ;;
        *) not_measured "copr-probe need=$1 http=${out##*$'\n'}" "${out%$'\n'*}" ;;
      esac ;;
    *) refuse 1 "needs=$1" "check-readme printed a needs value this runner does not know" ;;
  esac
}

# Each block's image, `nix`, `fedora` or `arch`; a fence that mixes them is
# refused before anything runs.
declare -A block_image=()
declare -A block_commands=()
arch_helper=""
for row in "${rows[@]}"; do
  IFS=$'\t' read -r block line channel needs vgshell helper command <<<"$row"
  case "$channel" in
    nix|fedora) image="$channel" ;;
    curl-debian) image=debian ;;
    curl-nixos) image=nixos ;;
    *) image=arch ;;
  esac
  [[ ${block_image[$block]:-$image} == "$image" ]] ||
    refuse 1 "block=mixed line=$line channel=$channel" "a fence mixes $image commands with others, which run in another image"
  block_image[$block]="$image"
  block_commands[$block]+="$command"$'\n'
  [[ -v published[$needs] ]] || probe "$needs"
  if [[ ${published[$needs]} == yes && $image == arch ]]; then
    if [[ $channel == aur ]]; then arch_helper=${command%% *};
    elif [[ $helper != - ]]; then arch_helper=$helper; fi
  fi
done

pull() { # IMAGE
  local out
  podman image exists "$1" && return 0
  out="$(podman pull -q "$1" 2>&1)" || not_measured "image-pull image=$1" "$out"
}

# The Arch image every aur, curl and checkout block starts from, made once.
prepare_arch() {
  [[ $prepared_made == false ]] || return 0
  pull "$arch_image"
  cat >"$scratch/prepare.sh" <<'PREPARE'
#!/usr/bin/env bash
# Runs as root in the preparing container. Argument: the README AUR helper.
set -euo pipefail
helper="$1"
# The cache is the host's tmp/readme-install-cache, and root here is the
# host user, so pacman downloads as root.
sed -i 's/^DownloadUser/#DownloadUser/' /etc/pacman.conf
sed -i '/^\[options\]/a NoExtract = usr/share/doc/* usr/share/licenses/*' /etc/pacman.conf
if grep -q '^DownloadUser' /etc/pacman.conf; then echo 'pacman.conf keeps DownloadUser' >&2; exit 1; fi
pacman -Syu --noconfirm --needed base-devel git sudo hyprland nodejs python
rm -rf /var/cache/pacman/pkg/download-*
useradd -m -u 1000 user
printf 'user ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/user
chmod 440 /etc/sudoers.d/user
if [[ -n $helper ]]; then
  runuser -u user -- bash -c 'cd && git clone -q "https://aur.archlinux.org/$1.git" && cd "${1:?}" && makepkg -si --noconfirm && cd && rm -rf -- "${1:?}"' _ "$helper"
fi
PREPARE
  chmod 755 "$scratch/prepare.sh"
  local name="vgs-readme-install-prepare.$$"
  containers+=("$name")
  podman run --name "$name" -v "$scratch/prepare.sh:/prepare.sh:ro" -v "$cache:/var/cache/pacman/pkg" \
    "$arch_image" /prepare.sh "$arch_helper" >"$scratch/prepare.log" 2>&1 ||
    not_measured "container-setup image=$arch_image" "$(tail -n 20 -- "$scratch/prepare.log")"
  podman commit -q -- "$name" "$prepared" >/dev/null || not_measured "container-setup step=commit"
  prepared_made=true
  podman rm -f -t 0 -- "$name" >/dev/null
}

# The Fedora image every fedora block starts from, made once.
prepare_fedora() {
  [[ $fedora_prepared_made == false ]] || return 0
  pull "$fedora_image"
  cat >"$scratch/prepare-fedora.sh" <<'PREPARE'
#!/usr/bin/env bash
# Runs as root in the preparing container.
set -euo pipefail
printf '[main]\ntsflags=nodocs\n' >/etc/dnf/dnf.conf
dnf -y install sudo
dnf clean all
useradd -m -u 1000 user
printf 'user ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/user
chmod 440 /etc/sudoers.d/user
PREPARE
  chmod 755 "$scratch/prepare-fedora.sh"
  local name="vgs-readme-install-prepare-fedora.$$"
  containers+=("$name")
  podman run --name "$name" -v "$scratch/prepare-fedora.sh:/prepare-fedora.sh:ro" \
    "$fedora_image" /prepare-fedora.sh >"$scratch/prepare-fedora.log" 2>&1 ||
    not_measured "container-setup image=$fedora_image" "$(tail -n 20 -- "$scratch/prepare-fedora.log")"
  podman commit -q -- "$name" "$fedora_prepared" >/dev/null || not_measured "container-setup step=commit"
  fedora_prepared_made=true
  podman rm -f -t 0 -- "$name" >/dev/null
}

prepare_debian() {
  [[ $debian_prepared_made == false ]] || return 0
  pull "$debian_image"
  local name="vgs-readme-install-prepare-debian.$$"
  containers+=("$name")
  podman run --name "$name" "$debian_image" bash -euc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl git sudo hyprland nodejs python3 util-linux xdg-terminal-exec
    useradd -m -u 1000 user
    printf "user ALL=(ALL) NOPASSWD: ALL\n" >/etc/sudoers.d/user
    chmod 440 /etc/sudoers.d/user
  ' >"$scratch/prepare-debian.log" 2>&1 || not_measured "container-setup image=$debian_image" "$(tail -n 20 -- "$scratch/prepare-debian.log")"
  podman commit -q -- "$name" "$debian_prepared" >/dev/null || not_measured "container-setup step=commit"
  debian_prepared_made=true
  podman rm -f -t 0 -- "$name" >/dev/null
}

prepare_nixos() {
  [[ $nixos_prepared_made == false ]] || return 0
  pull "$nix_image"
  cat >"$scratch/prepare-nixos.sh" <<'PREPARE'
set -euo pipefail
flake=github:vanillagreencom/vgshell
output="$(nix build --no-link --print-out-paths "$flake")"
entry="$(readlink -f -- "$output/bin/vgshell")"
# flake.nix owns this dependency entry; test-flake.sh holds its isolated use.
line="$(grep -F '# vgs-nix-path' "$entry")"
[[ $line != *$'\n'* ]]
dependencies="$(env -i "$(command -v bash)" -c 'PATH=; eval "$1"; printf "%s" "$PATH"' _ "$line")"
hyprland="$(nix shell --inputs-from "$flake" nixpkgs#hyprland --command bash -c 'dirname -- "$(readlink -f -- "$(command -v Hyprland)")"')"
printf '%s\n' "$output" >/vgs-runtime-output
nix_bin="$(dirname -- "$(readlink -f -- "$(command -v nix)")")"
printf '%s\n' "$hyprland:$dependencies:$nix_bin:$PATH" >/vgs-runtime-path
nix-store -qR "$output" "${hyprland%/bin}" > /vgs-runtime-closure
mkdir -p /usr/lib
printf 'ID=nixos\nNAME="VGS container-only NixOS identity fixture"\n' >/usr/lib/os-release
: >/etc/NIXOS
printf 'readme-install: fixture=nixos interpreter=%s dependency_root=%s\n' "$(command -v bash)" "$output"
PATH="$hyprland:$dependencies:$PATH"
if command -v vgshell; then exit 1; fi
[[ ! -e /etc/os-release && ! -e /bin/bash ]]
nix --version
PREPARE
  local name="vgs-readme-install-prepare-nixos.$$"
  containers+=("$name")
  podman run --name "$name" -v "$scratch/prepare-nixos.sh:/prepare-nixos.sh:ro" -v "$nix_volume:/nix" \
    -e 'NIX_CONFIG=experimental-features = nix-command flakes' "$nix_image" bash /prepare-nixos.sh >"$scratch/prepare-nixos.log" 2>&1 ||
    not_measured "container-setup image=$nix_image" "$(tail -n 20 -- "$scratch/prepare-nixos.log")"
  podman commit -q -- "$name" "$nixos_prepared" >/dev/null || not_measured "container-setup step=commit"
  nixos_prepared_made=true
  podman rm -f -t 0 -- "$name" >/dev/null
}

measured=0
unpublished=()
current_block=""
container=""
user=""
container_env=()
container_exec() {
  podman exec --user "$user" --workdir "$home" -e HOME="$home" -e XDG_RUNTIME_DIR="$runtime" "${container_env[@]}" -- "$container" "$@"
}
closure_size() { # CONTAINER STORE_PATH...
  local owner="$1" sizes bytes path total=0
  shift
  sizes="$(podman exec -- "$owner" du -sb --count-links -- "$@")" || return
  while read -r bytes path; do total=$((total + bytes)); done <<<"$sizes"
  printf '%s\n' "$total"
}
space_check() { # BYTES DIRECTORY...
  python3 - "$@" <<'PY'
import os, sys
size = int(sys.argv[1])
for path in sys.argv[2:]:
    fs = os.statvfs(path)
    free = fs.f_bavail * fs.f_frsize
    print(f"readme-install: space path={path} closure_bytes={size} free_bytes={free}")
    if free - size < 3_000_000_000:
        raise SystemExit(1)
PY
}
run_block_start() { # BLOCK
  local image
  if [[ ${block_image[$1]} == fedora ]]; then
    prepare_fedora
    image="$fedora_prepared" user=user
  elif [[ ${block_image[$1]} == debian ]]; then
    prepare_debian
    image="$debian_prepared" user=user
  elif [[ ${block_image[$1]} == nixos || ${block_image[$1]} == nix ]]; then
    prepare_nixos
    image="$nixos_prepared" user=user
  else
    prepare_arch
    image="$prepared" user=user
  fi
  container="vgs-readme-install-$1.$$"
  containers+=("$container")
  local run_args=(-d --name "$container")
  if [[ ${block_image[$1]} == nixos || ${block_image[$1]} == nix ]]; then
    run_args+=(-v /nix -e $'NIX_CONFIG=experimental-features = nix-command flakes\nbuild-users-group =')
  fi
  podman run "${run_args[@]}" "$image" sleep infinity >/dev/null 2>"$scratch/start.log" ||
    not_measured "container-start image=$image" "$(cat -- "$scratch/start.log")"
  home="/home/$user" runtime=/run/user/1000
  container_env=()
  if [[ ${block_image[$1]} == nixos || ${block_image[$1]} == nix ]]; then
    local candidate
    candidate="$(podman inspect --format '{{range .Mounts}}{{if eq .Destination "/nix"}}{{.Name}}{{end}}{{end}}' "$container")" || not_measured "container-setup step=private-store"
    [[ -n $candidate && $candidate != "$nix_volume" ]] || not_measured "container-setup step=private-store"
    nixos_volume="$candidate"
    # Nix's export/import carries registrations and references to the new
    # private store. Only that volume is handed to the curl install's user.
    local transfer="vgs-readme-install-nixos-closure-$1.$$"
    containers+=("$transfer")
    podman run -d --name "$transfer" -v "$nix_volume:/nix" "$nixos_prepared" sleep infinity >/dev/null || not_measured "container-setup step=closure-source"
    local closure paths=() bytes destination output
    closure="$(podman exec -- "$transfer" cat /vgs-runtime-closure)" || not_measured "container-setup step=closure-read"
    mapfile -t paths <<<"$closure"
    bytes="$(closure_size "$transfer" "${paths[@]}")" || not_measured "container-setup step=closure-size"
    destination="$(podman volume inspect --format '{{.Mountpoint}}' "$nixos_volume")" || not_measured "container-setup step=private-store-path"
    space_check "$bytes" "$destination" || not_measured "container-setup step=private-store-space"
    podman exec -- "$transfer" nix-store --export "${paths[@]}" 2>"$scratch/export-nixos.log" |
      podman exec -i -- "$container" nix-store --import >"$scratch/import-nixos.log" 2>&1 ||
      not_measured "container-setup step=private-store-import" "$(tail -n 20 -- "$scratch/import-nixos.log")" "$(tail -n 20 -- "$scratch/export-nixos.log")"
    # The Nix image's account files link into its store. Detach them only
    # after acquiring the private store, before any account write.
    podman exec -- "$container" bash -euc '
      for file in /etc/passwd /etc/group; do
        copy="$(mktemp "$file.vgs.XXXXXX")"
        cat -- "$file" >"$copy"
        chmod 644 "$copy"
        mv -T -- "$copy" "$file"
        [[ ! -L $file && $(readlink -f -- "$file") == "$file" ]]
      done
      printf "user:x:1000:1000:VGS install test:/home/user:/bin/sh\n" >>/etc/passwd
      printf "user:x:1000:\n" >>/etc/group
      mkdir -p /home/user
      chown 1000:1000 /home/user
    ' >"$scratch/private-account.log" 2>&1 || not_measured "container-setup step=private-account" "$(cat -- "$scratch/private-account.log")"
    podman exec -- "$container" chown -R 1000:1000 /nix || not_measured "container-setup step=private-store-owner"
    container_path="$(podman exec -- "$container" cat /vgs-runtime-path)" || not_measured "container-setup step=runtime-path"
    container_env=(-e "PATH=$container_path")
    container_exec bash -euc '[[ $(id -u) == 1000 && $(id -g) == 1000 && -O $HOME && -w $HOME && ! -L /etc/passwd && ! -L /etc/group ]]' ||
      not_measured "container-setup step=private-user"
    output="$(container_exec cat /vgs-runtime-output)" || not_measured "container-setup step=dependency-root"
    container_exec nix-store --add-root "$home/dependency-proof" --realise "$output" >"$scratch/private-store-proof.log" 2>&1 ||
      not_measured "container-setup step=private-store-user" "$(cat -- "$scratch/private-store-proof.log")"
    container_exec rm -- "$home/dependency-proof" || not_measured "container-setup step=private-store-user-cleanup"
  fi
  local syntax="${block_commands[$1]}"
  [[ -z $export_dir ]] || syntax+="$(declare -f closure_size space_check export_tree)"
  container_exec bash -n -c "$syntax" >"$scratch/syntax-$1.log" 2>&1 ||
    refuse 1 "block=$1 syntax=refused" "$(cat -- "$scratch/syntax-$1.log")"
  printf 'readme-install: syntax block=%s image=%s\n' "$1" "$image"
  # A login session's runtime directory, where `vgshell run` keeps its lock.
  [[ $user == root ]] || podman exec -- "$container" install -d -m 700 -o user -g user /run/user/1000 >/dev/null 2>"$scratch/start.log" ||
    not_measured "container-setup step=runtime-dir" "$(cat -- "$scratch/start.log")"
}

export_tree() { # VERSION_COMMAND
  local resolve_command resolved target="$export_dir/line-$line-$channel" nix_output="" closure path engine_bin="" engine_store engine_root
  local closure_bytes=0 store_paths=()
  [[ -n $export_dir && ! -v exported[$block] ]] || return 0
  resolve_command="${1% --version}"
  if [[ $channel == nix ]]; then
    # nix run's package is already built. Its bin link selects the same
    # installed entry point that command -v selects on other channels.
    resolve_command="${1% -- --version}"
    nix_output="$(container_exec nix build --no-link --print-out-paths "${resolve_command#nix run }")" || refuse 1 "line=$line export=nix-output-failed"
    printf -v resolve_command '%q' "$nix_output/bin/vgshell"
  elif [[ $channel == curl-nixos ]]; then
    nix_output="$(container_exec cat /vgs-runtime-output)" || refuse 1 "line=$line export=nix-output-failed"
  fi
  resolved="$(container_exec bash -euc 'entry="$(readlink -f -- "$(command -v '"$resolve_command"')")"; dirname -- "$(dirname -- "$entry")"')" || refuse 1 "line=$line export=resolve-failed"
  if [[ $channel == curl-nixos ]]; then
    engine_bin="$(container_exec bash -euc 'tree="$1"; revision=-; [[ ! -d $tree/.git ]] || revision="$(git -C "$tree" rev-parse HEAD)"; node "$tree/bin/lib/engine.js" path "$HOME/.local/share" "$tree" "$revision"' _ "$resolved")" || refuse 1 "line=$line export=engine-failed"
    [[ -n $engine_bin ]] || refuse 1 "line=$line export=engine-missing"
  fi
  if [[ -n $nix_output ]]; then
    local roots=("$nix_output")
    if [[ -n $engine_bin ]]; then
      engine_store="$(container_exec readlink -f -- "${engine_bin%/bin}")" || refuse 1 "line=$line export=engine-store-failed"
      roots+=("$engine_store")
      printf 'readme-install: dependency line=%s channel=%s root=%s engine=%s\n' "$line" "$channel" "$nix_output" "$engine_store"
    fi
    closure="$(container_exec nix-store -qR "${roots[@]}")" || refuse 1 "line=$line export=closure-failed"
    mapfile -t store_paths <<<"$closure"
    closure_bytes="$(closure_size "$container" "${store_paths[@]}")" || refuse 1 "line=$line export=closure-size-failed"
    mkdir -p -- "$export_dir"
    space_check "$closure_bytes" "$export_dir" "${TMPDIR:-/tmp}" || refuse 1 "line=$line export=space"
  fi
  mkdir -p -- "$export_dir"
  mkdir -- "$target" || refuse 1 "line=$line export=target-exists" "$target"
  podman cp -- "$container:$resolved/." "$target/" || refuse 1 "line=$line export=copy-failed"
  if [[ -n $engine_bin ]]; then
    mkdir -- "$target/.engines"
    engine_root="${engine_bin%/bin}"
    ln -s -- "$engine_store" "$target/.engines/${engine_root##*/}" || refuse 1 "line=$line export=engine-copy-failed"
  fi
  if [[ -n $nix_output ]]; then
    mkdir -p -- "$target/nix/store"
    for path in "${store_paths[@]}"; do
      podman cp -- "$container:$path" "$target/nix/store/" || refuse 1 "line=$line export=store-failed"
    done
    printf 'readme-install: tree line=%s channel=%s path=%s store=%s\n' "$line" "$channel" "$target" "$target/nix"
  else
    printf 'readme-install: tree line=%s channel=%s path=%s\n' "$line" "$channel" "$target"
  fi
  exported[$block]=true
}

for row in "${rows[@]}"; do
  IFS=$'\t' read -r block line channel needs vgshell helper command <<<"$row"
  if [[ ${published[$needs]} != yes ]]; then
    unpublished+=("line=$line needs=$needs")
    continue
  fi
  if [[ $block != "$current_block" ]]; then
    [[ -z $container ]] || podman rm -f -t 0 -- "$container" >/dev/null
    if [[ -n $nixos_volume ]]; then
      podman volume rm -- "$nixos_volume" >/dev/null || refuse 1 "private-store=cleanup-failed volume=$nixos_volume"
      nixos_volume=""
    fi
    run_block_start "$block"
    current_block="$block"
  fi
  home="/home/$user" runtime=/run/user/1000
  [[ $user != root ]] || home=/root runtime=/run/user/0
  log="$scratch/line-$line.log"
  started=$SECONDS
  status=0
  case "${block_image[$block]}" in
    # The newline feeder is the wrapper's own child, ended once script
    # returns: as a pipeline's head it held the wrapper up to its next
    # write, and as script's own child it kept script from exiting.
    arch|debian|nixos) wrapper='printf -v argv "%q " timeout "$1" bash -o pipefail -c "$2"; exec 3< <(while printf "\\n"; do sleep 1; done 2>/dev/null); feeder=$!; script -qE never -ec "$argv" /dev/null <&3 3<&-; status=$?; kill "$feeder"; exit "$status"' ;;
    fedora) wrapper='yes y | timeout "$1" bash -o pipefail -c "$2"' ;;
    *) wrapper='yes "" | timeout "$1" bash -o pipefail -c "$2"' ;;
  esac
  container_exec env PARU_PAGER=cat \
    bash -c "$wrapper" _ "$command_seconds" "$command" >"$log" 2>&1 || status=$?
  seconds=$((SECONDS - started))
  if [[ $vgshell == start ]]; then
    grep -q -E $'^vgshell: refused: hyprland=unreachable\r?$' -- "$log" && [[ $status -eq 69 ]] ||
      refuse 1 "line=$line exit=$status want=69-hyprland=unreachable command=$command" "$(tail -n 40 -- "$log")"
  elif [[ $status -eq 124 ]]; then
    refuse 1 "line=$line timeout=$command_seconds command=$command" "$(tail -n 40 -- "$log")"
  else
    [[ $status -eq 0 ]] || refuse 1 "line=$line exit=$status command=$command" "$(tail -n 40 -- "$log")"
  fi
  echo "readme-install: ok line=$line channel=$channel exit=$status seconds=$seconds"
  version_command=""
  case "$channel" in
    aur) version_command='vgshell --version' ;;
    fedora) [[ $command != *' dnf install '* ]] || version_command='vgshell --version' ;;
    curl|curl-debian|curl-nixos) [[ $command == *--uninstall* ]] || version_command='~/.local/bin/vgshell --version' ;;
    nix) version_command="${command% -- *} -- --version" ;;
    checkout) [[ $vgshell == - ]] || version_command='vgshell/bin/vgshell --version' ;;
  esac
  if [[ -n $version_command ]]; then
    version_out="$(container_exec \
      timeout "$command_seconds" bash -o pipefail -c "$version_command" 2>&1)" || refuse 1 "line=$line version=failed" "$version_out"
    if [[ $channel == checkout || ( $channel == curl* && $command == *--git* ) ]]; then
      report_command="${version_command% --version} version --json"
      version_report="$(container_exec \
        timeout "$command_seconds" bash -o pipefail -c "$report_command" 2>&1)" || refuse 1 "line=$line version=report-failed" "$version_report"
      node - "$(<"$repo/VERSION")" "$version_out" "$version_report" <<'JS' || refuse 1 "line=$line version=unexpected" "$version_out"
let report;
try { report = JSON.parse(process.argv[4]); } catch { process.exit(1); }
if (report.version !== process.argv[2]) process.exit(1);
if (process.argv[3] !== `vgshell ${report.describe ?? report.version}`) process.exit(1);
JS
    else
      [[ $version_out == "vgshell $(<"$repo/VERSION")" ]] || refuse 1 "line=$line version=unexpected" "$version_out"
    fi
    echo "readme-install: version line=$line channel=$channel value=$version_out"
    export_tree "$version_command"
  fi
  measured=$((measured + 1))
done

if [[ ${#unpublished[@]} -gt 0 ]]; then
  for entry in "${unpublished[@]}"; do echo "readme-install: status=not-measured reason=unpublished $entry"; done
  echo "readme-install: status=not-measured measured=$measured unpublished=${#unpublished[@]}"
  exit 77
fi
echo "readme-install: ok commands=$measured"
