# The plugin list past the IPC reply bound. The row installs one more
# generated plugin than shell/plugins ships, each with two optional
# requirements, and rescans; the set grows listPlugins alone, past the
# bound in a run of this row with no other row's fixtures. The raw
# listPlugins reply is then paged, the document the harness reassembles
# lists every generated id, `vgsh plugin list` prints a line for each, and
# built, lent, listShellConfig and listTuis, which answer unpaged and
# which no disabled plugin grows, each read whole JSON within the bound.
# The control is a copy of the shell whose listPlugins answers unpaged,
# started as an unguarded qs over the same set: its reply fails the
# oversize check once. The row removes the set and rescans before it ends.
# inputs: shell/shell.qml shell/Core/IpcPages.qml shell/Core/Registry.qml shell/Core/PluginLogic.js shell/Core/PackageManagers.js shell/Core/Plugins.qml shell/Core/Capabilities.qml shell/Core/Config.qml bin/vgsh bin/vgsh-scan bin/vgsh-pkg bin/vgsh-plugin-judge bin/lib/ipc-reply.sh scripts/smoke/fixtures/plugins/acme.bare/*
set -euo pipefail
pages_shipped="$(find "$repo/shell/plugins" -mindepth 2 -maxdepth 2 -name manifest.json | wc -l)"
pages_count=$((pages_shipped + 1))
# The control reads the copy's listPlugins unpaged, so the document must
# stay under 106496 characters, the send buffer's whole read that
# docs/architecture/runtime.md § Process records. It must also stay 8192
# characters under that, room for about four more shipped plugins, so a
# growing set fails here, naming the margin, before a control read can
# be cut.
pages_ceiling=$((106496 - 8192))
pages_before="$(ipc shell listPlugins)" || pages_before=""
pages_ids="$(python3 - "$home/.config/vgs/plugins" "$repo/scripts/smoke/fixtures/plugins/acme.bare/Service.qml" "$pages_count" <<'PY'
import json, os, shutil, sys
root, service, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
ids = []
for n in range(count):
    plugin_id = "acme.many-%02d" % n
    target = os.path.join(root, plugin_id)
    os.makedirs(target)
    shutil.copy(service, os.path.join(target, "Service.qml"))
    requirements = [{
        "command": "vgs-smoke-many-%02d-%d" % (n, k),
        "packages": {"pacman": "vgs-smoke-many-%d" % k, "dnf": "vgs-smoke-many-%d" % k},
        "optional": True,
        "purpose": "Stands in for a tool the plugin offers once it is installed, number %d" % k,
    } for k in range(2)]
    manifest = {"schemaVersion": 1, "id": plugin_id, "name": "Many %02d" % n, "version": "0.1.0", "author": "acme",
                "description": "smoke fixture of the paged plugin list", "kinds": ["service"],
                "entryPoints": {"service": "Service.qml"}, "requirements": requirements}
    with open(os.path.join(target, "manifest.json"), "w") as f:
        json.dump(manifest, f)
    ids.append(plugin_id)
print(" ".join(ids))
PY
)"
if [[ $pages_shipped -gt 0 ]]; then ok "the row generates $pages_count plugins, one more than the $pages_shipped shell/plugins ships, over a listPlugins document of ${#pages_before} chars"; else fail "no manifest under $repo/shell/plugins: the count of shipped plugins is broken"; fi

# The generated ids a listPlugins document READ lists, as a count, from
# the transport READ names: ipc for the runner's shell.
pages_known() { # READ...
  "$@" shell listPlugins | py_reply 'import json, sys
print(sum(1 for p in json.load(sys.stdin)["plugins"] if p["id"].startswith("acme.many-")))'
}
rescan "the rescan after generating the set lands"
expect "the rescan lists every generated plugin" "$pages_count" pages_known ipc

# (a) The raw reply, before reassembly.
raw_list() {
  ipc_call_last "$repo/bin/vgsh" shell listPlugins || return
  if vgs_ipc_paged_id shell "$ipc_last_reply"; then echo paged; else echo "unpaged chars=${#ipc_last_reply}"; fi
}
expect "the raw listPlugins reply is paged" paged raw_list
# (b) The reassembled document, whole JSON, with every generated id.
pages_missing() {
  ipc shell listPlugins | py_reply 'import json, sys
listed = {p["id"] for p in json.load(sys.stdin)["plugins"]}
print(" ".join(i for i in sys.argv[1].split() if i not in listed) or "none")' "$pages_ids"
}
expect "the reassembled listPlugins document lists every generated id" none pages_missing
# (c) `vgsh plugin list` through the sandbox: a plugin line per id.
cli_missing() {
  local listed id missing=""
  listed="$("${shell_env[@]}" "$repo/bin/vgsh" plugin list)" || return
  for id in $pages_ids; do
    grep -q -E "^${id//./\\.} +0\.1\.0 +disabled +kinds=service$" <<<"$listed" || missing+="$id "
  done
  echo "${missing:-none}"
}
expect "vgsh plugin list prints a line per generated id" none cli_missing
# (d) listPlugins and the four reads that answer unpaged, through the
# harness transport, which logs an unpaged reply past the bound: each
# reads whole JSON, the four within the bound. The label carries each
# document's size.
json_shape() { py_reply 'import json, sys
try:
    json.load(sys.stdin)
    print("json")
except ValueError:
    print("unparseable")'; }
shell_reads() {
  local fn doc shape sizes=""
  for fn in listPlugins built lent listShellConfig listTuis; do
    doc="$(ipc shell "$fn")" || { echo "$fn=unreadable reply=${doc:0:80}"; return 1; }
    shape="$(json_shape <<<"$doc")" || { echo "$fn=$shape"; return 1; }
    [[ $shape == json ]] || { echo "$fn=$shape reply=${doc:0:80}"; return 1; }
    if [[ $fn != listPlugins ]] && ((${#doc} > ipc_reply_chars)); then echo "$fn=${#doc} past the bound"; return 1; fi
    sizes+="$fn=${#doc} "
  done
  echo "${sizes% }"
}
if pages_sizes="$(shell_reads)"; then
  ok "every shell read is whole JSON, the unpaged ones within $ipc_reply_chars chars: $pages_sizes"
else
  fail "a shell read of the generated set: $pages_sizes"
fi
ipc_oversize_check "a shell read of the generated set"

# The control: a copy whose listPlugins answers unpaged, keeping the
# call's text, read through the harness transport with its own oversize
# log, fails the oversize check once.
pages_copy="$sandbox/plugin-pages-unpaged"; mkdir -p -- "$pages_copy"
cp -R -- "$repo/shell" "$pages_copy/shell"
for dir in bin config themes scripts; do ln -s -- "$repo/$dir" "$pages_copy/$dir"; done
paged_call='function listPlugins(): string { return IpcPages.answer(Registry.listJson()); }'
if [[ $(grep -c -F -- "$paged_call" "$pages_copy/shell/shell.qml") == 1 ]]; then
  python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); open(p, "w").write(s.replace(a, b))' "$pages_copy/shell/shell.qml" "$paged_call" 'function listPlugins(): string { return Registry.listJson(); }'
  spawn "$sandbox/plugin-pages-unpaged.log" "${shell_env[@]}" qs -p "$pages_copy/shell"
  pages_copy_pid="$spawn_pid"
  copy_guarded=""
  for _ in $(seq 1 100); do
    copy_guarded="$(ipc_at "$pages_copy_pid" shell guarded)" && [[ $copy_guarded == false ]] && break
    sleep 0.2
  done
  if [[ $copy_guarded == false ]]; then ok "the unpaged copy answers as an unguarded qs"; else fail "the unpaged copy: guarded=$copy_guarded"; fi
  # Every read of the copy logs to the control's own oversize log, so the
  # row's stays clear of the copy's planted replies.
  copy_known() { (ipc_oversize_log="$sandbox/plugin-pages-copy.log"; pages_known ipc_at "$pages_copy_pid"); }
  expect_poll "the unpaged copy's scan lists every generated plugin" "$pages_count" copy_known
  unpaged_control() {
    (failures=0; ipc_oversize_log="$sandbox/plugin-pages-control.log"; rm -f -- "$ipc_oversize_log"; ipc_at "$pages_copy_pid" shell listPlugins >/dev/null; ipc_oversize_check control >/dev/null; [[ $failures -eq 1 && ! -s $ipc_oversize_log ]] && echo failed-once || echo "failures=$failures")
  }
  # The copy's unpaged document lies past the bound, so the control can
  # fail, and under the ceiling, so its read is never cut.
  copy_size() { (ipc_oversize_log="$sandbox/plugin-pages-copy.log"; ipc_at "$pages_copy_pid" shell listPlugins); }
  pages_copy_doc="$(copy_size)" || pages_copy_doc=""
  if [[ $pages_copy_doc != '{'* ]]; then
    fail "the unpaged copy's listPlugins is unreadable: ${pages_copy_doc:0:80}"
  elif ((${#pages_copy_doc} <= ipc_reply_chars)); then
    fail "the unpaged copy's listPlugins is ${#pages_copy_doc} chars, within the $ipc_reply_chars bound: the control cannot fail"
  elif ((${#pages_copy_doc} >= pages_ceiling)); then
    fail "the unpaged copy's listPlugins is ${#pages_copy_doc} chars, past the $pages_ceiling ceiling, 8192 under the 106496-char whole read: generate lighter plugins"
  else
    ok "the unpaged copy's listPlugins is ${#pages_copy_doc} chars, past the bound and under the $pages_ceiling ceiling"
  fi
  expect "control: an unpaged listPlugins over the generated set fails the oversize check once" failed-once unpaged_control
  kill -TERM "$pages_copy_pid" 2>/dev/null || true
else
  fail "the paged listPlugins call occurs once in $pages_copy/shell/shell.qml"
fi

for id in $pages_ids; do rm -rf -- "${home:?}/.config/vgs/plugins/$id"; done
rescan "the rescan after removing the set lands"
expect "the rescan lists no generated plugin" 0 pages_known ipc
