#!/usr/bin/env bash
# Set up SSH key sign-in from this computer to HOST, the one argument, so
# Remote desktop's Connect signs in with no password: gliff starts ssh with
# no terminal and no askpass, so only a key ssh can use unattended works:
# a key with no passphrase, or one the session's SSH agent holds.
#
# The key is the first default private key that exists, id_ed25519,
# id_ecdsa or id_rsa; ssh-keygen makes a new id_ed25519 only when none of
# them exists and id_ed25519.pub does not either, with stdin closed, so it
# never asks to overwrite a file. A key that is a broken link or that this
# account cannot read stops the step with that cause. A key other users
# may read gets `chmod 600`, since ssh ignores it. A key with no .pub gets
# one derived with `ssh-keygen -y`. A key with a passphrase the agent does
# not hold is loaded with ssh-add, and with no agent running the step stops
# before it changes anything. Then ssh-copy-id installs the public key on
# HOST. Every password and passphrase is typed into this terminal, to the
# OpenSSH tool that asks, and VGS never reads or stores one. A new key has
# no passphrase, since no window can ask for one when gliff connects;
# ssh-keygen writes it readable only by its owner.
set -euo pipefail
# shellcheck source=/dev/null
source "${VGS_TUI_LIB:?}"
host="${1:-}"
# The host pattern Remote.js holds a profile's Computer to.
[[ $# == 1 && $host =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*(@[A-Za-z0-9_][A-Za-z0-9._:-]*)?$ ]] || { vgs_tui_error "This sign-in request names no computer."; exit 2; }

key=""
for name in id_ed25519 id_ecdsa id_rsa; do
  # -L too: a link whose target is gone still names the user's key.
  if [[ -e $HOME/.ssh/$name || -L $HOME/.ssh/$name ]]; then key="$HOME/.ssh/$name"; break; fi
done
shown() { printf '%s' "${1/#"$HOME"/\~}"; }
# holds KEYS: whether KEYS, the list `ssh-add -L` printed, holds the key.
holds() { grep -qF -- "$(cut -d' ' -f2 <"$key.pub")" <<<"$1"; }
make=false exposed=false derive=false add=false locked=false
if [[ -z $key ]]; then
  key="$HOME/.ssh/id_ed25519"
  # ssh-keygen replaces a .pub without asking. A .pub alone is a key whose
  # private half an agent or a hardware token holds.
  if [[ -e $key.pub || -L $key.pub ]]; then
    vgs_tui_error "You have the public key $(shown "$key.pub") but not its private key, and a new key would replace it. Nothing was changed."
    exit 1
  fi
  make=true
else
  if [[ ! -e $key ]]; then
    vgs_tui_error "Your key $(shown "$key") is a link to a file that no longer exists. Nothing was changed."
    exit 1
  fi
  if [[ ! -r $key ]]; then
    vgs_tui_error "Your account cannot read your key $(shown "$key"). Nothing was changed."
    exit 1
  fi
  # ssh, ssh-add and ssh-keygen refuse a key file the user owns that group
  # or other may read or write (sshkey_perm_ok in OpenSSH's authfile.c).
  [[ -O $key ]] && (( 8#$(stat -L -c %a -- "$key") & 8#077 )) && exposed=true
  [[ -f $key.pub ]] || derive=true
  # A key that opens with an empty passphrase needs nothing more; one with
  # a passphrase works for gliff only while the agent holds it. The probe
  # reads the key through a pipe, whose mode is 0600, so a key other users
  # may read still answers: checked with OpenSSH 10.6p1 on 2026-11-03.
  if ! cat -- "$key" | ssh-keygen -y -P '' -f /dev/stdin >/dev/null 2>&1; then
    locked=true
    # ssh-add -L exits 1 for an agent that holds no key, 2 for no agent.
    held="" agent=0
    held="$(ssh-add -L 2>/dev/null)" || agent=$?
    if [[ $agent == 2 ]]; then
      vgs_tui_error "Your key $(shown "$key") has a passphrase, and this session has no SSH agent to hold it. Remote desktop cannot type a passphrase, so it cannot use this key."
      exit 1
    fi
    if $derive || ! holds "$held"; then add=true; fi
  fi
fi
commands=()
$exposed && commands+=("chmod 600 $(shown "$key")")
$make && commands+=("ssh-keygen -t ed25519 -N '' -f $(shown "$key")")
$derive && commands+=("ssh-keygen -y -f $(shown "$key") > $(shown "$key").pub")
$add && commands+=("ssh-add $(shown "$key")")
commands+=("ssh-copy-id -i $(shown "$key").pub -- $host")

lines=("This computer signs in to $host with a key, so Connect needs no password.")
$exposed && lines+=("Other accounts on this computer have access to your key, so ssh will not use it. It becomes readable only by you.")
$add && lines+=("Your key has a passphrase. Type it when ssh-add asks: your SSH agent keeps the key open until you sign out.")
lines+=("Type the password of your account on $host when it asks. VGS does not see or keep it.")
vgs_tui_header "Set up sign-in to $host" "${lines[@]}"
vgs_tui_commands "${commands[@]}"
status=0
vgs_tui_confirm "Set up sign-in?" || status=$?
case "$status" in
  0) ;;
  1) exit 0 ;;
  *) exit "$status" ;;
esac

if $exposed; then
  vgs_tui_step "Making the key readable only by you"
  chmod 600 -- "$key" || { vgs_tui_error "VGS could not change who can read the key $(shown "$key")."; exit 1; }
fi
if $make; then
  vgs_tui_step "Making a key"
  mkdir -p -m 700 -- "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N '' -f "$key" </dev/null || { vgs_tui_error "ssh-keygen could not make a key."; exit 1; }
fi
if $derive; then
  vgs_tui_step "Writing the public key"
  ssh-keygen -y -f "$key" >"$key.pub.new" && mv -- "$key.pub.new" "$key.pub" || { rm -f -- "$key.pub.new"; vgs_tui_error "ssh-keygen could not read the key $(shown "$key")."; exit 1; }
fi
if $add; then
  vgs_tui_step "Loading the key into your SSH agent"
  ssh-add "$key" || { vgs_tui_error "The SSH agent did not take the key, so Remote desktop cannot use it."; exit 1; }
fi
vgs_tui_step "Copying the key to $host"
ssh-copy-id -i "$key.pub" -- "$host" || { vgs_tui_error "The key was not copied to $host."; exit 1; }
# Only this key: an agent's other key or another file's sign-in proves
# nothing about it. With a passphrase, ssh takes it from the agent.
if said="$(ssh -o BatchMode=yes -o ConnectTimeout=15 -o IdentitiesOnly=yes -i "$key" -- "$host" true </dev/null 2>&1 >/dev/null)"; then
  vgs_tui_success "This computer signs in to $host with its key."
elif $locked && ! holds "$(ssh-add -L 2>/dev/null)"; then
  vgs_tui_error "This computer still cannot sign in to $host: the SSH agent does not hold the key's passphrase."
  exit 1
else
  # ssh prints its cause lines, such as an agent refusing to sign, before
  # its `Permission denied` summary, and ends each line with \r\n: checked
  # with OpenSSH 10.6p1 against a scratch sshd on 2026-11-03. Every line is
  # shown, without the \r.
  details=""
  while IFS= read -r line; do
    if [[ -n $line ]]; then details+=$'\n'"$line"; fi
  done <<<"${said//$'\r'/}"
  vgs_tui_error "This computer still cannot sign in to $host with its key.${details:+ ssh said:}$details"
  exit 1
fi
