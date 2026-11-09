# DNS probe stand-ins for Network's smoke row and screenshot scene. Only
# the private product copy changes. Core system actions still reach the
# harness terminal, which records argv and runs no system command.
set -euo pipefail
network_dns_setup() {
  network_dns_pending_copy=""
  network_dns_saved="$sandbox/network-dns-system.before"
  cp -- "$repo/bin/vgshell-system" "$network_dns_saved"
  python3 - "$repo/bin/vgshell-system" "$sandbox/network-dns-steps" <<'PYDNSPROBE'
import pathlib,shlex,sys
p=pathlib.Path(sys.argv[1]); text=p.read_text()
needle='probe_dns() { # STEP\n'
assert text.count(needle)==1
probe='  while read -r dns_step dns_state dns_reason; do\n    if [[ $dns_step == "$1" ]]; then set_probe "$dns_state" "$dns_reason"; return; fi\n  done < '+shlex.quote(sys.argv[2])+'\n  set_probe unknown fixture-missing; return\n'
text=text.replace(needle,needle+probe)
needle='detect_system() {\n'
assert text.count(needle)==1
managed='  if [[ -f '+shlex.quote(sys.argv[2]+'.nixos')+' ]]; then detected_system=nix; return; fi\n'
p.write_text(text.replace(needle,needle+managed))
PYDNSPROBE
  network_dns_set default
}

network_dns_set() { # [nixos-]default|cloudflare|google|custom|foreign|partial|unknown|denied|absent
  local provider state reason reading="$1"
  rm -f -- "$sandbox/network-dns-steps.nixos"
  if [[ $reading == nixos-* ]]; then
    : >"$sandbox/network-dns-steps.nixos"
    reading="${reading#nixos-}"
  fi
  : >"$sandbox/network-dns-steps.next"
  for provider in cloudflare google custom; do
    state=needed reason=not-set
    case "$reading" in
      cloudflare|google|custom) [[ $provider != "$reading" ]] || { state=ready; reason=in-effect; } ;;
      foreign) reason=foreign ;;
      partial) [[ $provider != cloudflare ]] || reason=partial ;;
      unknown) state=unknown reason=resolved-inactive ;;
      denied) state=denied reason=foreign-dropin ;;
      absent) state=absent reason=no-profile ;;
      default) ;;
      *) fail "network DNS: unknown fixture state $1"; return 1 ;;
    esac
    printf 'dns-%s %s %s\n' "$provider" "$state" "$reason" >>"$sandbox/network-dns-steps.next"
  done
  mv -- "$sandbox/network-dns-steps.next" "$sandbox/network-dns-steps"
}

network_dns_restore() {
  network_dns_pending_end
  cp -- "$network_dns_saved" "$repo/bin/vgshell-system"
}

# A completed system report always holds every step. Before the first
# report, the capability exposes {}. Stand in only that absent input in a
# private plugin copy; dnsReading and the Settings field remain unchanged.
network_dns_pending_begin() {
  network_dns_pending_copy="$home/.config/vgshell/plugins/vgs.network"
  if [[ -e $network_dns_pending_copy ]]; then
    fail "DNS pending: a private Network copy already exists"
    network_dns_pending_copy=""
    return 1
  fi
  mkdir -p -- "$network_dns_pending_copy"
  cp -R -- "$repo/shell/plugins/vgs.network/." "$network_dns_pending_copy/"
  python3 - "$network_dns_pending_copy/Service.qml" <<'PYDNSPENDING'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); text=p.read_text()
needle='readonly property var dnsSteps: shell === null ? ({}) : shell.system.state'
assert text.count(needle)==1
p.write_text(text.replace(needle,'readonly property var dnsSteps: ({})'))
PYDNSPENDING
  rescan "the pre-report DNS input is discovered"
  expect "the pre-report DNS pane opens" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
}

network_dns_pending_end() {
  [[ -n $network_dns_pending_copy ]] || return 0
  rm -rf -- "${network_dns_pending_copy:?}"
  network_dns_pending_copy=""
  rescan "the reported DNS input is restored"
  expect "the reported DNS pane opens" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
}

network_dns_reading() {
  local fields
  fields="$(ipc smoke itemValues window vgs.network Select objectName,currentIndex,lock.locked)" || return
  ipc smoke statusValues vgs.network | py_reply 'import json,sys; dns=json.load(sys.stdin)["network"]["dns"]; field=next(r for r in json.loads(sys.argv[1]) if r["objectName"]=="network-dns-provider"); print(json.dumps([dns["kind"],dns["provider"],field["currentIndex"],field["lock.locked"],bool(dns["hint"] or dns["disabledReason"])]))' "$fields"
}

network_dns_refresh() {
  network_dns_pending_end
  if [[ $1 == pending ]]; then network_dns_pending_begin; return; fi
  network_dns_set "$1" || return
  expect "DNS $1: the network asks for a fresh probe" ok ipc vgs.network invoke refresh ""
}
