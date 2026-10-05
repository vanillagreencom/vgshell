# Sourced by scripts/smoke/rows/webapps.sh and scripts/sandbox-shots.sh,
# after the harness. No host browser may open from the sandbox: the Web
# Apps service opens a site with the default browser's desktop entry, else
# with the first Chromium-family browser entry it finds, and a host entry
# names its browser by an absolute path, so no stand-in on PATH hides it.
# Quickshell 0.3.1 drops every entry of an id whose file in an earlier data
# directory says Hidden=true (DesktopEntryManager::onScanCompleted in
# src/core/desktopentry.cpp, which scans the data home last so it wins), and
# the sandbox's own data home comes first, so a shadow there hides the
# host's entry of that id from DesktopEntries.byId and its applications.
#
# webapps_shadows_plant: one Hidden=true entry in the sandbox's data home
# for each desktop id under the data directories, the shell's default
# /usr/local/share:/usr/share and the harness's XDG_DATA_DIRS, whose entry
# the service's own judge, WebApps.isChromium run under node, takes for a
# browser, each id listed in $sandbox/webapps-shadows; 1 when the walk or
# a write fails. webapps_shadows_remove: removes exactly the shadows that
# list names, and the list.
webapps_shadows="$sandbox/webapps-shadows"
webapps_shadows_plant() {
  local ids id
  ids="$("$node_bin" -e '
const fs = require("fs"), path = require("path");
const WebApps = require(process.argv[1]).load(process.argv[2]);
const dirs = [...new Set(process.argv[3].split(":").filter(d => d !== "").map(d => path.join(d, "applications")))];
const found = new Set();
const walk = (root, dir) => {
  let names;
  try { names = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { if (e.code === "ENOENT") return; throw e; }
  for (const name of names) {
    const file = path.join(dir, name.name);
    if (name.isDirectory()) { walk(root, file); continue; }
    if (!name.name.endsWith(".desktop")) continue;
    const id = path.relative(root, file).slice(0, -".desktop".length).split(path.sep).join("-");
    const exec = /^Exec=(.*)$/m.exec(fs.readFileSync(file, "utf8"));
    const argv = exec === null ? [] : exec[1].trim().split(/\s+/).map(w => w.replace(/^"|"$/g, ""));
    if (WebApps.isChromium(id, argv)) found.add(id);
  }
};
for (const dir of dirs) walk(dir, dir);
process.stdout.write([...found].sort().join("\n"));
' "$repo/bin/lib/qml-library.js" "$repo/shell/plugins/vgs.webapps/WebApps.js" "/usr/local/share:/usr/share:${XDG_DATA_DIRS:-}")" || return 1
  mkdir -p -- "$home/.local/share/applications" || return 1
  : >"$webapps_shadows" || return 1
  for id in $ids; do
    [[ -e $home/.local/share/applications/$id.desktop ]] && { printf 'webapps_shadows_plant: refused: exists=%s\n' "$id.desktop" >&2; return 1; }
    printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$id" >"$home/.local/share/applications/$id.desktop" || return 1
    printf '%s\n' "$id" >>"$webapps_shadows" || return 1
  done
}
webapps_shadows_remove() {
  local id
  [[ -f $webapps_shadows ]] || return 0
  while IFS= read -r id; do
    [[ -n $id ]] && rm -f -- "$home/.local/share/applications/$id.desktop"
  done <"$webapps_shadows"
  rm -f -- "$webapps_shadows"
}
