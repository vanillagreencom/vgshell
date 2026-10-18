#!/usr/bin/env node
// The Google Drive runner, shell/plugins/vgs.google-drive/bin/google-drive, end to
// end against rclone's `local` backend: a Drive-side add and change reach
// the mirror after one run; a local edit since the last download keeps
// both versions and reads `both-changed`; a Drive deletion keeps the file and
// reads `removed-on-drive`; a rename reads `renamed` where the backend has
// object ids; a run during another is `busy` and starts no second copy; a
// run killed mid-copy reads as interrupted; pause persists across processes
// and a paused run copies nothing; an edit saved as a copy ends is kept as
// `both-changed` by the next run; offline and authorization failures keep
// the last success; a download that ran to its end past a file Drive could
// not open ends synced with that file and a doubled name to review and
// keeps that file's baseline, while a network cause in the same lines, an
// error that names no file and a fatal exit stay a failure; a doubled
// name is identical or different, and the account's own or not, from one
// read-only listing of its folder that runs only when the copy met a
// doubled name; each review record needs the user or nothing, and only
// the ones that need the user ask for attention or change its key; the
// earlier doubled-name record is dropped on the first invocation, and a
// notified status record stays notified across the key's change; the
// exclusions; pair validation; install, start, probe
// and status; the probe names a token's account; authorize stores the
// token Google's consent returns through secret-tool's stdin as the
// account's one item, named for the account Drive's about read returns,
// with the access token on curl's stdin; sign-out clears one direction;
// attention-seen keeps a notified key across renders until the key
// changes or a settled record needs nothing; two failing pairs keep one
// key through a run; the rename from the plugin's previous name holds
// while a sync of the old units runs, with an hourly timer enabled
// throughout, moves the directories, the units and the keyring items with
// the token's account in one invocation, keeps the setup log a TUI holds
// open in place, holds the keyring step alone while the keyring is locked
// with the held items read as locked, keeps a concurrent invocation
// waiting until it ends, and changes nothing a second time;
// and no credential value reaches an argv, a log line, a unit or
// the status record.
//
// Every case runs in its own scratch home and runtime directory with a PATH
// of stand-ins: `secret-tool` keeps items as files under the case's stub
// directory, `systemctl` records its calls, `curl` records its argv and
// stdin and answers Drive's about read, and `rclone` records its argv and
// RCLONE_* environment, swaps the drive remote for the local backend
// rooted at the case's fixture Drive and runs the host's rclone, except
// for `authorize`, which it answers itself with a fixture token, so no
// browser opens and no consent leaves the machine.
// No case reaches the user's keyring, systemd manager, rclone config or
// network.
//
// The controls at the end edit a copy of the runner, one rule at a time,
// and require the case that rule serves to fail on the copy.
"use strict";
const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const RUNNER = path.join(__dirname, "..", "shell", "plugins", "vgs.google-drive", "bin", "google-drive");
// The runner's rclone remote, as every Drive path in its argv names it.
const REMOTE_PREFIX = "vgsdrive:";

function which(command) {
    for (const dir of String(process.env.PATH || "").split(path.delimiter)) {
        const candidate = path.join(dir, command);
        try {
            fs.accessSync(candidate, fs.constants.X_OK);
            if (fs.statSync(candidate).isFile()) return fs.realpathSync(candidate);
        } catch (_e) {
            // Keep looking.
        }
    }
    return null;
}

const HOST = {};
for (const tool of ["rclone", "flock", "bash", "mkfifo"]) {
    HOST[tool] = which(tool);
    if (HOST[tool] === null) {
        console.log("test-google-drive-runner: unavailable: " + tool + "=missing");
        process.exit(77);
    }
}

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "test-google-drive-runner-"));
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));

const SECRETS = {
    "client-id": "fake-client-7f3a",
    "client-secret": "fake-secret-91c2",
    "token": "{\"access_token\":\"fake-access-55aa\",\"token_type\":\"Bearer\",\"refresh_token\":\"fake-refresh-d81e\",\"expiry\":\"2026-01-01T00:00:00Z\"}"
};
// The token the rclone stand-in's `authorize` prints, as rclone v1.75.1
// prints one: its JSON on one line between the paste lines. Its refresh
// token holds a quote, a space and a percent sign, which reach the store
// byte for byte and no argv.
const CONSENT_REFRESH = "fake-consent-refresh-f00d \\\"50% off\\\"";
const CONSENT_TOKEN = "{\"access_token\":\"fake-consent-access-c0de\",\"token_type\":\"Bearer\",\"refresh_token\":\"" + CONSENT_REFRESH + "\",\"expiry\":\"2026-10-10T13:00:00Z\"}";
const CONSENT_VALUES = ["fake-consent-access-c0de", CONSENT_REFRESH];
// The address the curl stand-in's about read answers with.
const ACCOUNT = "someone@example.com";
const ABOUT_URL = "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress)";
// Text every log, record and unit of every case is checked against.
const SEEN = [];

// rclone v1.75.1's own lines: the first from a drive remote with a fake
// token under `unshare -rn` (no network), the second from an empty token.
const OFFLINE_LINE = "2026/10/10 11:53:47 CRITICAL: Failed to create file system for \"vgsdrive:Docs\": couldn't find root directory ID: Get \"https://www.googleapis.com/drive/v3/files/root?alt=json&fields=id&prettyPrint=false&supportsAllDrives=true\": couldn't fetch token: Post \"https://oauth2.googleapis.com/token\": dial tcp [2607:f8b0:400e:c0d::5f]:443: connect: cannot assign requested address";
// The reason rclone v1.75.1 gave for a Drive shortcut whose target is gone.
const DANGLING_REASON = "failed to open source object: can't read dangling shortcut";
// OFFLINE_LINE's cause as the reason of one file's error: the file form is
// rclone's, the pairing with this cause is composed here.
const OFFLINE_REASON = OFFLINE_LINE.slice(OFFLINE_LINE.indexOf("couldn't fetch token"));
const AUTH_LINE = "2026/10/10 11:53:57 CRITICAL: Failed to create file system for \"vgsdrive:Docs\": drive: failed when making oauth client: failed to create oauth client: empty token found - please run \"rclone config reconnect vgsdrive{XLZpn}:\"";

// ------------------------------------------------------------ the world

function write(file, text, mode) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text, { mode: mode || 0o644 });
}

function read(file) {
    return fs.readFileSync(file, "utf8");
}

let worlds = 0;
// A fresh home, runtime directory, stand-ins and fixture Drive.
function world(options) {
    const opts = Object.assign({ secrets: Object.keys(SECRETS), ids: false, user: null }, options || {});
    const root = path.join(scratch, "w" + (worlds += 1));
    const w = {
        root,
        home: path.join(root, "home"),
        run: path.join(root, "run"),
        stub: path.join(root, "stub"),
        bin: path.join(root, "bin"),
        drive: path.join(root, "drive"),
        second: path.join(root, "second-folder")
    };
    for (const dir of [w.home, w.stub, w.bin, w.drive, w.second, path.join(w.stub, "secrets"), path.join(w.stub, "old-secrets")]) fs.mkdirSync(dir, { recursive: true });
    fs.mkdirSync(w.run, { recursive: true, mode: 0o700 });
    w.state = path.join(w.home, ".local", "state", "vgshell", "google-drive");
    w.mirror = path.join(w.home, "mirror", "docs");
    w.env = {
        PATH: w.bin,
        HOME: w.home,
        XDG_CONFIG_HOME: path.join(w.home, ".config"),
        XDG_STATE_HOME: path.join(w.home, ".local", "state"),
        XDG_DATA_HOME: path.join(w.home, ".local", "share"),
        XDG_RUNTIME_DIR: w.run,
        // The runner must not hand these to rclone.
        RCLONE_CONFIG: path.join(root, "leaked-config"),
        RCLONE_CONFIG_VGSDRIVE_TYPE: "s3"
    };
    fs.symlinkSync(HOST.flock, path.join(w.bin, "flock"));
    fs.symlinkSync(process.execPath, path.join(w.bin, "node"));
    // USER names the token item's account, as authorize stores it.
    for (const account of opts.secrets) write(path.join(w.stub, "secrets", account === "token" && opts.user !== null ? "token.user." + opts.user : account), SECRETS[account]);
    if (opts.ids) write(path.join(w.stub, "ids"), "");
    // Each item is a file of the store: <account> holds one without a
    // `user` attribute, <account>.user.<address> one with it, and
    // <account>.locked marks the account's items locked. secrets/ holds the
    // plugin's service, old-secrets/ the service of its name before the
    // rename, and any other service is refused. It prints as libsecret's
    // secret-tool does: the label and an unlocked item's secret on stdout,
    // the attributes and a lock failure on stderr. A store of the account
    // \`block-store\` names leaves \`store-blocked\` and waits for a line on
    // the \`release\` fifo before it writes.
    write(path.join(w.bin, "secret-tool"), `#!${process.execPath}
const fs = require("fs");
const path = require("path");
const stub = ${JSON.stringify(w.stub)};
const stores = { "vgs-google-drive": ${JSON.stringify(path.join(w.stub, "secrets"))}, "vgs-cloud-sync": ${JSON.stringify(path.join(w.stub, "old-secrets"))} };
const calls = ${JSON.stringify(path.join(w.stub, "secret-tool.calls"))};
const args = process.argv.slice(2);
const items = account => fs.readdirSync(store).filter(n => n === account || n.startsWith(account + ".user.")).sort();
const keyed = (rest, more) => rest.length === 4 + more && rest[0] === "service" && Object.hasOwn(stores, rest[1]) && rest[2] === "account";
const at = args.indexOf("service");
const service = at === -1 ? "" : args[at + 1];
const store = stores[service];
if (args[0] === "store") {
    const rest = args.slice(2);
    if (!String(args[1]).startsWith("--label=") || !(keyed(rest, 0) || keyed(rest, 2) && rest[4] === "user")) process.exit(2);
    fs.appendFileSync(calls, args.join(" ") + "\\n");
    if (fs.existsSync(stub + "/block-store") && fs.readFileSync(stub + "/block-store", "utf8") === rest[3]) {
        fs.unlinkSync(stub + "/block-store");
        fs.writeFileSync(stub + "/store-blocked", "");
        fs.readFileSync(stub + "/release");
    }
    fs.writeFileSync(path.join(store, rest.length === 6 ? rest[3] + ".user." + rest[5] : rest[3]), fs.readFileSync(0));
    process.exit(0);
}
if (args[0] === "clear") {
    const rest = args.slice(1);
    if (!keyed(rest, 0)) process.exit(2);
    fs.appendFileSync(calls, args.join(" ") + "\\n");
    // libsecret clears unlocked items alone, and exits 1 with no output
    // when it cleared none.
    const cleared = fs.existsSync(path.join(store, rest[3] + ".locked")) ? [] : items(rest[3]);
    for (const name of cleared) fs.unlinkSync(path.join(store, name));
    process.exit(cleared.length === 0 ? 1 : 0);
}
const all = args[1] === "--all";
const rest = args.slice(all ? 2 : 1);
if (args[0] !== "search" || !keyed(rest, 0)) process.exit(2);
const account = rest[3];
const locked = fs.existsSync(path.join(store, account + ".locked"));
let found = items(account);
if (locked && found.length === 0) found = [account];
for (const name of all ? found : found.slice(0, 1)) {
    process.stdout.write("[/org/freedesktop/secrets/collection/login/1]\\nlabel = VGS " + account + "\\n" + (locked ? "" : "secret = " + fs.readFileSync(path.join(store, name), "utf8") + "\\n"));
    process.stderr.write("attribute.service = " + service + "\\nattribute.account = " + account + "\\n" + (name === account ? "" : "attribute.user = " + name.slice(account.length + ".user.".length) + "\\n")
        + (locked ? "secret-tool: Cannot get secret of a locked object\\n" : ""));
}
`, 0o755);
    // Drive's about read: records its argv and stdin, then answers from
    // curl-mode: `fail` as curl does for a refused token, `bad` with an
    // address the judge refuses, else with ACCOUNT.
    write(path.join(w.bin, "curl"), `#!${process.execPath}
const fs = require("fs");
const stub = ${JSON.stringify(w.stub)};
fs.appendFileSync(stub + "/curl.calls", JSON.stringify({ argv: process.argv.slice(2), stdin: fs.readFileSync(0, "utf8") }) + "\\n");
const mode = fs.existsSync(stub + "/curl-mode") ? fs.readFileSync(stub + "/curl-mode", "utf8") : "";
if (mode === "fail") {
    process.stderr.write("curl: (22) The requested URL returned error: 401\\n");
    process.exit(22);
}
process.stdout.write(JSON.stringify({ user: { emailAddress: mode === "bad" ? "two@at@example.com" : ${JSON.stringify(ACCOUNT)} } }));
`, 0o755);
    // \`enable --now\` and \`disable --now\` keep the enabled units in
    // \`enabled\`, one a line. \`is-active\` prints activating while the
    // \`old-run\` file exists, as a oneshot sync reads while it runs, then
    // inactive with systemctl's exit 3; asked after the old state directory
    // has gone, it leaves \`moved-early\`. The first disable of the previous
    // timer while \`fire-on-disable\` exists starts the previous sync first,
    // as the timer elapsing just before the disable would. \`reset-failed\`
    // exits 1, as systemctl does for a unit its manager no longer holds.
    write(path.join(w.stub, "stop-post.js"), `const fs = require("fs");
const cp = require("child_process");
const stub = ${JSON.stringify(w.stub)};
const service = process.argv[2];
if (!fs.existsSync(stub + "/stop-post-commands")) process.exit(0);
const command = JSON.parse(fs.readFileSync(stub + "/stop-post-commands", "utf8"))[service];
if (!command || fs.existsSync(stub + "/suppressed-" + service)) process.exit(0);
fs.appendFileSync(stub + "/stop-post-executed", service + "\\n");
const out = cp.spawnSync(command[0], command.slice(1), { env: process.env, stdio: "ignore", timeout: 3000, killSignal: "SIGKILL" });
process.exit(out.status === null ? 1 : out.status);
`);
    write(path.join(w.bin, "systemctl"), `#!${HOST.bash}
stub=${JSON.stringify(w.stub)}
printf '%s\\n' "$*" >>"$stub/systemctl.calls"
[[ ! -f $stub/systemctl-fail ]] || exit 1
reload_overrides() {
  for service in vgs-cloud-sync.service vgs-google-drive.service; do
    override=${JSON.stringify(w.run)}/systemd/user/$service.d/90-vgs-google-drive-migrate.conf
    if [[ -f $override && $(<"$override") == $'[Service]\\nExecStopPost=' ]]; then : >"$stub/suppressed-$service"
    else /usr/bin/rm -f "$stub/suppressed-$service"; fi
  done
}
case $2 in
  daemon-reload) reload_overrides ;;
  enable)
    units=()
    [[ -f $stub/enabled ]] && mapfile -t units <"$stub/enabled"
    for unit in "\${units[@]}"; do [[ $unit == "$4" ]] && exit 0; done
    printf '%s\\n' "$4" >>"$stub/enabled" ;;
  disable)
    reload_overrides
    if [[ $4 == vgs-cloud-sync.timer && -f $stub/fire-on-disable && ! -e $stub/fired ]]; then : >"$stub/fired"; : >"$stub/old-run"; fi
    units=()
    [[ -f $stub/enabled ]] && mapfile -t units <"$stub/enabled"
    : >"$stub/enabled"
    for unit in "\${units[@]}"; do [[ $unit == "$4" ]] || printf '%s\\n' "$unit" >>"$stub/enabled"; done
    if [[ $4 == vgs-cloud-sync.service ]]; then
      [[ ! -f $stub/stop-fail ]] || exit 1
      [[ ! -f $stub/stop-unconfirmed ]] || exit 0
      was_active=false
      if [[ -f $stub/old-run ]]; then : >"$stub/old-run-stopped"; was_active=true; fi
      /usr/bin/rm -f "$stub/old-run"
      if [[ $was_active == true ]]; then ${JSON.stringify(process.execPath)} "$stub/stop-post.js" "$4" || exit 1; fi
    fi
    if [[ $4 == vgs-google-drive.service ]]; then
      was_active=false
      [[ ! -f $stub/new-run ]] || was_active=true
      /usr/bin/rm -f "$stub/new-run"
      if [[ $was_active == true ]]; then ${JSON.stringify(process.execPath)} "$stub/stop-post.js" "$4" || exit 1; fi
    fi ;;
  is-active)
    if [[ $3 == vgs-cloud-sync.service ]]; then
      [[ -d ${JSON.stringify(path.join(w.home, ".local", "state", "vgshell", "cloud-sync"))} ]] || : >"$stub/moved-early"
      if [[ -f $stub/old-run ]]; then echo activating; exit 3; fi
    elif [[ $3 == vgs-google-drive.service && -f $stub/new-run ]]; then echo activating; exit 3; fi
    echo inactive
    exit 3 ;;
  reset-failed)
    exit 1 ;;
esac
`, 0o755);
    // Each rclone call also records the status record's attention as the
    // run's own render left it.
    write(path.join(w.stub, "record.js"), `const fs = require("fs");
const env = {};
for (const name of Object.keys(process.env)) if (name.startsWith("RCLONE_")) env[name] = process.env[name];
const status = ${JSON.stringify(path.join(w.state, "status.json"))};
const attention = fs.existsSync(status) ? JSON.parse(fs.readFileSync(status, "utf8")).attention : null;
fs.appendFileSync(${JSON.stringify(path.join(w.stub, "rclone.calls"))}, JSON.stringify({ argv: process.argv.slice(2), env, attention }) + "\\n");
`);
    // The listing filter: object ids from inode numbers when \`ids\` exists,
    // and Size -1, as rclone's drive backend lists a Google-native
    // document, for each path the \`exports\` file names.
    write(path.join(w.stub, "listing.js"), `const fs = require("fs");
const path = require("path");
const stub = process.argv[2];
const drive = process.argv[3];
const root = process.argv.slice(4).find(a => a.startsWith("vgsdrive:")).slice("vgsdrive:".length);
const items = JSON.parse(fs.readFileSync(0, "utf8"));
const exportsFile = path.join(stub, "exports");
const exported = fs.existsSync(exportsFile) ? fs.readFileSync(exportsFile, "utf8").split("\\n").filter(Boolean) : [];
for (const item of items) {
    if (fs.existsSync(path.join(stub, "ids"))) item.ID = String(fs.statSync(path.join(drive, root, item.Path)).ino);
    if (exported.includes(item.Path)) item.Size = -1;
}
process.stdout.write(JSON.stringify(items));
`);
    // A listing of one Drive folder with each copy's metadata, as the
    // runner asks for a folder that holds a doubled name: the items
    // \`folder-listings\` maps the folder's remote path to, which the local
    // backend cannot hold, since a folder there holds a name once; with
    // \`folder-listing-offline\`, rclone's offline failure instead.
    write(path.join(w.stub, "folder-listing.js"), `const fs = require("fs");
const stub = process.argv[2];
const at = process.argv.slice(3).find(a => a.startsWith("vgsdrive:"));
const listings = JSON.parse(fs.readFileSync(stub + "/folder-listings", "utf8"));
if (fs.existsSync(stub + "/folder-listing-offline")) {
    process.stderr.write(${JSON.stringify(JSON.stringify(OFFLINE_LINE))} + "\\n");
    process.exit(1);
}
if (!Object.hasOwn(listings, at)) {
    process.stderr.write("stand-in: no folder listing for " + at + "\\n");
    process.exit(3);
}
process.stdout.write(JSON.stringify(listings[at]));
`);
    // The rclone stand-in: `mode` prints a real failure line instead of
    // running; `block` holds the first copy until `release` is written.
    write(path.join(w.bin, "rclone"), `#!${HOST.bash}
stub=${JSON.stringify(w.stub)}
${JSON.stringify(process.execPath)} "$stub/record.js" "$@"
mode=""
[[ -f $stub/mode ]] && mode=$(<"$stub/mode")
if [[ $3 == authorize ]]; then
  printf 'Waiting for code...\\n' >&2
  [[ $mode == no-refresh ]] && token='{"access_token":"x","token_type":"Bearer"}' || token=${JSON.stringify(CONSENT_TOKEN)}
  printf 'Paste the following into your remote machine --->\\n%s\\n<---End paste\\n' "$token"
  exit 0
fi
case "$mode" in
  offline) printf '%s\\n' ${JSON.stringify(OFFLINE_LINE)} >&2; exit 1 ;;
  auth) printf '%s\\n' ${JSON.stringify(AUTH_LINE)} >&2; exit 1 ;;
esac
if [[ \${RCLONE_CONFIG_VGSDRIVE_SCOPE:-} != drive && $3 == copy ]]; then
  remote=""
  local_source=""
  for word in "$@"; do
    [[ $word == vgsdrive:Shared ]] && remote=Shared
    [[ -d $word && $word == "$HOME"/* ]] && local_source="$word"
  done
  if [[ -n $remote && -n $local_source ]]; then
    mkdir -p ${JSON.stringify(w.second)}/"$remote"
    cp -a -- "$local_source/." ${JSON.stringify(w.second)}/"$remote"/
    exit 0
  fi
fi
export RCLONE_CONFIG_VGSDRIVE_TYPE=local
unset RCLONE_CONFIG_VGSDRIVE_CLIENT_ID RCLONE_CONFIG_VGSDRIVE_CLIENT_SECRET RCLONE_CONFIG_VGSDRIVE_TOKEN RCLONE_CONFIG_VGSDRIVE_SCOPE
cd ${JSON.stringify(w.drive)} || exit 9
if [[ -f $stub/block && ! -e $stub/blocked && $3 == copy ]]; then
  : >"$stub/blocked"
  read -r _ <"$stub/release"
fi
# The legs by their words: the download copies from vgsdrive: into a
# folder, the upload from a folder to vgsdrive:.
leg=""
if [[ $3 == copy && $4 == --update && $5 == vgsdrive:* ]]; then leg=download; folder=$6; fi
if [[ $3 == copy && $4 == --update && $6 == vgsdrive:* ]]; then leg=upload; folder=$5; fi
if [[ $leg == upload && -f $stub/fail-upload && ! -e $stub/failed-upload ]]; then
  : >"$stub/failed-upload"
  printf 'Failed to copy: stand-in upload error\n' >&2
  exit 1
fi
# Drive files rclone cannot open and a name Drive holds twice, in the
# lines rclone v1.75.1 printed for them: the copy leaves out each file
# \`unreadable\` names, one a line, repeats their errors over three
# attempts and exits 1, as rclone did; for each name \`duplicate\` holds,
# one a line, it prints the notice; with \`duplicate\` alone it exits 0
# after the notice. The file \`recovered\` names fails in the first attempt
# alone; \`uncounted\` adds an error no line names a file for to every
# attempt's count; \`fatal\` ends the copy after one attempt with exit 7.
if [[ $leg == download && ( -f $stub/unreadable || -f $stub/duplicate ) ]]; then
  gone=()
  [[ -f $stub/unreadable ]] && mapfile -t gone <"$stub/unreadable"
  excludes=()
  for rel in "\${gone[@]}"; do excludes+=(--exclude "/$rel"); done
  ${JSON.stringify(HOST.rclone)} "$@" "\${excludes[@]}" || exit 9
  twice() {
    [[ -f $stub/duplicate ]] || return 0
    while IFS= read -r rel || [[ -n $rel ]]; do printf '2026/10/13 00:03:27 NOTICE: %s: Duplicate object found in source - ignoring\\n' "$rel" >&2; done <"$stub/duplicate"
  }
  if [[ \${#gone[@]} == 0 ]]; then twice; exit 0; fi
  reason=$(<"$stub/unreadable-reason")
  attempts=3
  [[ -f $stub/fatal ]] && attempts=1
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    errors=\${#gone[@]}
    [[ -f $stub/uncounted ]] && errors=$((errors + 1))
    if [[ $attempt == 1 && -f $stub/recovered ]]; then
      errors=$((errors + 1))
      printf '2026/10/13 00:04:58 ERROR : %s: Failed to copy: %s\\n' "$(<"$stub/recovered")" "$reason" >&2
    fi
    twice
    for rel in "\${gone[@]}"; do
      printf '2026/10/13 00:04:59 NOTICE: Dangling shortcut "%s" detected\\n' "\${rel##*/}" >&2
      printf '2026/10/13 00:04:59 ERROR : %s: Failed to copy: %s\\n' "$rel" "$reason" >&2
    done
    printf '2026/10/13 00:04:59 ERROR : Attempt %s/%s failed with %s errors and: %s\\n' "$attempt" "$attempts" "$errors" "$reason" >&2
  done
  [[ -f $stub/fatal ]] && exit 7
  # rclone's closing notice carries the count only above one error.
  if [[ $errors == 1 ]]; then
    printf '2026/10/13 00:04:59 NOTICE: Failed to copy: %s\\n' "$reason" >&2
  else
    printf '2026/10/13 00:04:59 NOTICE: Failed to copy with %s errors: last error was: %s\\n' "$errors" "$reason" >&2
  fi
  exit 1
fi
if [[ $3 == lsjson && " $* " == *" --metadata "* && -f $stub/folder-listings ]]; then
  exec ${JSON.stringify(process.execPath)} "$stub/folder-listing.js" "$stub" "$@"
fi
if [[ $3 == lsjson && ( -f $stub/ids || -f $stub/exports ) ]]; then
  set -o pipefail
  ${JSON.stringify(HOST.rclone)} "$@" | ${JSON.stringify(process.execPath)} "$stub/listing.js" "$stub" ${JSON.stringify(w.drive)} "$@"
  exit
fi
${JSON.stringify(HOST.rclone)} "$@"
status=$?
# A user's save landing as a leg ends: once, the file the trigger names,
# after the download leg (edit-after-copy) or the upload leg
# (edit-after-upload).
for trigger in edit-after-copy:download edit-after-upload:upload; do
  if [[ -f $stub/\${trigger%%:*} && ! -e $stub/edited && $leg == "\${trigger#*:}" ]]; then
    printf 'edited during the copy\n' >"$folder/$(<"$stub/\${trigger%%:*}")"
    : >"$stub/edited"
  fi
done
: >"$stub/exited"
exit $status
`, 0o755);
    return w;
}

function cli(w, args, runner) {
    const out = childProcess.spawnSync(process.execPath, [runner || RUNNER].concat(args), { env: w.env, encoding: "utf8", timeout: 120000 });
    assert.notEqual(out.status, null, "runner " + args.join(" ") + " did not end: " + out.error);
    SEEN.push(out.stdout, out.stderr);
    return out;
}

function addPair(w, runner, pair) {
    const def = Object.assign({ id: "docs", label: "Documents", remote: "Docs", local: w.mirror }, pair || {});
    const out = cli(w, ["pair-add", "--definition", JSON.stringify(def)], runner);
    assert.equal(out.status, 0, out.stderr);
    return def;
}

function status(w, runner) {
    const out = cli(w, ["status"], runner);
    assert.equal(out.status, 0, out.stderr);
    const parsed = JSON.parse(out.stdout);
    assert.deepEqual(parsed, JSON.parse(read(path.join(w.state, "status.json"))), "status prints what it writes");
    return parsed;
}

function jsonLines(file) {
    return fs.existsSync(file) ? read(file).trim().split("\n").map(line => JSON.parse(line)) : [];
}

function rcloneCalls(w) {
    return jsonLines(path.join(w.stub, "rclone.calls"));
}

// The stand-in keyring's items of DIRECTION's token, as their file names.
function tokenItems(w) {
    return fs.readdirSync(path.join(w.stub, "secrets")).filter(n => n === "token" || n.startsWith("token.user.")).sort();
}

function drive(w, rel, text, mtimeSeconds) {
    const file = path.join(w.drive, "Docs", rel);
    write(file, text);
    if (mtimeSeconds !== undefined) fs.utimesSync(file, mtimeSeconds, mtimeSeconds);
}

function mirrorFiles(w) {
    const found = [];
    const walk = rel => {
        for (const entry of fs.readdirSync(path.join(w.mirror, rel), { withFileTypes: true })) {
            const child = rel === "" ? entry.name : rel + "/" + entry.name;
            if (entry.isDirectory()) walk(child);
            else found.push(child);
        }
    };
    if (fs.existsSync(w.mirror)) walk("");
    return found.sort();
}

function runOk(w, runner, result) {
    const out = cli(w, ["run"], runner);
    assert.equal(out.stdout, "pair=docs result=" + (result || "idle") + "\n", out.stderr);
    return out;
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// Waits for FILE, the stand-in's acknowledgement that it reached its block.
async function waitFor(file, what) {
    const deadline = Date.now() + 30000;
    while (!fs.existsSync(file)) {
        if (Date.now() > deadline) throw new Error("timed out waiting for " + what);
        await sleep(20);
    }
}

// Lets a blocked stand-in go on; false when no reader is waiting.
function release(w) {
    let fd;
    try {
        fd = fs.openSync(path.join(w.stub, "release"), fs.constants.O_WRONLY | fs.constants.O_NONBLOCK);
    } catch (e) {
        if (e.code === "ENXIO") return false;
        throw e;
    }
    fs.writeSync(fd, "go\n");
    fs.closeSync(fd);
    return true;
}

// The runner on ARGS in W, started and not waited for.
function spawnRunner(w, args, runner) {
    const child = childProcess.spawn(process.execPath, [runner || RUNNER].concat(args), { env: w.env, stdio: ["ignore", "pipe", "pipe"] });
    const exited = new Promise(resolve => child.on("exit", resolve));
    const done = new Promise(resolve => {
        let stdout = "";
        let stderr = "";
        child.stdout.on("data", d => { stdout += d; });
        child.stderr.on("data", d => { stderr += d; });
        child.on("close", (code, signal) => {
            SEEN.push(stdout, stderr);
            resolve({ code, signal, stdout, stderr });
        });
    });
    return { child, exited, done };
}

function startBlocked(w, runner) {
    write(path.join(w.stub, "block"), "");
    const made = childProcess.spawnSync(HOST.mkfifo, [path.join(w.stub, "release")]);
    assert.equal(made.status, 0, String(made.stderr));
    return spawnRunner(w, ["run"], runner);
}

// ------------------------------------------------------------- the cases

// A Drive-side add and change reach the mirror after one run, through the
// drive remote rclone receives in its environment alone.
function caseCopy(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    assert.deepEqual(mirrorFiles(w), ["a.txt"]);
    drive(w, "a.txt", "one, changed on Drive\n", 1700003600);
    drive(w, "b.txt", "added on Drive\n", 1700003600);
    runOk(w, runner);
    assert.equal(read(path.join(w.mirror, "a.txt")), "one, changed on Drive\n");
    assert.equal(read(path.join(w.mirror, "b.txt")), "added on Drive\n");
    // The unedited earlier download of a.txt is not kept as a conflict.
    assert.deepEqual(fs.readdirSync(path.join(w.state, "pairs", "docs", "conflicts")), []);
    const s = status(w, runner);
    assert.equal(s.pairs[0].state, "idle");
    assert.deepEqual(s.pairs[0].changes, { added: 1, updated: 1 });
    assert.deepEqual(s.conflicts, []);
    assert.equal(Date.parse(s.pairs[0].staleAfter) - Date.parse(s.pairs[0].lastSuccess), 2 * 3600 * 1000);
    const calls = rcloneCalls(w);
    assert.ok(calls.length >= 2);
    for (const call of calls) {
        assert.deepEqual(call.argv.slice(0, 2), ["--config", "/dev/null"]);
        assert.deepEqual(call.env, {
            RCLONE_CONFIG_VGSDRIVE_TYPE: "drive",
            RCLONE_CONFIG_VGSDRIVE_CLIENT_ID: SECRETS["client-id"],
            RCLONE_CONFIG_VGSDRIVE_CLIENT_SECRET: SECRETS["client-secret"],
            RCLONE_CONFIG_VGSDRIVE_TOKEN: SECRETS["token"],
            RCLONE_CONFIG_VGSDRIVE_SCOPE: "drive"
        });
        const at = call.argv.indexOf("--drive-export-formats");
        if (at !== -1) assert.equal(call.argv[at + 1], "docx,xlsx,pptx,svg");
    }
    assert.ok(calls.some(c => c.argv[2] === "copy" && c.argv.includes("vgsdrive:Docs") && c.argv.includes(w.mirror)));
    return w;
}

// A local edit since the last download: Drive's version in the mirror, the
// edit kept in conflict storage outside it, reported as `both-changed`.
function caseBothChangedKept(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "a.txt", "Drive version\n", 1700000000);
    runOk(w, runner);
    write(path.join(w.mirror, "a.txt"), "edited here, longer than before\n");
    fs.utimesSync(path.join(w.mirror, "a.txt"), 1700000500, 1700000500);
    drive(w, "a.txt", "Drive version changed\n", 1700001000);
    runOk(w, runner);
    assert.equal(read(path.join(w.mirror, "a.txt")), "Drive version changed\n");
    const s = status(w, runner);
    assert.equal(s.conflicts.length, 1);
    const c = s.conflicts[0];
    assert.equal(c.kind, "both-changed");
    assert.equal(c.pair, "docs");
    assert.equal(c.path, "a.txt");
    assert.equal(c.localPath, path.join(w.mirror, "a.txt"));
    assert.ok(c.storedPath.startsWith(path.join(w.state, "pairs", "docs", "conflicts") + "/"));
    assert.equal(read(c.storedPath), "edited here, longer than before\n");
    assert.deepEqual(s.attention.reasons, ["conflicts"]);
    // The record holds on the next run, and leaves once the kept copy is
    // removed.
    runOk(w, runner);
    assert.equal(status(w, runner).conflicts.length, 1);
    fs.unlinkSync(c.storedPath);
    runOk(w, runner);
    assert.ok(!status(w, runner).conflicts.some(c => c.path === "old-record.txt"));
}

// A local edit saved as a run's copy ends matches nothing Drive listed, so
// it does not become the baseline: the next run, which replaces it with
// Drive's version, keeps it as `both-changed`.
// A user's save landing as a leg ends is newer than Drive's copy, so it
// reaches Drive, in the same run after the download leg or in the next run
// after the upload leg, and reads as no conflict either way: the baseline
// is the state Drive listed last.
function caseEditDuringCopy(runner) {
    for (const trigger of ["edit-after-copy", "edit-after-upload"]) {
        const w = world();
        addPair(w, runner);
        drive(w, "a.txt", "drive v1\n", 1700000000);
        runOk(w, runner);
        // An edit this run uploads, then the save as a leg ends.
        write(path.join(w.mirror, "a.txt"), "edit one\n");
        fs.utimesSync(path.join(w.mirror, "a.txt"), 1700003600, 1700003600);
        write(path.join(w.stub, trigger), "a.txt");
        runOk(w, runner);
        assert.equal(fs.existsSync(path.join(w.stub, "edited")), true, trigger + " fired");
        assert.equal(read(path.join(w.mirror, "a.txt")), "edited during the copy\n", trigger);
        runOk(w, runner);
        assert.equal(read(path.join(w.drive, "Docs", "a.txt")), "edited during the copy\n", trigger);
        assert.equal(read(path.join(w.mirror, "a.txt")), "edited during the copy\n", trigger);
        assert.deepEqual(status(w, runner).conflicts, [], trigger);
    }
}

// A Drive deletion keeps the local file and reads `removed-on-drive`; a
// rename reads `renamed` where the backend has object ids, and as a
// removal where it tracks by path.
function caseRemovedAndRenamed(runner) {
    for (const ids of [true, false]) {
        const w = world({ ids: ids });
        addPair(w, runner);
        drive(w, "a.txt", "stays\n", 1700000000);
        drive(w, "b.txt", "deleted on Drive\n", 1700000000);
        drive(w, "c.txt", "renamed on Drive\n", 1700000000);
        runOk(w, runner);
        fs.unlinkSync(path.join(w.drive, "Docs", "b.txt"));
        fs.renameSync(path.join(w.drive, "Docs", "c.txt"), path.join(w.drive, "Docs", "c2.txt"));
        runOk(w, runner);
        assert.deepEqual(mirrorFiles(w), ["a.txt", "b.txt", "c.txt", "c2.txt"]);
        assert.equal(read(path.join(w.mirror, "b.txt")), "deleted on Drive\n");
        const kinds = status(w, runner).conflicts.map(c => [c.kind, c.path, c.to === undefined ? null : c.to]);
        assert.deepEqual(kinds, ids
            ? [["removed-on-drive", "b.txt", null], ["renamed", "c.txt", "c2.txt"]]
            : [["removed-on-drive", "b.txt", null], ["removed-on-drive", "c.txt", null]]);
    }
}

// A run while another holds the pair's lock is `busy` (exit 75) and starts
// no rclone; the first run finishes.
async function caseBusy(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    const first = startBlocked(w, runner);
    try {
        await waitFor(path.join(w.stub, "blocked"), "the first copy");
        const before = rcloneCalls(w).length;
        assert.equal(status(w, runner).state, "running");
        const second = cli(w, ["run"], runner);
        assert.equal(second.status, 75, second.stderr);
        assert.equal(second.stdout, "pair=docs result=busy\n");
        assert.equal(rcloneCalls(w).length, before, "a busy run starts no rclone");
    } finally {
        if (release(w)) await first.done;
    }
    const ended = await first.done;
    assert.equal(ended.code, 0, ended.stderr);
    assert.deepEqual(mirrorFiles(w), ["a.txt"]);
}

// A runner killed mid-copy leaves its rclone holding the pair's lock: the
// pair reads `running` and a second run is busy while that copy goes on.
// Once it ends, the pair reads as interrupted, not done.
async function caseInterrupted(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    const first = startBlocked(w, runner);
    let released = false;
    try {
        await waitFor(path.join(w.stub, "blocked"), "the copy");
        first.child.kill("SIGKILL");
        await first.exited;
        assert.equal(status(w, runner).pairs[0].state, "running", "the orphaned copy holds the lock");
        const before = rcloneCalls(w).length;
        const second = cli(w, ["run"], runner);
        assert.equal(second.status, 75, second.stderr);
        assert.equal(second.stdout, "pair=docs result=busy\n");
        assert.equal(rcloneCalls(w).length, before, "no second copy starts beside the orphaned one");
        released = release(w);
        assert.ok(released, "the orphaned copy waits for its release");
        await waitFor(path.join(w.stub, "exited"), "the orphaned copy");
        // The stand-in writes its mark just before it exits and drops the
        // lock; the lock is read again until it is free.
        const deadline = Date.now() + 30000;
        let s = status(w, runner);
        while (s.pairs[0].state === "running" && Date.now() < deadline) {
            await sleep(20);
            s = status(w, runner);
        }
        assert.equal(s.pairs[0].state, "error");
        assert.equal(s.pairs[0].lastError.kind, "interrupted");
        assert.equal(s.pairs[0].lastSuccess, null);
    } finally {
        if (!released && release(w)) await waitFor(path.join(w.stub, "exited"), "the orphaned copy");
    }
}

// Pause is the runner's own record: a later process reads it, a paused run
// copies nothing, and resume lets the next run copy.
function casePause(runner) {
    const w = world();
    addPair(w, runner);
    let out = cli(w, ["pause"], runner);
    assert.equal(out.stdout, "paused=all\n", out.stderr);
    const s = JSON.parse(read(path.join(w.state, "status.json")));
    assert.equal(s.paused, true);
    assert.equal(s.pairs[0].state, "paused");
    drive(w, "a.txt", "one\n", 1700000000);
    out = runOk(w, runner, "paused");
    assert.equal(out.status, 0);
    assert.deepEqual(rcloneCalls(w), []);
    assert.deepEqual(mirrorFiles(w), []);
    assert.equal(cli(w, ["resume"], runner).stdout, "resumed=all\n");
    runOk(w, runner);
    assert.deepEqual(mirrorFiles(w), ["a.txt"]);
    // One pair alone.
    assert.equal(cli(w, ["pause", "--pair", "docs"], runner).stdout, "paused=docs\n");
    runOk(w, runner, "paused");
    assert.equal(status(w, runner).paused, false);
    assert.equal(cli(w, ["pause", "--pair", "nope"], runner).status, 1);
}

// Offline and refused authorization keep the last success and the mirror;
// a missing or locked credential runs no rclone.
function caseFailures(runner) {
    const rows = [
        { name: "offline", setup: w => write(path.join(w.stub, "mode"), "offline"), state: "offline", kind: "offline", rclone: true },
        { name: "rclone refuses the token", setup: w => write(path.join(w.stub, "mode"), "auth"), state: "authorization-required", kind: "authorization-refused", rclone: true },
        { name: "no credential", setup: w => fs.unlinkSync(path.join(w.stub, "secrets", "token")), state: "authorization-required", kind: "credential-absent", account: "token", rclone: false },
        { name: "locked store", setup: w => write(path.join(w.stub, "secrets", "client-id.locked"), ""), state: "authorization-required", kind: "credential-locked", account: "client-id", rclone: false }
    ];
    for (const row of rows) {
        const w = world();
        assert.equal(cli(w, ["install"], runner).status, 0);
        addPair(w, runner);
        drive(w, "a.txt", "one\n", 1700000000);
        runOk(w, runner);
        const success = status(w, runner).pairs[0].lastSuccess;
        drive(w, "b.txt", "not yet\n", 1700000000);
        row.setup(w);
        const calls = rcloneCalls(w).length;
        const out = cli(w, ["run"], runner);
        assert.equal(out.status, 1, row.name);
        assert.equal(out.stdout, "pair=docs result=" + row.state + "\n", row.name);
        assert.equal(rcloneCalls(w).length > calls, row.rclone, row.name);
        assert.deepEqual(mirrorFiles(w), ["a.txt"], row.name);
        const s = status(w, runner);
        assert.equal(s.state, row.state, row.name);
        assert.equal(s.pairs[0].lastSuccess, success, row.name);
        assert.equal(s.lastSuccess, success, row.name);
        assert.equal(s.pairs[0].lastError.kind, row.kind, row.name);
        if (row.account !== undefined) assert.equal(s.pairs[0].lastError.account, row.account, row.name);
        if (row.state === "authorization-required") assert.deepEqual(s.attention.reasons, ["authorization-required"], row.name);
        // The same cause again keeps the attention key, so the plugin does
        // not notify again for it.
        assert.equal(cli(w, ["run"], runner).stdout, "pair=docs result=" + row.state + "\n", row.name);
        assert.deepEqual(status(w, runner).attention, s.attention, row.name + ": a repeated failure keeps the key");
    }
    // Another cause changes the key.
    const w = world();
    assert.equal(cli(w, ["install"], runner).status, 0);
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    write(path.join(w.stub, "mode"), "auth");
    cli(w, ["run"], runner);
    const refused = status(w, runner).attention.key;
    fs.unlinkSync(path.join(w.stub, "mode"));
    fs.unlinkSync(path.join(w.stub, "secrets", "token"));
    cli(w, ["run"], runner);
    assert.notEqual(status(w, runner).attention.key, refused, "a new cause changes the key");
    // Offline with a kept conflict: the conflict alone needs the user, so
    // repeated offline runs keep the key.
    const v = world();
    assert.equal(cli(v, ["install"], runner).status, 0);
    addPair(v, runner);
    drive(v, "a.txt", "one\n", 1700000000);
    runOk(v, runner);
    write(path.join(v.mirror, "a.txt"), "edited here, longer than before\n");
    fs.utimesSync(path.join(v.mirror, "a.txt"), 1700000500, 1700000500);
    drive(v, "a.txt", "one changed on Drive\n", 1700001000);
    runOk(v, runner);
    const kept = status(v, runner).attention;
    assert.deepEqual(kept.reasons, ["conflicts"]);
    write(path.join(v.stub, "mode"), "offline");
    cli(v, ["run"], runner);
    cli(v, ["run"], runner);
    assert.deepEqual(status(v, runner).attention, kept, "offline runs keep the conflicts' key");
}

const EXCLUDED = ["~$draft.docx", ".~lock.sheet.ods#", "notes.swp", "notes.txt~", ".#notes.txt", "big.iso.partial", "file.crdownload",
    ".git/config", "sub/.git/HEAD", ".agents/state.json", "local/derived/text.md", "archive/legacy-backups/2019.zip", "sub/key.pem",
    "server.key", "credentials.json", "token.json", "client_secret_123.json", ".env", ".env.local", "id_ed25519"];
const KEPT = ["keep.txt", "archive/2020/keep.pdf", "sub/report.docx"];

// What never enters the mirror and never leaves the upload folder.
function caseExclusions(runner) {
    const w = world();
    addPair(w, runner);
    for (const rel of EXCLUDED.concat(KEPT)) drive(w, rel, "x " + rel + "\n", 1700000000);
    runOk(w, runner);
    assert.deepEqual(mirrorFiles(w), KEPT.slice().sort());
    const uploads = path.join(w.home, "inbox", "agent-uploads");
    fs.mkdirSync(path.join(w.drive, "Inbox", "agent-uploads"), { recursive: true });
    // A `.git` at the upload folder's own root makes it a repository root,
    // which the pair rules refuse; a nested one is excluded.
    for (const rel of EXCLUDED.filter(rel => rel !== ".git/config" && rel !== "sub/.git/HEAD").concat(KEPT)) write(path.join(uploads, rel), "u " + rel + "\n");
    addPair(w, runner, { id: "uploads", label: "Agent uploads", remote: "Inbox/agent-uploads", local: uploads });
    const out = cli(w, ["run", "--pair", "uploads"], runner);
    assert.equal(out.stdout, "pair=uploads result=idle\n", out.stderr);
    const sent = [];
    const walk = (dir, rel) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const child = rel === "" ? entry.name : rel + "/" + entry.name;
            if (entry.isDirectory()) walk(path.join(dir, entry.name), child);
            else sent.push(child);
        }
    };
    walk(path.join(w.drive, "Inbox", "agent-uploads"), "");
    assert.deepEqual(sent.sort(), KEPT.slice().sort());
    const call = rcloneCalls(w).find(c => c.argv[2] === "copy" && c.argv.includes(uploads) && c.argv.includes("vgsdrive:Inbox/agent-uploads"));
    assert.equal(call.env.RCLONE_CONFIG_VGSDRIVE_SCOPE, "drive");
    assert.equal(call.env.RCLONE_CONFIG_VGSDRIVE_CLIENT_ID, SECRETS["client-id"]);
    assert.equal(call.env.RCLONE_CONFIG_VGSDRIVE_TOKEN, SECRETS["token"]);
    assert.ok(!call.argv.some(a => a.startsWith("--drive-import-formats")));
}

// Each refusal of a pair, against an existing pair `docs`.
function validationRows(w) {
    const repoDir = path.join(w.home, "repo");
    fs.mkdirSync(path.join(repoDir, ".git"), { recursive: true });
    fs.mkdirSync(path.join(w.home, "projects", "deep", "personal", ".git"), { recursive: true });
    return [
        { rule: null, def: { id: "uploads", remote: "Inbox/agent-uploads", local: path.join(w.home, "inbox") } },
        { rule: "shape", def: { extra: true } },
        { rule: "id", def: { id: "Bad_Id" } },
        { rule: "label", def: { label: "" } },
        { rule: "drive-root", def: { remote: "" } },
        { rule: "remote", def: { remote: "Other/../Docs" } },
        { rule: "local", def: { local: "mirror/other" } },
        { rule: "home-or-above", def: { local: w.home } },
        { rule: "home-or-above", def: { local: "/" } },
        { rule: "home-or-above", def: { local: path.dirname(w.home) } },
        { rule: "repository-root", def: { local: repoDir } },
        { rule: "state-overlap", def: { local: path.join(w.state, "elsewhere") } },
        { rule: "vgs-overlap", def: { local: path.join(w.home, ".local", "share", "vgshell", "google-drive", "engine") } },
        { rule: "vgs-overlap", def: { local: path.join(w.home, ".config") } },
        { rule: "unit-overlap", def: { local: path.join(w.home, ".config", "systemd", "user") } },
        { rule: "repository-inside", def: { local: w.home + "/projects" } },
        { rule: "duplicate-id", def: { id: "docs" } },
        { rule: "local-overlap", def: { local: path.join(w.mirror, "sub") } },
        { rule: "remote-overlap", def: { remote: "Docs/Sub" } }
    ].map(row => Object.assign(row, { def: Object.assign({ id: "other", label: "Other", remote: "Other", local: path.join(w.home, "mirror", "other") }, row.def) }));
}

function caseValidation(runner, onlyRule) {
    const w = world();
    addPair(w, runner);
    const before = read(path.join(w.home, ".config", "vgshell", "google-drive", "pairs.json"));
    for (const row of validationRows(w)) {
        if (onlyRule !== undefined && row.rule !== onlyRule) continue;
        const out = cli(w, ["pair-add", "--definition", JSON.stringify(row.def)], runner);
        if (row.rule === null) {
            assert.equal(out.status, 0, out.stderr);
            assert.equal(cli(w, ["pair-remove", row.def.id], runner).status, 0);
            continue;
        }
        assert.equal(out.status, 1, "rule " + row.rule + " " + JSON.stringify(row.def));
        const refused = /^google-drive: refused: pair=\S+ rule=(\S+)$/m.exec(out.stderr);
        assert.ok(refused !== null, out.stderr);
        assert.equal(refused[1], row.rule, JSON.stringify(row.def));
        assert.equal(read(path.join(w.home, ".config", "vgshell", "google-drive", "pairs.json")), before);
    }
    if (onlyRule !== undefined) return;
    // A hand-edited list that breaks a rule runs nothing and reads as an
    // error.
    write(path.join(w.home, ".config", "vgshell", "google-drive", "pairs.json"), JSON.stringify({ pairs: [{ id: "all", label: "All", remote: "", local: w.mirror }] }));
    const out = cli(w, ["run"], runner);
    assert.equal(out.status, 1);
    assert.match(out.stderr, /^google-drive: refused: pair=all rule=drive-root$/m);
    assert.deepEqual(rcloneCalls(w), []);
    const s = status(w, runner);
    assert.equal(s.state, "error");
    assert.equal(s.lastError.kind, "pairs-invalid");
    // Removing a pair deletes no file.
    const v = world();
    addPair(v, runner);
    drive(v, "a.txt", "one\n", 1700000000);
    runOk(v, runner);
    assert.equal(cli(v, ["pair-remove", "docs"], runner).stdout, "removed=docs\n");
    assert.deepEqual(mirrorFiles(v), ["a.txt"]);
    assert.equal(status(v, runner).state, "not-set-up");
}

// install writes both units and enables the timer through systemctl;
// start asks systemd for the same service; the units name the engine copy
// and hold no credential.
function caseInstall(runner) {
    const w = world();
    assert.equal(status(w, runner).state, "not-set-up");
    let out = cli(w, ["start"], runner);
    assert.equal(out.status, 1);
    assert.match(out.stderr, /^google-drive: refused: units=absent$/m);
    out = cli(w, ["install"], runner);
    assert.equal(out.stdout, "installed=vgs-google-drive.timer changed=2\n", out.stderr);
    const unitDir = path.join(w.home, ".config", "systemd", "user");
    const service = read(path.join(unitDir, "vgs-google-drive.service"));
    const timer = read(path.join(unitDir, "vgs-google-drive.timer"));
    SEEN.push(service, timer);
    const engines = fs.readdirSync(path.join(w.home, ".local", "share", "vgshell", "google-drive", "engine"));
    assert.equal(engines.length, 1);
    const engine = path.join(w.home, ".local", "share", "vgshell", "google-drive", "engine", engines[0], "google-drive");
    assert.equal(read(engine), read(runner || RUNNER));
    assert.ok((fs.statSync(engine).mode & 0o111) !== 0);
    const lines = service.split("\n");
    assert.ok(lines.includes("Type=oneshot"));
    assert.ok(lines.includes("ExecStart=\"" + process.execPath + "\" \"" + engine + "\" \"run\""));
    assert.ok(lines.includes("SuccessExitStatus=75"));
    assert.ok(timer.split("\n").includes("OnCalendar=hourly"));
    assert.ok(timer.split("\n").includes("Persistent=true"));
    assert.deepEqual(read(path.join(w.stub, "systemctl.calls")).trim().split("\n"), ["--user daemon-reload", "--user enable --now vgs-google-drive.timer"]);
    addPair(w, runner);
    assert.equal(cli(w, ["pairs", "--lines"], runner).stdout, "docs\tDocuments\n", "the Remove a folder pair list");
    assert.equal(status(w, runner).units, "installed");
    out = cli(w, ["install"], runner);
    assert.equal(out.stdout, "installed=vgs-google-drive.timer changed=0\n");
    out = cli(w, ["start"], runner);
    assert.equal(out.stdout, "started=vgs-google-drive.service\n", out.stderr);
    assert.deepEqual(read(path.join(w.stub, "systemctl.calls")).trim().split("\n").slice(2), ["--user enable --now vgs-google-drive.timer", "--user start --no-block vgs-google-drive.service"]);
    write(path.join(unitDir, "vgs-google-drive.service"), service.replace(engines[0], "0000000000000000"));
    const s = status(w, runner);
    assert.equal(s.units, "installed");
    assert.ok(read(path.join(unitDir, "vgs-google-drive.service")).includes(engines[0]));
}

// The words of one unit line's value as systemd reads them back, the
// forms the runner writes and no other: whitespace between words, each word
// double-quoted with `\\` and `\"` escaped (systemd.syntax(7) § Quoting),
// `%%` for `%` (systemd.unit(5) § Specifiers), and on a command line `$$`
// for `$` (systemd.service(5) § Command lines). Environment= gives `$` no
// meaning (systemd.exec(5)).
function unitWords(value, commandLine) {
    const words = [];
    let i = 0;
    while (i < value.length) {
        assert.equal(value[i], "\"", "an unquoted word at " + i + ": " + value);
        let word = "";
        for (i += 1; value[i] !== "\""; i += 1) {
            assert.ok(i < value.length, "an unterminated word: " + value);
            const pair = value.slice(i, i + 2);
            if (value[i] === "\\") assert.ok(pair === "\\\\" || pair === "\\\"", "escape " + pair + ": " + value);
            else if (value[i] === "%") assert.equal(pair, "%%", "a specifier: " + value);
            else if (value[i] === "$" && commandLine) assert.equal(pair, "$$", "a variable: " + value);
            else {
                word += value[i];
                continue;
            }
            word += pair[1];
            i += 1;
        }
        i += 1;
        if (i < value.length) assert.equal(value[i++], " ", "words run together: " + value);
        words.push(word);
    }
    return words;
}

// install hands the service every directory as systemd reads it back, a
// quote, a space, a percent sign, a dollar sign and a backslash in each
// included, and names the engine copy under them the same way on both
// command lines. A control character in a directory is refused before
// any unit is written.
function caseUnitWords(runner) {
    const w = world();
    const odd = path.join(w.root, "a \"quoted\" 100% $HOME back\\slash");
    const dirs = {
        XDG_CONFIG_HOME: path.join(odd, "config"),
        XDG_STATE_HOME: path.join(odd, "state"),
        XDG_DATA_HOME: path.join(odd, "data"),
        XDG_RUNTIME_DIR: path.join(odd, "run")
    };
    Object.assign(w.env, dirs);
    fs.mkdirSync(dirs.XDG_RUNTIME_DIR, { recursive: true, mode: 0o700 });
    const out = cli(w, ["install"], runner);
    assert.equal(out.stdout, "installed=vgs-google-drive.timer changed=2\n", out.stderr);
    const service = read(path.join(dirs.XDG_CONFIG_HOME, "systemd", "user", "vgs-google-drive.service"));
    SEEN.push(service);
    const value = key => {
        const found = service.split("\n").filter(l => l.startsWith(key + "="));
        assert.equal(found.length, 1, key);
        return found[0].slice(key.length + 1);
    };
    assert.deepEqual(unitWords(value("Environment"), false).sort(), Object.entries(dirs).map(([name, dir]) => name + "=" + dir).sort());
    const engineRoot = path.join(dirs.XDG_DATA_HOME, "vgshell", "google-drive", "engine");
    const engines = fs.readdirSync(engineRoot);
    assert.equal(engines.length, 1);
    const engine = path.join(engineRoot, engines[0], "google-drive");
    assert.deepEqual(unitWords(value("ExecStart"), true), [process.execPath, engine, "run"]);
    assert.deepEqual(unitWords(value("ExecStopPost"), true), [process.execPath, engine, "status", "--quiet"]);
    const v = world();
    v.env.XDG_STATE_HOME = path.join(v.root, "state\nnext");
    const refused = cli(v, ["install"], runner);
    assert.equal(refused.status, 1);
    assert.match(refused.stderr, /^google-drive: refused: unit-argument=control-character$/m);
    assert.ok(!fs.existsSync(path.join(v.env.XDG_CONFIG_HOME, "systemd", "user", "vgs-google-drive.service")));
}

// The probe reads presence alone, a locked item included, and a token's
// `user` attribute when it holds an address, a locked item's too.
function caseProbe(runner) {
    const w = world({ secrets: ["client-id", "client-secret"] });
    write(path.join(w.stub, "secrets", "token.user." + ACCOUNT), SECRETS["token"]);
    write(path.join(w.stub, "secrets", "token.locked"), "");
    addPair(w, runner);
    let out = cli(w, ["probe"], runner);
    assert.equal(out.status, 0, out.stderr);
    assert.deepEqual(JSON.parse(out.stdout), { credentials: [
        { account: "client-id", presence: "present", needed: true },
        { account: "client-secret", presence: "present", needed: true },
        { account: "token", presence: "locked", needed: true, user: ACCOUNT }
    ] });
    // A token without `user`, and one whose `user` is no address, carry none.
    const v = world({ secrets: ["token"] });
    write(path.join(v.stub, "secrets", "token.user.not an address"), SECRETS["token"]);
    out = cli(v, ["probe"], runner);
    assert.equal(out.status, 0, out.stderr);
    const rows = JSON.parse(out.stdout).credentials.filter(c => c.account === "token");
    assert.deepEqual(rows, [
        { account: "token", presence: "present", needed: false }
    ]);
}

// authorize reads the direction's client from the keyring, hands it to
// `rclone authorize drive` in the environment alone with the direction's
// scope, and stores the token rclone prints through secret-tool's stdin,
// byte for byte, never printing it. A missing client secret starts no
// consent, and a token without a refresh token is not stored.
//
// The token item names the account Drive's about read returns as its
// `user`, and is the account's one item: an older one without `user`, or
// of another user, is gone. The access token reaches curl on stdin alone.
// A failed read, or an address the judge refuses, still stores the token,
// without `user`, and logs one keyed line.
function caseAuthorize(runner) {
    const w = world({ secrets: ["client-id", "client-secret", "client-id", "client-secret"] });
    write(path.join(w.stub, "secrets", "token"), "an older sign-in");
    write(path.join(w.stub, "secrets", "token.user.other@example.com"), "another account's sign-in");
    for (const direction of ["drive"]) {
        const out = cli(w, ["authorize"], runner);
        assert.equal(out.stdout, "authorized=" + "drive" + "\n", out.stderr);
        assert.deepEqual(tokenItems(w, direction), ["token.user." + ACCOUNT]);
        assert.equal(read(path.join(w.stub, "secrets", "token.user." + ACCOUNT)), CONSENT_TOKEN);
        assert.ok(!out.stdout.includes("fake-consent") && !out.stderr.includes("fake-consent"), "the token is printed");
        assert.ok(!/^google-drive: account=/m.test(out.stderr), out.stderr);
    }
    const reads = jsonLines(path.join(w.stub, "curl.calls"));
    assert.equal(reads.length, 1);
    for (const call of reads) {
        assert.ok(!call.argv.some(a => CONSENT_VALUES.some(v => a.includes(v))), "the token is in curl's argv: " + JSON.stringify(call.argv));
        assert.equal(call.stdin, "Authorization: Bearer " + CONSENT_VALUES[0] + "\n");
        assert.deepEqual([call.argv[0], call.argv[call.argv.length - 1]], ["-q", ABOUT_URL]);
        assert.ok(call.argv.includes("--max-time"));
    }
    const calls = rcloneCalls(w);
    assert.deepEqual(calls.map(c => c.argv), [["--config", "/dev/null", "authorize", "drive"]]);
    assert.deepEqual(calls.map(c => c.env), [{
        RCLONE_DRIVE_CLIENT_ID: SECRETS["client-id"],
        RCLONE_DRIVE_CLIENT_SECRET: SECRETS["client-secret"],
        RCLONE_DRIVE_SCOPE: "drive"
    }]);
    const stores = read(path.join(w.stub, "secret-tool.calls")).trim().split("\n");
    assert.deepEqual(stores, [
        "clear service vgs-google-drive account token",
        "store --label=VGS Google Drive token service vgs-google-drive account token user " + ACCOUNT
    ]);
    for (const row of [{ mode: "fail", reason: "curl-failed exit=22" }, { mode: "bad", reason: "address-invalid" }]) {
        const u = world({ secrets: ["client-id", "client-secret"] });
        write(path.join(u.stub, "secrets", "pull-token.user.other@example.com"), "another account's sign-in");
        write(path.join(u.stub, "curl-mode"), row.mode);
        const out = cli(u, ["authorize"], runner);
        assert.equal(out.stdout, "authorized=drive\n", out.stderr);
        assert.deepEqual(tokenItems(u), ["token"], row.mode);
        assert.equal(read(path.join(u.stub, "secrets", "token")), CONSENT_TOKEN, row.mode);
        assert.deepEqual(out.stderr.split("\n").filter(l => l.startsWith("google-drive: account=")), ["google-drive: account=unread reason=" + row.reason], row.mode);
    }
    const v = world({ secrets: ["client-id"] });
    let out = cli(v, ["authorize"], runner);
    assert.equal(out.status, 1);
    assert.match(out.stderr, /^google-drive: refused: credential=absent account=client-secret$/m);
    assert.deepEqual(rcloneCalls(v), []);
    const x = world({ secrets: ["client-id", "client-secret"] });
    write(path.join(x.stub, "mode"), "no-refresh");
    out = cli(x, ["authorize"], runner);
    assert.match(out.stderr, /^google-drive: refused: authorize=no-token$/m);
    assert.ok(!fs.existsSync(path.join(x.stub, "secrets", "token")));
}

// sign-out clears every item of one direction's token and leaves the other
// direction and the client keys; that direction's pairs read as needing a
// sign-in at once, their last success kept. A locked item is not cleared,
// and sign-out says so.
function caseSignOut(runner) {
    const w = world();
    write(path.join(w.stub, "secrets", "token.user." + ACCOUNT), SECRETS["token"]);
    assert.equal(cli(w, ["install"], runner).status, 0);
    addPair(w, runner);
    const uploads = path.join(w.home, "inbox");
    fs.mkdirSync(uploads, { recursive: true });
    fs.mkdirSync(path.join(w.drive, "Inbox"), { recursive: true });
    addPair(w, runner, { id: "uploads", label: "Agent uploads", remote: "Inbox", local: uploads });
    drive(w, "a.txt", "one\n", 1700000000);
    const ran = cli(w, ["run"], runner);
    assert.equal(ran.status, 0, ran.stderr);
    const before = status(w, runner);
    const out = cli(w, ["sign-out"], runner);
    assert.equal(out.stdout, "signed-out=drive\n", out.stderr);
    assert.deepEqual(tokenItems(w), []);
    for (const account of ["client-id", "client-secret"]) assert.ok(fs.existsSync(path.join(w.stub, "secrets", account)), account);
    const s = JSON.parse(read(path.join(w.state, "status.json")));
    const docs = s.pairs.find(p => p.id === "docs");
    assert.equal(docs.state, "authorization-required");
    assert.deepEqual([docs.lastError.kind, docs.lastError.account], ["credential-absent", "token"]);
    assert.equal(docs.lastSuccess, before.pairs.find(p => p.id === "docs").lastSuccess);
    assert.equal(s.pairs.find(p => p.id === "uploads").state, "authorization-required");
    assert.deepEqual(status(w, runner).pairs, s.pairs, "the next render keeps it");
    assert.deepEqual([s.attention.reasons, s.attention.notified], [["authorization-required"], true], "the user's own sign-out notifies nothing");
    assert.deepEqual(mirrorFiles(w), ["a.txt"]);
    // A sign-in again: the direction's pairs leave the sign-in state at
    // once, their last success kept; the other direction stays as it was.
    const back = cli(w, ["authorize"], runner);
    assert.equal(back.stdout, "authorized=drive\n", back.stderr);
    const t = JSON.parse(read(path.join(w.state, "status.json")));
    const signedIn = t.pairs.find(p => p.id === "docs");
    assert.deepEqual([signedIn.state, signedIn.lastError, signedIn.lastSuccess], ["idle", null, docs.lastSuccess]);
    assert.equal(t.pairs.find(p => p.id === "uploads").state, "idle");
    assert.equal(t.attention, null);
    const v = world();
    write(path.join(v.stub, "secrets", "token.locked"), "");
    const locked = cli(v, ["sign-out"], runner);
    assert.equal(locked.status, 1);
    assert.match(locked.stderr, /^google-drive: refused: credential=locked account=token$/m);
    assert.equal(cli(v, ["sign-out", "both"], runner).status, 2);
}

// pairs-reset is only for an invalid list: it keeps the damaged bytes,
// starts a valid empty list, refreshes status and lets pair changes work
// again. A valid or absent list is never reset.
function casePairsReset(runner) {
    const w = world();
    const file = path.join(w.home, ".config", "vgshell", "google-drive", "pairs.json");
    const damaged = "{\"pairs\": [";
    write(file, damaged);
    const out = cli(w, ["pairs-reset"], runner);
    assert.equal(out.status, 0, out.stderr);
    assert.match(out.stdout, /^reset=pairs\.json\.damaged-\d{8}T\d{6}Z\n$/);
    const keptName = out.stdout.trim().slice("reset=".length);
    const kept = path.join(path.dirname(file), keptName);
    assert.equal(fs.existsSync(kept), true, "the damaged file is kept");
    assert.equal(read(kept), damaged, "the damaged bytes are kept exactly");
    assert.deepEqual(JSON.parse(read(file)), { pairs: [] });
    const rendered = JSON.parse(read(path.join(w.state, "status.json")));
    assert.equal(rendered.lastError, null);
    assert.deepEqual(rendered.pairs, []);
    addPair(w, runner);
    const validBefore = read(file);
    const refused = cli(w, ["pairs-reset"], runner);
    assert.equal(refused.status, 1);
    assert.match(refused.stderr, /^google-drive: refused: pairs=valid$/m);
    assert.equal(read(file), validBefore, "a valid list is unchanged");
    assert.deepEqual(fs.readdirSync(path.dirname(file)).filter(name => name.startsWith("pairs.json.damaged-")).sort(), [keptName]);

    const absent = world();
    const absentFile = path.join(absent.home, ".config", "vgshell", "google-drive", "pairs.json");
    const absentOut = cli(absent, ["pairs-reset"], runner);
    assert.equal(absentOut.status, 1);
    assert.match(absentOut.stderr, /^google-drive: refused: pairs=valid$/m);
    assert.equal(fs.existsSync(absentFile), false, "an absent list stays absent");

    const invalidPair = world();
    const invalidPairFile = path.join(invalidPair.home, ".config", "vgshell", "google-drive", "pairs.json");
    write(invalidPairFile, JSON.stringify({ pairs: [{ id: "docs", label: "Documents", remote: "Docs", local: invalidPair.home }] }));
    const prefixed = "google-drive: refused: pairs=invalid pair=docs rule=home-or-above";
    const add = cli(invalidPair, ["pair-add", "--definition", JSON.stringify({ id: "more", label: "More", remote: "More", local: path.join(invalidPair.home, "more") })], runner);
    assert.equal(add.status, 1);
    assert.match(add.stderr, new RegExp("^" + prefixed + "$", "m"));
    const remove = cli(invalidPair, ["pair-remove", "docs"], runner);
    assert.equal(remove.status, 1);
    assert.match(remove.stderr, new RegExp("^" + prefixed + "$", "m"));
    const lines = cli(invalidPair, ["pairs", "--lines"], runner);
    assert.equal(lines.status, 1);
    assert.match(lines.stderr, new RegExp("^" + prefixed + "$", "m"));

    assert.equal(cli(world(), ["pairs-reset", "extra"], runner).status, 2);
}

// attention-seen marks the record's key notified across renders, pause
// and resume, and a process that reads it afresh; a new key reads
// notified=false again.
function caseAttention(runner) {
    const w = world();
    assert.equal(cli(w, ["install"], runner).status, 0);
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    assert.equal(status(w, runner).attention, null);
    write(path.join(w.mirror, "a.txt"), "edited here, longer than before\n");
    fs.utimesSync(path.join(w.mirror, "a.txt"), 1700000500, 1700000500);
    drive(w, "a.txt", "one changed on Drive\n", 1700001000);
    runOk(w, runner);
    const first = status(w, runner).attention;
    assert.deepEqual([first.reasons, first.notified], [["conflicts"], false]);
    const out = cli(w, ["attention-seen", first.key], runner);
    assert.equal(out.stdout, "seen=" + first.key + "\n", out.stderr);
    const seen = Object.assign({}, first, { notified: true });
    assert.deepEqual(JSON.parse(read(path.join(w.state, "status.json"))).attention, seen, "attention-seen rewrites the record");
    assert.deepEqual(status(w, runner).attention, seen, "a second render keeps it");
    for (const args of [["pause"], ["resume"], ["pause", "--pair", "docs"], ["resume", "--pair", "docs"]]) {
        assert.equal(cli(w, args, runner).status, 0);
        assert.deepEqual(status(w, runner).attention, seen, args.join(" ") + " keeps it");
    }
    write(path.join(w.stub, "mode"), "auth");
    cli(w, ["run"], runner);
    const next = status(w, runner).attention;
    assert.notEqual(next.key, first.key);
    assert.equal(next.notified, false, "a new key is not notified");
    for (const bad of [[], ["nope"], [first.key, "extra"]]) assert.equal(cli(w, ["attention-seen"].concat(bad), runner).status, 2, JSON.stringify(bad));
    // A failure that recovers and returns the same way notifies again.
    const u = world();
    assert.equal(cli(u, ["install"], runner).status, 0);
    addPair(u, runner);
    drive(u, "a.txt", "one\n", 1700000000);
    runOk(u, runner);
    write(path.join(u.stub, "mode"), "auth");
    cli(u, ["run"], runner);
    const refused = status(u, runner).attention;
    assert.equal(cli(u, ["attention-seen", refused.key], runner).status, 0);
    assert.equal(status(u, runner).attention.notified, true);
    fs.unlinkSync(path.join(u.stub, "mode"));
    runOk(u, runner);
    assert.equal(status(u, runner).attention, null);
    write(path.join(u.stub, "mode"), "auth");
    cli(u, ["run"], runner);
    const again = status(u, runner).attention;
    assert.deepEqual([again.key, again.notified], [refused.key, false], "a returned failure is not notified");
}

// Two pairs refused at once keep one attention key through a whole run:
// the renders as each pair starts and ends, which the rclone stand-in
// records, and the one after it.
function caseRunKey(runner) {
    const w = world();
    assert.equal(cli(w, ["install"], runner).status, 0);
    addPair(w, runner);
    const uploads = path.join(w.home, "inbox");
    fs.mkdirSync(uploads, { recursive: true });
    addPair(w, runner, { id: "up", label: "Agent uploads", remote: "Inbox", local: uploads });
    write(path.join(w.stub, "mode"), "auth");
    cli(w, ["run"], runner);
    const settled = status(w, runner).attention;
    assert.deepEqual(settled.reasons, ["authorization-required"]);
    const before = rcloneCalls(w).length;
    const out = cli(w, ["run"], runner);
    assert.equal(out.stdout, "pair=docs result=authorization-required\npair=up result=authorization-required\n", out.stderr);
    const during = rcloneCalls(w).slice(before).map(c => c.attention === null ? null : c.attention.key);
    assert.equal(during.length, 2);
    assert.deepEqual(during.concat([status(w, runner).attention.key]), [settled.key, settled.key, settled.key]);
}

// No credential value in any argv, log line, unit or status record.
function caseNoLeak() {
    for (const dir of fs.readdirSync(scratch)) {
        const statusFile = path.join(scratch, dir, "home", ".local", "state", "vgshell", "google-drive", "status.json");
        if (fs.existsSync(statusFile)) SEEN.push(read(statusFile));
        for (const name of ["rclone.calls", "curl.calls"])
            for (const call of jsonLines(path.join(scratch, dir, "stub", name))) SEEN.push(JSON.stringify(call.argv));
    }
    assert.ok(SEEN.length > 50);
    for (const text of SEEN) {
        for (const [account, value] of Object.entries(SECRETS))
            assert.ok(!String(text).includes(value), "the value of " + account + " leaked");
        for (const value of CONSENT_VALUES) assert.ok(!String(text).includes(value), "the consent token leaked");
    }
}

function caseFullDriveSharedFolder(runner) {
    const w = world();
    const local = path.join(w.home, "mirror", "shared");
    const added = cli(w, ["pair-add", "--definition", JSON.stringify({ id: "shared", label: "Shared", remote: "Shared", local: local })], runner);
    assert.equal(added.status, 0, added.stderr);
    write(path.join(w.drive, "Shared", "original.txt"), "drive\n");
    write(path.join(local, "local.txt"), "local\n");
    const ran = cli(w, ["run"], runner);
    assert.equal(ran.stdout, "pair=shared result=idle\n", ran.stderr);
    assert.equal(fs.existsSync(path.join(w.drive, "Shared", "local.txt")), true);
    assert.equal(read(path.join(w.drive, "Shared", "local.txt")), "local\n");
    assert.equal(fs.existsSync(path.join(w.second, "Shared", "local.txt")), false);
    assert.equal(fs.readdirSync(w.drive).filter(name => name === "Shared").length, 1);
}

function caseLocalAdd(runner) {
    const w = world();
    addPair(w, runner);
    write(path.join(w.mirror, "local-add.txt"), "local add\n");
    runOk(w, runner);
    assert.equal(read(path.join(w.drive, "Docs", "local-add.txt")), "local add\n");
}

function caseRemovedLocally(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "removed-local.txt", "drive copy\n", 1700000000);
    runOk(w, runner);
    fs.unlinkSync(path.join(w.mirror, "removed-local.txt"));
    runOk(w, runner);
    assert.equal(read(path.join(w.drive, "Docs", "removed-local.txt")), "drive copy\n");
    assert.equal(read(path.join(w.mirror, "removed-local.txt")), "drive copy\n");
    assert.deepEqual(status(w, runner).conflicts.map(c => [c.kind, c.path]), [["removed-locally", "removed-local.txt"]]);
}

function caseRemovedOnDriveReturns(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "removed-drive.txt", "local copy\n", 1700000000);
    runOk(w, runner);
    fs.unlinkSync(path.join(w.drive, "Docs", "removed-drive.txt"));
    runOk(w, runner);
    assert.equal(read(path.join(w.mirror, "removed-drive.txt")), "local copy\n");
    assert.equal(read(path.join(w.drive, "Docs", "removed-drive.txt")), "local copy\n");
    assert.deepEqual(status(w, runner).conflicts.map(c => [c.kind, c.path]), [["removed-on-drive", "removed-drive.txt"]]);
}

function caseBothChangedLocalNewer(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "local-newer.txt", "base\n", 1700000000);
    runOk(w, runner);
    drive(w, "local-newer.txt", "drive older\n", 1700000500);
    write(path.join(w.mirror, "local-newer.txt"), "local newer\n");
    fs.utimesSync(path.join(w.mirror, "local-newer.txt"), 1700001000, 1700001000);
    runOk(w, runner);
    assert.equal(read(path.join(w.drive, "Docs", "local-newer.txt")), "local newer\n");
    const found = status(w, runner).conflicts.find(c => c.path === "local-newer.txt");
    assert.equal(found.kind, "both-changed");
    assert.equal(Object.prototype.hasOwnProperty.call(found, "storedPath"), false);
}

// A both-changed file gone from both sides leaves the pair record at the
// next run, unless the record holds a kept copy, the only version left.
function caseBothChangedGoneBothSides(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "no-copy.txt", "base\n", 1700000000);
    drive(w, "kept.txt", "Drive version\n", 1700000000);
    runOk(w, runner);
    drive(w, "no-copy.txt", "drive older\n", 1700000500);
    write(path.join(w.mirror, "no-copy.txt"), "local newer\n");
    fs.utimesSync(path.join(w.mirror, "no-copy.txt"), 1700001000, 1700001000);
    write(path.join(w.mirror, "kept.txt"), "edited here, longer than before\n");
    fs.utimesSync(path.join(w.mirror, "kept.txt"), 1700000500, 1700000500);
    drive(w, "kept.txt", "Drive version changed\n", 1700001000);
    runOk(w, runner);
    const records = () => JSON.parse(read(path.join(w.state, "pairs", "docs", "state.json"))).records
        .map(r => [r.kind, r.path, typeof r.stored === "string"]).sort();
    assert.deepEqual(records(), [["both-changed", "kept.txt", true], ["both-changed", "no-copy.txt", false]]);
    for (const rel of ["no-copy.txt", "kept.txt"]) {
        fs.unlinkSync(path.join(w.drive, "Docs", rel));
        fs.unlinkSync(path.join(w.mirror, rel));
    }
    runOk(w, runner);
    assert.deepEqual(records(), [["both-changed", "kept.txt", true]]);
}

// An export of a Google-native document (the stand-in lists it at Size
// -1) comes down and never goes up, edited here or not, and a name with
// rclone filter characters is excluded as itself.
function caseExportNoUpload(runner) {
    const w = world();
    addPair(w, runner);
    const name = "Plan [draft] *v2*.docx";
    write(path.join(w.stub, "exports"), name + "\n");
    drive(w, name, "exported\n", 1700000000);
    runOk(w, runner);
    assert.equal(read(path.join(w.mirror, name)), "exported\n");
    write(path.join(w.mirror, name), "edited here\n");
    runOk(w, runner);
    assert.equal(read(path.join(w.drive, "Docs", name)), "exported\n");
    const upload = rcloneCalls(w).filter(c => c.argv[2] === "copy" && c.argv[5].startsWith(REMOTE_PREFIX));
    assert.ok(upload.length >= 2 && upload.every(c => c.argv.includes("--exclude-from")));
}

// After a Google Doc is renamed (or moved, or deleted) on Drive, the old
// export stays here, a removal to review, and never uploads in any later
// run.
function caseExportRenamedOnDrive(runner) {
    const w = world();
    addPair(w, runner);
    write(path.join(w.stub, "exports"), "Report.docx\n");
    drive(w, "Report.docx", "exported\n", 1700000000);
    runOk(w, runner);
    fs.renameSync(path.join(w.drive, "Docs", "Report.docx"), path.join(w.drive, "Docs", "Final.docx"));
    write(path.join(w.stub, "exports"), "Final.docx\n");
    runOk(w, runner);
    runOk(w, runner);
    assert.equal(fs.existsSync(path.join(w.drive, "Docs", "Report.docx")), false);
    assert.equal(read(path.join(w.mirror, "Report.docx")), "exported\n");
    assert.deepEqual(status(w, runner).conflicts.map(c => [c.kind, c.path]), [["removed-on-drive", "Report.docx"]]);
}

// A failed upload leg after a complete download keeps the baseline the
// download reached, so a later local edit is a local change, not a
// conflict with a Drive change the mirror already holds.
function caseFailedUploadKeepsBaseline(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    drive(w, "a.txt", "two, from Drive\n", 1700003600);
    write(path.join(w.stub, "fail-upload"), "");
    runOk(w, runner, "error");
    assert.equal(read(path.join(w.mirror, "a.txt")), "two, from Drive\n");
    write(path.join(w.mirror, "a.txt"), "three, edited here\n");
    fs.utimesSync(path.join(w.mirror, "a.txt"), 1700007200, 1700007200);
    runOk(w, runner);
    assert.equal(read(path.join(w.drive, "Docs", "a.txt")), "three, edited here\n");
    assert.deepEqual(status(w, runner).conflicts, []);
}

// Names with a space, an en dash and a no-break space, as Drive allows.
const UNREADABLE = ["reports/Plan – first draft.pdf", "reports/Second gone.pdf"];
const DUPLICATE = "reports/Twice listed.txt";
// Another Google account than the signed-in ACCOUNT, and two md5 values.
const OTHER = "someone.else@example.com";
const MD5_ONE = "0f2d7d1a5b3e4c6a8b9d0e1f2a3b4c5d";
const MD5_TWO = "9e8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b";

// One copy of a doubled name as the folder listing gives it: OWNER is
// its `owner` metadata, or null for a copy that names none, as a shared
// drive's file does; MD5 null for a Google-native document, which rclone
// lists with Size -1 and no md5.
function listedCopy(rel, id, size, md5, owner) {
    const name = rel.slice(rel.lastIndexOf("/") + 1);
    const item = { Path: name, Name: name, Size: size, MimeType: "text/plain", ModTime: "2026-10-13T00:00:00Z", IsDir: false, ID: id, Metadata: { "content-type": "text/plain" } };
    if (md5 !== null) item.Hashes = { md5: md5 };
    if (owner !== null) item.Metadata.owner = owner;
    return item;
}

// Each [rel, copies] of NAMES as a name Drive holds twice: the copy leg's
// notice, and its copies in the listing of its folder. The fixture Drive
// file the copy leg copies is the caller's.
function plantDoubled(w, names) {
    const listings = {};
    for (const [rel, copies] of names) {
        const folder = "vgsdrive:Docs" + (rel.includes("/") ? "/" + rel.slice(0, rel.lastIndexOf("/")) : "");
        listings[folder] = (listings[folder] || []).concat(copies);
    }
    write(path.join(w.stub, "duplicate"), names.map(n => n[0]).join("\n") + "\n");
    write(path.join(w.stub, "folder-listings"), JSON.stringify(listings));
}

// Two different copies of DUPLICATE the signed-in account owns.
const MINE_DIFFERENT = [listedCopy(DUPLICATE, "copy-1", 13, MD5_ONE, ACCOUNT), listedCopy(DUPLICATE, "copy-2", 20, MD5_TWO, ACCOUNT)];

function plantUnreadable(w, reason) {
    drive(w, "a.txt", "one\n", 1700000000);
    for (const rel of UNREADABLE) drive(w, rel, "a shortcut to nothing\n", 1700000000);
    write(path.join(w.stub, "unreadable"), UNREADABLE.join("\n") + "\n");
    write(path.join(w.stub, "unreadable-reason"), reason);
    drive(w, DUPLICATE, "listed twice\n", 1700000000);
    plantDoubled(w, [[DUPLICATE, MINE_DIFFERENT]]);
}

// The structured fields of a status record's conflict a duplicate or the
// needs rule decides.
function marks(c) {
    return { kind: c.kind, path: c.path, needs: c.needs, mine: c.mine, owner: c.owner };
}

// A download that copied every file but two Drive could not open, and met
// a name Drive holds twice: the pair is synced, the run exits 0, and the
// three files wait for review, once each for rclone's three attempts. A
// file that failed in the first attempt alone and then copied is not one.
// A file with no copy here names no local folder.
function caseUnreadableOnDrive(runner) {
    const w = world({ user: ACCOUNT });
    assert.equal(cli(w, ["install"], runner).status, 0);
    addPair(w, runner);
    plantUnreadable(w, DANGLING_REASON);
    write(path.join(w.stub, "recovered"), "a.txt");
    const out = cli(w, ["run"], runner);
    assert.equal(out.stdout, "pair=docs result=idle\n", out.stderr);
    assert.equal(out.status, 0);
    assert.deepEqual(mirrorFiles(w), ["a.txt", DUPLICATE]);
    const s = status(w, runner);
    assert.equal(s.pairs[0].state, "idle");
    assert.equal(s.pairs[0].lastError, null);
    assert.notEqual(s.pairs[0].lastSuccess, null);
    assert.deepEqual(s.conflicts.map(c => [c.kind, c.path, c.reason, c.localPath, c.needs]), [
        ["unreadable-on-drive", UNREADABLE[0], DANGLING_REASON, undefined, "nothing"],
        ["unreadable-on-drive", UNREADABLE[1], DANGLING_REASON, undefined, "nothing"],
        ["duplicate-different", DUPLICATE, undefined, path.join(w.mirror, DUPLICATE), "you"]
    ]);
    assert.equal(s.needsYou, 1);
    assert.deepEqual(s.attention.reasons, ["conflicts"]);
    return w;
}

// The same files failing again keep their records' time, so the attention
// key stands, also past the age at which other records are removed; once
// they copy, no record of them or of the doubled name stays.
function caseUnreadableClears(runner) {
    const w = caseUnreadableOnDrive(runner);
    const first = status(w, runner);
    runOk(w, runner);
    assert.deepEqual(status(w, runner).conflicts, first.conflicts);
    assert.equal(status(w, runner).attention.key, first.attention.key);
    const stateFile = path.join(w.state, "pairs", "docs", "state.json");
    const state = JSON.parse(read(stateFile));
    for (const record of state.records) record.since = "2000-01-01T00:00:00.000Z";
    write(stateFile, JSON.stringify(state));
    runOk(w, runner);
    assert.deepEqual(status(w, runner).conflicts.map(c => c.since), first.conflicts.map(() => "2000-01-01T00:00:00.000Z"));
    fs.unlinkSync(path.join(w.stub, "unreadable"));
    fs.unlinkSync(path.join(w.stub, "duplicate"));
    fs.unlinkSync(path.join(w.stub, "folder-listings"));
    runOk(w, runner);
    assert.deepEqual(mirrorFiles(w), ["a.txt", DUPLICATE].concat(UNREADABLE).sort());
    assert.deepEqual(status(w, runner).conflicts, []);
}

// A download that could not run to its end stays a failed sync with no
// file to review: a network cause that shows as file errors, an error
// count above the files named, and rclone's fatal exit.
const DOWNLOAD_FAILURES = [
    { name: "network cause", reason: OFFLINE_REASON, flag: null, state: "offline", kind: "offline" },
    { name: "error naming no file", reason: DANGLING_REASON, flag: "uncounted", state: "error", kind: "rclone-failed" },
    { name: "fatal exit", reason: DANGLING_REASON, flag: "fatal", state: "error", kind: "rclone-failed" }
];

function caseDownloadFailures(runner, only) {
    for (const row of DOWNLOAD_FAILURES.filter(r => only === undefined || r.name === only)) {
        const w = world();
        addPair(w, runner);
        plantUnreadable(w, row.reason);
        if (row.flag !== null) write(path.join(w.stub, row.flag), "");
        const out = cli(w, ["run"], runner);
        assert.equal(out.stdout, "pair=docs result=" + row.state + "\n", row.name + ": " + out.stderr);
        assert.equal(out.status, 1, row.name);
        const s = status(w, runner);
        assert.equal(s.pairs[0].lastError.kind, row.kind, row.name);
        assert.equal(s.pairs[0].lastSuccess, null, row.name);
        assert.deepEqual(s.conflicts, [], row.name);
    }
}

// A clean download that met a name Drive holds twice records it.
function caseDuplicateOnCleanRun(runner) {
    const w = world({ user: ACCOUNT });
    addPair(w, runner);
    drive(w, DUPLICATE, "listed twice\n", 1700000000);
    plantDoubled(w, [[DUPLICATE, MINE_DIFFERENT]]);
    const out = cli(w, ["run"], runner);
    assert.equal(out.stdout, "pair=docs result=idle\n", out.stderr);
    assert.equal(out.status, 0);
    assert.deepEqual(status(w, runner).conflicts.map(marks), [{ kind: "duplicate-different", path: DUPLICATE, needs: "you", mine: true, owner: undefined }]);
}

// A doubled name's record, from the folder listing alone: identical
// when every copy has the same md5 and size, else different; mine when
// the signed-in account owns a copy, compared without case; a record
// that is not mine names the copies' owner when one is named. USER is
// the account the token item names, null for a token that names none.
const DUPLICATE_ROWS = [
    { name: "identical copies the account owns", user: ACCOUNT, copies: [listedCopy(DUPLICATE, "c1", 13, MD5_ONE, ACCOUNT), listedCopy(DUPLICATE, "c2", 13, MD5_ONE, ACCOUNT)],
        want: { kind: "duplicate-identical", needs: "nothing", mine: true, owner: undefined } },
    { name: "different copies the account owns", user: ACCOUNT, copies: MINE_DIFFERENT,
        want: { kind: "duplicate-different", needs: "you", mine: true, owner: undefined } },
    { name: "one copy the account owns", user: ACCOUNT, copies: [listedCopy(DUPLICATE, "c1", 13, MD5_ONE, OTHER), listedCopy(DUPLICATE, "c2", 20, MD5_TWO, ACCOUNT.toUpperCase())],
        want: { kind: "duplicate-different", needs: "you", mine: true, owner: undefined } },
    { name: "different copies another account owns", user: ACCOUNT, copies: [listedCopy(DUPLICATE, "c1", 13, MD5_ONE, OTHER), listedCopy(DUPLICATE, "c2", 20, MD5_TWO, OTHER)],
        want: { kind: "duplicate-different", needs: "nothing", mine: false, owner: OTHER } },
    { name: "identical copies another account owns", user: ACCOUNT, copies: [listedCopy(DUPLICATE, "c1", 13, MD5_ONE, OTHER), listedCopy(DUPLICATE, "c2", 13, MD5_ONE, OTHER)],
        want: { kind: "duplicate-identical", needs: "nothing", mine: false, owner: OTHER } },
    { name: "Google-native documents", user: ACCOUNT, copies: [listedCopy(DUPLICATE, "c1", -1, null, ACCOUNT), listedCopy(DUPLICATE, "c2", -1, null, ACCOUNT)],
        want: { kind: "duplicate-different", needs: "you", mine: true, owner: undefined } },
    { name: "same md5, another size", user: ACCOUNT, copies: [listedCopy(DUPLICATE, "c1", 13, MD5_ONE, ACCOUNT), listedCopy(DUPLICATE, "c2", 14, MD5_ONE, ACCOUNT)],
        want: { kind: "duplicate-different", needs: "you", mine: true, owner: undefined } },
    { name: "a shared drive's copies name no owner", user: ACCOUNT, copies: [listedCopy(DUPLICATE, "c1", 13, MD5_ONE, null), listedCopy(DUPLICATE, "c2", 20, MD5_TWO, null)],
        want: { kind: "duplicate-different", needs: "nothing", mine: false, owner: undefined } },
    { name: "the token names no account", user: null, copies: MINE_DIFFERENT,
        want: { kind: "duplicate-different", needs: "nothing", mine: false, owner: ACCOUNT } }
];

function caseDuplicateRecords(runner, only) {
    for (const row of DUPLICATE_ROWS.filter(r => only === undefined || r.name === only)) {
        const w = world({ user: row.user });
        assert.equal(cli(w, ["install"], runner).status, 0);
        addPair(w, runner);
        drive(w, DUPLICATE, "listed twice\n", 1700000000);
        plantDoubled(w, [[DUPLICATE, row.copies]]);
        runOk(w, runner);
        const s = status(w, runner);
        assert.deepEqual(s.conflicts.map(marks), [Object.assign({ path: DUPLICATE }, row.want)], row.name);
        assert.equal(s.needsYou, row.want.needs === "you" ? 1 : 0, row.name);
        assert.deepEqual(s.attention === null ? [] : s.attention.reasons, row.want.needs === "you" ? ["conflicts"] : [], row.name);
        const stored = JSON.parse(read(path.join(w.state, "pairs", "docs", "state.json"))).records;
        assert.deepEqual(stored.map(r => [r.kind, r.mine, r.owner]), [[row.want.kind, row.want.mine, row.want.owner]], row.name + ": the pair record keeps the marks");
    }
}

// The folder listing that decides a doubled name is read-only, runs only
// when the copy met a doubled name, and once per folder that holds one.
// A listing that fails fails the sync as any other leg does.
function caseDuplicateListing(runner) {
    const w = world({ user: ACCOUNT });
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    const metadataReads = () => rcloneCalls(w).filter(c => c.argv[2] === "lsjson" && c.argv.includes("--metadata"));
    assert.deepEqual(metadataReads(), [], "no doubled name, no folder listing");
    const second = "reports/Also twice.txt";
    const root = "Top twice.txt";
    for (const rel of [DUPLICATE, second, root]) drive(w, rel, "listed twice\n", 1700000000);
    plantDoubled(w, [
        [DUPLICATE, MINE_DIFFERENT],
        [second, [listedCopy(second, "c3", 5, MD5_ONE, ACCOUNT), listedCopy(second, "c4", 5, MD5_ONE, ACCOUNT)]],
        [root, [listedCopy(root, "c5", 5, MD5_ONE, OTHER), listedCopy(root, "c6", 7, MD5_TWO, OTHER)]]
    ]);
    runOk(w, runner);
    const reads = metadataReads();
    assert.deepEqual(reads.map(c => c.argv.slice(2, 11)), [
        ["lsjson", "--files-only", "--hash", "--hash-type", "md5", "--metadata", "--drive-metadata-owner", "read", "vgsdrive:Docs/reports"],
        ["lsjson", "--files-only", "--hash", "--hash-type", "md5", "--metadata", "--drive-metadata-owner", "read", "vgsdrive:Docs"]
    ]);
    for (const call of reads) assert.equal(call.argv[call.argv.indexOf("--drive-export-formats") + 1], "docx,xlsx,pptx,svg");
    assert.deepEqual(status(w, runner).conflicts.map(c => [c.path, c.kind, c.needs]).sort(), [
        [root, "duplicate-different", "nothing"],
        [second, "duplicate-identical", "nothing"],
        [DUPLICATE, "duplicate-different", "you"]
    ].sort());
    write(path.join(w.stub, "folder-listing-offline"), "");
    const out = cli(w, ["run"], runner);
    assert.equal(out.stdout, "pair=docs result=offline\n", out.stderr);
    assert.equal(status(w, runner).pairs[0].lastError.kind, "offline");
}

// Whether each kind of review record needs the user, from records as the
// runner writes them; then a record whose rows all need nothing asks for
// no attention, one row that needs the user brings the reason back, and a
// note added beside it keeps the key.
const NEEDS_ROWS = [
    [{ kind: "both-changed", path: "b.txt" }, "you"],
    [{ kind: "removed-locally", path: "l.txt" }, "nothing"],
    [{ kind: "removed-on-drive", path: "d.txt" }, "nothing"],
    [{ kind: "renamed", path: "r.txt", to: "r2.txt" }, "nothing"],
    [{ kind: "unreadable-on-drive", path: "s.lnk", reason: DANGLING_REASON }, "nothing"],
    [{ kind: "unreadable-on-drive", path: "u.pdf", reason: "failed to open source object: stand-in read error" }, "you"],
    [{ kind: "duplicate-identical", path: "i.txt", mine: true }, "nothing"],
    [{ kind: "duplicate-different", path: "m.txt", mine: true }, "you"],
    [{ kind: "duplicate-different", path: "o.txt", mine: false, owner: OTHER }, "nothing"]
];

function writeRecords(w, records) {
    const file = path.join(w.state, "pairs", "docs", "state.json");
    const state = JSON.parse(read(file));
    state.records = records.map(r => Object.assign({ since: "2026-10-13T00:00:00.000Z" }, r));
    write(file, JSON.stringify(state));
}

function caseNeedsAttention(runner) {
    const w = world();
    assert.equal(cli(w, ["install"], runner).status, 0);
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    writeRecords(w, NEEDS_ROWS.map(row => row[0]));
    const all = status(w, runner);
    assert.deepEqual(all.conflicts.map(c => [c.path, c.needs]), NEEDS_ROWS.map(row => [row[0].path, row[1]]));
    assert.equal(all.needsYou, NEEDS_ROWS.filter(row => row[1] === "you").length);
    const notes = NEEDS_ROWS.filter(row => row[1] === "nothing").map(row => row[0]);
    writeRecords(w, notes);
    const quiet = status(w, runner);
    assert.equal(quiet.needsYou, 0);
    assert.equal(quiet.attention, null, "notes alone ask for no attention");
    const needing = NEEDS_ROWS.find(row => row[0].kind === "both-changed")[0];
    writeRecords(w, notes.slice(1).concat([needing]));
    const asked = status(w, runner);
    assert.equal(asked.needsYou, 1);
    assert.deepEqual(asked.attention.reasons, ["conflicts"]);
    writeRecords(w, notes.concat([needing]));
    assert.equal(status(w, runner).attention.key, asked.attention.key, "a note beside it keeps the key");
}

// The pair record's earlier doubled-name kind, which said nothing of the
// copies, is dropped on the first invocation, with no credential or
// network; the next sync that meets the name records it whole. A status
// record an earlier runner notified of stays notified across the change
// of key, so the update raises no notification; one it had not notified
// of stays not notified.
const MIGRATION_ROWS = [
    { name: "notified", notified: true },
    { name: "not notified", notified: false }
];

function caseDuplicateMigration(runner, only) {
    for (const row of MIGRATION_ROWS.filter(r => only === undefined || r.name === only)) {
        const w = world({ user: ACCOUNT });
        assert.equal(cli(w, ["install"], runner).status, 0);
        addPair(w, runner);
        drive(w, "a.txt", "one\n", 1700000000);
        runOk(w, runner);
        const stateFile = path.join(w.state, "pairs", "docs", "state.json");
        const old = JSON.parse(read(stateFile));
        old.records = [
            { kind: "duplicate-on-drive", path: DUPLICATE, since: "2026-10-13T00:00:00.000Z" },
            { kind: "both-changed", path: "b.txt", since: "2026-10-13T00:00:00.000Z" }
        ];
        write(stateFile, JSON.stringify(old));
        // The earlier runner's record: no needsYou, its key over every row.
        const earlier = JSON.parse(read(path.join(w.state, "status.json")));
        delete earlier.needsYou;
        earlier.attention = { reasons: ["conflicts"], key: "0123456789abcdef", notified: row.notified };
        write(path.join(w.state, "status.json"), JSON.stringify(earlier));
        write(path.join(w.state, "control.json"), JSON.stringify({ paused: false, pausedPairs: [], notifiedKey: row.notified ? "0123456789abcdef" : null }));
        const out = cli(w, ["pairs"], runner);
        assert.equal(out.status, 0, row.name + ": " + out.stderr);
        assert.deepEqual(JSON.parse(read(stateFile)).records.map(r => r.kind), ["both-changed"], row.name);
        assert.equal(rcloneCalls(w).filter(c => c.argv.includes("--metadata")).length, 0, row.name + ": the migration lists nothing");
        const s = JSON.parse(read(path.join(w.state, "status.json")));
        assert.deepEqual([s.needsYou, s.attention.reasons, s.attention.notified], [1, ["conflicts"], row.notified], row.name);
        assert.deepEqual(status(w, runner).attention, s.attention, row.name + ": a later render keeps it");
        drive(w, DUPLICATE, "listed twice\n", 1700000000);
        plantDoubled(w, [[DUPLICATE, MINE_DIFFERENT]]);
        runOk(w, runner);
        assert.deepEqual(status(w, runner).conflicts.filter(c => c.path === DUPLICATE).map(marks), [{ kind: "duplicate-different", path: DUPLICATE, needs: "you", mine: true, owner: undefined }], row.name);
    }
}

// A changed Drive file whose download failed keeps the baseline of the
// copy here, and counts as no change: the sync that copies it later makes
// no conflict of it. Its older copy here names its folder.
function caseUnreadableKeepsBaseline(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    drive(w, "a.txt", "two, from Drive\n", 1700003600);
    write(path.join(w.stub, "unreadable"), "a.txt\n");
    write(path.join(w.stub, "unreadable-reason"), DANGLING_REASON);
    runOk(w, runner);
    const held = status(w, runner);
    assert.deepEqual(held.conflicts.map(c => [c.kind, c.path, c.localPath]), [["unreadable-on-drive", "a.txt", path.join(w.mirror, "a.txt")]]);
    assert.deepEqual(held.pairs[0].changes, { added: 0, updated: 0 });
    assert.equal(read(path.join(w.mirror, "a.txt")), "one\n");
    fs.unlinkSync(path.join(w.stub, "unreadable"));
    runOk(w, runner);
    assert.equal(read(path.join(w.mirror, "a.txt")), "two, from Drive\n");
    assert.deepEqual(status(w, runner).conflicts, []);
}

// A pair with nothing synced whose only Drive file could not be copied,
// and whose Drive folder then goes away: the next sync has no download
// and keeps no record of that folder's files.
function caseUnreadableDriveFolderGone(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, UNREADABLE[0], "a shortcut to nothing\n", 1700000000);
    write(path.join(w.stub, "unreadable"), UNREADABLE[0] + "\n");
    write(path.join(w.stub, "unreadable-reason"), DANGLING_REASON);
    plantDoubled(w, [[DUPLICATE, MINE_DIFFERENT]]);
    // An excluded file: the mirror exists and nothing uploads.
    write(path.join(w.mirror, "notes.swp"), "swap\n");
    runOk(w, runner);
    assert.deepEqual(status(w, runner).conflicts.map(c => c.kind), ["unreadable-on-drive", "duplicate-different"]);
    fs.rmSync(path.join(w.drive, "Docs"), { recursive: true, force: true });
    write(path.join(w.mirror, "first.txt"), "first\n");
    runOk(w, runner);
    assert.deepEqual(status(w, runner).conflicts, []);
}

// Two Drive-newer conflicts on one path keep two copies and two records.
function caseRepeatedConflict(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "n.md", "base\n", 1700000000);
    runOk(w, runner);
    for (const [round, at] of [[1, 1700001000], [2, 1700003000]]) {
        write(path.join(w.mirror, "n.md"), "edit " + round + " here\n");
        fs.utimesSync(path.join(w.mirror, "n.md"), at - 500, at - 500);
        drive(w, "n.md", "drive " + round + "\n", at);
        runOk(w, runner);
    }
    const kept = status(w, runner).conflicts.filter(c => c.path === "n.md").map(c => read(c.storedPath)).sort();
    assert.deepEqual(kept, ["edit 1 here\n", "edit 2 here\n"]);
}

// A path both sides hold with no baseline: a newer, different local file
// replaces Drive's and is recorded; an equal one is no conflict.
function caseSamePathNoBaseline(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "same.txt", "same\n", 1700000000);
    write(path.join(w.mirror, "same.txt"), "same\n");
    fs.utimesSync(path.join(w.mirror, "same.txt"), 1700000500, 1700000500);
    drive(w, "differs.txt", "drive's\n", 1700000000);
    write(path.join(w.mirror, "differs.txt"), "this computer's\n");
    fs.utimesSync(path.join(w.mirror, "differs.txt"), 1700000500, 1700000500);
    runOk(w, runner);
    assert.equal(read(path.join(w.drive, "Docs", "differs.txt")), "this computer's\n");
    assert.deepEqual(status(w, runner).conflicts.map(c => [c.kind, c.path, c.storedPath]), [["both-changed", "differs.txt", undefined]]);
}

// An old pair list the new judge refuses, such as an upload pair over a
// folder that holds a Git repository, is still migrated: every verb runs,
// the status reads the list as invalid, and Start again recovers.
function casePairListMigrationRefused(runner) {
    const w = world();
    const pairsFile = path.join(w.env.XDG_CONFIG_HOME, "vgshell", "google-drive", "pairs.json");
    const local = path.join(w.home, "outbox");
    fs.mkdirSync(path.join(local, "project", ".git"), { recursive: true });
    write(pairsFile, JSON.stringify({ pairs: [{ id: "uploads", label: "Uploads", direction: "upload", remote: "Up", local: local }] }));
    const s = status(w, runner);
    assert.deepEqual([s.state, s.lastError.kind], ["error", "pairs-invalid"]);
    assert.match(s.lastError.detail, /rule=repository-inside/);
    assert.equal(JSON.parse(read(pairsFile)).pairs[0].direction, undefined);
    const reset = cli(w, ["pairs-reset"], runner);
    assert.equal(reset.status, 0, reset.stderr);
    assert.deepEqual(JSON.parse(read(pairsFile)), { pairs: [] });
}

// Kept local edits the previous runner recorded get 30 days from the
// upgrade, not deletion by the first prune.
function caseStateMigrationKeepsCopies(runner) {
    const w = world();
    addPair(w, runner);
    const pairDir = path.join(w.state, "pairs", "docs");
    write(path.join(pairDir, "conflicts", "20200101T000000Z-1", "a.txt"), "kept edit\n");
    write(path.join(pairDir, "state.json"), JSON.stringify({
        state: "idle", startedAt: null, lastAttempt: null, lastSuccess: null, lastError: null, changes: null,
        localEdits: [{ path: "a.txt", stored: "20200101T000000Z-1/a.txt", at: "2020-01-01T00:00:00.000Z" }]
    }));
    drive(w, "a.txt", "drive\n", 1700000000);
    runOk(w, runner);
    const kept = status(w, runner).conflicts;
    assert.deepEqual(kept.map(c => [c.kind, c.path]), [["both-changed", "a.txt"]]);
    assert.equal(read(kept[0].storedPath), "kept edit\n");
    assert.ok(Date.now() - Date.parse(kept[0].since) < 3600 * 1000);
}

// Old client keys split across the two old clients: both keys come from
// the one client that holds both; with no complete client nothing is
// copied and the old accounts stay, so no key is lost.
function caseCredentialMigrationMixed(runner) {
    const w = world({ secrets: [] });
    for (const account of ["pull-client-id", "upload-client-id", "upload-client-secret", "upload-token"])
        write(path.join(w.stub, "secrets", account), OLD_SECRETS[account]);
    assert.equal(cli(w, ["probe"], runner).status, 0);
    assert.equal(read(path.join(w.stub, "secrets", "client-id")), "old-upload-client");
    assert.equal(read(path.join(w.stub, "secrets", "client-secret")), "old-upload-secret");
    const held = world({ secrets: [] });
    write(path.join(held.stub, "secrets", "pull-client-id"), OLD_SECRETS["pull-client-id"]);
    const out = cli(held, ["probe"], runner);
    assert.equal(out.status, 0, out.stderr);
    assert.match(out.stderr, /^google-drive: migration=held reason=credential-incomplete$/m);
    assert.equal(read(path.join(held.stub, "secrets", "pull-client-id")), "old-pull-client");
}

// Units an earlier runner installed are rewritten to name this runner on
// its next invocation; a refresh the user manager refuses leaves them
// stale and the verb still answers.
function caseStaleUnitsRefresh(runner) {
    const w = world();
    assert.equal(cli(w, ["install"], runner).status, 0);
    const unitFile = path.join(w.home, ".config", "systemd", "user", "vgs-google-drive.service");
    const engineRoot = path.join(w.home, ".local", "share", "vgshell", "google-drive", "engine");
    const hash = fs.readdirSync(engineRoot)[0];
    const installed = read(unitFile);
    write(unitFile, installed.split(hash).join("0000000000000000"));
    write(path.join(w.stub, "systemctl-fail"), "");
    const failed = status(w, runner);
    assert.equal(failed.units, "stale");
    assert.ok(failed.attention.reasons.includes("units-stale"));
    fs.rmSync(path.join(w.stub, "systemctl-fail"));
    assert.equal(status(w, runner).units, "installed");
    assert.equal(read(unitFile), installed);
}

// The layout the runner kept under its name before the rename to Google
// Drive, planted in W: a paused pair with an inventory and a kept copy,
// the setup log, an engine copy, the hourly units with the timer enabled
// and, unless KEYRING is false, the three keyring items, the token naming
// its account.
const OLD_NAME = "cloud-sync";
const OLD_KEPT = "20990101T000000Z-1/a.txt";

function oldPlaces(w) {
    return {
        config: path.join(w.env.XDG_CONFIG_HOME, "vgshell", OLD_NAME),
        state: path.join(w.env.XDG_STATE_HOME, "vgshell", OLD_NAME),
        data: path.join(w.env.XDG_DATA_HOME, "vgshell", OLD_NAME)
    };
}

function plantOldLayout(w, keyring) {
    const old = oldPlaces(w);
    write(path.join(old.config, "pairs.json"), JSON.stringify({ pairs: [{ id: "docs", label: "Documents", remote: "Docs", local: w.mirror }] }, null, 2) + "\n");
    write(path.join(old.state, "control.json"), JSON.stringify({ paused: false, pausedPairs: ["docs"], notifiedKey: null }, null, 2) + "\n");
    write(path.join(old.state, "pairs", "docs", "state.json"), JSON.stringify({
        state: "idle", startedAt: null, lastAttempt: null, lastSuccess: null, lastError: null, changes: null,
        records: [{ kind: "both-changed", path: "a.txt", stored: OLD_KEPT, since: new Date().toISOString() }]
    }, null, 2) + "\n");
    write(path.join(old.state, "pairs", "docs", "inventory.json"), JSON.stringify({ entries: { "a.txt": { size: 6, mtimeMs: 1, hash: null, id: null } } }, null, 2) + "\n");
    write(path.join(old.state, "pairs", "docs", "conflicts", OLD_KEPT), "kept edit\n");
    write(path.join(old.state, "setup.log"), "earlier line\n");
    write(path.join(old.data, "engine", "0000000000000000", OLD_NAME), "the previous runner\n", 0o755);
    const unitDir = path.join(w.env.XDG_CONFIG_HOME, "systemd", "user");
    write(path.join(unitDir, "vgs-cloud-sync.service"), "[Service]\nExecStart=" + path.join(old.data, "engine", "0000000000000000", OLD_NAME) + " run\n");
    write(path.join(unitDir, "vgs-cloud-sync.timer"), "[Timer]\nOnCalendar=hourly\n");
    write(path.join(w.stub, "enabled"), "vgs-cloud-sync.timer\n");
    if (keyring === false) return old;
    write(path.join(w.stub, "old-secrets", "client-id"), SECRETS["client-id"]);
    write(path.join(w.stub, "old-secrets", "client-secret"), SECRETS["client-secret"]);
    write(path.join(w.stub, "old-secrets", "token.user." + ACCOUNT), SECRETS["token"]);
    return old;
}

// Every file under each of DIRS, by path, with its bytes.
function snapshot(dirs) {
    const files = {};
    for (const dir of dirs) {
        const walk = d => {
            if (!fs.existsSync(d)) return;
            for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
                const child = path.join(d, entry.name);
                if (entry.isDirectory()) walk(child);
                else files[child] = fs.readFileSync(child, "utf8");
            }
        };
        walk(dir);
    }
    return files;
}

// What the Google Drive Settings Setup tab and Details page read from the
// runner's status record and probe, through the plugin's own judge.
function setupValues(w, runner) {
    const Logic = load(path.join(__dirname, "..", "shell", "plugins", "vgs.google-drive", "GoogleDriveLogic.js"));
    const statusOut = cli(w, ["status"], runner);
    const probeOut = cli(w, ["probe"], runner);
    assert.equal(statusOut.status + probeOut.status, 0, statusOut.stderr + probeOut.stderr);
    const record = Logic.parseStatus(statusOut.stdout);
    const presence = Logic.parseProbe(probeOut.stdout);
    assert.ok(record.ok && presence.ok, JSON.stringify([record, presence]));
    // The judge runs in its own realm; JSON brings its answer into this one.
    return JSON.parse(JSON.stringify(Logic.statusValues(record.record, presence.presence, "", "", Date.now())));
}

// The units the systemctl stand-in holds enabled, sorted.
function enabledUnits(w) {
    const file = path.join(w.stub, "enabled");
    return fs.existsSync(file) ? read(file).split("\n").filter(Boolean).sort() : [];
}

const CREDENTIAL_ACCOUNTS = ["client-id", "client-secret", "token"];
const UNIT_HOLD = { exit: "held", reason: "old-service-activating" };
const FIRST_RENAME_CALLS = [
    "--user is-active vgs-cloud-sync.service",
    "--user disable --now vgs-cloud-sync.timer",
    "--user is-active vgs-cloud-sync.service",
    "--user daemon-reload",
    "--user enable --now vgs-google-drive.timer",
    "--user daemon-reload",
    "--user reset-failed vgs-cloud-sync.service vgs-cloud-sync.timer"
];
// Each state the rename can meet at the shell's first start, the hold it
// makes and what ends the hold. Every row then ends with the same moved
// home.
const RENAME_ROWS = [
    { name: "previous service idle", plant: () => {}, hold: null, calls: FIRST_RENAME_CALLS },
    {
        name: "previous service syncing",
        plant: w => write(path.join(w.stub, "old-run"), ""),
        hold: UNIT_HOLD,
        release: w => fs.unlinkSync(path.join(w.stub, "old-run")),
        calls: ["--user is-active vgs-cloud-sync.service"].concat(FIRST_RENAME_CALLS)
    },
    {
        name: "previous timer starts a sync as it is disabled",
        plant: w => write(path.join(w.stub, "fire-on-disable"), ""),
        hold: UNIT_HOLD,
        release: w => fs.unlinkSync(path.join(w.stub, "old-run")),
        calls: [
            "--user is-active vgs-cloud-sync.service",
            "--user disable --now vgs-cloud-sync.timer",
            "--user is-active vgs-cloud-sync.service",
            "--user enable --now vgs-cloud-sync.timer"
        ].concat(FIRST_RENAME_CALLS)
    },
    {
        name: "keyring locked",
        plant: w => { for (const account of CREDENTIAL_ACCOUNTS) write(path.join(w.stub, "old-secrets", account + ".locked"), ""); },
        hold: { exit: 0, reason: "credential-locked" },
        release: w => { for (const account of CREDENTIAL_ACCOUNTS) fs.unlinkSync(path.join(w.stub, "old-secrets", account + ".locked")); },
        calls: FIRST_RENAME_CALLS
    }
];

// The held invocation of ROW: a running previous sync refuses it with the
// code the plugin's service asks again on, with nothing moved and the
// previous timer enabled; a locked keyring holds its own step alone, and
// every reader takes the held items as locked, never as absent.
function assertRenameHeld(w, row, runner, out, before) {
    const Logic = load(path.join(__dirname, "..", "shell", "plugins", "vgs.google-drive", "GoogleDriveLogic.js"));
    const old = oldPlaces(w);
    if (row.hold.exit === "held") {
        assert.equal(out.status, Logic.RUNNER_HELD, out.stderr);
        assert.match(out.stderr, new RegExp("^google-drive: refused: migration=held reason=" + row.hold.reason + "$", "m"));
        assert.equal(Logic.heldReason(out.stderr), "old-sync", "the service reads the runner's hold as a running previous sync");
        assert.deepEqual(snapshot(Object.values(old)), before);
        assert.deepEqual(fs.readdirSync(w.state), ["setup.log"]);
        assert.deepEqual(enabledUnits(w), ["vgs-cloud-sync.timer"]);
        return;
    }
    assert.equal(out.status, 0, out.stderr);
    for (const account of CREDENTIAL_ACCOUNTS)
        assert.match(out.stderr, new RegExp("^google-drive: migration=held reason=" + row.hold.reason + " account=" + account + "$", "m"));
    assert.ok(!/result=written/.test(out.stderr), out.stderr);
    for (const dir of Object.values(old)) assert.equal(fs.existsSync(dir), false, dir);
    assert.deepEqual(enabledUnits(w), ["vgs-google-drive.timer"]);
    assert.ok(fs.existsSync(path.join(w.state, "rename.pending")));
    assert.deepEqual(fs.readdirSync(path.join(w.stub, "secrets")), []);
    const probed = cli(w, ["probe"], runner);
    assert.deepEqual(JSON.parse(probed.stdout).credentials.map(c => c.presence), ["locked", "locked", "locked"]);
    assert.equal(setupValues(w, runner).account.text, "Keyring locked");
    assert.equal(cli(w, ["resume", "--pair", "docs"], runner).status, 0);
    assert.equal(cli(w, ["run"], runner).stdout, "pair=docs result=authorization-required\n");
    assert.equal(JSON.parse(read(path.join(w.state, "pairs", "docs", "state.json"))).lastError.kind, "credential-locked");
    assert.equal(cli(w, ["pause", "--pair", "docs"], runner).status, 0);
    assert.match(cli(w, ["authorize"], runner).stderr, /^google-drive: refused: credential=locked account=client-id$/m);
}

// A home with the layout of the plugin's name before the rename, its
// hourly units installed and enabled, a paused pair and all three keyring
// items, and the setup log a floating TUI already holds open under the new
// name, in each state of RENAME_ROWS: the invocation that state allows
// moves everything, installs the units under the new name, keeps both
// setup logs with the TUI's file in place and leaves nothing under the old
// name, and an hourly timer is enabled throughout. A further invocation
// changes nothing.
function caseRenameMigration(runner, only) {
    for (const row of RENAME_ROWS.filter(r => only === undefined || r.name === only)) {
        const w = world({ secrets: [] });
        const old = plantOldLayout(w);
        write(path.join(w.state, "setup.log"), "later line\n");
        const tuiLog = fs.statSync(path.join(w.state, "setup.log")).ino;
        row.plant(w);
        const unitDir = path.join(w.env.XDG_CONFIG_HOME, "systemd", "user");
        let out = cli(w, ["status"], runner);
        if (row.hold !== null) {
            assertRenameHeld(w, row, runner, out, snapshot(Object.values(old)));
            row.release(w);
            out = cli(w, ["status"], runner);
        }
        assert.equal(out.status, 0, row.name + ": " + out.stderr);
        assert.match(out.stderr, /^google-drive: migration=rename old=cloud-sync result=written$/m);
        for (const dir of Object.values(old)) assert.equal(fs.existsSync(dir), false, dir);
        assert.equal(fs.existsSync(path.join(w.state, "rename.pending")), false);
        assert.deepEqual(read(path.join(w.env.XDG_CONFIG_HOME, "vgshell", "google-drive", "pairs.json")), JSON.stringify({ pairs: [{ id: "docs", label: "Documents", remote: "Docs", local: w.mirror }] }, null, 2) + "\n");
        assert.deepEqual(JSON.parse(read(path.join(w.state, "control.json"))).pausedPairs, ["docs"]);
        assert.deepEqual(JSON.parse(read(path.join(w.state, "pairs", "docs", "inventory.json"))).entries["a.txt"].size, 6);
        assert.equal(fs.statSync(path.join(w.state, "setup.log")).ino, tuiLog);
        assert.equal(read(path.join(w.state, "setup.log")), "later line\n");
        assert.equal(read(path.join(w.state, "setup.before-rename.log")), "earlier line\n");
        const s = JSON.parse(out.stdout);
        assert.deepEqual([s.units, s.pairs.map(p => [p.id, p.state])], ["installed", [["docs", "paused"]]]);
        assert.deepEqual(s.conflicts.map(c => c.storedPath), [path.join(w.state, "pairs", "docs", "conflicts", OLD_KEPT)]);
        assert.equal(read(s.conflicts[0].storedPath), "kept edit\n");
        // Nothing moved while the previous service read busy, and the
        // previous units went after the new ones were in.
        assert.equal(fs.existsSync(path.join(w.stub, "moved-early")), false);
        assert.deepEqual(read(path.join(w.stub, "systemctl.calls")).trim().split("\n"), row.calls, row.name);
        assert.deepEqual(enabledUnits(w), ["vgs-google-drive.timer"]);
        assert.deepEqual(fs.readdirSync(unitDir).sort(), ["vgs-google-drive.service", "vgs-google-drive.timer"]);
        assert.match(read(path.join(unitDir, "vgs-google-drive.timer")), /^OnCalendar=hourly$/m);
        const engines = fs.readdirSync(path.join(w.env.XDG_DATA_HOME, "vgshell", "google-drive", "engine"));
        assert.equal(engines.length, 1);
        assert.ok(read(path.join(unitDir, "vgs-google-drive.service")).includes(path.join(engines[0], "google-drive")));
        assert.deepEqual(fs.readdirSync(path.join(w.stub, "old-secrets")), []);
        assert.deepEqual(fs.readdirSync(path.join(w.stub, "secrets")).sort(), ["client-id", "client-secret", "token.user." + ACCOUNT]);
        for (const [account, file] of [["client-id", "client-id"], ["client-secret", "client-secret"], ["token", "token.user." + ACCOUNT]])
            assert.equal(read(path.join(w.stub, "secrets", file)), SECRETS[account], account);
        const values = setupValues(w, runner);
        assert.deepEqual([values.schedule.tone, values.firstPair.tone, values.account.tone, values.keys.map(k => k.value)],
            ["ok", "ok", "ok", ["present", "present"]], row.name);
        assert.equal(cli(w, ["probe"], runner).stdout, JSON.stringify({ credentials: [
            { account: "client-id", presence: "present", needed: true },
            { account: "client-secret", presence: "present", needed: true },
            { account: "token", presence: "present", needed: true, user: ACCOUNT }
        ] }) + "\n");

        if (row.name === "previous service idle") {
            for (const name of ["vgs-cloud-sync.service", "vgs-google-drive.service"])
                write(path.join(w.run, "systemd", "user", name + ".d", "90-vgs-google-drive-migrate.conf"), "[Service]\nExecStopPost=\n");
            assert.equal(cli(w, ["probe"], runner).status, 0);
            for (const name of ["vgs-cloud-sync.service", "vgs-google-drive.service"])
                assert.equal(fs.existsSync(path.join(w.run, "systemd", "user", name + ".d", "90-vgs-google-drive-migrate.conf")), false);
        }

        const places = [w.home, path.join(w.stub, "secrets"), path.join(w.stub, "old-secrets")];
        const before = snapshot(places);
        const calls = ["systemctl.calls", "secret-tool.calls"].map(name => read(path.join(w.stub, name)));
        const again = cli(w, ["probe"], runner);
        assert.equal(again.status, 0, again.stderr);
        assert.ok(!/migration=/.test(again.stderr), again.stderr);
        assert.deepEqual(snapshot(places), before);
        assert.deepEqual(["systemctl.calls", "secret-tool.calls"].map(name => read(path.join(w.stub, name))), calls);
    }
}

// Disabled startup shares the rename operations, but stops active old and
// partial-new services and never enables a schedule or invokes a sync.
// A failed stop or locked keyring keeps the source data for the next start.
function caseDisabledMigration(runner, only) {
    const partialInstall = w => {
        const units = path.join(w.env.XDG_CONFIG_HOME, "systemd", "user");
        const stopPost = JSON.parse(read(path.join(w.stub, "stop-post-commands")))["vgs-google-drive.service"];
        write(path.join(units, "vgs-google-drive.service"), "[Service]\nExecStopPost=" + stopPost.map(word => JSON.stringify(word)).join(" ") + "\n");
        write(path.join(units, "vgs-google-drive.timer"), "partial timer\n");
        write(path.join(w.stub, "enabled"), "vgs-cloud-sync.timer\nvgs-google-drive.timer\n");
        write(path.join(w.stub, "new-run"), "");
    };
    const rows = [
        { name: "disabled", plant: () => {} },
        { name: "active old service", plant: w => write(path.join(w.stub, "old-run"), "") },
        { name: "partial new install", plant: partialInstall },
        { name: "locked keyring", plant: w => {
            for (const account of CREDENTIAL_ACCOUNTS) write(path.join(w.stub, "old-secrets", account + ".locked"), "");
        }, release: w => {
            for (const account of CREDENTIAL_ACCOUNTS) fs.unlinkSync(path.join(w.stub, "old-secrets", account + ".locked"));
        } },
        ...["stop-fail", "stop-unconfirmed"].map(marker => ({ name: marker, plant: w => {
            partialInstall(w);
            write(path.join(w.stub, "old-run"), "");
            write(path.join(w.stub, marker), "");
        }, release: w => fs.unlinkSync(path.join(w.stub, marker)), stopHeld: true }))
    ];
    for (const row of rows.filter(row => only === undefined || row.name === only)) {
        const w = world({ secrets: [] });
        const old = plantOldLayout(w);
        const oldEngine = path.join(old.data, "engine", "0000000000000000", OLD_NAME);
        write(oldEngine, read(runner || RUNNER), 0o755);
        const partialEngine = path.join(w.env.XDG_DATA_HOME, "vgshell", "google-drive", "engine", "partial", "google-drive");
        const oldStatus = [process.execPath, oldEngine, "status", "--quiet"];
        const partialStatus = [process.execPath, partialEngine, "status", "--quiet"];
        write(partialEngine, read(runner || RUNNER), 0o755);
        write(path.join(w.stub, "stop-post-commands"), JSON.stringify({ "vgs-cloud-sync.service": oldStatus, "vgs-google-drive.service": partialStatus }));
        row.plant(w);
        const before = snapshot(Object.values(old));
        const assertCleanStop = () => {
            for (const name of ["vgs-cloud-sync.service", "vgs-google-drive.service"])
                assert.equal(fs.existsSync(path.join(w.run, "systemd", "user", name + ".d", "90-vgs-google-drive-migrate.conf")), false, row.name + ": " + name);
            assert.equal(fs.existsSync(path.join(w.stub, "stop-post-executed")), false, row.name);
        };
        let out;
        if (runner === undefined) {
            out = childProcess.spawnSync(path.join(path.dirname(RUNNER), "..", "migrate"), ["disabled"], { env: w.env, encoding: "utf8", timeout: 120000 });
        } else out = cli(w, ["migrate", "disabled"], runner);
        assertCleanStop();
        if (row.release) {
            assert.equal(out.status, 75, row.name + ": " + out.stderr);
            assert.deepEqual(enabledUnits(w), [], row.name);
            if (row.stopHeld) {
                assert.deepEqual(snapshot(Object.values(old)), before);
                assert.ok(fs.existsSync(path.join(w.stub, "old-secrets", "token.user." + ACCOUNT)));
            } else {
                assert.ok(fs.existsSync(path.join(w.state, "rename.pending")));
                assert.ok(fs.existsSync(path.join(w.stub, "old-secrets", "token.user." + ACCOUNT)));
                assert.equal(fs.existsSync(path.join(w.stub, "secret-tool.calls")), false);
            }
            row.release(w);
            out = cli(w, ["migrate", "disabled"], runner);
            assertCleanStop();
        }
        assert.equal(out.status, 0, row.name + ": " + out.stderr);
        assert.deepEqual(enabledUnits(w), [], row.name);
        assert.equal(fs.existsSync(path.join(w.stub, "old-run")), false);
        assert.equal(fs.existsSync(path.join(w.stub, "new-run")), false);
        if (row.name === "active old service") assert.ok(fs.existsSync(path.join(w.stub, "old-run-stopped")));
        for (const dir of Object.values(old)) assert.equal(fs.existsSync(dir), false, row.name + ": " + dir);
        for (const name of ["vgs-cloud-sync.service", "vgs-cloud-sync.timer"])
            assert.equal(fs.existsSync(path.join(w.env.XDG_CONFIG_HOME, "systemd", "user", name)), false);
        assert.deepEqual(fs.readdirSync(path.join(w.stub, "old-secrets")), []);
        assert.equal(fs.existsSync(path.join(w.state, "rename.pending")), false);
        assert.equal(read(path.join(w.state, "pairs", "docs", "conflicts", OLD_KEPT)), "kept edit\n");
        const calls = read(path.join(w.stub, "systemctl.calls"));
        assert.ok(!calls.split("\n").some(line => /--user (enable|start) /.test(line)), row.name + ": " + calls);
        for (const name of ["rclone.calls", "curl.calls"]) assert.equal(fs.existsSync(path.join(w.stub, name)), false);
        const places = [w.home, path.join(w.stub, "secrets"), path.join(w.stub, "old-secrets")];
        const after = snapshot(places);
        assert.equal(cli(w, ["migrate", "disabled"], runner).status, 0);
        assert.deepEqual(snapshot(places), after);
        assert.equal(read(path.join(w.stub, "systemctl.calls")), calls);
        assert.deepEqual(status(w, runner).pairs.map(pair => [pair.id, pair.state]), [["docs", "paused"]]);
        for (const name of ["rclone.calls", "curl.calls"]) assert.equal(fs.existsSync(path.join(w.stub, name)), false);
    }
}

// A rename on a home whose units were never installed, held inside its
// keyring step after every directory has moved, and a sign-out started
// then: the sign-out waits for the rename on the state lock, so the token
// the rename moves is the one it clears and no sign-in comes back.
async function caseRenameConcurrent(runner) {
    const w = world({ secrets: [] });
    plantOldLayout(w);
    for (const unit of ["vgs-cloud-sync.service", "vgs-cloud-sync.timer"]) fs.unlinkSync(path.join(w.env.XDG_CONFIG_HOME, "systemd", "user", unit));
    // flock, logged: a call that waits names -w first.
    fs.unlinkSync(path.join(w.bin, "flock"));
    write(path.join(w.bin, "flock"), "#!" + HOST.bash + "\nprintf '%s\\n' \"$*\" >>" + JSON.stringify(path.join(w.stub, "flock.calls")) + "\nexec " + JSON.stringify(HOST.flock) + " \"$@\"\n", 0o755);
    const waits = () => fs.existsSync(path.join(w.stub, "flock.calls")) ? read(path.join(w.stub, "flock.calls")).split("\n").filter(line => line.startsWith("-w ")).length : 0;
    const made = childProcess.spawnSync(HOST.mkfifo, [path.join(w.stub, "release")]);
    assert.equal(made.status, 0, String(made.stderr));
    write(path.join(w.stub, "block-store"), "token");
    const rename = spawnRunner(w, ["status"], runner);
    let signOut = null;
    try {
        await waitFor(path.join(w.stub, "store-blocked"), "the rename's token store");
        for (const dir of Object.values(oldPlaces(w))) assert.equal(fs.existsSync(dir), false, dir);
        const before = waits();
        signOut = spawnRunner(w, ["sign-out"], runner);
        const deadline = Date.now() + 30000;
        while (waits() === before) {
            if (Date.now() > deadline) throw new Error("timed out waiting for the sign-out's lock wait");
            await sleep(20);
        }
        while (!release(w)) await sleep(20);
        const [renamed, signedOut] = await Promise.all([rename.done, signOut.done]);
        assert.equal(renamed.code, 0, renamed.stderr);
        assert.equal(signedOut.code, 0, signedOut.stderr);
        assert.equal(signedOut.stdout, "signed-out=drive\n");
        assert.deepEqual(fs.readdirSync(path.join(w.stub, "old-secrets")), []);
        assert.deepEqual(fs.readdirSync(path.join(w.stub, "secrets")).sort(), ["client-id", "client-secret"]);
    } finally {
        // A stand-in still waiting on the fifo outlives a killed runner.
        release(w);
        for (const started of [rename, signOut]) if (started !== null && started.child.exitCode === null && started.child.signalCode === null) {
            started.child.kill("SIGKILL");
            await started.exited;
        }
    }
}

function casePruneConflictStorage(runner) {
    const w = world();
    addPair(w, runner);
    const old = path.join(w.state, "pairs", "docs", "conflicts", "20000101T000000Z-1", "old.txt");
    const young = path.join(w.state, "pairs", "docs", "conflicts", "29990101T000000Z-1", "young.txt");
    write(old, "old");
    write(young, "young");
    write(path.join(w.state, "pairs", "docs", "state.json"), JSON.stringify({
        records: [{ kind: "both-changed", path: "old-record.txt", since: "2000-01-01T00:00:00.000Z" }]
    }));
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    assert.equal(fs.existsSync(old), false);
    assert.equal(fs.existsSync(young), true);
    assert.ok(!status(w, runner).conflicts.some(c => c.path === "old-record.txt"));
}

// No rclone call of W can delete or move a file: no deleting verb or flag,
// and --backup-dir only on the download leg, into the pair's own records.
function assertNoDeletingArgv(w) {
    for (const call of rcloneCalls(w)) {
        const words = call.argv;
        const shown = JSON.stringify(words);
        for (const word of words) {
            assert.ok(!/^(sync|bisync|move|moveto|delete|deletefile|purge|rmdir|rmdirs|cleanup|dedupe)$/.test(word), shown);
            assert.ok(!word.startsWith("--delete") && !word.startsWith("--remove-") && word !== "--drive-use-trash=false", shown);
        }
        const at = words.indexOf("--backup-dir");
        if (at === -1) continue;
        assert.ok(words[3] === "--update" && words[4].startsWith(REMOTE_PREFIX), "backup only on the download leg: " + shown);
        assert.ok(words[at + 1].startsWith(path.join(w.state, "pairs") + "/"), "backup inside the pair records: " + shown);
    }
}

function caseForbiddenRcloneArgv(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    write(path.join(w.mirror, "b.txt"), "two\n");
    runOk(w, runner);
    assertNoDeletingArgv(w);
}

// Every world the cases made, so the argv rule holds over every run.
function assertNoDeletingArgvAnywhere() {
    let checked = 0;
    for (const name of fs.readdirSync(scratch)) {
        if (!/^w\d+$/.test(name)) continue;
        const root = path.join(scratch, name);
        assertNoDeletingArgv({ stub: path.join(root, "stub"), state: path.join(root, "home", ".local", "state", "vgshell", "google-drive") });
        checked += 1;
    }
    assert.equal(checked, worlds);
}

const OLD_SECRETS = {
    "pull-client-id": "old-pull-client",
    "pull-client-secret": "old-pull-secret",
    "pull-token": "old-pull-token",
    "upload-client-id": "old-upload-client",
    "upload-client-secret": "old-upload-secret",
    "upload-token": "old-upload-token"
};

function plantOldSecrets(w) {
    for (const [account, value] of Object.entries(OLD_SECRETS)) write(path.join(w.stub, "secrets", account), value);
}

function assertMigratedSecrets(w) {
    assert.equal(read(path.join(w.stub, "secrets", "client-id")), "old-pull-client");
    assert.equal(read(path.join(w.stub, "secrets", "client-secret")), "old-pull-secret");
    assert.deepEqual(tokenItems(w), []);
    for (const account of Object.keys(OLD_SECRETS))
        assert.equal(fs.existsSync(path.join(w.stub, "secrets", account)), false, account);
}

// The first run of the new runner over the previous version's files: the
// six old keyring accounts go, the client keys move to the one credential,
// no token is kept, so the status asks for Connect; the pair list, the
// pair's state and its inventory are rewritten in the new form.
function caseCredentialMigration(runner) {
    const w = world({ secrets: [] });
    plantOldSecrets(w);
    const pairsFile = path.join(w.env.XDG_CONFIG_HOME, "vgshell", "google-drive", "pairs.json");
    write(pairsFile, JSON.stringify({ pairs: [{ id: "docs", label: "Documents", direction: "pull", remote: "Docs", local: w.mirror }] }));
    const pairDir = path.join(w.state, "pairs", "docs");
    write(path.join(pairDir, "state.json"), JSON.stringify({
        state: "idle", startedAt: null, lastAttempt: null, lastSuccess: null, lastError: null, changes: null,
        localEdits: [{ path: "a.txt", stored: "20990101T000000Z-1/a.txt", at: "2099-01-01T00:00:00.000Z" }]
    }));
    write(path.join(pairDir, "conflicts", "20990101T000000Z-1", "a.txt"), "kept edit\n");
    write(path.join(pairDir, "inventory.json"), JSON.stringify({ entries: {
        "b.txt": { size: 1, mtimeMs: 1, hash: null, id: null, state: "removed-on-drive", since: "2099-01-01T00:00:00.000Z" }
    } }));
    const out = cli(w, ["run"], runner);
    assert.equal(out.stdout, "pair=docs result=authorization-required\n", out.stderr);
    assertMigratedSecrets(w);
    assert.deepEqual(JSON.parse(read(pairsFile)), { pairs: [{ id: "docs", label: "Documents", local: w.mirror, remote: "Docs" }] });
    const state = JSON.parse(read(path.join(pairDir, "state.json")));
    assert.equal(Object.prototype.hasOwnProperty.call(state, "localEdits"), false);
    assert.deepEqual(state.records.map(r => [r.kind, r.path]).sort(), [["both-changed", "a.txt"], ["removed-on-drive", "b.txt"]]);
    assert.equal(JSON.parse(read(path.join(pairDir, "inventory.json"))).entries["b.txt"].state, undefined);
    const s = status(w, runner);
    assert.equal(s.pairs[0].state, "authorization-required");
    assert.deepEqual([s.lastError.kind, s.lastError.account], ["credential-absent", "token"]);
    assert.ok(s.attention.reasons.includes("authorization-required"));
}

// The shell probes at start, so the probe migrates too.
function caseCredentialMigrationProbe(runner) {
    const w = world({ secrets: [] });
    plantOldSecrets(w);
    const probe = cli(w, ["probe"], runner);
    assert.equal(probe.status, 0, probe.stderr);
    assertMigratedSecrets(w);
    const rows = JSON.parse(probe.stdout).credentials.map(c => [c.account, c.presence]);
    assert.deepEqual(rows, [["client-id", "present"], ["client-secret", "present"], ["token", "absent"]]);
}

// A pair never synced whose Drive folder does not exist yet: the upload
// leg creates it.
function caseMissingRemoteFirstSync(runner) {
    const w = world();
    addPair(w, runner);
    write(path.join(w.mirror, "first.txt"), "first\n");
    const out = cli(w, ["run"], runner);
    assert.equal(out.stdout, "pair=docs result=idle\n", out.stderr);
    assert.equal(read(path.join(w.drive, "Docs", "first.txt")), "first\n");
}

// A synced pair whose Drive folder went away is an error, not a re-upload.
function caseMissingRemoteWithBaseline(runner) {
    const w = world();
    addPair(w, runner);
    drive(w, "a.txt", "one\n", 1700000000);
    runOk(w, runner);
    fs.rmSync(path.join(w.drive, "Docs"), { recursive: true, force: true });
    const out = cli(w, ["run"], runner);
    assert.equal(out.stdout, "pair=docs result=error\n", out.stderr);
    assert.equal(status(w, runner).lastError.kind, "source-missing");
    assert.equal(fs.existsSync(path.join(w.drive, "Docs")), false);
}

// ----------------------------------------------------------- the controls

// A copy of the runner with FROM replaced by TO, COUNT times.
function mutant(name, from, to, count) {
    const text = read(RUNNER);
    const found = text.split(from).length - 1;
    assert.equal(found, count === undefined ? 1 : count, "control " + name + " matches " + found + " times");
    const dir = fs.mkdtempSync(path.join(scratch, "control-"));
    const file = path.join(dir, "google-drive");
    fs.writeFileSync(file, text.split(from).join(to), { mode: 0o755 });
    assert.notEqual(read(file), text);
    return file;
}

async function mustFail(name, runner, fn) {
    let failedWith = null;
    try {
        await fn(runner);
    } catch (e) {
        failedWith = e;
    }
    assert.ok(failedWith !== null, "control " + name + ": the case passed against the broken runner");
}

async function controls() {
    await mustFail("copy", mutant("copy", "[\"copy\", \"--update\", remotePath(pair), pair.local,", "[\"copy\", \"--dry-run\", remotePath(pair), pair.local,"), caseCopy);
    await mustFail("upload copy", mutant("upload copy", "[\"copy\", \"--update\", pair.local, remotePath(pair)]", "[\"copy\", \"--dry-run\", pair.local, remotePath(pair)]"), caseLocalAdd);
    await mustFail("removed-locally", mutant("removed-locally", "addRecord(records, { kind: \"removed-locally\", path: rel });", ""), caseRemovedLocally);
    await mustFail("removed-on-drive", mutant("removed-on-drive", "addRecord(records, { kind: to === null ? \"removed-on-drive\" : \"renamed\", path: rel, to: to });", ""), caseRemovedOnDriveReturns);
    await mustFail("local-newer both-changed", mutant("local-newer both-changed", "if (local.mtimeMs > driveTime) addRecord(records, { kind: \"both-changed\", path: rel });", ""), caseBothChangedLocalNewer);
    await mustFail("both-changed gone from both sides", mutant("both-changed gone from both sides", "\n            || record.kind === \"both-changed\" && typeof record.stored !== \"string\")", ")"), caseBothChangedGoneBothSides);
    await mustFail("export no upload", mutant("export no upload", "if (excludes !== null) uploadArgs.push(\"--exclude-from\", excludes);", ""), caseExportNoUpload);
    await mustFail("prune conflict storage", mutant("prune conflict storage", "const cutoff = Date.now() - KEEP_MS;", "const cutoff = 0;"), casePruneConflictStorage);
    await mustFail("credential migration", mutant("credential migration", "migrateCredentialsIfNeeded();\n    const read = readPairs();", "const read = readPairs();"), caseCredentialMigration);
    await mustFail("credential migration in probe", mutant("credential migration in probe", "migrateCredentialsIfNeeded();\n    const tool = which(\"secret-tool\");\n    const needed", "const tool = which(\"secret-tool\");\n    const needed"), caseCredentialMigrationProbe);
    await mustFail("pair list migration", mutant("pair list migration", "if (read.kind !== \"ok\" || !oldPairList(read.value)) return;", "return;"), caseCredentialMigration);
    await mustFail("missing remote keeps the error", mutant("missing remote keeps the error", "(listed.kind !== \"source-missing\" || hasBaseline)", "listed.kind !== \"source-missing\""), caseMissingRemoteWithBaseline);
    await mustFail("missing remote creates", mutant("missing remote creates", "const emptyRemote = !listed.ok && listed.kind === \"source-missing\";", "const emptyRemote = false;"), caseMissingRemoteFirstSync);
    await mustFail("edit during the legs", mutant("edit during the legs", "const baseline = { size: item.Size, mtimeMs: modTime, hash: md5, id: item.ID || null, export: exportItem || undefined };", "const baseline = item.Size === st.size && modTime === Math.floor(st.mtimeMs) || exportItem ? { size: item.Size, mtimeMs: modTime, hash: md5, id: item.ID || null, export: exportItem || undefined } : old;\n        if (baseline === undefined) continue;"), caseEditDuringCopy);
    await mustFail("export exclusion", mutant("export exclusion", "if (excludes !== null) uploadArgs.push(\"--exclude-from\", excludes);", ""), caseExportNoUpload);
    await mustFail("export filter escape", mutant("export filter escape", "return \"/\" + rel.replace(/[\\\\*?\\[\\]{}]/g, \"\\\\$&\");", "return \"/\" + rel;"), caseExportNoUpload);
    await mustFail("export kept after rename", mutant("export kept after rename", "        entries[rel] = before[rel];\n", ""), caseExportRenamedOnDrive);
    await mustFail("baseline after download", mutant("baseline after download", "writeJson(path.join(pairDir(pair.id), \"inventory.json\"), { entries: nextInventory(pair, listing, inventory, held).entries });", ""), caseFailedUploadKeepsBaseline);
    await mustFail("record per stored copy", mutant("record per stored copy", "return record.kind + \"\\n\" + record.path + \"\\n\" + (record.stored || \"\");", "return record.kind + \"\\n\" + record.path;"), caseRepeatedConflict);
    await mustFail("same path no baseline", mutant("same path no baseline", "if (differs) addRecord(records, { kind: \"both-changed\", path: item.Path });", ""), caseSamePathNoBaseline);
    await mustFail("pair list migration never refuses", mutant("pair list migration never refuses", "        writeJson(pairsFile, { pairs: pairs });\n        log(\"migration=pairs", "        if (pairsError(pairs) !== null) refuse(pairsError(pairs));\n        writeJson(pairsFile, { pairs: pairs });\n        log(\"migration=pairs"), casePairListMigrationRefused);
    await mustFail("migrated copies kept", mutant("migrated copies kept", "const renamed = slash === -1 ? edit.stored : migratedStamp + edit.stored.slice(slash);", "const renamed = edit.stored;"), caseStateMigrationKeepsCopies);
    await mustFail("one old client", mutant("one old client", "const source = pull.every(row => row[1].kind === \"found\") ? pull : upload.every(row => row[1].kind === \"found\") ? upload : null;", "const source = pull.every(row => row[1].kind === \"found\") ? pull : upload;"), caseCredentialMigrationMixed);
    await mustFail("clear only when complete", mutant("clear only when complete", "log(\"migration=held reason=credential-incomplete\");\n        return;", "log(\"migration=held reason=credential-incomplete\");"), caseCredentialMigrationMixed);
    await mustFail("rename", mutant("rename", "const renamed = migrateRenameIfNeeded();", "const renamed = false;"), caseRenameMigration);
    await mustFail("rename holds while the previous service syncs", mutant("rename holds while the previous service syncs", "if (busy !== null) holdRename(\"reason=old-service-\" + busy);", ""), r => caseRenameMigration(r, "previous service syncing"));
    await mustFail("rename keeps the timer of a sync it raced", mutant("rename keeps the timer of a sync it raced", "const restored = systemctlFailure([\"enable\", \"--now\", OLD_TIMER]);", "const restored = null;"), r => caseRenameMigration(r, "previous timer starts a sync as it is disabled"));
    await mustFail("rename held exit", mutant("rename held exit", "    process.exit(EXIT_BUSY);\n}", "    process.exit(1);\n}"), r => caseRenameMigration(r, "previous service syncing"));
    await mustFail("rename held account reads held", mutant("rename held account reads held", "function renameHeldPresence(account) {\n", "function renameHeldPresence(account) {\n    return null;\n"), r => caseRenameMigration(r, "keyring locked"));
    await mustFail("rename pending before the first move", mutant("rename pending before the first move", "if (!exists(RENAME_PENDING)) writeJson(RENAME_PENDING, { held: {} });", ""), caseRenameConcurrent);
    await mustFail("rename keeps the account", mutant("rename keeps the account", "old.user === null ? [] : [\"user\", old.user]", "[]"), r => caseRenameMigration(r, "previous service idle"));
    await mustFail("rename keeps the previous setup log", mutant("rename keeps the previous setup log", "if (path.basename(to) === \"setup.log\")", "if (false)"), r => caseRenameMigration(r, "previous service idle"));
    await mustFail("rename installs the units", mutant("rename installs the units", "const installed = writeInstall(false, scheduling);", "const installed = { changed: 0, failure: null };"), r => caseRenameMigration(r, "previous service idle"));
    await mustFail("disabled rename never enables timers", mutant("disabled rename never enables timers", 'if (scheduling === "enabled" && failure === null', 'if (failure === null'), r => caseDisabledMigration(r, "disabled"));
    await mustFail("disabled rename suppresses installed stop-post", mutant("disabled rename suppresses installed stop-post", 'const DISABLED_STOP_POST = "[Service]\\nExecStopPost=\\n";', 'const DISABLED_STOP_POST = "[Service]\\n# ExecStopPost=\\n";'), r => caseDisabledMigration(r, "partial new install"));
    await mustFail("disabled failed stop clears overrides", mutant("disabled failed stop clears overrides", '    } finally {\n        clearDisabledStopPost("disabled");\n    }', '    } finally {\n        if (failures.length === 0) clearDisabledStopPost("disabled");\n    }'), r => caseDisabledMigration(r, "stop-fail"));
    await mustFail("rename resumes a held keyring", mutant("rename resumes a held keyring", "writeJson(RENAME_PENDING, { held: keyring.held });", "fs.rmSync(RENAME_PENDING, { force: true });"), r => caseRenameMigration(r, "keyring locked"));
    await mustFail("stale units refresh", mutant("stale units refresh", "if (verb !== \"install\") refreshStaleInstallIfNeeded();", ""), caseStaleUnitsRefresh);
    await mustFail("stale refresh never refuses", mutant("stale refresh never refuses", "if (done.failure !== null) log(\"units=stale refresh=failed \" + done.failure);", "if (done.failure !== null) refuse(done.failure);"), caseStaleUnitsRefresh);
    await mustFail("forbidden argv", mutant("forbidden argv", "const uploadArgs = [\"copy\", \"--update\", pair.local, remotePath(pair)].concat(filterArgs());", "const uploadArgs = [\"copy\", \"--update\", pair.local, remotePath(pair), \"--delete-after\"].concat(filterArgs());"), caseForbiddenRcloneArgv);
    await mustFail("attention key", mutant("attention key", "needing.map(c => [c.kind, c.pair, c.path, c.since]), cause])", "needing.map(c => [c.kind, c.pair, c.path, c.since]), lastError])"), caseFailures);
    await mustFail("orphaned copy lock", mutant("orphaned copy lock", "stdio: [\"ignore\", \"pipe\", \"pipe\", lock] });", "stdio: [\"ignore\", \"pipe\", \"pipe\"] });"), caseInterrupted);
    await mustFail("both-changed", mutant("both-changed", "const unedited = base !== undefined", "const unedited = true || base !== undefined"), caseBothChangedKept);
    await mustFail("lock", mutant("lock", "if (out.status === 0) return fd;", "if (out.status === 0 || true) return fd;"), caseBusy);
    await mustFail("pause", mutant("pause", "if (isPaused(control, pair.id)) return \"paused\";", ""), casePause);
    await mustFail("exclusions", mutant("exclusions", "return [].concat(...EXCLUDES.map(pattern => [\"--exclude\", pattern]));", "return [];"), caseExclusions);
    await mustFail("renamed", mutant("renamed", "if (item.ID) pathOfId[item.ID] = item.Path;", ""), caseRemovedAndRenamed);
    await mustFail("file errors alone end synced", mutant("file errors alone end synced", "if (review === null) return rcloneFailed(state, downloaded);", "if (!downloaded.ok) return rcloneFailed(state, downloaded);"), caseUnreadableOnDrive);
    await mustFail("one record per file", mutant("one record per file", "if (error !== null) reasons.set(error[1], error[2]);", "if (error !== null) reasons.set(error[1] + reasons.size, error[2]);"), caseUnreadableOnDrive);
    await mustFail("the last attempt counts", mutant("the last attempt counts", "ends.length > 1 ? ends[ends.length - 2] + 1 : 0, last)", "0, last)"), caseUnreadableOnDrive);
    await mustFail("drive records cleared", mutant("drive records cleared", "const kept = records.filter(r => DRIVE_KINDS.indexOf(r.kind) === -1);", "const kept = records.slice();"), caseUnreadableClears);
    await mustFail("a standing record keeps its time", mutant("a standing record keeps its time", "old === undefined ? record : Object.assign({}, record, { since: old.since })", "record"), caseUnreadableClears);
    await mustFail("a network cause stays a failure", mutant("a network cause stays a failure", "if (result.kind !== \"rclone-failed\" || result.exit === 7) return null;", "if (result.exit === 7) return null;"), r => caseDownloadFailures(r, "network cause"));
    await mustFail("every counted error names a file", mutant("every counted error names a file", "if (reasons.size !== Number(ATTEMPT_END.exec(lines[last])[1])) return null;", "if (false) return null;"), r => caseDownloadFailures(r, "error naming no file"));
    await mustFail("a fatal exit stays a failure", mutant("a fatal exit stays a failure", "if (result.kind !== \"rclone-failed\" || result.exit === 7) return null;", "if (result.kind !== \"rclone-failed\") return null;"), r => caseDownloadFailures(r, "fatal exit"));
    await mustFail("a clean download records a doubled name", mutant("a clean download records a doubled name", "if (result.ok) return found;", "if (result.ok) return { unreadable: [], doubled: [] };"), caseDuplicateOnCleanRun);
    await mustFail("the not-owned flag", mutant("the not-owned flag", "if (typeof record.mine === \"boolean\") kept.mine = record.mine;", ""), r => caseDuplicateRecords(r, "different copies another account owns"));
    await mustFail("mine needs the account's own copy", mutant("mine needs the account's own copy", "const mine = address !== null && owners.some(o => o !== null && o.toLowerCase() === address.toLowerCase());", "const mine = owners.some(o => o !== null);"), r => caseDuplicateRecords(r, "different copies another account owns"));
    await mustFail("mine needs a known account", mutant("mine needs a known account", "const mine = address !== null && owners.some(", "const mine = address === null || owners.some("), r => caseDuplicateRecords(r, "the token names no account"));
    await mustFail("identical needs an md5", mutant("identical needs an md5", "md5s.every(m => m !== null && /^[0-9a-f]{32}$/.test(m) && m === md5s[0])", "md5s.every(m => m === md5s[0])"), r => caseDuplicateRecords(r, "Google-native documents"));
    await mustFail("identical needs one size", mutant("identical needs one size", " && copies.every(c => c.Size === copies[0].Size);", ";"), r => caseDuplicateRecords(r, "same md5, another size"));
    await mustFail("folder listing only for a doubled name", mutant("folder listing only for a doubled name", "const folders = new Map();", "const folders = new Map([[\"\", []]]);"), caseDuplicateListing);
    await mustFail("a dangling shortcut needs nothing", mutant("a dangling shortcut needs nothing", "return DANGLING.test(record.reason) ? \"nothing\" : \"you\";", "return \"you\";"), caseNeedsAttention);
    await mustFail("only needs-you rows ask for attention", mutant("only needs-you rows ask for attention", "if (needing.length > 0) reasons.push(\"conflicts\");", "if (conflicts.length > 0) reasons.push(\"conflicts\");"), caseNeedsAttention);
    await mustFail("the key hashes needs-you rows", mutant("the key hashes needs-you rows", "needing.map(c => [c.kind, c.pair, c.path, c.since]), cause])", "conflicts.map(c => [c.kind, c.pair, c.path, c.since]), cause])"), caseNeedsAttention);
    await mustFail("the earlier doubled-name kind is dropped", mutant("the earlier doubled-name kind is dropped", "    if (oldDuplicates(state)) {", "    if (false) {"), r => caseDuplicateMigration(r, "not notified"));
    await mustFail("a notified record stays notified", mutant("a notified record stays notified", "&& after.reasons.every(r => earlier.reasons.indexOf(r) !== -1))", "&& false)"), r => caseDuplicateMigration(r, "notified"));
    await mustFail("a failed download keeps the baseline", mutant("a failed download keeps the baseline", "if (held.has(item.Path)) {", "if (false) {"), caseUnreadableKeepsBaseline);
    await mustFail("no download clears the drive records", mutant("no download clears the drive records", "state.records = withDriveRecords(state.records, []);", "void 0;"), caseUnreadableDriveFolderGone);
    await mustFail("drive records outlive the age cut", mutant("drive records outlive the age cut", "if (DRIVE_KINDS.indexOf(r.kind) === -1 && Date.parse(r.since) < cutoff) return false;", "if (Date.parse(r.since) < cutoff) return false;"), caseUnreadableClears);
    await mustFail("no copy here names no folder", mutant("no copy here names no folder", "if (r.kind !== \"unreadable-on-drive\" || fs.existsSync(localPath)) out.localPath = localPath;", "out.localPath = localPath;"), caseUnreadableOnDrive);
    await mustFail("failure table", mutant("failure table", "const row = FAILURES.find(r => r.pattern.test(stderr));", "const row = undefined;"), caseFailures);
    await mustFail("authorize store", mutant("authorize store", "{ input: value, encoding", "{ input: value + \"\\n\", encoding"), caseAuthorize);
    await mustFail("authorize scope", mutant("authorize scope", "RCLONE_DRIVE_SCOPE: DRIVE_SCOPE", "RCLONE_DRIVE_SCOPE: \"drive.file\""), caseAuthorize);
    await mustFail("full drive shared folder", mutant("full drive shared folder", "const DRIVE_SCOPE = \"drive\";", "const DRIVE_SCOPE = \"drive.file\";"), caseFullDriveSharedFolder);
    await mustFail("token off curl's argv", mutant("token off curl's argv", "\"--header\", \"@-\", ABOUT_URL]", "\"--header\", \"Authorization: Bearer \" + access, ABOUT_URL]"), caseAuthorize);
    await mustFail("user attribute", mutant("user attribute", ", read.kind === \"read\" ? [\"user\", read.address] : []);", ", []);"), caseAuthorize);
    await mustFail("one token item", mutant("one token item", "clearAccount(tool, account);\n    const stored", "const stored"), caseAuthorize);
    await mustFail("unread logged", mutant("unread logged", "if (read.kind === \"unread\") log(\"account=unread reason=\" + read.reason);", ""), caseAuthorize);
    await mustFail("address judge", mutant("address judge", "function validAddress(value) {\n    return ", "function validAddress(value) {\n    return typeof value === \"string\" || "), caseAuthorize);
    await mustFail("probe user", mutant("probe user", "if (part === \"token\" && probed.user !== null) row.user = probed.user;", ""), caseProbe);
    await mustFail("sign-out clears", mutant("sign-out clears", "clearAccount(tool, account);\n    const left", "const left"), caseSignOut);
    await mustFail("sign-out locked", mutant("sign-out locked", "if (left === \"locked\") refuse(\"credential=locked account=\" + account);", ""), caseSignOut);
    await mustFail("notified", mutant("notified", "notified: control.notifiedKey === key", "notified: false"), caseAttention);
    await mustFail("attention-seen writes", mutant("attention-seen writes", "writeJson(controlFile, Object.assign(readControl(), { notifiedKey: words[0] }));", ""), caseAttention);
    await mustFail("nothing to clear", mutant("nothing to clear", "if (out.status === 1 && out.stderr === \"\") return;", ""), caseAuthorize);
    await mustFail("running pair stands", mutant("running pair stands", "p.state === \"running\" && p.lastError !== null ? failureState(p.lastError.kind) : p.state", "p.state"), caseRunKey);
    await mustFail("cause by pair id", mutant("cause by pair id", ".sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);", ".sort((a, b) => String(b.lastError.at).localeCompare(String(a.lastError.at))).slice(0, 1);"), caseRunKey);
    await mustFail("re-arm", mutant("re-arm", "if (control.notifiedKey !== null) writeJson(controlFile, Object.assign(control, { notifiedKey: null }));", ""), caseAttention);
    await mustFail("sign-out notified", mutant("sign-out notified", "if (after !== null && (before === null || before.notified)) writeJson(", "if (false) writeJson("), caseSignOut);
    await mustFail("sign-in resets", mutant("sign-in resets", "if (state.state === \"authorization-required\") writePairState(", "if (false) writePairState("), caseSignOut);
    await mustFail("pause keeps notified", mutant("pause keeps notified", "paused ? control.pausedPairs : [], notifiedKey: control.notifiedKey }", "paused ? control.pausedPairs : [] }"), caseAttention);
    await mustFail("child environment", mutant("child environment", "const env = { LANG: \"C.UTF-8\" };", "const env = Object.assign({ LANG: \"C.UTF-8\" }, process.env);"), caseCopy);
    await mustFail("secret attributes", mutant("secret attributes", "return verb.concat([\"service\", service, \"account\", account], extra);", "return verb.concat([\"service\", service, \"user\", account], extra);"), caseAuthorize);
    await mustFail("unit backslash", mutant("unit backslash", ".replace(/\\\\/g, \"\\\\\\\\\")", ""), caseUnitWords);
    await mustFail("unit quote", mutant("unit quote", ".replace(/\"/g, \"\\\\\\\"\")", ""), caseUnitWords);
    await mustFail("unit dollar in ExecStart", mutant("unit dollar in ExecStart", "quoted.replace(/\\$/g, \"$$$$\")", "quoted"), caseUnitWords);
    await mustFail("unit dollar in Environment", mutant("unit dollar in Environment", "directive === \"Environment\" ? quoted : ", ""), caseUnitWords);
    await mustFail("unit percent", mutant("unit percent", ".replace(/%/g, \"%%\")", ""), caseUnitWords);
    await mustFail("unit control character", mutant("unit control character", "if (CONTROL.test(s)) refuse(\"unit-argument=control-character\");", ""), caseUnitWords);
    await mustFail("pairs-reset keeps the damaged file", mutant("pairs-reset keeps the damaged file", "fs.renameSync(pairsFile, kept);\n        fs.renameSync(temp, pairsFile);", "fs.renameSync(temp, pairsFile);"), casePairsReset);
    await mustFail("pairs-reset refuses a valid list", mutant("pairs-reset refuses a valid list", "if (read.error === null) refuse(\"pairs=valid\");", "if (false) refuse(\"pairs=valid\");"), casePairsReset);
    const rules = [...new Set(validationRows(world()).map(row => row.rule).filter(rule => rule !== null))];
    for (const rule of rules) {
        const text = read(RUNNER);
        const target = ["duplicate-id", "local-overlap", "remote-overlap"].indexOf(rule) !== -1 ? "return refusal(a, \"" + rule + "\")" : "return refusal(pair, \"" + rule + "\")";
        await mustFail("rule " + rule, mutant("rule " + rule, target, "(0)", text.split(target).length - 1 || 1), r => caseValidation(r, rule));
    }
}

async function main() {
    caseCopy();
    caseLocalAdd();
    caseRemovedLocally();
    caseRemovedOnDriveReturns();
    caseBothChangedLocalNewer();
    caseBothChangedGoneBothSides();
    caseExportNoUpload();
    casePruneConflictStorage();
    caseForbiddenRcloneArgv();
    caseBothChangedKept();
    caseEditDuringCopy();
    caseRemovedAndRenamed();
    await caseBusy();
    await caseInterrupted();
    casePause();
    caseFailures();
    caseExclusions();
    caseValidation();
    caseInstall();
    caseUnitWords();
    caseProbe();
    caseAuthorize();
    caseSignOut();
    casePairsReset();
    caseAttention();
    caseRunKey();
    caseNoLeak();
    caseFullDriveSharedFolder();
    caseCredentialMigration();
    caseCredentialMigrationProbe();
    caseCredentialMigrationMixed();
    caseExportRenamedOnDrive();
    caseFailedUploadKeepsBaseline();
    caseRepeatedConflict();
    caseUnreadableOnDrive();
    caseUnreadableClears();
    caseDownloadFailures();
    caseDuplicateOnCleanRun();
    caseDuplicateRecords();
    caseDuplicateListing();
    caseNeedsAttention();
    caseDuplicateMigration();
    caseUnreadableKeepsBaseline();
    caseUnreadableDriveFolderGone();
    caseSamePathNoBaseline();
    casePairListMigrationRefused();
    caseStateMigrationKeepsCopies();
    caseStaleUnitsRefresh();
    caseRenameMigration();
    caseDisabledMigration();
    await caseRenameConcurrent();
    caseMissingRemoteFirstSync();
    caseMissingRemoteWithBaseline();
    assertNoDeletingArgvAnywhere();
    await controls();
    console.log("test-google-drive-runner: ok");
}

main().catch(e => {
    console.error(e);
    process.exit(1);
});
