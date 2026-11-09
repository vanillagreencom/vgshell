# DNS probe stand-ins for Network's smoke row and screenshot scene. Only
# the private product copy changes. Core system actions still reach the
# harness terminal, which records argv and runs no system command.
set -euo pipefail
network_dns_setup() {
  network_dns_saved="$sandbox/network-dns-system.before"
  cp -- "$repo/bin/vgshell-system" "$network_dns_saved"
  python3 - "$repo/bin/vgshell-system" "$sandbox/network-dns-steps" <<'PYDNSPROBE'
import pathlib,shlex,sys
p=pathlib.Path(sys.argv[1]); text=p.read_text()
needle='probe_dns() { # STEP\n'
assert text.count(needle)==1
probe='  while read -r dns_step dns_state dns_reason; do\n    if [[ $dns_step == "$1" ]]; then set_probe "$dns_state" "$dns_reason"; return; fi\n  done < '+shlex.quote(sys.argv[2])+'\n  set_probe unknown fixture-missing; return\n'
p.write_text(text.replace(needle,needle+probe))
PYDNSPROBE
  network_dns_set default
}

network_dns_set() { # default|cloudflare|google|custom|foreign|partial|unknown|denied|absent
  local provider state reason
  : >"$sandbox/network-dns-steps.next"
  for provider in cloudflare google custom; do
    state=needed reason=not-set
    case "$1" in
      cloudflare|google|custom) [[ $provider != "$1" ]] || { state=ready; reason=in-effect; } ;;
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
  cp -- "$network_dns_saved" "$repo/bin/vgshell-system"
}

network_dns_reading() {
  local fields
  fields="$(ipc smoke itemValues window vgs.network Select objectName,currentIndex,lock.locked)" || return
  ipc smoke statusValues vgs.network | py_reply 'import json,sys; dns=json.load(sys.stdin)["network"]["dns"]; field=next(r for r in json.loads(sys.argv[1]) if r["objectName"]=="network-dns-provider"); print(json.dumps([dns["kind"],dns["provider"],field["currentIndex"],field["lock.locked"],bool(dns["hint"] or dns["disabledReason"])]))' "$fields"
}

network_dns_refresh() {
  network_dns_set "$1" || return
  expect "DNS $1: the network asks for a fresh probe" ok ipc vgs.network invoke refresh ""
}
