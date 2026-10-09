#!/usr/bin/env node
// Table-driven checks for vgs.updates pure decisions: probe normalization,
// snapshot judging, status values, cadence, staleness, TUI end detection, the
// review's agent and verdict, the install script change, the packages that
// need a reboot by the distribution's reboot hook, the reboot notice's
// status, and what the bar widget and the window draw from the published
// values.
// Controls edit a copy of the logic and require this suite to fail.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.updates", "UpdatesLogic.js");
const scratch = path.join(__dirname, "..", "tmp", "test-updates-logic-" + process.pid);
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message || "");

// The [Trigger] of CachyOS's reboot hook,
// /usr/share/libalpm/hooks/cachyos-reboot-required.hook of cachyos-hooks.
const REBOOT_HOOK = `[Trigger]
Operation = Upgrade
Type = Package
Target = amd-ucode
Target = intel-ucode
Target = btrfs-progs
Target = e2fsprogs
Target = xfsprogs
Target = cryptsetup
Target = linux
Target = linux-hardened
Target = linux-lts
Target = linux-zen
Target = linux-firmware
Target = linux-cachyos*
Target = linux-cacule*
Target = nvidia
Target = nvidia-dkms
Target = nvidia-*xx-dkms
Target = nvidia-*xx
Target = nvidia-*lts-dkms
Target = nvidia*-lts
Target = mesa
Target = systemd*
Target = wayland
Target = egl-wayland
Target = xf86-video-*
Target = xorg-server*
Target = xorg-fonts*
Target = mkinitcpio*
Target = booster*
Target = dracut*
Target = winesync-dkms
`;

function probe(value, status = 0, stderr = "") {
  return { status, stdout: typeof value === "string" ? value : JSON.stringify(value), stderr };
}

// The 1password install script at AUR commit e4388fb, 8.12.38, which
// d0a8a7e, 8.12.40, ships unchanged. It sets a setgid bit and adds a group.
const ONEPASSWORD_INSTALL = `# Do not add your user, or any others, to this group.
GROUP_NAME="onepassword"

app_group_exists() {
    if [ $(getent group "\${GROUP_NAME}") ]; then
        true
    else
        false
    fi
}

setup_browser_helper() {
    # Setup the Core App Integration helper binary with the correct permissions and group
    BROWSER_SUPPORT_PATH="/opt/1Password/1Password-BrowserSupport"

    chgrp "\${GROUP_NAME}" $BROWSER_SUPPORT_PATH
    chmod g+s $BROWSER_SUPPORT_PATH
}

pre_install() {
    if app_group_exists; then
        : # Do nothing
    else
        groupadd "\${GROUP_NAME}"
    fi
}

pre_upgrade() {
    if app_group_exists; then
        : # Do nothing
    else
        groupadd "\${GROUP_NAME}"
    fi
}

post_install() {
    setup_browser_helper
}

post_upgrade() {
    setup_browser_helper
}

post_remove() {
    if app_group_exists; then
        groupdel "\${GROUP_NAME}"
    fi
}
`;

function verify(logic) {
    // Producer diagnostics never cross the display boundary.
    for (const diagnostic of ["spawn=failed", "unparseable pkg", "timeout=120", "fetch=failed", "helper-missing=checkupdates", "unexpected: key=value"]) {
        const text = logic.errorText(diagnostic);
        assert.ok(text.length > 0, "a failed operation must tell the user");
        assert.doesNotMatch(text, /[a-z][a-z-]*=|start-failed|output-unreadable/, "diagnostic fields stay in logs");
    }

  const now = 1000000;
  const snapshot = logic.normalizeSnapshot({
    pkg: probe([
      { source: "pacman", count: 2, packages: [{ name: "linux", old: "1", new: "2" }], checkedAt: now - 10, error: null },
      { source: "aur", count: 1, packages: [{ name: "tool", old: "3", new: "4" }], checkedAt: now - 9, error: null },
      { source: "flatpak", count: 0, packages: [], checkedAt: now - 8, error: null },
      { source: "mise", count: null, packages: [], checkedAt: null, error: "skipped=no-check" }
    ]),
    self: probe({ version: "0.1.0", method: "checkout", package: null, current: "0.1.0.r1.g1111111", latest: "0.1.0.r2.g2222222", behind: true, error: null }),
    plugins: probe([{ id: "acme.one", behind: 2, head: "a", upstream: "b", error: null }]),
    themes: probe([{ id: "moss", behind: 0, head: "c", upstream: "c", error: null }])
  }, now);
  assert.equal(snapshot.checkedAt, now);
  same(snapshot.sources.map(s => [s.source, s.count, s.label]), [["pacman", 2, "System"], ["aur", 1, "AUR"], ["flatpak", 0, "Flatpak"], ["mise", null, "mise"], ["vgs", 1, "VGS"], ["plugins", 1, "Plugins"], ["themes", 0, "Themes"]]);
  same(snapshot.sources[4].packages, [{ name: "vgs", old: "0.1.0.r1.g1111111", new: "0.1.0.r2.g2222222" }]);
  assert.equal(logic.pendingCount(snapshot), 5);
  same(logic.checkState(snapshot, false, now, 6 * 60 * 60 * 1000, ""), { tone: "warning", text: "mise: The update check failed. Select Refresh to try again." });
  const clean = JSON.parse(JSON.stringify(snapshot));
  clean.sources[3].error = null;
  clean.sources[3].count = 0;
  same(logic.checkState(clean, false, now, 6 * 60 * 60 * 1000, ""), { tone: "ok", text: "Updates waiting" });
  clean.sources.forEach(s => { s.count = 0; });
  same(logic.checkState(clean, false, now, 6 * 60 * 60 * 1000, ""), { tone: "ok", text: "Up to date" });
  same(logic.checkState(clean, true, now, 6, ""), { tone: "info", text: "Checking" });
  clean.checkedAt = now - 13;
  same(logic.checkState(clean, false, now, 6, ""), { tone: "warning", text: "The last check is old. Select Refresh to check again." });
  clean.error = "exit=1";
  same(logic.checkState(clean, false, now, 6, ""), { tone: "danger", text: "The update check failed. Select Refresh to try again." });
  same(logic.publishValues(snapshot, false, now, 6 * 60 * 60 * 1000, "").pending, 5);
  assert.equal(logic.publishValues(snapshot, false, now, 6, "").lastCheck, now);
  assert.equal(logic.nextCheckDelay(null, false, now, 6, null, null), 0);
  assert.equal(logic.nextCheckDelay({ checkedAt: now - 2, sources: [], error: null }, false, now, 6, null, null), 4);
  assert.equal(logic.nextCheckDelay({ checkedAt: now - 7, sources: [], error: null }, false, now, 6, null, null), 0);
  assert.equal(logic.parseBootTime("cpu  1 2 3\nbtime 12345\nintr 9\n"), 12345000);
  assert.equal(logic.parseBootTime("cpu  1 2 3\n"), null);
  assert.equal(logic.parseBootTime("btime nope\n"), null);
  assert.equal(logic.nextCheckDelay({ checkedAt: now - 2, sources: [], error: null, cached: true }, false, now, 6, null, now - 1), 0);
  assert.equal(logic.shouldRunCheck({ checkedAt: now - 2, sources: [], error: null, cached: true }, false, now, 6, null, now - 1), true);
  assert.equal(logic.nextTimerDelay({ checkedAt: now - 2, sources: [], error: null, cached: true }, false, now, 6, null, true, true, now - 1), 0);
  assert.equal(logic.nextCheckDelay({ checkedAt: now - 2, sources: [], error: null, cached: true }, false, now, 6, null, now - 3), 4);
  assert.equal(logic.shouldRunCheck({ checkedAt: now - 2, sources: [], error: null, cached: true }, false, now, 6, null, now - 3), false);
  // The wall clock stepped back past the boot time read at start: a check
  // run's snapshot is stamped before it, and is still due one interval on.
  const hours = 6 * 60 * 60 * 1000;
  const stepped = { checkedAt: now - 60000, sources: [], error: null, cached: false };
  assert.equal(logic.nextCheckDelay(stepped, false, now - 59990, hours, null, now), hours - 10);
  assert.equal(logic.nextTimerDelay(stepped, false, now - 59990, hours, null, true, true, now), hours - 10);
  assert.equal(logic.shouldRunCheck(stepped, false, now - 59990, hours, null, now), false);
  assert.equal(logic.nextCheckDelay({ checkedAt: now - 2, sources: [], error: null }, false, now, 6, null, null), 4);
  assert.equal(logic.intervalMs({ intervalHours: 0 }), 3600000);
  assert.equal(logic.intervalMs({ intervalHours: 49 }), 48 * 3600000);
  same(snapshot.sources[5].packages, [{ name: "acme.one", old: "a", new: "b", behind: 2 }]);
  same(logic.checkState(clean, false, now, 6, "timeout=120"), { tone: "danger", text: "The update check took too long. Select Refresh to try again." });
  same(logic.statusWrites({}, { pending: 1, lastCheck: null, checkState: { tone: "ok", text: "Up to date" }, sources: [] }).map(w => w.key), ["pending", "checkState", "sources"]);
  same(logic.statusWrites({ pending: 1 }, { pending: 1, checkState: { tone: "ok", text: "Up to date" } }).map(w => w.key), ["checkState"]);
  assert.equal(logic.nextCheckDelay(snapshot, false, now + 1000, 99999999, now, null), logic.RETRY_AFTER_FAILURE_MS - 1000);
  assert.equal(logic.nextCheckDelay(snapshot, false, now + logic.RETRY_AFTER_FAILURE_MS, 6, now, null), 0);
  assert.equal(logic.nextTimerDelay({ checkedAt: now - 7, sources: [], error: null }, false, now, 6, null, true, true, null), 0);
  assert.equal(logic.nextTimerDelay(null, false, now, 6, null, true, true, null), 0);
  assert.equal(logic.nextTimerDelay(null, false, now, 6, null, false, true, null), null);
  assert.equal(logic.nextTimerDelay(null, false, now, 6, null, true, false, null), null);
  // The timer wakes when the snapshot turns stale, and not again while a
  // failure retry waits on a snapshot already stale.
  assert.equal(logic.nextTimerDelay({ checkedAt: now - 7, sources: [], error: null }, false, now, 6, now, true, true, null), 5);
  assert.equal(logic.nextTimerDelay({ checkedAt: now - 13, sources: [], error: null }, false, now, 6, now - 1000, true, true, null), logic.RETRY_AFTER_FAILURE_MS - 1000);
  const many = logic.normalizeSnapshot({
    pkg: probe([{ source: "pacman", count: 3000, packages: Array.from({ length: 3000 }, (_, i) => ({ name: "pkg-" + i + "-".repeat(120), old: "1".repeat(120), new: "2".repeat(120) })), checkedAt: now, error: null }]),
    self: probe({ behind: false, error: null }),
    plugins: probe([]),
    themes: probe([])
  }, now);
  const bounded = logic.publishValues(many, false, now, 6 * 60 * 60 * 1000, "");
  assert.equal(bounded.pending, 3000);
  assert.equal(bounded.sources[0].packages.length, logic.PUBLISHED_PACKAGES_PER_SOURCE_MAX);
  assert.equal(bounded.sources[0].more, 3000 - logic.PUBLISHED_PACKAGES_PER_SOURCE_MAX);
  assert.equal(bounded.sources[0].packages[0].name.length, logic.PUBLISHED_PACKAGE_TEXT_MAX);
  assert.equal(logic.statusRecordBytes(bounded) < logic.STATUS_MAX_BYTES, true);
  assert.equal(logic.statusRecordBytes(Object.assign({}, bounded, { sources: many.sources })) > logic.STATUS_MAX_BYTES, true);

  same(logic.parseSnapshotText(JSON.stringify(snapshot)), { ok: true, snapshot });
  same(logic.parseSnapshotText("{"), { ok: false, error: "not-json" });
  same(logic.snapshotFromObject({ checkedAt: now, sources: [{ source: "x", count: -1 }] }), { ok: false, error: "sources.0.count" });

  const failedPlugins = logic.normalizeSnapshot({ pkg: probe([]), self: probe({ behind: false, error: null }), plugins: probe([{ id: "bad", behind: null, head: null, upstream: null, error: "fetch=bad" }, { id: "good", behind: 3, head: "a", upstream: "b", error: null }]), themes: probe([]) }, now);
  const pluginRow = failedPlugins.sources.find(s => s.source === "plugins");
  same([pluginRow.count, pluginRow.error], [1, "bad: fetch=bad"]);
  same(logic.checkState(failedPlugins, false, now, 6 * 60 * 60 * 1000, ""), { tone: "warning", text: "Plugins: The update source could not be reached. Check your connection and select Refresh." });
  const untracked = logic.normalizeSnapshot({ pkg: probe([]), self: probe({ behind: false, error: null }), plugins: probe([{ id: "local", behind: null, head: null, upstream: null, error: "not-a-checkout=/home/u/.config/vgshell/plugins/local" }]), themes: probe([]) }, now);
  const untrackedRow = untracked.sources.find(s => s.source === "plugins");
  same([untrackedRow.count, untrackedRow.packages, untrackedRow.error], [0, [], null]);
  const noManager = logic.normalizeSnapshot({ pkg: probe([]), self: probe({ behind: false, error: null }), plugins: probe([]), themes: probe([]) }, now);
  same(noManager.sources.map(s => s.source), ["vgs", "plugins", "themes"]);
  const failedPkg = logic.normalizeSnapshot({ pkg: probe("", 1, "vgshell: refused: lock=failed"), self: probe({ behind: false, error: null }), plugins: probe([]), themes: probe([]) }, now);
  same(failedPkg.sources[0], { source: "packages", label: "Packages", count: null, packages: [], checkedAt: null, error: "exit=1 lock=failed" });

  assert.equal(logic.tuiRunEnded({}, {}), false);
  assert.equal(logic.tuiRunEnded(null, { update: { running: false, code: 0, endedAt: "2026-10-05T03:30:10.000Z" } }), false);
  assert.equal(logic.tuiRunEnded({}, { update: { running: false, code: 0, endedAt: "2026-10-05T03:30:10.000Z" } }), true);
  assert.equal(logic.tuiRunEnded({ update: { running: true, endedAt: null } }, { update: { running: false, code: 0, endedAt: "2026-10-05T03:30:11.000Z" } }), true);
  assert.equal(logic.tuiRunEnded({ update: { running: false, endedAt: "2026-10-05T03:30:12.000Z" } }, { update: { running: false, endedAt: "2026-10-05T03:30:12.000Z" } }), false);
  assert.equal(logic.tuiRunEnded({ update: { running: false, endedAt: "2026-10-05T03:30:12.000Z" } }, { update: { running: false, endedAt: "2026-10-05T03:30:12.027Z" } }), true);
  assert.equal(logic.tuiRunEnded({ update: { running: true, endedAt: "2026-10-05T03:30:12.000Z" } }, { update: { running: false, endedAt: "2026-10-05T03:30:12.000Z" } }), false);
  // The review runs inside an update run, whose own end checks.
  assert.equal(logic.tuiRunEnded({ review: { running: true, endedAt: null } }, { review: { running: false, code: 0, endedAt: "2026-10-05T03:30:13.000Z" } }), false);

  same([logic.publishValues(snapshot, true, now, 6, "").checking, logic.publishValues(snapshot, false, now, 6, "").checking], [true, false]);
  same(logic.statusWrites({ checking: true }, { checking: false }), [{ key: "checking", value: false }]);
  verifyView(logic);
}

// The widget and the window, from published values as the service writes
// them. Each row: [name, values, hideWhenCurrent, the widget's view].
function verifyView(logic) {
  const ok = { tone: "ok", text: "Up to date" };
  const widgetRows = [
    ["current", { pending: 0, checkState: ok, checking: false }, false, { state: "current", icon: "refresh-cw", tone: "calm", spinning: false, badge: "", badgeTone: "neutral", hidden: false }],
    ["current hidden", { pending: 0, checkState: ok, checking: false }, true, { state: "current", icon: "refresh-cw", tone: "calm", spinning: false, badge: "", badgeTone: "neutral", hidden: true }],
    ["pending", { pending: 7, checkState: { tone: "ok", text: "Updates waiting" }, checking: false }, true, { state: "pending", icon: "refresh-cw", tone: "accent", spinning: false, badge: "7", badgeTone: "accent", hidden: false }],
    ["pending past the badge", { pending: 150, checkState: { tone: "ok", text: "Updates waiting" } }, false, { state: "pending", icon: "refresh-cw", tone: "accent", spinning: false, badge: "99+", badgeTone: "accent", hidden: false }],
    ["failed source", { pending: 3, checkState: { tone: "warning", text: "AUR: exit=1 network down" }, checking: false }, true, { state: "attention", icon: "triangle-alert", tone: "warning", spinning: false, badge: "3", badgeTone: "warning", hidden: false }],
    ["failed check", { pending: 0, checkState: { tone: "danger", text: "exit=2 lock" }, checking: false }, true, { state: "attention", icon: "triangle-alert", tone: "warning", spinning: false, badge: "", badgeTone: "warning", hidden: false }],
    ["stale", { pending: 0, checkState: { tone: "warning", text: "Check stale" }, checking: false }, true, { state: "attention", icon: "triangle-alert", tone: "warning", spinning: false, badge: "", badgeTone: "warning", hidden: false }],
    ["checking", { pending: 2, checkState: { tone: "info", text: "Checking" }, checking: true }, true, { state: "checking", icon: "refresh-cw", tone: "calm", spinning: true, badge: "2", badgeTone: "accent", hidden: false }],
    ["not checked", { checkState: { tone: "info", text: "Not checked" }, checking: false }, true, { state: "unchecked", icon: "circle-dashed", tone: "calm", spinning: false, badge: "", badgeTone: "neutral", hidden: false }],
    ["nothing published", {}, true, { state: "unchecked", icon: "circle-dashed", tone: "calm", spinning: false, badge: "", badgeTone: "neutral", hidden: false }]
  ];
  for (const [name, values, hide, want] of widgetRows) same(logic.widgetView(values, hide), want, "widget " + name);
  assert.throws(() => logic.widgetView({ checkState: { tone: "loud", text: "x" } }, false), /checkState tone "loud"/);

  const summaryRows = [
    [{ pending: 0, checkState: ok }, "Up to date"],
    [{ pending: 1, checkState: ok }, "1 update waiting"],
    [{ pending: 7, checkState: ok }, "7 updates waiting"],
    [{ pending: 7, checkState: { tone: "warning", text: "Check stale" } }, "Check stale"],
    [{ checking: true }, "Checking for updates"],
    [{}, "Not checked yet"]
  ];
  for (const [values, want] of summaryRows) assert.equal(logic.summaryText(values), want);

  const now = new Date(2026, 8, 29, 14, 30).getTime();
  const today = new Date(2026, 8, 29, 14, 2).getTime();
  const yesterday = new Date(2026, 8, 28, 23, 59).getTime();
  const when = (ms, withDate) => (withDate ? "date+" : "") + (ms === today ? "14:02" : "23:59");
  assert.equal(logic.checkedText(today, now, when), "Checked 14:02");
  assert.equal(logic.checkedText(yesterday, now, when), "Checked date+23:59");
  assert.equal(logic.checkedText(undefined, now, when), "Never checked");

  const sources = [
    { source: "pacman", label: "System", count: 2, packages: [{ name: "linux", old: "6.1", new: "6.2" }, { name: "mesa", old: null, new: "25.2" }], checkedAt: today, error: null, more: 3 },
    { source: "aur", label: "AUR", count: null, packages: [], checkedAt: null, error: "exit=1 network down", more: 0 },
    { source: "flatpak", label: "Flatpak", count: 0, packages: [], checkedAt: today, error: null, more: 0 },
    { source: "plugins", label: "Plugins", count: 1, packages: [{ name: "acme.one", old: "a".repeat(40), new: "b".repeat(40), behind: 2 }], checkedAt: today, error: "bad: fetch=bad", more: 0 },
    { source: "later", label: "later", count: 1, packages: [{ name: "x", old: null, new: null }], checkedAt: today, error: null, more: 0 }
  ];
  const values = { pending: 4, lastCheck: today, checkState: { tone: "warning", text: "AUR: exit=1 network down" }, checking: false, sources };
  same(logic.widgetTooltip(values, now, when), {
    title: "AUR: exit=1 network down",
    details: [
      { label: "System", value: 2 },
      { label: "AUR", value: "check failed" },
      { label: "Flatpak", value: 0 },
      { label: "Plugins", value: 1 },
      { label: "later", value: 1 },
      "Checked 14:02"
    ]
  });
  same(logic.widgetTooltip({}, now, when), { title: "Not checked yet", details: ["Never checked"] });
  same(logic.windowRows(values), [
    { key: "pacman", source: "pacman", label: "System", icon: "package", secondary: "2 updates", badge: "2", badgeTone: "accent", updatable: true, lines: ["linux 6.1 → 6.2", "mesa → 25.2"], more: "+3 more" },
    { key: "aur", source: "aur", label: "AUR", icon: "package-open", secondary: "The update check failed. Select Refresh to try again.", badge: "Failed", badgeTone: "warning", updatable: false, lines: [], more: "" },
    { key: "flatpak", source: "flatpak", label: "Flatpak", icon: "boxes", secondary: "Up to date", badge: "0", badgeTone: "neutral", updatable: false, lines: [], more: "" },
    { key: "plugins", source: "plugins", label: "Plugins", icon: "puzzle", secondary: "The update source could not be reached. Check your connection and select Refresh.", badge: "1", badgeTone: "warning", updatable: true, lines: ["acme.one: 2 commits behind"], more: "" },
    { key: "later", source: "later", label: "later", icon: "package", secondary: "1 update", badge: "1", badgeTone: "accent", updatable: true, lines: ["x"], more: "" }
  ]);
  same(logic.windowRows({}), []);

  same(logic.tuiRequest("all"), { name: "update", args: [] });
  same(logic.tuiRequest("source", "aur"), { name: "update-source", args: ["aur"] });
  same(logic.tuiRequest("log"), { name: "log", args: [] });
  assert.throws(() => logic.tuiRequest("source", ""), /needs a source/);
  assert.throws(() => logic.tuiRequest("everything"), /is not one of all, source, log/);
  same(["ok", "started", "queued", "refused: tui=update reason=busy"].map(logic.replyLine), ["", "", "", ""]);
  assert.equal(logic.replyLine("refused: tui=update reason=launcher-missing"), "The setup window could not open. VGS is missing its terminal launcher, xdg-terminal-exec. Reinstall VGS to restore it.");
  assert.equal(logic.replyLine("refused: tui=update reason=launcher-failed"), "VGS could not open the update action. Try again.");

  // The third-party review. Expected values are written from the issue's
  // rulings: claude before codex, each with the owner's default command.
  const claude = ["claude", "--model", "opus", "--effort", "medium", "--permission-mode", "default"];
  const codex = ["codex", "-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=medium", "--sandbox", "workspace-write", "--ask-for-approval", "on-request"];
  const on = (agent, command) => ({ reviewThirdParty: true, reviewAgent: agent, reviewCommand: command });
  // [name, settings, agents found, plan]
  const reviewRows = [
    ["off", { reviewThirdParty: false, reviewAgent: "", reviewCommand: "" }, ["claude"], { state: "off", agent: null, label: "", command: null }],
    ["claude before codex", on("", ""), ["codex", "claude"], { state: "agent", agent: "claude", label: "Claude Code", command: claude }],
    ["codex alone", on("", ""), ["codex"], { state: "agent", agent: "codex", label: "Codex", command: codex }],
    ["a chosen agent", on("codex", ""), ["claude", "codex"], { state: "agent", agent: "codex", label: "Codex", command: codex }],
    ["a chosen agent not found", on("codex", ""), ["claude"], { state: "missing", agent: "codex", label: "Codex", command: null }],
    ["no agent found", on("", ""), [], { state: "none", agent: null, label: "", command: null }],
    ["a command runs as written", on("", "  /opt/bin/agent   --flag  x "), [], { state: "command", agent: null, label: "/opt/bin/agent", command: ["/opt/bin/agent", "--flag", "x"] }],
    ["a command naming an agent", on("codex", "claude --model sonnet"), ["claude"], { state: "command", agent: "claude", label: "Claude Code", command: ["claude", "--model", "sonnet"] }],
    ["a command naming an agent not found", on("", "claude --model sonnet"), ["codex"], { state: "missing", agent: "claude", label: "Claude Code", command: null }]
  ];
  for (const [name, settings, found, plan] of reviewRows) {
    same(logic.reviewPlan(settings, found), plan, "review plan: " + name);
    const text = logic.reviewAgentText(logic.reviewPlan(settings, found));
    assert.ok(typeof text === "string" && text.length > 0 && text.length <= 200, "review text: " + name);
  }
  assert.throws(() => logic.reviewAgentText({ state: "elsewhere" }), /has no text/);
  same(logic.reviewChoices(["codex", "claude"]), [{ label: "Claude Code", value: "claude" }, { label: "Codex", value: "codex" }]);
  same(logic.reviewChoices([]), []);
  same(logic.reviewValues(on("", ""), null), { reviewAgents: null, reviewAgent: null });
  same(logic.reviewValues(on("", ""), ["codex"]).reviewAgents, [{ label: "Codex", value: "codex" }]);
  assert.equal(logic.reviewValues(on("", ""), ["codex"]).reviewAgent, logic.reviewAgentText(logic.reviewPlan(on("", ""), ["codex"])));
  same(logic.statusWrites({}, { reviewAgents: [], reviewAgent: "Off" }).map(w => w.key), ["reviewAgents", "reviewAgent"]);
  // The manifest's presets are the table's default commands.
  const manifest = JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8"));
  same(manifest.schema.reviewCommand.presets.map(p => p.value), ["", claude.join(" "), codex.join(" ")]);
  for (const [repo, official] of [["core", true], ["extra", true], ["multilib", true], ["cachyos", true], ["cachyos-extra-znver4", true], ["chaotic-aur", false], ["core-testing", false], ["mycore", false]])
    assert.equal(logic.officialRepository(repo), official, "official repository: " + repo);
  // [name, verdict text, the packages reviewed, the judgement]
  const verdictRows = [
    ["clean", "verdict clean\n", ["a"], { ok: true, verdict: "clean", flags: [] }],
    ["flagged", "verdict flagged\nflag a A new source domain.\nflag b It runs curl into sh.\n", ["a", "b", "c"], { ok: true, verdict: "flagged", flags: [{ name: "a", concern: "A new source domain." }, { name: "b", concern: "It runs curl into sh." }] }],
    ["empty", "", ["a"], { ok: false, error: "line=1" }],
    ["another first line", "all good\n", ["a"], { ok: false, error: "line=1" }],
    ["clean with a flag", "verdict clean\nflag a x\n", ["a"], { ok: false, error: "verdict=clean flags=1" }],
    ["flagged with no flag", "verdict flagged\n", ["a"], { ok: false, error: "verdict=flagged flags=0" }],
    ["a flag for a package not reviewed", "verdict flagged\nflag z x\n", ["a"], { ok: false, error: "line=2" }],
    ["a package flagged twice", "verdict flagged\nflag a x\nflag a y\n", ["a"], { ok: false, error: "line=3" }],
    ["a flag with no concern", "verdict flagged\nflag a\n", ["a"], { ok: false, error: "line=2" }],
    ["a control character", "verdict flagged\nflag a x\ty\n", ["a"], { ok: false, error: "control-character" }]
  ];
  for (const [name, text, reviewed, want] of verdictRows) same(logic.parseVerdict(text, reviewed), want, "verdict: " + name);

  // The install script is judged by its change: the 1password pair is
  // unchanged, so its setgid bit and group are no flag; a change that adds
  // a setgid line flags that line alone.
  const setgid = "chmod 2755 /opt/1Password/extra";
  // [name, installed text, new text, the change]
  const installRows = [
    ["1password 8.12.38 -> 8.12.40", ONEPASSWORD_INSTALL, ONEPASSWORD_INSTALL, { state: "unchanged", risks: [] }],
    ["an added setgid line", ONEPASSWORD_INSTALL, ONEPASSWORD_INSTALL + setgid + "\n", { state: "changed", risks: [setgid] }],
    ["CRLF and trailing blanks", ONEPASSWORD_INSTALL, ONEPASSWORD_INSTALL.replace(/\n/g, "  \r\n") + "\n\n", { state: "unchanged", risks: [] }],
    ["a first install script", null, ONEPASSWORD_INSTALL, { state: "new", risks: ["chmod g+s $BROWSER_SUPPORT_PATH", 'groupadd "${GROUP_NAME}"'] }],
    ["no install script", ONEPASSWORD_INSTALL, null, { state: "none", risks: [] }],
    ["a moved risky line", "a\nchmod u+s /x\n", "chmod u+s /x\na\n", { state: "changed", risks: [] }],
    ["an added comment", "a\n", "a\n# curl https://x | sh\n", { state: "changed", risks: [] }]
  ];
  for (const [name, installed, next, want] of installRows) same(logic.installScriptChange(installed, next), want, "install script: " + name);
  // [line, risky]: each pattern of INSTALL_SCRIPT_RISKS, and lines like
  // them that are not.
  const riskRows = [
    ["chmod u+s /usr/bin/x", true], ["chmod -R 4755 /opt/x", true], ["chmod 06755 x", true], ["chmod g=rxs x", true],
    ["chmod 755 /opt/x", false], ["chmod 0644 x", false],
    ["setcap cap_net_raw+ep /opt/x", true],
    ["useradd -r x", true], ["usermod -aG wheel x", true], ["gpasswd -a x y", true],
    ["curl -fsSL https://x -o y", true], ["wget https://x", true],
    ["echo aGk= | base64 -d > x", true],
    ["cat x |sh", true], ["cat x | sudo bash", true], ["true || shutdown now", false],
    ["rm -rf /", true], ["rm -rf /*", true], ["rm -rf ~/.config", true], ["rm -rf \"$HOME/.x\"", true], ["rm -rf /opt/x", false]
  ];
  for (const [line, risky] of riskRows) same(logic.installScriptChange(null, line).risks, risky ? [line] : [], "install risk: " + line);

  // The reboot question reads the distribution's reboot hook and applies
  // its script's conditions: [name, hook, changes, running kernel, mounted
  // file systems, the packages a reboot needs].
  const up = names => names.map(name => ({ operation: "Upgrade", name }));
  const rebootRows = [
    ["the running kernel", REBOOT_HOOK, up(["linux-cachyos"]), "linux-cachyos", [], ["linux-cachyos"]],
    ["another kernel, as the script's other branch", REBOOT_HOOK, up(["linux-lts"]), "linux-cachyos", [], ["linux-lts"]],
    ["nvidia beside linux-cachyos", REBOOT_HOOK, up(["nvidia"]), "linux-cachyos", [], []],
    ["nvidia beside linux", REBOOT_HOOK, up(["nvidia"]), "linux", [], ["nvidia"]],
    ["nvidia-lts beside linux", REBOOT_HOOK, up(["nvidia-lts"]), "linux", [], []],
    ["nvidia-lts beside linux-lts", REBOOT_HOOK, up(["nvidia-lts"]), "linux-lts", [], ["nvidia-lts"]],
    ["linux-cachyos-nvidia beside linux-cachyos-lts", REBOOT_HOOK, up(["linux-cachyos-nvidia-open"]), "linux-cachyos-lts", [], ["linux-cachyos-nvidia-open"]],
    ["linux-cachyos-nvidia beside linux-zen", REBOOT_HOOK, up(["linux-cachyos-nvidia-open"]), "linux-zen", [], []],
    ["btrfs-progs with no btrfs mounted", REBOOT_HOOK, up(["btrfs-progs"]), "linux-cachyos", ["ext4", "tmpfs"], []],
    ["btrfs-progs with btrfs mounted", REBOOT_HOOK, up(["btrfs-progs"]), "linux-cachyos", ["btrfs"], ["btrfs-progs"]],
    ["xfsprogs with no xfs mounted", REBOOT_HOOK, up(["xfsprogs"]), "linux-cachyos", ["btrfs"], []],
    ["xfsprogs with xfs mounted", REBOOT_HOOK, up(["xfsprogs"]), "linux-cachyos", ["xfs"], ["xfsprogs"]],
    ["e2fsprogs with no ext4 mounted", REBOOT_HOOK, up(["e2fsprogs"]), "linux-cachyos", ["btrfs"], []],
    ["e2fsprogs with ext4 mounted", REBOOT_HOOK, up(["e2fsprogs"]), "linux-cachyos", ["ext4"], ["e2fsprogs"]],
    ["mesa", REBOOT_HOOK, up(["mesa"]), "linux-cachyos", [], ["mesa"]],
    ["firefox", REBOOT_HOOK, up(["firefox"]), "linux-cachyos", [], []],
    ["globbed targets, in the run's order", REBOOT_HOOK, up(["systemd-libs", "linux-headers", "nvidia-470xx", "mesa-utils", "xf86-video-amdgpu"]), "linux-cachyos", [], ["systemd-libs", "nvidia-470xx", "xf86-video-amdgpu"]],
    ["a new package under an Upgrade trigger", REBOOT_HOOK, [{ operation: "Install", name: "linux-lts" }], "linux-cachyos", [], []],
    ["no hook", null, up(["linux-cachyos", "mesa"]), "linux-cachyos", [], []],
    ["an Install trigger", "[Trigger]\nOperation = Install\nType = Package\nTarget = linux*\n", [{ operation: "Install", name: "linux-lts" }, { operation: "Upgrade", name: "linux" }], "linux", [], ["linux-lts"]],
    ["the last matching target decides", "[Trigger]\nOperation = Upgrade\nType = Package\nTarget = linux*\nTarget = !linux-*-headers\n", up(["linux-zen", "linux-zen-headers"]), "linux", [], ["linux-zen"]],
    ["a Path trigger names no package", "[Trigger]\nOperation = Upgrade\nType = Path\nTarget = linux\n", up(["linux"]), "linux", [], []],
    ["an action section names no target", "[Action]\nOperation = Upgrade\nTarget = linux\n", up(["linux"]), "linux", [], []]
  ];
  for (const [name, hook, changes, kernel, mounted, want] of rebootRows) same(logic.rebootPackages(hook, changes, kernel, mounted), want, "reboot: " + name);
  // [pattern, name, matches]: fnmatch(3) as alpm matches a Target.
  const globRows = [
    ["linux-cachyos*", "linux-cachyos-lts", true], ["linux-cachyos*", "linux-zen", false],
    ["nvidia-*xx", "nvidia-470xx", true], ["nvidia-?70xx", "nvidia-470xx", true], ["nvidia-?xx", "nvidia-470xx", false],
    ["xf86-video-[ai]*", "xf86-video-intel", true], ["xf86-video-[!ai]*", "xf86-video-intel", false], ["xf86-video-[^ai]*", "xf86-video-nouveau", true],
    ["lib\\*", "lib*", true], ["lib\\*", "libx", false], ["a.b", "axb", false], ["a+", "aa", false]
  ];
  for (const [pattern, name, want] of globRows) assert.equal(logic.globMatch(pattern, name), want, "glob: " + pattern + " " + name);
  // [/proc/version text, the running kernel's package]
  const kernelRows = [
    ["Linux version 7.2.9-1-cachyos (linux-cachyos@cachyos) (clang version 23.1.1, LLD 23.1.1) #1 SMP PREEMPT_DYNAMIC Sat, 03 Oct 2026 14:14:24 +0000", "linux-cachyos"],
    ["Linux version 6.10.3-arch1-1 (linux@archlinux) (gcc (GCC) 14.2.1 20240805, GNU ld (GNU Binutils) 2.43.0) #1 SMP PREEMPT_DYNAMIC", "linux"],
    ["Linux version 6.1.0", ""]
  ];
  for (const [text, want] of kernelRows) assert.equal(logic.kernelPackage(text), want, "kernel: " + text);
  // [the reboot-notice step, the rebootNotice status value]
  const noticeRows = [
    [{ state: "absent", reason: "hook-missing" }, { hidden: true }],
    [{ state: "unknown", reason: "unprobed" }, { hidden: true }],
    [{ state: "needed", reason: "notice-on" }, { tone: "info", text: "CachyOS and VGS", action: "vgsOnly" }],
    [{ state: "ready", reason: "notice-off" }, { tone: "ok", text: "VGS only", action: "both" }],
    [{ state: "denied", reason: "foreign-file" }, null],
    [{ state: "denied", reason: "foreign-link" }, null],
    [{ state: "unknown", reason: "probe-failed" }, null],
    [null, null]
  ];
  for (const [step, want] of noticeRows) {
    const value = logic.rebootNoticeValue(step);
    if (want !== null) same(value, want, "reboot notice: " + JSON.stringify(step));
    else same([value.hidden, value.action], [undefined, undefined], "reboot notice offers nothing: " + JSON.stringify(step));
  }
  same(logic.statusWrites({}, { rebootNotice: { hidden: true } }), [{ key: "rebootNotice", value: { hidden: true } }]);
}

verify(load(file));

const controls = [
  ["a missing launcher needs installation repair", 'if (/reason=launcher-missing/.test(reply))', 'if (false)'],
    ["diagnostics stay out of display text", 'function errorText(reason) {', 'function errorText(reason) { return String(reason);'],
  ["package rows count", "total += snapshot.sources[i].count;", "total += 0;"],
  ["outdated rows count once", "count += 1;", "count += behind;"],
  ["outdated packages keep behind", "behind: behind", "oldBehind: behind"],
  ["check failure wins state", "if (checkFailure !== null && checkFailure !== undefined && checkFailure !== \"\") return { tone: \"danger\", text: errorText(checkFailure) };", "if (false) return { tone: \"danger\", text: \"\" };"],
  ["status writes skip unchanged", "if (!hasOwn(before, key) || !sameJson(before[key], next[key])) out.push({ key: key, value: clone(next[key]) });", "out.push({ key: key, value: clone(next[key]) });"],
  ["failure retry uses short delay", "failedAt + RETRY_AFTER_FAILURE_MS - now", "failedAt + interval - now"],
  ["proc stat btime is parsed as milliseconds", "if (m !== null) return Number(m[1]) * 1000;", "if (false) return Number(m[1]) * 1000;"],
  ["a pre-boot snapshot is due now", "if (snapshotBeforeBoot(snapshot, bootedAt)) return 0;", "if (false) return 0;"],
  ["only a cached snapshot is judged against boot", "snapshot !== null && snapshot.cached === true && typeof bootedAt", "snapshot !== null && typeof bootedAt"],
  ["a failed package probe is one packages row", "if (!parsed.ok) return [sourceRow(\"packages\", null, [], null, parsed.error)];", "if (!parsed.ok) return [];"],
  ["published packages are bounded", "var limit = Math.min(row.packages.length, PUBLISHED_PACKAGES_PER_SOURCE_MAX);", "var limit = row.packages.length;"],
  ["published rows carry the omitted package count", "made.more = Math.max(0, row.packages.length - packages.length);", "made.more = 0;"],
  ["published package text is bounded", "return text.length > PUBLISHED_PACKAGE_TEXT_MAX ? text.slice(0, PUBLISHED_PACKAGE_TEXT_MAX) : text;", "return text;"],
  ["source errors set warning", "if (source !== null) return { tone: \"warning\", text: ((source.label || source.source) + \": \" + errorText(source.error)).slice(0, 200) };", "if (false) return { tone: \"warning\", text: \"\" };"] ,
  ["stale after twice the interval", "now - snapshot.checkedAt >= 2 * intervalMs", "now - snapshot.checkedAt > 3 * intervalMs"],
  ["a stale snapshot sets no stale timer", "return delay > 0 ? delay : null;", "return Math.max(0, delay);"],
  ["the timer wakes when the snapshot turns stale", "return delay > 0 ? delay : null;", "return null;"],
  ["TUI endedAt advances", "if (next.endedAt > prior.endedAt) return true;", "if (false) return true;"],
  ["a running record that goes ends no run", "if (next.endedAt > prior.endedAt) return true;", "if (next.endedAt > prior.endedAt || prior.running === true) return true;"],
  ["outdated error makes a source error", "if (!UNTRACKED_REFUSAL.test(String(row.error))) errors.push(row.id + \": \" + row.error);", "count += 0;"],
  ["an untracked directory is not a source error", "var UNTRACKED_REFUSAL = /^not-a-checkout=/;", "var UNTRACKED_REFUSAL = /^$never/;"],
  ["one failing checkout keeps the others' count", "return sourceRow(source, count, packages, checkedAt, errors.length > 0 ? errors.join(\"; \") : null);", "return sourceRow(source, errors.length > 0 ? null : count, packages, checkedAt, errors.length > 0 ? errors.join(\"; \") : null);"],
  ["only a current widget hides", "hidden: hideWhenCurrent === true && state === \"current\"", "hidden: hideWhenCurrent === true && state !== \"checking\""],
  ["a warning or danger check draws attention", "case \"danger\": return \"attention\";", "case \"danger\": return \"current\";"],
  ["a running check spins", "if (v.checking === true) return \"checking\";", "if (false) return \"checking\";"],
  ["pending needs a count", "case \"ok\": return pendingOf(v) > 0 ? \"pending\" : \"current\";", "case \"ok\": return \"pending\";"],
  ["the badge is capped", "return count > BADGE_COUNT_MAX ? BADGE_COUNT_MAX + \"+\" : String(count);", "return String(count);"],
  ["the checked line dates another day", "formatWhen(lastCheck, !sameLocalDay(lastCheck, now))", "formatWhen(lastCheck, false)"],
  ["a source with no count reads failed in the tooltip", "sources[i].count === null ? \"check failed\" : sources[i].count", "sources[i].count"],
  ["a failed source keeps its badge", "badge: failed ? \"Failed\" : badgeText(row.count),", "badge: badgeText(row.count),"],
  ["only a source with updates offers Update", "updatable: !failed && row.count > 0,", "updatable: true,"],
  ["the omitted packages read +N more", "more: typeof row.more === \"number\" && row.more > 0 ? \"+\" + row.more + \" more\" : \"\"", "more: \"\""],
  ["a checkout reads its commits behind", "if (typeof pkg.behind === \"number\") return", "if (false) return"],
  ["one source's update names its source", "return { name: \"update-source\", args: [source] };", "return { name: \"update-source\", args: [] };"],
  ["a first TUI state read counts no ended run", "if (previous === null) return false;", "if (false) return false;"],
  ["no timer before the cache read answers", "if (cacheRead !== true) return null;", "if (false) return null;"],
  ["no timer before the boot read answers", "if (bootRead !== true) return null;", "if (false) return null;"],
  ["the service publishes whether it checks", "checking: checking === true,", "checking: false,"],
  ["the review offers claude before codex", 'var REVIEW_AGENTS = [\n    { id: "claude", label: "Claude Code", command: ["claude", "--model", "opus", "--effort", "medium", "--permission-mode", "default"] },\n    { id: "codex", label: "Codex", command: ["codex", "-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=medium", "--sandbox", "workspace-write", "--ask-for-approval", "on-request"] }\n];', 'var REVIEW_AGENTS = [\n    { id: "codex", label: "Codex", command: ["codex", "-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=medium", "--sandbox", "workspace-write", "--ask-for-approval", "on-request"] },\n    { id: "claude", label: "Claude Code", command: ["claude", "--model", "opus", "--effort", "medium", "--permission-mode", "default"] }\n];'],
  ["a default command keeps its restricted mode", '"--permission-mode", "default"] },', '] },'],
  ["a review command runs as written", "if (words.length > 0) {", "if (false) {"],
  ["a chosen agent must be found", "if (row === null || found.indexOf(chosen) < 0) return", "if (row === null) return"],
  ["the review is off with its setting", "if (s.reviewThirdParty !== true) return", "if (false) return"],
  ["a command naming an absent agent is missing", "if (named !== null && found.indexOf(named.id) < 0) return", "if (false) return"],
  ["the review's end starts no check", "if (UNCHECKED_TUIS.indexOf(key) >= 0) continue;", ""],
  ["the review statuses are written", '"sources", "reviewAgents", "reviewAgent", "rebootNotice"]', '"sources", "rebootNotice"]'],
  ["a CachyOS repository is official", "/^(core|extra|multilib|cachyos.*)$/", "/^(core|extra|multilib)$/"],
  ["a flag names a reviewed package", "reviewed.indexOf(m[1]) < 0 || ", ""],
  ["a clean verdict holds no flag", "if ((head[1] === \"clean\") !== (flags.length === 0))", "if (false)"],
  ["a verdict holds no control character", "if (/[\\u0000-\\u0009\\u000b-\\u001f\\u007f]/.test(String(text))) return", "if (false) return"],
  ["an install script is judged against the installed one", "var held = {};", "var held = {}; old = null;"],
  ["equal scripts are unchanged", 'sameJson(old, next) ? "unchanged" : "changed"', '"changed"'],
  ["line ends and trailing whitespace are set aside", 'return line.replace(/\\s+$/, "");', "return line;"],
  ["a comment line is no risk", 'line.charAt(0) === "#" || ', ""],
  ["a setuid or setgid mode is a risk", "/\\bchmod (?:[^;|&]* )?(?:[ugoa]*[+=][rwxXt]*s|0?[234567][01234567]{3}\\b)/,", ""],
  ["file capabilities are a risk", "/\\bsetcap\\b/,", ""],
  ["a user or group change is a risk", "/\\b(?:groupadd|useradd|usermod|gpasswd)\\b/,", ""],
  ["a download is a risk", "/\\b(?:curl|wget)\\b/,", ""],
  ["an encoded payload is a risk", "/\\bbase64\\b/,", ""],
  ["a pipe into a shell is a risk", "/\\| ?(?:sudo )?(?:ba|da|z)?sh\\b/,", ""],
  ["a removal of the root or a home is a risk", '/\\brm (?:-\\S+ )*(?:\\/\\*?|~\\S*|"?\\$HOME\\S*|\\/home\\S*|\\/root\\S*)(?: |$)/', "/$^/"],
  ["nvidia needs linux", 'if (name === "nvidia") return kernel === "linux";', 'if (name === "nvidia") return true;'],
  ["nvidia-lts needs linux-lts", 'if (name === "nvidia-lts") return kernel === "linux-lts";', 'if (name === "nvidia-lts") return true;'],
  ["linux-cachyos-nvidia needs linux-cachyos", 'return globMatch("linux-cachyos*", kernel);', "return true;"],
  ["a file system tool needs its file system mounted", "return mounted.indexOf(FILESYSTEM_TOOLS[name]) !== -1;", "return true;"],
  ["each file system tool serves its own file system", 'var FILESYSTEM_TOOLS = { "btrfs-progs": "btrfs", "xfsprogs": "xfs", "e2fsprogs": "ext4" };', 'var FILESYSTEM_TOOLS = {};'],
  ["only the hook's targets need a reboot", "&& targetsMatch(trigger.targets, change.name);", ";"],
  ["a trigger lists the run's operation", "return trigger.operations.indexOf(change.operation) !== -1 && targetsMatch", "return targetsMatch"],
  ["only a Package trigger names packages", '.filter(function (trigger) { return trigger.type === "Package"; })', ""],
  ["only a Trigger section holds targets", 'current = section[1] === "Trigger" ? { operations: [], type: "", targets: [] } : null;', 'current = { operations: [], type: "Package", targets: [] };'],
  ["the last matching target decides", "for (var i = targets.length - 1; i >= 0; i--) {", "for (var i = 0; i < targets.length; i++) {"],
  ["a ! target excludes", "if (globMatch(inverted ? targets[i].slice(1) : targets[i], name)) return !inverted;", "if (globMatch(inverted ? targets[i].slice(1) : targets[i], name)) return true;"],
  ["a glob * matches any run", 'if (c === "*") { out += "[\\\\s\\\\S]*"; continue; }', 'if (c === "*") { out += "[\\\\s\\\\S]"; continue; }'],
  ["a glob ? matches one character", 'if (c === "?") { out += "[\\\\s\\\\S]"; continue; }', 'if (c === "?") { out += "[\\\\s\\\\S]*"; continue; }'],
  ["a glob bracket negates", 'out += "[" + (negated ? "^" : "")', 'out += "[" + ""'],
  ["a glob \\ quotes", 'if (c === "\\\\" && i + 1 < pattern.length) { i++; out += pattern.charAt(i)', 'if (false) { i++; out += pattern.charAt(i)'],
  ["a glob matches a literal literally", 'out += c.replace(/[\\\\^$.*+?()[\\]{}|\\/-]/g, "\\\\$&");\n    }', "out += c;\n    }"],
  ["the kernel is read from /proc/version", 'return m === null ? "" : m[1];', 'return "";'],
  ["an absent hook hides the reboot notice", 'if (state === "absent" || (state === "unknown"', 'if ((state === "unknown"'],
  ["an unprobed step hides the reboot notice", '(state === "unknown" && step && step.reason === "unprobed")', "false"],
  ["the CachyOS notice on offers VGS only", 'case "needed": return { tone: "info", text: "CachyOS and VGS", action: "vgsOnly" };', 'case "needed": return { tone: "info", text: "CachyOS and VGS" };'],
  ["a file or link VGS did not make offers nothing", 'case "denied": return { tone: "warning", text: "Set by another file",', 'case "denied": return { tone: "warning", text: "Set by another file", action: "both",'],
  ["VGS only offers both", 'case "ready": return { tone: "ok", text: "VGS only", action: "both" };', 'case "ready": return { tone: "ok", text: "VGS only", action: "vgsOnly" };'],
  ["the reboot notice is written", '"reviewAgents", "reviewAgent", "rebootNotice"]', '"reviewAgents", "reviewAgent"]'],
  ["failed probe is reported", "if (!probe || probe.status !== 0) return { ok: false, error: commandError(name, probe || { status: null, stderr: \"\" }) };", "if (!probe || probe.status !== 0) return { ok: true, value: [] };"],
];

fs.rmSync(scratch, { recursive: true, force: true });
fs.mkdirSync(scratch, { recursive: true });
try {
  const source = fs.readFileSync(file, "utf8");
  for (const [label, needle, replacement] of controls) {
    const count = source.split(needle).length - 1;
    assert.equal(count, 1, "control pattern occurs once: " + label);
    const mutant = path.join(scratch, "UpdatesLogic.js");
    fs.writeFileSync(mutant, source.replace(needle, replacement));
    let red = false;
    try { verify(load(mutant)); } catch (e) { red = true; }
    assert.equal(red, true, "control fails without rule: " + label);
  }
} finally {
  fs.rmSync(scratch, { recursive: true, force: true });
}

console.log("test-updates-logic: ok");
