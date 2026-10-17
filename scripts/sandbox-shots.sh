#!/usr/bin/env bash
# Capture the shell's surfaces in the nested Hyprland sandbox with grim.
#
# Usage: scripts/sandbox-shots.sh [--out DIR] [--rev REV] [--modes LIST]
#                                 [--size WxH] [--scale N]
#                                 [--theme-card NAME] [--hidden]
#                                 [--preview-themes LIST] [--preview-wallpaper NAME=PATH]...
#                                 [--dotfiles DIR] [--pages LIST] [--enable LIST] [--disable LIST]
#                                 [--timeout SECONDS] [--keep] [SCENE...]
#                                 [--title-inventory]
#       scripts/sandbox-shots.sh --check-desktop-pair BEFORE_DIR AFTER_DIR
#
# The sandbox is the smoke's own (scripts/smoke/harness.sh): its own HOME,
# runtime dir, buses and nested compositor, with the shell started inside
# it. grim is pointed at the nested compositor's socket alone
# (scripts/smoke/shot.sh refuses the host socket), so nothing is captured
# or started on the live desktop. It needs the smoke's prerequisites,
# WAYLAND_DISPLAY and XDG_RUNTIME_DIR included, plus grim.
#

# SCENE is gallery, settings, wide-settings, focus, focus-open, flyout-titles, plugin-pages, manager, launcher,
# notifications, bar, panels, devtools, system, network, vpn, vpn-locked, bluetooth, power, dialog, by-hand, reset, lock, polkit,
# greeter, narrow, theme-browser, wallpaper-browser, automations, cloudsync, tooltips, capture,
# keyhints, clipboard, voice, voice-setup, voice-elsewhere, dictation-setup, jarvis-console, jarvis-audit, jarvis-setup, elevenlabs-voices, jarvis-fleet, outdated, jarvis-causes, plugin-messages, page-links, tooltip-link, traffic, ai-usage, sysmon, tui-edges, appearance, sounds, setup-tab, updates, clone-voice or theme-previews. settings takes the
# automations', the Jarvis, the AI Usage and the Tray pages among the plugin pages,
# each when the tree ships its plugin. plugin-pages, taken only when named, opens every
# plugin the Settings window lists, in that window's order, or with --pages
# the comma-separated ids it names. `ID:settings`, `ID:setup` and
# `ID:details` select a tab. A missing Setup tab is captured on Settings,
# with its tab strip in view. pages.tsv records the requested and shown
# tabs beside each shot. It captures
# every screen of an overflowing page. bar is the bar with every
# first-party widget and each widget's tooltip or
# hover; tooltips, taken only when named, enables and places every
# first-party plugin with a bar widget and shoots each widget's tooltip;
# panels is the Agent Warden panel, the Updates window and the
# themes panel over planted status or packages, the themes panel's
# apply held and answered by a stand-in
# runner that changes no theme; devtools is the Dev Tools window;
# appearance is the System window's Appearance group, Motion, Windows, UI
# and, where the tree ships it, Fonts, each Set by theme, then Windows with
# a corner radius of 12; sounds,
# taken only when named, is its Sounds section over the events of
# Notifications, Voice and Jarvis, then with a picker's list open and with
# one event turned off; system
# is the System window as it opens with no System section enabled, then
# System → Displays over the device fakes and two monitors when the tree
# ships it, and
# its Sound section over the sandbox's private PipeWire, then the window
# as Sound is turned off while shown, the Mouse pane and Keyboard's pane,
# widget menu and panel source menu; bluetooth is
# its Bluetooth section, then the Bluetooth dropdown, over the device
# fakes; vpn is its VPN section, then the VPN dropdown, over the
# tailscale and nmcli stand-ins; vpn-locked, taken only when named, is the
# VPN dropdown while Tailscale's access step is offered: at rest, its
# header switch under the pointer and under keyboard focus, the switch's
# unlock mark under keyboard focus, and Sign in under the pointer over a
# signed-out tailnet; power is its flyout over the sandbox's fake
# battery and power profile daemon, then over the daemon with no battery;
# keyhints is the
# Key Hints window over the Launcher's, Settings' and Themes' shortcuts and
# its own; ai-usage is AI Usage's dropdown opened from its bar widget over
# three signed-in accounts, two Claude Code and one Codex, at rest and
# scrolled so the dividers under its header and over its footer show, read
# as scripts/smoke/rows/ai-usage.sh reads them: the endpoint stand-in
# scripts/fixtures/ai-usage/endpoint.js on 127.0.0.1, the Codex stand-in
# beside it and planted sign-ins, with no host claude or codex on the
# shell's PATH; jarvis-console is the Jarvis console window over the
# scripted daemon fixture in each conversation state, taken only when
# named; jarvis-audit draws the Audit tab over three entries from that
# fixture, at the default and narrow window sizes, and checks that an
# empty log fails its entry check; clipboard is the clipboard history over copies made on the
# nested instance's own clipboard, taken only when named; capture is
# Capture's widget, panel and Settings page at the Recording section, taken
# only when named; voice is Voice's
# on-screen display while dictating, its plasma orb fed by stand-ins for
# voxtype's status stream and audio bridge, so no audio device opens, taken
# only when named; voice-setup is the requirement notice Voice's
# Requirements install (Set up on an older tree) raises without voxtype
# and Voice's Settings page then, the screen after a
# Set up run over a voxtype stand-in ended with code 0, with Voice's
# core toast or its notification card where the tree sends one, and
# Voice's Settings page once the
# stand-ins report it ready, taken only when named;
# voice-elsewhere is Voice's Settings page beside a voxtype daemon the
# shell did not start, then once that daemon has ended, after the page's
# Stop the other voxtype run ended with code 0 where the tree offers it,
# taken only when named;
# dictation-setup captures the floating setup terminal at its model
# confirmation, over the voxtype stand-in and a real kitty terminal.
# With --rev on a tree before the core setup, it captures Voice's Set up.
# No model download, system step or authentication runs.
# voice-keys is the Keys
# section of Voice's Settings page with Voice on, then the pointer on its
# first key's info icon where the tree draws one, which opens no tooltip,
# taken only when named; jarvis-setup is the Jarvis page's row
# actions with its daemon ready, as the settings scene readies it: the
# Settings tab's Setup section, then the Details tab at its Browser driver
# line and at its AI model section, then the Settings tab at its AI model
# fields with two backup models planted where the tree ships them, each
# anchor 12 px under the page's top; then, over a ready local voice, the
# Setup section with voxtype missing, with the voxtype stand-in and after
# a microphone check, and the Local voice field closed and open, listing
# the tree's setup-local choices, taken only when named; elevenlabs-voices
# is the Jarvis page with a stored ElevenLabs key whose voices a loopback
# stand-in first refuses, then lists: the Settings tab's Voice section and
# the Details tab's ElevenLabs voices line in each state, and the Voice
# field's list open on the listed voices, taken only when named; setup-tab is
# the plugin list's required-step badge, an optional-tool icon's tooltip
# where the captured revision declares that icon, a page with no
# Setup tab, and the status fixture's Setup tab with its required Token
# step incomplete and complete. setup-states.tsv records each fixture
# state and the tab's warning reading. It is taken only when named;
# updates is the Updates
# page with every tool it requires found or stood in and no Setup tab: its
# Settings tab, then Details with its Actions row, which holds Update
# everything, taken only when named; clone-voice is the
# Jarvis page's Settings tab at its Local voice section and its Setup tab
# at its Input step, over a ready Large local voice, with the Cloned voice
# off and not set up, with the clone setup's floating terminal at its first
# consent question beside the Settings window, set up with the setting on, and after Remove recording,
# or once in a tree without the Cloned voice, taken only when named;
# outdated is the
# Jarvis page over a stand-in
# agent-browser and a stand-in Pi that each answer a version below the
# floor Jarvis holds them to, Pi chosen as the AI model: the Details tab
# at its Browser driver line, the driver's line of its Requirements
# section, the Setup section, each on the tab the tree draws it on, and the
# core's requirement notice that Install all missing raises, its missing
# and outdated packages, over a stand-in bin/vgshell-pkg
# that answers pacman, paru and mise whatever the host runs, and that
# notice once a run of its step that changed nothing has ended, taken only
# when named; jarvis-fleet is the Settings tab's Setup section with a
# Jarvis home folder chosen that holds no kendex mail tool, taken only
# when named; jarvis-causes plants each Jarvis start cause and
# captures its bar widget tooltip and Setup section, taken only when named;
# cloudsync is Cloud Sync's bar widget, its tooltip, its window and every
# screen of its Settings page in each state the plugin's runner reaches
# over a local rclone remote and a keyring stand-in, from first run to a
# damaged folder pair list, each shot once the plugin's own
# CloudSyncLogic.js reads the published values as that state, taken only
# when named;
# printers is its Printers section over the CUPS stand-ins: no printer, one
# printer, two printers with the default, a busy printer and a stopped
# one, then the add flow with the devices CUPS finds and a refused
# address, and printing not installed, taken only when named;
# plugin-messages is a plugin's message to the
# user as the tree draws it, a core toast where the tree ships
# shell/Core/Toasts.qml and else its card in vgs.notifications with
# Silence off: the clipboard's paste failure, a transient message, its
# unsaved history, a lasting one, a lasting one whose message holds a page
# reference and, where its card draws the reference as a link, Settings on
# that page after a click on the card, and the lock's warning that the computer slept unlocked, sent
# through the lock's own unlock path, taken only when named; page-links is
# the acme.surfaces panel with a FormRow message holding a page reference
# to the probe fixture, then, where the tree's FormRow forwards the
# reference, the Settings window a click on its words opens on that page
# through shell.surfaces.openPage, taken only when named; tooltip-link is
# a bar item whose tooltip names another plugin's page, with the pointer on
# the link's words and then with the keyboard's focus ring on them, where
# the tree ships the acme.tiplink fixture, and else the same tooltip under
# the pointer on its item, taken only when named; focus is
# the keyboard focus proof set; dialog is the core's requirement notice;
# lock is the vgs.lock screen, locked and after wrong attempts; polkit is
# the vgs.polkit prompt, asking and after a failed attempt; greeter is the
# login screen, the core's greeter host over vgs.greeter's view; narrow holds a
# monitor 480 by 720 logical pixels and takes the bar, panels, devtools,
# dialog, lock, launcher, notifications and the first gallery pages again, each
# shot named <scene>-<mode>-narrow-*; theme-browser and wallpaper-browser
# are the vgs.themes browsers, taken only when named: the theme view
# loaded, with the pointer on a card, with a filter no card matches, with
# a refused card's failure line, on the chosen catalog card, on it
# installed and with its wallpaper offer; the wallpaper view on its Theme
# source, with the pointer on a card, with a typed filter, on its download
# card, on All and with a missing image's failure line.
# Each leaves vgs and the mode's theme applied. The default is every
# other scene the tree ships, or gallery and the manager's scene with
# --rev; the manager's scene is `settings` for a tree that ships
# vgs.settings and `manager`, the bar's manager panel, for one that ships
# the bar's manager built-in. A scene the tree does not ship is refused as
# `sandbox-shots: refused: scene=<scene> tree=<rev or checkout>`. --modes is a comma list of dark,
# light and rounded, dark by default with --rev and dark and light
# otherwise: dark is the defaults (theme `vgs`), light is the tree's
# catalog package themes/catalog/flexoki-light, and rounded is the
# defaults with `radius.sm`, `radius.md` and `radius.lg` at 6, 12 and 16,
# so every theme-rounded component shows whether its content clears its
# corners. catalog-NAME is the tree's catalog package
# themes/catalog/NAME, so a shot shows a component under any catalog theme;
# a NAME the catalog lacks is refused as `sandbox-shots: refused: mode=`.
# --enable LIST is a comma list of plugin ids. In each mode, before its
# first scene, the run turns each one on and waits for published enablement.
# Services, bars and backgrounds also wait for their live build. Windows
# and panes build when their scene opens them. An id
# of another shape is refused as `sandbox-shots: refused: enable=<value>`,
# and one the tree does not ship as
# `sandbox-shots: refused: enable=<id> tree=<rev or checkout>`.
# --disable LIST requests off states after scene fixtures are ready, before
# each mode's scenes. The active bar stays on so the capture retains its
# active surface; plugin-states.tsv records requested and actual states
# and that reason. Other requested plugins turn off, Themes included.
# The two lists must not share an id. plugin-states.tsv also records every
# shipped plugin's actual enablement and tool readings before each scene.
# page-states.tsv records each plugin-page image's actual theme, enablement,
# settings, choices, status and tools. It records live state; it does not
# freeze a service's poller. Pair readers compare these records before
# claiming equal states across themes or revisions.
# --rev REV runs that revision's shell, bin, config and themes (git archive),
# under this checkout's harness and probe, for a before shot; the plugin
# fixtures a scene installs are that revision's, which its judge accepts.
# A scene reaches what that tree ships: the gear's and the launcher
# entries' item types, a search cleared by keys where no Clear
# search exists, and Install where a Dev Tools row has no Details.
# --scale is 1, the default, or 2: at 2 the harness holds the nested
# output at double its mode and scale 2 before the shell starts
# (shell_output_scale in scripts/smoke/harness.sh), so the layout keeps its
# logical size and the shell draws each PNG in device pixels. A configure
# the host sends the nested window, such as a resize or a refocus, resets
# a held mode (held_mode_state in scripts/smoke/mode-hold.sh), so before
# each shot and each hover under a held mode, this one or --size's, the
# run takes the mode again and puts the pointer back where the scene left
# it (settle_hold), and a shot after whose capture the output no longer
# reads the mode is taken once more (shot_held in scripts/smoke/shot.sh);
# a mode that cannot be taken again, or a second reset in that capture,
# fails the shot. Another value is refused as
# `sandbox-shots: refused: scale=<value>`.
# --size WxH holds the nested output at W by H logical pixels, at the run's
# scale, for every scene, so a shot's width does not depend on the host's
# window; another shape is refused as `sandbox-shots: refused: size=<value>`.
# --theme-card NAME is the catalog theme the theme-browser scene selects,
# frankenstein by default. A name other than lowercase letters, digits and
# hyphens is refused as `sandbox-shots: refused: theme-card=<value>`, and
# with the theme-browser scene a name the tree's catalog lacks as
# `sandbox-shots: refused: theme-card=<value> tree=<rev or checkout>`.
# tui-edges, taken only when named and without sysmon or flyout-titles,
# whose btop stand-in it refuses, opens System Monitor's See all in the
# host's Ghostty running the host's btop, after `theme apply vgs` with
# btop's theme target alone and then with Ghostty's beside it, shot as
# tui-edges-<mode>-btop-alone and tui-edges-<mode>-btop-and-ghostty; it
# fails unless the first shows a band other than btop's background on all
# four sides of the window and the second none, with a Free meter in vgs's
# terminal.color2. It then applies the catalog's flexoki-light and shoots
# tui-edges-<mode>-btop-flexoki-light, which fails unless btop draws that
# package's palette.background, a Used meter in its terminal.color1, and
# each program name, MemB figure, per-core percentage and temperature in a
# colour that reads at 4.5:1 or more on it. A
# sheet of a themed TUI at its class size takes these shots. A host without
# xdg-terminal-exec, ghostty or btop leaves it not measured.
# theme-previews, taken only when named, applies each theme of
# --preview-themes, a comma list of package names, and shoots
# theme-preview-<name>: the theme's desktop with the standard bar widgets,
# the System window on Displays and Ghostty running tmux and Neovim from
# --dotfiles, a stow tree holding tmux/ and nvim/, with the Neovim plugins
# and tmux plugin of this user's home copied in. A catalog package's
# wallpaper is the file its --preview-wallpaper NAME=PATH names
# (scripts/theme-previews.sh passes them). A scene argument that is missing
# or names nothing is refused as `sandbox-shots: refused: <option>=<value>`.
# The lock scene enables vgs.lock with its sleep hook and idle watch off,
# locks the nested session, and shoots the lock screen, then after one and
# after ten wrong attempts. No password is typed and no PAM runs: the
# probe calls the service's `fail()`, the step PAM's refusal takes, and
# releases the lock with `sessionUnlock`, test code that never ships
# (docs/decisions/D062-native-lock-and-polkit-plugins.md). It disables the probe
# fixture, which holds `lock`, while it runs, when the settings scene
# enabled it.
# The greeter scene starts a second qs on shell/greeter.qml, as
# rows/greeter.sh does, over the smoke's fixture session directories, the
# mode's theme file and a stand-in getent that lists one fixture account,
# so no host account shows; no greetd socket exists, so nothing reaches
# PAM. It shoots once the view has chosen its session, then stops the host.
# The polkit scene builds the plugin's own Prompt.qml over a stand-in
# authentication flow the probe owns, in a stand-in of the summon host's
# overlay surface (polkitStandInOpen in scripts/smoke/Probe.qml), with
# vgs.polkit disabled, so no agent and no request exist. Nothing is typed,
# the stand-in's submit only counts, and the scene reads that no request
# went live and no authentication helper ran. The Settings scene enables
# vgs.automations over the harness's automations_stand_ins for its page's
# shot, so no call reaches the host's systemd user manager, and leaves its
# enablement as it found it: a tree with the setup steps of D061 enables
# the plugin for their Automations shot, which comes later in the same
# mode. It enables vgs.jarvis for its page's shot, once the daemon
# answers, over the J09 world the harness prepares for every sandbox
# (scripts/smoke/harness.sh), so the child reaches no audio, account,
# network or desktop, and disables it again.
# --hidden refuses every shot not taken with the nested window hidden on
# the host (SHOT_WINDOW_REQUIRE in scripts/smoke/shot.sh), so a run that
# exits 0 proves each shot's frame arrived while the window was hidden.
#
# PNGs go to DIR, which must lie under this checkout's tmp/; the default is
# tmp/sandbox-shots/<UTC time>[-REV][-x2]. shots.tsv beside them lists each shot
# with the sha256 of its file, how it was proved current, whether the host
# showed the nested window while it was taken, and whether the shot had
# chrome such as a tooltip or focus ring (shot.sh). desktop.tsv records
# each scene's sampled desktop
# before its surfaces open: scene, mode, source commit, x, y and RGB hex.
# --check-desktop-pair compares those records and exits 1 if a sample
# differs or a record is missing or unreadable. It starts no sandbox.
# items.tsv lists the box of the surface's items a scene read over IPC for a shot,
# as name, x, y, width and height in device pixels, which
# scripts/readme-shots.sh's item crop cuts: the theme browser's tabs,
# selected card and name in its installed shot. Each shot is of the
# nested compositor's first output alone, which the harness sized (grim
# -o), so an output a scene adds never enters a capture. The last line
# counts the shots taken with the window hidden as hidden=N; the host
# window's state is the one read this runner makes of the host compositor
# (scripts/smoke/host-window.sh).
#
# A scene with a missing tool names itself not measured and leaves the
# other scenes running. Exit 0 when every shot was taken.
# Exit 77 when a prerequisite is missing
# or when every failure was a grim that got no frame from the nested
# compositor (nested-window=not-drawn: the host sends a hidden window no
# frame callbacks unless a host window rule gives class aquamarine
# render_unfocused, docs/architecture/validation.md § Faults). Exit 1
# when any other step or shot failed.
set -euo pipefail

desktop_pair_check() { # BEFORE_DIR AFTER_DIR
  python3 - "$@" <<'PYDESKTOP'
import csv, pathlib, re, sys
def read(directory):
    rows = {}
    with (pathlib.Path(directory) / "desktop.tsv").open() as source:
        for scene, mode, commit, x, y, rgb in csv.reader(source, delimiter="\t"):
            key = (scene, mode)
            if key in rows or not re.fullmatch(r"[0-9a-f]{6}", rgb):
                raise ValueError("invalid desktop record")
            if not scene or not mode or not commit or int(x) < 0 or int(y) < 0:
                raise ValueError("invalid desktop record")
            rows[key] = (x, y, rgb)
    if not rows:
        raise ValueError("empty desktop record")
    return rows
try:
    before, after = map(read, sys.argv[1:])
    if before.keys() != after.keys():
        raise ValueError("desktop scene sets differ")
    for scene, mode in before:
        a, b = before[(scene, mode)], after[(scene, mode)]
        if a != b:
            print("sandbox-shots: desktop-pair=differ scene=%s mode=%s before=%s after=%s" %
                  (scene, mode, ",".join(a), ",".join(b)))
            sys.exit(1)
        print("sandbox-shots: desktop-pair=same scene=%s mode=%s rgb=%s" % (scene, mode, a[2]))
except (OSError, ValueError) as error:
    print("sandbox-shots: desktop-pair=unreadable cause=%s" % error, file=sys.stderr)
    sys.exit(1)
PYDESKTOP
}

if [[ ${1:-} == --check-desktop-pair ]]; then
  [[ $# -eq 3 ]] || { printf 'sandbox-shots: refused: desktop-pair-arguments\n' >&2; exit 2; }
  desktop_pair_check "$2" "$3"
  exit
fi

argv=("$@")
timeout_s=60
keep=false
out=""
rev=""
modes=""
scale=1
shot_size=""
theme_card="frankenstein"
preview_themes=()
declare -A preview_wallpaper=()
preview_dotfiles=""
page_ids=()
enable_ids=()
disable_ids=()
require_window=""
scenes=()
title_inventory=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --rev) rev="$2"; shift 2 ;;
    --modes) modes="$2"; shift 2 ;;
    --size) shot_size="$2"; shift 2 ;;
    --scale) scale="$2"; shift 2 ;;
    --theme-card) theme_card="$2"; shift 2 ;;
    --preview-themes) IFS=, read -r -a preview_themes <<<"$2"; shift 2 ;;
    --preview-wallpaper) preview_wallpaper["${2%%=*}"]="${2#*=}"; shift 2 ;;
    --dotfiles) preview_dotfiles="$2"; shift 2 ;;
    --pages) IFS=, read -r -a page_ids <<<"$2"; shift 2 ;;
    --enable) enable_arg="$2"; shift 2 ;;
    --disable) disable_arg="$2"; shift 2 ;;
    --hidden) require_window=hidden; shift ;;
    --timeout) timeout_s="$2"; shift 2 ;;
    --keep) keep=true; shift ;;
    --title-inventory) title_inventory=true; shift ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;

    sysmon|tui-edges|gallery|settings|wide-settings|focus|focus-open|flyout-titles|plugin-pages|manager|launcher|notifications|bar|panels|capture|keyhints|clipboard|voice|voice-setup|voice-elsewhere|dictation-setup|voice-keys|jarvis-console|jarvis-audit|jarvis-setup|elevenlabs-voices|jarvis-fleet|outdated|jarvis-causes|plugin-messages|page-links|tooltip-link|traffic|ai-usage|devtools|system|appearance|sounds|network|vpn|vpn-locked|bluetooth|printers|power|dialog|by-hand|reset|lock|polkit|greeter|narrow|theme-browser|wallpaper-browser|automations|cloudsync|tooltips|screensaver|theme-previews|setup-tab|updates|clone-voice) scenes+=("$1"); shift ;;
    *) printf 'sandbox-shots: refused: argument=%s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -n $modes ]] || { if [[ -n $rev ]]; then modes=dark; else modes=dark,light; fi; }
IFS=, read -r -a mode_list <<<"$modes"
for mode in "${mode_list[@]}"; do
  [[ $mode == dark || $mode == light || $mode == rounded ]] && continue
  [[ $mode =~ ^catalog-[a-z0-9][a-z0-9-]*$ ]] || { printf 'sandbox-shots: refused: mode=%s\n' "$mode" >&2; exit 2; }
done
[[ $scale == 1 || $scale == 2 ]] || { printf 'sandbox-shots: refused: scale=%s\n' "$scale" >&2; exit 2; }
[[ -z $shot_size || $shot_size =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]] || { printf 'sandbox-shots: refused: size=%s\n' "$shot_size" >&2; exit 2; }
[[ $theme_card =~ ^[a-z0-9][a-z0-9-]*$ ]] || { printf 'sandbox-shots: refused: theme-card=%s\n' "$theme_card" >&2; exit 2; }
# A plugin id has the shape of ID_PATTERN in shell/Core/PluginLogic.js.
plugin_id='[a-z0-9]+(\.[a-z0-9-]+)+'
if [[ -n ${enable_arg+set} ]]; then
  [[ $enable_arg =~ ^$plugin_id(,$plugin_id)*$ ]] || { printf 'sandbox-shots: refused: enable=%s\n' "$enable_arg" >&2; exit 2; }
  IFS=, read -r -a enable_ids <<<"$enable_arg"
fi
if [[ -n ${disable_arg+set} ]]; then
  [[ $disable_arg =~ ^$plugin_id(,$plugin_id)*$ ]] || { printf 'sandbox-shots: refused: disable=%s\n' "$disable_arg" >&2; exit 2; }
  IFS=, read -r -a disable_ids <<<"$disable_arg"
fi
for id in "${enable_ids[@]}"; do
  for disabled in "${disable_ids[@]}"; do
    [[ $id != "$disabled" ]] || { printf 'sandbox-shots: refused: state=%s reason=enabled-and-disabled\n' "$id" >&2; exit 2; }
  done
done

self="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo="$(cd -- "$(dirname -- "$self")/.." && pwd)"
checkout="$repo"
# No process this run starts may open an amdgpu node, so the run goes on
# only where none is visible: scripts/smoke/gpu-fence.sh.
"$checkout/scripts/smoke/gpu-fence.sh" --check || exec "$checkout/scripts/smoke/gpu-fence.sh" "$self" "${argv[@]}"
capture_source="${rev:-$(git -C "$checkout" rev-parse HEAD)}"
if [[ $title_inventory == true && -z $rev ]]; then
  # The inventory round stages and freezes its sources before capture.
  # A tree id binds uncommitted sources without labelling them as HEAD.
  capture_source="tree:$(git -C "$checkout" write-tree)"
fi
if ! command -v grim >/dev/null 2>&1; then
  printf 'sandbox-shots: status=not-measured missing=grim\n'
  exit 77
fi
source "$checkout/scripts/smoke/shot.sh"
source "$checkout/scripts/smoke/tree.sh"
[[ -n $out ]] || out="$checkout/tmp/sandbox-shots/$(date -u +%Y%m%dT%H%M%SZ)${rev:+-$rev}$([[ $scale == 1 ]] || echo "-x$scale")"
SHOT_DIR="$(shot_dir_under "$checkout" "$out")" || exit 2
if [[ -e $SHOT_DIR/shots.tsv ]]; then printf 'sandbox-shots: refused: out-dir-used=%s\n' "$SHOT_DIR" >&2; exit 2; fi

source_tree=""
# The harness's own cleanup removes the export on every exit once it has
# armed; this trap covers the prerequisite checks it makes before that.
trap '[[ -z $source_tree ]] || rm -rf -- "$source_tree"' EXIT
if [[ -n $rev ]]; then
  git -C "$checkout" rev-parse --verify --quiet "$rev^{commit}" >/dev/null || { printf 'sandbox-shots: refused: rev=%s\n' "$rev" >&2; exit 2; }
  mkdir -p -- "${TMPDIR:-$checkout/tmp}"
  source_tree="$(mktemp -d "${TMPDIR:-$checkout/tmp}/vgshell-shots-tree.XXXXXX")"
  # The fence removes it once its namespace has ended, after a SIGKILL too.
  printf '%s\n' "$source_tree" >>"$VGSHELL_FENCE_LEDGER"
  if ! tree_export "$checkout" "$rev" "$source_tree"; then
    rm -rf -- "$source_tree"
    printf 'sandbox-shots: refused: rev-export=%s\n' "$rev" >&2
    exit 2
  fi
fi

# Which plugin manager the tree ships picks the manager's scene.
tree="${source_tree:-$checkout}"
# What the tree draws decides how a scene reaches it, so a --rev tree from
# before a control existed is still captured: the bar's gear and the
# launcher's bar entry are BarItems or older items, and the Settings list
# may have no Clear search.
tree_has() { grep -qF -- "$2" "$tree/$1" 2>/dev/null; }
gear_type=IconButton
[[ -f $tree/shell/Ui/controls/BarItem.qml ]] && gear_type=BarItem
launcher_entry_item=false
tree_has shell/plugins/vgs.launcher/Widget.qml "BarItem {" && launcher_entry_item=true
has_clear_search=false
tree_has shell/plugins/vgs.settings/ListPage.qml '"Clear search"' && has_clear_search=true
# A tree whose plugin page has two pages draws Status and Requirements on
# Details; page_details moves the open page there, and an older tree's one
# page needs no move.
has_tab_pages=false
tree_has shell/plugins/vgs.settings/PluginPage.qml "TabPages {" && has_tab_pages=true
page_details() { ! "$has_tab_pages" || settings_details; }
# A tree whose plugin page draws a plugin's stored keys in the Setup section
# of its Settings tab offers Add key there; an older tree draws them on
# Details, in the entry's own section, with Connect. page_keys moves the
# open page to the tab that draws them.
has_setup_keys=false
tree_has shell/plugins/vgs.settings/Steps.js "function keyEntries(" && has_setup_keys=true
keys_action=Connect
! "$has_setup_keys" || keys_action="Add key"
# A tree whose plugin page has a Setup tab draws a plugin's setup steps,
# stored keys, setup screens and, beside them, its Requirements there; an
# older tree draws the first three on Settings. page_setup moves the open
# page to the tab that draws them.
has_setup_tab=false
tree_has shell/plugins/vgs.settings/Steps.js "function setupTab(" && has_setup_tab=true
page_setup() {
  if "$has_setup_tab"; then settings_setup; return; fi
  settings_tab_click Settings || fail "the click on the Settings tab failed"
  expect_poll "the plugin page shows Settings" 0 settings_tab
}
page_keys() { if "$has_setup_tab"; then settings_setup; else "$has_setup_keys" || page_details; fi; }
# A tree whose plugin page holds a save bar keeps a typed value until it is
# saved and asks before a page with one is left.
has_save_bar=false
tree_has shell/plugins/vgs.settings/PluginPage.qml "SaveBar {" && has_save_bar=true
card_hover_state=false
tree_has shell/Ui/layout/AngledCard.qml "property bool hovered" && card_hover_state=true
# A tree whose rescanPlugins names the scan revision is read once the scan
# has landed (the harness's rescan); an older one answers a bare `ok`.
tree_rescan() { # LABEL
  if tree_has shell/shell.qml "function scanRevision("; then rescan "$1"; else expect "$1" ok ipc shell rescanPlugins; fi
}
tooltip_widgets=()
for widget in "$tree"/shell/plugins/vgs.*/Widget.qml; do
  [[ -f $widget ]] && tooltip_widgets+=("$(basename -- "$(dirname -- "$widget")")")
done
manager_scene=""
if [[ -f $tree/shell/plugins/vgs.settings/manifest.json ]]; then manager_scene=settings
elif [[ -f $tree/shell/plugins/vgs.bar/Manager.qml ]]; then manager_scene=manager
fi
# scene_ships SCENE: whether the tree ships what SCENE draws. The dialog is
# the core's notice, raised for the checkout's acme.needs fixture.
ships_plugin() { local id; for id; do [[ -f $tree/shell/plugins/$id/manifest.json ]] || return 1; done; }
scene_ships() {
  case $1 in
    sysmon) ships_plugin vgs.sysmon vgs.settings ;;
    tui-edges) ships_plugin vgs.sysmon ;;
    settings|manager) [[ $1 == "$manager_scene" ]] ;;
    plugin-pages) [[ $manager_scene == settings ]] ;;
    setup-tab) [[ $manager_scene == settings && $has_setup_tab == true ]] ;;
    wide-settings) ships_plugin vgs.system vgs.displays vgs.mouse vgs.sound ;;
    gallery) ships_plugin vgs.gallery ;;
    focus) ships_plugin vgs.gallery vgs.settings ;;
    focus-open) ships_plugin vgs.settings vgs.network vgs.system ;;
    flyout-titles) ships_plugin vgs.sysmon vgs.settings vgs.network vgs.sound vgs.updates ;;
    launcher|notifications) ships_plugin "vgs.$1" ;;
    automations) ships_plugin vgs.automations ;;
    screensaver) ships_plugin vgs.screensaver ;;
    bar) ships_plugin vgs.bar vgs.launcher vgs.agent-warden vgs.updates vgs.themes ;;
    tooltips) scene_ships bar ;;
    panels) ships_plugin vgs.agent-warden vgs.updates vgs.themes ;;
    capture) ships_plugin vgs.capture ;;
    keyhints) ships_plugin vgs.keyhints vgs.launcher vgs.settings vgs.themes ;;
    clipboard) ships_plugin vgs.clipboard ;;
    jarvis-console|jarvis-audit) ships_plugin vgs.jarvis ;;
    voice) ships_plugin vgs.voice ;;
    voice-setup) ships_plugin vgs.voice vgs.settings ;;
    voice-elsewhere) ships_plugin vgs.voice vgs.settings && tree_has shell/plugins/vgs.voice/manifest.json '"dictation"' ;;
    dictation-setup) ships_plugin vgs.settings && { [[ -x $tree/bin/vgshell-dictation ]] || { [[ -n $rev ]] && ships_plugin vgs.voice; }; } ;;
    plugin-messages) ships_plugin vgs.clipboard vgs.lock vgs.notifications ;;
    page-links) [[ $manager_scene == settings ]] && tree_has shell/Ui/feedback/LinkText.qml '(page:' ;;
    tooltip-link) scene_ships bar ;;
    voice-keys) [[ $manager_scene == settings ]] && ships_plugin vgs.voice ;;
    elevenlabs-voices) [[ $manager_scene == settings && $has_tab_pages == true ]] && tree_has shell/plugins/vgs.jarvis/backend/ElevenLabs.js 'async function voices(' && ships_plugin vgs.jarvis ;;
    jarvis-setup|jarvis-fleet|outdated|jarvis-causes) [[ $manager_scene == settings && $has_tab_pages == true ]] && ships_plugin vgs.jarvis ;;
    clone-voice) [[ $manager_scene == settings && $has_setup_tab == true ]] && ships_plugin vgs.jarvis ;;
    updates) [[ $manager_scene == settings ]] && ships_plugin vgs.updates && tree_has shell/plugins/vgs.settings/PluginPage.qml "detailScreens" ;;
    ai-usage) ships_plugin vgs.ai-usage ;;
    traffic) ships_plugin vgs.traffic vgs.settings ;;
    devtools) ships_plugin vgs.devtools ;;
    system) ships_plugin vgs.system ;;
    appearance) ships_plugin vgs.system vgs.motion vgs.windows vgs.ui ;;
    sounds) ships_plugin vgs.system vgs.sounds vgs.notifications vgs.voice vgs.jarvis ;;
    network) ships_plugin vgs.system vgs.network ;;
    vpn) ships_plugin vgs.system vgs.vpn ;;
    vpn-locked) ships_plugin vgs.vpn ;;
    bluetooth) ships_plugin vgs.system vgs.bluetooth ;;
    printers) ships_plugin vgs.system vgs.printers ;;
    power) ships_plugin vgs.power ;;
    theme-browser|wallpaper-browser) ships_plugin vgs.themes ;;
    theme-previews) ships_plugin vgs.themes vgs.system vgs.displays vgs.network vgs.bluetooth vgs.sound vgs.ai-usage vgs.agent-warden vgs.updates ;;
    dialog|by-hand|reset) [[ -f $tree/shell/Hosts/NoticeHost.qml ]] ;;
    lock) ships_plugin vgs.lock ;;
    polkit) ships_plugin vgs.polkit ;;
    cloudsync) [[ $manager_scene == settings ]] && ships_plugin vgs.cloud-sync && tree_has shell/plugins/vgs.cloud-sync/CloudSyncLogic.js "function headline(" ;;
    greeter) ships_plugin vgs.greeter && [[ -f $tree/shell/greeter.qml ]] ;;
    narrow) scene_ships bar && scene_ships panels && scene_ships devtools && scene_ships dialog && scene_ships launcher && scene_ships notifications && scene_ships gallery ;;
    *) printf 'sandbox-shots: refused: scene=%s reason=unknown\n' "$1" >&2; exit 2 ;;
  esac
}
if [[ ${#scenes[@]} -eq 0 ]]; then
  if [[ -n $rev ]]; then
    scenes=(gallery)
    [[ -z $manager_scene ]] || scenes+=("$manager_scene")
  else
    for scene in gallery settings focus launcher notifications bar panels ai-usage devtools system network vpn bluetooth power dialog lock polkit greeter automations screensaver narrow; do
      if scene_ships "$scene"; then scenes+=("$scene"); fi
    done
  fi
fi
for scene in "${scenes[@]}"; do
  if ! scene_ships "$scene"; then
    printf 'sandbox-shots: refused: scene=%s tree=%s\n' "$scene" "${rev:-checkout}" >&2
    exit 2
  fi
  if [[ $scene == theme-previews ]]; then
    [[ ${#preview_themes[@]} -gt 0 ]] || { printf 'sandbox-shots: refused: preview-themes=\n' >&2; exit 2; }
    for name in "${preview_themes[@]}"; do
      [[ $name == vgs || -f $tree/themes/catalog/$name/theme.json ]] || { printf 'sandbox-shots: refused: preview-themes=%s\n' "$name" >&2; exit 2; }
      [[ $name == vgs || -f ${preview_wallpaper[$name]:-} ]] || { printf 'sandbox-shots: refused: preview-wallpaper=%s\n' "$name" >&2; exit 2; }
    done
    [[ -f $preview_dotfiles/tmux/.tmux.conf && -d $preview_dotfiles/nvim/.config/nvim ]] || { printf 'sandbox-shots: refused: dotfiles=%s\n' "$preview_dotfiles" >&2; exit 2; }
  fi
  if [[ $scene == theme-browser && ! -f $tree/themes/catalog/$theme_card/theme.json ]]; then
    printf 'sandbox-shots: refused: theme-card=%s tree=%s\n' "$theme_card" "${rev:-checkout}" >&2
    exit 2
  fi
done
for mode in "${mode_list[@]}"; do
  [[ $mode != catalog-* || -f $tree/themes/catalog/${mode#catalog-}/theme.json ]] || { printf 'sandbox-shots: refused: mode=%s\n' "$mode" >&2; exit 2; }
done
for id in "${enable_ids[@]}"; do
  ships_plugin "$id" || { printf 'sandbox-shots: refused: enable=%s tree=%s\n' "$id" "${rev:-checkout}" >&2; exit 2; }
done
for id in "${disable_ids[@]}"; do
  ships_plugin "$id" || { printf 'sandbox-shots: refused: disable=%s tree=%s\n' "$id" "${rev:-checkout}" >&2; exit 2; }
done

# shellcheck disable=SC2034 # the harness sourced below reads it
shell_output_scale="$scale"
# A plugin that holds `dictation`, as Voice does, has the core start a
# voxtype daemon, so no shell of a run finds the host's voxtype or its
# bridge (harness.sh's shell_hidden_commands); a scene that dictates stands
# the smoke's stand-in in the shell's own directory.
shell_hidden_commands=(voxtype voxtype-audio-bridge)
# The setup steps' shots draw each install button, which a Settings page
# offers only while its command is absent; on a host that has vsys, mise or
# the browser-policy writer they would draw none. The shell finds those
# three absent (harness.sh's shell_hidden_commands); a scene that stands
# its own stand-in for one, as panels does for vsys and devtools for mise,
# still finds it, and the shot of that button is then skipped. focus and
# jarvis-causes run the settings setup too (need_setup), which ships the
# chromium target: a later theme apply would run its reload hook were the
# writer found.
if [[ " ${scenes[*]} " =~ " "(settings|focus|jarvis-causes)" " && -f $tree/shell/plugins/vgs.settings/Steps.js ]]; then
  shell_hidden_commands+=(vsys mise vgshell-browser-policy)
fi
if [[ " ${scenes[*]} " == *" by-hand "* ]]; then
  # shellcheck disable=SC2034 # the harness sourced below reads it
  shell_hidden_commands+=(pacman paru yay apt-get dnf5 dnf nix flatpak mise sudo doas run0)
fi
# AI Usage reads the sign-ins through stand-ins alone, so the shell finds no
# host claude or codex.
if [[ " ${scenes[*]} " == *" ai-usage "* ]]; then
  shell_hidden_commands+=(claude codex)
fi
if [[ " ${scenes[*]} " == *" traffic "* ]]; then
  shell_hidden_commands+=(bandwhich)
fi
launcher_fixture=false
if [[ " ${scenes[*]} " == *" launcher "* || " ${scenes[*]} " == *" narrow "* ]]; then
  launcher_fixture=true
  harness_scene_only=true
fi
source "$checkout/scripts/smoke/harness.sh"
if [[ $launcher_fixture == true ]]; then
  # DesktopEntries otherwise reads /usr/share/applications. Plant before
  # its first load, with no host applications in the capture's data paths.
  mkdir -p -- "$home/.local/share/applications" "$sandbox/launcher-data"
  while IFS='|' read -r id name; do
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\n' "$name" >"$home/.local/share/applications/$id.desktop"
  done <<'APPS'
capture-shelly|Shelly
capture-sunshine|Sunshine
capture-avahi|Avahi SSH Server Browser
APPS
  shell_start_words+=(XDG_DATA_DIRS="$sandbox/launcher-data")
  start_shell "$repo" "$sandbox/qs.log" || exit 1
fi
source "$checkout/scripts/smoke/power-fakes.sh"
if [[ " ${scenes[*]} " == *" sysmon "* || " ${scenes[*]} " == *" flyout-titles "* ]]; then
  # Presence draws See all; the scene never invokes this stand-in.
  printf '#!/usr/bin/env bash\nexit 1\n' >"$shim/btop"
  chmod 755 "$shim/btop"
  # The private copy keeps the live poller from replacing posed readings.
  cp -- "$checkout/scripts/smoke/fixtures/sysmon/Service.qml" "$repo/shell/plugins/vgs.sysmon/Service.qml"
fi
# The harness copied the tree into the sandbox; the export is no longer
# read, and every later read of the tree reads the sandbox's copy.
[[ -z $source_tree ]] || rm -rf -- "$source_tree"
tree="$repo"
if grep -qF -- "Let VGS manage its Hyprland settings?" "$tree/shell/Core/HyprlandLayer.js" 2>/dev/null; then
  hypr_consent_connect "the screenshot sandbox answers Hyprland consent"
fi
# The plugin fixtures a scene installs: this checkout's, or with --rev that
# revision's, since its manifest judge is the one that reads them.
fixtures="$checkout/scripts/smoke/fixtures/plugins"
if [[ -n $rev ]]; then
  fixtures="$sandbox/rev-fixtures/scripts/smoke/fixtures/plugins"
  mkdir -p -- "$sandbox/rev-fixtures"
  git -C "$checkout" archive "$rev" scripts/smoke/fixtures/plugins | tar -x -C "$sandbox/rev-fixtures" || fail "the fixtures of $rev could not be exported"
fi

# The kind a first-party window has in the tree the sandbox runs: `window`
# since D044, or `panel` in a tree from before, which shipped it as a layer
# panel; and the surface it is drawn in, as surface_box names one.
summoned_kind() { # ID
  python3 -c 'import json,sys; print("window" if "window" in json.load(open(sys.argv[1]))["kinds"] else "panel")' "$tree/shell/plugins/$1/manifest.json"
}
summoned_name() { # ID
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$tree/shell/plugins/$1/manifest.json"
}
summoned_surface() { # KIND TITLE
  if [[ $1 == window ]]; then echo "window:$2"; else echo vgs:panel; fi
}
surface_count() { # SURFACE
  if [[ $1 == window:* ]]; then window_count "${1#window:}"; else layer_count "$1"; fi
}
gallery_kind="$(summoned_kind vgs.gallery)" || fail "the gallery's manifest is unreadable"
gallery_name="$(summoned_name vgs.gallery)" || fail "the gallery's name is unreadable"
gallery_surface="$(summoned_surface "$gallery_kind" "$gallery_name")"
# The manager's name is its window's title and its gear's label in every tree.
settings_kind=panel
settings_name=""
if [[ $manager_scene == settings ]]; then
  settings_kind="$(summoned_kind vgs.settings)" || fail "the Settings manifest is unreadable"
  settings_name="$(summoned_name vgs.settings)" || fail "the Settings name is unreadable"
fi
settings_surface="$(summoned_surface "$settings_kind" "$settings_name")"
has_agent_warden=false
has_bar_plugin=false
has_automations=false
has_jarvis=false
has_scratchpads=false
has_webapps=false
has_setup_steps=false
has_voice=false
has_ai_usage=false
has_tray=false
has_sudo=false
[[ -f $tree/shell/plugins/vgs.settings/Steps.js ]] && has_setup_steps=true
[[ -f $tree/shell/plugins/vgs.agent-warden/manifest.json ]] && has_agent_warden=true
[[ -f $tree/shell/plugins/vgs.automations/manifest.json ]] && has_automations=true
[[ -f $tree/shell/plugins/vgs.jarvis/manifest.json ]] && has_jarvis=true
[[ -f $tree/shell/plugins/vgs.scratchpads/manifest.json ]] && has_scratchpads=true
[[ -f $tree/shell/plugins/vgs.webapps/manifest.json ]] && has_webapps=true
[[ -f $tree/shell/plugins/vgs.bar/manifest.json ]] && has_bar_plugin=true
[[ -f $tree/shell/plugins/vgs.voice/manifest.json ]] && has_voice=true
[[ -f $tree/shell/plugins/vgs.ai-usage/manifest.json ]] && has_ai_usage=true
[[ -f $tree/shell/plugins/vgs.tray/manifest.json ]] && has_tray=true
[[ -f $tree/shell/plugins/vgs.sudo/manifest.json ]] && has_sudo=true
settings_count() { surface_count "$settings_surface"; }

SHOT_RUNTIME_DIR="$rt_dir"
if ! SHOT_SOCKET="$(shot_socket "$rt_dir" "$nested_socket" "$host_socket")"; then
  fail "the nested socket is not safe to capture"
  exit 1
fi
ok "grim captures only $SHOT_SOCKET"
# Each shot records whether the host showed the nested window while it was
# taken, read from the host compositor by read-only requests. The
# fence's pid namespace hides the nested compositor's host pid, so its
# window is an aquamarine stableId the host lists now and did not list
# before the harness started the compositor (host_windows_since). Other
# sandboxes that started since add windows too. Hyprland gives each new
# window the next value of one counter that starts at 0x18000000 and
# prints it as hex (src/desktop/view/window/WindowMetadata.cpp), so every
# id has eight digits, string order is creation order, and the lowest new
# id is the first window made after that read: this run's, unless another
# compositor made its window between that read and this one's. With no
# new window each shot records unreadable.
source "$checkout/scripts/smoke/host-window.sh"
source "$checkout/scripts/smoke/webapps-browsers.sh"
nested_window_id() {
  local new entry id=""
  local -a entries
  new="$(host_windows_since)" || return 1
  [[ $new != none ]] || return 1
  IFS=';' read -ra entries <<<"$new"
  for entry in "${entries[@]}"; do
    entry="${entry%% *}"
    if [[ -z $id || $entry < $id ]]; then id="$entry"; fi
  done
  printf '%s\n' "$id"
}
nested_window_state() {
  [[ -n $nested_window ]] || { echo unreadable; return 1; }
  host_window_state "$nested_window"
}
nested_window="$(nested_window_id)" || nested_window=""
printf 'shots: nested-window=%s\n' "${nested_window:-unknown}"
SHOT_WINDOW_READER=nested_window_state
SHOT_WINDOW_REQUIRE="$require_window"
# Hyprland's own notice that it was not started through start-hyprland
# would sit over the top right of every shot.
expect "the nested compositor's notices are dismissed" ok hypr dismissnotify
main_name="$(first_name)" || { fail "the monitor is unreadable"; exit 1; }
# Every shot is of this output alone, so an output a scene adds, such as a
# headless one with no size, never enters a capture.
SHOT_OUTPUT="$main_name"
ok "grim captures only the output $SHOT_OUTPUT"
# --size: the output holds WxH logical pixels at the run's scale for every
# scene. At scale 2 the harness's own hold ends first and the run's mode
# becomes the doubled size, which a scene that leaves the hold returns to.
if [[ -n $shot_size ]]; then
  size_mode="$shot_size"
  [[ $scale == 1 ]] || size_mode="$((${shot_size%x*} * 2))x$((${shot_size#*x} * 2))"
  [[ $scale == 1 ]] || release_mode "the run's scale-2 hold ends for the requested shot size" "$main_name" "$shell_output_mode" "$scale"
  hold_mode "the nested output holds the requested shot size" "$main_name" "$size_mode" "$scale"
  [[ $scale == 1 ]] || shell_output_mode="$size_mode"
fi
# The monitor's logical size, the layout coordinates the pointer helper
# takes, and the space the bar reserves at its top.
read -r mon_w mon_h bar_reserved < <(hypr -j monitors | python3 -c 'import json,sys; m=json.load(sys.stdin)[0]; print(round(m["width"] / m["scale"]), round(m["height"] / m["scale"]), m["reserved"][1])')
run_w="$mon_w" run_h="$mon_h"

undrawn=0
unmeasured=0
# hold_left: what the output reads in place of the held mode.
hold_left() {
  echo "${mode_hold[0]} reads $(mode_scale_of "${mode_hold[0]}" || echo unreadable), not the held ${mode_hold[1]}; a host resize or refocus, or another writer, reset it"
}
# settle_hold: the output reads the run's held mode, if it holds one,
# before a shot or a hover. A host configure of the nested window resets
# the mode at any moment, and the reset stays until a rule takes the mode
# again (held_mode_state in scripts/smoke/mode-hold.sh), so every shot and
# hover after it would meet the reset output. A reset is taken again
# through hold_restore, and the pointer goes back to pointer_at, where the
# scene left it, since the reset moved it and the restore does not.
# Returns 1, printing why, when the mode cannot be taken again or the
# output cannot be read.
settle_hold() {
  local state restored x y
  [[ ${#mode_hold[@]} -gt 0 ]] || return 0
  state="$(held_mode_state)"
  case $state in
    held) return 0 ;;
    reset) printf '  reset %s; the held mode is taken again\n' "$(hold_left)" ;;
    *) printf '  reset %s reads %s\n' "${mode_hold[0]}" "$state"; return 1 ;;
  esac
  if ! restored="$(hold_restore)"; then
    printf '        %s\n' "$restored"
    return 1
  fi
  [[ -n $pointer_at ]] || return 0
  read -r x y <<<"$pointer_at"
  hover "$x" "$y" || { echo "        the pointer did not go back to $pointer_at"; return 1; }
}
shot_chrome_read() { ipc smoke shotChrome false; }
shot_chrome_clear() { ipc smoke shotChrome true; }
# clean_shot_chrome: the shot chrome cleared and polled until it reads
# `clean`, else its last word. The 5 s bound outlasts a scroll bar's
# settling, Theme.scrollArea.fadeDelay (800 ms) after the last scroll plus
# its Theme.scrollArea.fade.
clean_shot_chrome() {
  local state=unreadable
  for _ in $(seq 1 50); do
    state="$(shot_chrome_clear)" || state=unreadable
    [[ $state == clean ]] && return 0
    sleep 0.1
  done
  printf '%s\n' "$state"
  return 1
}
# take_raw NAME: one shot. While the run holds a mode, shot_held settles it
# first and takes the shot once more when the output left it while shot
# waited for a settled frame, so a PNG never shows a reset output under a
# held mode's name.
take_raw() { # NAME
  local status=0
  if [[ ${#mode_hold[@]} -eq 0 ]]; then
    shot "$1" || status=$?
  else
    shot_held "$1" held_mode_state settle_hold || status=$?
  fi
  case $status in
    0)
      if [[ $title_inventory == true ]]; then
        local inventory
        if inventory="$(ipc smoke titleInventory)"; then
          printf 'sandbox-shots: title-inventory source=%s shot=%s phase=after-frame value=%s\n' "$capture_source" "$1" "$inventory"
          printf '%s\t%s\n' "$1" "$inventory" >>"$SHOT_DIR/title-inventory.tsv"
          expect "the $1 titled panes keep their last row reachable" True py_reply 'import json,sys; rows=json.load(sys.stdin); print(isinstance(rows,list) and all(row["end"]["lastRowVisible"] and row["end"]["footerFits"] for row in rows))' <<<"$inventory"
        else
          fail "the $1 titled pane inventory is unreadable"
        fi
      fi
      ;;
    2) undrawn=$((undrawn + 1)); fail "grim got no frame from the nested compositor for $1" ;;
    3) fail "shot $1 not taken: the held mode could not be taken again" ;;
    4) fail "shot $1 not accepted: $(hold_left)" ;;
    *) fail "shot $1 failed" ;;
  esac
}
take_posed() { # NAME
  SHOT_CHROME_READER=shot_chrome_read SHOT_CHROME_REQUIRE= take_raw "$1"
}
take() { # NAME
  local chrome
  park_pointer
  if ! chrome="$(clean_shot_chrome)"; then
    fail "shot $1 not taken: chrome $chrome"
    return
  fi
  SHOT_CHROME_READER=shot_chrome_read SHOT_CHROME_REQUIRE=clean take_raw "$1"
}
# record_item NAME BOX: BOX, `[x, y, w, h]` in logical pixels of the
# first output, as shot NAME's line in items.tsv, in device pixels with
# its edges rounded outward.
record_item() {
  local line
  if line="$(python3 -c 'import json,math,sys
x, y, w, h = json.loads(sys.argv[2]); s = int(sys.argv[3])
left, top = math.floor(x * s), math.floor(y * s)
assert left >= 0 and top >= 0 and w > 0 and h > 0
print("%s\t%d\t%d\t%d\t%d" % (sys.argv[1], left, top, math.ceil((x + w) * s) - left, math.ceil((y + h) * s) - top))' "$1" "$2" "$scale" 2>/dev/null)"; then
    printf '%s\n' "$line" >>"$SHOT_DIR/items.tsv"
  else
    fail "shot $1: its item box is unreadable: $2"
  fi
}
centre_of() { python3 -c 'import json,sys; t=sys.argv[1]; r=json.loads(t) if t.startswith("[") else None; print("%d %d" % (r[0] + r[2] / 2, r[1] + r[3] / 2) if r else "none")' "$1"; }
# hover_on LABEL HOST ID TYPE TEXT [SURFACE]: the pointer on the centre of
# that item, held until the item reports the pointer over it twice in a
# row, so a hover shot shows the hover state; an item that has no hover
# state of its own is hover_text's. Both go through point_item in
# scripts/smoke/harness.sh; a window's item needs SURFACE, the window's
# surface name, since its box is read in the window.
# window_point SURFACE HOST ID TYPE TEXT: that window item's centre on the
# output, as `X Y`.
# arriving by two motions: the launcher follows the pointer only once it
# has moved over the list (selectFromPointer in its Launcher.qml).
window_point() {
  local rect
  rect="$(ipc smoke windowGeometry "$2" "$3" "$4" "$5")" && [[ $rect == \[* ]] || return 1
  at_centre "$1" "$rect"
}
# The hover helpers and park_pointer settle the held mode first: an item's
# position read on a reset output is not where it sits once the mode is
# taken again for the shot.
hover_on() {
  settle_hold || { fail "$1: the held mode could not be taken again"; return 1; }
  if [[ -z ${6:-} ]]; then
    if ! point_item "$2" "$3" "$4" "$5" >/dev/null; then fail "$1: $4 \"$5\" under $2 $3 never reported the pointer"; return 1; fi
  elif ! point_item "$6" "$2" "$3" "$4" "$5" >/dev/null; then
    fail "$1: $4 \"$5\" in $6 never reported the pointer"; return 1
  fi
  ok "$1"
}
# hover_text LABEL HOST ID TYPE TEXT: the pointer on the centre of a text
# that has no hover state; the caller proves the state the hover drives.
hover_text() {
  local label="$1" rect at="" x y
  settle_hold || { fail "$label: the held mode could not be taken again"; return 1; }
  for _ in $(seq 1 25); do
    rect="$(ipc smoke itemGeometry "$2" "$3" "$4" "$5")" && at="$(centre_of "$rect")" && [[ $at != none ]] && break
    at=""; sleep 0.2
  done
  if [[ -z $at ]]; then fail "$label: no $4 \"$5\" under $2 $3"; return 1; fi
  read -r x y <<<"$at"
  if ! hover "$((x - 6))" "$y" || ! hover "$x" "$y"; then fail "$label: the hover failed"; return 1; fi
  ok "$label"
}
park_pointer() {
  if settle_hold; then
    hover "$((mon_w - 2))" "$((mon_h - 2))" || fail "parking the pointer failed"
  else
    fail "parking the pointer: the held mode could not be taken again"
  fi
}
# narrow_begin: the nested output holds a mode 480 by 720 logical pixels at
# the run's scale, and the pointer helpers take that size, until
# narrow_end gives the run's mode back. At scale 2 the run's mode is the
# one the harness held before the shell started, since the monitor may
# read a reset one by now; at scale 1 it is the monitor's own mode.
narrow_main_mode=""
narrow_begin() {
  if [[ $scale == 2 ]]; then
    narrow_main_mode="$shell_output_mode"
  else
    narrow_main_mode="$(first_mode)" || fail "the monitor's mode is unreadable"
  fi
  [[ $scale == 1 ]] || release_mode "the run's scale-2 hold ends for the narrow monitor" "$main_name" "$narrow_main_mode" "$scale"
  hold_mode "the monitor is made narrower than the window" "$main_name" "$((480 * scale))x$((720 * scale))" "$scale"
  expect_poll "the monitor is 480 logical pixels wide" 480 first_width
  mon_w=480 mon_h=720
}
narrow_end() {
  release_mode "the run's mode is restored" "$main_name" "$narrow_main_mode" "$scale"
  [[ $scale == 1 ]] || hold_mode "the monitor holds its scale-2 mode again" "$main_name" "$narrow_main_mode" "$scale"
  expect_poll "the monitor has its width back" "$run_w" first_width
  mon_w="$run_w" mon_h="$run_h"
}

theme_file="$home/.config/vgshell/theme.json"
set_mode() { # dark|light|rounded|catalog-NAME
  local name
  case $1 in
    catalog-*) cp -- "$repo/themes/catalog/${1#catalog-}/theme.json" "$theme_file.tmp"; name="${1#catalog-}" ;;
    dark) printf '{ "schemaVersion": 1, "name": "vgs", "tokens": {} }\n' >"$theme_file.tmp"; name=vgs ;;
    rounded) printf '{ "schemaVersion": 1, "name": "rounded", "tokens": { "radius": { "sm": 6, "md": 12, "lg": 16 } } }\n' >"$theme_file.tmp"; name=rounded ;;
    light) cp -- "$repo/themes/catalog/flexoki-light/theme.json" "$theme_file.tmp"; name=flexoki-light ;;
  esac
  mv -T -- "$theme_file.tmp" "$theme_file"
  expect_poll "the $1 theme ($name) is published" "$name" ipc smoke themeName
}

# Sample before opening the scene: a modal scrim changes the displayed
# pixel, so its colour cannot identify the desktop behind it.
scene_desktop() { # SCENE MODE
  local sample enabled
  bg_state_names "$repo/themes/vgs/backgrounds/black.png" || return 1
  enabled="$(plugin_enabled vgs.themes)" || return 1
  case $enabled in
    True)
      expect_poll "the $1 $2 desktop image is ready" "$repo/themes/vgs/backgrounds/black.png ready" background_image_on "$main_name"
      expect_poll "the $1 $2 desktop draws black" 000000 pixel 100 100 ;;
    False) expect_poll "the $1 $2 desktop has no Themes background" False record_exists vgs.themes ;;
    *) fail "the $1 $2 background owner's enablement is unreadable: $enabled"; return 1 ;;
  esac
  sample="$(pixel 100 100)" || return 1
  [[ $sample =~ ^[0-9a-f]{6}$ && ( $enabled == False || $sample == 000000 ) ]] || { fail "the $1 $2 desktop sample is $sample"; return 1; }
  printf '%s\t%s\t%s\t100\t100\t%s\n' "$1" "$2" "$capture_source" "$sample" >>"$SHOT_DIR/desktop.tsv"
  printf 'sandbox-shots: desktop scene=%s mode=%s source=%s sample=100,100 rgb=%s\n' "$1" "$2" "$capture_source" "$sample"
}

# The gallery's field in error, scrolled to a third of the way down the
# view and clicked, so the shot shows its focus ring in the error colour.
gallery_error_focus() { # MODE
  local box y x
  ipc smoke scrollTo "$gallery_kind" vgs.gallery 0 >/dev/null || { fail "the gallery did not scroll to its top"; return; }
  box="$(ipc smoke windowGeometry "$gallery_kind" vgs.gallery TextField taken)"
  [[ $box == \[* ]] || { fail "the gallery's field in error has no box: $box"; return; }
  y="$(python3 -c 'import json,sys; print(max(0, int(json.loads(sys.argv[1])[1]) - 200))' "$box")"
  ipc smoke scrollTo "$gallery_kind" vgs.gallery "$y" >/dev/null || { fail "the gallery did not scroll to its field in error"; return; }
  read -r x y < <(window_point "$gallery_surface" "$gallery_kind" vgs.gallery TextField taken) || { fail "the gallery's field in error has no box on the output"; return; }
  if hover "$((x - 1))" "$y" && click "$x" "$y"; then
    expect_poll "the field in error holds the keyboard" true ipc smoke activeFocusIn "$gallery_kind" vgs.gallery
    take_posed "gallery-$1-error-focus"
  else
    fail "the click on the gallery's field in error failed"
  fi
  park_pointer
}

# The gallery's menu opened from its button, the pointer on its first
# entry, 20 px under the button, which highlights it.
gallery_menu_current() { ipc smoke menus "$gallery_kind" vgs.gallery | py_reply 'import json,sys; m=[x for x in json.load(sys.stdin) if x["opened"]]; print(json.dumps(m[0]["current"]) if len(m) == 1 else "open=%d" % len(m))'; }
gallery_menu_first() { # MODE
  local box y x
  ipc smoke scrollTo "$gallery_kind" vgs.gallery 0 >/dev/null || { fail "the gallery did not scroll to its top"; return; }
  if ! box="$(ipc smoke windowGeometry "$gallery_kind" vgs.gallery Button "Open a menu")" || [[ $box != \[* ]]; then fail "the gallery's menu button has no box: ${box:-}"; return; fi
  y="$(python3 -c 'import json,sys; print(max(0, int(json.loads(sys.argv[1])[1]) - 200))' "$box")"
  ipc smoke scrollTo "$gallery_kind" vgs.gallery "$y" >/dev/null || { fail "the gallery did not scroll to its menu button"; return; }
  read -r x y < <(window_point "$gallery_surface" "$gallery_kind" vgs.gallery Button "Open a menu") || { fail "the gallery's menu button has no box on the output"; return; }
  if hover "$((x - 1))" "$y" && click "$x" "$y" && box="$(ipc smoke windowGeometry "$gallery_kind" vgs.gallery Button "Open a menu")"; then
    read -r x y < <(at_centre "$gallery_surface" "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(json.dumps([r[0], r[1] + r[3], 80, 40]))' "$box")")
    # Opening disarms the pointer, which takes the highlight once it moves
    # over the menu: two motions onto the entry.
    hover "$((x - 6))" "$y" && hover "$x" "$y" || fail "the hover on the gallery menu's first entry failed"
    expect_poll "the pointer highlights the gallery menu's first entry" '"Rescan plugins"' gallery_menu_current
    take_posed "gallery-$1-menu"
    type_keys -k Escape || fail "sending Escape to the gallery's menu failed"
  else
    fail "the click on the gallery's menu button failed"
  fi
  park_pointer
}

# One shot per page of the gallery's scrolling list, a page's height less
# 40 px apart so each page repeats the last lines of the one before, up to
# gallery_pages pages.
gallery_pages=12
scene_gallery() { # MODE
  local page=1 y=0 at cy ch h
  expect "the gallery summons" ok ipc shell summon "$gallery_kind" vgs.gallery '{}'
  expect_poll "the gallery maps its surface" 1 surface_count "$gallery_surface"
  expect_poll "the gallery draws every component" '[]' ipc smoke galleryMissing "$gallery_kind" vgs.gallery
  while (( page <= gallery_pages )); do
    at="$(ipc smoke scrollTo "$gallery_kind" vgs.gallery "$y")" || at=""
    if [[ $at != "["* ]]; then fail "the gallery did not scroll: ${at:-no reply}"; break; fi
    read -r cy ch h < <(python3 -c 'import json,sys; print(*(int(v) for v in json.loads(sys.argv[1])))' "$at")
    # The Gallery's focus examples deliberately draw rings when reached.
    # Inventory images retain those examples rather than judge them as chrome.
    if [[ $title_inventory == true ]]; then take_posed "gallery-$1-p$page"; else take "gallery-$1-p$page"; fi
    (( cy + h < ch )) || break
    y=$(( cy + h - 40 )); page=$(( page + 1 ))
  done
  if [[ $title_inventory == true ]]; then
    ipc smoke titledPaneScrollEnd "$gallery_kind" vgs.gallery >/dev/null || fail "the Gallery's final row was not reached"
    take_posed "gallery-$1-last-row"
  fi
  gallery_error_focus "$1"
  gallery_menu_first "$1"
  if [[ $title_inventory == true ]]; then
    ipc smoke revealText "$gallery_kind" vgs.gallery Button "Open a popover" >/dev/null || fail "the Gallery popover launcher was not revealed"
    click_in "$gallery_surface" "$gallery_kind" vgs.gallery Button "Open a popover" || fail "the Gallery title popover did not open"
    gallery_title_popover() { ipc smoke titleInventory | py_reply 'import json,sys; print(any(row["opened"]["title"]=="A popover" for row in json.load(sys.stdin)))'; }
    expect_poll "the Gallery popover title is visible" True gallery_title_popover
    take_posed "gallery-$1-titled-popover-opened"
    type_keys -k Escape || fail "the Gallery title popover did not close"
    expect_poll "the Gallery title popover closes" False gallery_title_popover
    ipc smoke revealText "$gallery_kind" vgs.gallery Button "Open modal dialog" >/dev/null || fail "the Gallery modal launcher was not revealed"
    click_in "$gallery_surface" "$gallery_kind" vgs.gallery Button "Open modal dialog" || fail "the Gallery modal did not open"
    gallery_title_modal() { layer_count vgs:dialog; }
    expect_poll "the Gallery titled modal maps" 1 gallery_title_modal
    take_posed "gallery-$1-titled-modal-opened"
    type_keys -k Tab || fail "native Tab in the Gallery modal failed"
    take_posed "gallery-$1-titled-modal-tab"
    type_keys -k Escape || fail "the Gallery titled modal did not close"
    expect_poll "the Gallery titled modal closes" 0 gallery_title_modal
  fi
  expect "the gallery hides" ok ipc shell hide "$gallery_kind" vgs.gallery
  expect_poll "the gallery's surface is gone" 0 surface_count "$gallery_surface"
}

settings_page() { ipc smoke readInstance "$settings_kind" vgs.settings page; }
settings_menu_hovered() { ipc smoke menus "$settings_kind" vgs.settings | py_reply 'import json,sys; m=json.load(sys.stdin); print(len(m) == 1 and m[0].get("barHovered") is True)'; }
settings_menu_highlighted() { ipc smoke menus "$settings_kind" vgs.settings | py_reply 'import json,sys; m=json.load(sys.stdin); print(len(m) == 1 and m[0]["current"] is not None)'; }
settings_menu_open() { ipc smoke menus "$settings_kind" vgs.settings | python3 -c 'import json,sys; m=json.load(sys.stdin); print(len(m) == 1 and m[0]["opened"])'; }
# Whether the pointer took the title's menu's highlight from the checked
# entry, which opening highlights.
settings_menu_pointed() { ipc smoke menus "$settings_kind" vgs.settings | py_reply 'import json,sys; m=json.load(sys.stdin); print(len(m) == 1 and m[0]["current"] is not None and m[0]["current"] not in m[0]["checked"])'; }
# The page's one scroll area as the probe reads it.
settings_scroll() { ipc smoke scrollAreas "$settings_kind" vgs.settings | python3 -c 'import json,sys; a=json.load(sys.stdin); print(json.dumps(a[0]) if len(a) == 1 else "areas=%d" % len(a))'; }
# settings_scroll_set Y: the page's scroll area moved to contentY Y through
# the probe's scrollTo, held inside its content; prints where it landed.
settings_scroll_set() { # Y
  ipc smoke scrollTo "$settings_kind" vgs.settings "$1" | py_reply 'import json,sys; print(int(json.load(sys.stdin)[0]))'
}
# settings_bar_box AREA: the bar of AREA, a settings_scroll reading, on
# the output as [x, y, w, h]: its window box plus the window's place.
settings_bar_box() { # AREA
  local box
  box="$(surface_box "$settings_surface")" && [[ $box == \[* ]] || { echo "window=${box:-unread}"; return 1; }
  python3 -c 'import json,sys; o=json.loads(sys.argv[1]); b=json.loads(sys.argv[2])["bar"]; print(json.dumps([o[0] + b[0], o[1] + b[1], b[2], b[3]]))' "$box" "$1"
}
# shot_region_same A B BOX: `same` when shots A and B, PNGs under SHOT_DIR,
# hold the same pixels in BOX, [x, y, w, h] in logical pixels of the
# output, in device pixels with its edges rounded outward as record_item
# rounds them; else `differ pixels=N`.
shot_region_same() { # A B BOX
  python3 -c 'import json,math,sys
from PIL import Image
x, y, w, h = json.loads(sys.argv[3]); s = int(sys.argv[4])
left, top = math.floor(x * s), math.floor(y * s)
box = (left, top, math.ceil((x + w) * s), math.ceil((y + h) * s))
a, b = (Image.open(path).convert("RGBA").crop(box).tobytes() for path in sys.argv[1:3])
if a == b:
    print("same")
else:
    print("differ pixels=%d" % sum(a[i:i + 4] != b[i:i + 4] for i in range(0, len(a), 4)))' "$SHOT_DIR/$1.png" "$SHOT_DIR/$2.png" "$3" "$scale"
}
settings_drag_page_down() { # LABEL
  local area tx ty
  if area="$(settings_scroll)" && [[ $area == \{* ]]; then
    read -r tx ty < <(at_centre "$settings_surface" "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["thumb"]))' "$area")")
    drag "$tx" "$ty" "$tx" "$((ty + 120))" || { fail "the drag on $1's thumb failed"; return 1; }
    hover "$tx" "$((ty + 120))" || { fail "the hover on $1's dragged thumb failed"; return 1; }
    expect_poll "the drag on $1's thumb scrolls it down" False settings_at_top
    [[ $(settings_at_top) == False ]]
    return
  fi
  fail "$1 scroll area is unreadable: ${area:-}"
  return 1
}
# settings_page_fit: `overflows` when the page's one scroll area holds
# content taller than its view by the half pixel ScrollBar.qml's `needed`
# counts, with its bar shown, and `fits` when it does not, with its bar
# hidden; a bar that disagrees with the heights, or an unreadable area,
# answers what was read.
settings_page_fit() {
  local area
  area="$(settings_scroll)" && [[ $area == \{* ]] || { echo "area=${area:-unread}"; return; }
  python3 -c 'import json,sys
a = json.loads(sys.argv[1])
over = a["contentHeight"] - a["height"] >= 0.5
print(("overflows" if over else "fits") if over == a["barVisible"] else "contentHeight=%s height=%s barVisible=%s" % (a["contentHeight"], a["height"], a["barVisible"]))' "$area" || echo "area=$area"
}
# settings_page_settled: `settled` once settings_page_fit reads overflows or
# fits, else that reading: a card still growing toward its page holds its
# bar hidden over an overflow (Pane.cardGrowing).
settings_page_settled() {
  local fit
  fit="$(settings_page_fit)"
  case $fit in overflows | fits) echo settled ;; *) echo "$fit" ;; esac
}
# settings_scrolled_shot MODE NAME LABEL: the shown page dragged down its
# bar as settings-MODE-NAME-scrolled when it overflows its view; a page that
# fits takes no scrolled shot, since a drag there moves nothing.
settings_scrolled_shot() {
  local fit
  expect_poll "$3's fit settles" settled settings_page_settled
  fit="$(settings_page_fit)"
  case $fit in
    overflows) if settings_drag_page_down "$3"; then take "settings-$1-$2-scrolled"; fi ;;
    fits) ok "$3 fits its view: no settings-$1-$2-scrolled shot" ;;
    *) fail "$3's fit is unreadable: $fit" ;;
  esac
}
settings_at_top() { settings_scroll | python3 -c 'import json,sys; t=sys.stdin.read(); a=json.loads(t) if t.startswith("{") else None; print(a is not None and int(a["contentY"]) == 0)'; }
settings_close() {
  expect "the Settings window closes" ok ipc shell hide "$settings_kind" vgs.settings
  expect_poll "the Settings window is gone" 0 settings_count
}
# settings_section HEADING [SCOPE_TYPE SCOPE_TEXT] TYPE TEXT: the page's
# section headed HEADING, through the item TYPE TEXT, inside the first
# shown SCOPE_TYPE that draws SCOPE_TEXT when one is named, in its scroll
# area's content coordinates, as
# `START END HEIGHT`: the heading's top, that item's bottom, and the area's
# height. The bar spans the area, so its top is the area's.
settings_section() {
  local area header last
  area="$(settings_scroll)" && [[ $area == \{* ]] || { echo "area=${area:-unread}"; return 1; }
  header="$(ipc smoke windowGeometry "$settings_kind" vgs.settings SectionHeader "$1")" && [[ $header == \[* ]] || { echo "heading=${header:-unread}"; return 1; }
  if [[ $# -eq 5 ]]; then last="$(ipc smoke scopedWindowGeometry "$settings_kind" vgs.settings "$2" "$3" "$4" "$5")"
  else last="$(ipc smoke windowGeometry "$settings_kind" vgs.settings "$2" "$3")"
  fi
  [[ $last == \[* ]] || { echo "last-line=${last:-unread}"; return 1; }
  python3 -c 'import json,sys
a, h, l = (json.loads(v) for v in sys.argv[1:4])
top, y = a["bar"][1], a["contentY"]
print(int(h[1] - top + y), int(l[1] + l[3] - top + y), int(a["height"]))' "$area" "$header" "$last"
}
# settings_scroll_to Y: the page's scroll area moved to about contentY Y,
# held inside its content, by dragging its bar's thumb as the scrolled
# probe page's shot does: the thumb travels the bar less its own length
# while the content travels its height less the area's.
settings_scroll_to() {
  local area move tx ty
  area="$(settings_scroll)" && [[ $area == \{* ]] || return 1
  move="$(python3 -c 'import json,sys
a, want = json.loads(sys.argv[1]), int(sys.argv[2])
most = a["contentHeight"] - a["height"]
travel = a["bar"][3] - a["thumb"][3]
print(0 if most <= 0 or travel <= 0 else round((max(0, min(want, most)) - a["contentY"]) * travel / most))' "$area" "$1")" || return 1
  [[ $move -ne 0 ]] || return 0
  read -r tx ty < <(at_centre "$settings_surface" "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["thumb"]))' "$area")") || return 1
  drag "$tx" "$ty" "$tx" "$((ty + move))"
}
# Whether every status row of plugin ID's page is reported.
page_reported() { # ID
  ipc smoke readInstance "$settings_kind" vgs.settings plugins | python3 -c 'import json,sys; r=[p for p in json.load(sys.stdin) if p["id"] == sys.argv[1]]; print(len(r) == 1 and len(r[0]["status"]) > 0 and all(s["report"] == "reported" for s in r[0]["status"]))' "$1"
}
# The number of status rows the Settings window holds for plugin ID, or
# `absent`: a status entry whose value is unreported still holds its row.
page_status_rows() { # ID
  ipc smoke readInstance "$settings_kind" vgs.settings plugins | py_reply 'import json,sys; r=[p for p in json.load(sys.stdin) if p["id"] == sys.argv[1]]; print(len(r[0]["status"]) if len(r) == 1 else "absent")' "$1"
}
# `ready` once the Jarvis service's first child has answered hello, as the
# probe reads it (jarvisProcess in scripts/smoke/Probe.qml); a restart
# never counts.
jarvis_started() { ipc smoke jarvisProcess | py_reply 'import json,sys; d=json.load(sys.stdin); print("ready" if d["retries"] == 0 and d["lifetime"]["kind"] == "ready" else "retries=%d kind=%s" % (d["retries"], d["lifetime"]["kind"]))'; }
# Whether the Jarvis page's Status rows draw its readiness row as ready.
jarvis_page_ready() { ipc smoke itemTexts "$settings_kind" vgs.settings StatusRow | py_reply 'import json,sys; print(any("Jarvis readiness" in r and "Jarvis is ready; microphone is off" in r for r in json.load(sys.stdin)))'; }
jarvis_shot_requirement_standins=()
jarvis_setup_requirements() {
  local commands command
  jarvis_shot_requirement_standins=()
  commands="$(python3 - "$repo/shell/plugins/vgs.jarvis/manifest.json" <<'PY'
import json,sys
with open(sys.argv[1]) as source:
    manifest=json.load(source)
for row in manifest["requirements"]:
    if not row.get("optional", False) and "command" in row:
        print(row["command"])
PY
)" || return 1
  while IFS= read -r command; do
    [[ $(shell_resolves "$command") == none ]] || continue
    printf '#!/bin/sh\nexit 99\n' >"$shim/$command"
    chmod 755 "$shim/$command"
    jarvis_shot_requirement_standins+=("$command")
  done <<<"$commands"
}
jarvis_restore_requirements() {
  local command
  for command in "${jarvis_shot_requirement_standins[@]}"; do
    rm -f -- "${shim:?}/$command"
  done
  rescan "the Jarvis console requirement stand-ins are removed"
}
jarvis_notice_close() {
  jarvis_setup_requirements || { fail "the Jarvis requirement stand-ins are not written"; return 1; }
  rescan "the scan that finds Jarvis's required commands"
  expect_poll "the scan that finds Jarvis's required commands closes its notice" 0 layer_count vgs:notice
  jarvis_restore_requirements
}
# slack_section: the section that draws the Slack tokens, through Globex's
# action that takes one.
slack_section() {
  local heading=Slack
  ! "$has_setup_keys" || heading=Setup
  settings_section "$heading" StatusLine "Globex" RowAction "$keys_action"
}
# The setup steps of D061 on the open Settings window: Globex's Add key with
# its masked field typed into, the status fixture's Set up token and Install
# the tool, Automations' Enable while logged out, Agent Warden's Set up, and
# Themes' Install browser theming once the chromium target ships. A tool a
# plugin requires installs from Requirements, which setup-tab's and
# traffic's requirements shots show.
# step_offered ID KEY: whether plugin ID's Settings page offers the step of
# its status entry KEY.
step_offered() { status_row "$1" "$2" | py_reply 'import json,sys; r=json.load(sys.stdin); print(str(bool(r["action"] and r["action"]["offered"])).lower())'; }
# step_shot MODE ID KEY LABEL NAME: plugin ID's page, on the tab that draws
# its setup steps, with the action LABEL of its entry KEY scrolled into
# view, as setup-MODE-NAME. A host where the step is not offered, such as
# one whose scene stood in the command the button installs, skips the shot
# and says so.
step_shot() {
  local shown offered=false control _
  expect "the window opens the $2 page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin "$2"
  expect_poll "the $2 page is shown" "\"$2\"" settings_page
  page_setup
  # expect_poll's own window, 5 s at 0.2 s.
  for _ in $(seq 1 25); do
    [[ $(step_offered "$2" "$3") == true ]] && { offered=true; break; }
    sleep 0.2
  done
  if ! "$offered"; then
    ok "skipped setup-$1-$5: $2 offers no $4 here"
    return 0
  fi
  # The page draws its first open step's action as its one primary Button
  # and every other as a RowAction (Steps.markPrimary), and reveals only a
  # shown one, so the step's action is whichever of the two is revealed.
  for control in Button RowAction; do
    shown="$(ipc smoke revealText "$settings_kind" vgs.settings "$control" "$4")" || shown=unread
    [[ $shown != absent ]] && break
  done
  [[ $shown =~ ^[0-9.]+$ ]] || { fail "the $4 button was not revealed: $shown"; return 0; }
  park_pointer
  take "setup-$1-$5"
}
scene_setup_steps() { # MODE
  local section start end height
  if section="$(slack_section)"; then
    read -r start end height <<<"$section"
    settings_scroll_to "$((start - 12))" || fail "the scroll to the Slack section failed"
  fi
  settings_press --type RowAction "$keys_action" StatusLine "Globex" || fail "the click on Globex's $keys_action failed"
  type_keys "xoxp-shot-token" || fail "typing into the masked field failed"
  park_pointer
  take_posed "setup-$1-slack-connect"
  type_keys -k Escape || fail "sending Escape to the masked field failed"
  expect "the status fixture publishes its token absent" ok ipc acme.status invoke set 'token="absent"'
  expect "the status fixture publishes a check that offers its install" ok ipc acme.status invoke set 'check={"tone":"warning","text":"Tool missing","action":true}'
  expect "the window opens the status fixture's page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin acme.status
  expect_poll "the status fixture's page is shown" '"acme.status"' settings_page
  page_details
  park_pointer
  take "setup-$1-actions"
  # The harness's loginctl sentinel answers lingering off on every host, so
  # the step is always offered and step_shot never skips it.
  expect_poll "Automations offers Enable while logged out" true step_offered vgs.automations linger
  step_shot "$1" vgs.automations linger "Enable while logged out" automations
  # Set up is offered while vsys is present: a stand-in that runs nothing
  # stands for it, and goes again after the shot, so the next mode starts
  # from the same PATH.
  local vsys_stood=false
  if [[ ! -e $shim/vsys ]]; then
    printf '#!/usr/bin/env bash\nexit 0\n' >"$shim/vsys"
    chmod 755 "$shim/vsys"
    vsys_stood=true
    tree_rescan "a rescan after the stand-in vsys arrives starts"
  fi
  step_shot "$1" vgs.agent-warden setup "Set up" warden-set-up
  if "$vsys_stood"; then
    rm -f -- "${shim:?}/vsys"
    tree_rescan "a rescan after the stand-in vsys goes starts"
  fi
  step_shot "$1" vgs.themes browserTheming "Install browser theming" browser-theming
}
# The Settings window: the list opened from the gear, the pointer on the
# gear; a search nothing matches; a plugin page with many grouped settings at its top, with a typed
# value over its save bar, under the prompt the back button then raises, dragged down
# its scroll bar, scrolled a third and two thirds down, which match on the
# settled bar's region, and with its Mode select open; a plugin with keys; the
# automations' page at its Status section; the Jarvis page with its
# daemon ready; the Scratchpads page at its Pads section, holding one pad; the
# title's menu open with the pointer on its first entry, and scrolled half
# an entry; the notifications' page scrolled to its
# Slack token rows, over two shots when they are taller than the page; and
# the list and a page on a monitor narrower than the window's width token.
settings_empty() { [[ $(ipc smoke itemGeometry "$settings_kind" vgs.settings Label 'No plugin matches "zzqxv"') == \[* ]] && echo shown || echo hidden; }
scene_settings() { # MODE
  # A section shot keeps its heading margin px below the area's top edge.
  local area at bar title x y section start end height half margin=12
  click_centre "$(bar_key)" vgs.settings || fail "the click on the gear failed"
  expect_poll "the gear opens the Settings window" 1 settings_count
  expect_poll "the Settings window holds the keyboard" true ipc smoke activeFocusIn "$settings_kind" vgs.settings
  expect "the Settings window's root takes the focus for the list image" focused ipc smoke invokeInstance "$settings_kind" vgs.settings focusInstance ""
  take "settings-$1-list"
  ipc smoke invokeInstance "$settings_kind" vgs.settings open '{}' >/dev/null || fail "the Settings search did not regain focus"
  # A search nothing matches: the empty state and its way back.
  type_keys "zzqxv" || fail "typing a search nothing matches failed"
  expect_poll "the list shows its empty state" shown settings_empty
  expect "the Settings window's root takes the focus for the empty image" focused ipc smoke invokeInstance "$settings_kind" vgs.settings focusInstance ""
  take "settings-$1-empty"
  ipc smoke invokeInstance "$settings_kind" vgs.settings open '{}' >/dev/null || fail "the Settings search did not regain focus after the empty image"
  if "$has_clear_search"; then
    if read -r x y < <(window_point "$settings_surface" "$settings_kind" vgs.settings Button "Clear search") && hover "$((x - 1))" "$y" && click "$x" "$y"; then :; else fail "the click on Clear search failed"; fi
  else
    type_keys -k BackSpace -k BackSpace -k BackSpace -k BackSpace -k BackSpace || fail "erasing the search failed"
  fi
  expect_poll "the search is empty again" '""' ipc smoke readShownDescendant "$settings_kind" vgs.settings TextField text
  park_pointer
  # The gear draws no text, so it is found by its label.
  if at="$(centre_of "$(ipc smoke labelledGeometry "$(bar_key)" vgs.settings "$gear_type" "$settings_name")")" && [[ $at != none ]]; then
    read -r x y <<<"$at"
    if hover "$((x - 6))" "$y" && hover "$x" "$y" \
      && expect_poll "the gear shows its hover" true ipc smoke readDescendant "$(bar_key)" vgs.settings "$gear_type" hovered; then take_posed "settings-$1-gear"; else fail "the hover on the gear failed"; fi
  else
    fail "the gear has no box"
  fi
  park_pointer
  expect "the window opens the probe's page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin acme.probe
  expect_poll "the probe's page is shown" '"acme.probe"' settings_page
  take "settings-$1-page"
  park_pointer
  # An unsaved edit: the save bar under the page, then the prompt the back
  # button raises, answered Discard through the window, as its button
  # answers, whatever holds the keyboard; the page is then opened again.
  if "$has_save_bar"; then
    settings_unsaved() { ipc smoke readDescendant "$settings_kind" vgs.settings SaveBar dirty; }
    settings_prompt() { ipc smoke dialogCard "$settings_kind" vgs.settings | py_reply 'import json,sys; print(json.load(sys.stdin)["shown"])'; }
    if [[ $(ipc smoke invokeInstance "$settings_kind" vgs.settings holdField '{"id":"acme.probe","key":"gap","text":"12"}') == \[* ]]; then
      expect_poll "the typed Gap shows the save bar" true settings_unsaved
      take_posed "settings-$1-unsaved"
      expect "the back button is held by the unsaved edit" "refused: unsaved=acme.probe" ipc smoke invokeInstance "$settings_kind" vgs.settings back ''
      expect_poll "the back button raises the prompt" True settings_prompt
      take "settings-$1-leave-prompt"
      ipc smoke invokeInstance "$settings_kind" vgs.settings answer discard >/dev/null || fail "answering the prompt Discard failed"
      expect_poll "Discard closes the prompt" False settings_prompt
      expect_poll "Discard leaves the page for the list" '""' settings_page
      expect "the window opens the probe's page again" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin acme.probe
      expect_poll "the probe's page is shown again" '"acme.probe"' settings_page
    else
      fail "the probe's Gap field took no edit"
    fi
  fi
  # The page opened again grows its card toward its content, and the card
  # holds its bar hidden until it lands (Pane.cardGrowing), so the thumb is
  # dragged once the page reads as overflowing with its bar shown.
  expect_poll "the probe's page overflows its view with its bar shown" overflows settings_page_fit
  if [[ $(settings_page_fit) == overflows ]] && settings_drag_page_down "the probe's page"; then
    take "settings-$1-page-scrolled"
    # Two captures of the page, each taken right after a scroll restarts
    # the bar's fade delay, a third and two thirds down its content: take
    # waits for the bar to settle, so both match on its region.
    if area="$(settings_scroll)" && [[ $area == \{* ]] && [[ $(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["barVisible"])' "$area") == True ]] \
      && at="$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); print(int(a["contentHeight"] - a["height"]))' "$area")" \
      && bar="$(settings_bar_box "$area")"; then
      expect "the page scrolls a third down" "$((at / 3))" settings_scroll_set "$((at / 3))"
      take "settings-$1-page-third"
      expect "the page scrolls two thirds down" "$((2 * at / 3))" settings_scroll_set "$((2 * at / 3))"
      take "settings-$1-page-two-thirds"
      expect "the two scrolled captures match on the scroll bar's region" same shot_region_same "settings-$1-page-third" "settings-$1-page-two-thirds" "$bar"
    else
      fail "the scrolled probe's page bar is unreadable: ${area:-} ${bar:-}"
    fi
  fi
  park_pointer
  # The probe's Label preset select, scrolled into view and opened by a click on
  # its chevron end: the inline row's right 40 px, one row height tall.
  local field
  if field="$(ipc smoke invokeInstance "$settings_kind" vgs.settings fieldGeometry '{"id":"acme.probe","key":"label"}')" && [[ $field == \[* ]] \
    && area="$(settings_scroll)" && [[ $area == \{* ]] \
    && settings_scroll_to "$(python3 -c 'import json,sys; f, a = json.loads(sys.argv[1]), json.loads(sys.argv[2]); print(int(f[1] - a["bar"][1] + a["contentY"]) - 60)' "$field" "$area")" \
    && field="$(ipc smoke invokeInstance "$settings_kind" vgs.settings fieldGeometry '{"id":"acme.probe","key":"label"}')" && [[ $field == \[* ]] \
    && read -r x y < <(at_centre "$settings_surface" "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); h=json.loads(sys.argv[2]); print(json.dumps([r[0] + r[2] - 40, r[1], 40, h]))' "$field" "$(ipc smoke themeValue row.height)")") \
    && hover "$((x - 1))" "$y" && click "$x" "$y"; then
    expect_poll "the Label select opens its list" true ipc smoke readShownDescendant "$settings_kind" vgs.settings Select listOpen
    take_posed "settings-$1-select"
    type_keys -k Escape || fail "sending Escape to the Label select failed"
    expect_poll "the Label select closes its list" false ipc smoke readShownDescendant "$settings_kind" vgs.settings Select listOpen
  else
    fail "the probe's Label field is unreadable: ${field:-}"
  fi
  park_pointer
  expect "the window opens the launcher's page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.launcher
  expect_poll "the launcher's page is shown" '"vgs.launcher"' settings_page
  if section="$(settings_section Keys KeyField 'Open or close the launcher')"; then
    read -r start _ _ <<<"$section"
    settings_scroll_to "$((start - margin))" || fail "the scroll to the Keys section failed"
  else
    fail "the launcher's Keys section is unreadable: $section"
  fi
  park_pointer
  take "settings-$1-keys"
  ipc smoke scrollTo "$settings_kind" vgs.settings 0 >/dev/null || fail "the Keys screenshot did not restore its page's scroll"
  expect_poll "the Keys screenshot leaves the page at its top" True settings_at_top
  if "$has_agent_warden"; then
    expect "the window opens the Agent Warden page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.agent-warden
    expect_poll "the Agent Warden page is shown" '"vgs.agent-warden"' settings_page
    settings_scroll_to 0 >/dev/null || fail "the Agent Warden page did not scroll to the top"
    expect_poll "the Agent Warden page is at its top" True settings_at_top
    take "settings-$1-agent-warden"
    settings_scrolled_shot "$1" agent-warden "the Agent Warden page"
  fi
  if "$has_voice"; then
    if voice_dictates; then
      voice_stand_ins
    else
      cat >"$shim/voxtype" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  'status --follow --extended --format json') printf '{"state":"idle","backend":"ONNX CPU","device":"default","model":"parakeet-tdt-0.6b-v3"}\n' ;;
  'config get engine --json') printf '{"value":"parakeet"}\n' ;;
  'config get parakeet.model --json') printf '{"value":"parakeet-tdt-0.6b-v3"}\n' ;;
  'info models --json') printf '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false,"downloadable":true,"download_arg":"parakeet-tdt-0.6b-v3"}],"default":"parakeet-tdt-0.6b-v3"}},"verified":true}\n' ;;
  'info engines --json') printf '[{"name":"whisper","compiled":true,"active":false},{"name":"parakeet","compiled":true,"active":true}]\n' ;;
esac
EOF
      chmod 755 "$shim/voxtype"
    fi
    voice_bridge_stand_in
    rescan "the Voice voxtype stand-in is scanned"
    expect "enabling vgs.voice is allowed" ok ipc shell setPluginEnabled vgs.voice true
    expect_poll "vgs.voice is built" True record_exists vgs.voice
    expect "the window opens the Voice page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.voice
    expect_poll "the Voice page is shown" '"vgs.voice"' settings_page
    page_details
    expect_poll "the Voice setup row is reported" True page_reported vgs.voice
    settings_scroll_to 0 >/dev/null || fail "the Voice page did not scroll to the top"
    expect_poll "the Voice page is at its top" True settings_at_top
    park_pointer
    take "settings-$1-voice"
    expect "disabling vgs.voice is allowed" ok ipc shell setPluginEnabled vgs.voice false
    expect_poll "vgs.voice is gone" False record_exists vgs.voice
    voice_stand_ins_removed
    rm -f -- "${shim:?}/voxtype-audio-bridge"
    rescan "the Voice voxtype stand-in is removed"
  fi
  # The AI Usage page with its Sign in offered: the sandbox HOME holds no
  # account folder, so its helper runs no tool and sends no request.
  if "$has_ai_usage"; then
    expect "enabling vgs.ai-usage is allowed" ok ipc shell setPluginEnabled vgs.ai-usage true
    expect_poll "vgs.ai-usage is built" True record_exists vgs.ai-usage
    expect "the window opens the AI Usage page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.ai-usage
    expect_poll "the AI Usage page is shown" '"vgs.ai-usage"' settings_page
    # Sign-in's entries each declare a step, which the page draws on the tab
    # that holds its setup.
    page_setup
    expect_poll "the AI Usage sign-in rows are reported" True page_reported vgs.ai-usage
    # The Sign-in section's heading at the top.
    if section="$(settings_section Sign-in SectionHeader Sign-in)"; then
      read -r start _ _ <<<"$section"
      settings_scroll_to "$((start - margin))" || fail "the scroll to AI Usage's Sign-in section failed"
    else
      fail "AI Usage's Sign-in section is unreadable: $section"
    fi
    park_pointer
    take "settings-$1-ai-usage"
    expect "disabling vgs.ai-usage is allowed" ok ipc shell setPluginEnabled vgs.ai-usage false
    expect_poll "vgs.ai-usage is gone" False record_exists vgs.ai-usage
  fi
  # The Tray page at its top, its pinned and hidden lists empty: the sandbox
  # runs no tray app. The enablement is put back after the shot.
  local tray_found=unread
  if "$has_tray"; then
    tray_found="$(plugin_enabled vgs.tray)" || tray_found=unread
    [[ $tray_found == True || $tray_found == False ]] || fail "vgs.tray's enablement is unreadable: $tray_found"
  fi
  if [[ $tray_found != unread ]]; then
    if [[ $tray_found == False ]]; then
      expect "enabling vgs.tray is allowed" ok ipc shell setPluginEnabled vgs.tray true
      expect_poll "vgs.tray is built" True record_exists vgs.tray
    fi
    expect "the window opens the Tray page as a click does" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPluginByPointer vgs.tray
    expect_poll "the Tray page is shown" '"vgs.tray"' settings_page
    settings_scroll_to 0 >/dev/null || fail "the Tray page did not scroll to the top"
    expect_poll "the Tray page is at its top" True settings_at_top
    park_pointer
    expect "the Settings window's root takes the focus for the Tray page" focused ipc smoke invokeInstance "$settings_kind" vgs.settings focusInstance ""
    take "settings-$1-tray"
    if [[ $tray_found == False ]]; then
      expect "disabling vgs.tray is allowed" ok ipc shell setPluginEnabled vgs.tray false
      expect_poll "vgs.tray is gone" False record_exists vgs.tray
    fi
  fi
  # The Passwordless Sudo page at its top, its default duration field
  # shown. Its status read reaches the harness's tree, whose sudo is the
  # sentinel and which holds no root half. The enablement is put back after
  # the shot.
  local sudo_found=unread
  if "$has_sudo"; then
    sudo_found="$(plugin_enabled vgs.sudo)" || sudo_found=unread
    [[ $sudo_found == True || $sudo_found == False ]] || fail "vgs.sudo's enablement is unreadable: $sudo_found"
  fi
  if [[ $sudo_found != unread ]]; then
    if [[ $sudo_found == False ]]; then
      expect "enabling vgs.sudo is allowed" ok ipc shell setPluginEnabled vgs.sudo true
      expect_poll "vgs.sudo is built" True record_exists vgs.sudo
    fi
    expect "the window opens the Passwordless Sudo page as a click does" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPluginByPointer vgs.sudo
    expect_poll "the Passwordless Sudo page is shown" '"vgs.sudo"' settings_page
    settings_scroll_to 0 >/dev/null || fail "the Passwordless Sudo page did not scroll to the top"
    expect_poll "the Passwordless Sudo page is at its top" True settings_at_top
    park_pointer
    expect "the Settings window's root takes the focus for the Passwordless Sudo page" focused ipc smoke invokeInstance "$settings_kind" vgs.settings focusInstance ""
    take "settings-$1-sudo"
    if [[ $sudo_found == False ]]; then
      expect "disabling vgs.sudo is allowed" ok ipc shell setPluginEnabled vgs.sudo false
      expect_poll "vgs.sudo is gone" False record_exists vgs.sudo
    fi
  fi
  if "$has_bar_plugin"; then
    expect "the window opens the Bar page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.bar
    expect_poll "the Bar page is shown" '"vgs.bar"' settings_page
    settings_scroll_to 0 >/dev/null || fail "the Bar page did not scroll to the top"
    expect_poll "the Bar page is at its top" True settings_at_top
    take "settings-$1-bar"
    settings_scrolled_shot "$1" bar "the Bar page"
  fi
  # The automations' page at its top, the plugin enabled over the stand-ins
  # rows/automations.sh reads (automations_stand_ins in
  # scripts/smoke/harness.sh), so no call reaches the host's systemd user
  # manager; the stand-ins removed after the shot, and the plugin disabled
  # again only when this scene enabled it, since the setup steps' shot below
  # reads the page of the plugin their setup enabled.
  local auto_found=unread
  if "$has_automations"; then
    auto_found="$(plugin_enabled vgs.automations)" || auto_found=unread
    [[ $auto_found == True || $auto_found == False ]] || fail "vgs.automations' enablement is unreadable: $auto_found"
  fi
  if [[ $auto_found != unread ]]; then
    automations_stand_ins "$sandbox/shots-automations-$1"
    tree_rescan "the automations' stand-ins are scanned"
    if [[ $auto_found == False ]]; then
      expect "enabling vgs.automations is allowed" ok ipc shell setPluginEnabled vgs.automations true
      expect_poll "vgs.automations is built" True record_exists vgs.automations
    fi
    expect "the window opens the automations' page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.automations
    expect_poll "the automations' page is shown" '"vgs.automations"' settings_page
    page_details
    expect_poll "the automations' status rows are reported" True page_reported vgs.automations
    # The Status section's heading at the top.
    if section="$(settings_section Status SectionHeader Status)"; then
      read -r start _ _ <<<"$section"
      settings_scroll_to "$((start - margin))" || fail "the scroll to the automations' status failed"
    else
      fail "the automations' Status section is unreadable: $section"
    fi
    park_pointer
    take "settings-$1-automations"
    if [[ $auto_found == False ]]; then
      expect "disabling vgs.automations is allowed" ok ipc shell setPluginEnabled vgs.automations false
      expect_poll "vgs.automations is gone" False record_exists vgs.automations
    fi
    automations_stand_ins_restore "$sandbox/shots-automations-$1"
  fi
  # The Jarvis page at its top, the daemon's status reported: the plugin
  # enabled over the J09 world the harness prepares for every sandbox, as
  # rows/jarvis.sh enables it, so the child reaches no audio, account,
  # network or desktop; disabled again after the shot.
  if "$has_jarvis"; then
    expect "enabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
    expect_poll "the Jarvis daemon answers hello without a restart" ready jarvis_started
    # Jarvis requires wlrctl, which the shell finds absent, so enabling it
    # raises its requirement notice, which closes before the shot.
    for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
    close_notices
    expect "the window opens the Jarvis page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.jarvis
    expect_poll "the Jarvis page is shown" '"vgs.jarvis"' settings_page
    page_details
    expect_poll "the Jarvis page shows its daemon ready" True jarvis_page_ready
    settings_scroll_to 0 >/dev/null || fail "the Jarvis page did not scroll to the top"
    expect_poll "the Jarvis page is at its top" True settings_at_top
    park_pointer
    take "settings-$1-jarvis"
    expect "disabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
    expect_poll "vgs.jarvis is gone" absent ipc smoke jarvisProcess
  fi
  # The Scratchpads page at its Pads section, opened as a click opens it so
  # no focus ring or tooltip covers it, one pad of the item defaults
  # written through the window, so the shot shows the list field; the pad
  # starts no app, since it is never pressed. The pads and the enablement
  # are put back after the shot.
  local pads_found=unread
  if "$has_scratchpads"; then
    pads_found="$(plugin_enabled vgs.scratchpads)" || pads_found=unread
    [[ $pads_found == True || $pads_found == False ]] || fail "vgs.scratchpads' enablement is unreadable: $pads_found"
  fi
  if [[ $pads_found != unread ]]; then
    if [[ $pads_found == False ]]; then
      expect "enabling vgs.scratchpads is allowed" ok ipc shell setPluginEnabled vgs.scratchpads true
      expect_poll "vgs.scratchpads is built" True record_exists vgs.scratchpads
    fi
    expect "the window opens the Scratchpads page as a click does" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPluginByPointer vgs.scratchpads
    expect_poll "the Scratchpads page is shown" '"vgs.scratchpads"' settings_page
    expect "the Pads field's Add is clicked" clicked ipc smoke invokeInstance "$settings_kind" vgs.settings listAdd '{"id":"vgs.scratchpads","key":"pads"}'
    # The section's heading three margins under the top, clear of the
    # header, with the Add button its last line.
    if section="$(settings_section Pads RowAction Add)"; then
      read -r start _ _ <<<"$section"
      settings_scroll_to "$((start - 3 * margin))" || fail "the scroll to the Pads section failed"
    else
      fail "the Pads section is unreadable: $section"
    fi
    park_pointer
    expect "the Settings window's root takes the focus" focused ipc smoke invokeInstance "$settings_kind" vgs.settings focusInstance ""
    take "settings-$1-scratchpads"
    expect "the pad is removed after the shot" ok ipc smoke invokeInstance "$settings_kind" vgs.settings applySetting '{"id":"vgs.scratchpads","key":"pads","value":[]}'
    if [[ $pads_found == False ]]; then
      expect "disabling vgs.scratchpads is allowed" ok ipc shell setPluginEnabled vgs.scratchpads false
      expect_poll "vgs.scratchpads is gone" False record_exists vgs.scratchpads
    fi
  fi
  # The Web Apps page at its Web apps section, opened as a click opens it,
  # one web app written through the window. Its address is the loopback
  # discard port, where nothing listens, so the service's read of the site
  # reaches no network and fails at once; the shot shows the list field.
  # Each host browser entry hides behind a shadow while Web Apps runs, as
  # in scripts/smoke/rows/webapps.sh, though the scene opens no web app.
  # The web apps, their entry, the shadows and the enablement are put back
  # after the shot.
  local webapps_found=unread
  if "$has_webapps"; then
    webapps_found="$(plugin_enabled vgs.webapps)" || webapps_found=unread
    [[ $webapps_found == True || $webapps_found == False ]] || fail "vgs.webapps' enablement is unreadable: $webapps_found"
  fi
  if [[ $webapps_found != unread ]] && ! webapps_shadows_plant; then
    fail "the host browser entries could not be shadowed, so Web Apps is not started"
    webapps_shadows_remove
    webapps_found=unread
  fi
  if [[ $webapps_found != unread ]]; then
    if [[ $webapps_found == False ]]; then
      expect "enabling vgs.webapps is allowed" ok ipc shell setPluginEnabled vgs.webapps true
      expect_poll "vgs.webapps is built" True record_exists vgs.webapps
    fi
    expect "the window opens the Web Apps page as a click does" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPluginByPointer vgs.webapps
    expect_poll "the Web Apps page is shown" '"vgs.webapps"' settings_page
    expect "the Web apps field's Add is clicked" clicked ipc smoke invokeInstance "$settings_kind" vgs.settings listAdd '{"id":"vgs.webapps","key":"apps"}'
    expect "the web app's address and name are written" ok ipc smoke invokeInstance "$settings_kind" vgs.settings applySetting '{"id":"vgs.webapps","key":"apps","value":[{"name":"1","url":"http://127.0.0.1:9/","title":"Mail","icon":""}]}'
    if section="$(settings_section "Web apps" RowAction Add)"; then
      read -r start _ _ <<<"$section"
      settings_scroll_to "$((start - 3 * margin))" || fail "the scroll to the Web apps section failed"
    else
      fail "the Web apps section is unreadable: $section"
    fi
    park_pointer
    expect "the Settings window's root takes the focus" focused ipc smoke invokeInstance "$settings_kind" vgs.settings focusInstance ""
    expect "no notice covers the Web Apps page" null notice_shown
    take "settings-$1-webapps"
    expect "the web app is removed after the shot" ok ipc smoke invokeInstance "$settings_kind" vgs.settings applySetting '{"id":"vgs.webapps","key":"apps","value":[]}'
    expect_poll "the removed web app's entry is gone" absent bash -c '[[ -e $1 ]] && echo present || echo absent' _ "$home/.local/share/applications/vgs-webapp-1.desktop"
    if [[ $webapps_found == False ]]; then
      expect "disabling vgs.webapps is allowed" ok ipc shell setPluginEnabled vgs.webapps false
      expect_poll "vgs.webapps is gone" False record_exists vgs.webapps
    fi
    webapps_shadows_remove
  fi
  expect "the window opens the launcher's page again" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.launcher
  expect_poll "the launcher's page is shown again" '"vgs.launcher"' settings_page
  click_in "$settings_surface" "$settings_kind" vgs.settings TitleButton Launcher || fail "the click on the title failed"
  expect_poll "the title's menu opens" True settings_menu_open
  # The menu opens under the title; the pointer rests on its first entry,
  # 20 px under the title, which highlights it and shows the scroll bar.
  if title="$(ipc smoke windowGeometry "$settings_kind" vgs.settings TitleButton Launcher)" && [[ $title == \[* ]]; then
    read -r x y < <(at_centre "$settings_surface" "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(json.dumps([r[0], r[1] + r[3], 80, 40]))' "$title")")
    hover "$((x - 6))" "$y" && hover "$x" "$y" || fail "the hover inside the title's menu failed"
    expect_poll "the title's menu reports the pointer inside it" True settings_menu_hovered
    expect_poll "the pointer takes the menu's highlight" True settings_menu_pointed
  fi
  take_posed "settings-$1-menu"
  # The same menu, the pointer off it, scrolled so the highlighted entry is
  # half past the list's top edge: its fill cut there, inside a rounded
  # corner's curve. The pointer leaving the entries clears a highlight no
  # key chose (Menu.qml), so Down highlights the first entry first.
  park_pointer
  type_keys -k Down || fail "sending Down to the title's menu failed"
  expect_poll "Down highlights an entry of the title's menu" True settings_menu_highlighted
  if half="$(ipc smoke themeValue menu.item.height)" && [[ $half =~ ^[0-9]+$ ]]; then
    expect "the title's menu scrolls its highlight half past the top" "$((half / 2))" ipc smoke scrollMenu "$settings_kind" vgs.settings "$((half / 2))"
    take_posed "settings-$1-menu-scrolled"
  else
    fail "the title's menu entry height is unreadable: ${half:-}"
  fi
  type_keys -k Escape || fail "sending Escape to the title's menu failed"
  expect_poll "the title's menu closes" False settings_menu_open
  expect "the window opens the Bar plugin page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.bar
  expect_poll "the Bar plugin page is shown" '"vgs.bar"' settings_page
  take "settings-$1-bar-page"
  park_pointer
  expect "the window opens the notifications' page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.notifications
  expect_poll "the notifications' page is shown" '"vgs.notifications"' settings_page
  page_keys
  expect_poll "the notifications' status rows are reported" True page_reported vgs.notifications
  # The Slack tokens' section in view: its heading at the top, and, when the
  # section is taller than the area, a second shot with its last line at
  # the bottom, so every line and command shows across the two.
  if section="$(slack_section)"; then
    read -r start end height <<<"$section"
    settings_scroll_to "$((start - margin))" || fail "the scroll to the Slack section failed"
    park_pointer
    take "settings-$1-slack"
    if (( end - start + 2 * margin > height )); then
      settings_scroll_to "$((end + margin - height))" || fail "the scroll to the Slack section's end failed"
      park_pointer
      take "settings-$1-slack-end"
    fi
  else
    fail "the notifications' Slack section is unreadable: $section"
  fi
  if "$has_setup_steps"; then scene_setup_steps "$1"; fi
  settings_close
  # The monitor made narrower than the window (narrow_begin): the gear
  # opens the window on its bar's monitor, the list first and then a page.
  narrow_begin
  expect "the gear opens the window on the narrow monitor" ok ipc smoke invokeInstance "$(bar_key)" vgs.settings toggle ''
  expect_poll "the narrow window maps" 1 settings_count
  expect "the narrow Settings window's root takes the focus" focused ipc smoke invokeInstance "$settings_kind" vgs.settings focusInstance ""
  take "settings-$1-narrow-list"
  expect "the narrow window opens the probe's page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin acme.probe
  expect_poll "the probe's page is shown on the narrow monitor" '"acme.probe"' settings_page
  take "settings-$1-narrow-page"
  settings_close
  narrow_end
}


plugin_pages_list() {
  ipc smoke readInstance "$settings_kind" vgs.settings plugins | python3 -c 'import json,sys; print("\n".join(p["id"] for p in json.load(sys.stdin)))'
}

# Record the manager's state, not credentials. Stored secrets never enter
# manager rows; this is the same state the page uses to draw its fields.
page_state_record() { # IMAGE MODE ID
  local state theme
  theme="$(ipc smoke themeName)" || { fail "the $3 page theme is unreadable"; return 1; }
  state="$(ipc smoke readInstance "$settings_kind" vgs.settings plugins | py_reply 'import json,sys
rows=json.load(sys.stdin)
row=next((r for r in rows if r.get("id")==sys.argv[1]),None) if isinstance(rows,list) else None
keys=("enabled","kinds","settings","settingChoices","status","requirements","errors")
print("absent" if row is None or not all(k in row for k in keys) else json.dumps({k:row[k] for k in keys},sort_keys=True,separators=(",",":")))' "$3")" || { fail "the $3 page state is unreadable"; return 1; }
  [[ $state == \{* ]] || { fail "the $3 page state is $state"; return 1; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$capture_source" "$theme" "$3" "$state" >>"$SHOT_DIR/page-states.tsv"
}

# plugin_page_shots MODE ID [NAME [TAB]]: every screen of plugin ID's page.
# A requested Setup tab that is absent leaves Settings visible, so the
# captured strip proves that the plugin has no Setup tab.
plugin_page_shots() {
  local id="$2" name="${3:-plugin-pages-$1-$2}" requested="${4:-settings}" shown=Settings tabs image suffix=1 at cy ch h y=0
  expect "the window opens the $id page for screenshots" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin "$id"
  expect_poll "the $id page is shown for screenshots" "\"$id\"" settings_page
  case "$requested" in
    setup)
      tabs="$(ipc smoke itemValues "$settings_kind" vgs.settings TabPages model | py_reply 'import json,sys; rows=json.load(sys.stdin); print("unreadable" if len(rows)!=1 or not isinstance(rows[0].get("model"),list) else "setup" if "Setup" in rows[0]["model"] else "absent")')" || { fail "the $id tab strip is unreadable"; return; }
      [[ $tabs != unreadable ]] || { fail "the $id tab strip is unreadable"; return; }
      if [[ $tabs == setup ]]; then settings_setup; shown=Setup; fi ;;
    details) page_details; shown=Details ;;
    settings) ;;
    *) fail "the requested tab is unknown: $requested"; return ;;
  esac
  if [[ $shown == Settings ]]; then
    settings_tab_click Settings || { fail "the click on the $id Settings tab failed"; return; }
    expect_poll "the $id Settings tab is shown for screenshots" Settings settings_tab_text
  fi
  at="$(ipc smoke scrollTo "$settings_kind" vgs.settings 0)" || at=""
  if [[ $at != "["* ]]; then
    fail "the $id page did not scroll to its top: ${at:-no reply}"
    return
  fi
  while :; do
    read -r cy ch h < <(python3 -c 'import json,sys; print(*(int(v) for v in json.loads(sys.argv[1])))' "$at")
    image="$name"
    (( suffix == 1 )) || image="$name-$suffix"
    take "$image"
    page_state_record "$image" "$1" "$id"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$image" "$1" "$capture_source" "$id" "$requested" "$shown" "$cy" >>"$SHOT_DIR/pages.tsv"
    (( cy + h < ch )) || break
    y=$(( cy + h - 40 ))
    suffix=$(( suffix + 1 ))
    at="$(ipc smoke scrollTo "$settings_kind" vgs.settings "$y")" || at=""
    if [[ $at != "["* ]]; then
      fail "the $id page did not scroll to page $suffix: ${at:-no reply}"
      break
    fi
  done
}

scene_plugin-pages() { # MODE
  local id ids=()
  expect "the Settings window opens for all plugin pages" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for all plugin pages" 1 settings_count
  if [[ ${#page_ids[@]} -gt 0 ]]; then
    ids=("${page_ids[@]}")
  else
    mapfile -t ids < <(plugin_pages_list)
  fi
  if [[ ${#ids[@]} -eq 0 ]]; then
    fail "the Settings window listed no plugins for plugin page screenshots"
  fi
  for id in "${ids[@]}"; do
    case "$id" in
      *:settings|*:setup|*:details) plugin_page_shots "$1" "${id%:*}" "plugin-pages-$1-${id%:*}-${id##*:}" "${id##*:}" ;;
      *) plugin_page_shots "$1" "$id" ;;
    esac
  done
  settings_close
}


# The browsers' readings: the theme view's shown card count, whether it
# names a problem, the card it offers wallpapers for, and the wallpaper
# view's selected card kind.
theme_view_count() { ipc smoke readDescendant overlay vgs.themes ThemeView shownCards | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
theme_view_problem() { ipc smoke readDescendant overlay vgs.themes ThemeView problem | py_reply 'import json,sys; print(json.load(sys.stdin) != "")'; }
theme_view_offer() { ipc smoke readDescendant overlay vgs.themes ThemeView offer | py_reply 'import json,sys; o=json.load(sys.stdin); print(json.dumps(None if o is None else o["name"]))'; }
wallpaper_selected_kind() { ipc smoke readDescendant overlay vgs.themes WallpaperView selected | py_reply 'import json,sys; s=json.load(sys.stdin); print(json.dumps(None if s is None else s["kind"]))'; }
wallpaper_failure_shown() {
  local problem
  problem="$(ipc smoke readDescendant overlay vgs.themes WallpaperView problem)" || return
  ipc smoke descendantGeometry overlay vgs.themes | py_reply 'import json,sys
problem=json.loads(sys.argv[1]); rows=json.load(sys.stdin)
print(isinstance(problem,str) and bool(problem) and isinstance(rows,list) and any(
    r["type"] == "Label" and r.get("text") == problem and r["visible"] and r["box"][2] > 0 and r["box"][3] > 0 for r in rows))' "$problem"
}
# sandbox_vgshell ARGS...: bin/vgshell in the sandbox on the PATH every sandbox
# shell starts with, so the runner meets the commands the shell meets. The
# host's PATH can hold the browser-policy writer the run hides from every
# shell (shell_hidden_commands); the CLI would then judge the chromium
# target the settings scene ships set up and run its reload hook, which
# the theme judge refuses under the test-run marker, failing the apply.
sandbox_vgshell() { "${shell_env[@]}" PATH="$shell_start_path" "$repo/bin/vgshell" "$@"; }
# themes_restore MODE LABEL: vgs applied, which draws Black, then the mode's
# theme, after a scene applied another package.
themes_restore() {
  sandbox_vgshell theme apply vgs >/dev/null || fail "vgs applies after $2"
  expect_poll "Black is drawn after $2" 1 layer_count vgs:background
  set_mode "$1"
}
# browser_card_right: the centre of the card right of the selected one on
# a browser's rail, the selected card being the largest, as `X Y`.
browser_card_right() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply 'import json,sys
cards = [r["box"] for r in json.load(sys.stdin) if r["type"] == "AngledCard" and r["box"][2] > 0 and r["box"][3] > 0]
selected = max(cards, key=lambda b: b[2] * b[3]) if cards else None
right = [b for b in cards if selected is not None and b[0] > selected[0]]
b = min(right, key=lambda b: b[0]) if right else None
print("none" if b is None else "%d %d" % (b[0] + b[2] / 2, b[1] + b[3] / 2))'
}
# theme_browser_box: the box around the theme browser's tabs, its selected
# card, the largest, and the name the filter shows under it, as
# `[x, y, w, h]`, or `none`.
theme_browser_box() {
  ipc smoke descendantGeometry overlay vgs.themes | py_reply 'import json,sys
rows = [r for r in json.load(sys.stdin) if r["visible"] and r["box"][2] > 0 and r["box"][3] > 0]
tabs = [r["box"] for r in rows if r["type"] == "Tabs"]
cards = [r["box"] for r in rows if r["type"] == "AngledCard"]
names = [r["box"] for r in rows if r["type"] == "Label" and r.get("role") == "h3" and r.get("text") == sys.argv[1]]
boxes = [tabs[0], max(cards, key=lambda b: b[2] * b[3]), names[0]] if tabs and cards and names else []
left, top = (min(b[0] for b in boxes), min(b[1] for b in boxes)) if boxes else (0, 0)
print(json.dumps([left, top, max(b[0] + b[2] for b in boxes) - left, max(b[1] + b[3] for b in boxes) - top]) if boxes else "none")' "$theme_card"
}
rail_card_hovered() { ipc smoke itemValues overlay vgs.themes AngledCard hovered | py_reply 'import json,sys; print(any(v["hovered"] is True for v in json.load(sys.stdin)))'; }
# hover_card LABEL: the pointer on that card, held until a card reports it
# twice in a row. A tree whose cards draw no hover takes the shot once the
# pointer is there.
hover_card() {
  local at x y i held=0
  at="$(browser_card_right)" && [[ $at != none ]] || { fail "$1: no card right of the selected one"; return 1; }
  read -r x y <<<"$at"
  if ! "$card_hover_state"; then
    hover "$x" "$y" || { fail "$1: the hover failed"; return 1; }
    ok "$1 (the tree's cards draw no hover)"; return 0
  fi
  for i in $(seq 1 50); do
    hover "$((x + i % 2))" "$y" || { fail "$1: the hover failed"; return 1; }
    if [[ $(rail_card_hovered) == True ]]; then held=$((held + 1)); else held=0; fi
    if (( held >= 2 )); then ok "$1"; return 0; fi
    sleep 0.1
  done
  fail "$1: no card reported the pointer"
  return 1
}

# The same required Token step before and after completion. The fixture's
# publisher changes its status; the page's shared judge chooses the warning.
setup_tab_ready=false
setup_tab_prepare() {
  local fixture
  "$setup_tab_ready" && return 0
  setup_tab_ready=true
  for fixture in acme.probe acme.bare acme.needs acme.status; do
    mkdir -p "$home/.config/vgshell/plugins/$fixture"
    cp -R -- "$fixtures/$fixture/." "$home/.config/vgshell/plugins/$fixture/"
  done
  tree_rescan "the setup tab fixtures are scanned"
  for fixture in acme.probe acme.bare acme.needs acme.status; do
    expect "enabling $fixture for the setup tab shots is allowed" ok ipc shell setPluginEnabled "$fixture" true
  done
  expect_poll "the status fixture is built for setup warning shots" True record_exists acme.status
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
}
setup_tab_mark() { ipc smoke scopedWindowGeometry "$settings_kind" vgs.settings ListItem "$1" "$2" "$3" | py_reply 'import sys; print("absent" if sys.stdin.read().strip() == "absent" else "drawn")'; }
setup_tab_marks() { printf '%s %s\n' "$(setup_tab_mark "$1" Badge "Setup needed")" "$(setup_tab_mark "$1" IconButton "Open setup")"; }
setup_tab_tip() { ipc smoke itemValues "$settings_kind" vgs.settings Tooltip opened | py_reply 'import json,sys; print(any(v["opened"] is True for v in json.load(sys.stdin)))'; }
setup_tab_page() { # ID
  expect "the window opens the $1 page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin "$1"
  expect_poll "the $1 page is shown" "\"$1\"" settings_page
}
setup_tab_warning() {
  ipc smoke itemValues "$settings_kind" vgs.settings TabPages warningTabs | py_reply 'import json,sys; rows=json.load(sys.stdin); print("warning" if len(rows)==1 and "Setup" in rows[0].get("warningTabs",[]) else "clear" if len(rows)==1 else "unreadable")'
}
setup_tab_token_tone() { status_row acme.status token | py_reply 'import json,sys; print(json.load(sys.stdin)["tone"])'; }
scene_setup-tab() { # MODE
  local rect x y state token warning optional_icon=false list_marks="drawn absent"
  if tree_has shell/plugins/vgs.settings/ListPage.qml '"Open setup"'; then
    optional_icon=true
    list_marks="drawn drawn"
  fi
  setup_tab_prepare
  expect "the fixture publishes a complete check" ok ipc acme.status invoke set 'check={"tone":"ok","text":"The check is complete"}'
  expect "the fixture publishes a missing token" ok ipc acme.status invoke set 'token="absent"'
  expect "the Settings window opens for the setup tab shots" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for the setup tab shots" 1 settings_count
  expect_poll "the Acme Sync row draws its required badge and the captured tree's optional-icon state" "$list_marks" setup_tab_marks "Acme Sync"
  expect "the Probe row draws neither mark" "absent absent" setup_tab_marks Probe
  expect "the Settings window's root takes the focus for the list image" focused ipc smoke invokeInstance "$settings_kind" vgs.settings focusInstance ""
  take "setup-tab-$1-list"
  if "$optional_icon"; then
    rect="$(ipc smoke scopedWindowGeometry "$settings_kind" vgs.settings ListItem 'Acme Sync' IconButton 'Open setup')" || rect=""
    if [[ $rect == \[* ]] && read -r x y < <(at_centre "$settings_surface" "$rect") && hover "$((x - 6))" "$y" && hover "$x" "$y"; then
      expect_poll "the optional-tool icon's tooltip opens" True setup_tab_tip
      take_posed "setup-tab-$1-list-tooltip"
    else
      fail "the Acme Sync row's optional-tool icon has no box: $rect"
    fi
  fi
  park_pointer
  setup_tab_page acme.probe
  take "setup-tab-$1-no-setup"
  for state in incomplete complete; do
    token=absent warning=warning
    [[ $state != complete ]] || { token=present; warning=clear; }
    expect "the fixture publishes its $state Token step" ok ipc acme.status invoke set "token=\"$token\""
    setup_tab_page acme.status
    settings_setup
    if [[ $state == incomplete ]]; then
      expect_poll "the fixture's Token is missing" warning setup_tab_token_tone
    else
      expect_poll "the fixture's Token is present" success setup_tab_token_tone
    fi
    if tree_has shell/Ui/layout/TabPages.qml warningTabs; then
      expect_poll "the Setup tab warning follows the $state required step" "$warning" setup_tab_warning
    else
      warning=unsupported
    fi
    settings_scroll_to 0 || fail "the fixture Setup tab did not scroll to its top"
    park_pointer
    take "setup-tab-$1-fixture-$state"
    printf '%s\t%s\t%s\t%s\t%s\n' "setup-tab-$1-fixture-$state" "$1" "$capture_source" "$state" "$warning" >>"$SHOT_DIR/setup-states.tsv"
  done
  settings_close
}

# The Updates page with every tool it requires found: its tab strip holds
# Settings and Details alone, since the Update everything screen carries no
# setup mark, and Details draws that screen in its Actions row. Each
# requirement command the shell does not find, optional ones included,
# since any tool not present gives the page its Setup tab, is stood in by
# a stand-in no step runs: the service reads the planted snapshot
# (updates_snapshot_plant), so it starts no check, and it only looks the
# review agents up on the PATH. The smoke set starts Updates turned off
# with no snapshot, and turning it on then would start a check.
updates_requirement_standins=()
updates_tabs() { ipc smoke itemValues "$settings_kind" vgs.settings TabPages model | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(v[0]["model"]) if len(v) == 1 else "tabs=%d" % len(v))'; }
# updates_action: `shown` while Details draws Update everything in its
# Actions row inside the page's scroll area, `hidden` while it is out of
# view, `absent` while no Actions row holds it.
updates_action() {
  local box area
  box="$(ipc smoke scopedWindowGeometry "$settings_kind" vgs.settings Field Actions RowAction "Update everything")" || return 1
  [[ $box == \[* ]] || { echo absent; return 0; }
  area="$(settings_scroll)" && [[ $area == \{* ]] || { echo "area=${area:-unread}"; return 0; }
  python3 -c 'import json,sys
b, bar = json.loads(sys.argv[1]), json.loads(sys.argv[2])["bar"]
print("shown" if b[1] >= bar[1] and b[1] + b[3] <= bar[1] + bar[3] else "hidden")' "$box" "$area"
}
scene_updates() { # MODE
  local command commands at
  updates_requirement_standins=()
  commands="$(python3 -c 'import json,sys; print("\n".join(r["command"] for r in json.load(open(sys.argv[1]))["requirements"] if "command" in r))' "$repo/shell/plugins/vgs.updates/manifest.json")" ||
    fail "the Updates requirements are unreadable"
  while IFS= read -r command; do
    [[ -n $command && $(shell_resolves "$command") == none ]] || continue
    printf '#!/bin/sh\nexit 99\n' >"$shim/$command" && chmod 755 "$shim/$command" || fail "the $command stand-in is not written"
    updates_requirement_standins+=("$command")
  done <<<"$commands"
  updates_snapshot_plant
  tree_rescan "the Updates requirement stand-ins are scanned"
  expect "enabling vgs.updates for its page shots is allowed" ok ipc shell setPluginEnabled vgs.updates true
  expect_poll "the updates service reads the planted snapshot" 6 updates_pending
  expect "the updates service runs no check" False updates_checking
  close_notices
  expect "the Settings window opens for the Updates page" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for the Updates page" 1 settings_count
  setup_tab_page vgs.updates
  park_pointer
  expect_poll "the Updates page draws no Setup tab before its Settings shot" '["Settings", "Details"]' updates_tabs
  take "updates-$1-settings"
  page_details
  at="$(ipc smoke scrollTo "$settings_kind" vgs.settings 0)" || at=""
  [[ $at == "["* ]] || fail "the Updates Details tab did not scroll to its top: ${at:-no reply}"
  park_pointer
  expect_poll "the Updates page draws no Setup tab before its Details shot" '["Settings", "Details"]' updates_tabs
  expect_poll "the Updates Actions row shows Update everything before its Details shot" shown updates_action
  take "updates-$1-details"
  settings_close
  expect "the updates service ran no check" False updates_checking
  for command in "${updates_requirement_standins[@]}"; do
    rm -f -- "${shim:?}/$command"
  done
  tree_rescan "the Updates requirement stand-ins are removed"
}

scene_focus() { # MODE
  local start surfaces focus_box
  expect "the gallery summons for focus shots" ok ipc shell summon "$gallery_kind" vgs.gallery '{}'
  expect_poll "the gallery maps for focus shots" 1 surface_count "$gallery_surface"
  expect_poll "the gallery focus examples are complete" '[]' ipc smoke galleryFocusMissing "$gallery_kind" vgs.gallery
  start="$(ipc smoke windowGeometry "$gallery_kind" vgs.gallery SectionHeader Focus)" || start=""
  if [[ $start == \[* ]]; then
    ipc smoke scrollTo "$gallery_kind" vgs.gallery "$(python3 -c 'import json,sys; print(max(0, int(json.loads(sys.argv[1])[1]) - 80))' "$start")" >/dev/null || fail "the gallery did not scroll to the Focus section"
    take_posed "focus-$1-gallery"
  else
    fail "the Gallery Focus section is unreadable: ${start:-}"
  fi
  expect "the gallery hides after focus shots" ok ipc shell hide "$gallery_kind" vgs.gallery
  expect_poll "the gallery focus window is gone" 0 surface_count "$gallery_surface"

  expect "the Settings window opens for focus shots" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings focus window maps" 1 settings_count
  expect_poll "the Settings search holds the keyboard" true ipc smoke activeFocusIn "$settings_kind" vgs.settings
  type_keys -k Tab || fail "sending Tab to Settings for focus shots failed"
  focus_box="$(ipc smoke focused "$settings_kind" vgs.settings)" || focus_box=""
  if [[ $(python3 -c 'import json,sys; row=json.loads(sys.argv[1]); print(len(row) >= 4 and row[3] is True)' "$focus_box" 2>/dev/null || echo False) == True ]]; then
    take_posed "focus-$1-settings-ring"
  else
    fail "the Settings focused control has no focus ring: ${focus_box:-}"
  fi
  type_keys -k Down || fail "moving the Settings list cursor for focus shots failed"
  expect_poll "the Settings list cursor is shown after keys" true ipc smoke readShownDescendant "$settings_kind" vgs.settings ListCursor shown
  take_posed "focus-$1-settings-list-cursor"
  settings_close
}

# The theme previews, one shot a theme, taken only when named: each theme
# applied on the desktop a user sees, the standard bar widgets over the
# stand-ins the bar, panels, AI Usage and Network scenes use, the System
# window on Displays over the device fakes, and Ghostty running the
# owner's tmux and LazyVim (--dotfiles) on this plugin's files with
# Neo-tree open. Each shot is theme-preview-<name>; scripts/theme-previews.sh
# makes each package's preview.jpg from it.
preview_workspaces() { hypr -j workspaces | py_reply 'import json,sys; print(json.dumps(sorted(w["name"] for w in json.load(sys.stdin))))'; }
preview_windows() { hypr -j clients | py_reply 'import json,sys; print(len([c for c in json.load(sys.stdin) if c["mapped"]]))'; }
preview_tmux() { "${shell_env[@]}" PATH="$shell_start_path" tmux "$@"; }
# preview_drawn: whether Neovim has drawn Neo-tree and its status line.
preview_drawn() {
  local pane
  pane="$(preview_tmux capture-pane -p -t vgshell:1 2>/dev/null)" || { echo False; return; }
  [[ $pane == *"~/Projects/vgshell"* && $pane == *NORMAL* ]] && echo True || echo False
}
preview_terminal_pid=""
# preview_terminal_start: tmux with Neovim in its first window and fish in
# its second, then Ghostty on it, so the theme just applied is the one
# Ghostty, tmux and Neovim read as they start.
preview_terminal_start() {
  preview_tmux new-session -d -s vgshell -c "$home/Projects/vgshell" -x 140 -y 42 || { fail "the preview's tmux session did not start"; return; }
  preview_tmux new-window -d -t vgshell -c "$home/Projects/vgshell" || fail "the preview's second tmux window did not open"
  preview_tmux send-keys -t vgshell:1 "nvim ThemeCard.qml -c 'Neotree show'" Enter || fail "Neovim did not start in tmux"
  spawn "$sandbox/preview-terminal.log" "${shell_env[@]}" PATH="$shell_start_path" TERM=xterm-256color ghostty -e tmux attach -t vgshell
  preview_terminal_pid="$spawn_pid"
  expect_poll "Neovim draws Neo-tree and its status line" True preview_drawn
}
preview_terminal_stop() {
  [[ -z $preview_terminal_pid ]] || kill -- "-$preview_terminal_pid" 2>/dev/null || true
  preview_terminal_pid=""
  preview_tmux kill-server 2>/dev/null || true
}
# preview_package NAME: NAME's package where apply finds it: vgs ships in
# the tree; a catalog package is laid out as install lays it out, with the
# wallpaper it applies first (scripts/theme-preview-wallpaper.js).
preview_package() {
  local name="$1" dest
  [[ $name == vgs ]] && return 0
  dest="$home/.config/vgshell/themes/$name"
  rm -rf -- "${dest:?}"
  mkdir -p -- "$dest/backgrounds"
  cp -- "$repo/themes/catalog/$name/theme.json" "$dest/theme.json"
  [[ ! -f $repo/themes/catalog/$name/terminal.json ]] || cp -- "$repo/themes/catalog/$name/terminal.json" "$dest/terminal.json"
  [[ ! -d $repo/themes/catalog/$name/targets ]] || cp -R -- "$repo/themes/catalog/$name/targets" "$dest/targets"
  cp -- "${preview_wallpaper[$name]}" "$dest/backgrounds/"
}
scene_theme-previews() { # MODE
  local id name status=0 first_output link target
  # The harness keeps workspace 100 alive for the bar rows' wide pill; a
  # user's desktop has no such workspace. The two windows float at set
  # places, so the wallpaper shows around them, and the pointer is hidden.
  # They go in the configuration, since each theme's apply reloads it.
  hypr_lua_save previews
  sed -i '/workspace = "100", persistent = true/d' "$home/.config/hypr/hyprland.lua"
  cat >>"$home/.config/hypr/hyprland.lua" <<'LUA'
hl.window_rule({ name = "preview-system", match = { title = "^System Settings$" }, float = true, size = { 960, 660 }, move = { 920, 470 } })
hl.window_rule({ name = "preview-terminal", match = { class = "^com\\.mitchellh\\.ghostty$" }, float = true, size = { 1100, 700 }, move = { 60, 80 } })
hl.config({ cursor = { invisible = true } })
LUA
  expect "Hyprland reloads without workspace 100" ok hypr reload
  expect_poll "workspace 100 is gone" '["1", "2"]' preview_workspaces
  devices_up || status=$?
  ((status == 0)) || { fail "the device fakes for the previews did not start: $devices_state"; return; }
  devices_system_tree >/dev/null || { fail "the fakes' system tree for the previews is unreadable"; return; }
  devices_ready network-shot || { fail "the network fakes for the previews are not ready"; return; }
  device_reply nmcli 0 'org.freedesktop.NetworkManager.network-control:yes' -t -f PERMISSION,VALUE general permissions
  expect "the previews have a saved fake profile" ok python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" prepare
  expect "the previews have two wired fake devices" ok python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" wired
  device_reply nmcli 0 $'GENERAL.DEVICE:enp10s0\nGENERAL.TYPE:ethernet\nGENERAL.STATE:100 (connected)\nIP4.ADDRESS[1]:192.0.2.10/24\nIP4.GATEWAY:192.0.2.1' -t device show enp10s0
  for id in vgs.network vgs.bluetooth vgs.sound vgs.displays vgs.system; do
    expect "enabling $id for the previews is allowed" ok ipc shell setPluginEnabled "$id" true
  done
  for id in vgs.launcher vgs.updates vgs.ai-usage vgs.agent-warden vgs.network vgs.bluetooth vgs.sound vgs.settings; do
    expect "$id is placed for the previews" ok ipc shell setPluginPlaced "$id" true
  done
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  for _ in $(seq 1 16); do
    id="$(notice_plugin)" || id=unread
    [[ $id == null ]] && break
    expect_poll "the requirement notice of $id maps" 1 layer_count vgs:notice
    expect_poll "the requirement notice of $id holds the keyboard" true ipc smoke noticeFocused
    type_keys -k Escape || fail "sending Escape to the requirement notice of $id failed"
    expect_poll "Escape closes the requirement notice of $id" closed notice_moved_from "$id"
  done
  expect_poll "no requirement notice is left" null notice_shown
  expect_poll "the displays service lists the three fake displays" 3 displays_listed
  first_output="$(ipc smoke readInstance service vgs.displays outputs | py_reply 'import json,sys; print(json.load(sys.stdin)[0]["identifier"])')" || fail "the outputs the displays service reads are unreadable"
  expect "the XDR is on the output" ok ipc vgs.displays invoke assign "{\"device\":\"usb:class/hidraw/hidraw0/device#VGSSMOKEXDR01\",\"output\":\"$first_output\"}"
  # The owner's tmux and LazyVim, copied, never linked. For the sandbox:
  # panes start fish, not his agent-confine shell; his pane-exit reap hook,
  # which needs his systemd scopes, is dropped; status-right, which names
  # his user and host, is empty; his Neovim reads the sandbox's theme
  # state. His installed plugins and Mason tools are copied, so nothing installs.
  rm -rf -- "${home:?}/.config/tmux" "${home:?}/.config/nvim" "${home:?}/Projects/vgshell"
  mkdir -p -- "$home/.config/ghostty" "$home/.tmux/plugins" "$home/.local/share/nvim" "$home/Projects"
  cp -R -- "$preview_dotfiles/tmux/.config/tmux" "$home/.config/tmux"
  cp -- "$preview_dotfiles/tmux/.tmux.conf" "$home/.tmux.conf"
  sed -i -e '/^set-hook -ga pane-exited .*tmux-scope-reap/d' -e 's|^set -g default-shell .*|set -g default-shell /usr/bin/fish|' \
    -e 's|^set -g status-right .*|set -g status-right ""|' "$home/.tmux.conf"
  cp -R -- "$HOME/.tmux/plugins/tmux-smooth-scroll" "$home/.tmux/plugins/"
  cp -R -- "$preview_dotfiles/nvim/.config/nvim" "$home/.config/nvim"
  printf 'dofile("%s/.local/state/vgshell/theme/neovim.lua")\n' "$home" >"$home/.config/nvim/plugin/vgs-theme.lua"
  cp -R --reflink=auto -- "$HOME/.local/share/nvim/lazy" "$HOME/.local/share/nvim/site" "$HOME/.local/share/nvim/mason" "$home/.local/share/nvim/"
  # A link the copy kept into his data, such as treesitter's queries, names
  # the sandbox's copy instead.
  while IFS= read -r -d '' link; do
    target="$(readlink -- "$link")"
    ln -sfnT -- "$home/.local/share/nvim/${target#"$HOME/.local/share/nvim/"}" "$link"
  done < <(find "$home/.local/share/nvim" -type l -lname "$HOME/.local/share/nvim/*" -print0)
  cp -R -- "$repo/shell/plugins/vgs.themes" "$home/Projects/vgshell"
  # His Ghostty font and padding; the theme's colours come from its target.
  cat >"$home/.config/ghostty/config" <<'GHOSTTY'
font-family = "JetBrainsMono Nerd Font Mono"
font-style = Normal
font-size = 10
adjust-cell-height = 15%
window-padding-x = 10
window-padding-y = 10,0
window-padding-balance = false
window-theme = ghostty
cursor-style = block
cursor-style-blink = false
resize-overlay = never
confirm-close-surface = false
GHOSTTY
  for id in ghostty neovim; do cp -R -- "$checkout/themes/targets/$id" "$repo/themes/targets/$id"; done
  hover "$((mon_w - 2))" "$((mon_h - 2))" || true
  for name in "${preview_themes[@]}"; do
    preview_package "$name"
    sandbox_vgshell theme apply "$name" >/dev/null || true
    expect_poll "the $name theme is published" "$name" ipc smoke themeName
    if [[ $name == vgs ]]; then
      expect_poll "vgs draws Black" 1 layer_count vgs:background
    else
      expect_poll "$name's wallpaper is drawn" 1 layer_count vgs:background
    fi
    preview_terminal_start
    expect_poll "the terminal is mapped" 1 preview_windows
    # The System window opens last, so it is on top and focused.
    expect "System → Displays summons" ok ipc shell summon window vgs.system '{"pane":"vgs.displays"}'
    expect_poll "System → Displays is shown" '["vgs.displays"]' window_panes
    expect_poll "both windows are mapped" 2 preview_windows
    take_raw "theme-preview-$name"
    expect "the System window hides" ok ipc shell hide window vgs.system
    expect_poll "the System window is gone" hidden system_shown
    preview_terminal_stop
    expect_poll "the terminal is gone" 0 preview_windows
  done
  hypr_lua_restore previews
  expect "Hyprland reloads the harness's configuration" ok hypr reload
}

scene_theme-browser() { # MODE
  local selected
  selected_path() { ipc smoke readDescendant overlay vgs.themes ThemeView selected | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("previewImage") or d.get("image") or "")'; }
  selected_ready() { selected="$(selected_path)" && [[ -n $selected ]] && ipc smoke images overlay vgs.themes | python3 -c 'import json,sys; path=sys.argv[1]; print(any(i[0] == path and i[1] == "ready" for i in json.load(sys.stdin)))' "$selected"; }
  mkdir -p -- "$themes_mismatch"
  printf '%s\n' '{ "schemaVersion": 1, "name": "other", "tokens": {} }' >"$themes_mismatch/theme.json"
  expect "vgs.themes enables for the theme browser shot" ok ipc shell setPluginEnabled vgs.themes true
  expect_poll "vgs.themes is built for the theme browser shot" True record_exists vgs.themes
  expect "the theme browser opens" ok ipc shell summon overlay vgs.themes '{"view":"themes"}'
  expect_poll "the theme browser maps" 1 layer_count vgs:overlay
  expect_poll "the theme browser holds the keyboard" true ipc smoke activeFocusIn overlay vgs.themes
  expect_poll "the theme browser reads its cards" true ipc smoke readDescendant overlay vgs.themes ThemeView loaded
  park_pointer
  take "theme-browser-$1-loaded"
  hover_card "the pointer rests on the theme browser's next card" && take_posed "theme-browser-$1-hover"
  park_pointer
  type_keys zzqx || fail "typing the theme browser's empty filter failed"
  expect_poll "the theme browser's filter matches no card" 0 theme_view_count
  take "theme-browser-$1-empty"
  type_keys -k Escape || fail "clearing the theme browser's filter failed"
  type_keys mismatch || fail "typing the refused package's name failed"
  expect_poll "the theme browser selects the refused package" '"mismatch"' ipc smoke readDescendant overlay vgs.themes ThemeView selectedName
  type_keys -k Return || fail "Enter on the refused package failed"
  expect_poll "the theme browser names the refused package's problem" True theme_view_problem
  take "theme-browser-$1-failure"
  # A new open starts with no filter and no problem line.
  expect "the theme browser hides before the catalog shot" ok ipc shell hide overlay vgs.themes
  expect_poll "the theme browser is gone before the catalog shot" 0 layer_count vgs:overlay
  expect "the theme browser opens for the catalog shot" ok ipc shell summon overlay vgs.themes '{"view":"themes"}'
  expect_poll "the theme browser reads its cards for the catalog shot" true ipc smoke readDescendant overlay vgs.themes ThemeView loaded
  type_keys "$theme_card" || fail "typing the theme-browser card failed"
  expect_poll "the theme browser selects $theme_card" "\"$theme_card\"" ipc smoke readDescendant overlay vgs.themes ThemeView selectedName
  expect_poll "the selected catalog image is ready" True selected_ready
  take "theme-browser-$1-catalog-$theme_card"
  # Enter installs and applies the catalog card, whose wallpapers are not
  # downloaded, so the view offers them; Not now declines, and vgs and
  # the mode's theme are applied again before the installed shot.
  type_keys -k Return || fail "Enter on the catalog theme-browser card failed"
  expect_poll "the theme browser offers $theme_card's wallpapers" "\"$theme_card\"" theme_view_offer
  park_pointer
  take "theme-browser-$1-download"
  click_item overlay vgs.themes Button "Not now" || fail "the click on Not now failed"
  expect_poll "Not now declines the offer" null theme_view_offer
  park_pointer
  expect "the theme browser hides before the installed shot" ok ipc shell hide overlay vgs.themes
  expect_poll "the theme browser is gone before the installed shot" 0 layer_count vgs:overlay
  themes_restore "$1" "the theme browser's install"
  rm -rf -- "${home:?}/.config/vgshell/themes/${theme_card:?}"
  mkdir -p -- "$home/.config/vgshell/themes/$theme_card/backgrounds"
  cp -- "$repo/themes/catalog/$theme_card/theme.json" "$home/.config/vgshell/themes/$theme_card/theme.json"
  [[ ! -f $repo/themes/catalog/$theme_card/terminal.json ]] || cp -- "$repo/themes/catalog/$theme_card/terminal.json" "$home/.config/vgshell/themes/$theme_card/terminal.json"
  "$imagemagick" "$repo/scripts/smoke/fixtures/theme-image.jpg" -resize 2560x1440\! "$home/.config/vgshell/themes/$theme_card/backgrounds/preview.jpg"
  expect "the theme browser opens for the installed shot" ok ipc shell summon overlay vgs.themes '{"view":"themes"}'
  expect_poll "the installed theme browser reads its cards" true ipc smoke readDescendant overlay vgs.themes ThemeView loaded
  type_keys "$theme_card" || fail "typing the installed theme-browser card failed"
  expect_poll "the theme browser selects installed $theme_card" "\"$theme_card\"" ipc smoke readDescendant overlay vgs.themes ThemeView selectedName
  expect_poll "the installed theme browser image is ready" True selected_ready
  take "theme-browser-$1-installed-$theme_card"
  record_item "theme-browser-$1-installed-$theme_card" "$(theme_browser_box)"
  expect "the theme browser hides" ok ipc shell hide overlay vgs.themes
  expect_poll "the theme browser is gone" 0 layer_count vgs:overlay
  # The next mode's catalog shot must show the card as the catalog has it.
  rm -rf -- "${home:?}/.config/vgshell/themes/${theme_card:?}" "${themes_mismatch:?}"
}

# The wallpaper browser over a catalog package with the mode's look,
# flexoki-light in light and nord in every other mode, applied with two
# images, and a second monitor, which gives the browser its monitor scope.
# Each shot first reads the package's scheme published. The scene removes
# the monitor and restores the mode's theme, so a later scene starts from
# the run's own state.
wallpaper_output="VGS-SHOT"
# overlays_on OUTPUT: the live vgs:overlay layers on that output.
overlays_on() { hypr -j layers | python3 -c 'import json,sys; m=json.load(sys.stdin).get(sys.argv[1]); print(0 if m is None else sum(1 for lv in m["levels"].values() for l in lv if l["namespace"]=="vgs:overlay" and l["pid"]!=-1))' "$1"; }
# wallpaper_look NAME LOOK: the published scheme is LOOK, NAME's own.
wallpaper_look() { expect_poll "the wallpaper browser shows the $2 look of $1" "\"$2\"" ipc smoke themeValue scheme.mode; }
# wallpaper_images_of NAME: the image files the themes service's retained
# list holds for package NAME, sorted, as JSON.
wallpaper_images_of() { ipc smoke readInstance service vgs.themes images | py_reply 'import json,sys; i=json.load(sys.stdin)["images"] or []; print(json.dumps(sorted(x["background"] for x in i if x["theme"] == sys.argv[1])))' "$1"; }
scene_wallpaper-browser() { # MODE
  local name=nord look
  [[ $1 != light ]] || name=flexoki-light
  local theme_dir="$home/.config/vgshell/themes/$name"
  look="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tokens"]["scheme"]["mode"])' "$repo/themes/catalog/$name/theme.json")" || fail "the $name catalog package names no scheme for the wallpaper browser shot"
  # The runner's install writes the catalog marker, with no wallpapers, so
  # the Theme source ends on the download card.
  rm -rf -- "${theme_dir:?}"
  sandbox_vgshell theme install "$name" >/dev/null || fail "$name installs for the wallpaper browser shot"
  mkdir -p -- "$theme_dir/backgrounds"
  cp -- "$checkout/scripts/smoke/fixtures/theme-image.jpg" "$theme_dir/backgrounds/a.jpg"
  cp -- "$checkout/scripts/smoke/fixtures/theme-image.jpg" "$theme_dir/backgrounds/b.jpg"
  sandbox_vgshell theme apply "$name" >/dev/null || fail "$name applies for the wallpaper browser shot"
  expect_poll "$name is published for the wallpaper browser shot" "$name" ipc smoke themeName
  expect "the nested compositor adds a monitor for the wallpaper browser shot" ok hypr output create headless "$wallpaper_output"
  expect "vgs.themes enables for the wallpaper browser shot" ok ipc shell setPluginEnabled vgs.themes true
  expect_poll "vgs.themes is built for the wallpaper browser shot" True record_exists vgs.themes
  # In light set_mode published flexoki-light already, so the name proves
  # no apply; the service's images, which the browser opens on, must hold
  # the two the apply chose from.
  expect_poll "the themes service lists $name's two images for the wallpaper browser shot" '["a.jpg", "b.jpg"]' wallpaper_images_of "$name"
  expect "the wallpaper browser opens" ok ipc shell summon overlay vgs.themes '{"view":"wallpapers"}'
  expect_poll "the wallpaper browser maps" 1 layer_count vgs:overlay
  expect_poll "the wallpaper browser holds the keyboard" true ipc smoke activeFocusIn overlay vgs.themes
  expect_poll "the wallpaper browser reads its cards" true ipc smoke readDescendant overlay vgs.themes WallpaperView loaded
  expect_poll "the wallpaper browser is on $SHOT_OUTPUT" 1 overlays_on "$SHOT_OUTPUT"
  expect_poll "the wallpaper browser shows its monitor scope" true ipc smoke readDescendant overlay vgs.themes WallpaperView scoped
  park_pointer
  wallpaper_look "$name" "$look"
  take "wallpaper-browser-$1"
  wallpaper_look "$name" "$look"
  hover_card "the pointer rests on the wallpaper browser's next card" && take_posed "wallpaper-browser-$1-hover"
  park_pointer
  type_keys a. || fail "typing the wallpaper browser's filter failed"
  expect_poll "the wallpaper browser's filter reaches the view" '"a."' ipc smoke readDescendant overlay vgs.themes WallpaperView filterText
  wallpaper_look "$name" "$look"
  take "wallpaper-browser-$1-filter"
  type_keys -k Escape || fail "clearing the wallpaper browser's filter failed"
  expect_poll "Escape clears the wallpaper browser's filter" '""' ipc smoke readDescendant overlay vgs.themes WallpaperView filterText
  type_keys -k End || fail "End in the wallpaper browser failed"
  expect_poll "End selects the wallpaper download card" '"download"' wallpaper_selected_kind
  wallpaper_look "$name" "$look"
  take "wallpaper-browser-$1-download"
  type_keys -M alt -k s -m alt || fail "Alt+S in the wallpaper browser failed"
  expect_poll "Alt+S shows every source's images" '"all"' ipc smoke readDescendant overlay vgs.themes WallpaperView source
  wallpaper_look "$name" "$look"
  take "wallpaper-browser-$1-all"
  type_keys -M alt -k s -m alt || fail "Alt+S back to the wallpaper theme source failed"
  expect_poll "the wallpaper browser returns to the theme source" '"theme"' ipc smoke readDescendant overlay vgs.themes WallpaperView source
  type_keys -k Home || fail "Home in the wallpaper browser failed"
  expect_poll "Home selects the first wallpaper image card" '"image"' wallpaper_selected_kind
  # Keep the loaded card while its file disappears, so Enter reaches the
  # real runner's missing-image refusal without changing the view's state.
  mv -- "$theme_dir/backgrounds" "$theme_dir/backgrounds-missing" || { fail "wallpaper-browser-$1-failure: backgrounds move failed"; return; }
  type_keys -k Return || fail "Enter on the missing wallpaper image failed"
  expect_poll "wallpaper-browser-$1-failure: the failure line is visible" True wallpaper_failure_shown
  if [[ $(wallpaper_failure_shown) == True ]]; then
    wallpaper_look "$name" "$look"
    take "wallpaper-browser-$1-failure"
  fi
  mv -- "$theme_dir/backgrounds-missing" "$theme_dir/backgrounds" || { fail "wallpaper-browser-$1-failure: backgrounds restore failed"; return; }
  expect "the wallpaper browser hides" ok ipc shell hide overlay vgs.themes
  expect_poll "the wallpaper browser is gone" 0 layer_count vgs:overlay
  expect "the wallpaper browser shot's monitor is removed" ok hypr output remove "$wallpaper_output"
  # Applying vgs restores its shipped Black wallpaper after the package's image.
  sandbox_vgshell theme apply vgs >/dev/null || fail "vgs applies after the wallpaper browser shot"
  expect_poll "Black is drawn after the wallpaper browser shot" 1 layer_count vgs:background
  rm -rf -- "${theme_dir:?}"
  set_mode "$1"
}

launcher_rows() { ipc smoke launcherRows overlay vgs.launcher; }
launcher_rows_labels() { launcher_rows | py_reply 'import json,sys; print(json.dumps([r[1] for r in json.load(sys.stdin)]))'; }
launcher_card_box() { ipc smoke descendantGeometry overlay vgs.launcher | py_reply 'import json,sys; print(json.dumps(next((r["box"] for r in json.load(sys.stdin) if r["type"] == "GlassSurface" and r["visible"]), None)))'; }
# settled_box HOST ID TYPE TEXT: `same` when two readings of that item's box
# a frame apart agree, `moving` when they differ.
settled_box() {
  local first second
  first="$(ipc smoke itemGeometry "$@")" || return 1
  sleep 0.05
  second="$(ipc smoke itemGeometry "$@")" || return 1
  [[ $first == \[* && $first == "$second" ]] && echo same || echo moving
}
launcher_file_listed() { launcher_rows | python3 -c 'import json,sys; t=sys.stdin.read(); print(t.startswith("[") and any(r[0] == "file" and r[1] == sys.argv[1] for r in json.loads(t)))' "$1"; }
launcher_listed() { launcher_rows | python3 -c 'import json,sys; t=sys.stdin.read(); print(t.startswith("[") and len(json.loads(t)) > 2)'; }
scene_launcher() { # MODE
  local second motion
  expect "the launcher summons" ok ipc vgs.launcher invoke summon '{}'
  expect_poll "the launcher maps its overlay" 1 layer_count vgs:overlay
  expect_poll "the launcher holds the keyboard" true ipc smoke activeFocusIn overlay vgs.launcher
  take "launcher-$1-open"
  # The orbiting edge light: frames a moment apart, each proved to differ
  # from the one before, so the light is seen moving.
  for i in 1 2 3; do sleep 0.3; SHOT_SETTLE_S=1 take "launcher-$1-orbit-$i"; done
  type_keys sh || fail "typing the fixed application query failed"
  expect_poll "the launcher shows the fixed search rows" '["Shelly", "Shut down", "Avahi SSH Server Browser", "Sunshine", "Screenshot"]' launcher_rows_labels
  launcher_rows >"$SHOT_DIR/launcher-$1-results.json"
  # A resting result comparison must not depend on the caret's blink phase.
  motion="$(ipc smoke themeValue motion.scale)"
  cp -- "$theme_file" "$sandbox/launcher-theme.json"
  python3 - "$theme_file" <<'PYLAUNCHER'
import json, os, sys
path = sys.argv[1]
theme = json.load(open(path))
theme.setdefault("tokens", {}).setdefault("motion", {})["scale"] = 0
with open(path + ".tmp", "w") as out:
    json.dump(theme, out)
os.replace(path + ".tmp", path)
PYLAUNCHER
  expect_poll "the launcher result frame has stopped motion" 0 ipc smoke themeValue motion.scale
  take "launcher-$1-results"
  record_item "launcher-$1-results" "$(launcher_card_box)"
  cp -- "$sandbox/launcher-theme.json" "$theme_file.tmp"
  mv -T -- "$theme_file.tmp" "$theme_file"
  expect_poll "the launcher restores theme motion" "$motion" ipc smoke themeValue motion.scale
  type_keys -M ctrl -k a -m ctrl -k BackSpace || fail "clearing the fixed application query failed"
  type_keys -M ctrl -k b -m ctrl || fail "sending Ctrl+B failed"
  expect_poll "the launcher lists its categories" True launcher_listed
  take "launcher-$1-list"
  type_keys -k Down || fail "sending Down failed"
  expect_poll "Down selects the second row" 1 ipc smoke readInstance overlay vgs.launcher selectedIndex
  take "launcher-$1-selected"
  second="$(launcher_rows | python3 -c 'import json,sys; print(json.load(sys.stdin)[2][1])')" || second=""
  hover_text "the pointer rests on the launcher's third row" overlay vgs.launcher QQuickText "$second" \
    && expect_poll "the pointer selects the third row" 2 ipc smoke readInstance overlay vgs.launcher selectedIndex \
    && take_posed "launcher-$1-hover"
  # The file flyout: a right click on a file hit, then the pointer on one of
  # its entries, whose highlight draws over the flyout's glass.
  touch -- "$home/shots-flyout.txt"
  type_keys "f:shots-flyout" || fail "typing a file search failed"
  expect_poll "the file search lists the planted file" True launcher_file_listed shots-flyout.txt
  if file_at="$(centre_of "$(ipc smoke itemGeometry overlay vgs.launcher QQuickText shots-flyout.txt)")" && [[ $file_at != none ]] && read -r fx fy <<<"$file_at" && hover "$fx" "$fy" && right_click "$fx" "$fy"; then
    # The flyout grows in from the click; its entries hold still once it has.
    expect_poll "the flyout has opened" same settled_box overlay vgs.launcher QQuickText "Copy path"
    hover_text "the pointer rests on the flyout's Copy path" overlay vgs.launcher QQuickText "Copy path" && take_posed "launcher-$1-flyout"
  else
    fail "the right click on the planted file failed"
  fi
  park_pointer
  type_keys -k Escape -k Escape -k Escape || fail "sending Escape failed"
  expect_poll "the launcher closes" 0 layer_count vgs:overlay
}

notify() { # APP SUMMARY BODY ACTIONS HINTS: prints the id
  "${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.Notify "$1" 0 "" "$2" "$3" "$4" "$5" 30000 | python3 -c 'import re,sys; print(re.search(r"uint32 (\d+)", sys.stdin.read()).group(1))'
}
notes() { ipc vgs.notifications invoke "$1" "${2:-}"; }
card_hovered() { ipc smoke layerItems vgs.notifications NotificationCard summary,hovered | py_reply 'import json,sys; print(any(v["hovered"] for s, r, v in json.load(sys.stdin) if v["summary"] == sys.argv[1]))' "$1"; }
card_centre() { ipc smoke layerItems vgs.notifications NotificationCard summary | python3 -c 'import json,sys; y0=int(sys.argv[2])
for screen, (x, y, w, h), v in json.load(sys.stdin):
    if v["summary"] == sys.argv[1]: print(x + w // 2, y0 + y + h // 2); break' "$1" "$bar_reserved"; }
on_screen() { notes status | python3 -c 'import json,sys; print(json.load(sys.stdin)["onScreen"])'; }
acme_emoji() { notes status | python3 -c 'import json,sys; print(json.load(sys.stdin)["slack"]["emoji"]["teams"].get("T0ACME", 0))'; }
slack_badges() { ipc smoke layerItems vgs.notifications NotificationCard showsBadge,app | python3 -c 'import json,sys; print(json.dumps([v["showsBadge"] for _, _, v in json.load(sys.stdin) if v["app"] == "Slack"][:3]))'; }
# notification_header_shot NAME: one shot of the open panel, with its
# header's box on the output recorded for a crop.
notification_header_box() {
  local layer
  layer="$(surface_box vgs:panel)" || return 1
  ipc smoke descendantGeometry panel vgs.notifications | py_reply 'import json,sys
t = sys.stdin.read().strip()
rows = json.loads(t) if t.startswith("[") else []
box = next((r["box"] for r in rows if r["type"] == "InboxHeader" and r["box"][3] > 0), None)
layer = json.loads(sys.argv[1])
print("absent" if box is None else json.dumps([layer[0] + box[0], layer[1] + box[1], box[2], box[3]]))' "$layer"
}
notification_header_shot() { # NAME
  take "$1"
  record_item "$1" "$(notification_header_box)"
}
# notification_header_shots MODE: the open inbox's header in each state of
# its controls, then the History's. A tree whose header holds the Sound
# and Do Not Disturb icons takes their four pairs; an older one takes its
# Silence switch off and on.
notification_header_shots() { # MODE
  local state sound dnd states=(:off :on)
  ! tree_has shell/plugins/vgs.notifications/InboxHeader.qml "signal soundRequested" || states=(on:off off:off on:on off:on)
  for state in "${states[@]}"; do
    sound="${state%%:*}" dnd="${state#*:}"
    if [[ -n $sound ]]; then
      expect "Sound turns $sound for the header" "$sound" notes sound "$sound"
      expect_poll "the header reads Sound $sound" "$([[ $sound == on ]] && echo true || echo false)" ipc smoke readInstance panel vgs.notifications sound
    fi
    expect "Do Not Disturb turns $dnd for the header" "$dnd" notes silence "$dnd"
    expect_poll "the header reads Do Not Disturb $dnd" "$([[ $dnd == on ]] && echo true || echo false)" ipc smoke readInstance panel vgs.notifications silenced
    notification_header_shot "notifications-$1-header${sound:+-sound-$sound}-dnd-$dnd"
  done
  [[ -z $sound ]] || expect "Sound turns on after the header shots" on notes sound on
  expect "Do Not Disturb turns off after the header shots" off notes silence off
  expect "the History opens for its header" ok notes history
  expect_poll "the panel is the History" '"history"' ipc smoke readInstance panel vgs.notifications mode
  notification_header_shot "notifications-$1-header-history"
  expect "the inbox opens again after the History's header" ok notes panel
  expect_poll "the panel is the inbox again" '"inbox"' ipc smoke readInstance panel vgs.notifications mode
}
scene_notifications() { # MODE
  local ids=() at
  ids+=("$(notify smoke-build "Build finished" "vgs main is green in 2 min" '[]' '{}')")
  ids+=("$(notify smoke-power "Battery low" "12% left" '[]' '{"urgency": <byte 2>}')")
  ids+=("$(notify smoke-chat "New message" "Lunch at noon?" '["default", "Open", "reply", "Reply"]' '{}')")
  expect_poll "three toasts are on screen" 3 on_screen
  take "notifications-$1-toasts"
  at="$(card_centre "New message")" || at=""
  if [[ -n $at ]]; then
    # shellcheck disable=SC2086
    hover $at || fail "the hover over the actionable toast failed"
    expect_poll "the actionable toast reports the pointer" True card_hovered "New message"
    take_posed "notifications-$1-hover"
  else
    fail "the actionable toast has no card"
  fi
  park_pointer
  expect "the inbox opens" ok notes inbox
  expect_poll "the panel is the inbox" '"inbox"' ipc smoke readInstance service vgs.notifications panelMode
  take "notifications-$1-inbox"
  # A click on the newest notification runs its default action; the inbox
  # shows what is left.
  expect "a click on the newest notification is allowed" ok notes invoke-latest
  expect_poll "the clicked toast leaves the screen" 2 on_screen
  take "notifications-$1-inbox-clicked"
  notification_header_shots "$1"
  expect "the inbox closes" ok notes close
  for id in "${ids[@]}"; do
    "${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null || fail "closing notification $id failed"
  done
  expect "the history clears" ok notes clear-history
  expect_poll "no toast is left" 0 on_screen
  # Slack-shaped notifications, as Slack's web client titles them, from the
  # synthetic Slack under the sandbox's configuration: a direct message, a
  # group message past three people and a channel mention with the
  # workspace's custom emoji, each with the workspace's icon in place of its
  # bracketed name. An older revision draws the shortcode as text.
  [[ -n $rev ]] || expect_poll "acme's custom emoji are made" 1 acme_emoji
  ids=()
  ids+=("$(notify Slack "[acme] in eng-core" "Grace Hopper: @ada the build is green :smoke-party: ship it :smoke-party:" '["default", "View"]' '{"desktop-entry": <"slack">}')")
  ids+=("$(notify Slack "[acme] in ada, grace, alan, edsger, barbara" "alan: lunch at noon?" '["default", "View"]' '{"desktop-entry": <"slack">}')")
  ids+=("$(notify Slack "[acme] from Ada Lovelace" "Did you see the notes?" '["default", "View"]' '{"desktop-entry": <"slack">}')")
  expect_poll "three Slack toasts are on screen" 3 on_screen
  # An older revision's card has no workspace icon to read back.
  [[ -n $rev ]] || expect_poll "each Slack toast draws the workspace icon" '[true, true, true]' slack_badges
  take "notifications-$1-slack"
  for id in "${ids[@]}"; do
    "${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null || fail "closing notification $id failed"
  done
  expect "the history clears" ok notes clear-history
  expect_poll "no toast is left" 0 on_screen
  # Heights: a one-line card, a two-line card and one past its most lines,
  # which stops at the look's maximum height.
  ids=()
  ids+=("$(notify smoke-heights "Screenshot saved" "" '[]' '{}')")
  ids+=("$(notify smoke-heights "Download complete" "report.pdf is in Downloads" '[]' '{}')")
  ids+=("$(notify smoke-heights "Release notes" "$(printf 'A body long enough to run past every line the card may show. %.0s' $(seq 1 12))" '[]' '{}')")
  expect_poll "three height toasts are on screen" 3 on_screen
  take "notifications-$1-heights"
  for id in "${ids[@]}"; do
    "${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null || fail "closing notification $id failed"
  done
  expect "the history clears" ok notes clear-history
  expect_poll "no toast is left" 0 on_screen
  # Icons: a card whose icon the theme lacks, sent as notify-send --icon
  # sends it, and five VGS plugin notices with no icon of their own, with
  # the hints the core's shell.notify.send adds: no tone, info, danger,
  # success and warning, so the bell and each tone's icon show; then the
  # same cards in the inbox, over the black desktop and over a white one,
  # the lightest wallpaper the glass cards sit on.
  ids=()
  ids+=("$(notify smoke-power "Battery caution" "15% left, plug in soon" '[]' '{"image-path": <"vgs-smoke-themeless">}')")
  ids+=("$(notify Updates "Updates are ready" "" '[]' '{"x-vgs-plugin": <"vgs.updates">, "x-vgs-click": <"none">}')")
  ids+=("$(notify Updates "Restart to finish updating" "" '[]' '{"x-vgs-plugin": <"vgs.updates">, "x-vgs-tone": <"info">, "x-vgs-click": <"none">}')")
  ids+=("$(notify Power "Battery critical" "Suspending in 2 minutes" '[]' '{"x-vgs-plugin": <"vgs.power">, "x-vgs-tone": <"danger">, "x-vgs-click": <"none">}')")
  ids+=("$(notify Power "Charging resumed" "" '[]' '{"x-vgs-plugin": <"vgs.power">, "x-vgs-tone": <"success">, "x-vgs-click": <"none">}')")
  ids+=("$(notify Power "Battery saver is on" "Background sync pauses until you plug in" '[]' '{"x-vgs-plugin": <"vgs.power">, "x-vgs-tone": <"warning">, "x-vgs-click": <"none">}')")
  expect_poll "six icon toasts are on screen" 6 on_screen
  take "notifications-$1-icons"
  expect "the inbox opens on the icon cards" ok notes inbox
  expect_poll "the panel is the inbox for the icon cards" '"inbox"' ipc smoke readInstance service vgs.notifications panelMode
  take "notifications-$1-icons-inbox"
  solid_png "$home/white.png" 640 360 255 255 255 || fail "the white desktop image was not written"
  bg_state_names "$home/white.png" || fail "the white desktop's state file was not written"
  expect_poll "the white desktop image is ready" "$home/white.png ready" background_image_on "$main_name"
  expect_poll "the desktop draws white" ffffff pixel 100 100
  take "notifications-$1-icons-inbox-white"
  bg_state_names "$repo/themes/vgs/backgrounds/black.png" || fail "the black desktop's state file was not written"
  expect_poll "the black desktop image is ready again" "$repo/themes/vgs/backgrounds/black.png ready" background_image_on "$main_name"
  expect "the inbox closes after the icon cards" ok notes close
  for id in "${ids[@]}"; do
    "${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null || fail "closing notification $id failed"
  done
  expect "the history clears" ok notes clear-history
  expect_poll "no toast is left" 0 on_screen
}

# hover_widget LABEL ID: the pointer on the centre of bar widget ID,
# arriving by two motions.
hover_widget() {
  local at x y
  at="$(centre_of "$(ipc smoke instanceGeometry "$(bar_key)" "$2")")" || at=none
  if [[ $at == none ]]; then fail "$1: widget $2 has no box"; return 1; fi
  read -r x y <<<"$at"
  if ! hover "$((x - 6))" "$y" || ! hover "$x" "$y"; then fail "$1: the hover failed"; return 1; fi
}
tooltip_opened() { ipc smoke readDescendant "$(bar_key)" "$1" Tooltip opened; }
warden_detail_state() { ipc vgs.agent-warden invoke status '' | py_reply 'import json,sys; d=json.load(sys.stdin).get("detail"); print(d["state"] if d else "unpublished")'; }
# warden_status NAME STATE: the warden's status-NAME.json written fresh,
# read back as STATE, so a surface never shows the status gone stale.
warden_status() {
  warden_put "$1" 0 >/dev/null || fail "writing the warden's $1 status failed"
  expect_poll "the warden reads its $1 status as $2" "$2" warden_detail_state
}
# The pointer on each bar widget: the tooltip of each widget that declares
# one, open, and the hover of the launcher's widget, which declares none; then
# the bar at rest, which a run that starts with this scene has drawn since
# before its first shot.
scene_bar() { # MODE
  local id
  warden_status calm calm
  for id in vgs.agent-warden vgs.updates; do
    hover_widget "the pointer rests on $id" "$id" || continue
    expect_poll "the $id tooltip opens" true tooltip_opened "$id"
    take_posed "bar-$1-tip-${id#vgs.}"
    park_pointer
    expect_poll "the $id tooltip closes" false tooltip_opened "$id"
  done
  hover_widget "the pointer rests on the launcher's widget" vgs.launcher \
    && { ! "$launcher_entry_item" || expect_poll "the launcher's widget shows its hover" true ipc smoke readDescendant "$(bar_key)" vgs.launcher BarItem hovered; } \
    && take_posed "bar-$1-hover-launcher"
  park_pointer
  take "bar-$1"
}

# The pointer on each first-party bar widget the sandbox draws, its tooltip
# open; a widget whose plugin draws no bar item here, for a device or
# program the sandbox lacks, is named and not shot.
widget_centre() { python3 -c 'import json,sys; t=sys.argv[1]; r=json.loads(t) if t.startswith("[") else None; print("%d %d" % (r[0] + r[2] / 2, r[1] + r[3] / 2) if r and r[2] > 0 and r[3] > 0 else "none")' "$1"; }
scene_tooltips() { # MODE
  local id at
  warden_status calm calm
  for id in "${tooltip_widgets[@]}"; do
    at="$(widget_centre "$(ipc smoke instanceGeometry "$(bar_key)" "$id")")" || at=none
    if [[ $at == none ]]; then ok "$id draws no bar item in the sandbox"; continue; fi
    hover_widget "the pointer rests on $id" "$id" || continue
    expect_poll "the $id tooltip opens" true tooltip_opened "$id"
    take "tooltips-$1-${id#vgs.}"
    park_pointer
    expect_poll "the $id tooltip closes" false tooltip_opened "$id"
  done
}

# The Agent Warden panel opened from its shield over a calm status and then
# a problem one, and the Updates window opened from its widget over the
# planted snapshot, with its System row expanded and then the pointer on
# a row. Nothing presses Refresh, so no check runs.
warden_panel_texts() { ipc smoke itemTexts panel vgs.agent-warden Panel; }
warden_panel_lines() { warden_panel_texts | py_reply 'import json,sys; print(sys.argv[1] in json.load(sys.stdin)[0])' "$shots_vsys_line"; }
updates_window() { [[ $(ipc smoke readInstance window vgs.updates rows) != absent ]] && echo open || echo closed; }
updates_pending() { ipc vgs.updates invoke status '' | py_reply 'import json,sys; print(json.load(sys.stdin).get("pending"))'; }
updates_checking() { ipc vgs.updates invoke status '' | py_reply 'import json,sys; print(json.load(sys.stdin).get("checking"))'; }
# updates_snapshot_plant: the updates snapshot fixture as the service's
# status cache, checked now, so the service runs no check while it is
# younger than the interval.
updates_snapshot_plant() {
  mkdir -p -- "$home/.local/state/vgshell/updates"
  python3 - "$checkout/scripts/smoke/fixtures/updates-status.json" "$home/.local/state/vgshell/updates/status.json" <<'PY' || fail "planting the updates snapshot failed"
import json, sys, time
doc = json.load(open(sys.argv[1]))
now = int(time.time() * 1000)
doc["checkedAt"] = now
for source in doc["sources"]:
    source["checkedAt"] = now
json.dump(doc, open(sys.argv[2], "w"))
PY
}
scene_panels() { # MODE
  warden_status calm calm
  click_in vgs:bar "$(bar_key)" vgs.agent-warden BarItem "Agent Warden" || fail "the click on the shield failed"
  expect_poll "the shield opens the warden's panel" True warden_panel_lines
  park_pointer
  take "panels-$1-warden-calm"
  warden_status holding-off problem
  take "panels-$1-warden-problem"
  hover_on "the pointer rests on the panel's Open vsys" panel vgs.agent-warden Button "Open vsys" && take_posed "panels-$1-warden-hover"
  park_pointer
  expect "the warden's panel hides" ok ipc shell hide panel vgs.agent-warden
  expect_poll "the warden's panel is gone" absent warden_panel_texts
  warden_status calm calm
  click_centre "$(bar_key)" vgs.updates || fail "the click on the updates widget failed"
  expect_poll "the widget opens the Updates window" open updates_window
  park_pointer
  take "panels-$1-updates"
  click_in window:Updates window vgs.updates ListItem System || fail "the click on the window's System row failed"
  park_pointer
  take "panels-$1-updates-open"
  hover_on "the pointer rests on the window's VGS row" window vgs.updates ListItem VGS window:Updates && take_posed "panels-$1-updates-hover"
  park_pointer
  expect "the Updates window hides" ok ipc shell hide window vgs.updates
  expect_poll "the Updates window is gone" closed updates_window
  expect "the window started no check" False updates_checking
  scene_themes_panel "$1"
}

# Capture's idle widget, options panel and Settings page Recording section.
# No action or recorder is started.
scene_capture() { # MODE
  expect "Capture is placed for its widget image" ok ipc shell setPluginPlaced vgs.capture true
  expect_poll "Capture's widget is built for its image" false ipc smoke readInstance "$(bar_key)" vgs.capture recording
  park_pointer
  take "capture-$1-widget"
  click_centre "$(bar_key)" vgs.capture || fail "opening Capture from its widget failed"
  expect_poll "Capture opens its options panel" false ipc smoke readInstance panel vgs.capture recording
  park_pointer
  take "capture-$1-panel"
  expect "Capture's panel hides" ok ipc shell hide panel vgs.capture
  expect "the Settings window opens for the Capture page" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for the Capture page" 1 settings_count
  expect "the window opens the Capture page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.capture
  expect_poll "the Capture page is shown" '"vgs.capture"' settings_page
  settings_tab_click Settings || fail "the click on the Settings tab failed"
  expect_poll "the Capture page shows Settings" 0 settings_tab
  jarvis_anchor_shot "capture-settings-$1-recording" SectionHeader Recording
  settings_close
}

# AI Usage's dropdown from its widget, at rest, then scrolled halfway down
# its body, where both dividers show.
usage_shot_rows() { ipc smoke readInstance panel vgs.ai-usage rows | py_reply 'import json,sys; r=json.load(sys.stdin); print(isinstance(r,list) and len(r) >= 3)'; }
scene_ai-usage() { # MODE
  local at y
  expect "enabling AI Usage for its dropdown is allowed" ok ipc shell setPluginEnabled vgs.ai-usage true
  expect "AI Usage's widget is placed" ok ipc shell setPluginPlaced vgs.ai-usage true
  expect_poll "AI Usage's widget shows" true ipc smoke readInstance "$(bar_key)" vgs.ai-usage visible
  click_centre "$(bar_key)" vgs.ai-usage || fail "opening AI Usage from its widget failed"
  expect_poll "the widget opens its panel over its accounts" True usage_shot_rows
  park_pointer
  take "ai-usage-$1-panel"
  at="$(ipc smoke scrollTo panel vgs.ai-usage 0)" || at=""
  if y="$(python3 -c 'import json,sys; _, content, view = json.loads(sys.argv[1]); print(int(content - view)) if content - view > 2 else sys.exit(1)' "$at" 2>/dev/null)"; then
    ipc smoke scrollTo panel vgs.ai-usage "$y" >/dev/null || fail "the AI Usage panel did not scroll"
    take "ai-usage-$1-panel-scrolled"
    ipc smoke descendantGeometry panel vgs.ai-usage >"$out/ai-usage-$1-items.json"
  else
    fail "the AI Usage panel does not scroll: $at"
  fi
  expect "AI Usage's panel hides" ok ipc shell hide panel vgs.ai-usage
  expect_poll "AI Usage's panel is gone" absent ipc smoke readInstance panel vgs.ai-usage rows
}

# The production traffic views over a fixture service in the sandbox copy.
traffic_shot_setting() {
  python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY2' || return 1
import json, os, sys
path, show = sys.argv[1:]
config = json.load(open(path))
rows = config.setdefault("plugins", [])
row = next((r for r in rows if r["id"] == "vgs.traffic"), None)
if row is None:
    row = {"id": "vgs.traffic"}
    rows.append(row)
row["show"] = show
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PY2
  expect "Traffic's display mode reloads" ok ipc shell reloadConfig
  expect_poll "Traffic shows $1" "\"$1\"" ipc smoke readInstance "$(bar_key)" vgs.traffic showMode
}
scene_traffic() { # MODE
  local state show box
  expect "Traffic hides for its Before image" ok ipc shell setPluginPlaced vgs.traffic false
  take "traffic-$1-before-bar"
  expect "Traffic is placed for its After images" ok ipc shell setPluginPlaced vgs.traffic true
  for show in both download upload; do
    traffic_shot_setting "$show" || fail "Traffic's $show setting failed"
    take "traffic-$1-bar-$show"
    box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.traffic)" || box=absent
    record_item "traffic-$1-bar-$show" "$box"
  done
  traffic_shot_setting both || fail "Traffic's both setting failed"
  for state in apps measuring idle capture-needed no-bandwhich; do
    if [[ $state == no-bandwhich ]]; then
      rm -- "${shim:?}/bandwhich"
      tree_rescan "Traffic's missing optional tool is scanned"
    fi
    expect "Traffic's $state fixture publishes" ok ipc vgs.traffic invoke scene "$state"
    click_centre "$(bar_key)" vgs.traffic || fail "opening Traffic's $state panel failed"
    expect_poll "Traffic's panel opens" true ipc smoke readInstance panel vgs.traffic visible
    expect "Traffic's panel takes focus for its image" focused ipc smoke invokeInstance panel vgs.traffic focusInstance ""
    take "traffic-$1-panel-$state"
    box="$(ipc smoke instanceGeometry panel vgs.traffic)" || box=absent
    record_item "traffic-$1-panel-$state" "$box"
    expect "Traffic's panel hides" ok ipc shell hide panel vgs.traffic
    # The hide answers before the popup is gone; a click on the widget
    # then does not open it, so the next state's click waits.
    expect_poll "Traffic's panel is gone" absent ipc smoke readInstance panel vgs.traffic visible
  done
  cp -- "$checkout/scripts/smoke/fixtures/traffic/allow.sh" "$shim/bandwhich"
  tree_rescan "Traffic's optional tool stand-in is scanned for Settings"
  expect "Traffic's capture-needed fixture publishes for Settings" ok ipc vgs.traffic invoke scene capture-needed
  expect "Settings opens Traffic's page" ok ipc shell summon "$settings_kind" vgs.settings '{"plugin":"vgs.traffic"}'
  expect "Settings selects Traffic" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.traffic
  expect_poll "Settings shows Traffic" '"vgs.traffic"' settings_page
  take "traffic-$1-settings-display"
  page_details
  ipc smoke revealText "$settings_kind" vgs.settings Button "Allow" >/dev/null || fail "Traffic's capture action was not revealed"
  take "traffic-$1-settings-capture"
  rm -- "${shim:?}/bandwhich"
  tree_rescan "Traffic's missing optional tool is scanned for Settings"
  expect "Traffic's absent capture fixture publishes for Settings" ok ipc vgs.traffic invoke scene no-bandwhich
  ipc smoke revealText "$settings_kind" vgs.settings RowAction "Install optional tools" >/dev/null || fail "Traffic's optional requirement was not revealed"
  take "traffic-$1-settings-requirements"
  settings_close
  cp -- "$checkout/scripts/smoke/fixtures/traffic/allow.sh" "$shim/bandwhich"
  tree_rescan "Traffic restores its optional tool stand-in"
  expect "Traffic restores its apps fixture" ok ipc vgs.traffic invoke scene apps
}

# The Key Hints window, with the pointer parked.
scene_keyhints() { # MODE
  expect "the Key Hints window summons" ok ipc shell summon window vgs.keyhints '{}'
  expect_poll "the Key Hints window maps" 1 window_count "Key Hints"
  expect "the Key Hints window's root takes the focus" focused ipc smoke invokeInstance window vgs.keyhints focusInstance ""
  park_pointer
  take "keyhints-$1"
  expect "the Key Hints window hides" ok ipc shell hide window vgs.keyhints
  expect_poll "the Key Hints window is gone" 0 window_count "Key Hints"
}

# Jarvis Console over the scripted daemon fixture. It mutates only the
# sandbox copy of the daemon and engine, then restores them before leaving.
scene_jarvis-console() { # MODE
  local plugin="$repo/shell/plugins/vgs.jarvis" backend="$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
  local engine="$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js"
  local before_backend="$sandbox/jarvis-console-$1-jarvisd-before.js"
  local before_engine="$sandbox/jarvis-console-$1-engine-before.js"
  local gates="$sandbox/jarvis-console-$1-gates" startup_gate="$sandbox/jarvis-console-$1-startup-gate"
  local startup_seen="$sandbox/jarvis-console-$1-startup-seen"
  cp -- "$backend" "$before_backend"
  cp -- "$engine" "$before_engine"
  mkdir -p -- "$gates"
  jarvis_console_last() {
    ipc smoke jarvisProcess | py_reply '
import json,sys
s=json.load(sys.stdin)["status"].get("conversation", [])
print("none" if not s else s[-1]["role"]+":"+s[-1]["text"]+":"+s[-1]["stage"])
'
  }
  jarvis_console_lifetime() { ipc smoke jarvisProcess | py_reply 'import json,sys; print(json.load(sys.stdin)["lifetime"]["kind"])'; }
  jarvis_console_approval() {
    ipc smoke jarvisProcess | py_reply '
import json,sys
a=json.load(sys.stdin)["status"]["detail"]["state"]["approval"]
print("drawn" if a["kind"]=="held" and a["shownAt"] is not None else a["kind"])
'
  }
  jarvis_console_mute() { ipc smoke jarvisProcess | py_reply 'import json,sys; print(json.load(sys.stdin)["status"]["detail"]["state"]["mute"]["kind"])'; }
  jarvis_console_focused() {
    ipc smoke itemValues window vgs.jarvis TextField activeFocus | py_reply '
import json,sys
print("true" if any(row.get("activeFocus") is True for row in json.load(sys.stdin)) else "false")
'
  }
  jarvis_console_field_text() { ipc smoke readShownDescendant window vgs.jarvis TextField text; }
  jarvis_console_summon() {
    expect "the Jarvis console summons" ok ipc shell summon window vgs.jarvis '{}'
    expect_poll "the Jarvis console maps" 1 window_count Jarvis
    expect_poll "the Jarvis console text field has focus" true jarvis_console_focused
  }
  jarvis_console_restore() {
    cp -- "$before_backend" "$backend"
    cp -- "$before_engine" "$engine"
    rm -f -- "$plugin/backend/scripted-fixture.js" "$home/.local/state/vgshell/jarvis/mute.json"
  }

  jarvis_setup_requirements
  "$node_bin" "$checkout/scripts/fixtures/jarvis/prepare.js" --gate-daemon "$backend" "$startup_gate" "$startup_seen"
  tree_rescan "the Jarvis gated daemon is scanned"
  expect "enabling vgs.jarvis for the not-ready console image is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the Jarvis gated daemon starts" starting jarvis_console_lifetime
  jarvis_console_summon
  park_pointer
  take_posed "jarvis-console-$1-not-ready"
  expect "the Jarvis console hides after the not-ready image" ok ipc shell hide window vgs.jarvis
  expect "disabling vgs.jarvis after the not-ready image is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone after the not-ready image" absent ipc smoke jarvisProcess
  jarvis_console_restore

  "$node_bin" "$checkout/scripts/fixtures/jarvis/scripted.js" "$backend" "$gates" --mapped-indicator
  "$node_bin" "$checkout/scripts/fixtures/jarvis/scripted.js" --held-approvals "$backend"
  tree_rescan "the Jarvis scripted daemon is scanned"
  expect "enabling vgs.jarvis for console images is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the Jarvis scripted daemon answers hello" ready jarvis_started
  jarvis_console_summon
  park_pointer
  take_posed "jarvis-console-$1-empty"
  type_keys "Draft message for Jarvis" || fail "typing a Jarvis console draft failed"
  expect_poll "the Jarvis console draft is shown" '"Draft message for Jarvis"' jarvis_console_field_text
  park_pointer
  take_posed "jarvis-console-$1-draft"
  type_keys -M ctrl a -m ctrl -k BackSpace || fail "clearing the Jarvis console draft failed"
  expect_poll "the Jarvis console draft clears" '""' jarvis_console_field_text
  expect "the Jarvis console IPC says a typed turn" ok ipc vgs.jarvis invoke say "typed from console"
  expect_poll "the Jarvis console shows the typed user line" "user:typed from console:final" jarvis_console_last
  park_pointer
  take_posed "jarvis-console-$1-thinking"
  : >"$gates/approve-action"
  expect_poll "the Jarvis console turn holds a drawn confirmation" drawn jarvis_console_approval
  park_pointer
  take_posed "jarvis-console-$1-confirming"
  expect "the Jarvis console confirmation stops" ok ipc vgs.jarvis invoke stop ''
  expect_poll "the stopped confirmation ends" none jarvis_console_approval
  # A refused say sends nothing, so the poll sends the turn once.
  expect_poll "the Jarvis console IPC says the typed turn again" ok ipc vgs.jarvis invoke say "typed from console"
  expect_poll "the Jarvis console shows the repeated typed line" "user:typed from console:final" jarvis_console_last
  : >"$gates/brain"
  expect_poll "the Jarvis console shows the scripted reply" "assistant:scripted utterance:partial" jarvis_console_last
  park_pointer
  take_posed "jarvis-console-$1-reply"
  expect "the Jarvis console mutes Jarvis" ok ipc vgs.jarvis invoke mute ''
  expect_poll "muted Jarvis reaches the console" on jarvis_console_mute
  park_pointer
  take_posed "jarvis-console-$1-muted"
  expect "the Jarvis console hides after its images" ok ipc shell hide window vgs.jarvis
  expect "disabling vgs.jarvis after its console images is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone after its console images" absent ipc smoke jarvisProcess
  jarvis_restore_requirements
  jarvis_console_restore
  tree_rescan "the stock Jarvis files are scanned after console images"
  jarvis_notice_close
}

scene_jarvis-audit() { # MODE
  local backend="$repo/shell/plugins/vgs.jarvis/backend/jarvisd.js"
  local engine="$repo/shell/plugins/vgs.jarvis/backend/ChainedEngine.js"
  local saved="$sandbox/jarvis-audit-$1" control size rejected
  cp -- "$backend" "$saved-backend"
  cp -- "$engine" "$saved-engine"
  jarvis_audit_tabs() { ipc smoke itemValues window vgs.jarvis Tabs currentIndex | py_reply 'import json,sys; print(json.dumps([r.get("currentIndex") for r in json.load(sys.stdin)]))'; }
  jarvis_audit_entries() {
    ipc smoke itemValues window vgs.jarvis Label text,visible | py_reply '
import json,sys
rows=json.load(sys.stdin)
tools=[r.get("text") for r in rows if r.get("visible") and r.get("text") in ["files.delete", "release"]]
print(json.dumps(sorted(tools)))
'
  }
  jarvis_audit_check() {
    local before="$failures"
    expect_poll "Audit is the current tab" '[2]' jarvis_audit_tabs
    expect_poll "Audit draws all three planted entries" '["files.delete", "files.delete", "release"]' jarvis_audit_entries
    [[ $failures == "$before" ]]
  }
  jarvis_setup_requirements
  "$node_bin" "$checkout/scripts/fixtures/jarvis/scripted.js" "$backend" "$saved-gates" --mapped-indicator
  # The console fixture has two records. Repeat its first record to exercise
  # a list with more than one separator without building another audit log.
  python3 - "$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
needle='function consoleAudit() { return consoleFailures; }'
assert s.count(needle)==1
p.write_text(s.replace(needle, 'function consoleAudit() { return consoleFailures.concat(consoleFailures.slice(0, 1)); }'))
PY
  for control in empty planted; do
    if [[ $control == planted ]]; then
      "$node_bin" "$checkout/scripts/fixtures/jarvis/scripted.js" --console-data "$backend"
    fi
    tree_rescan "the Audit $control fixture is scanned"
    expect "Jarvis enables for Audit $control" ok ipc shell setPluginEnabled vgs.jarvis true
    expect_poll "the Audit daemon answers hello" ready jarvis_started
    close_notices
    for size in default narrow; do
      [[ $size != narrow ]] || narrow_begin
      expect "the Audit console summons" ok ipc shell summon window vgs.jarvis '{}'
      expect_poll "the Audit console maps" 1 window_count Jarvis
      expect_poll "the Audit console composer has focus" true ipc smoke activeFocusWithin window vgs.jarvis TextField
      type_keys -M ctrl -k Tab -k Tab -m ctrl || fail "selecting Audit failed"
      expect_poll "Audit is the current tab" '[2]' jarvis_audit_tabs
      if [[ $control == empty ]]; then
        rejected="$(
          failures=0 behaviour_failures=0
          jarvis_audit_check >"$saved-control.log" || true
          echo "$failures"
        )"
        expect "control: no planted log fails the Audit scene" 1 echo "$rejected"
        sed 's/^/  CONTROL  /' "$saved-control.log"
      else
        if jarvis_audit_check; then
          park_pointer
          take_posed "jarvis-audit-$1-$size"
        fi
      fi
      expect "the Audit console hides" ok ipc shell hide window vgs.jarvis
      [[ $size != narrow ]] || narrow_end
      [[ $control != empty ]] || break
    done
    expect "Jarvis disables after Audit $control" ok ipc shell setPluginEnabled vgs.jarvis false
    expect_poll "the Audit daemon is gone" absent ipc smoke jarvisProcess
  done
  cp -- "$saved-backend" "$backend"
  cp -- "$saved-engine" "$engine"
  rm -f -- "$repo/shell/plugins/vgs.jarvis/backend/scripted-fixture.js"
  jarvis_restore_requirements
  tree_rescan "the stock Jarvis files are scanned after Audit images"
  jarvis_notice_close
}

# The clipboard history over the copies its setup made, the newest copy
# selected under the pinned one, with the pointer parked.
scene_clipboard() { # MODE
  expect "the clipboard history summons" ok ipc vgs.clipboard invoke toggle ''
  expect_poll "the clipboard history maps its overlay" 1 layer_count vgs:overlay
  expect_poll "the clipboard history holds the keyboard" true ipc smoke activeFocusIn overlay vgs.clipboard
  type_keys -k Down || fail "sending Down failed"
  expect_poll "Down selects the newest copy" 1 ipc smoke readInstance overlay vgs.clipboard current
  expect "the clipboard history root takes the focus" focused ipc smoke invokeInstance overlay vgs.clipboard focusInstance ""
  park_pointer
  take "clipboard-$1"
  type_keys -k Escape || fail "sending Escape failed"
  expect_poll "the clipboard history closes" 0 layer_count vgs:overlay
}

# voice_dictates: whether the tree's Voice dictates through the core's
# `dictation` capability, over the daemon the core starts; a tree from
# before it follows voxtype's status stream itself.
voice_dictates() { grep -qF '"dictation"' "$tree/shell/plugins/vgs.voice/manifest.json"; }
# voice_stand_ins: the smoke's voxtype stand-in and its wtype
# (scripts/smoke/fixtures/voxtype/) in the shell's stand-in directory, so
# the daemon the core starts for Voice hears no microphone and types
# nothing. Its copy answers the config and info verbs from this run's
# files, as rows/voice.sh's does: dictation sounds read on, and the model
# reads installed once voice_model_installed exists.
voice_model_installed="$sandbox/voice-model-installed"
voice_stand_ins() {
  printf 'true\n' >"$sandbox/voice-feedback-value"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'voice_installed=%q voice_feedback=%q voice_feedback_sets=%q\n' "$voice_model_installed" "$sandbox/voice-feedback-value" "$sandbox/voice-feedback-sets"
    printf 'voice_feedback_unreadable=%q voice_feedback_refused=%q voice_feedback_dropped=%q\n' "$sandbox/voice-feedback-unreadable" "$sandbox/voice-feedback-refused" "$sandbox/voice-feedback-dropped"
    printf '. %q\n' "$repo/scripts/smoke/fixtures/voxtype/voxtype"
  } >"$shim/voxtype"
  cp -- "$repo/scripts/smoke/fixtures/voxtype/wtype" "$shim/wtype"
  chmod 755 "$shim/voxtype" "$shim/wtype"
}
voice_stand_ins_removed() { rm -f -- "${shim:?}/voxtype" "${shim:?}/wtype" "${voice_model_installed:?}"; }
# voxtype-audio-bridge's stand-in: a status line, then a frame every 50 ms
# until TERM. A tree whose Voice requires the bridge raises its requirement
# notice on an enable without it.
voice_bridge_stand_in() {
  cat >"$shim/voxtype-audio-bridge" <<'EOF'
#!/usr/bin/env bash
printf '{"status":"connected"}\n'
trap 'exit 0' TERM
while :; do printf '{"peak":0.42,"rms":0.18,"vad":1,"ts_ms":0}\n'; sleep 0.05; done
EOF
  chmod 755 "$shim/voxtype-audio-bridge"
}
# voice_enable_notice_closed LABEL: on a tree whose Voice requires voxtype,
# an enable that leaves voxtype or its bridge missing raises Voice's
# requirement notice, read and closed with Not now; a tree from before
# raises none, and closes nothing.
voice_enable_notice_closed() {
  tree_has shell/plugins/vgs.voice/manifest.json '"install": "on-request"' || return 0
  expect_poll "$1 raises Voice's requirement notice" '"vgs.voice"' notice_plugin
  close_notices
}
# The capability's state as Voice reads it: its daemon and what Voice
# shows of its own dictation.
voice_daemon() { ipc smoke readInstance service vgs.voice dictationState | py_reply 'import json,sys; d=json.load(sys.stdin); print(d["daemon"], d["phase"])'; }

# Voice's on-screen display over the bare desktop: Voice records through
# the core over the voxtype stand-in, or on a tree from before that a
# stand-in status stream holds recording, and the stand-in bridge prints a
# frame every 50 ms, then both are removed with the plugin disabled.
scene_voice() { # MODE
  if voice_dictates; then
    voice_stand_ins
  else
    cat >"$shim/voxtype" <<'EOF'
#!/usr/bin/env bash
[[ $* == 'status --follow --extended --format json' ]] || exit 0
printf '{"state":"recording","backend":"ONNX CPU","device":"default","model":"parakeet-tdt-0.6b-v3"}\n'
exec sleep infinity
EOF
  fi
  voice_bridge_stand_in
  chmod 755 "$shim/voxtype"
  rescan "the Voice stand-ins are scanned"
  expect "enabling vgs.voice for its display is allowed" ok ipc shell setPluginEnabled vgs.voice true
  if voice_dictates; then
    expect_poll "the core's daemon is ready for Voice's display" "ready idle" voice_daemon
    expect "Voice starts a recording for its display" ok ipc vgs.voice invoke toggle ""
  fi
  expect_poll "Voice draws its plasma orb while recording" 1 ipc smoke layerItemsWith vgs.voice Plasma active true
  expect_poll "the stand-in's frames reach Voice" true voice_level_flowing
  park_pointer
  take "voice-$1-osd"
  expect "disabling vgs.voice after its display is allowed" ok ipc shell setPluginEnabled vgs.voice false
  expect_poll "Voice's display is gone" 0 ipc smoke layerItemsWith vgs.voice Plasma active true
  voice_stand_ins_removed
  rm -f -- "${shim:?}/voxtype-audio-bridge"
  rescan "the Voice stand-ins are removed"
}
# Voice's Keys section on its Settings page, with Voice on so each row
# reads the description its shortcut registered; voxtype stays absent, so
# nothing records. Then the pointer on the first key's info icon, on a
# tree whose Keys rows draw one: a form row's info icon opens no tooltip,
# and an older tree's has the tooltip delay to open in.
voice_keys_first="Start or stop dictation"
voice_keys_section() { settings_section Keys KeyField "Dictate while held"; }
voice_key_shown() { [[ $(ipc smoke windowGeometry "$settings_kind" vgs.settings KeyField "$voice_keys_first") == \[* ]] && echo shown || echo absent; }
scene_voice-keys() { # MODE
  local section start x y
  expect "enabling vgs.voice for its keys is allowed" ok ipc shell setPluginEnabled vgs.voice true
  expect_poll "vgs.voice is built for its keys" True record_exists vgs.voice
  for _ in $(seq 1 10); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
  expect "the Settings window opens for Voice's keys" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for Voice's keys" 1 settings_count
  expect "the window opens the Voice page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.voice
  expect_poll "the Voice page is shown" '"vgs.voice"' settings_page
  expect_poll "the Voice page's first key reads its description" shown voice_key_shown
  if section="$(voice_keys_section)"; then
    read -r start _ _ <<<"$section"
    settings_scroll_to "$((start - 16))" || fail "the scroll to Voice's Keys section failed"
    take "voice-keys-$1"
  else
    fail "Voice's Keys section is unreadable: $section"
  fi
  # The icon draws no text, so hover_on's text reading cannot find it; the
  # pointer goes to its centre.
  if [[ $(ipc smoke windowGeometry "$settings_kind" vgs.settings InfoButton "About $voice_keys_first") == \[* ]]; then
    settle_hold || fail "the held mode could not be taken again for the info icon"
    if read -r x y < <(window_point "$settings_surface" "$settings_kind" vgs.settings InfoButton "About $voice_keys_first") && hover "$((x - 4))" "$y" && hover "$x" "$y"; then
      for _ in $(seq 1 10); do [[ $(shot_chrome_read) == tooltip ]] && break; sleep 0.2; done
      take_posed "voice-keys-$1-info"
    else
      fail "the pointer could not reach the first key's info icon"
    fi
  else
    ok "the tree draws no info icon on Voice's keys"
  fi
  park_pointer
  settings_close
  expect "disabling vgs.voice after its keys is allowed" ok ipc shell setPluginEnabled vgs.voice false
  expect_poll "vgs.voice is gone after its keys" False record_exists vgs.voice
}

# The Jarvis page's row actions, the daemon ready over the J09 world as the
# settings scene enables it: the Settings tab's Setup section, then two
# places of the Details tab whose status lines offer a step, the Browser
# driver line and the AI model section. Each shot puts its anchor `margin`
# px under the scroll area's top through the probe's scrollTo, so the
# pointer never crosses the page and a tree whose rows differ in height
# still draws the anchor at one place.
# jarvis_anchor TYPE TEXT: the top of the first shown TYPE reading TEXT in
# the page's scroll area's content coordinates.
jarvis_anchor() {
  local area box
  area="$(settings_scroll)" && [[ $area == \{* ]] || { echo "area=${area:-unread}"; return 1; }
  box="$(ipc smoke windowGeometry "$settings_kind" vgs.settings "$1" "$2")" && [[ $box == \[* ]] || { echo "anchor=${box:-unread}"; return 1; }
  python3 -c 'import json,sys
a, b = (json.loads(v) for v in sys.argv[1:3])
print(int(b[1] - a["bar"][1] + a["contentY"]))' "$area" "$box"
}
# jarvis_anchor_shot NAME TYPE TEXT: the page scrolled to TYPE TEXT, taken.
jarvis_anchor_shot() {
  local top margin=12
  if top="$(jarvis_anchor "$2" "$3")"; then
    ipc smoke scrollTo "$settings_kind" vgs.settings "$((top - margin))" >/dev/null || fail "the scroll to the Jarvis page's $3 failed"
    park_pointer
    take "$1"
  else
    fail "the Jarvis page's $3 is unreadable: $top"
  fi
}
# The label of the tree's input step on the Setup tab: its checklist entry
# where the tree has one, else the input reader's own row.
jarvis_input_label() {
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["status"]; print(s.get("setupInput", s["input"])["label"])' "$repo/shell/plugins/vgs.jarvis/manifest.json"
}
# Whether the Setup tab draws its steps: the required AI model and Voice
# rows by manifest key, once each with a chip, the set
# scripts/smoke/rows/jarvis-setup.sh's setup_rows reads.
jarvis_setup_drawn() { ipc smoke setupRows "$settings_kind" vgs.settings | py_reply 'import json,sys; t=sys.stdin.read(); r=json.loads(t) if t.startswith("[") else []; print(all([x["key"] for x in r if x["chips"]].count(k) == 1 for k in ("setupModel", "setupVoice")))'; }
jarvis_ships_backups() { grep -q '"fallbacks"' "$repo/shell/plugins/vgs.jarvis/manifest.json"; }
jarvis_backups_drawn() { ipc smoke invokeInstance "$settings_kind" vgs.settings listItems '{"id":"vgs.jarvis","key":"fallbacks"}' | py_reply 'import json,sys; t=sys.stdin.read(); print(t!="absent" and len(json.loads(t)) == 2)'; }
jarvis_brain_choice_ids() {
  ipc smoke readInstance "$settings_kind" vgs.settings plugins | py_reply 'import json,sys
rows=json.load(sys.stdin)
row=next((p for p in rows if p["id"]=="vgs.jarvis"), None)
choices=[] if row is None else row.get("settingChoices", {}).get("brain", [])
values=[c["value"] for c in choices if c.get("value") and "(unavailable)" not in c.get("label", "")]
print("\n".join(values[:2]) if len(values) >= 2 else "waiting")'
}
jarvis_brain_choices_ready() { [[ $(jarvis_brain_choice_ids) != waiting ]] && echo True || echo False; }
jarvis_cause_status_rows() { # CAUSE PHASE
  "$node_bin" - "$repo" "$1" "$2" <<'JS'
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const [repo, cause, phase] = process.argv.slice(2);
function lib(file) {
  const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, "");
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(source + "\nthis.__exports = Object.assign({}, this);", sandbox, { filename: file });
  return sandbox.__exports;
}
function literal(source, pattern, label) {
  const match = source.match(pattern);
  if (!match) throw new Error("missing " + label);
  return match[1];
}
const gate = lib(path.join(repo, "shell/plugins/vgs.jarvis/SetupGate.js"));
const session = lib(path.join(repo, "shell/plugins/vgs.jarvis/Session.js"));
const service = fs.readFileSync(path.join(repo, "shell/plugins/vgs.jarvis/Service.qml"), "utf8");
const readyText = literal(service, /publish\("info", message\.daemon === "locked" \? "Jarvis is locked; microphone is off" : "([^"]+)"\)/, "ready literal");
const audioReady = literal(service, /shell\.status\.set\("audio", \{ tone: "ok", text: "([^"]+)" \}\)/, "audio literal");
const rows = [["audio", { tone: "ok", text: audioReady }], ["setupHome", { hidden: true }]];
function detail(gate) {
  const state = JSON.parse(JSON.stringify(session.initial()));
  state.gate = gate;
  return { phase: session.phaseOf(state), seq: 1, state };
}
// The steps as Service.qml's publishSetup words them: the Voice step
// declares named actions, so the judge refuses readiness's boolean on it.
// voiceStep keeps the last Voice step value, which shapes Local voice.
let voiceStep = null;
function addSetup(answer, check) {
  const values = gate.readiness(answer);
  values.setupVoice = gate.voiceCheck(values.setupVoice, check);
  voiceStep = values.setupVoice;
  for (const key of ["setup", "setupVoice", "setupModel"]) rows.push([key, values[key]]);
}
function addReady(answer, gateValue) {
  const planted = detail(gateValue || { kind: "up" });
  rows.push(["daemon", { tone: "info", text: readyText }], ["detail", planted]);
  addSetup(answer, planted.state.check);
}
if (phase === "before") {
  if (cause === "speech=local-ready-timeout" || cause === "setup=probe-timeout") addReady({ kind: "answered", causes: [] }, { kind: "up" });
  else {
    const danger = literal(service, /publish\("danger", "([^"]+)"\)/, "old danger literal");
    rows.push(["detail", null], ["daemon", { tone: "danger", text: danger }]);
    addSetup({ kind: "stopped" }, null);
  }
} else if (cause === "speech=local-ready-timeout" || cause === "setup=probe-timeout") {
  addReady({ kind: "answered", causes: [cause] }, cause === "speech=local-ready-timeout" ? { kind: "down", reason: "unconfigured" } : { kind: "up" });
  if (cause === "setup=probe-timeout") {
    const manifest = JSON.parse(fs.readFileSync(path.join(repo, "shell/plugins/vgs.jarvis/manifest.json"), "utf8"));
    // The row as Service.qml shapes LocalRuntime's reading: the sandbox
    // keeps the manifest's default voice, Local.
    rows.push(["localRuntime", gate.localVoiceStep(gate.checkFailure("timeout", manifest.status.localRuntime), "local", voiceStep)]);
  }
} else {
  rows.push(["detail", null], ["daemon", gate.startStatus(cause, false)]);
  addSetup({ kind: "problem", cause }, null);
  // The held provider drops the service's own republish of the Local voice
  // row, so the scene shapes it beside the planted Voice step, from
  // setup-local's reading in the sandbox, which has no local voice.
  rows.push(["localRuntime", gate.localVoiceStep({ tone: "warning", text: "Not set up", action: true }, "local", voiceStep)]);
}
for (const [key, value] of rows) console.log(key + "\t" + JSON.stringify(value));
JS
}
jarvis_plant_cause() { # CAUSE PHASE
  local key value reply failed=0
  while IFS=$'\t' read -r key value; do
    reply="$(ipc smoke heldStatusSet "$key" "$value")" || reply=unread
    [[ $reply == ok ]] || { printf '%s=%s\n' "$key" "$reply"; failed=1; }
  done < <(jarvis_cause_status_rows "$1" "$2")
  [[ $failed == 0 ]] && echo ok || return 1
}
scene_jarvis-setup() { # MODE
  local accounts_before="$sandbox/jarvis-backups-accounts-before"
  if jarvis_ships_backups; then
    jarvis_backup_choice_accounts plant "$accounts_before"
  fi
  expect "enabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the Jarvis daemon answers hello without a restart" ready jarvis_started
  # Jarvis requires wlrctl, which the shell finds absent, so enabling it
  # raises its requirement notice, which closes before the shots.
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
  expect "the Settings window opens for the Jarvis page" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for the Jarvis page" 1 settings_count
  expect "the window opens the Jarvis page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.jarvis
  expect_poll "the Jarvis page is shown" '"vgs.jarvis"' settings_page
  page_details
  expect_poll "the Jarvis page shows its daemon ready" True jarvis_page_ready
  jarvis_anchor_shot "jarvis-details-$1-status" Label "Browser driver"
  jarvis_anchor_shot "jarvis-details-$1-model" SectionHeader "AI model"
  page_setup
  expect_poll "the Jarvis Setup section draws its rows" True jarvis_setup_drawn
  jarvis_anchor_shot "jarvis-setup-$1" SectionHeader Setup
  settings_tab_click Settings || fail "the click on the Settings tab failed"
  expect_poll "the Jarvis page shows Settings" 0 settings_tab
  if jarvis_ships_backups; then
    expect_poll "the Jarvis AI model choice list shows two rows" True jarvis_brain_choices_ready
    jarvis_backups plant
    expect_poll "the Jarvis backup model list shows two rows" True jarvis_backups_drawn
  fi
  jarvis_anchor_shot "jarvis-settings-$1-model" SectionHeader "AI model"
  if jarvis_ships_backups; then
    jarvis_anchor_shot "jarvis-settings-$1-backups" SectionHeader "Backup models"
  fi
  jarvis_backups clear
  settings_close
  expect "disabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone" absent ipc smoke jarvisProcess
  if jarvis_ships_backups; then
    jarvis_backup_choice_accounts restore "$accounts_before"
  fi
  jarvis_voice_states "$1"
}

# The Voice step over a ready local voice, as rows/jarvis-setup.sh plants
# it: the local speech stand-in, the marker of the tree's first declared
# tier and the world's local-mode at ready, with Jarvis's required tools
# stood in. First voxtype missing, then the smoke's voxtype stand-in on the
# shell's PATH with its dictation model installed, then a microphone check
# the stand-in source wakes. The
# Local voice field lists the tree's own setup-local choices for a machine
# that runs every tier and picks small: its `choices` over that reading,
# in place of the two rows scripts/fixtures/jarvis/prepare.js plants.
# The Voice step's chips, then its offered actions, as setup_rows reads them.
jarvis_voice_step() { ipc smoke setupRows "$settings_kind" vgs.settings | py_reply 'import json,sys; t=sys.stdin.read(); r=json.loads(t) if t.startswith("[") else []; v=next((x for x in r if x["key"]=="setupVoice"),None); print("absent" if v is None else " / ".join([c[0] for c in v["chips"]] + [b["text"] for b in v["buttons"]]))'; }
jarvis_check_state() { ipc smoke jarvisProcess | py_reply 'import json,sys; d=json.load(sys.stdin)["status"].get("detail"); print(d["state"]["check"]["kind"] if d else "pending")'; }
jarvis_tier_list_open() { ipc smoke readMatchingDescendant "$settings_kind" vgs.settings Select currentText "$1" listOpen; }
jarvis_real_tiers() { # TIERS READY
  python3 - "$repo/shell/plugins/vgs.jarvis" "$1" "$2" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
from pathlib import Path
plugin, path, ready = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
loader = importlib.machinery.SourceFileLoader("setup_local", str(plugin / "setup-local"))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
value = module.measurement().manifest(plugin / "artifacts.json")
answer = module.choices(value, {"gpu": 8192, "ram": 32768, "threads": 16}, ready)
open(path + ".next", "w").write(json.dumps(answer))
os.replace(path + ".next", path)
print(answer["choices"][0]["label"])
PY
}
jarvis_voice_page() { # LABEL
  expect "enabling vgs.jarvis $1 is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the Jarvis daemon answers hello $1" ready jarvis_started
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
  expect "the Settings window opens $1" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps $1" 1 settings_count
  expect "the window opens the Jarvis page $1" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.jarvis
  expect_poll "the Jarvis page is shown $1" '"vgs.jarvis"' settings_page
  page_setup
  expect_poll "the Jarvis Setup section draws its rows $1" True jarvis_setup_drawn
}
jarvis_voice_states() { # MODE
  local state="$home/.local/state/vgshell/jarvis" data="$home/.local/share/vgshell/jarvis" world="$sandbox/jarvis-world"
  local tier auto field x y
  jarvis_setup_requirements || fail "the Jarvis requirement stand-ins are not written"
  tree_rescan "the Jarvis requirement stand-ins are scanned for the voice states"
  mkdir -p -- "$state" "$data/local/venv/bin"
  cp -- "$checkout/scripts/fixtures/jarvis-local-speech/standin.py" "$data/local/venv/bin/python"
  chmod 700 -- "$data/local/venv/bin/python"
  tier="$(python3 -c 'import json,os,sys
tier=next(iter(json.load(open(sys.argv[1]))["tiers"]))
open(sys.argv[3],"w").write(json.dumps({"tier": tier, "data": os.path.realpath(sys.argv[2])}))
open(os.path.join(sys.argv[2],"scenario.json"),"w").write(json.dumps({"start": "ready", "checks": [{"afterFrames": 1}]}))
print(tier)' "$repo/shell/plugins/vgs.jarvis/artifacts.json" "$data/local" "$state/local-ready.json")" || fail "the local voice marker is not written"
  cp -- "$world/local-mode" "$sandbox/voice-states-local-mode" 2>/dev/null || printf 'absent\n' >"$sandbox/voice-states-local-mode"
  cp -- "$world/local-tiers.json" "$sandbox/voice-states-local-tiers" || fail "the planted local tiers are not saved"
  printf 'ready\n' >"$world/local-mode"
  auto="$(jarvis_real_tiers "$world/local-tiers.json" "$tier")" || fail "setup-local's choices are not read"
  # voxtype missing.
  jarvis_voice_page "with voxtype missing"
  expect_poll "the Voice step offers Set up dictation with voxtype missing" "To do / Set up dictation" jarvis_voice_step
  jarvis_anchor_shot "jarvis-setup-$1-voxtype-missing" SectionHeader Setup
  settings_close
  expect "disabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone" absent ipc smoke jarvisProcess
  # voxtype ready.
  voice_stand_ins
  : >"$voice_model_installed"
  rescan "the voxtype stand-in is scanned for the voice states"
  jarvis_voice_page "with voxtype ready"
  expect_poll "the Voice step offers Check microphone with voxtype ready" "To do / Check microphone" jarvis_voice_step
  jarvis_anchor_shot "jarvis-setup-$1-voxtype-ready" SectionHeader Setup
  # The local voice ready: the check the stand-in source wakes.
  expect_poll "the local voice can be checked" ready jarvis_check_state
  expect "Check microphone asks the daemon to start" ok ipc vgs.jarvis invoke check-microphone ''
  expect_poll "the Voice step reads Done after the check" "Done / Check microphone" jarvis_voice_step
  jarvis_anchor_shot "jarvis-setup-$1-local-voice-ready" SectionHeader Setup
  settings_tab_click Settings || fail "the click on the Settings tab failed"
  expect_poll "the Jarvis page shows Settings" 0 settings_tab
  expect_poll "the Local voice field reads setup-local's pick" false jarvis_tier_list_open "$auto"
  jarvis_anchor_shot "jarvis-settings-$1-local-voice" SectionHeader "Local voice"
  if field="$(ipc smoke invokeInstance "$settings_kind" vgs.settings fieldGeometry '{"id":"vgs.jarvis","key":"localTier"}')" && [[ $field == \[* ]] \
    && read -r x y < <(at_centre "$settings_surface" "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); h=json.loads(sys.argv[2]); print(json.dumps([r[0] + r[2] - 40, r[1], 40, h]))' "$field" "$(ipc smoke themeValue row.height)")") \
    && hover "$((x - 1))" "$y" && click "$x" "$y"; then
    expect_poll "the Local voice field opens its list" true jarvis_tier_list_open "$auto"
    take_posed "jarvis-settings-$1-local-voice-open"
    type_keys -k Escape || fail "sending Escape to the Local voice field failed"
    expect_poll "the Local voice field closes its list" false jarvis_tier_list_open "$auto"
  else
    fail "the Local voice field is unreadable: ${field:-}"
  fi
  park_pointer
  settings_close
  expect "disabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone" absent ipc smoke jarvisProcess
  voice_stand_ins_removed
  rm -f -- "${state:?}/local-ready.json" "${data:?}/local/scenario.json"
  cp -- "$sandbox/voice-states-local-mode" "$world/local-mode"
  cp -- "$sandbox/voice-states-local-tiers" "$world/local-tiers.json" || fail "the planted local tiers are not put back"
  jarvis_restore_requirements
}

# The ElevenLabs voices (VGS-1202) read from a stored key, as a user with
# network reads them: the daemon runs on the sandbox's backend copy, whose
# elevenlabs row names the loopback stand-in
# scripts/fixtures/jarvis/elevenlabs-voices.js, which that copy starts
# inside the daemon's private network namespace. One stored ElevenLabs key
# is planted for the daemon and for the account reader's world, the
# keyring stand-ins answer it present, and Jarvis picks it as the sole key.
# Hearing is the ready local voice of jarvis_voice_states with the
# voxtype stand-in. First the stand-in refuses the key, as ElevenLabs
# refuses a key that may not read voices: the Settings tab's Voice section
# and the Details tab's ElevenLabs voices line. Then it lists the voices:
# the Voice section, the Voice field's list open, and that Details line.
elevenlabs_port=45127
# elevenlabs_line_has TEXT: whether the Details tab's ElevenLabs voices
# line reads TEXT.
elevenlabs_line_has() { ipc smoke itemTexts "$settings_kind" vgs.settings StatusRow | py_reply 'import json,sys; print(any("ElevenLabs voices" in r and sys.argv[1] in r for r in json.load(sys.stdin)))' "$1"; }
elevenlabs_page() { # LABEL
  expect "enabling vgs.jarvis $1 is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the Jarvis daemon answers hello $1" ready jarvis_started
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
  expect "the Settings window opens $1" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps $1" 1 settings_count
  expect "the window opens the Jarvis page $1" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.jarvis
  expect_poll "the Jarvis page is shown $1" '"vgs.jarvis"' settings_page
  page_details
}
elevenlabs_off() {
  settings_close
  expect "disabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone" absent ipc smoke jarvisProcess
}
scene_elevenlabs-voices() { # MODE
  local state="$home/.local/state/vgshell/jarvis" data="$home/.local/share/vgshell/jarvis" world="$sandbox/jarvis-world"
  local backend="$repo/shell/plugins/vgs.jarvis/backend" config="$home/.config/vgshell/shell.json"
  local origin="http://127.0.0.1:$elevenlabs_port" first="My voice (cloned)" field x y
  local saved="$sandbox/elevenlabs-voices-before"
  mkdir -p -- "$saved" "$state" "$data/local/venv/bin"
  cp -- "$backend/Providers.js" "$backend/jarvisd.js" "$config" "$saved/" || fail "the ElevenLabs scene's files are not saved"
  [[ ! -e $state/keys.json ]] || cp -- "$state/keys.json" "$saved/keys.json"
  python3 - "$backend" "$checkout/scripts/fixtures/jarvis/elevenlabs-voices.js" "$elevenlabs_port" "$world/elevenlabs-mode" "$origin" "$state/keys.json" "$world/keys.json" "$config" <<'PY' || fail "the ElevenLabs stand-in is not planted"
import json, os, sys
backend, standin, port, mode, origin, keys, world_keys, config = sys.argv[1:]
providers = os.path.join(backend, "Providers.js")
text = open(providers).read()
needle = 'base: "https://api.elevenlabs.io",'
assert text.count(needle) == 1, "the elevenlabs row's base matches once"
open(providers, "w").write(text.replace(needle, 'base: "%s",' % origin))
with open(os.path.join(backend, "jarvisd.js"), "a") as daemon:
    daemon.write("\nrequire(%s).serve(%s, %s);\n" % (json.dumps(standin), port, json.dumps(mode)))
reference = {"provider": "elevenlabs", "account": "personal", "origin": origin,
             "attributes": {"service": "vgs-jarvis", "provider": "elevenlabs", "account": "personal", "origin": origin}}
for path in (keys, world_keys):
    open(path, "w").write(json.dumps([reference]))
value = json.load(open(config))
row = next((r for r in value.setdefault("plugins", []) if r["id"] == "vgs.jarvis"), None)
if row is None:
    row = {"id": "vgs.jarvis"}; value["plugins"].append(row)
row["voiceProvider"] = "elevenlabs"
open(config + ".next", "w").write(json.dumps(value))
os.replace(config + ".next", config)
PY
  expect "deliver the ElevenLabs voice provider" ok ipc shell reloadConfig
  jarvis_setup_requirements || fail "the Jarvis requirement stand-ins are not written"
  voice_stand_ins
  tree_rescan "the Jarvis requirement and voxtype stand-ins are scanned for the ElevenLabs voices"
  cp -- "$checkout/scripts/fixtures/jarvis-local-speech/standin.py" "$data/local/venv/bin/python"
  chmod 700 -- "$data/local/venv/bin/python"
  python3 -c 'import json,os,sys
tier=next(iter(json.load(open(sys.argv[1]))["tiers"]))
open(sys.argv[3],"w").write(json.dumps({"tier": tier, "data": os.path.realpath(sys.argv[2])}))
open(os.path.join(sys.argv[2],"scenario.json"),"w").write(json.dumps({"start": "ready"}))' "$repo/shell/plugins/vgs.jarvis/artifacts.json" "$data/local" "$state/local-ready.json" || fail "the local voice marker is not written"
  cp -- "$world/local-mode" "$saved/local-mode" 2>/dev/null || printf 'absent\n' >"$saved/local-mode"
  printf 'ready\n' >"$world/local-mode"
  # The key refused.
  printf 'refused\n' >"$world/elevenlabs-mode"
  elevenlabs_page "with the ElevenLabs key refused"
  expect_poll "the ElevenLabs voices line reads Could not read voices" True elevenlabs_line_has "Could not read voices"
  jarvis_anchor_shot "elevenlabs-voices-details-$1-refused" Label "ElevenLabs voices"
  settings_tab_click Settings || fail "the click on the Settings tab failed"
  expect_poll "the Jarvis page shows Settings" 0 settings_tab
  jarvis_anchor_shot "elevenlabs-voices-settings-$1-refused" SectionHeader Voice
  elevenlabs_off
  # The voices listed.
  printf 'listed\n' >"$world/elevenlabs-mode"
  elevenlabs_page "with the ElevenLabs voices listed"
  expect_poll "the ElevenLabs voices line reads 6 voices" True elevenlabs_line_has "6 voices"
  jarvis_anchor_shot "elevenlabs-voices-details-$1-listed" Label "ElevenLabs voices"
  settings_tab_click Settings || fail "the click on the Settings tab failed"
  expect_poll "the Jarvis page shows Settings" 0 settings_tab
  expect_poll "the Voice field reads the account's first voice" false jarvis_tier_list_open "$first"
  jarvis_anchor_shot "elevenlabs-voices-settings-$1-listed" SectionHeader Voice
  if field="$(ipc smoke invokeInstance "$settings_kind" vgs.settings fieldGeometry '{"id":"vgs.jarvis","key":"voice"}')" && [[ $field == \[* ]] \
    && read -r x y < <(at_centre "$settings_surface" "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); h=json.loads(sys.argv[2]); print(json.dumps([r[0] + r[2] - 40, r[1], 40, h]))' "$field" "$(ipc smoke themeValue row.height)")") \
    && hover "$((x - 1))" "$y" && click "$x" "$y"; then
    expect_poll "the Voice field opens its list" true jarvis_tier_list_open "$first"
    take_posed "elevenlabs-voices-settings-$1-open"
    type_keys -k Escape || fail "sending Escape to the Voice field failed"
    expect_poll "the Voice field closes its list" false jarvis_tier_list_open "$first"
  else
    fail "the Voice field is unreadable: ${field:-}"
  fi
  park_pointer
  elevenlabs_off
  voice_stand_ins_removed
  cp -- "$saved/Providers.js" "$saved/jarvisd.js" "$backend/"
  cp -- "$saved/shell.json" "$config"
  expect "deliver the settings from before the ElevenLabs voices" ok ipc shell reloadConfig
  rm -f -- "${state:?}/keys.json" "${state:?}/local-ready.json" "${data:?}/local/scenario.json" "${world:?}/keys.json" "${world:?}/elevenlabs-mode"
  [[ ! -e $saved/keys.json ]] || cp -- "$saved/keys.json" "$state/keys.json"
  cp -- "$saved/local-mode" "$world/local-mode"
  rm -rf -- "${saved:?}"
  jarvis_restore_requirements
}

# The Cloned voice (VGS-1385) for the owner's sheets, posed as
# rows/jarvis-setup.sh poses it: the clone reader answers from the world's
# clone-status.json (scripts/fixtures/jarvis/prepare.js instruments
# CloneRuntime.qml), so no model, recording or tier is judged. The local
# voice is the Large tier, ready: its marker, the world's local-mode at
# ready and setup-local's own choices for a card its pick takes as Large.
# Each Setup tab shot is anchored at the input step, which both trees draw
# just before where the Cloned voice step goes, so a tree without it is
# shot at the same place. The consent shots run the real tui/clone-voice.sh
# under gum in a kitty, as dictation-setup does, and close it at its first
# question, before any download. The clone setup has no launcher entry,
# so the manager's openTui refuses it as undeclared (listedTuiRequest in
# shell/Core/PluginLogic.js); the scene opens it as the step's button does,
# through the manager's act on the clonedVoiceSetup row, which opens the
# action the row offers. The clone setup's later run and Remove recording
# run over the harness's stand-in terminal, held live (hold_runs) while
# the reader's next answer is written, so the run's end reads it.
clone_ships() { tree_has shell/plugins/vgs.jarvis/manifest.json '"clonedVoiceSetup"'; }
# clone_answer TONE TEXT ACTION RECORDING: setup-local clone status's
# answer, beside a ready Large tier.
clone_answer() {
  python3 - "$sandbox/jarvis-world/clone-status.json" "$@" <<'PY'
import json,os,sys
path,tone,text,action,recording=sys.argv[1:]
open(path+".next","w").write(json.dumps({"tone":tone,"text":text,"action":action,"recording":recording=="true","tierReady":True}))
os.replace(path+".next",path)
PY
}
# clone_large_tiers PATH: setup-local's own choices for a machine whose
# card its pick() takes as Large (GPU_SHARE times large's GPU peak and
# dictation's model, and RAM_SHARE times its RAM peak), with Large ready,
# written to PATH; prints the label the Local voice field then shows.
clone_large_tiers() {
  python3 - "$repo/shell/plugins/vgs.jarvis" "$1" <<'PY'
import importlib.machinery, importlib.util, json, os, sys
from pathlib import Path
plugin, path = Path(sys.argv[1]), sys.argv[2]
loader = importlib.machinery.SourceFileLoader("setup_local", str(plugin / "setup-local"))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
value = module.measurement().manifest(plugin / "artifacts.json")
answer = module.choices(value, {"gpu": 16384, "ram": 32768, "threads": 16}, "large")
assert answer["pick"] == "large", answer["pick"]
open(path + ".next", "w").write(json.dumps(answer))
os.replace(path + ".next", path)
print(answer["choices"][0]["label"])
PY
}
# clone_setting true|false: the Cloned voice setting in the user's
# shell.json, false as no entry, delivered by a reload.
clone_setting() {
  python3 - "$home/.config/vgshell/shell.json" "$1" <<'PY' || { fail "the Cloned voice setting is not written"; return; }
import json,os,sys
value=json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {"version": 2}
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
if sys.argv[2]=="true": row["clonedVoice"]=True
else: row.pop("clonedVoice",None)
open(sys.argv[1]+".next","w").write(json.dumps(value))
os.replace(sys.argv[1]+".next",sys.argv[1])
PY
  expect "deliver the Cloned voice setting $1" ok ipc shell reloadConfig
}
# The Cloned voice setting the running daemon's Session holds.
clone_daemon_setting() {
  ipc smoke jarvisProcess | py_reply 'import json,sys
d=json.load(sys.stdin)
detail=d.get("status",{}).get("detail") if isinstance(d,dict) else None
print(json.dumps(detail["state"]["settings"].get("clonedVoice", False)) if isinstance(detail,dict) else "none")'
}
# clone_step LABEL: the Setup tab step LABEL's chip texts.
clone_step() {
  ipc smoke setupRows "$settings_kind" vgs.settings | py_reply 'import json,sys
t=sys.stdin.read(); r=json.loads(t) if t.startswith("[") else []
v=next((x for x in r if x["label"]==sys.argv[1]),None)
print("absent" if v is None else " / ".join(c[0] for c in v["chips"]))' "$1"
}
# clone_offers LABEL: whether the page shows an enabled RowAction LABEL.
clone_offers() {
  local box
  box="$(ipc smoke windowGeometry "$settings_kind" vgs.settings RowAction "$1")" || return 1
  [[ $box == \[* ]] && echo shown || echo absent
}
clone_world_tool="$(dirname -- "$self")/clone-world.py"
# The world of doubles clone_steps prepares for the mode it runs in.
clone_world=""
clone_tui_windows() { hypr -j clients | py_reply 'import json,sys; print(sum(c["class"] == "org.vgs.tui" and c["mapped"] for c in json.load(sys.stdin)))'; }
clone_tui_floating() { hypr -j clients | py_reply 'import json,sys; c=[c for c in json.load(sys.stdin) if c["class"] == "org.vgs.tui" and c["mapped"]]; print(str(len(c)==1 and c[0]["floating"]).lower())'; }
clone_asking() { [[ -e $sandbox/clone-voice-confirm ]] && echo asking || echo waiting; }
# How many gum confirms the clone setup has asked in this run.
clone_confirms() { if [[ -f $sandbox/clone-voice-confirms ]]; then wc -l <"$sandbox/clone-voice-confirms" | tr -d ' '; else echo 0; fi; }
# The mapped floating terminal's whole hyprctl client entry.
clone_tui_client() { hypr -j clients | py_reply 'import json,sys; c=[c for c in json.load(sys.stdin) if c["class"] == "org.vgs.tui" and c["mapped"]]; print(json.dumps(c[0]) if len(c)==1 else "windows=%d" % len(c))'; }
clone_tui_address() { clone_tui_client | py_reply 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["address"] if t.startswith("{") else "none")'; }
clone_tui_fullscreen() { clone_tui_client | py_reply 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["fullscreen"] if t.startswith("{") else "none")'; }
# The Settings window's address, then the x that puts it at the output's
# right edge, a gutter in.
clone_settings_place() {
  python3 - "$shell_class" "$(hypr -j clients)" "$(hypr -j monitors)" <<'PY'
import json,sys
shell,clients,monitors=sys.argv[1],json.loads(sys.argv[2]),json.loads(sys.argv[3])
s=[c for c in clients if c["mapped"] and c["class"]==shell and c.get("title")=="Plugins"]
if len(s)!=1 or not monitors:
    print("none 0"); raise SystemExit
print(s[0]["address"], monitors[0]["width"]-s[0]["size"][0]-16)
PY
}
# true once the consent terminal and the Settings window do not overlap.
clone_consent_apart() {
  hypr -j clients | py_reply 'import json,sys
clients=json.load(sys.stdin)
tui=[c for c in clients if c["class"]=="org.vgs.tui" and c["mapped"]]
settings=[c for c in clients if c["mapped"] and c["class"]==sys.argv[1] and c.get("title")=="Plugins"]
if len(tui)!=1 or len(settings)!=1:
    print("windows"); raise SystemExit
t,s=tui[0]["at"]+tui[0]["size"],settings[0]["at"]+settings[0]["size"]
print(str(t[0]+t[2]<=s[0] or s[0]+s[2]<=t[0] or t[1]+t[3]<=s[1] or s[1]+s[3]<=t[1]).lower())' "$shell_class"
}
# The consent terminal at the output's left and the Settings window at its
# right, so a consent shot shows both. A tree from before VGS-1474 lets
# kitty's remembered maximize through as fullscreen 1, which refuses a
# move, so the terminal's fullscreen state is set to none first.
clone_arrange_consent() { # LABEL
  local tui settings x
  tui="$(clone_tui_address)"
  read -r settings x < <(clone_settings_place)
  [[ $tui == 0x* && $settings == 0x* && $x =~ ^[0-9]+$ ]] || { fail "clone-voice: the consent windows are unreadable $1"; return 1; }
  expect "the clone setup terminal leaves fullscreen $1" ok hypr dispatch "hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = \"address:$tui\" })"
  expect_poll "the clone setup terminal is not fullscreen $1" 0 clone_tui_fullscreen
  expect "the clone setup terminal is sized beside Settings $1" ok hypr dispatch "hl.dsp.window.resize({ x = 820, y = 814, relative = false, window = \"address:$tui\" })"
  expect "the clone setup terminal moves left of Settings $1" ok hypr dispatch "hl.dsp.window.move({ x = 16, y = 74, relative = false, window = \"address:$tui\" })"
  expect "the Settings window moves right of the clone setup $1" ok hypr dispatch "hl.dsp.window.move({ x = $x, y = 40, relative = false, window = \"address:$settings\" })"
  expect_poll "the consent terminal does not cover Settings $1" true clone_consent_apart
}
# clone_box tui|settings: that window's [x, y, w, h] in logical pixels,
# as hyprctl places it, its border outside.
clone_box() {
  if [[ $1 == tui ]]; then
    clone_tui_client | py_reply 'import json,sys; t=sys.stdin.read(); print(json.dumps(json.loads(t)["at"] + json.loads(t)["size"]) if t.startswith("{") else t.strip())'
  else
    window_of Plugins at size | py_reply 'import json,sys; t=sys.stdin.read(); v=json.loads(t) if t.startswith("[") else None; print(json.dumps(v[0] + v[1]) if v else t.strip())'
  fi
}
# clone_record NAME KIND [PAGE_KIND]: shot NAME's crop in items.tsv, the
# box of window KIND, and with PAGE_KIND the box of that window as
# NAME@page.
clone_record() {
  record_item "$1" "$(clone_box "$2")"
  [[ $# -lt 3 ]] || record_item "$1@page" "$(clone_box "$3")"
}
clone_anchor_shot() { # NAME TYPE TEXT
  jarvis_anchor_shot "$@"
  clone_record "$1" settings
}
clone_tui_shot() { # NAME
  park_pointer
  take_posed "$1"
  clone_record "$1" tui
}
# One line per open of the clone setup's terminal, for the window size
# readings: the terminal's hyprctl client entry, the shell windows', the
# outputs, the floating TUI rule the shell's Hyprland layer wrote to
# vgs.lua (tuiWindowLines in shell/Core/HyprlandLayer.js) and what kitty
# keeps in its cache, whose remember_window_size the scene's kitty.conf
# leaves at kitty's default.
clone_window_log() { # MODE LABEL
  local client windows monitors rule cache
  client="$(clone_tui_client)" || client=unread
  windows="$(hypr -j clients | py_reply 'import json,sys; print(json.dumps([{k: c.get(k) for k in ("class","title","at","size","floating","fullscreen","pseudo")} for c in json.load(sys.stdin) if c["mapped"] and c["class"] == sys.argv[1]]))' "$shell_class")" || windows=unread
  monitors="$(hypr -j monitors | py_reply 'import json,sys; print(json.dumps([{k: m.get(k) for k in ("name","width","height","scale","x","y","reserved","transform")} for m in json.load(sys.stdin)]))')" || monitors=unread
  rule="$(grep -F -- 'name = "vgs:tui"' "$home/.local/state/vgshell/hypr/vgs.lua" 2>/dev/null)" || rule=unread
  cache="$(find "$home/.cache/kitty" -type f -printf '%P=%s ' 2>/dev/null)" || cache=unread
  [[ -n $cache ]] || cache=none
  printf 'clone-voice-window: mode=%s open=%s client=%s shell-windows=%s monitors=%s tui-rule=%s kitty-cache=%s\n' \
    "$1" "${2// /-}" "$client" "$windows" "$monitors" "$rule" "$cache"
}
# live while the terminal's kitty runs tui/clone-voice.sh below it, waiting
# while that script runs no program for half a second, as at
# vgs_tui_cancelled's closing key (bin/lib/tui.sh), ended once the script
# has ended and present waits for its closing key.
clone_script_state() {
  local pid
  pid="$(clone_tui_client | py_reply 'import json,sys; t=sys.stdin.read(); print(json.loads(t)["pid"] if t.startswith("{") else "none")')"
  [[ $pid =~ ^[0-9]+$ ]] || { echo no-window; return; }
  python3 - "$pid" <<'PY'
import os, sys, time
def tree():
    children = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat") as stat:
                parent = int(stat.read().rsplit(")", 1)[1].split()[1])
            with open(f"/proc/{entry}/cmdline", "rb") as cmdline:
                words = cmdline.read().split(b"\0")
        except OSError:
            continue
        children.setdefault(parent, []).append((int(entry), words))
    return children
def scripts(children):
    pending, found = [int(sys.argv[1])], []
    while pending:
        for pid, words in children.get(pending.pop(), []):
            clean = [word for word in words if word]
            head = os.path.basename(clean[0]) if clean else b""
            if head in (b"bash", b"sh") and len(clean) > 1 and clean[1].endswith(b"tui/clone-voice.sh"):
                found.append(pid)
            pending.append(pid)
    return found
children = tree()
live = scripts(children)
if not live:
    print("ended")
    raise SystemExit
if any(children.get(pid) for pid in live):
    print("live")
    raise SystemExit
time.sleep(0.5)
children = tree()
print("waiting" if scripts(children) == live and not any(children.get(pid) for pid in live) else "live")
PY
}
clone_curl_held() { [[ -e $clone_world/curl-held ]] && echo held || echo waiting; }
clone_record_held() { [[ -e $clone_world/record-held ]] && echo held || echo waiting; }
clone_world_marker() { [[ -f $clone_world/state/vgshell/jarvis/clone-ready.json ]] && echo ready || echo absent; }
# Whether the tree's clone setup waits for a key after No (VGS-1475).
clone_holds_cancel() { grep -qF -- 'vgs_tui_cancelled' "$repo/shell/plugins/vgs.jarvis/tui/clone-voice.sh"; }
clone_refuses_before_consent() { grep -qF -- 'clone check' "$repo/shell/plugins/vgs.jarvis/tui/clone-voice.sh"; }
active_class() { active_window | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps(v[0]) if v else "none")'; }
clone_prepare_world() { # MODE
  clone_world="$sandbox/clone-world-$1"
  if [[ ! -d $clone_world ]]; then
    if ! python3 "$clone_world_tool" prepare "$clone_world" "$repo/shell/plugins/vgs.jarvis"; then
      fail "clone-voice: the clone setup's world of doubles is not prepared"
      return 1
    fi
  fi
  if [[ -f $home/.local/state/vgshell/theme/gum.env ]]; then
    mkdir -p -- "$clone_world/state/vgshell/theme" && cp -- "$home/.local/state/vgshell/theme/gum.env" "$clone_world/state/vgshell/theme/gum.env" ||
      fail "clone-voice: gum's theme is not copied to the world"
  fi
}
# clone_key LABEL WTYPE_ARGS...: keys typed into the floating terminal once
# it holds the keyboard.
clone_key() {
  local label="$1" address
  shift
  address="$(clone_tui_address)"
  [[ $address == 0x* ]] || { fail "clone-voice: no terminal to type $label into"; return 1; }
  expect "the terminal is focused for $label" ok hypr dispatch "hl.dsp.focus({ window = \"address:$address\" })"
  expect_poll "the terminal holds the keyboard for $label" '"org.vgs.tui"' active_class
  type_keys "$@" || { fail "clone-voice: typing $label failed"; return 1; }
}
# The Jarvis page shown again on the Setup tab, its daemon still running.
clone_page_show() { # LABEL
  expect "the Settings window opens $1" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps $1" 1 settings_count
  expect "the window opens the Jarvis page $1" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.jarvis
  expect_poll "the Jarvis page is shown $1" '"vgs.jarvis"' settings_page
  page_setup
  expect_poll "the Jarvis Setup tab draws its steps $1" True jarvis_setup_drawn
}
clone_settings_tab() { # LABEL
  settings_tab_click Settings || fail "the click on the Settings tab failed $1"
  expect_poll "the Jarvis page shows Settings $1" 0 settings_tab
}
# The clone setup's requirements the shell does not find, stood in by
# programs no run reaches: the consent shots stop at gum's first question,
# and the step runs find the world's doubles first on their PATH.
clone_tui_standins=()
clone_tui_requirements() {
  local commands command
  clone_tui_standins=()
  commands="$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["tui"]["clone-voice"]["requires"]))' "$repo/shell/plugins/vgs.jarvis/manifest.json")" || return 1
  while IFS= read -r command; do
    [[ $(shell_resolves "$command") == none ]] || continue
    printf '#!/bin/sh\nexit 99\n' >"$shim/$command" && chmod 755 "$shim/$command" || return 1
    clone_tui_standins+=("$command")
  done <<<"$commands"
}
# The real clone setup in a kitty themed as the shell, gum's confirm
# marking each question, as dictation-setup does for Voice's setup. While
# $sandbox/clone-voice-steps names a world (clone-world.py prepare), a run
# is a step run: the terminal stand-in hands present a copy of the
# snapshot whose artifacts.json points at that world's synthetic downloads
# and runs it with the world's doubles first on PATH and its state and data
# roots, so the script's own setup-local runs every step and reaches no
# network, model, microphone or the daemon's roots.
clone_terminal_on() { # KITTY GUM
  local bg fg theme_name
  # Only gum is applied: terminal reload targets can signal host terminals.
  cp -RT -- "$checkout/themes/targets/gum" "$repo/themes/targets/gum" || { fail "clone-voice: gum's theme target is not copied"; return 1; }
  theme_name="$(ipc smoke themeName)" || { fail "clone-voice: the theme is unreadable"; return 1; }
  if [[ $theme_name != vgs ]]; then
    mkdir -p -- "$home/.config/vgshell/themes/$theme_name"
    cp -- "$theme_file" "$home/.config/vgshell/themes/$theme_name/theme.json"
  fi
  sandbox_vgshell theme apply "$theme_name" >/dev/null || { fail "clone-voice: gum's theme did not apply"; return 1; }
  bg="$(ipc smoke themeValue color.background)" fg="$(ipc smoke themeValue color.text)"
  python3 - "$bg" "$fg" "$sandbox/clone-voice-kitty.conf" <<'PY' || { fail "clone-voice: terminal colours are unreadable"; return 1; }
import json,sys
background,foreground=("#"+json.loads(v)[-6:] for v in sys.argv[1:3])
with open(sys.argv[3],"w") as out:
    out.write(f"background {background}\nforeground {foreground}\nconfirm_os_window_close 0\nshell_integration disabled\nenable_audio_bell no\n")
PY
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'marker=%q confirms=%q gum=%q\n' "$sandbox/clone-voice-confirm" "$sandbox/clone-voice-confirms" "$2"
    printf '[[ ${1:-} != confirm ]] || { : >"$marker"; read -r question <<<"${*: -1}"; printf "%%s\\n" "$question" >>"$confirms"; }\nexec "$gum" "$@"\n'
  } >"$shim/gum" && chmod 755 "$shim/gum" || { fail "clone-voice: the gum wrapper is not written"; return 1; }
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'kitty=%q config=%q presenter=%q key=%q script=%q steps=%q tool=%q\n' "$1" "$sandbox/clone-voice-kitty.conf" "$tui_self" vgs.jarvis/clone-voice \
      "$repo/shell/plugins/vgs.jarvis/tui/clone-voice.sh" "$sandbox/clone-voice-steps" "$clone_world_tool"
    cat <<'EOF'
app_id="" title=""
while [[ $# -gt 0 && $1 != -- ]]; do
  case "$1" in --app-id=*) app_id="${1#*=}" ;; --title=*) title="${1#*=}" ;; *) exit 70 ;; esac
  shift
done
[[ $# -gt 0 ]] || exit 70
shift
[[ ${1:-} == "$presenter" && ${2:-} == present ]] || exit 70
run=("$@") plugin="" dir="" record=""
shift 2
while [[ $# -ge 2 && $1 != -- ]]; do
  case "$1" in --plugin) plugin="$2" ;; --dir) dir="$2" ;; --record) record="$2" ;; esac
  shift 2
done
[[ ${1:-} == -- && $record == "$key" ]] || exit 70
shift
# Only the clone setup's own script runs, from the core's private copy.
[[ $# -eq 1 && $1 == tui/clone-voice.sh && $plugin == vgs.jarvis && $dir == /* && -f $dir/tui/clone-voice.sh && ! -L $dir/tui/clone-voice.sh ]] || exit 70
cmp -s -- "$script" "$dir/tui/clone-voice.sh" || exit 70
if [[ -f $steps ]]; then
  world="$(<"$steps")"
  copy="$world/snapshot-$$"
  python3 "$tool" snapshot "$world" "$dir" "$copy" || exit 70
  for i in "${!run[@]}"; do
    [[ ${run[i]} == -- ]] && break
    [[ ${run[i]} != --dir ]] || run[i + 1]="$copy"
  done
  # The installer doubles read their world from UV_CACHE_DIR's parent.
  export PATH="$world/hold:$world/bin:$PATH" XDG_STATE_HOME="$world/state" XDG_DATA_HOME="$world/data" \
    UV_CACHE_DIR="$world/data/vgshell/jarvis/local/cache"
fi
# kitty's documented --class retains the core's floating size class.
# https://sw.kovidgoyal.net/kitty/invocation/
exec "$kitty" --config "$config" --class "$app_id" --title "$title" "${run[@]}"
EOF
  } >"$tui_terminal" && chmod 755 "$tui_terminal" || { fail "clone-voice: the kitty terminal is not written"; return 1; }
}
# The clone setup's terminal asking its first consent question, floating.
clone_consent_shown() { # LABEL
  expect_poll "the clone setup asks its first consent question $1" asking clone_asking
  expect_poll "the clone setup's floating terminal maps $1" 1 clone_tui_windows
  expect "the clone setup's terminal floats $1" true clone_tui_floating
}
# The clone setup's terminal closed by the compositor.
clone_tui_close() { # LABEL
  local address
  address="$(clone_tui_address)"
  [[ $address == 0x* ]] || { fail "clone-voice: the floating terminal is unreadable $1"; return; }
  expect "the clone setup's terminal closes $1" ok hypr dispatch "hl.dsp.window.close({ window = \"address:$address\" })"
  expect_poll "the core sees the closed clone setup run $1" idle key_idle vgs.jarvis/clone-voice
  expect_poll "no floating terminal is left $1" 0 clone_tui_windows
}
# A step run of the clone setup, opened as the step's button opens it.
clone_step_open() { # MODE LABEL
  rm -f -- "${sandbox:?}/clone-voice-confirm" "${sandbox:?}/clone-voice-confirms"
  expect "the clone setup opens $2" ok settings_act vgs.jarvis clonedVoiceSetup
  clone_consent_shown "$2"
  clone_window_log "$1" "$2"
}
clone_failure_open() { # MODE LABEL
  rm -f -- "${sandbox:?}/clone-voice-confirm" "${sandbox:?}/clone-voice-confirms"
  expect "the clone setup opens $2" ok settings_act vgs.jarvis clonedVoiceSetup
  expect_poll "the clone setup's floating terminal maps $2" 1 clone_tui_windows
  expect "the clone setup's terminal floats $2" true clone_tui_floating
  clone_window_log "$1" "$2"
}
# The clone setup's terminal at each step after the first question, over
# the world clone-world.py prepares for MODE: No at the first question;
# Yes twice without the Large tier, setup-local's refusal; then Yes to
# each question with the model download held at its first file, the
# recording question, and the end once setup-local published its marker.
clone_steps() { # MODE
  local mode="$1" marker precheck
  clone_prepare_world "$mode" || return
  marker="$clone_world/state/vgshell/jarvis/local-ready.json"
  precheck=false
  clone_refuses_before_consent && precheck=true
  printf '%s\n' "$clone_world" >"$sandbox/clone-voice-steps"
  clone_step_open "$mode" "for the No answer"
  clone_key "No" n
  if clone_holds_cancel; then
    expect_poll "the clone setup waits for its closing key after No" waiting clone_script_state
    clone_tui_shot "clone-voice-$mode-tui-declined"
    clone_key "the closing key after No" -k Return
    expect_poll "the core sees the closed clone setup run after No" idle key_idle vgs.jarvis/clone-voice
    expect_poll "no floating terminal is left after No" 0 clone_tui_windows
  else
    expect_poll "the clone setup ends after No" ended clone_script_state
    if [[ $(clone_tui_windows) == 1 ]]; then
      clone_tui_shot "clone-voice-$mode-tui-declined"
      clone_tui_close "after No"
    else
      printf 'clone-voice: declined-window=closed mode=%s\n' "$mode"
      park_pointer
      take_posed "clone-voice-$mode-tui-declined"
      expect_poll "no floating terminal is left after No" 0 clone_tui_windows
    fi
  fi
  mv -T -- "$marker" "$marker.aside" || fail "clone-voice: the world's Large tier marker is not set aside"
  if "$precheck"; then
    clone_failure_open "$mode" "without the Large tier"
    expect_poll "the clone setup asks no consent without the Large tier" 0 clone_confirms
  else
    clone_step_open "$mode" "without the Large tier"
    clone_key "Yes to the use text without the Large tier" -k Return
    expect_poll "the clone setup asks whose voice it is without the Large tier" 2 clone_confirms
    clone_key "Yes to whose voice without the Large tier" -k Return
  fi
  expect_poll "the clone setup ends without the Large tier" ended clone_script_state
  clone_tui_shot "clone-voice-$mode-tui-failed"
  clone_tui_close "without the Large tier"
  mv -T -- "$marker.aside" "$marker" || fail "clone-voice: the world's Large tier marker is not put back"
  clone_step_open "$mode" "for its steps"
  clone_key "Yes to the use text" -k Return
  expect_poll "the clone setup asks whose voice it is" 2 clone_confirms
  clone_tui_shot "clone-voice-$mode-tui-permission"
  : >"$clone_world/hold-curl"
  clone_key "Yes to whose voice" -k Return
  expect_poll "the clone setup's model download is held" held clone_curl_held
  clone_tui_shot "clone-voice-$mode-tui-busy"
  rm -f -- "${clone_world:?}/hold-curl"
  expect_poll "the clone setup asks to start recording" 3 clone_confirms
  clone_tui_shot "clone-voice-$mode-tui-recording-ready"
  : >"$clone_world/hold-record"
  clone_key "Start recording" -k Return
  expect_poll "the clone setup's recording is held" held clone_record_held
  clone_tui_shot "clone-voice-$mode-tui-recording"
  rm -f -- "${clone_world:?}/hold-record"
  expect_poll "the clone setup ends after its recording" ended clone_script_state
  expect_poll "setup-local published the clone marker in the world" ready clone_world_marker
  clone_tui_shot "clone-voice-$mode-tui-finished"
  clone_tui_close "after the finished setup"
  rm -f -- "${sandbox:?}/clone-voice-steps"
}
# Whether box A, [x, y, w, h], holds box B.
clone_box_holds() { python3 -c 'import json,sys; a,b=(json.loads(v) for v in sys.argv[1:3]); print(str(a[0]<=b[0] and a[1]<=b[1] and a[0]+a[2]>=b[0]+b[2] and a[1]+a[3]>=b[1]+b[3]).lower())' "$1" "$2" 2>/dev/null || echo unread; }
scene_clone-voice() { # MODE
  local mode="$1" state="$home/.local/state/vgshell/jarvis" data="$home/.local/share/vgshell/jarvis" world="$sandbox/jarvis-world"
  local auto step setup_label remove_label kitty_bin gum_bin command covered
  jarvis_setup_requirements || fail "the Jarvis requirement stand-ins are not written"
  mkdir -p -- "$state" "$data/local/venv/bin"
  cp -- "$checkout/scripts/fixtures/jarvis-local-speech/standin.py" "$data/local/venv/bin/python"
  chmod 700 -- "$data/local/venv/bin/python"
  python3 -c 'import json,os,sys
assert "large" in json.load(open(sys.argv[1]))["tiers"]
open(sys.argv[3],"w").write(json.dumps({"tier": "large", "data": os.path.realpath(sys.argv[2])}))
open(os.path.join(sys.argv[2],"scenario.json"),"w").write(json.dumps({"start": "ready"}))' "$repo/shell/plugins/vgs.jarvis/artifacts.json" "$data/local" "$state/local-ready.json" ||
    fail "the Large local voice marker is not written"
  cp -- "$world/local-mode" "$sandbox/clone-voice-local-mode" 2>/dev/null || printf 'absent\n' >"$sandbox/clone-voice-local-mode"
  cp -- "$world/local-tiers.json" "$sandbox/clone-voice-local-tiers" || fail "the planted local tiers are not saved"
  printf 'ready\n' >"$world/local-mode"
  auto="$(clone_large_tiers "$world/local-tiers.json")" || fail "setup-local's Large choices are not read"
  if clone_ships; then
    cp -- "$world/clone-status.json" "$sandbox/clone-voice-status" || fail "the planted clone status is not saved"
    clone_answer info "Not set up" setup false || fail "the clone status answer is not written"
    # The manager opens the clone setup only while the scan finds its
    # requirements, so its runs reach the terminal and raise no notice.
    clone_tui_requirements || fail "the clone setup's requirement stand-ins are not written"
  fi
  tree_rescan "the clone voice stand-ins are scanned"
  ! clone_ships || voice_setup_launcher_ready
  ! clone_ships || clone_setting false
  jarvis_voice_page "beside a ready Large local voice"
  if ! clone_ships; then
    # A tree from before the Cloned voice: its Local voice section and
    # Setup tab at the same places.
    clone_settings_tab "before the Cloned voice"
    expect_poll "the Local voice field reads the Large pick" false jarvis_tier_list_open "$auto"
    clone_anchor_shot "clone-voice-$mode-before-settings" SectionHeader "Local voice"
    page_setup
    expect_poll "the Jarvis Setup tab draws its steps before the Cloned voice" True jarvis_setup_drawn
    clone_anchor_shot "clone-voice-$mode-before-setup" Field "$(jarvis_input_label)"
  else
    { read -r step && read -r setup_label && read -r remove_label; } < <(python3 -c 'import json,sys
row=json.load(open(sys.argv[1]))["status"]["clonedVoiceSetup"]
print(row["label"]); print(row["actions"]["setup"]["label"]); print(row["actions"]["remove"]["label"])' "$repo/shell/plugins/vgs.jarvis/manifest.json") ||
      fail "the manifest names no Cloned voice step, Set up or Remove action"
    # off: no recording, the setting off.
    expect_poll "the Cloned voice step reads Not set up" "Not set up" clone_step "$step"
    expect_poll "the Cloned voice step offers $setup_label" shown clone_offers "$setup_label"
    clone_anchor_shot "clone-voice-$mode-off-setup" Field "$(jarvis_input_label)"
    clone_settings_tab "with the Cloned voice off"
    expect_poll "the daemon holds the Cloned voice off" false clone_daemon_setting
    expect_poll "the Local voice field reads the Large pick" false jarvis_tier_list_open "$auto"
    clone_anchor_shot "clone-voice-$mode-off-settings" SectionHeader "Local voice"
    # consent: the real clone setup at its first question, over the
    # Settings tab, then opened by the step's button over the Setup tab,
    # each moved beside the Settings window (clone_arrange_consent),
    # then alone once the Settings window closes; then its later steps.
    if kitty_bin="$(command -v kitty)" && gum_bin="$(command -v gum)"; then
      if clone_terminal_on "$kitty_bin" "$gum_bin"; then
        clone_prepare_world "$mode" || return
        printf '%s\n' "$clone_world" >"$sandbox/clone-voice-steps"
        rm -f -- "${sandbox:?}/clone-voice-confirm" "${sandbox:?}/clone-voice-confirms"
        expect "the clone setup opens over the Settings tab" ok settings_act vgs.jarvis clonedVoiceSetup
        clone_consent_shown "over the Settings tab"
        clone_arrange_consent "over the Settings tab"
        if [[ $(clone_asking) == asking && $(clone_tui_windows) == 1 ]]; then
          clone_window_log "$mode" "settings-tab"
          park_pointer
          take_posed "clone-voice-$mode-consent-settings"
          clone_record "clone-voice-$mode-consent-settings" tui settings
          clone_tui_close "over the Settings tab"
        fi
        page_setup
        rm -f -- "${sandbox:?}/clone-voice-confirm" "${sandbox:?}/clone-voice-confirms"
        settings_press --type RowAction "$setup_label" || fail "the click on $setup_label failed"
        clone_consent_shown "from the Setup tab"
        clone_arrange_consent "from the Setup tab"
        if [[ $(clone_asking) == asking && $(clone_tui_windows) == 1 ]]; then
          clone_window_log "$mode" "setup-tab-button"
          park_pointer
          take_posed "clone-voice-$mode-consent-setup"
          clone_record "clone-voice-$mode-consent-setup" tui settings
          # A terminal that holds the whole Settings window draws the same
          # frame once that window closes, which shot.sh refuses as stale;
          # the sheet then crops the terminal from consent-setup.
          covered="$(clone_box_holds "$(clone_box tui)" "$(clone_box settings)")"
          settings_close
          if [[ $covered == true ]]; then
            printf 'clone-voice: consent-tui=covered mode=%s crop=clone-voice-%s-consent-setup\n' "$mode" "$mode"
          else
            clone_tui_shot "clone-voice-$mode-consent-tui"
          fi
          clone_tui_close "alone"
        fi
        clone_page_show "for the clone setup's steps"
        clone_steps "$mode"
      fi
      rm -f -- "${shim:?}/gum" "${sandbox:?}/clone-voice-steps"
    else
      fail "clone-voice: kitty or gum is missing, so the consent question is not drawn"
    fi
    terminal_stand_in
    if [[ $(settings_count) == 1 ]]; then page_setup; else clone_page_show "for the cloned state"; fi
    # cloned: a clone setup run ended with the recording and its marker
    # present, then the setting turned on.
    hold_runs
    forget_record
    expect "a clone setup run opens over the stand-in terminal" ok settings_act vgs.jarvis clonedVoiceSetup
    expect_poll "the stand-in clone setup run is live" busy key_idle vgs.jarvis/clone-voice
    printf 'RIFF' >"$state/voice-reference.wav" && chmod 600 -- "$state/voice-reference.wav" && printf '{}\n' >"$state/clone-ready.json" ||
      fail "the planted recording and clone marker are not written"
    clone_answer ok Ready remove true || fail "the clone status answer is not written"
    release_runs
    expect_run_end "the stand-in clone setup run ends" vgs.jarvis/clone-voice
    expect_poll "no stand-in terminal window is left after the clone setup" 0 clone_tui_windows
    clone_setting true
    expect_poll "the daemon holds the Cloned voice on" true clone_daemon_setting
    expect_poll "the Cloned voice step reads Ready" Ready clone_step "$step"
    expect_poll "the Cloned voice step offers $remove_label" shown clone_offers "$remove_label"
    clone_anchor_shot "clone-voice-$mode-cloned-setup" Field "$(jarvis_input_label)"
    clone_settings_tab "with the Cloned voice on"
    clone_anchor_shot "clone-voice-$mode-cloned-settings" SectionHeader "Local voice"
    # removed: Remove recording's run ended; the page reports whether the
    # runtime turned the setting off.
    page_setup
    hold_runs
    forget_record
    settings_press --type RowAction "$remove_label" || fail "the click on $remove_label failed"
    expect_poll "the stand-in recording removal run is live" busy key_idle vgs.jarvis/clone-voice-remove
    rm -f -- "${state:?}/voice-reference.wav" "${state:?}/clone-ready.json"
    clone_answer info "Not set up" setup false || fail "the clone status answer is not written"
    release_runs
    expect_run_end "the stand-in recording removal run ends" vgs.jarvis/clone-voice-remove
    expect_poll "no stand-in terminal window is left after the removal" 0 clone_tui_windows
    expect_poll "the Cloned voice step reads Not set up after the removal" "Not set up" clone_step "$step"
    expect_poll "the Cloned voice step offers $setup_label again" shown clone_offers "$setup_label"
    clone_anchor_shot "clone-voice-$mode-removed-setup" Field "$(jarvis_input_label)"
    clone_settings_tab "after the removal"
    printf 'clone-voice: removed-setting mode=%s value=%s\n' "$mode" "$(clone_daemon_setting)"
    clone_anchor_shot "clone-voice-$mode-removed-settings" SectionHeader "Local voice"
  fi
  park_pointer
  settings_close
  expect "disabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone" absent ipc smoke jarvisProcess
  rm -f -- "${state:?}/local-ready.json" "${data:?}/local/scenario.json"
  cp -- "$sandbox/clone-voice-local-mode" "$world/local-mode"
  cp -- "$sandbox/clone-voice-local-tiers" "$world/local-tiers.json" || fail "the planted local tiers are not put back"
  if clone_ships; then cp -- "$sandbox/clone-voice-status" "$world/clone-status.json" || fail "the planted clone status is not put back"; fi
  for command in "${clone_tui_standins[@]}"; do rm -f -- "${shim:?}/$command"; done
  clone_tui_standins=()
  jarvis_restore_requirements
}

# jarvis_home_setting CONFIG VALUE: the Jarvis home folder setting in the
# user's shell.json, "" for none, delivered by a reload.
jarvis_home_setting() {
  python3 - "$1" "$2" <<'PY' || fail "the Jarvis home folder setting is not written"
import json,os,sys
value=json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {"version": 2}
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
if sys.argv[2]: row["home"]=sys.argv[2]
else: row.pop("home",None)
open(sys.argv[1],"w").write(json.dumps(value))
PY
  expect "the Jarvis home folder setting is delivered" ok ipc shell reloadConfig
}
# The Setup section with a home folder chosen whose kendex mail tool is
# absent, where the tree offers its Agent fleet row.
scene_jarvis-fleet() { # MODE
  local config="$home/.config/vgshell/shell.json"
  jarvis_home_setting "$config" "~/jarvis-home"
  expect "enabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the Jarvis daemon answers hello without a restart" ready jarvis_started
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
  expect "the Settings window opens for the Jarvis page" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for the Jarvis page" 1 settings_count
  expect "the window opens the Jarvis page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.jarvis
  expect_poll "the Jarvis page is shown" '"vgs.jarvis"' settings_page
  page_details
  expect_poll "the Jarvis page shows its daemon ready" True jarvis_page_ready
  page_setup
  expect_poll "the Jarvis Setup section draws its rows" True jarvis_setup_drawn
  jarvis_anchor_shot "jarvis-fleet-$1" SectionHeader Setup
  settings_close
  expect "disabling vgs.jarvis is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone" absent ipc smoke jarvisProcess
  jarvis_home_setting "$config" ""
}

# A command below its version floor on the Jarvis page. The daemon's world
# copies its stand-ins when the daemon starts (scripts/lib/jarvis-env.sh),
# so its Pi is written before Jarvis is enabled, and the shell's scan reads
# the same program from the sandbox PATH. Pi's folder is added to the
# account list by hand and chosen as the AI model. The notice is raised as
# the Requirements section's Install all missing raises it, through the
# Settings window's installRequirements; a notice that does not show fails
# the scene and takes no notice shot.
# Its step is then run: the stand-in terminal runs
# the update as `true`, which ends with code 0, the driver stays below its
# floor, and the last shot is the notice that comes back.
scene_outdated() { # MODE
  local state="$home/.local/state/vgshell/jarvis" pi_dir="$home/.pi/agent" config="$home/.config/vgshell/shell.json"
  local pkg_real="$sandbox/outdated-vgshell-pkg.real" world_pi="$sandbox/jarvis-world/standins/pi" pi_line="$sandbox/jarvis-world/pi-version"
  local accounts_before="$sandbox/outdated-accounts-before" brain
  jarvis_setup_requirements
  printf '#!/bin/sh\necho "agent-browser 0.37.9"\n' >"$shim/agent-browser" && chmod 755 "$shim/agent-browser" || fail "the driver stand-in is not written"
  printf '1.0.2\n' >"$pi_line"
  printf '#!/bin/bash\n[[ $# == 1 && $1 == --version ]] || exit 2\nexec cat %q\n' "$pi_line" >"$world_pi" && chmod 755 "$world_pi" && cp -- "$world_pi" "$shim/pi" ||
    fail "the Pi stand-ins are not written"
  mkdir -p -- "$pi_dir" "$state" "$sandbox/outdated-no-path" && printf '{}\n' >"$pi_dir/auth.json" || fail "the Pi folder is not written"
  rm -f -- "${accounts_before:?}"
  [[ ! -e $state/accounts.json ]] || cp -- "$state/accounts.json" "$accounts_before"
  python3 - "$state/accounts.json" "$pi_dir" <<'PY' || fail "the Pi folder is not added to the account list"
import json,os,sys
held=json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else []
open(sys.argv[1],"w").write(json.dumps(held + [{"provider": "pi", "directory": sys.argv[2], "label": "setup"}]))
PY
  cp -- "$repo/bin/vgshell-pkg" "$pkg_real"
  cat >"$sandbox/outdated-vgshell-pkg.stub" <<'EOF_PKG'
#!/usr/bin/env node
if (process.argv[2] === "detect" && process.argv[3] === "--json") {
    process.stdout.write('{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"paru"}],"sources":[{"id":"mise","binary":"mise"}]}\n');
    process.exit(0);
}
process.stderr.write("vgshell: refused: stub=vgshell-pkg\n");
process.exit(70);
EOF_PKG
  chmod 755 "$sandbox/outdated-vgshell-pkg.stub"
  cp -- "$sandbox/outdated-vgshell-pkg.stub" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
  tree_rescan "the outdated scene's stand-ins are scanned"
  brain="$(env -i PATH="$sandbox/outdated-no-path" HOME="$home" XDG_STATE_HOME="$home/.local/state" XDG_CONFIG_HOME="$home/.config" \
    XDG_DATA_HOME="$home/.local/share" "$node_bin" "$repo/shell/plugins/vgs.jarvis/backend/accounts.js" --tree "$repo" list |
    py_reply 'import json,sys; print(next(a["id"] for a in json.load(sys.stdin) if a["source"].get("directory")==sys.argv[1]))' "$pi_dir")" ||
    fail "the account helper lists no id for the Pi folder"
  outdated_brain "$config" "$brain"
  expect "enabling vgs.jarvis for the outdated scene is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
  expect_poll "the Jarvis daemon answers hello over the outdated stand-ins" ready jarvis_started
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
  expect "the Settings window opens for the outdated scene" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for the outdated scene" 1 settings_count
  expect "the window opens the Jarvis page for the outdated scene" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.jarvis
  expect_poll "the Jarvis page is shown for the outdated scene" '"vgs.jarvis"' settings_page
  page_details
  expect_poll "the Jarvis page shows its daemon ready over the outdated stand-ins" True jarvis_page_ready
  jarvis_anchor_shot "outdated-$1-driver" Label "Browser driver"
  "$has_setup_tab" || jarvis_anchor_shot "outdated-$1-requirement" Label agent-browser
  page_setup
  ! "$has_setup_tab" || jarvis_anchor_shot "outdated-$1-requirement" Label agent-browser
  expect_poll "the Jarvis Setup section draws its rows for the outdated scene" True jarvis_setup_drawn
  jarvis_anchor_shot "outdated-$1-setup" SectionHeader Setup
  expect "Install all missing is answered for the outdated scene" ok ipc smoke invokeInstance "$settings_kind" vgs.settings installRequirements vgs.jarvis
  expect_poll "Jarvis's requirement notice shows for the outdated scene" 1 layer_count vgs:notice
  if [[ $(layer_count vgs:notice) == 1 ]]; then
    park_pointer
    take "outdated-$1-notice"
    terminal_stand_in
    forget_record
    expect_poll "the driver's notice holds the keyboard for its step" true ipc smoke noticeFocused
    type_keys -k Return || fail "Enter on the driver's notice failed"
    expect_poll "the driver's notice is back after a run that changed nothing" back outdated_notice_back
    take "outdated-$1-notice-unchanged"
  fi
  close_notices
  settings_close
  expect "disabling vgs.jarvis after the outdated scene is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone after the outdated scene" absent ipc smoke jarvisProcess
  outdated_brain "$config" ""
  cp -- "$pkg_real" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
  rm -f -- "${shim:?}/agent-browser" "${shim:?}/pi" "${world_pi:?}" "${pi_line:?}" "${state:?}/accounts.json"
  [[ ! -e $accounts_before ]] || cp -- "$accounts_before" "$state/accounts.json"
  rm -f -- "${pi_dir:?}/auth.json"
  jarvis_restore_requirements
}
# `back` once the notice's step reached the terminal, its run ended and
# the notice shows again with no run in flight.
outdated_notice_back() {
  [[ $(recorded) != absent && $(key_idle core/requirements-update) == idle && $(layer_count vgs:notice) == 1 ]] || { echo waiting; return; }
  ipc shell lent | py_reply 'import json,sys; s=json.load(sys.stdin)["notices"]["shown"]; print("back" if s is not None and not s["installing"] else "waiting")'
}
jarvis_backup_choice_accounts() { # plant|restore BACKUP
  local mode="$sandbox/jarvis-world/account-mode"
  [[ $1 == plant || $1 == restore ]] || fail "unknown Jarvis backup account action: $1"
  if [[ $1 == plant ]]; then
    rm -f -- "$2"
    [[ ! -e $mode ]] || cp -- "$mode" "$2"
    printf 'copilot\n' >"$mode" || fail "the Jarvis backup account mode is not written"
  else
    if [[ -e $2 ]]; then
      cp -- "$2" "$mode"
    else
      rm -f -- "$mode"
    fi
  fi
}
# jarvis_backups plant|clear: write the Jarvis backup model list in the
# shell.json rows Jarvis reads, then reload it.
jarvis_backups() {
  local config="$home/.config/vgshell/shell.json" ids
  [[ $1 == plant || $1 == clear ]] || fail "unknown Jarvis backup model action: $1"
  jarvis_ships_backups || return 0
  if [[ $1 == plant ]]; then
    ids="$(jarvis_brain_choice_ids)" || fail "the Jarvis AI model choices are unreadable"
    [[ $ids != waiting ]] || fail "the Jarvis AI model choice list has fewer than two rows"
  fi
  python3 - "$config" "$1" ${ids:+$ids} <<'PY' || fail "the Jarvis backup model setting is not written"
import json, os, re, sys
config, action, *ids = sys.argv[1:]
value = json.load(open(config)) if os.path.exists(config) else {"version": 2}
row = next((r for r in value.setdefault("plugins", []) if r["id"] == "vgs.jarvis"), None)
if row is None:
    row = {"id": "vgs.jarvis"}
    value["plugins"].append(row)
targets = [row]
if action == "plant":
    fallbacks = [{"name": f"backup-{i + 1}", "brain": ids[i], "model": ""} for i in range(2)]
    name_pattern = re.compile(r"^[a-z0-9][a-z0-9-]*$")
    if any(not name_pattern.match(item["name"]) for item in fallbacks):
        raise SystemExit("name-pattern")
    for target in targets:
        target["fallbacks"] = fallbacks
else:
    for target in targets:
        target.pop("fallbacks", None)
open(config, "w").write(json.dumps(value))
PY
  "$node_bin" - "$repo" "$config" <<'NODE' || fail "the Jarvis backup model list does not fit the manifest"
const fs = require("fs");
const path = require("path");
const { load } = require(path.join(process.argv[2], "bin/lib/qml-library.js"));
const logic = load(path.join(process.argv[2], "shell/Core/PluginLogic.js"));
const manifest = JSON.parse(fs.readFileSync(path.join(process.argv[2], "shell/plugins/vgs.jarvis/manifest.json"), "utf8"));
const config = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const row = config.plugins.find(entry => entry.id === "vgs.jarvis") || {};
const value = Object.prototype.hasOwnProperty.call(row, "fallbacks") ? row.fallbacks : [];
const refused = logic.settingRefusal(manifest, "fallbacks", value);
if (refused !== "") { console.error(refused); process.exit(1); }
NODE
  expect "the Jarvis backup model setting is delivered" ok ipc shell reloadConfig
}

# outdated_brain CONFIG BRAIN: the Jarvis AI model setting in the user's
# shell.json, "" for none, delivered by a reload.
outdated_brain() {
  python3 - "$1" "$2" <<'PY' || fail "the Jarvis AI model setting is not written"
import json,os,sys
value=json.load(open(sys.argv[1])) if os.path.exists(sys.argv[1]) else {"version": 2}
row=next((r for r in value.setdefault("plugins",[]) if r["id"]=="vgs.jarvis"),None)
if row is None:
    row={"id":"vgs.jarvis"}; value["plugins"].append(row)
if sys.argv[2]: row["brain"]=sys.argv[2]
else: row.pop("brain",None)
open(sys.argv[1],"w").write(json.dumps(value))
PY
  expect "the Jarvis AI model setting is delivered" ok ipc shell reloadConfig
}
scene_jarvis-causes() { # MODE
  local phase cause slug label headline=Setup
  phase=after
  [[ -z $rev ]] || phase=before
  # The Setup tab draws the summary, which words the cause, in its own
  # Status section over the steps.
  ! "$has_setup_tab" || headline=Status
  expect "enabling vgs.jarvis for cause sheets is allowed" ok ipc shell setPluginEnabled vgs.jarvis true
  expect "vgs.jarvis is placed for cause sheets" ok ipc shell setPluginPlaced vgs.jarvis true
  expect_poll "the Jarvis service exists for cause sheets" True record_exists vgs.jarvis
  expect_poll "the Jarvis daemon is settled for cause sheets" ready jarvis_started
  expect "the Jarvis status provider is held for cause sheets" held ipc smoke holdStatus service vgs.jarvis
  close_notices
  expect "the Settings window opens for Jarvis cause sheets" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps for Jarvis cause sheets" 1 settings_count
  expect "the window opens the Jarvis page for cause sheets" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin vgs.jarvis
  expect_poll "the Jarvis page is shown for cause sheets" '"vgs.jarvis"' settings_page
  page_setup
  for row in \
    "hello-timeout|jarvis: hello=timeout|Hello timeout" \
    "node-too-old|jarvis: node=20.19.5 need=22|Node too old" \
    "daemon-exit|jarvis: daemon=exit code=1 status=0|Daemon exit" \
    "wire-defect|jarvis: protocol=identity|Wire defect" \
    "local-voice|speech=local-ready-timeout|Local voice not ready" \
    "probe-timeout|setup=probe-timeout|Probe timeout"; do
    IFS='|' read -r slug cause label <<<"$row"
    expect "the Jarvis $label cause is planted" ok jarvis_plant_cause "$cause" "$phase"
    hover_widget "the pointer rests on Jarvis for $label" vgs.jarvis || continue
    expect_poll "the Jarvis tooltip opens for $label" true tooltip_opened vgs.jarvis
    take_posed "jarvis-causes-$1-$phase-$slug-widget"
    park_pointer
    expect_poll "the Jarvis tooltip closes for $label" false tooltip_opened vgs.jarvis
    jarvis_anchor_shot "jarvis-causes-$1-$phase-$slug-setup" SectionHeader "$headline"
  done
  settings_close
  expect "disabling vgs.jarvis after cause sheets is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone after cause sheets" absent ipc smoke jarvisProcess
}

voice_level_flowing() { ipc smoke readInstance service vgs.voice level | py_reply 'import json,sys; print(str(json.load(sys.stdin) > 0).lower())'; }

scene_dictation-setup() { # MODE
  local mode="$1" phase=after key=core/dictation-setup holder=acme.dictation
  local kitty_bin gum_bin bg fg theme_name
  kitty_bin="$(command -v kitty)" && gum_bin="$(command -v gum)" || { fail "dictation-setup: kitty or gum is missing"; return; }
  if [[ ! -x $repo/bin/vgshell-dictation ]]; then
    phase=before key=vgs.voice/setup holder=vgs.voice
  fi
  cp -- "$repo/scripts/smoke/fixtures/voxtype/voxtype" "$shim/voxtype"
  cp -- "$repo/scripts/smoke/fixtures/voxtype/wtype" "$shim/wtype"
  chmod 755 "$shim/voxtype" "$shim/wtype"
  rescan "the dictation setup stand-ins are scanned"
  expect "the setup scene resolves only its voxtype stand-in" "$shim/voxtype" shell_resolves voxtype
  if [[ $phase == after ]]; then
    mkdir -p -- "$home/.config/vgshell/plugins/acme.dictation"
    cp -R -- "$fixtures/acme.dictation/." "$home/.config/vgshell/plugins/acme.dictation/"
    rescan "the setup holder is scanned"
  fi
  expect "the setup holder enables over stand-ins" ok ipc shell setPluginEnabled "$holder" true
  expect_poll "the setup holder is built" True record_exists "$holder"
  expect "the setup Settings window enables" ok ipc shell setPluginEnabled vgs.settings true
  expect_poll "the setup Settings window is built" True record_exists vgs.settings
  close_notices

  # Only gum is applied: terminal reload targets can signal host terminals.
  cp -R -- "$checkout/themes/targets/gum" "$repo/themes/targets/gum"
  theme_name="$(ipc smoke themeName)" || { fail "dictation-setup: the theme is unreadable"; return; }
  if [[ $theme_name != vgs ]]; then
    mkdir -p -- "$home/.config/vgshell/themes/$theme_name"
    cp -- "$theme_file" "$home/.config/vgshell/themes/$theme_name/theme.json"
  fi
  sandbox_vgshell theme apply "$theme_name" >/dev/null || { fail "dictation-setup: gum's theme did not apply"; return; }
  bg="$(ipc smoke themeValue color.background)" fg="$(ipc smoke themeValue color.text)"
  python3 - "$bg" "$fg" "$sandbox/dictation-setup-kitty.conf" <<'PY' || { fail "dictation-setup: terminal colours are unreadable"; return; }
import json,sys
background,foreground=("#"+json.loads(v)[-6:] for v in sys.argv[1:3])
with open(sys.argv[3],"w") as out:
    out.write(f"background {background}\nforeground {foreground}\nconfirm_os_window_close 0\nshell_integration disabled\nenable_audio_bell no\n")
PY
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'marker=%q gum=%q\n' "$sandbox/dictation-setup-confirm" "$gum_bin"
    printf '[[ ${1:-} != confirm ]] || : >"$marker"\nexec "$gum" "$@"\n'
  } >"$shim/gum"
  chmod 755 "$shim/gum"
  rm -f -- "$sandbox/dictation-setup-confirm"
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'kitty=%q config=%q presenter=%q key=%q core=%q voice=%q\n' "$kitty_bin" "$sandbox/dictation-setup-kitty.conf" "$tui_self" "$key" "$core_vgshell" "$repo/shell/plugins/vgs.voice/tui/setup.sh"
    cat <<'EOF'
app_id="" title=""
while [[ $# -gt 0 && $1 != -- ]]; do
  case "$1" in --app-id=*) app_id="${1#*=}" ;; --title=*) title="${1#*=}" ;; *) exit 70 ;; esac
  shift
done
[[ $# -gt 0 ]] || exit 70
shift
[[ ${1:-} == "$presenter" && ${2:-} == present ]] || exit 70
run=("$@") plugin="" dir="" record=""
shift 2
while [[ $# -ge 2 && $1 != -- ]]; do
  case "$1" in --plugin) plugin="$2" ;; --dir) dir="$2" ;; --record) record="$2" ;; esac
  shift 2
done
[[ ${1:-} == -- && $record == "$key" ]] || exit 70
shift
if [[ $key == core/dictation-setup ]]; then
  [[ $# -eq 3 && $1 == "$core" && $2 == dictation && $3 == setup && -z $plugin && -z $dir ]] || exit 70
else
  [[ $# -eq 1 && $1 == tui/setup.sh && $plugin == vgs.voice && $dir == /* && -f $dir/tui/setup.sh && ! -L $dir/tui/setup.sh ]] || exit 70
  cmp -s -- "$voice" "$dir/tui/setup.sh" || exit 70
fi
# kitty's documented --class retains the core's floating size class.
# https://sw.kovidgoyal.net/kitty/invocation/
exec "$kitty" --config "$config" --class "$app_id" --title "$title" "${run[@]}"
EOF
  } >"$tui_terminal"
  chmod 755 "$tui_terminal"
  voice_setup_launcher_ready
  expect "the setup Settings window opens" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the setup Settings window maps" 1 settings_count
  if [[ $phase == before ]]; then
    expect "Voice's Set up opens" ok settings_open_tui vgs.voice setup
  else
    expect "the setup holder's page opens" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin acme.dictation
    settings_setup || { fail "dictation-setup: the Setup tab did not open"; return; }
    settings_press --type RowAction "Set up" || { fail "dictation-setup: Set up did not open"; return; }
  fi
  settings_close
  dictation_setup_confirm() { [[ -e $sandbox/dictation-setup-confirm ]] && echo asking || echo waiting; }
  expect_poll "the setup terminal asks for the model download" asking dictation_setup_confirm
  dictation_setup_windows() { hypr -j clients | py_reply 'import json,sys; print(sum(c["class"] == "org.vgs.tui" and c["mapped"] for c in json.load(sys.stdin)))'; }
  expect_poll "the floating setup terminal maps" 1 dictation_setup_windows
  dictation_setup_floating() { hypr -j clients | py_reply 'import json,sys; c=[c for c in json.load(sys.stdin) if c["class"] == "org.vgs.tui" and c["mapped"]]; print(str(len(c)==1 and c[0]["floating"]).lower())'; }
  expect "the setup terminal floats" true dictation_setup_floating
  park_pointer
  take_posed "dictation-setup-$mode-$phase-confirm"
  local address
  address="$(hypr -j clients | py_reply 'import json,sys; c=[c for c in json.load(sys.stdin) if c["class"] == "org.vgs.tui" and c["mapped"]]; print(c[0]["address"] if len(c)==1 else "none")')"
  [[ $address == 0x* ]] || { fail "dictation-setup: the floating terminal is unreadable"; return; }
  expect "the setup terminal closes before any download" ok hypr dispatch "hl.dsp.window.close({ window = \"address:$address\" })"
  expect_poll "the core sees the closed setup run" idle key_idle "$key"
  expect "the setup holder disables" ok ipc shell setPluginEnabled "$holder" false
  rm -f -- "$shim/gum" "$shim/voxtype" "$shim/wtype"
  terminal_stand_in
}

# Voice's Set up as a first-time user meets it. A tree whose Voice requires
# voxtype and its bridge raises their requirement notice when the scene
# enables Voice without them; that notice closes with Not now before the
# shots. Without voxtype, Set up on
# the Settings window raises the core's requirement notice, which a stand-in
# bin/vgshell-pkg answers with pacman and paru, so voxtype's AUR package
# shows whatever the host runs; Escape closes it and drops the Set up it
# owed. Then a voxtype stand-in reports the speech model missing, Set up
# runs, the stand-in terminal runs `true` for the script (harness.sh's
# terminal_stand_in) and the run ends with code 0. A tree whose Voice names
# capability toasts is shot once the core toast for that end shows; one
# whose Voice names notify once Voice's card shows in vgs.notifications,
# which the scene enables with Silence off for it; an older one after a
# bounded wait. Voice's Settings page is shot without voxtype and once the
# stand-ins report the model installed and a systemctl stand-in the
# service enabled and running, scrolled so the Setup tab's sections are
# whole in view. A tree whose Voice dictates through the core
# (voice_dictates) has no Set up screen of its own: its setup entry's step
# raises the notice without voxtype and opens the core's dictation setup
# with it, over the smoke's voxtype stand-in, and its page reads Ready
# once that stand-in reports the model. A tree whose Voice hides its setup
# state without voxtype offers no step then: the Requirements section's
# Install all missing raises the notice, and the page draws no chip. A
# tree whose Voice puts its setup state in the Setup group is shot once
# the section draws its chip. Enablement, stand-ins and the package script
# are put back, and the Settings window is hidden again.
scene_voice-setup() { # MODE
  local voice_found settings_found notes_found=True silence_found=false pkg_real="$sandbox/voice-setup-vgshell-pkg.real" systemctl_saved="$sandbox/voice-setup-systemctl.saved" stood=() command before notifies=false missing_chip="Requirements missing" missing_press=voice_setup_press
  voice_setup_key=vgs.voice/setup
  if voice_dictates; then
    voice_setup_key=core/dictation-setup
    missing_chip="Setup needed"
  fi
  if tree_has shell/plugins/vgs.voice/VoiceLogic.js "hidden: true"; then
    missing_chip=none
    missing_press=voice_install_press
  fi
  voice_found="$(plugin_enabled vgs.voice)" || voice_found=unread
  settings_found="$(plugin_enabled vgs.settings)" || settings_found=unread
  [[ $voice_found == True || $voice_found == False ]] || fail "vgs.voice's enablement is unreadable before the Voice setup scene: $voice_found"
  [[ $settings_found == True || $settings_found == False ]] || fail "vgs.settings' enablement is unreadable before the Voice setup scene: $settings_found"
  if grep -qF '"notify"' "$tree/shell/plugins/vgs.voice/manifest.json"; then
    notifies=true
    notes_found="$(plugin_enabled vgs.notifications)" || notes_found=unread
    [[ $notes_found == True || $notes_found == False ]] || fail "vgs.notifications' enablement is unreadable before the Voice setup scene: $notes_found"
    if [[ $notes_found == False ]]; then
      expect "enabling vgs.notifications for the Voice setup scene is allowed" ok ipc shell setPluginEnabled vgs.notifications true
      expect_poll "vgs.notifications is built for the Voice setup scene" True record_exists vgs.notifications
    fi
    # The status function registers once the store is read, after the
    # plugin is built: 10 s at most, polled as expect_poll polls.
    for _ in $(seq 1 50); do
      silence_found="$(voice_setup_silence)" || silence_found=unread
      [[ $silence_found == unread || $silence_found == empty ]] || break
      sleep 0.2
    done
    [[ $silence_found == true || $silence_found == false ]] || fail "Silence is unreadable before the Voice setup scene: $silence_found"
    [[ $silence_found == false ]] || expect "Silence goes off for the Voice setup scene" off notes silence off
  fi
  # Voice's required commands but voxtype and its bridge stand in where the
  # shell finds none; a tree whose Voice requires those two raises their
  # notice on the enable, which closes before Set up.
  for command in wtype wl-copy; do
    [[ $(shell_resolves "$command") == none ]] || continue
    printf '#!/bin/sh\nexit 0\n' >"$shim/$command"
    chmod 755 "$shim/$command"
    stood+=("$command")
  done
  cp -- "$repo/bin/vgshell-pkg" "$pkg_real"
  cat >"$sandbox/voice-setup-vgshell-pkg.stub" <<'EOF_PKG'
#!/usr/bin/env node
if (process.argv[2] === "detect" && process.argv[3] === "--json") {
    process.stdout.write('{"primary":{"id":"pacman","binary":"pacman"},"overlays":[{"id":"aur","binary":"paru"}],"sources":[]}\n');
    process.exit(0);
}
process.stderr.write("vgshell: refused: stub=vgshell-pkg\n");
process.exit(70);
EOF_PKG
  chmod 755 "$sandbox/voice-setup-vgshell-pkg.stub"
  cp -- "$sandbox/voice-setup-vgshell-pkg.stub" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
  voice_stand_ins_removed
  rm -f -- "${shim:?}/voxtype-audio-bridge"
  rescan "the Voice setup scene's commands are scanned"
  expect_poll "voxtype is missing for the Voice setup dialog" missing voice_setup_requirement voxtype
  if [[ $settings_found == False ]]; then
    expect "enabling vgs.settings for the Voice setup scene is allowed" ok ipc shell setPluginEnabled vgs.settings true
    expect_poll "vgs.settings is built for the Voice setup scene" True record_exists vgs.settings
  fi
  expect "enabling vgs.voice without voxtype is allowed" ok ipc shell setPluginEnabled vgs.voice true
  expect_poll "vgs.voice is built without voxtype" True record_exists vgs.voice
  voice_enable_notice_closed "enabling Voice without voxtype"
  expect "no notice shows before Set up" null notice_shown

  "$missing_press" "the Voice setup dialog"
  expect_poll "voxtype's install raises Voice's notice" '"vgs.voice"' notice_plugin
  expect_poll "Voice's notice maps its surface" 1 layer_count vgs:notice
  expect_poll "Voice's notice holds the keyboard" true ipc smoke noticeFocused
  park_pointer
  take "voice-setup-$1-dialog"
  type_keys -k Escape || fail "sending Escape to Voice's notice failed"
  expect_poll "Escape closes Voice's notice" 0 layer_count vgs:notice
  voice_setup_page "Voice's page without voxtype" "voice-setup-$1-page-missing" "$missing_chip"

  if voice_dictates; then
    voice_stand_ins
  else
    cat >"$shim/voxtype" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  'status --follow --extended --format json') printf '{"state":"idle"}\n'; exec sleep infinity ;;
  'config get engine --json') printf '{"value":"parakeet"}\n' ;;
  'config get parakeet.model --json') printf '{"value":"parakeet-tdt-0.6b-v3"}\n' ;;
  'info models --json') printf '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":false,"downloadable":true,"download_arg":"parakeet-tdt-0.6b-v3"}],"default":"parakeet-tdt-0.6b-v3"}},"verified":true}\n' ;;
  'info engines --json') printf '[{"name":"parakeet","compiled":true,"active":true}]\n' ;;
esac
EOF
    chmod 755 "$shim/voxtype"
  fi
  rescan "the voxtype stand-in is scanned"
  expect_poll "Voice finds the voxtype stand-in" true ipc smoke readInstance service vgs.voice voxtypePresent
  if voice_dictates; then
    expect_poll "the core starts its daemon once voxtype is found" "ready idle" voice_daemon
    expect_poll "Voice offers Set up while the model is missing" setup voice_setup_wanted
    voice_setup_page "Voice's page with Set up offered" "voice-setup-$1-page-needed" "Setup needed"
  fi
  terminal_stand_in
  voice_setup_launcher_ready
  before="$(voice_setup_run)" || before=unread
  voice_setup_press "the Voice setup run"
  expect_poll "the Set up run ends with code 0" 0 voice_setup_code "$before"
  if grep -qF '"toasts"' "$tree/shell/plugins/vgs.voice/manifest.json"; then
    expect_poll "the finished Set up shows Voice's toast" 1 voice_setup_toasts
  elif [[ $notifies == true ]]; then
    expect_poll "the finished Set up shows Voice's notification" 1 voice_setup_cards
  elif voice_dictates; then
    # The run's end with code 0 starts the core's daemon again, and Voice
    # sends no message of its own.
    expect_poll "the core's daemon is ready after the Set up run" "ready idle" voice_daemon
  else
    # A tree from before the toast: a short bounded wait, 2 s, for the
    # page and the bar to settle after the run.
    for _ in $(seq 1 10); do [[ $(voice_setup_toasts) == 0 ]] || break; sleep 0.2; done
  fi
  park_pointer
  take "voice-setup-$1-done"

  # The toast or the notification goes before the page's shot and the next
  # mode's dialog, so no shot holds it twice; the notification leaves the
  # History too, so no later shot shows it there.
  if [[ $notifies == true ]]; then
    expect "Voice's notification is dismissed" ok notes dismiss-all
    expect_poll "Voice's notification is gone after the Voice setup run" 0 on_screen
    expect "the history clears after the Voice setup run" ok notes clear-history
  elif ! voice_dictates; then
    expect_poll "Voice's toast is gone after the Voice setup run" 0 voice_setup_toasts
  fi
  # Ready: the stand-in reports its version and the model installed, and,
  # for a tree whose Voice probes a user unit, a systemctl stand-in, over
  # whichever the sandbox holds, the service enabled and running.
  if voice_dictates; then
    : >"$voice_model_installed"
    rescan "the ready stand-in is scanned"
    expect_poll "Voice reads its setup ready" none voice_setup_wanted
  else
    cat >"$shim/voxtype" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  '--version') printf 'voxtype 1.1.0\n' ;;
  'status --follow --extended --format json') printf '{"state":"idle"}\n'; exec sleep infinity ;;
  'config get engine --json') printf '{"value":"parakeet"}\n' ;;
  'config get parakeet.model --json') printf '{"value":"parakeet-tdt-0.6b-v3"}\n' ;;
  'info models --json') printf '{"engines":{"parakeet":{"models":[{"name":"parakeet-tdt-0.6b-v3","installed":true,"downloadable":true,"download_arg":"parakeet-tdt-0.6b-v3"}],"default":"parakeet-tdt-0.6b-v3"}},"verified":true}\n' ;;
  'info engines --json') printf '[{"name":"parakeet","compiled":true,"active":true}]\n' ;;
esac
EOF
    rm -f -- "$systemctl_saved"
    if [[ -e $shim/systemctl ]]; then mv -- "$shim/systemctl" "$systemctl_saved"; fi
    cat >"$shim/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  '--user is-enabled voxtype') printf 'enabled\n' ;;
  '--user is-active voxtype') printf 'active\n' ;;
esac
EOF
    chmod 755 "$shim/voxtype" "$shim/systemctl"
    rescan "the ready stand-ins are scanned"
    expect_poll "Voice reads its setup ready" False voice_setup_wanted
  fi
  voice_setup_page "Voice's page once set up" "voice-setup-$1-page-ready" "Ready"
  if [[ $voice_found == False ]]; then
    expect "disabling vgs.voice after the Voice setup scene is allowed" ok ipc shell setPluginEnabled vgs.voice false
    expect_poll "vgs.voice is gone after the Voice setup scene" False record_exists vgs.voice
  fi
  if [[ $settings_found == False ]]; then
    expect "disabling vgs.settings after the Voice setup scene is allowed" ok ipc shell setPluginEnabled vgs.settings false
    expect_poll "vgs.settings is gone after the Voice setup scene" False record_exists vgs.settings
  fi
  [[ $silence_found != true ]] || expect "Silence goes back on after the Voice setup scene" on notes silence on
  if [[ $notes_found == False ]]; then
    expect "disabling vgs.notifications after the Voice setup scene is allowed" ok ipc shell setPluginEnabled vgs.notifications false
    expect_poll "vgs.notifications is gone after the Voice setup scene" False record_exists vgs.notifications
  fi
  voice_stand_ins_removed
  if ! voice_dictates; then
    rm -f -- "${shim:?}/systemctl"
    if [[ -e $systemctl_saved ]]; then mv -- "$systemctl_saved" "$shim/systemctl"; fi
  fi
  for command in "${stood[@]}"; do rm -f -- "${shim:?}/$command"; done
  cp -- "$pkg_real" "$repo/bin/vgshell-pkg.next" && mv -T -- "$repo/bin/vgshell-pkg.next" "$repo/bin/vgshell-pkg"
  rescan "the Voice setup scene's stand-ins are removed"
}
# voice_setup_press LABEL: Set up pressed on the Settings window, through
# the manager's openTui as its Setup button hands it on (harness.sh's
# settings_open_tui), or, for a tree whose Voice dictates through the
# core, through the manager's act on the setup entry (settings_act), then
# the window hidden, so the shot shows what the press raised over the
# desktop.
voice_setup_press() { # LABEL
  expect "$1: the Settings window opens" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "$1: the Settings window maps" 1 settings_count
  if voice_dictates; then
    expect "$1: the setup step is answered" ok settings_act vgs.voice setup
  else
    expect "$1: Set up is answered" ok settings_open_tui vgs.voice setup
  fi
  settings_close
}
# voice_install_press LABEL: Install all missing pressed for Voice on the
# Settings window, through the manager's installRequirements as the
# Requirements section's button hands it on, then the window hidden.
voice_install_press() { # LABEL
  expect "$1: the Settings window opens" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "$1: the Settings window maps" 1 settings_count
  expect "$1: Install all missing is answered" ok ipc smoke invokeInstance "$settings_kind" vgs.settings installRequirements vgs.voice
  settings_close
}
# voice_setup_page LABEL SHOT CHIP: the Settings window opened on Voice's
# page, scrolled so the Setup tab's sections, the button row included, are
# in view once every status row is reported, shot as SHOT with the pointer
# parked, then hidden. On a tree whose Voice puts its setup
# state in the Setup group, the shot waits for the section's chip to read
# CHIP; an older tree draws none.
voice_setup_page() { # LABEL SHOT CHIP
  expect "$1: the Settings window opens on Voice's page" ok ipc shell summon "$settings_kind" vgs.settings '{"plugin":"vgs.voice"}'
  expect_poll "$1: the Settings window maps" 1 settings_count
  expect_poll "$1: Voice's page is shown" '"vgs.voice"' settings_page
  if [[ $3 == none ]]; then
    # The published hidden setup state is the one entry Voice's page
    # draws, so the page draws no status row once it lands.
    expect_poll "$1: Voice's hidden setup state is reported" 0 page_status_rows vgs.voice
  else
    expect_poll "$1: Voice's status is reported" True page_reported vgs.voice
  fi
  page_setup
  if grep -qF '"group": "Setup"' "$tree/shell/plugins/vgs.voice/manifest.json"; then
    expect_poll "$1: the Setup section's chip reads $3" "$3" voice_setup_chip
  fi
  voice_setup_reveal || fail "$1: the Setup tab's sections could not be scrolled into view"
  expect_poll "$1: the Setup tab's sections, their buttons included, are in view" in-view voice_setup_in_view
  park_pointer
  take "$2"
  settings_close
}
# voice_setup_span: the Setup tab's shown sections, Status, Setup and
# Requirements, as one span, [top, bottom, contentY, height] as the
# probe's sectionSpan reads each: the least top and the greatest bottom;
# `absent` while none shows.
voice_setup_span() {
  local title span spans=()
  for title in Status Setup Requirements; do
    span="$(ipc smoke sectionSpan "$settings_kind" vgs.settings "$title")" || return 1
    [[ $span == \[* ]] && spans+=("$span")
  done
  python3 -c 'import json,sys
s = [json.loads(v) for v in sys.argv[1:]]
print(json.dumps([min(v[0] for v in s), max(v[1] for v in s), s[0][2], s[0][3]]) if s else "absent")' "${spans[@]}"
}
# voice_setup_reveal: the page's scroll area moved, through the probe's
# scrollTo, so the Setup tab's sections' top and their bottom, the button
# row, both lie in view: as far as their bottom needs, never past their top.
voice_setup_reveal() {
  local span y
  span="$(voice_setup_span)" && [[ $span == \[* ]] || return 1
  y="$(python3 -c 'import json,sys; top, bottom, _, height = json.loads(sys.argv[1]); print(int(min(top, max(0, bottom - height))))' "$span")" || return 1
  ipc smoke scrollTo "$settings_kind" vgs.settings "$y" >/dev/null
}
# `in-view` once the Setup tab's sections lie whole in the page's view,
# else their span.
voice_setup_in_view() { voice_setup_span | py_reply 'import json,sys; t=sys.stdin.read(); s=json.loads(t) if t.startswith("[") else None; print("in-view" if s is not None and s[0] >= s[2] - 0.5 and s[1] <= s[2] + s[3] + 0.5 else t.strip())'; }
# The first chip text of the page's Status and Setup sections, `none`
# when they draw none: the probe's setupSection answers `absent` while
# neither shows, as Voice's page draws only Requirements then.
voice_setup_chip() {
  local reply
  reply="$(ipc smoke setupSection "$settings_kind" vgs.settings)" || return 1
  if [[ $reply == absent ]]; then echo none; return 0; fi
  py_reply 'import json,sys; c=json.load(sys.stdin)["chips"]; print(c[0][0] if c else "none")' <<<"$reply"
}
# Whether Voice's own setup state offers Set up, as its service holds it.
voice_setup_wanted() { ipc smoke readInstance service vgs.voice setupValue | py_reply 'import json,sys; a=json.load(sys.stdin).get("action"); print("none" if a == "" else a)'; }
voice_setup_requirement() { ipc shell listPlugins | py_reply 'import json,sys; print([r["state"] for p in json.load(sys.stdin)["plugins"] if p["id"] == "vgs.voice" for r in p["requirements"] if r["name"] == sys.argv[1]][0])' "$1"; }
# The run id of Set up's last ended run, or `none`.
voice_setup_run() { ipc shell lent | py_reply 'import json,sys; r=json.load(sys.stdin)["tui"]["runs"].get(sys.argv[1]) or {}; e=r.get("ended"); print(e["run"] if e else "none")' "$voice_setup_key"; }
# The code of Set up's ended run once it is another run than BEFORE and no
# run of the key is live, else `pending`.
voice_setup_code() { # BEFORE
  ipc shell lent | py_reply 'import json,sys; r=json.load(sys.stdin)["tui"]["runs"].get(sys.argv[2]) or {}; e=r.get("ended"); print(e["code"] if e and e["run"] != sys.argv[1] and r.get("running") is None else "pending")' "$1" "$voice_setup_key"
}
voice_setup_toasts() { ipc shell lent | py_reply 'import json,sys; t=json.load(sys.stdin)["toasts"]; print(sum(r["plugin"] == "vgs.voice" for k in ("visible", "waiting") for r in t[k]))'; }
# Voice's cards in vgs.notifications' layer: the core sends Voice's
# message under its manifest name.
voice_setup_cards() { ipc smoke layerItems vgs.notifications NotificationCard app | py_reply 'import json,sys; print(sum(v["app"] == "Voice" for _, _, v in json.load(sys.stdin)))'; }
voice_setup_silence() { notes status | py_reply 'import json,sys; print(str(json.load(sys.stdin)["silence"]).lower())'; }
# The launcher state present, so the press launches: a host without
# xdg-terminal-exec left it missing at the shell's start, and one request
# then answers launcher-missing, launches nothing and probes again, now
# against the stand-in.
voice_setup_launcher() { ipc shell lent | py_reply 'import json,sys; print(json.load(sys.stdin)["tui"]["launcher"])'; }
voice_setup_launcher_ready() {
  if [[ $(voice_setup_launcher) == missing ]]; then
    expect "a request before the stand-in's probe answers launcher-missing" "refused: tui=core/doctor reason=launcher-missing" ipc shell openTui core/doctor
  fi
  expect_poll "the launcher state is present for the Voice setup run" present voice_setup_launcher
}

# Voice's Settings page beside a voxtype daemon the shell did not start,
# one the scene starts as rows/dictation.sh's own daemon stands for one
# the user's session runs: the core's probe finds it answering and reads
# it elsewhere. The daemon then ends with TERM, as the step's
# `systemctl --user disable --now` ends it. A tree whose Voice offers Stop
# the other voxtype runs that step over the stand-in terminal (harness.sh's
# terminal_stand_in), which runs `true` for the script, and is shot once
# the core's daemon, started again on the run's code 0, reads ready; an
# older tree is shot after a bounded wait, still reading elsewhere. The
# model reads installed throughout, so the daemon's is the only Setup
# line; voxtype-audio-bridge stands in beside voxtype, so the enable raises
# no requirement notice. Enablement and stand-ins are put back, the notice
# an enable without them raises closed, and no daemon is left.
voice_elsewhere_pid=""
voice_elsewhere_state() { "${shell_env[@]}" PATH="$shell_start_path" "$shim/voxtype" status --format json | py_reply 'import json,sys; print(json.load(sys.stdin)["alt"])'; }
voice_elsewhere_end() {
  [[ -z $voice_elsewhere_pid ]] || { kill -TERM "$voice_elsewhere_pid" 2>/dev/null || true; wait "$voice_elsewhere_pid" 2>/dev/null || true; }
  voice_elsewhere_pid=""
}
scene_voice-elsewhere() { # MODE
  local voice_found settings_found stood=() command before stops=false
  tree_has shell/plugins/vgs.voice/manifest.json '"stop-other"' && stops=true
  voice_found="$(plugin_enabled vgs.voice)" || voice_found=unread
  settings_found="$(plugin_enabled vgs.settings)" || settings_found=unread
  [[ $voice_found == True || $voice_found == False ]] || fail "vgs.voice's enablement is unreadable before the Voice elsewhere scene: $voice_found"
  [[ $settings_found == True || $settings_found == False ]] || fail "vgs.settings' enablement is unreadable before the Voice elsewhere scene: $settings_found"
  voice_stand_ins
  voice_bridge_stand_in
  : >"$voice_model_installed"
  # Voice's required commands stand in where the shell finds none, the
  # bridge with voxtype, so enabling it raises no notice of its own.
  for command in wtype wl-copy; do
    [[ $(shell_resolves "$command") == none ]] || continue
    printf '#!/bin/sh\nexit 0\n' >"$shim/$command"
    chmod 755 "$shim/$command"
    stood+=("$command")
  done
  rescan "the Voice elsewhere scene's stand-ins are scanned"
  # Disabling Voice ends the core's daemon, which would refuse the other.
  if [[ $voice_found == True ]]; then
    expect "disabling vgs.voice before the other voxtype starts is allowed" ok ipc shell setPluginEnabled vgs.voice false
    expect_poll "vgs.voice is gone before the other voxtype starts" False record_exists vgs.voice
  fi
  expect_poll "no voxtype daemon answers before the other one starts" stopped voice_elsewhere_state
  "${shell_env[@]}" PATH="$shell_start_path" "$shim/voxtype" daemon >>"$sandbox/voice-elsewhere-daemon.log" 2>&1 &
  voice_elsewhere_pid=$!
  expect_poll "the other voxtype daemon answers" idle voice_elsewhere_state
  if [[ $settings_found == False ]]; then
    expect "enabling vgs.settings for the Voice elsewhere scene is allowed" ok ipc shell setPluginEnabled vgs.settings true
    expect_poll "vgs.settings is built for the Voice elsewhere scene" True record_exists vgs.settings
  fi
  expect "enabling vgs.voice beside the other voxtype is allowed" ok ipc shell setPluginEnabled vgs.voice true
  expect_poll "vgs.voice is built beside the other voxtype" True record_exists vgs.voice
  expect_poll "the core reads the other voxtype's daemon elsewhere" "elsewhere idle" voice_daemon
  voice_setup_page "Voice's page beside another voxtype" "voice-elsewhere-$1-page" "Setup needed"
  [[ $stops == false ]] || expect_poll "Voice offers Stop the other voxtype" stop voice_setup_wanted

  voice_elsewhere_end
  expect_poll "the other voxtype daemon has ended" stopped voice_elsewhere_state
  if [[ $stops == true ]]; then
    voice_setup_key=vgs.voice/stop-other
    terminal_stand_in
    voice_setup_launcher_ready
    before="$(voice_setup_run)" || before=unread
    voice_setup_press "the Stop the other voxtype run"
    expect_poll "the Stop the other voxtype run ends with code 0" 0 voice_setup_code "$before"
    expect_poll "the core's daemon is ready after the Stop the other voxtype run" "ready idle" voice_daemon
    voice_setup_page "Voice's page after the other voxtype stopped" "voice-elsewhere-$1-page-after" "Ready"
  else
    # A tree from before the step: a short bounded wait, 2 s, for a probe
    # it never makes.
    for _ in $(seq 1 10); do [[ $(voice_daemon) == "elsewhere idle" ]] || break; sleep 0.2; done
    voice_setup_page "Voice's page after the other voxtype stopped" "voice-elsewhere-$1-page-after" "Setup needed"
  fi

  # Disabling Voice ends the core's daemon; Voice is enabled again without
  # the stand-ins when the scene found it on.
  expect "disabling vgs.voice after the Voice elsewhere scene is allowed" ok ipc shell setPluginEnabled vgs.voice false
  expect_poll "vgs.voice is gone after the Voice elsewhere scene" False record_exists vgs.voice
  if [[ $settings_found == False ]]; then
    expect "disabling vgs.settings after the Voice elsewhere scene is allowed" ok ipc shell setPluginEnabled vgs.settings false
    expect_poll "vgs.settings is gone after the Voice elsewhere scene" False record_exists vgs.settings
  fi
  expect_poll "no voxtype daemon answers after the Voice elsewhere scene" stopped voice_elsewhere_state
  voice_stand_ins_removed
  rm -f -- "${shim:?}/voxtype-audio-bridge"
  for command in "${stood[@]}"; do rm -f -- "${shim:?}/$command"; done
  rescan "the Voice elsewhere scene's stand-ins are removed"
  if [[ $voice_found == True ]]; then
    expect "enabling vgs.voice again after the Voice elsewhere scene is allowed" ok ipc shell setPluginEnabled vgs.voice true
    expect_poll "vgs.voice is built again after the Voice elsewhere scene" True record_exists vgs.voice
    voice_enable_notice_closed "enabling Voice again without its stand-ins"
  fi
}

# The themes panel summoned over the shipped and catalog packages, the
# light catalog package installed and a refused one: its top, the pointer
# on a row, its catalog scrolled into view, a click on the vgs row held
# behind a gate and the partial result the gate lets through. The stand-in
# runner answers every apply with the exit code and result in
# themes_answer, which change no theme, polls the gate every 50 ms for at
# most 10 s and hands every other command to the real runner. The core
# keeps the last apply result for the shell's life (ThemeRunner.qml), so
# the scene ends on a second click answered with a quiet result, and the
# next pass opens a panel that draws no line under the vgs row. For the
# scene a dark mode's theme file holds the shipped vgs bytes, so its row
# is current and not modified, as the installed light package's is in
# light. The dark and light passes, narrow ones included, must draw the
# same rows, badges and lines at the top and after the failure, Displayed
# aside, which marks the mode's own theme: the first of them sets each
# stage's reference.
themes_mismatch="$home/.config/vgshell/themes/mismatch"
themes_installed=flexoki-light
themes_installed_dir="$home/.config/vgshell/themes/$themes_installed"
themes_gate="$sandbox/shots-themes-gate"
themes_answer="$sandbox/shots-themes-answer"
themes_failed='{"state":"partial","shell":"unchanged","targets":[{"name":"kitty","state":"failed","reason":"placeholder"}],"theme":"vgs","reason":null}'
themes_quiet='{"state":"ok","shell":"unchanged","targets":[],"theme":"vgs","reason":null}'
declare -A themes_panel_reference=() themes_panel_first=()
themes_panel_listed() { ipc smoke readInstance panel vgs.themes catalogEntries | py_reply 'import json,sys; t=sys.stdin.read(); print(t.startswith("[") and len(json.loads(t)) > 0)'; }
themes_panel_shown() { [[ $(ipc smoke readInstance panel vgs.themes packages) != absent ]] && echo open || echo closed; }
themes_panel_last() { ipc smoke readInstance panel vgs.themes last | py_reply 'import json,sys; l=json.load(sys.stdin); print("applying" if l["applying"] else "result" if l["result"] else "none")'; }
# The state of the last apply result the panel draws, or `applying` or
# `none`.
themes_panel_result() { ipc smoke readInstance panel vgs.themes last | py_reply 'import json,sys; l=json.load(sys.stdin); r=l["result"]; print("applying" if l["applying"] else "none" if r is None else r["state"])'; }
# The core's retained list, which the panel copies when it opens: whether
# it accepts the installed light package, and the theme file's package and
# whether it is modified, as `NAME MODIFIED`; and the catalog's install
# flag for that package.
themes_listed_installed() { ipc smoke readInstance service vgs.themes listing | py_reply 'import json,sys; l=json.load(sys.stdin); print(l is not None and any(p["name"] == sys.argv[1] and p["state"] == "ok" for p in l["packages"]))' "$themes_installed"; }
themes_listed_file() { ipc smoke readInstance service vgs.themes listing | py_reply 'import json,sys; l=json.load(sys.stdin); print("none" if l is None else "%s %s" % (l["file"]["name"], json.dumps(l["file"]["modified"])))'; }
themes_catalog_installed() { ipc smoke readInstance service vgs.themes catalog | py_reply 'import json,sys; e=json.load(sys.stdin)["entries"] or []; print(any(x["name"] == sys.argv[1] and x["installed"] for x in e))' "$themes_installed"; }
# The panel's digest: each ThemeRow's visible texts, its name, secondary
# line, badges, action and lines, in tree order, Displayed dropped.
themes_panel_state() { ipc smoke itemTexts panel vgs.themes ThemeRow | py_reply 'import json,sys; print(json.dumps([[t for t in row if t != "Displayed"] for row in json.load(sys.stdin)], ensure_ascii=False))'; }
# `ok` when the rows that draw Displayed are exactly the rows named after
# the published theme, at least one; else the names of the rows that do.
themes_panel_displayed() {
  local name
  name="$(ipc smoke themeName)" || return 1
  ipc smoke itemTexts panel vgs.themes ThemeRow | py_reply 'import json,sys
rows = [r for r in json.load(sys.stdin) if r]
shown = [r[0] for r in rows if "Displayed" in r]
print("ok" if shown and shown == [r[0] for r in rows if r[0] == sys.argv[1]] else "displayed=" + json.dumps(shown))' "$name"
}
# `ok` once the panel lists its catalog, reads the theme file unmodified
# and marks the published theme's rows Displayed; else what it lacks.
themes_panel_settled() {
  local listed file
  listed="$(themes_panel_listed)" || return 1
  [[ $listed == True ]] || { echo "catalog-listed=$listed"; return 0; }
  file="$(ipc smoke readInstance panel vgs.themes file | py_reply 'import json,sys; f=json.load(sys.stdin); print("unmodified" if f is not None and f["modified"] is False else "file=" + json.dumps(f))')" || return 1
  [[ $file == unmodified ]] || { echo "$file"; return 0; }
  themes_panel_displayed
}
# themes_panel_compare MODE STAGE: in a dark or light mode, the first one
# the run takes records STAGE's digest once the panel has settled, and
# every later one must draw that digest.
themes_panel_compare() {
  local base="${1%-narrow}" digest
  [[ $base == dark || $base == light ]] || return 0
  if [[ -z ${themes_panel_first[$2]:-} ]]; then
    expect_poll "the themes panel has settled for its $2 reference ($1)" ok themes_panel_settled
    if digest="$(themes_panel_state)"; then
      themes_panel_reference[$2]="$digest"
      themes_panel_first[$2]="$1"
    else
      fail "the themes panel's $2 rows are unreadable ($1): $digest"
    fi
  else
    expect_poll "the themes panel shows the same rows, badges and messages as the ${themes_panel_first[$2]} pass at its $2 ($1)" "${themes_panel_reference[$2]}" themes_panel_state
    expect "the themes panel marks the published theme's rows Displayed at its $2 ($1)" ok themes_panel_displayed
  fi
}
# themes_answer_write CODE RESULT: the stand-in's answer to the next apply.
themes_answer_write() {
  printf '%s\n%s\n' "$1" "$2" >"$themes_answer.tmp" && mv -T -- "$themes_answer.tmp" "$themes_answer"
}
themes_stand_in() {
  cp -p -- "$repo/bin/vgshell" "$repo/bin/vgshell.real" || return 1
  cat >"$repo/bin/vgshell.next" <<SH || return 1
#!/usr/bin/env bash
if [[ \${1:-} == theme && \${2:-} == apply ]]; then
  for _ in \$(seq 1 200); do [[ -e $(printf %q "$themes_gate") ]] && break; sleep 0.05; done
  { IFS= read -r code && IFS= read -r answer; } <$(printf %q "$themes_answer") || exit 1
  printf '%s\n' "\$answer"
  exit "\$code"
fi
exec $(printf %q "$repo/bin/vgshell.real") "\$@"
SH
  chmod 755 -- "$repo/bin/vgshell.next" && mv -T -- "$repo/bin/vgshell.next" "$repo/bin/vgshell"
}
scene_themes_panel() { # MODE
  local base="${1%-narrow}" name
  mkdir -p -- "$themes_mismatch"
  printf '%s\n' '{ "schemaVersion": 1, "name": "other", "tokens": {} }' >"$themes_mismatch/theme.json"
  rm -rf -- "${themes_installed_dir:?}"
  # The runner's install writes the catalog marker the catalog reads the
  # package installed by.
  sandbox_vgshell theme install "$themes_installed" >/dev/null || fail "$themes_installed installs for the themes panel"
  if [[ $base == dark ]]; then
    { cp -- "$repo/themes/vgs/theme.json" "$theme_file.tmp" && mv -T -- "$theme_file.tmp" "$theme_file"; } || fail "the shipped vgs theme file could not be written for the themes panel"
  fi
  expect_poll "the theme list accepts the installed $themes_installed for the themes panel ($1)" True themes_listed_installed
  expect_poll "the catalog reads $themes_installed installed for the themes panel ($1)" True themes_catalog_installed
  if [[ $base == dark || $base == light ]]; then
    if name="$(ipc smoke themeName)"; then
      expect_poll "the theme list reads the $name theme file unmodified for the themes panel ($1)" "$name false" themes_listed_file
    else
      fail "the published theme's name is unreadable for the themes panel ($1)"
    fi
  fi
  expect "the unanchored themes panel summons" ok ipc shell summon panel vgs.themes '{}'
  expect_poll "the themes panel lists its catalog" True themes_panel_listed
  ipc smoke scrollTo panel vgs.themes 0 >/dev/null || fail "the themes panel did not scroll to its top for its initial image"
  themes_panel_compare "$1" top
  park_pointer
  take "panels-$1-themes"
  ipc smoke revealText panel vgs.themes ListItem vgs >/dev/null || fail "the themes panel did not reveal its vgs row for the hover"
  hover_on "the pointer rests on the themes panel's vgs row" panel vgs.themes ListItem vgs vgs:panel && take_posed "panels-$1-themes-hover"
  park_pointer
  ipc smoke scrollTo panel vgs.themes 100000 >/dev/null || fail "the themes panel did not scroll to its catalog"
  take "panels-$1-themes-catalog"
  ipc smoke scrollTo panel vgs.themes 0 >/dev/null || fail "the themes panel did not scroll to its top"
  rm -f -- "$themes_gate"
  { themes_answer_write 3 "$themes_failed" && themes_stand_in; } || fail "the themes panel's stand-in runner could not be written"
  click_in vgs:panel panel vgs.themes ListItem vgs || fail "the click on the themes panel's vgs row failed"
  expect_poll "the themes panel shows the held apply" applying themes_panel_last
  park_pointer
  take "panels-$1-themes-applying"
  touch -- "$themes_gate"
  expect_poll "the themes panel shows the partial result" result themes_panel_last
  themes_panel_compare "$1" failure
  take "panels-$1-themes-failure"
  themes_answer_write 0 "$themes_quiet" || fail "the themes panel's quiet answer could not be written"
  click_in vgs:panel panel vgs.themes ListItem vgs || fail "the click that clears the themes panel's result failed"
  expect_poll "the themes panel's last result is the quiet one, which draws no line" ok themes_panel_result
  mv -T -- "$repo/bin/vgshell.real" "$repo/bin/vgshell" || fail "the real runner could not be restored"
  rm -f -- "$themes_gate" "$themes_answer"
  expect "the themes panel hides" ok ipc shell hide panel vgs.themes
  expect_poll "the themes panel is gone" closed themes_panel_shown
  rm -rf -- "${themes_mismatch:?}" "${themes_installed_dir:?}"
  # Later scenes read the run's own theme file again.
  [[ $base != dark ]] || set_mode "$base"
}

# The Dev Tools window: its top, the pointer on an Install button, and one
# shot per page down its list, at most four.
devtools_shown() { [[ $(ipc smoke instanceGeometry window vgs.devtools) != absent ]] && echo shown || echo hidden; }
devtools_sections() { ipc smoke itemTexts window vgs.devtools SectionHeader | py_reply 'import json,sys; print(len(json.load(sys.stdin)) > 1)'; }
scene_devtools() { # MODE
  local page=1 y=0 at cy ch h hover=Install
  expect "the Dev Tools window summons" ok ipc vgs.devtools invoke open ''
  expect_poll "the Dev Tools window is shown" shown devtools_shown
  expect_poll "the Dev Tools window draws its sections" True devtools_sections
  expect "the Dev Tools window's root takes the focus for the top image" focused ipc smoke invokeInstance window vgs.devtools focusInstance ""
  take "devtools-$1-top"
  # The VGS row draws Details only where its problem line clips
  # (ToolRow.qml), as in the narrow pass: the sandbox's install method is
  # always unknown, so the line is there whatever the other scenes set up.
  # Where the line fits, the first row's Install takes the hover.
  [[ $(ipc smoke windowGeometry window vgs.devtools RowAction Details) != \[* ]] || hover=Details
  local hover_offset
  hover_offset="$(ipc smoke revealText window vgs.devtools RowAction "$hover")" || hover_offset=unread
  [[ $hover_offset =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "the Dev Tools $hover button was not revealed: $hover_offset"
  hover_on "the pointer rests on the Dev Tools $hover button" window vgs.devtools RowAction "$hover" "window:Dev Tools" && take_posed "devtools-$1-hover"
  park_pointer
  while (( page <= 4 )); do
    at="$(ipc smoke scrollTo window vgs.devtools "$y")" || at=""
    if [[ $at != "["* ]]; then fail "the Dev Tools window did not scroll: ${at:-no reply}"; break; fi
    read -r cy ch h < <(python3 -c 'import json,sys; print(*(int(v) for v in json.loads(sys.argv[1])))' "$at")
    (( page == 1 )) || take "devtools-$1-p$page"
    (( cy + h < ch )) || break
    y=$(( cy + h - 40 )); page=$(( page + 1 ))
  done
  expect "the Dev Tools window hides" ok ipc shell hide window vgs.devtools
  expect_poll "the Dev Tools window is gone" hidden devtools_shown
}

# The System window as it opens with no System section enabled: the
# sidebar holds Shell & Plugins alone and the page its empty state. The
# sandbox starts the plugin disabled, so the scene enables it for the shot
# and disables it again. A tree that ships vgs.displays then takes System
# → Displays, system-<mode>-displays, over the device fakes' Pro Display
# XDR, placed on the output by the pane's own choice, and two Studio
# Displays the helper cannot place; the fakes' system tree keeps the
# core's step probe off the host's /sys and /dev. The arrangement shows two
# monitors: the shot's own output and a second nested Wayland output placed
# as the owner's portrait 5K is, left of and above it, which the scene
# removes after the shot. A headless output stays 0x0 in the sandbox
# (scripts/smoke/mode-hold.sh); a nested Wayland output takes the mode.
# A tree that ships vgs.sound then takes its Sound section,
# system-<mode>-sound, over the sandbox's private PipeWire
# (scripts/smoke/devices.sh), with a test stream that plays in the
# sandbox's environment alone, enabled for the shot and disabled again.
# A tree that ships vgs.mouse then takes its Mouse section,
# system-<mode>-mouse, over Hyprland's nested pointer list, enabled for
# the shot and disabled again, and the same section with Pointer speed
# set over the user's own line, system-<mode>-mouse-overridden: the user
# file sets the speed, so the layer applies the option, and a line after
# the VGS loading line of hyprland.lua sets another, as rows/mouse.sh
# plants it, so the row names that value and offers it. Both
# files go back as the take found them. Displays stays enabled through the
# other Hardware shots, so the sidebar shows the group as a user with
# several sections sees it.
system_shown() { [[ $(ipc smoke instanceGeometry window vgs.system) != absent ]] && echo shown || echo hidden; }
displays_output="VGS-PLANTED-VRR"
# The rule of the Displays shot's second monitor: a 5120x2880 panel at
# scale 2, turned to portrait, left of and above the shot's output.
displays_output_rule="hl.monitor({ output = \"$displays_output\", mode = \"5120x2880@60\", position = \"-1440x-620\", scale = 2, transform = 1 })"
# The displays service's reading of the second monitor as WxH@X,Y
# scale=S transform=T, or absent while it lists none.
displays_second_output() { ipc smoke readInstance service vgs.displays outputs | py_reply 'import json,sys; m=[o for o in json.load(sys.stdin) if o["name"]==sys.argv[1]]; print("%dx%d@%d,%d scale=%g transform=%d" % (m[0]["width"], m[0]["height"], m[0]["x"], m[0]["y"], m[0]["scale"], m[0]["transform"]) if m else "absent")' "$displays_output"; }
# displays_output_taken: the Displays shot's second monitor rule applied
# again, then the compositor's reading of that monitor as WxH@X,Y scale=S
# transform=T. A nested Wayland output comes up at the host window's size
# and takes a rule's mode only once it exists, as take_mode in
# scripts/smoke/mode-hold.sh applies it, so each poll applies the rule.
displays_output_taken() {
  local reply
  reply="$(hypr eval "$displays_output_rule")" || { echo eval-failed; return; }
  [[ $reply == ok ]] || { echo eval-refused; return; }
  hypr -j monitors all | py_reply 'import json,sys; m=[o for o in json.load(sys.stdin) if o["name"]==sys.argv[1]]; print("%dx%d@%d,%d scale=%g transform=%d" % (m[0]["width"], m[0]["height"], m[0]["x"], m[0]["y"], m[0]["scale"], m[0]["transform"]) if m else "absent")' "$displays_output"
}
# Adding the scaled output changes HyprlandLayer's highestMonitorScale;
# its asynchronous reload clears eval-only rules (smoke/mode-hold.sh).
# The scene's saved configuration keeps this rule through later reloads.
# Reapply through the bounded poll until Hyprland and the service agree.
# eval emits no monitor event, so a stale service needs another refresh.
displays_outputs_applied() {
  local taken listed reply
  listed="$(displays_second_output)" || { echo service-unread; return; }
  taken="$(displays_output_taken)" || { echo hyprland-unread; return; }
  if [[ $taken != '5120x2880@-1440,-620 scale=2 transform=1' ]]; then
    printf 'hyprland=[%s] service=[%s]\n' "$taken" "$listed"
  elif [[ $listed != "$taken" ]]; then
    reply="$(hypr output create headless "$displays_output-READ")" || { echo refresh-create-failed; return; }
    [[ $reply == ok ]] || { echo refresh-create-refused; return; }
    reply="$(hypr output remove "$displays_output-READ")" || { echo refresh-remove-failed; return; }
    [[ $reply == ok ]] || { echo refresh-remove-refused; return; }
    printf 'hyprland=[%s] service=[%s]\n' "$taken" "$listed"
  else
    printf '%s\n' "$taken"
  fi
}
displays_listed() { ipc smoke readInstance service vgs.displays values | py_reply 'import json,sys; print(len(json.load(sys.stdin)["displays"]["items"]))'; }
# How many shown actions of the Mouse section offer the user's own value.
mouse_offers() { ipc smoke descendantGeometry window vgs.mouse | py_reply 'import json,sys; print(sum(1 for i in json.load(sys.stdin) if i["name"] == "useHyprlandValue" and i["visible"]))'; }
mouse_speed() { hypr -j getoption input:sensitivity | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v.get("float"), v["set"]]))'; }
take_mouse_overridden() { # MODE
  local user="$home/.config/vgshell/shell.json" saved="$sandbox/shell-before-mouse-shot.json"
  cp -- "$user" "$saved"
  hypr_lua_save mouse-shot
  python3 - "$user" <<'PY' || fail "the user file took no pointer speed"
import json, os, sys
path = sys.argv[1]
config = json.load(open(path))
rows = config.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.mouse"), None)
if row is None:
    row = {"id": "vgs.mouse"}
    rows.append(row)
row["sensitivity"] = 0.5
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PY
  expect "the configuration reloads with a pointer speed" ok ipc shell reloadConfig
  expect_poll "the layer's pointer speed reaches Hyprland" '[0.5, true]' mouse_speed
  printf '%s\n' 'hl.config({ input = { sensitivity = -0.5 } })' >>"$home/.config/hypr/hyprland.lua"
  expect "the nested instance reloads with the user's pointer speed" ok hypr reload config-only
  expect_poll "the Pointer speed row offers the user's value" 1 mouse_offers
  park_pointer
  take "system-$1-mouse-overridden"
  hypr_lua_restore mouse-shot || fail "hyprland.lua is put back after the overridden Mouse shot"
  expect "the nested instance reloads without the user's pointer speed" ok hypr reload config-only
  cp -- "$saved" "$user.next" && mv -T -- "$user.next" "$user" || fail "the user file is put back after the overridden Mouse shot"
  expect "the configuration reloads as the Mouse shot found it" ok ipc shell reloadConfig
}
scene_wide-settings() { # MODE
  local first_output geometry status=0
  devices_up || status=$?
  if ((status != 0)); then fail "the wide Settings device fakes failed: $devices_state"; return; fi
  devices_system_tree >/dev/null || { fail "the wide Settings system tree failed"; return; }
  devices_audio_play
  for id in vgs.system vgs.displays vgs.mouse vgs.sound; do
    expect "enabling $id for wide Settings is allowed" ok ipc shell setPluginEnabled "$id" true
    expect_poll "$id is built for wide Settings" True record_exists "$id"
  done
  expect_poll "the wide Settings displays are listed" 3 displays_listed
  first_output="$(ipc smoke readInstance service vgs.displays outputs | py_reply 'import json,sys; print(json.load(sys.stdin)[0]["identifier"])')" || return
  expect "wide Settings assigns the XDR" ok ipc vgs.displays invoke assign "{\"device\":\"usb:class/hidraw/hidraw0/device#VGSSMOKEXDR01\",\"output\":\"$first_output\"}"
  python3 - "$theme_file" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
doc.setdefault("tokens", {}).setdefault("size", {}).setdefault("window", {}).update({"width": 2000, "heightShare": 0.8})
with open(path + ".tmp", "w") as out:
    json.dump(doc, out)
os.replace(path + ".tmp", path)
PY
  expect_poll "the wide Settings window token is published" 2000 ipc smoke themeValue size.window.width
  for id in vgs.displays vgs.mouse vgs.sound; do
    expect "wide Settings opens $id" ok ipc shell summon window vgs.system "{\"pane\":\"$id\"}"
    expect_poll "wide Settings mounts $id" "[\"$id\"]" window_panes
    if [[ $id == vgs.sound ]]; then
      expect_poll "wide Settings Sound lists the test stream" true sound_lists_player
    fi
    expect "wide Settings clears visual focus" focused ipc smoke invokeInstance window vgs.system focusInstance ""
    park_pointer
    take "wide-settings-$1-$id"
    if geometry="$(ipc smoke instanceGeometry window vgs.system)"; then
      record_item "wide-settings-$1-$id" "$geometry"
    else
      fail "the wide Settings window geometry is unreadable for $id"
    fi
    expect "wide Settings closes $id" ok ipc shell hide window vgs.system
    expect_poll "wide Settings is gone after $id" hidden system_shown
  done
  kill -- "-$devices_player_pid" 2>/dev/null || true
  set_mode "$1"
}

scene_system() { # MODE
  local status=0 tree_state first_output displays_on=false geometry_failures
  expect "enabling vgs.system for its shot is allowed" ok ipc shell setPluginEnabled vgs.system true
  expect "the System window summons" ok ipc shell summon window vgs.system '{}'
  expect_poll "the System window is shown" shown system_shown
  expect "the System window's root takes the focus" focused ipc smoke invokeInstance window vgs.system focusInstance ""
  park_pointer
  take "system-$1"
  expect "the System window hides" ok ipc shell hide window vgs.system
  expect_poll "the System window is gone" hidden system_shown
  if ships_plugin vgs.displays; then
    devices_up || status=$?
    if ((status != 0)); then
      fail "the device fakes for the Displays shot did not start: $devices_state"
    elif ! tree_state="$(devices_system_tree)"; then
      fail "the fakes' system tree for the Displays shot: $tree_state"
    else
      expect "enabling vgs.displays for its shot is allowed" ok ipc shell setPluginEnabled vgs.displays true
      expect_poll "the displays service lists the three fake displays" 3 displays_listed
      first_output="$(ipc smoke readInstance service vgs.displays outputs | py_reply 'import json,sys; print(json.load(sys.stdin)[0]["identifier"])')" || fail "the outputs the displays service reads are unreadable"
      expect "the pane's choice puts the XDR on the output" ok ipc vgs.displays invoke assign "{\"device\":\"usb:class/hidraw/hidraw0/device#VGSSMOKEXDR01\",\"output\":\"$first_output\"}"
      hypr_lua_save displays-shot
      printf '%s\n' "$displays_output_rule" >>"$home/.config/hypr/hyprland.lua"
      expect "the nested compositor adds the Displays shot's second monitor" ok hypr output create wayland "$displays_output"
      # The nested Wayland panel has no VRR hardware. Only the shell's
      # systeminfo read gets the planted capability; its output name labels
      # the planted panel in the arrangement canvas.
      cat >"$sandbox/displays-systeminfo" <<EOF
Monitor info:
	Panel $displays_output: 5120x2880, 60 -> backend wayland
		explicit ❌
		edid:
			hdr ❌
			chroma ❌
			bt2020 ❌
		vrr capable ✔️
		non-desktop ❌
State:
EOF
      cat >"$shim/hyprctl.displays-shot" <<EOF
#!/usr/bin/env bash
if [[ \$* == *systeminfo ]]; then cat -- "$sandbox/displays-systeminfo"; else exec "$shim/hyprctl.real" "\$@"; fi
EOF
      chmod 755 "$shim/hyprctl.displays-shot"
      shim_hyprctl displays-shot
      expect "System → Displays summons" ok ipc shell summon window vgs.system '{"pane":"vgs.displays"}'
      expect_poll "System → Displays is shown" '["vgs.displays"]' window_panes
      geometry_failures=$failures
      expect_poll "displays-geometry-not-applied: Hyprland and the displays service agree on the second monitor's rule" "5120x2880@-1440,-620 scale=2 transform=1" displays_outputs_applied
      expect "the displays service lists the second monitor where the rule puts it" "5120x2880@-1440,-620 scale=2 transform=1" displays_second_output
      if ((failures == geometry_failures)); then
        park_pointer
        take "system-$1-displays"
      fi
      shim_hyprctl real
      expect "the System window hides after Displays" ok ipc shell hide window vgs.system
      expect_poll "the System window is gone after Displays" hidden system_shown
      expect "the Displays shot's second monitor is removed" ok hypr output remove "$displays_output"
      expect_poll "the displays service drops the second monitor" absent displays_second_output
      hypr_lua_restore displays-shot || fail "hyprland.lua is put back after the Displays shot"
      expect "the nested instance reloads without the Displays shot's rule" ok hypr reload config-only
      displays_on=true
    fi
  fi
  if ships_plugin vgs.sound; then
    status=0
    devices_up || status=$?
    if ((status != 0)); then
      fail "the device fakes the Sound shot reads did not start: $devices_state"
    else
      devices_audio_play
      expect "enabling vgs.sound for its shot is allowed" ok ipc shell setPluginEnabled vgs.sound true
      expect "the System window summons on the Sound section" ok ipc shell summon window vgs.system '{"pane":"vgs.sound"}'
      expect_poll "the Sound section is mounted" '["vgs.sound"]' window_panes
      expect_poll "the Sound section lists the test stream" true sound_lists_player
      park_pointer
      take "system-$1-sound"
      expect "disabling vgs.sound while its section is shown is allowed" ok ipc shell setPluginEnabled vgs.sound false
      expect_poll "the window names the Sound section that left" '"Sound is no longer enabled."' ipc smoke readInstance window vgs.system notice
      park_pointer
      take "system-$1-sound-disabled"
      expect "the System window hides after the Sound shot" ok ipc shell hide window vgs.system
      expect_poll "the System window is gone after the Sound shot" hidden system_shown
      kill -- "-$devices_player_pid" 2>/dev/null || true
    fi
  fi
  if ships_plugin vgs.mouse; then
    expect "enabling vgs.mouse for its shot is allowed" ok ipc shell setPluginEnabled vgs.mouse true
    expect "System → Mouse summons" ok ipc shell summon window vgs.system '{"pane":"vgs.mouse"}'
    expect_poll "System → Mouse is shown" '["vgs.mouse"]' window_panes
    park_pointer
    take "system-$1-mouse"
    take_mouse_overridden "$1"
    expect "the System window hides after Mouse" ok ipc shell hide window vgs.system
    expect_poll "the System window is gone after Mouse" hidden system_shown
    expect "disabling vgs.mouse after its shot is allowed" ok ipc shell setPluginEnabled vgs.mouse false
  fi
  if ships_plugin vgs.keyboard; then
    local keyboard_saved="$sandbox/shell-before-keyboard-shot.json"
    cp -- "$home/.config/vgshell/shell.json" "$keyboard_saved"
    python3 - "$home/.config/vgshell/shell.json" <<'PYKEYBOARD'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
rows = doc.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.keyboard"), None)
if row is None:
    row = {"id": "vgs.keyboard"}
    rows.append(row)
row.update(layouts="us,de", variants=",nodeadkeys")
with open(path + ".tmp", "w") as out: json.dump(doc, out)
os.replace(path + ".tmp", path)
PYKEYBOARD
    expect "the keyboard shot configuration reloads" ok ipc shell reloadConfig
    expect "enabling Keyboard for its shot is allowed" ok ipc shell setPluginEnabled vgs.keyboard true
    expect "placing Keyboard for its shot is allowed" ok ipc shell setPluginPlaced vgs.keyboard true
    expect_poll "the keyboard shot has two layouts" '"us,de"' keyboard_shot_layouts
    expect "System Keyboard summons" ok ipc shell summon window vgs.system '{"pane":"vgs.keyboard"}'
    expect_poll "System Keyboard is mounted" '["vgs.keyboard"]' window_panes
    expect_poll "the Keyboard layout catalog is ready" '"ready"' keyboard_shot_catalog
    park_pointer
    take "system-$1-keyboard"
    keyboard_shot_reveal "Key Repeat"
    park_pointer
    take "system-$1-keyboard-repeat"
    keyboard_shot_reveal "Modifier Options"
    # At the scene's default size the pane fits its view, so the Key Repeat
    # reveal already shows Modifier Options and this reveal moves nothing;
    # the shot opens the section's Modifier keys list, a frame the previous
    # shot never drew.
    if keyboard_shot_modifier_list; then
      expect_poll "the Modifier keys list is open for its shot" true keyboard_shot_modifier_open
      take_posed "system-$1-keyboard-modifiers"
      type_keys -k Escape || fail "closing the Modifier keys list failed"
      expect_poll "the Modifier keys list is closed after its shot" false keyboard_shot_modifier_open
    else
      fail "opening the Modifier keys list failed"
    fi
    expect "System hides after the keyboard pane shot" ok ipc shell hide window vgs.system
    expect_poll "System is gone before the keyboard widget shot" hidden system_shown
    park_pointer
    take "system-$1-keyboard-widget"
    keyboard_shot_right_click || fail "opening the Keyboard widget menu failed"
    expect_poll "the Keyboard widget menu is open for its shot" true ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuOpen
    expect "the widget menu includes Keyboard Controls, System settings, Readme and Settings" '["Hide","Keyboard Controls","Keyboard Settings","Readme","Settings"]' ipc smoke readInstance "$(bar_key)" vgs.keyboard frameMenuEntries
    take "system-$1-keyboard-widget-menu"
    type_keys -k Home -k Down -k Return || fail "opening Keyboard Controls from its widget menu failed"
    expect_poll "the widget action opens the typed Keyboard panel" '[["us", ""], ["de", "nodeadkeys"]]' keyboard_shot_panel_sources
    expect "the panel takes source-list focus" '["DeviceRow","English (US)"]' ipc smoke activeFocusItem panel vgs.keyboard
    type_keys -M shift -k F10 -m shift || fail "opening the Keyboard input source menu failed"
    expect_poll "the source menu opens with the Remove entry" True keyboard_shot_source_menu
    take "system-$1-keyboard-panel-menu"
    type_keys -k Escape || fail "closing the Keyboard input source menu failed"
    expect "Keyboard Controls hides after its shot" ok ipc shell hide panel vgs.keyboard
    expect "disabling Keyboard after its shot is allowed" ok ipc shell setPluginEnabled vgs.keyboard false
    cp -- "$keyboard_saved" "$home/.config/vgshell/shell.json.tmp" && mv -T -- "$home/.config/vgshell/shell.json.tmp" "$home/.config/vgshell/shell.json"
    expect "the keyboard shot configuration restores" ok ipc shell reloadConfig
  fi
  if [[ $displays_on == true ]]; then
    expect "disabling vgs.displays after the System shots is allowed" ok ipc shell setPluginEnabled vgs.displays false
    rm -f -- "${home:?}/.local/state/vgshell/plugins/vgs.displays/assignments.json"
  fi
  expect "disabling vgs.system after its shot is allowed" ok ipc shell setPluginEnabled vgs.system false
}
keyboard_shot_right_click() {
  local box x y
  box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.keyboard)" || return 1
  [[ $box == \[* ]] || return 1
  read -r x y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2), int(y+h/2))' "$box") || return 1
  hover "$((x - 1))" "$y" && right_click "$x" "$y"
}
keyboard_shot_modifier_list() {
  local box x y
  box="$(ipc smoke scopedWindowGeometry window vgs.keyboard KeyboardRow "Modifier keys" Select Default)" || return 1
  read -r x y < <(at_centre "window:System Settings" "$box") || return 1
  hover "$((x - 1))" "$y" && click "$x" "$y"
}
keyboard_shot_modifier_open() { ipc smoke readMatchingDescendant window vgs.keyboard Select objectName modifierPicker listOpen; }
keyboard_shot_panel_sources() { ipc smoke readDescendant panel vgs.keyboard KeyboardControls sources | py_reply 'import json,sys; print(json.dumps([[r["code"], r["variant"]] for r in json.load(sys.stdin)]))'; }
keyboard_shot_source_menu() { ipc smoke menus panel vgs.keyboard | py_reply 'import json,sys; menus=json.load(sys.stdin); print(any(m["opened"] and m["entries"] == ["Move down", "Remove"] for m in menus))'; }
keyboard_shot_reveal() {
  local at
  at="$(ipc smoke revealText window vgs.system SectionHeader "$1")" || { fail "the Keyboard section cannot be revealed"; return 1; }
  [[ $at =~ ^[0-9]+([.][0-9]+)?$ ]] || { fail "the Keyboard section has no scroll position: $at"; return 1; }
}
keyboard_shot_layouts() { hypr -j getoption input:kb_layout | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("str")))'; }
keyboard_shot_catalog() { ipc smoke statusValues vgs.keyboard | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin).get("catalog", {}).get("state", "absent")))'; }
sound_lists_player() { ipc smoke itemTexts window vgs.sound FormRow | py_reply 'import json,sys; print(json.dumps(any("Smoke Player" in t for row in json.load(sys.stdin) for t in row)))'; }

# The System window's Bluetooth section over the device fakes: the
# planted adapter, its connected headphones and a nearby keyboard the
# setup adds. The service holds `system`, so the core's step probes run in
# the fakes' system tree (devices_system_tree), never the host's; a setup
# that could not make that tree, start the fakes or read the shell inside
# the sandbox fails the run and enables nothing.
bluetooth_shot_ready=false
scene_bluetooth() { # MODE
  [[ $bluetooth_shot_ready == true ]] || return 0
  expect "enabling vgs.bluetooth for its shot is allowed" ok ipc shell setPluginEnabled vgs.bluetooth true
  expect "enabling vgs.system for the Bluetooth shot is allowed" ok ipc shell setPluginEnabled vgs.system true
  expect "the Bluetooth section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.bluetooth"}'
  expect_poll "the Bluetooth section lists the nearby keyboard" 1 bluetooth_nearby
  park_pointer
  take "bluetooth-$1"
  expect "the System window hides" ok ipc shell hide window vgs.system
  expect_poll "the System window is gone" hidden system_shown
  click_centre "$(bar_key)" vgs.bluetooth || fail "the click on the Bluetooth widget failed"
  expect_poll "the Bluetooth widget opens its dropdown" shown bluetooth_shot_panel
  park_pointer
  take "bluetooth-$1-dropdown"
  expect "the Bluetooth dropdown hides" ok ipc shell hide panel vgs.bluetooth
  expect "disabling vgs.system after the Bluetooth shot is allowed" ok ipc shell setPluginEnabled vgs.system false
  expect "disabling vgs.bluetooth after its shot is allowed" ok ipc shell setPluginEnabled vgs.bluetooth false
}
# The System window's Printers section over the CUPS stand-ins
# (scripts/smoke/fixtures/devices/cups.py): each state is planted in the
# world and announced with CUPS's notification, as rows/printers.sh does.
# The service holds `system`, so the setup makes the fakes' system tree
# first, as the Bluetooth setup does.
printers_shot_ready=false
printers_office='{"name": "Office", "uri": "ipp://office.local/ipp/print", "state": "idle", "message": "", "jobs": 0, "accepting": true}'
printers_lab='{"name": "Lab", "uri": "ipp://lab.local/ipp/print", "state": "idle", "message": "", "jobs": 0, "accepting": true}'
printers_office_busy='{"name": "Office", "uri": "ipp://office.local/ipp/print", "state": "printing", "message": "", "jobs": 2, "accepting": true}'
printers_lab_stopped='{"name": "Lab", "uri": "ipp://lab.local/ipp/print", "state": "stopped", "message": "Paper jam", "jobs": 0, "accepting": true}'
printers_copy="$home/.config/vgshell/plugins/vgs.printers"
printers_cups() { ipc smoke statusValues vgs.printers | py_reply 'import json,sys; v=json.load(sys.stdin).get("printers"); print("unpublished" if v is None else json.dumps(v["cups"]))'; }
printers_watch() { ipc smoke statusValues vgs.printers | py_reply 'import json,sys; v=json.load(sys.stdin).get("printers"); print("unpublished" if v is None else json.dumps(v["watch"]))'; }
printers_count() { ipc smoke readInstance window vgs.printers printers | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
printers_found() { ipc smoke readInstance window vgs.printers foundList | py_reply 'import json,sys; print(len(json.load(sys.stdin)))'; }
printers_state() { ipc smoke readInstance window vgs.printers printers | py_reply 'import json,sys; print(" ".join(p["state"] for p in json.load(sys.stdin)))'; }
# printers_plant LABEL WORLD MEMBER PRINTER: the world's keys of WORLD set,
# then CUPS's notification MEMBER for PRINTER.
printers_plant() {
  expect "$1: the world changes" world=set cups_world "$2"
  expect "$1: CUPS notifies it" signal=sent cups_signal "$3" "$4"
}
scene_printers() { # MODE
  [[ $printers_shot_ready == true ]] || return 0
  expect "the printers world starts empty" world=set cups_world '{"down": false, "printers": [], "default": "", "devices": [], "refuse": false, "quiet": false}'
  rescan "a scan reads the printer helper on the sandbox's bus for the Printers shots"
  expect "enabling vgs.system for the Printers shots is allowed" ok ipc shell setPluginEnabled vgs.system true
  expect "enabling vgs.printers for its shots is allowed" ok ipc shell setPluginEnabled vgs.printers true
  expect "the Printers section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.printers"}'
  expect_poll "the Printers section lists no printer" 0 printers_count
  expect_poll "the Printers watcher is ready for CUPS's notifications" '"ready"' printers_watch
  park_pointer
  take "printers-$1-empty"
  printers_plant "one printer" "{\"printers\": [$printers_office]}" PrinterAdded Office
  expect_poll "the Printers section lists one printer" 1 printers_count
  take "printers-$1-one"
  printers_plant "two printers" "{\"printers\": [$printers_office, $printers_lab], \"default\": \"Lab\"}" PrinterAdded Lab
  expect_poll "the Printers section lists two printers" 2 printers_count
  take "printers-$1-two"
  printers_plant "a busy printer" "{\"printers\": [$printers_office_busy, $printers_lab]}" JobCreated Office
  expect_poll "Office reads busy" "idle printing" printers_state
  take "printers-$1-busy"
  printers_plant "a stopped printer" "{\"printers\": [$printers_office, $printers_lab_stopped]}" PrinterStateChanged Lab
  expect_poll "Lab reads stopped" "stopped idle" printers_state
  take "printers-$1-error"
  printers_plant "printers ready again" "{\"printers\": [$printers_office, $printers_lab], \"devices\": [{\"class\": \"network\", \"info\": \"Hall Printer\", \"make\": \"HP LaserJet\", \"uri\": \"ipp://hall.local:631/ipp/print\"}, {\"class\": \"direct\", \"info\": \"Brother HL-L2350DW\", \"make\": \"Brother HL-L2350DW\", \"uri\": \"usb://Brother/HL-L2350DW?serial=E7\"}]}" PrinterStateChanged Lab
  expect "Find printers answers ok" ok ipc smoke invokeInstanceArgs window vgs.printers find '{"args": []}'
  expect_poll "the Printers section lists the found devices" 2 printers_found
  expect "an address of another scheme is refused" "refused: address=scheme" ipc smoke invokeInstanceArgs window vgs.printers addAddress '{"args": ["lpd://hall.local/queue"]}'
  take "printers-$1-add"
  expect "the System window hides after the Printers shots" ok ipc shell hide window vgs.system
  expect_poll "the System window is gone after the Printers shots" hidden system_shown
  expect "disabling vgs.printers after its shots is allowed" ok ipc shell setPluginEnabled vgs.printers false
  # Printing not installed: the copy whose lpstat no PATH holds.
  rm -rf -- "${printers_copy:?}"
  expect "the not-installed Printers copy is written" copy=written cups_uninstalled_copy "$printers_copy"
  rescan "a scan reads the not-installed Printers copy"
  expect "enabling the not-installed Printers copy is allowed" ok ipc shell setPluginEnabled vgs.printers true
  expect "the not-installed Printers section summons" ok ipc shell summon window vgs.system '{"pane":"vgs.printers"}'
  expect_poll "the not-installed Printers section reads printing not installed" '"missing"' printers_cups
  park_pointer
  take "printers-$1-uninstalled"
  expect "the System window hides after the not-installed shot" ok ipc shell hide window vgs.system
  expect_poll "the System window is gone after the not-installed shot" hidden system_shown
  expect "disabling the not-installed Printers copy is allowed" ok ipc shell setPluginEnabled vgs.printers false
  rm -rf -- "${printers_copy:?}"
  rescan "a scan drops the not-installed Printers copy"
  expect "disabling vgs.system after the Printers shots is allowed" ok ipc shell setPluginEnabled vgs.system false
  expect "the printers world is empty again" world=set cups_world '{"printers": [], "default": "", "devices": []}'
}
bluetooth_shot_panel() { [[ $(ipc smoke instanceGeometry panel vgs.bluetooth) != absent ]] && echo shown || echo hidden; }
# The rows the section's Nearby list draws for the keyboard the setup adds.
bluetooth_nearby() { ipc smoke itemTexts window vgs.bluetooth Section | py_reply 'import json,sys; print(sum(t.count("Desk Keyboard") for t in json.load(sys.stdin) if t[:1] == ["Nearby"]))'; }

scene_power() { # MODE
  devices_ready power-shot || return 0
  power_start_mocks shots-power balanced
  tree_rescan "the Power shots' fake daemon is scanned"
  expect "the power shot starts with a discharging battery object" "/org/freedesktop/UPower/devices/mock_BAT0" power_add_battery 64.0 7200
  power_discharging 64.0 7200
  expect "Power enables for its shot" ok ipc shell setPluginEnabled vgs.power true
  expect "Power's requirement notice is absent" null notice_shown
  expect "Power's widget is placed for its shot" ok ipc shell setPluginPlaced vgs.power true
  expect_poll "Power's service reads the fake battery" 64 power_shot_level
  park_pointer
  take "power-$1-bar"
  click_centre "$(bar_key)" vgs.power || fail "opening Power from its widget failed"
  expect_poll "Power opens its panel" shown power_shot_panel
  park_pointer
  take "power-$1-panel"
  expect "Power's panel hides" ok ipc shell hide panel vgs.power
  notes_on "Power notice shots"
  power_discharging 19.0 1800
  expect_poll "Power sends its low battery notice" 1 notes_on_screen
  take "power-$1-notice-low"
  notes_clear "Power low notice shot"
  power_discharging 9.0 600
  expect_poll "Power sends its critical battery notice" 1 notes_on_screen
  take "power-$1-notice-critical"
  notes_off "Power notice shots"
  power_no_battery
  expect_poll "Power's service reads no battery" False power_shot_battery
  click_centre "$(bar_key)" vgs.power || fail "opening Power with no battery failed"
  expect_poll "Power opens its panel with no battery" shown power_shot_panel
  park_pointer
  take "power-$1-panel-no-battery"
  expect "Power's panel with no battery hides" ok ipc shell hide panel vgs.power
  power_discharging 64.0 7200
  expect_poll "Power's service reads the battery again" 64 power_shot_level
  expect "Power's widget is unplaced after its shot" ok ipc shell setPluginPlaced vgs.power false
  expect "Power disables after its shot" ok ipc shell setPluginEnabled vgs.power false
  power_stop_mocks
}
power_shot_panel() { [[ $(ipc smoke instanceGeometry panel vgs.power) != absent ]] && echo shown || echo hidden; }
power_shot_level() { ipc smoke statusValues vgs.power | py_reply 'import json,sys; print(json.load(sys.stdin)["power"]["battery"]["level"])'; }
power_shot_battery() { ipc smoke statusValues vgs.power | py_reply 'import json,sys; print(json.load(sys.stdin)["power"]["battery"]["present"])'; }

# The core's requirement notice, raised by enabling the acme.needs
# fixture, which misses a command it needs; Escape closes it, and the
# fixture is disabled again so the next mode raises it anew.
notice_plugin() { notice_shown | py_reply 'import json,sys; s=json.load(sys.stdin); print(json.dumps(s[0] if s else None))'; }
notice_drawn_key() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"; }
notice_message_hold() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(str(sys.argv[1] in json.load(sys.stdin)["message"]).lower())' "$1"; }
notice_rows_hold() { ipc smoke noticeDrawn | py_reply 'import json,sys; print(str(any(sys.argv[1] in row for row in json.load(sys.stdin)["rows"])).lower())' "$1"; }
shot_reset_ask() { "${shell_env[@]}" "$tree/bin/vgshell" reset </dev/null; }
# notice_moved_from PLUGIN: `closed` once the shown notice is no longer
# PLUGIN's, JSON-quoted as notice_plugin prints it.
notice_moved_from() { local now; now="$(notice_plugin)" || return 1; if [[ $now != "$1" ]]; then echo closed; else echo "$now"; fi; }
# close_notices: every requirement notice the scene's enabling raised
# closed in queue order. The published queue supplies the count. The notices show one at a
# time; Escape closes the shown one once its layer maps and its dialog
# holds the keyboard, and the next then shows.
close_notices() {
  local shown count i
  count="$(ipc shell lent | py_reply 'import json,sys; n=json.load(sys.stdin)["notices"]; print(len(n["waiting"])+(n["shown"] is not None))')" || { fail "the requirement notice queue is unreadable"; return; }
  [[ $count =~ ^[0-9]+$ ]] || { fail "the requirement notice count is $count"; return; }
  for ((i=0; i<count; i++)); do
    shown="$(notice_plugin)" || shown=unread
    [[ $shown == null ]] && break
    expect_poll "the requirement notice of $shown maps" 1 layer_count vgs:notice
    expect_poll "the requirement notice of $shown holds the keyboard" true ipc smoke noticeFocused
    type_keys -k Escape || fail "sending Escape to the requirement notice of $shown failed"
    expect_poll "Escape closes the requirement notice of $shown" closed notice_moved_from "$shown"
  done
  expect_poll "Escape closed every requirement notice" null notice_shown
  expect_poll "the requirement notice layer is gone" 0 layer_count vgs:notice
}
# Initial focus and the title block on a Settings dialog, an anchored
# Network panel and the join form. Posed shots preserve the keyboard ring
# before and after Tab, including when --rev reads the old focus policy.
scene_focus-open() { # MODE
  expect "Settings opens for the title and focus comparison" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "Settings maps for the comparison" 1 settings_count
  expect "the comparison opens its fixture page" ok ipc smoke invokeInstance "$settings_kind" vgs.settings openPlugin acme.probe
  expect_poll "the comparison fixture page is shown" '"acme.probe"' settings_page
  local edit_box
  edit_box="$(ipc smoke invokeInstance "$settings_kind" vgs.settings holdField '{"id":"acme.probe","key":"gap","text":"12"}')" || edit_box="unread"
  [[ $edit_box == \[* ]] || fail "the comparison Gap field took no edit: $edit_box"
  expect "Back raises the comparison dialog" "refused: unsaved=acme.probe" ipc smoke invokeInstance "$settings_kind" vgs.settings back ''
  expect_poll "the comparison dialog is shown" True focus_open_settings_dialog
  park_pointer
  take_posed "focus-open-$1-settings-dialog-opened"
  type_keys -k Tab || fail "Tab in the Settings comparison dialog failed"
  park_pointer
  take_posed "focus-open-$1-settings-dialog-tab"
  ipc smoke invokeInstance "$settings_kind" vgs.settings answer discard >/dev/null || fail "the comparison dialog could not discard its synthetic edit"
  settings_close

  devices_ready focus-open-shot || return 0
  device_reply systemctl 0 $'LoadState=loaded\nActiveState=active' show --property=LoadState --property=ActiveState NetworkManager.service
  device_reply nmcli 0 'org.freedesktop.NetworkManager.network-control:yes' -t -f PERMISSION,VALUE general permissions
  expect "the comparison prepares fake Wi-Fi" ok python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" prepare
  expect "Network enables for the comparison" ok ipc shell setPluginEnabled vgs.network true
  expect "Network refreshes its comparison replies" ok ipc vgs.network invoke refresh ''
  expect_poll "Network has comparison permission" '"allowed"' ipc smoke readInstance service vgs.network access
  expect_poll "Network has its comparison service" '"running"' ipc smoke readInstance service vgs.network serviceState
  expect "System enables for the comparison" ok ipc shell setPluginEnabled vgs.system true
  expect "Network is placed for the anchored comparison" ok ipc shell setPluginPlaced vgs.network true
  expect_poll "the network widget is built for the comparison" True record_exists vgs.network
  click_centre "$(bar_key)" vgs.network || fail "the comparison network widget did not open its panel"
  expect_poll "the comparison network panel is shown" shown network_shot_panel
  park_pointer
  take_posed "focus-open-$1-network-panel-opened"
  type_keys -k Tab || fail "Tab in the network comparison panel failed"
  park_pointer
  take_posed "focus-open-$1-network-panel-tab"
  expect "the comparison network panel closes" ok ipc shell hide panel vgs.network

  expect "the comparison opens Network in System" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
  expect_poll "the comparison Network pane mounts" shown network_shot_shown
  expect_poll "the comparison Network pane reads the saved mock" '[["VGS Smoke Wi-Fi", "Wpa2Psk", true]]' network_shot_names
  expect "the comparison reveals Other Network" scrolled network_shot_other_reveal
  click_in 'window:System Settings' window vgs.network Button 'Other Network…' || fail "the comparison Other Network form did not open"
  expect_poll "the comparison join input owns focus" true ipc smoke activeFocusWithin window vgs.network NetworkJoin
  park_pointer
  take_posed "focus-open-$1-network-join-opened"
  type_keys -k Tab || fail "Tab in the network join comparison failed"
  park_pointer
  take_posed "focus-open-$1-network-join-tab"
  expect "the comparison System window closes" ok ipc shell hide window vgs.system
  expect "the comparison forgets its saved fake profile" ok ipc vgs.network invoke action '{"kind":"forget","key":"[\"wlan0\",\"VGS Smoke Wi-Fi\"]"}'
  expect_poll "the comparison releases its saved fake profile" False network_shot_known
  expect "Network disables after the comparison" ok ipc shell setPluginEnabled vgs.network false
  expect "System disables after the comparison" ok ipc shell setPluginEnabled vgs.system false
  device_reply_clear nmcli
  device_reply_clear systemctl
}
focus_open_settings_dialog() { ipc smoke dialogCard "$settings_kind" vgs.settings | py_reply 'import json,sys; print(json.load(sys.stdin)["shown"])'; }

# Network reads S08's mock and command stand-ins. Its pane is a real
# System section, so this shot includes the holder's sidebar and inset.
# The Appearance group of the System window: Motion, Windows, UI and, where
# the tree ships it, Fonts,
# appearance-<mode>-<section>, each enabled for its shot and Set by theme,
# then Windows with a user corner radius of 12 in shell.json,
# appearance-<mode>-windows-radius, which reaches the window itself and
# its flyout radius. Each section is disabled again, and the user file goes
# back as the scene found it.
appearance_radius() { ipc smoke themeValue popover.radius; }
scene_appearance() { # MODE
  local user="$home/.config/vgshell/shell.json" saved="$sandbox/shell-before-appearance-shot.json" id
  expect "enabling vgs.system for the Appearance shots is allowed" ok ipc shell setPluginEnabled vgs.system true
  for id in vgs.motion vgs.windows vgs.ui vgs.fonts; do
    ships_plugin "$id" || continue
    expect "enabling $id for its shot is allowed" ok ipc shell setPluginEnabled "$id" true
    expect "System → $id summons" ok ipc shell summon window vgs.system "{\"pane\":\"$id\"}"
    expect_poll "System → $id is shown" "[\"$id\"]" window_panes
    expect "the System window's root takes the focus for $id" focused ipc smoke invokeInstance window vgs.system focusInstance ""
    park_pointer
    take "appearance-$1-${id#vgs.}"
  done
  cp -- "$user" "$saved"
  python3 - "$user" <<'PY' || fail "the user file took no corner radius"
import json, os, sys
path = sys.argv[1]
config = json.load(open(path))
config.setdefault("appearance", {})["windowRadius"] = 12
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PY
  expect "the configuration reloads with a corner radius" ok ipc shell reloadConfig
  expect_poll "the flyout radius follows the corner radius, 12 * 0.75" 9 appearance_radius
  expect "System → Windows summons with the corner radius" ok ipc shell summon window vgs.system '{"pane":"vgs.windows"}'
  expect_poll "System → Windows is shown with the corner radius" '["vgs.windows"]' window_panes
  expect "the System window's root takes the focus for the corner radius" focused ipc smoke invokeInstance window vgs.system focusInstance ""
  park_pointer
  take "appearance-$1-windows-radius"
  cp -- "$saved" "$user.next" && mv -T -- "$user.next" "$user" || fail "the user file is put back after the Appearance shots"
  expect "the configuration reloads as the Appearance shots found it" ok ipc shell reloadConfig
  expect "the System window hides after the Appearance shots" ok ipc shell hide window vgs.system
  expect_poll "the System window is gone after the Appearance shots" hidden system_shown
  for id in vgs.motion vgs.windows vgs.ui vgs.fonts; do
    ships_plugin "$id" || continue
    expect "disabling $id after its shot is allowed" ok ipc shell setPluginEnabled "$id" false
  done
}

# The Sounds section of the System window over the sound events of
# Notifications, Voice and Jarvis, each enabled for the shots, Jarvis once
# its daemon answers: sounds-<mode>-list, every event with the sound it
# plays; sounds-<mode>-picker, the New notification picker's list open on
# Off and the core's sounds; and sounds-<mode>-off, Jarvis's tones turned
# off and the notification set to Chime in shell.json; and
# sounds-<mode>-voxtype-missing, the Dictation sounds row's line once the
# stand-in is gone, which names the Voice page. Voice reads its
# dictation sounds from a voxtype stand-in that answers the value alone,
# tones on; no shot chooses a dictation value, so nothing is written and
# no service restarts. The player is the harness's pw-play stand-in and no
# shot presses Test, so nothing sounds. The other Appearance sections the
# tree ships are enabled too, so the sidebar holds the whole group whatever
# an earlier scene left disabled. Jarvis is disabled again, the stand-in is
# removed, and the user file, with every other enablement, goes back as
# the scene found it.
sounds_row() { ipc smoke readMatchingDescendant window vgs.sounds FormRow label "$1" "$2"; }
sounds_picker_open() { ipc smoke readMatchingDescendant window vgs.sounds Select currentText "$1" listOpen; }
scene_sounds() { # MODE
  local user="$home/.config/vgshell/shell.json" saved="$sandbox/shell-before-sounds-shot.json" id box px py voice_found
  voice_found="$(plugin_enabled vgs.voice)" || voice_found=unread
  cp -- "$user" "$saved"
  if voice_dictates; then
    voice_stand_ins
  else
    cat >"$shim/voxtype" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  'status --follow --extended --format json') printf '{"state":"idle"}\n'; exec sleep infinity ;;
  'config get audio.feedback.enabled --json') printf '{"file_value":true,"key":"audio.feedback.enabled","value":true}\n' ;;
esac
EOF
    chmod 755 "$shim/voxtype"
  fi
  rescan "the Sounds shots' voxtype stand-in is scanned"
  for id in vgs.system vgs.motion vgs.windows vgs.ui vgs.fonts vgs.sounds vgs.notifications vgs.voice vgs.jarvis; do
    ships_plugin "$id" || continue
    expect "enabling $id for the Sounds shots is allowed" ok ipc shell setPluginEnabled "$id" true
  done
  expect_poll "the Jarvis daemon answers hello before the Sounds shots" ready jarvis_started
  # Jarvis requires wlrctl, which the shell finds absent, so enabling it
  # raises its requirement notice, which closes before the shots.
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
  expect "System → Sounds summons" ok ipc shell summon window vgs.system '{"pane":"vgs.sounds"}'
  expect_poll "System → Sounds is shown" '["vgs.sounds"]' window_panes
  expect_poll "the section lists Jarvis's own sound" 1 sounds_row "Feedback sounds" chosen
  expect_poll "the section lists the notification sound, off" 0 sounds_row "New notification" chosen
  expect_poll "the section lists voxtype's dictation tones" 1 sounds_row "Dictation sounds" chosen
  expect "the System window's root takes the focus for the Sounds list" focused ipc smoke invokeInstance window vgs.system focusInstance ""
  take "sounds-$1-list"
  box="$(ipc smoke scopedWindowGeometry window vgs.sounds FormRow "New notification" Select Off)" || box=""
  if read -r px py < <(at_centre "window:System Settings" "$box"); then
    hover "$px" "$py" || fail "hovering the New notification picker failed"
    click "$px" "$py" || fail "clicking the New notification picker failed"
    expect_poll "the New notification picker's list is open" true sounds_picker_open Off
    take_posed "sounds-$1-picker"
    type_keys -k Escape || fail "Escape on the open picker failed"
    expect_poll "the New notification picker's list is closed" false sounds_picker_open Off
  else
    fail "the New notification picker has no box: $box"
  fi
  python3 - "$user" <<'PY' || fail "the user file took no sound choice"
import json, os, sys
path = sys.argv[1]
config = json.load(open(path))
config.setdefault("sounds", {}).setdefault("vgs.jarvis", {})["feedback"] = ""
config["sounds"].setdefault("vgs.notifications", {})["notification"] = "chime"
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PY
  expect "the configuration reloads with Jarvis's tones off" ok ipc shell reloadConfig
  expect_poll "the Feedback sounds row shows Off" 0 sounds_row "Feedback sounds" chosen
  expect_poll "the New notification row shows Chime" 1 sounds_row "New notification" chosen
  expect "the System window's root takes the focus for the off event" focused ipc smoke invokeInstance window vgs.system focusInstance ""
  take "sounds-$1-off"
  voice_stand_ins_removed
  rescan "the Sounds shots' voxtype stand-in is removed for the missing line"
  close_notices
  expect_poll "the Dictation sounds row states voxtype missing in the warning tone" '"warning"' sounds_row "Dictation sounds" warningTone
  expect "the System window's root takes the focus for the missing line" focused ipc smoke invokeInstance window vgs.system focusInstance ""
  take "sounds-$1-voxtype-missing"
  expect "the System window hides after the Sounds shots" ok ipc shell hide window vgs.system
  expect_poll "the System window is gone after the Sounds shots" hidden system_shown
  expect "disabling vgs.jarvis after the Sounds shots is allowed" ok ipc shell setPluginEnabled vgs.jarvis false
  expect_poll "vgs.jarvis is gone after the Sounds shots" absent ipc smoke jarvisProcess
  cp -- "$saved" "$user.next" && mv -T -- "$user.next" "$user" || fail "the user file is put back after the Sounds shots"
  expect "the configuration reloads as the Sounds shots found it" ok ipc shell reloadConfig
  expect_poll "Voice's enablement is as the Sounds shots found it" "$voice_found" plugin_enabled vgs.voice
  voice_stand_ins_removed
  rescan "the Sounds shots' voxtype stand-in is removed"
}

scene_network() { # MODE
  devices_ready network-shot || return 0
  device_reply systemctl 0 $'LoadState=loaded\nActiveState=active' show --property=LoadState --property=ActiveState NetworkManager.service
  device_reply nmcli 0 'org.freedesktop.NetworkManager.network-control:yes' -t -f PERMISSION,VALUE general permissions
  expect "the network shot has a saved fake profile" ok python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" prepare
  expect "the network shot has two wired fake devices" ok python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" wired
  device_reply nmcli 0 $'GENERAL.DEVICE:enp10s0\nGENERAL.TYPE:ethernet\nGENERAL.STATE:100 (connected)\nIP4.ADDRESS[1]:192.0.2.10/24\nIP4.GATEWAY:192.0.2.1' -t device show enp10s0
  expect "Network enables for its shot" ok ipc shell setPluginEnabled vgs.network true
  expect "System enables for the network shot" ok ipc shell setPluginEnabled vgs.system true
  expect "Network's pane summons" ok ipc shell summon window vgs.system '{"pane":"vgs.network"}'
  expect_poll "Network's pane is mounted" shown network_shot_shown
  expect_poll "Network's pane reads the saved mock" '[["VGS Smoke Wi-Fi", "Wpa2Psk", true]]' network_shot_names
  park_pointer
  take "network-$1-pane"
  expect "Other Network is revealed for its form shot" scrolled network_shot_other_reveal
  click_in 'window:System Settings' window vgs.network Button 'Other Network…' || fail "Other Network did not open for its shot"
  expect_poll "the hidden PSK form takes focus" true ipc smoke activeFocusWithin window vgs.network NetworkJoin
  type_keys 'Hidden office Wi-Fi'
  type_keys -k Tab
  type_keys -k Tab
  type_keys 'network-shot-synthetic-password'
  park_pointer
  take_posed "network-$1-other-psk"
  # Click the existing shared Select; Down chooses Enterprise without a popup.
  click_in 'window:System Settings' window vgs.network Select 'WPA/WPA2 Personal' || fail "the security choice did not open"
  type_keys -k Down -k Return
  expect_poll "the enterprise form is selected" true ipc smoke readDescendant window vgs.network NetworkJoin enterprise
  click_in 'window:System Settings' window vgs.network Select 'PEAP / MSCHAPv2' || fail "the enterprise method choice did not open"
  type_keys -k Down -k Return
  expect "the enterprise shot chooses TTLS" 1 ipc smoke readMatchingDescendant window vgs.network Select objectName network-join-method currentIndex
  type_keys -k Tab
  type_keys 'office.user'
  type_keys -k Tab
  type_keys 'auth.example.com'
  type_keys -k Tab
  type_keys 'network-shot-synthetic-password'
  park_pointer
  take_posed "network-$1-other-enterprise"
  expect "Cancel is revealed after the enterprise shot" scrolled network_shot_cancel_reveal
  click_in 'window:System Settings' window vgs.network Button Cancel || fail "the form did not close after its shot"
  expect_poll "the Other Network shot releases its form" absent ipc smoke readDescendant window vgs.network NetworkJoin result
  expect "enp10s0 scrolls into view" scrolled network_shot_reveal
  click_in "window:System Settings" window vgs.network ListItem enp10s0 || fail "the click on enp10s0 failed"
  expect_poll "enp10s0's details draw" True network_shot_details
  park_pointer
  take "network-$1-pane-details"
  expect "the network System window closes" ok ipc shell hide window vgs.system
  click_centre "$(bar_key)" vgs.network || fail "the click on the network widget failed"
  expect_poll "the network widget opens its panel" shown network_shot_panel
  park_pointer
  take "network-$1-dropdown"
  # The saved profile's activation fails on its password, so the service
  # prompts, as the network row's net_reprompt drives it. A tree from
  # before the prompt's Dialog draws the password field in the list.
  expect "the network shot starts the saved profile" ok ipc vgs.network invoke action '{"kind":"connect","key":"[\"wlan0\",\"VGS Smoke Wi-Fi\"]"}'
  expect_poll "the network shot's activation is pending" connect network_shot_action
  expect "the network shot's mock refuses the saved password" ok python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" fail
  expect_poll "the network shot's service prompts" True network_shot_prompt
  expect "the network shot's failed activation is removed" ok python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" drop-active
  if tree_has shell/plugins/vgs.network/NetworkBody.qml 'objectName: "network-prompt"'; then
    expect_poll "the password dialog shows in the dropdown" true ipc smoke readMatchingDescendant panel vgs.network Dialog objectName network-prompt visible
    expect_poll "the password dialog focuses its empty masked field" '{"masked":true,"length":0,"focused":true}' ipc smoke networkField panel
  else
    expect_poll "the password field shows in the dropdown's list" true ipc smoke readMatchingDescendant panel vgs.network TextField objectName network-password visible
  fi
  park_pointer
  take_posed "network-$1-dropdown-password"
  expect "the network shot cancels its prompt" ok ipc vgs.network invoke action '{"kind":"cancel"}'
  expect_poll "the network shot's prompt ends" False network_shot_prompt
  expect "the network panel hides" ok ipc shell hide panel vgs.network
  expect "the network shot forgets its saved fake profile" ok ipc vgs.network invoke action '{"kind":"forget","key":"[\"wlan0\",\"VGS Smoke Wi-Fi\"]"}'
  expect_poll "the network shot releases its saved fake profile" False network_shot_known
  expect "the network shot removes its wired fake devices" ok python3 "$repo/scripts/smoke/fixtures/devices/network.py" "unix:path=$rt_dir/system-bus" unwired
  expect "Network disables after its shot" ok ipc shell setPluginEnabled vgs.network false
  expect "System disables after the network shot" ok ipc shell setPluginEnabled vgs.system false
  device_reply_clear nmcli
  device_reply_clear systemctl
}
# VPN reads a running Tailscale tailnet and saved NetworkManager profiles
# from the device stand-ins. The core's system tree holds no tailscale,
# so the operator step reads absent and no setup step shows.
scene_vpn() { # MODE
  devices_ready vpn-shot || return 0
  device_reply nmcli 0 $'Home tunnel:wireguard:activated\nOffice VPN:vpn:deactivated' -t -f NAME,TYPE,STATE connection show
  device_reply tailscale 0 "$(<"$repo/scripts/fixtures/vpn/mullvad.json")" status --json
  device_reply tailscale 0 "$(<"$repo/scripts/fixtures/vpn/accounts.txt")" switch --list
  expect "VPN enables for its shot" ok ipc shell setPluginEnabled vgs.vpn true
  expect "System enables for the VPN shot" ok ipc shell setPluginEnabled vgs.system true
  expect "VPN's pane summons" ok ipc shell summon window vgs.system '{"pane":"vgs.vpn"}'
  expect_poll "VPN's pane is mounted" shown vpn_shot_shown
  expect_poll "VPN's pane reads the stand-in's tailnet" '["running", 2]' vpn_shot_read
  expect_poll "VPN's pane lists the saved profile stand-ins" '[["Home tunnel", "wireguard", true], ["Office VPN", "vpn", false]]' vpn_shot_profiles window
  expect "the saved VPN profiles scroll into the pane" scrolled vpn_shot_reveal window vgs.system
  park_pointer
  take "vpn-$1-pane"
  expect "the VPN System window closes" ok ipc shell hide window vgs.system
  click_centre "$(bar_key)" vgs.vpn || fail "the click on the VPN widget failed"
  expect_poll "the VPN widget opens its dropdown" shown vpn_shot_panel
  expect_poll "VPN's dropdown lists the saved profile stand-ins" '[["Home tunnel", "wireguard", true], ["Office VPN", "vpn", false]]' vpn_shot_profiles panel
  expect "the saved VPN profiles scroll into the dropdown" scrolled vpn_shot_reveal panel vgs.vpn
  park_pointer
  take "vpn-$1-dropdown"
  expect "the VPN dropdown hides" ok ipc shell hide panel vgs.vpn
  expect "VPN disables after its shot" ok ipc shell setPluginEnabled vgs.vpn false
  expect "System disables after the VPN shot" ok ipc shell setPluginEnabled vgs.system false
  device_reply_clear tailscale
  device_reply_clear nmcli
}
vpn_shot_panel() { [[ $(ipc smoke instanceGeometry panel vgs.vpn) != absent ]] && echo shown || echo hidden; }
vpn_shot_shown() { [[ $(ipc smoke instanceGeometry window vgs.vpn) != absent ]] && echo shown || echo hidden; }
vpn_shot_read() { ipc smoke readDescendant window vgs.vpn VpnBody vpn | py_reply 'import json,sys; v=json.load(sys.stdin); print(json.dumps([v["state"], len(v["accounts"])]))'; }
vpn_shot_profiles() { ipc smoke readDescendant "$1" vgs.vpn VpnBody profileRows | py_reply 'import json,sys; print(json.dumps([[r["name"],r["type"],r["active"]] for r in json.load(sys.stdin)]))'; }
vpn_shot_reveal() { ipc smoke revealText "$1" "$2" SectionHeader "VPN profiles" | py_reply 'import sys; s=sys.stdin.read().strip(); print("scrolled" if s.replace(".", "", 1).isdigit() else s)'; }
# The VPN flyout while Tailscale's access step is offered: no operator, so
# the core's tailscale-operator step reads needed through the stand-in
# linked into the fakes' system tree, as rows/vpn.sh links it. A tree whose
# flyout hands its header switch the unlock step (Panel.qml's
# switchUnlock) is held to the reason's tooltip and the mark's focus; an
# older tree, whose switch and Sign in are plainly disabled, takes the
# same shots in the same poses and logs what it reads instead.
scene_vpn-locked() { # MODE
  local locked=false link="$devices_system_root/usr/bin/tailscale"
  tree_has shell/plugins/vgs.vpn/Panel.qml switchUnlock && locked=true
  devices_ready vpn-locked-shot || return 0
  device_reply nmcli 0 "" -t -f NAME,TYPE,STATE connection show
  device_reply tailscale 0 "$(<"$repo/scripts/fixtures/vpn/mullvad.json")" status --json
  device_reply tailscale 0 "$(<"$repo/scripts/fixtures/vpn/accounts.txt")" switch --list
  device_reply tailscale 0 "" get operator
  device_reply systemctl 0 "" is-active --quiet tailscaled.service
  expect "the core's system steps resolve in the fakes' tree for the locked VPN shot" prefixed devices_system_tree
  ln -sfn -- "$shim/tailscale" "$link"
  expect "VPN enables for its locked shot" ok ipc shell setPluginEnabled vgs.vpn true
  expect_poll "VPN's widget is built for its locked shot" True record_exists vgs.vpn
  tree_rescan "a scan probes Tailscale's access step for the locked VPN shot"
  expect_poll "an unset operator offers Allow for the locked VPN shot" allow vpn_locked_setup
  click_centre "$(bar_key)" vgs.vpn || fail "the click on the VPN widget failed for its locked shot"
  expect_poll "the VPN widget opens its locked dropdown" shown vpn_shot_panel
  expect_poll "the locked dropdown reads the running tailnet" '"running"' vpn_locked_state
  take "vpn-locked-$1-flyout"

  if vpn_locked_hover "the pointer rests on the locked header switch" Switch ""; then
    vpn_locked_wait "$locked" "the pointer opens the switch's reason" open vpn_locked_tip
    take_posed "vpn-locked-$1-switch-hover"
  fi

  park_pointer
  if vpn_locked_tab_to '["Switch",""]'; then
    vpn_locked_wait "$locked" "Tab reaches the locked header switch" '["Switch",""]' ipc smoke activeFocusItem panel vgs.vpn
    vpn_locked_wait "$locked" "keyboard focus opens the switch's reason" open vpn_locked_tip
    take_posed "vpn-locked-$1-switch-focus"
    if type_keys -k Tab; then
      vpn_locked_wait "$locked" "Tab reaches the switch's unlock mark" '["IconButton","Let my login control Tailscale"]' ipc smoke activeFocusItem panel vgs.vpn
      take_posed "vpn-locked-$1-mark-focus"
    else
      fail "Tab from the locked header switch failed"
    fi
  fi

  expect "the locked dropdown hides before sign-in" ok ipc shell hide panel vgs.vpn
  device_reply tailscale 0 "$(<"$repo/scripts/fixtures/vpn/logged-out.json")" status --json
  expect "VPN refreshes over the signed-out stand-in" ok ipc vgs.vpn invoke refresh ""
  expect_poll "VPN publishes the signed-out tailnet" '"signed-out"' vpn_locked_published
  click_centre "$(bar_key)" vgs.vpn || fail "the click on the VPN widget failed for its locked sign-in shot"
  expect_poll "the VPN widget opens its signed-out dropdown" shown vpn_shot_panel
  expect_poll "the locked dropdown reads the signed-out tailnet" '"signed-out"' vpn_locked_state
  if vpn_locked_hover "the pointer rests on the locked Sign in" Button vpn-sign-in; then
    vpn_locked_wait "$locked" "the pointer opens Sign in's reason" open vpn_locked_tip
    take_posed "vpn-locked-$1-sign-in-hover"
  fi

  park_pointer
  expect "the signed-out dropdown hides" ok ipc shell hide panel vgs.vpn
  expect "VPN disables after its locked shot" ok ipc shell setPluginEnabled vgs.vpn false
  rm -f -- "$link"
  device_reply_clear tailscale
  device_reply_clear nmcli
  device_reply_clear systemctl
  tree_rescan "a scan finds no Tailscale after the locked VPN shot"
}
vpn_locked_setup() { ipc smoke statusValues vgs.vpn | py_reply 'import json,sys; v=json.load(sys.stdin).get("setup"); print("unpublished" if v is None else v.get("action", "none"))'; }
vpn_locked_published() { ipc smoke statusValues vgs.vpn | py_reply 'import json,sys; v=json.load(sys.stdin).get("vpn"); print("unpublished" if v is None else json.dumps(v["state"]))'; }
vpn_locked_state() { ipc smoke readDescendant panel vgs.vpn VpnBody vpn | py_reply 'import json,sys; print(json.dumps(json.load(sys.stdin)["state"]))'; }
vpn_locked_tip() { [[ $(shot_chrome_read) == *tooltip* ]] && echo open || echo closed; }
# vpn_locked_point TYPE NAME: `X Y`, where the pointer rests on the first
# shown TYPE under the VPN flyout whose objectName is NAME, enabled or not:
# itemGeometry finds enabled controls alone, and an older tree disables
# these. A Switch is pointed on its track, the Rectangle child that
# leaves out the unlock mark the switch is wider by; another item on its
# centre. descendantGeometry's boxes are mapToGlobal's, the frame
# itemGeometry hands point_item for a panel item, so they are layout
# positions; `absent` without such an item.
vpn_locked_point() { # TYPE NAME
  ipc smoke descendantGeometry panel vgs.vpn | py_reply '
import json, sys
items, (kind, name) = json.load(sys.stdin), sys.argv[1:]
at = next((i for i, item in enumerate(items) if item["type"] == kind and item.get("name", "") == name and item["visible"]), None)
box = None if at is None else items[at]["box"]
if box is not None and kind == "Switch":
    box = next((item["box"] for item in items if item["parent"] == at and item["type"].endswith("Rectangle")), None)
print("absent" if box is None else "%d %d" % (box[0] + box[2] / 2, box[1] + box[3] / 2))' "$1" "$2"
}
# vpn_locked_hover LABEL TYPE NAME: the pointer on vpn_locked_point's
# point by two motions, without reading a hover state, which a plainly
# disabled control never reports.
vpn_locked_hover() { # LABEL TYPE NAME
  local at x y
  settle_hold || { fail "$1: the held mode could not be taken again"; return 1; }
  at="$(vpn_locked_point "$2" "$3")" || at=unreadable
  [[ $at =~ ^[0-9]+\ [0-9]+$ ]] || { fail "$1: no shown $2 \"$3\" in the VPN flyout: $at"; return 1; }
  read -r x y <<<"$at"
  if hover "$((x - 6))" "$y" && hover "$x" "$y"; then ok "$1"; else fail "$1: the hover failed"; return 1; fi
}
# vpn_locked_tab_to WANT: Tab, up to 8 presses, until the flyout's focused
# item reads WANT; each press waits up to 1 s for the reading to move, so
# a reading taken before the key landed never adds a press. An older
# tree's disabled switch takes no focus, so this ends at the bound there.
vpn_locked_tab_to() { # WANT
  local at before
  at="$(ipc smoke activeFocusItem panel vgs.vpn)" || at=unreadable
  for _ in $(seq 1 8); do
    [[ $at == "$1" ]] && return 0
    before="$at"
    type_keys -k Tab || { fail "Tab in the locked VPN dropdown failed"; return 1; }
    for _ in $(seq 1 10); do
      at="$(ipc smoke activeFocusItem panel vgs.vpn)" || at=unreadable
      [[ $at != "$before" ]] && break
      sleep 0.1
    done
  done
}
# vpn_locked_wait LOCKED LABEL WANT CMD...: expect_poll on a tree that draws
# the lock; on an older tree, which may never reach WANT, 25 reads 0.2 s
# apart that end at WANT or log the last reading.
vpn_locked_wait() { # LOCKED LABEL WANT CMD...
  local locked="$1" label="$2" want="$3" got=unread
  shift 3
  if "$locked"; then expect_poll "$label" "$want" "$@"; return; fi
  for _ in $(seq 1 25); do
    got="$("$@")" || got=unreadable
    [[ $got == "$want" ]] && return 0
    sleep 0.2
  done
  printf 'sandbox-shots: vpn-locked tree=%s step=%s want=%s read=%s\n' "${rev:-checkout}" "$label" "$want" "$got"
}
network_shot_shown() { [[ $(ipc smoke instanceGeometry window vgs.network) != absent ]] && echo shown || echo hidden; }
network_shot_other_reveal() { ipc smoke revealText window vgs.system Button 'Other Network…' | py_reply 'import json,sys; json.load(sys.stdin); print("scrolled")'; }
network_shot_cancel_reveal() { ipc smoke revealText window vgs.system Button Cancel | py_reply 'import json,sys; json.load(sys.stdin); print("scrolled")'; }
network_shot_reveal() { ipc smoke revealText window vgs.system ListItem enp10s0 | py_reply 'import json,sys; json.load(sys.stdin); print("scrolled")'; }
network_shot_panel() { [[ $(ipc smoke instanceGeometry panel vgs.network) != absent ]] && echo shown || echo hidden; }
network_shot_details() { ipc smoke networkDetails window | py_reply 'import json,sys; s=sys.stdin.read(); print(s.startswith("{") and len(json.loads(s)["rows"]) > 0)'; }
network_shot_names() { ipc smoke readDescendant window vgs.network NetworkBody rows | py_reply 'import json,sys; print(json.dumps([[r["name"],r["security"],r["known"]] for r in json.load(sys.stdin)]))'; }
network_shot_known() { ipc smoke statusValues vgs.network | py_reply 'import json,sys; print(any(r["known"] for r in json.load(sys.stdin)["network"]["wifi"]))'; }
network_shot_action() { ipc smoke statusValues vgs.network | py_reply 'import json,sys; print(json.load(sys.stdin)["network"]["action"]["kind"])'; }
network_shot_prompt() { ipc smoke statusValues vgs.network | py_reply 'import json,sys; print(bool(json.load(sys.stdin)["network"]["prompt"]))'; }

scene_dialog() { # MODE
  expect "enabling acme.needs is allowed" ok ipc shell setPluginEnabled acme.needs true
  expect_poll "the notice shows for acme.needs" '"acme.needs"' notice_plugin
  expect_poll "the notice maps its surface" 1 layer_count vgs:notice
  park_pointer
  take "dialog-$1"
  type_keys -k Escape || fail "sending Escape to the notice failed"
  expect_poll "Escape closes the notice" 0 layer_count vgs:notice
  expect "disabling acme.needs is allowed" ok ipc shell setPluginEnabled acme.needs false
}

scene_by-hand() { # MODE
  expect "enabling acme.needs for the by-hand notice is allowed" ok ipc shell setPluginEnabled acme.needs true
  expect_poll "the by-hand notice shows for acme.needs" '"acme.needs"' notice_plugin
  expect_poll "the by-hand notice maps its surface" 1 layer_count vgs:notice
  expect "the by-hand notice offers Close alone" '["Close"]' notice_drawn_key actions
  expect "the by-hand notice says to install by hand" true notice_message_hold "by hand"
  park_pointer
  take "by-hand-$1"
  type_keys -k Escape || fail "sending Escape to the by-hand notice failed"
  expect_poll "Escape closes the by-hand notice" 0 layer_count vgs:notice
  expect "disabling acme.needs after the by-hand shot is allowed" ok ipc shell setPluginEnabled acme.needs false
}

scene_reset() { # MODE
  local marker backup
  expect "reset with no terminal asks the running shell" shell=asked shot_reset_ask
  expect_poll "the reset question maps" 1 layer_count vgs:notice
  expect_poll "the reset question title is shown" '"Reset VGS?"' notice_drawn_key title
  park_pointer
  take "reset-ask-$1"
  type_keys -k Escape || fail "sending Escape to the reset question failed"
  expect_poll "Escape closes the reset question" 0 layer_count vgs:notice

  marker="$home/.local/state/vgshell/reset-backup"
  backup="$home/.local/state/vgshell/reset-shot-backup"
  mkdir -p -- "$backup"
  printf '%s\n' "$backup" >"$marker"
  stop_shell
  start_shell "$tree" "$sandbox/shell-reset-$1.log"
  expect_poll "the reset-done notice maps" 1 layer_count vgs:notice
  expect_poll "the reset-done title is shown" '"VGS was reset"' notice_drawn_key title
  park_pointer
  take "reset-done-$1"
  type_keys -k Escape || fail "sending Escape to the reset-done notice failed"
  expect_poll "Escape hides the reset-done notice" 0 layer_count vgs:notice
  rm -f -- "$marker"
  rm -rf -- "$backup"
}

# Every surface class again on a monitor 480 by 720 logical pixels.
scene_narrow() { # MODE
  narrow_begin
  gallery_pages=2
  scene_bar "$1-narrow"
  scene_panels "$1-narrow"
  scene_devtools "$1-narrow"
  scene_dialog "$1-narrow"
  ! scene_ships lock || scene_lock "$1-narrow"
  scene_launcher "$1-narrow"
  scene_notifications "$1-narrow"
  scene_gallery "$1-narrow"
  gallery_pages=12
  narrow_end
}

lock_core() { ipc shell lent | py_reply 'import json,sys; l=json.load(sys.stdin)["lock"]; print(json.dumps([l["requested"], l["secure"], l["content"]]))'; }
lock_failures() { ipc vgs.lock invoke status '' | py_reply 'import json,sys; print(json.load(sys.stdin)["failures"])'; }
# lock_fail N: N wrong attempts through the service's own failure step,
# with no PAM.
lock_fail() {
  local i
  for ((i = 0; i < $1; i++)); do
    [[ $(ipc smoke invokeInstance service vgs.lock fail '') != no-function ]] || { fail "vgs.lock has no fail()"; return; }
  done
}
scene_lock() { # MODE
  local probe
  probe="$(plugin_enabled acme.probe)" || probe=unreadable
  [[ $probe != True ]] || expect "disabling the probe fixture, which holds lock, is allowed" ok ipc shell setPluginEnabled acme.probe false
  expect "enabling vgs.lock is allowed" ok ipc shell setPluginEnabled vgs.lock true
  expect_poll "vgs.lock is built" True record_exists vgs.lock
  expect "the lock answers ok" ok ipc vgs.lock invoke lock ''
  expect_poll "the lock is confirmed with the lock screen" '[true, true, true]' lock_core
  take "lock-$1"
  lock_fail 1
  expect_poll "one wrong attempt is shown" 1 lock_failures
  take "lock-$1-wrong"
  lock_fail 9
  expect_poll "ten wrong attempts are shown" 10 lock_failures
  take "lock-$1-pause"
  expect "the probe releases the lock" ok ipc smoke sessionUnlock
  expect_poll "the core holds no lock" '[false, false, true]' lock_core
  expect "disabling vgs.lock is allowed" ok ipc shell setPluginEnabled vgs.lock false
  expect_poll "vgs.lock is gone" False record_exists vgs.lock
  [[ $probe != True ]] || expect "re-enabling the probe fixture is allowed" ok ipc shell setPluginEnabled acme.probe true
}

# A plugin's message to the user, as the tree draws it: a core toast where
# the tree ships shell/Core/Toasts.qml, else the system notification
# vgs.notifications draws. The clipboard's paste failure is a message that
# answers one key press, its unsaved history a lasting one, and the lock's
# warning that the computer slept unlocked shows once the lock ends. Both
# trees' vgs.clipboard has notice(title, message), which a tree with toasts
# calls with two arguments and drops the third, and both trees' vgs.lock
# has released(reason).
messages_toasts=false
[[ -f $tree/shell/Core/Toasts.qml ]] && messages_toasts=true
messages_shown() {
  if "$messages_toasts"; then
    ipc shell lent | py_reply 'import json,sys; print(len(json.load(sys.stdin)["toasts"]["visible"]))'
  else
    notes status | py_reply 'import json,sys; print(json.load(sys.stdin)["onScreen"])'
  fi
}
messages_silence() { notes status | py_reply 'import json,sys; print(str(json.load(sys.stdin)["silence"]).lower())'; }
# messages_clear PLUGIN: a toast ends with its plugin's instance; a
# notification is dismissed, `none` when no card shows, and its History
# cleared.
messages_clear() { # PLUGIN
  local reply
  if "$messages_toasts"; then
    expect "disabling $1 ends its toasts" ok ipc shell setPluginEnabled "$1" false
    expect_poll "$1 is gone" False record_exists "$1"
    expect "enabling $1 again is allowed" ok ipc shell setPluginEnabled "$1" true
    expect_poll "$1 is built again" True record_exists "$1"
  else
    reply="$(notes dismiss-all)" || reply=unread
    [[ $reply == ok || $reply == none ]] || fail "dismissing the notifications answered $reply"
    expect "the history clears" ok notes clear-history
  fi
  expect_poll "no message is left on screen" 0 messages_shown
}
page_links_text='[Probe page](page:acme.probe) holds the probe.'
page_links_forward=false
tree_has shell/Ui/controls/FormRow.qml 'signal warningPageActivated' && page_links_forward=true
scene_page-links() { # MODE
  local box layer x y
  expect "the page link panel opens" ok ipc shell summon panel acme.surfaces '{}'
  expect_poll "the page link panel is mapped" 1 layer_count vgs:panel
  summon_drawn panel acme.surfaces || { fail "the page link panel never drew"; return; }
  park_pointer
  take "page-links-$1-panel"
  if "$page_links_forward"; then
    box="$(ipc smoke windowGeometry panel acme.surfaces LinkText "$page_links_text")" || box=unread
    [[ $box == \[* ]] || { fail "the page link line is unreadable: $box"; return; }
    layer="$(surface_box vgs:panel)" || { fail "the page link panel's box is unreadable"; return; }
    read -r x y < <(python3 -c 'import json,sys; b=json.loads(sys.argv[1]); l=json.loads(sys.argv[2]); print(int(l[0] + b[0] + 8), int(l[1] + b[1] + b[3] / 2))' "$box" "$layer")
    hover "$x" "$y" || fail "the pointer did not reach the page link"
    expect_poll "the pointer on the page link reaches its words" true ipc smoke readMatchingDescendant panel acme.surfaces LinkText text "$page_links_text" hoveredLink
    click "$x" "$y" || fail "the click on the page link failed"
    expect_poll "the page link opens the probe fixture's page" '"acme.probe"' settings_page
    park_pointer
    take "page-links-$1-opened"
    settings_close
  fi
  ipc shell hide panel acme.surfaces >/dev/null || true
  expect_poll "the page link panel is gone" 0 layer_count vgs:panel
}
# A bar item's tooltip that names another plugin's page. A tree that ships
# the acme.tiplink fixture draws the reference as a link: the pointer
# crosses from the item onto the link's words, and then, with the bar's
# window holding the keyboard as the fixture has it take it, Tab puts the
# focus ring on those words. An older tree gets a widget with the same
# item and tooltip, and its one shot is that tooltip under the pointer on
# the item, since the pointer cannot leave the item there.
tooltip_link_call() { ipc smoke invokeInstance "$(bar_key)" acme.tiplink "$1" "${2:-}"; }
scene_tooltip-link() { # MODE
  local at x y step
  hover_widget "the pointer rests on the tooltip link item" acme.tiplink || return
  expect_poll "the tooltip link item's tooltip opens" true tooltip_opened acme.tiplink
  if [[ ! -f $fixtures/acme.tiplink/Widget.qml ]]; then
    take_posed "tooltip-link-$1-pointer"
    park_pointer
    expect_poll "the tooltip link item's tooltip closes" false tooltip_opened acme.tiplink
    return
  fi
  at="$(centre_of "$(tooltip_link_call linkGeometry)")" || at=none
  if [[ $at == none ]]; then fail "the tooltip's link has no box"; return; fi
  read -r x y <<<"$at"
  hover "$x" "$y" || fail "the pointer did not reach the tooltip's link"
  expect_poll "the pointer is on the tooltip" true ipc smoke readInstance "$(bar_key)" acme.tiplink tooltipHovered
  take_posed "tooltip-link-$1-pointer"
  park_pointer
  expect_poll "the tooltip closes after the pointer leaves it" false tooltip_opened acme.tiplink
  expect "the bar window takes the keyboard for the ring" ok tooltip_link_call holdKeyboard true
  for step in 2 3; do
    at="$(ipc smoke instanceGeometry "$(bar_key)" vgs.bar | py_reply 'import json,sys; x,y,w,h=json.load(sys.stdin); print(int(x+int(sys.argv[1])), int(y+h/2))' "$step")" || at=none
    read -r x y <<<"$at"
    [[ $x =~ ^[0-9]+$ ]] && hover "$x" "$y" || fail "moving the pointer onto the bar failed"
  done
  expect_poll "the tooltip link item holds the focus a Tab gives" true tooltip_link_call focusItem
  expect_poll "keyboard focus opens the item's tooltip" true tooltip_opened acme.tiplink
  type_keys -k Tab || fail "sending Tab to the bar failed"
  expect_poll "Tab makes the tooltip's link current" 1 ipc smoke readInstance "$(bar_key)" acme.tiplink currentLine
  take_posed "tooltip-link-$1-ring"
  type_keys -k Escape || fail "sending Escape to the bar failed"
  expect_poll "Escape closes the tooltip" false tooltip_opened acme.tiplink
  expect "the bar window gives the keyboard back" ok tooltip_link_call holdKeyboard false
  park_pointer
}
scene_plugin-messages() { # MODE
  local probe silence_found=false
  if ! "$messages_toasts"; then
    # The status function registers once the store is read, after the
    # plugin is built: 10 s at most, polled as expect_poll polls.
    for _ in $(seq 1 50); do
      silence_found="$(messages_silence)" || silence_found=unread
      [[ $silence_found == unread || $silence_found == empty ]] || break
      sleep 0.2
    done
    [[ $silence_found == true || $silence_found == false ]] || fail "Silence is unreadable before the plugin messages: $silence_found"
    [[ $silence_found == false ]] || expect "Silence goes off for the plugin messages" off notes silence off
  fi
  expect_poll "the clipboard history's store is ready" '"ready"' ipc smoke readInstance service vgs.clipboard store
  expect_poll "no message shows at first" 0 messages_shown
  expect "the clipboard's paste failure is sent" "" ipc smoke invokeInstanceArgs service vgs.clipboard notice \
    '{"args": ["Paste failed", "The entry is on the clipboard. Paste it with the key of the application.", true]}'
  expect_poll "the paste failure shows" 1 messages_shown
  park_pointer
  take "plugin-messages-$1-transient"
  messages_clear vgs.clipboard
  expect_poll "the clipboard history's store is ready again" '"ready"' ipc smoke readInstance service vgs.clipboard store
  expect "the clipboard's unsaved history is sent" "" ipc smoke invokeInstanceArgs service vgs.clipboard notice \
    '{"args": ["Clipboard history is not saved", "The history file cannot be written.", false]}'
  expect_poll "the unsaved history shows" 1 messages_shown
  park_pointer
  take "plugin-messages-$1-lasting"
  messages_clear vgs.clipboard
  expect_poll "the clipboard history's store is ready for the page reference" '"ready"' ipc smoke readInstance service vgs.clipboard store
  expect "the clipboard's message with a page reference is sent" "" ipc smoke invokeInstanceArgs service vgs.clipboard notice \
    '{"args": ["Clipboard history is off", "Turn it on in [Settings > Clipboard](page:vgs.clipboard).", false]}'
  expect_poll "the page reference message shows" 1 messages_shown
  park_pointer
  take "plugin-messages-$1-page-reference"
  # A click on the card opens Settings on the page its link names, and the
  # card leaves.
  if ! "$messages_toasts"; then
    click_item vgs:layer vgs.notifications NotificationCard summary "Clipboard history is off" 24 - || fail "the click on the page reference card failed"
    expect_poll "the page reference card opens Settings on the Clipboard page" '"vgs.clipboard"' settings_page
    expect_poll "the page reference card leaves" 0 messages_shown
    park_pointer
    take "plugin-messages-$1-page-reference-opened"
    settings_close
  fi
  messages_clear vgs.clipboard
  probe="$(plugin_enabled acme.probe)" || probe=unreadable
  [[ $probe != True ]] || expect "disabling the probe fixture, which holds lock, is allowed" ok ipc shell setPluginEnabled acme.probe false
  expect "enabling vgs.lock is allowed" ok ipc shell setPluginEnabled vgs.lock true
  expect_poll "vgs.lock is built" True record_exists vgs.lock
  expect "the lock answers ok" ok ipc vgs.lock invoke lock ''
  expect_poll "the lock is confirmed with the lock screen" '[true, true, true]' lock_core
  expect "a sleep the lock did not confirm is released" "" ipc smoke invokeInstanceArgs service vgs.lock released '{"args": ["timeout"]}'
  expect "no message shows over the lock screen" 0 messages_shown
  expect "the probe releases the lock" ok ipc smoke sessionUnlock
  expect_poll "the core holds no lock" '[false, false, true]' lock_core
  expect_poll "the warning shows once the lock ends" 1 messages_shown
  park_pointer
  take "plugin-messages-$1-lock"
  messages_clear vgs.lock
  expect "disabling vgs.lock is allowed" ok ipc shell setPluginEnabled vgs.lock false
  expect_poll "vgs.lock is gone" False record_exists vgs.lock
  [[ $probe != True ]] || expect "re-enabling the probe fixture is allowed" ok ipc shell setPluginEnabled acme.probe true
  [[ $silence_found != true ]] || expect "Silence goes back on after the plugin messages" on notes silence on
}

# The vgs.polkit prompt, asking and after a failed attempt, over the
# probe's stand-in flow (polkitStandInOpen in scripts/smoke/Probe.qml): the
# plugin's own Prompt.qml in a stand-in of the summon host's overlay
# surface. vgs.polkit stays disabled and nothing is typed; the scene reads
# that no request went live, that the stand-in was never submitted and
# that no authentication helper ran while it was open, as rows/polkit.sh
# reads them (docs/decisions/D062-native-lock-and-polkit-plugins.md).
polkit_flows() { ipc shell lent | py_reply 'import json,sys; print(json.load(sys.stdin)["polkitFlows"])'; }
scene_polkit() { # MODE
  local watch_log="$sandbox/shots-polkit-$1-auth.log"
  auth_watch_start "$watch_log"
  expect "vgs.polkit stays disabled for its prompt's shots" False plugin_enabled vgs.polkit
  expect "the stand-in prompt opens" ok ipc smoke polkitStandInOpen "$repo/shell/plugins/vgs.polkit/Prompt.qml"
  expect_poll "the stand-in prompt maps its surface" 1 layer_count vgs:overlay
  park_pointer
  take "polkit-$1"
  expect "the stand-in flow reads a failed attempt" ok ipc smoke polkitStandInFail
  take "polkit-$1-failed"
  expect "the prompt closes and cancels only the stand-in, which was never submitted" '{"submits":0,"cancels":1}' ipc smoke polkitStandInDrop
  expect_poll "the stand-in prompt's surface is gone" 0 layer_count vgs:overlay
  expect "no authentication request went live in this shell" 0 polkit_flows
  expect "no authentication helper runs under the shell" none auth_helpers "$shell_qs_pid"
  kill "$auth_watch_pid" 2>/dev/null || fail "stopping the helper watcher pid $auth_watch_pid failed"
  expect "while the prompt was open, the watcher saw no authentication helper" "" cat -- "$watch_log"
}

# The login screen: the core's greeter host over vgs.greeter's view
# (docs/decisions/D101-greeter-host-and-greeter-system-step.md), with the smoke's fixture sessions, the
# mode's theme file and one fixture account.
scene_greeter() { # MODE
  local dir="$sandbox/shots-greeter-$1" word base_path="" pid ready=false
  mkdir -p -- "$dir/config/vgshell" "$dir/state" "$dir/bin"
  if [[ -f $home/.config/vgshell/theme.json ]]; then cp -- "$home/.config/vgshell/theme.json" "$dir/config/vgshell/theme.json"; fi
  printf '#!/bin/sh\n[ "$1" = passwd ] || exit 2\necho "alex:x:1000:1000:Alex Doe:/home/alex:/bin/bash"\n' >"$dir/bin/getent"
  chmod 755 "$dir/bin/getent"
  for word in "${shell_env[@]}"; do [[ $word != PATH=* ]] || base_path="${word#PATH=}"; done
  spawn "$dir/greeter.log" "${shell_env[@]}" PATH="$dir/bin:$base_path" \
    XDG_DATA_DIRS="$checkout/scripts/smoke/fixtures/greeter/share-a:$checkout/scripts/smoke/fixtures/greeter/share-b" \
    XDG_CONFIG_HOME="$dir/config" XDG_STATE_HOME="$dir/state" \
    VGS_GREETER_VIEW="$repo/shell/plugins/vgs.greeter/Greeter.qml" qs -p "$repo/shell/greeter.qml"
  pid="$spawn_pid"
  for _ in $(seq 1 100); do
    if grep -q -F -- "greeter: sessions=" "$dir/greeter.log"; then ready=true; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  if [[ $ready == true ]]; then ok "the greeter host lists its sessions"; else fail "the greeter host listed no sessions: $(tail -n 5 -- "$dir/greeter.log")"; fi
  expect_poll "the greeter host maps its surface" 1 layer_count vgs:greeter
  park_pointer
  take "greeter-$1"
  kill -TERM "$pid" 2>/dev/null || fail "stopping the greeter host pid $pid failed"
  wait "$pid" 2>/dev/null || true
  expect_poll "the greeter host's surface is gone" 0 layer_count vgs:greeter
}

scene_screensaver() { # MODE
  if ! command -v ttfx >/dev/null 2>&1; then
    printf 'sandbox-shots: scene=screensaver mode=%s status=not-measured missing=ttfx\n' "$1"
    unmeasured=$((unmeasured + 1))
    return 0
  fi
  python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
path = sys.argv[1]
doc = json.load(open(path))
rows = doc.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.screensaver"), None)
if row is None:
    row = {"id": "vgs.screensaver"}
    rows.append(row)
row.update({"idleEnabled": False, "effect": "print", "frameRate": 30})
with open(path + ".tmp", "w") as out:
    json.dump(doc, out)
os.replace(path + ".tmp", path)
PY
  expect "enabling vgs.screensaver is allowed" ok ipc shell setPluginEnabled vgs.screensaver true
  expect "reload config for the screensaver shot" ok ipc shell reloadConfig
  expect_poll "vgs.screensaver is built" True record_exists vgs.screensaver
  expect "starting the screensaver for the shot is allowed" ok ipc vgs.screensaver invoke start ''
  expect_poll "the screensaver cover is shown for the shot" 1 layer_count vgs:cover
  sleep 8
  take "screensaver-$1-cover"
  expect "stopping the screensaver after the shot is allowed" ok ipc vgs.screensaver invoke stop ''
  expect_poll "the screensaver cover is gone after the shot" 0 layer_count vgs:cover
  expect "disabling vgs.screensaver after the shot is allowed" ok ipc shell setPluginEnabled vgs.screensaver false
}

# The setup each scene needs, once each, in the order the scenes first
# need them: the bar draws the launcher's and the panels' widgets, and the
# narrow pass takes every other scene's surfaces again.
setups=()
need_setup() { local s; for s in "${setups[@]}"; do [[ $s == "$1" ]] && return 0; done; setups+=("$1"); }

scene_automations() { # MODE
  local auto_stub="$sandbox/shots-automations"
  local auto_found notif_found
  auto_found="$(plugin_enabled vgs.automations)" || auto_found=unread
  notif_found="$(plugin_enabled vgs.notifications)" || notif_found=unread
  [[ $auto_found == True || $auto_found == False ]] || fail "vgs.automations' enablement is unreadable before the Automations scene: $auto_found"
  [[ $notif_found == True || $notif_found == False ]] || fail "vgs.notifications' enablement is unreadable before the Automations scene: $notif_found"
  automations_stand_ins "$auto_stub"
  if [[ -e $shim/systemd-analyze ]]; then mv -- "$shim/systemd-analyze" "$auto_stub/saved/systemd-analyze"; fi
  printf '#!/usr/bin/env bash\nexit 0\n' >"$shim/systemd-analyze"
  chmod 755 "$shim/systemd-analyze"
  terminal_stand_in
  local auto_engine="$repo/shell/plugins/vgs.automations/bin/automations"
  local shell_path
  shell_path="$(tr '\0' '\n' <"/proc/$shell_qs_pid/environ" | sed -n 's/^PATH=//p')"
  automations_shot() { "${shell_env[@]}" PATH="$shell_path" "$auto_engine" --tree "$repo" "$@"; }
  automation_list_has() { ipc smoke itemTexts window vgs.automations AutomationRow | py_reply 'import json,sys; print(any(row and row[0] == sys.argv[1] for row in json.load(sys.stdin)))' "$1"; }
  automation_list_empty() { ipc smoke itemTexts window vgs.automations AutomationRow | py_reply 'import json,sys; rows=json.load(sys.stdin); print(len(rows) == 0)'; }
  automation_history_count() { automations_shot history "$1" --json | py_reply 'import json,sys; print(len(json.load(sys.stdin)["rows"]))'; }
  # A control below the fold: its scroll area moves, as a wheel would,
  # until it lies in view (the probe's revealText).
  automation_reveal() { local at; at="$(ipc smoke revealText window vgs.automations "$1" "$2")" && [[ -n $at && $at != absent ]]; }
  automation_click() { automation_reveal "$1" "$2" && click_in window:Automations window vgs.automations "$1" "$2"; }
  automation_read() { ipc smoke readInstance window vgs.automations "$1"; }
  local success='{"name":"Shot success","command":"echo success","notifyEveryRun":true,"schedule":{"frequency":"weekly","interval":1,"weekdays":["mon"],"times":["09:00"],"start":"2026-01-05","end":{"type":"never"}}}'
  local failure='{"name":"Shot failure","command":"echo nope >&2; exit 3","notifyEveryRun":true,"schedule":{"frequency":"weekly","interval":1,"weekdays":["fri"],"times":["17:30"],"start":"2026-01-09","end":{"type":"never"}}}'
  local custom='{"name":"Shot custom","command":"printf custom","notifyEveryRun":false,"schedule":{"frequency":"weekly","interval":3,"weekdays":["mon","wed"],"times":["08:30","16:45"],"start":"2026-01-05","end":{"type":"never"}}}'
  automations_shot add --definition "$success" >/dev/null
  automations_shot add --definition "$failure" >/dev/null
  automations_shot add --definition "$custom" >/dev/null
  expect "enabling vgs.automations is allowed" ok ipc shell setPluginEnabled vgs.automations true
  expect_poll "vgs.automations is built" True record_exists vgs.automations
  automation_active_count() { ipc vgs.automations invoke status "" | py_reply 'import json,sys; print(json.load(sys.stdin).get("active", "unset"))'; }
  expect_poll "the service lists the seeded automations" 3 automation_active_count
  expect "the automations window opens" ok ipc shell summon window vgs.automations '{}'
  expect_poll "the automations window maps" 1 window_count Automations
  expect_poll "the automations list shows Shot success" True automation_list_has "Shot success"
  take "automations-$1-list"
  click_in window:Automations window vgs.automations AutomationRow "Shot success" || fail "selecting the success automation failed"
  auto_shot_preview_ready() { ipc smoke readInstance window vgs.automations previewFirst | py_reply 'import json,sys; print(str(json.load(sys.stdin)).isdigit())'; }
  expect_poll "the preset preview has a first occurrence" True auto_shot_preview_ready
  expect "the Automations window's root takes the focus for the preset image" focused ipc smoke invokeInstance window vgs.automations focusInstance ""
  take "automations-$1-editor-preset-next"
  automation_click Button "Test run" || fail "starting a test run from the editor failed"
  expect_poll "the editor test run reaches history" 1 automation_history_count shot-success
  auto_shot_transcript_ready() { ipc smoke readInstance window vgs.automations testTranscript | py_reply 'import json,sys; print(json.load(sys.stdin) != "")'; }
  expect_poll "the editor shows the test run transcript" True auto_shot_transcript_ready
  expect "the Automations window's root takes the focus for the transcript image" focused ipc smoke invokeInstance window vgs.automations focusInstance ""
  take "automations-$1-test-run-transcript"
  automation_click IconButton "Back to automations" || fail "returning to the automations list failed"
  click_in window:Automations window vgs.automations AutomationRow "Shot custom" || fail "selecting the custom automation failed"
  expect_poll "the custom preview has a first occurrence" True auto_shot_preview_ready
  expect "the Automations window's root takes the focus for the custom image" focused ipc smoke invokeInstance window vgs.automations focusInstance ""
  take "automations-$1-editor-custom-next"
  automation_click Radio On || fail "showing the end date field failed"
  ipc smoke revealScopedText window vgs.automations Field Ends IconButton "Pick date" >/dev/null || fail "revealing the end date's picker failed"
  click_scoped_in window:Automations window vgs.automations Field Ends IconButton "Pick date" || fail "opening the date picker failed"
  automation_date_open() { ipc smoke itemValues window vgs.automations DateField pickerOpen | py_reply 'import json,sys; print(str(any(r["pickerOpen"] for r in json.load(sys.stdin))).lower())'; }
  expect_poll "the date picker opens" true automation_date_open
  take_posed "automations-$1-date-picker"
  type_keys -k Escape || fail "closing the date picker failed"
  expect_poll "the date picker closes" false automation_date_open
  automations_shot run-now shot-success >/dev/null
  automations_shot run-now shot-failure >/dev/null
  automation_click Label History || fail "opening history failed"
  take "automations-$1-history"
  automation_click Button "Clear history" || fail "asking to clear history failed"
  expect_poll "the clear question shows" '"clear"' automation_read confirmAction
  take "automations-$1-confirm-dialog"
  click_in window:Automations window vgs.automations Button Confirm || fail "confirming history clear failed"
  expect_poll "the history is cleared" 0 automation_history_count shot-success
  take "automations-$1-history-empty-state"
  automations_shot remove shot-success >/dev/null
  automations_shot remove shot-failure >/dev/null
  automations_shot remove shot-custom >/dev/null
  expect "the Automations window hides before the empty shot" ok ipc shell hide window vgs.automations
  expect_poll "the Automations window is hidden before the empty shot" 0 window_count Automations
  expect "the empty Automations window opens" ok ipc shell summon window vgs.automations '{}'
  expect_poll "the empty Automations window maps" 1 window_count Automations
  expect_poll "the automations list is empty" True automation_list_empty
  take "automations-$1-empty-state"
  expect "enabling vgs.notifications is allowed" ok ipc shell setPluginEnabled vgs.notifications true
  expect_poll "vgs.notifications is built" True record_exists vgs.notifications
  local ids=()
  ids+=("$(notify Automations "Shot success finished" "Finished in 0 s" '["default", "Open"]' '{"x-vgs-icon": <"circle-check">, "x-vgs-tone": <"success">, "x-vgs-click": <"open">}')")
  ids+=("$(notify Automations "Shot failure failed" "Exit code 3" '["default", "Open"]' '{"x-vgs-icon": <"circle-x">, "x-vgs-tone": <"danger">, "x-vgs-click": <"open">}')")
  expect_poll "automation notifications are on screen" 2 on_screen
  take "automations-$1-notifications"
  for id in "${ids[@]}"; do
    "${shell_env[@]}" gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.CloseNotification "$id" >/dev/null || fail "closing automation notification $id failed"
  done
  expect "the automation notification history clears" ok notes clear-history
  expect "the Automations window hides after its scene" ok ipc shell hide window vgs.automations
  expect_poll "the Automations window is gone after its scene" 0 window_count Automations
  if [[ $auto_found == False ]]; then
    expect "disabling vgs.automations after its scene is allowed" ok ipc shell setPluginEnabled vgs.automations false
    expect_poll "vgs.automations is gone after its scene" False record_exists vgs.automations
  fi
  if [[ $notif_found == False ]]; then
    expect "disabling vgs.notifications after the Automations scene is allowed" ok ipc shell setPluginEnabled vgs.notifications false
    expect_poll "vgs.notifications is gone after the Automations scene" False record_exists vgs.notifications
  fi
  if [[ -e $auto_stub/saved/systemd-analyze ]]; then mv -f -- "$auto_stub/saved/systemd-analyze" "$shim/systemd-analyze"; else rm -f -- "$shim/systemd-analyze"; fi
  automations_stand_ins_restore "$auto_stub"
}

# The cloudsync scene stages each state through vgs.cloud-sync's own
# runner, bin/cloud-sync, and plants no status: the plugin's
# CloudSyncLogic.js, run under node, reads the values the service
# published and names the state, which each state's shots wait for.
# scripts/test-cloud-sync-scene.js holds the scene to that rule.
# cs_code FIELD...: what CloudSyncLogic.js makes of the published values,
# one word per FIELD: cause, the headline's cause; kind, the last error's
# kind or none; hidden, whether the bar widget hides.
cs_code() {
  ipc vgs.cloud-sync invoke status "" | node -e '
const [lib, logic, ...fields] = process.argv.slice(1);
const text = require("fs").readFileSync(0, "utf8");
let cloud;
try { cloud = JSON.parse(text).cloud; } catch (e) { console.log("unreadable=" + text.trim().slice(0, 80)); process.exit(0); }
if (cloud === undefined || cloud === null) { console.log("unpublished"); process.exit(0); }
const L = require(lib).load(logic), now = Date.now();
const read = { cause: L.headline(cloud, now).cause, kind: cloud.lastError === null ? "none" : cloud.lastError.kind, hidden: L.widgetView(cloud, now).hidden };
console.log(fields.map(f => String(read[f])).join(" "));' "$tree/bin/lib/qml-library.js" "$tree/shell/plugins/vgs.cloud-sync/CloudSyncLogic.js" "$@"
}
# cs_shots MODE STATE CAUSE [KIND]: once the code reads the published
# values as CAUSE, and the last error as KIND when given, the bar with
# the widget and its tooltip unless the code hides it, the Cloud Sync
# window, and every screen of the Cloud Sync Settings page.
cs_shots() {
  local m="$1" s="$2" want="$3" fields=(cause) hidden box name f at
  if [[ $# -gt 3 ]]; then want+=" $4"; fields+=(kind); fi
  expect "Cloud Sync reads its record again ($s)" ok ipc vgs.cloud-sync invoke refresh ""
  expect_poll "Cloud Sync's code reads the published values as $s" "$want" cs_code "${fields[@]}"
  hidden="$(cs_code hidden)"
  expect_poll "the Cloud Sync widget is shown as its code decides ($s)" "$([[ $hidden == true ]] && echo false || echo true)" ipc smoke readInstance "$(bar_key)" vgs.cloud-sync visible
  if [[ $hidden == false ]]; then
    take "cloudsync-$m-$s-bar"
    box="$(ipc smoke instanceGeometry "$(bar_key)" vgs.cloud-sync)" || box=absent
    record_item "cloudsync-$m-$s-bar" "$box"
    if hover_widget "the pointer rests on Cloud Sync's widget ($s)" vgs.cloud-sync; then
      expect_poll "Cloud Sync's tooltip opens ($s)" true tooltip_opened vgs.cloud-sync
      take_posed "cloudsync-$m-$s-bar-tooltip"
    fi
    park_pointer
  fi
  expect "the Cloud Sync window opens ($s)" ok ipc shell summon window vgs.cloud-sync '{}'
  expect_poll "the Cloud Sync window maps ($s)" 1 window_count "Cloud Sync"
  take "cloudsync-$m-$s-window"
  record_item "cloudsync-$m-$s-window" "$(one_window "Cloud Sync")"
  # A window that runs past its view is shot again at its end, so each row
  # to review shows in a shot. The probe's reply is [contentY,
  # contentHeight, height].
  at="$(ipc smoke scrollTo window vgs.cloud-sync 1000000)" || at=""
  if [[ $at != \[* ]]; then
    fail "the Cloud Sync window did not scroll ($s): ${at:-no reply}"
  elif [[ $at != \[0,* ]]; then
    take "cloudsync-$m-$s-window-end"
    record_item "cloudsync-$m-$s-window-end" "$(one_window "Cloud Sync")"
  fi
  expect "the Cloud Sync window hides ($s)" ok ipc shell hide window vgs.cloud-sync
  expect_poll "the Cloud Sync window is gone ($s)" 0 window_count "Cloud Sync"
  expect "the Settings window opens ($s)" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  expect_poll "the Settings window maps ($s)" 1 settings_count
  plugin_page_shots "$m" vgs.cloud-sync "cloudsync-$m-$s-page" setup
  box="$(one_window Plugins)"
  for f in "$SHOT_DIR/cloudsync-$m-$s-page"*.png; do
    name="${f##*/}"
    record_item "${name%.png}" "$box"
  done
  settings_close
}
# Every state VGS-1314 sheets, over a local rclone remote that `block`
# holds inside its copy and `fail` fails, and a keyring stand-in with one
# file per account: no credential, keyring or Drive call. A token's file
# holds a stand-in account address on its second line. rclone's local
# backend lists no object ID, and the runner tells a Drive rename from a
# Drive deletion only by the ID its baseline holds (bin/cloud-sync
# classifyBeforeCopy), so the stand-in's listing gives each file its inode
# as its ID: a rename keeps it, as a rename on Drive keeps the object's ID.
scene_cloudsync() { # MODE
  local m="$1" cs="$sandbox/cloudsync-$1" host_rclone host_node drive runner pairs_file
  # The node binary itself: a version manager's shim on PATH may not run
  # under the runner's environment, which the stand-in inherits.
  host_node="$(node -e 'process.stdout.write(process.execPath)')" || { fail "cloudsync scene: node missing"; return; }
  if ! host_rclone="$(command -v rclone)"; then
    printf 'sandbox-shots: scene=cloudsync mode=%s status=not-measured missing=rclone\n' "$m"
    unmeasured=$((unmeasured + 1))
    return 0
  fi
  if [[ -e $shim/rclone ]]; then fail "cloudsync scene: $shim/rclone exists"; return; fi
  drive="$cs/drive"
  mkdir -p -- "$cs/secrets" "$drive/Documents/Taxes" "$home/cloudsync-$m/inbox/agent-uploads"
  automations_stand_ins "$cs/systemd"
  cat >"$shim/rclone" <<SH
#!/usr/bin/env bash
export RCLONE_CONFIG_VGSDRIVE_TYPE=local
unset RCLONE_CONFIG_VGSDRIVE_CLIENT_ID RCLONE_CONFIG_VGSDRIVE_CLIENT_SECRET RCLONE_CONFIG_VGSDRIVE_TOKEN RCLONE_CONFIG_VGSDRIVE_SCOPE
if [[ -f "$cs/block" ]]; then for _ in \$(seq 1 300); do [[ -f "$cs/release" ]] && break; sleep 0.2; done; fi
if [[ -f "$cs/fail" ]]; then echo "Failed to copy: stand-in sync error" >&2; exit 1; fi
cd "$drive" || exit 9
# While \`unreadable\` names files of the Documents folder, one a line, its
# download copies the rest, then prints rclone v1.75.1's lines for files it
# could not open and a name Drive holds twice, and exits 1 as rclone did.
if [[ -f "$cs/unreadable" && \${3:-} == copy && \${5:-} == vgsdrive:Documents ]]; then
  mapfile -t gone <"$cs/unreadable"
  skip=()
  for rel in "\${gone[@]}"; do skip+=(--exclude "/\$rel"); done
  "$host_rclone" "\$@" "\${skip[@]}" || exit 9
  why="failed to open source object: can't read dangling shortcut"
  for n in 1 2 3; do
    printf '2026/10/13 00:03:27 NOTICE: %s: Duplicate object found in source - ignoring\\n' "Plans/Budget copy.xlsx" >&2
    for rel in "\${gone[@]}"; do printf '2026/10/13 00:04:59 ERROR : %s: Failed to copy: %s\\n' "\$rel" "\$why" >&2; done
    printf '2026/10/13 00:04:59 ERROR : Attempt %s/3 failed with %s errors and: %s\\n' "\$n" "\${#gone[@]}" "\$why" >&2
  done
  printf '2026/10/13 00:04:59 NOTICE: Failed to copy with %s errors: last error was: %s\\n' "\${#gone[@]}" "\$why" >&2
  exit 1
fi
list= remote=
for a in "\$@"; do
  case "\$a" in
    lsjson) list=1 ;;
    vgsdrive:*) remote="\${a#vgsdrive:}" ;;
  esac
done
[[ -n \$list ]] || exec "$host_rclone" "\$@"
listing="\$("$host_rclone" "\$@")" || exit
printf '%s' "\$listing" | "$host_node" -e '
const fs = require("fs"), path = require("path"), dir = process.argv[1];
const items = JSON.parse(fs.readFileSync(0, "utf8"));
for (const item of items) item.ID = String(fs.statSync(path.join(dir, item.Path)).ino);
process.stdout.write(JSON.stringify(items));' "$drive/\$remote"
SH
  chmod 755 "$shim/rclone"
  sentinel_stand_over "$shim/secret-tool" <<SH
#!/usr/bin/env bash
if [[ \${1:-} == search && \${3:-} == vgs-cloud-sync && \$# -eq 5 ]]; then
  if [[ -f "$cs/secrets/\$5" ]]; then
    printf '[/1]\\nlabel = VGS Cloud Sync %s\\nsecret = %s\\n' "\$5" "\$(head -n1 "$cs/secrets/\$5")"
    printf 'attribute.service = vgs-cloud-sync\\nattribute.account = %s\\n' "\$5" >&2
    u="\$(sed -n 2p "$cs/secrets/\$5")"; [[ -z \$u ]] || printf 'attribute.user = %s\\n' "\$u" >&2
  fi
  exit 0
fi
if [[ \${1:-} == clear && \${2:-} == service && \${3:-} == vgs-cloud-sync && \${4:-} == account && \$# -eq 5 ]]; then
  if [[ -f "$cs/secrets/\$5" ]]; then rm -f -- "$cs/secrets/\$5"; exit 0; fi
  exit 1
fi
if [[ \${1:-} == store ]]; then
  shift
  [[ \${1:-} == --label=* ]] && shift
  account= user=
  while [[ \$# -gt 1 ]]; do
    case "\$1" in
      account) account="\$2" ;;
      user) user="\$2" ;;
    esac
    shift 2
  done
  if [[ -n \$account ]]; then
    secret="\$(cat)"
    printf '%s\\n' "\$secret" >"$cs/secrets/\$account"
    [[ -z \$user ]] || printf '%s\\n' "\$user" >>"$cs/secrets/\$account"
    exit 0
  fi
fi
case "\${1:-}" in search) exit 0 ;; lookup) exit 1 ;; esac
exit 1
SH
  csr() { env -i HOME="$home" PATH="$shell_start_path" LANG=C.UTF-8 XDG_RUNTIME_DIR="$rt_dir" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" node "$tree/shell/plugins/vgs.cloud-sync/bin/cloud-sync" "$@" >/dev/null 2>>"$cs/runner.err"; }
  cs_keys() {
    local a
    for a in client-id client-secret; do printf 'stand-in\n' >"$cs/secrets/$a"; done
    printf '{"access_token":"x","refresh_token":"y"}\na.person@example.com\n' >"$cs/secrets/token"
  }
  # One pair's Drive folder carries its name and one's does not, so the
  # shots show both forms of a pair's second line.
  cs_pairs() {
    csr pair-add --definition "{\"id\":\"documents\",\"label\":\"Documents\",\"remote\":\"Documents\",\"local\":\"$home/cloudsync-$m/Drive/Documents\"}" || fail "cloudsync scene: pair documents"
    csr pair-add --definition "{\"id\":\"uploads\",\"label\":\"Agent uploads\",\"remote\":\"VGS/Uploads\",\"local\":\"$home/cloudsync-$m/inbox/agent-uploads\"}" || fail "cloudsync scene: pair uploads"
  }
  printf 'Return filed.\n' >"$drive/Documents/Taxes/2025 return.pdf"
  printf '# Notes\n' >"$drive/Documents/notes.md"
  printf 'budget\n' >"$drive/Documents/budget.xlsx"
  printf 'report\n' >"$home/cloudsync-$m/inbox/agent-uploads/report.md"
  expect "Cloud Sync is enabled for its images" ok ipc shell setPluginEnabled vgs.cloud-sync true
  expect "Cloud Sync's widget is placed for its images" ok ipc shell setPluginPlaced vgs.cloud-sync true
  csr status || fail "cloudsync scene: first status"

  # Nothing installed, no folder pair, no key.
  cs_shots "$m" 1-first-run not-set-up
  # Hourly sync on and two folder pairs, no key or sign-in.
  csr install || fail "cloudsync scene: install"
  cs_pairs
  csr run || true
  cs_shots "$m" 2-no-keys authorization-required credential-absent
  # Keys and sign-ins stored, no folder pair.
  cs_keys
  csr pair-remove documents || fail "cloudsync scene: remove documents"
  csr pair-remove uploads || fail "cloudsync scene: remove uploads"
  csr status || fail "cloudsync scene: status without pairs"
  cs_shots "$m" 3-no-pair no-pairs
  # Both pairs synced, nothing to review.
  cs_pairs
  csr run || fail "cloudsync scene: first run"
  cs_shots "$m" 4-empty-review idle none
  csr pause || fail "cloudsync scene: pause"
  cs_shots "$m" 5-paused paused
  csr resume || fail "cloudsync scene: resume"
  # A run held inside its copy.
  rm -f -- "$cs/release"; : >"$cs/block"
  ( csr run ) &
  runner=$!
  cs_shots "$m" 6-syncing running
  : >"$cs/release"
  wait "$runner" || true
  rm -f -- "$cs/block" "$cs/release"
  : >"$cs/fail"
  csr run || true
  cs_shots "$m" 7-error error
  rm -f -- "$cs/fail"
  # Set up, with a change on both sides, a local deletion, a Drive
  # deletion and a Drive rename to a long name to review.
  printf '# Notes, edited here\n' >"$home/cloudsync-$m/Drive/Documents/notes.md"
  touch -d '2000-01-01T00:00:00Z' -- "$home/cloudsync-$m/Drive/Documents/notes.md"
  rm -f -- "$drive/Documents/budget.xlsx"
  printf '# Notes, edited on Drive\n' >"$drive/Documents/notes.md"
  rm -f -- "${home:?}/cloudsync-$m/Drive/Documents/Taxes/2025 return.pdf"
  mv -- "$drive/VGS/Uploads/report.md" "$drive/VGS/Uploads/October-planning-meeting-report-with-every-agent-task-its-owner-and-its-due-date.md"
  csr run || fail "cloudsync scene: review run"
  cs_shots "$m" 8-review review
  # Two Drive files the download cannot open and a name Drive holds twice.
  # A runner that reads rclone's lines for them ends the pair synced with
  # the files to review; one that does not ends it as a failed sync.
  mkdir -p -- "$drive/Documents/Plans"
  printf 'plan\n' >"$drive/Documents/Plans/Launch plan – final.pdf"
  printf 'offsite\n' >"$drive/Documents/Plans/Team offsite.pdf"
  printf 'budget copy\n' >"$drive/Documents/Plans/Budget copy.xlsx"
  printf '%s\n' "Plans/Launch plan – final.pdf" "Plans/Team offsite.pdf" >"$cs/unreadable"
  csr run || true
  if tree_has shell/plugins/vgs.cloud-sync/bin/cloud-sync '"unreadable-on-drive"'; then
    cs_shots "$m" 8-unreadable review
  else
    cs_shots "$m" 8-unreadable error
  fi
  rm -f -- "$cs/unreadable"
  # The folder pair list cut short, so it is not JSON.
  pairs_file="$home/.config/vgshell/cloud-sync/pairs.json"
  printf '{"pairs": [{"id": "documents", "label": "Documents", "direction": "pull",' >"$pairs_file"
  csr status || true
  cs_shots "$m" 9-pairs-invalid error pairs-invalid
  csr pairs-reset || fail "cloudsync scene: pairs-reset"
  rm -f -- "$cs/secrets/client-id" "$cs/secrets/client-secret" "$cs/secrets/token"
  for a in pull-client-id pull-client-secret pull-token upload-client-id upload-client-secret upload-token; do printf 'old\n' >"$cs/secrets/$a"; done
  printf '{"pairs":[{"id":"documents","label":"Documents","direction":"pull","remote":"Documents","local":"%s"}]}\n' "$home/cloudsync-$m/Drive/Documents" >"$pairs_file"
  csr run || true
  cs_shots "$m" 10-migrated authorization-required credential-absent

  rm -f -- "$pairs_file".damaged-* "$home/.config/systemd/user/vgs-cloud-sync.service" "$home/.config/systemd/user/vgs-cloud-sync.timer" "$cs"/secrets/*
  # The service watches status.json; its directory stays so the watch holds.
  rm -rf -- "${home:?}/.local/state/vgshell/cloud-sync/pairs" "${home:?}/.config/vgshell/cloud-sync"
  rm -f -- "${home:?}/.local/state/vgshell/cloud-sync/control.json"
  csr status || true
  expect "Cloud Sync reads its record again after its images" ok ipc vgs.cloud-sync invoke refresh ""
  expect "Cloud Sync's widget is unplaced after its images" ok ipc shell setPluginPlaced vgs.cloud-sync false
  expect "Cloud Sync is disabled after its images" ok ipc shell setPluginEnabled vgs.cloud-sync false
  sentinel_restore "$shim/secret-tool"
  rm -f -- "$shim/rclone"
  automations_stand_ins_restore "$cs/systemd"
}

# Idle covers stay off during page captures. A lock or screensaver would
# cover a long page set; no sleep hook should run from its idle state.
lock_row_quiet() {
  python3 - "$home/.config/vgshell/shell.json" "$repo" <<'PY' || fail "writing the quiet idle rows failed"
import json, os, sys
path = sys.argv[1]
config = json.load(open(path))
rows = config.setdefault("plugins", [])
for id, values in (("vgs.lock", {"lockBeforeSleep": False, "idleLockSeconds": 0}), ("vgs.screensaver", {"idleEnabled": False})):
    if not os.path.isfile(os.path.join(sys.argv[2], "shell/plugins", id, "manifest.json")): continue
    row = next((r for r in rows if r.get("id") == id), None)
    if row is None:
        row = {"id": id}
        rows.append(row)
    row.update(values)
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PY
}

# Release the probe through its fixture owner. The product judge decides
# which requested provider conflicts with the fixture's capabilities.
capture_probe_release() {
  local conflicts
  [[ ${#enable_ids[@]} -gt 0 && -f $home/.config/vgshell/plugins/acme.probe/manifest.json ]] || return 0
  conflicts="$("$node_bin" - "$checkout" "$repo" "$home/.config/vgshell/plugins/acme.probe/manifest.json" "${enable_ids[@]}" <<'JS'
const fs = require("node:fs");
const path = require("node:path");
const [checkout, tree, fixture, ...ids] = process.argv.slice(2);
const { load } = require(path.join(checkout, "bin/lib/qml-library.js"));
const logic = load(path.join(tree, "shell/Core/PluginLogic.js"));
const probe = JSON.parse(fs.readFileSync(fixture, "utf8"));
const held = Object.fromEntries(probe.capabilities.map(name => [name, probe.id]));
console.log(ids.filter(id => logic.lendRefusal(held, JSON.parse(fs.readFileSync(path.join(tree, "shell/plugins", id, "manifest.json"), "utf8"))) !== "").join(","));
JS
  )" || { fail "the requested providers' fixture conflicts are unreadable"; return 1; }
  [[ -n $conflicts ]] || return 0
  expect "the probe releases its capabilities for $conflicts" ok ipc shell setPluginEnabled acme.probe false
  expect_poll "the probe's exclusive providers are gone" False record_exists acme.probe
}

# Apply requested states after every scene fixture has been installed.
# On-demand window and pane hosts own their own first build in the scene.
capture_plugin_states() { # MODE
  local id active_bar live
  active_bar="$(ipc shell listShellConfig | py_reply 'import json,sys; print(json.load(sys.stdin)["bar"]["id"])')" || { fail "the active bar is unreadable"; return 1; }
  for id in "${disable_ids[@]}"; do
    if [[ $id == "$active_bar" ]]; then
      printf 'sandbox-shots: state mode=%s id=%s requested=off reason=active-bar\n' "$1" "$id"
      continue
    fi
    expect "disabling $id for the run is allowed" ok ipc shell setPluginEnabled "$id" false
    expect_poll "$id publishes off for the run" False plugin_enabled "$id"
    expect_poll "$id has no instance for the off run" False record_exists "$id"
  done
  capture_probe_release || return 1
  for id in "${enable_ids[@]}"; do
    expect "enabling $id for the run is allowed" ok ipc shell setPluginEnabled "$id" true
    expect_poll "$id publishes on for the run" True plugin_enabled "$id"
    live="$(python3 -c 'import json,sys; kinds=json.load(open(sys.argv[1]))["kinds"]; print(any(k in kinds for k in ("service","bar","background")))' "$repo/shell/plugins/$id/manifest.json")" || { fail "the $id host kinds are unreadable"; return 1; }
    [[ $live != True ]] || expect_poll "$id is built for its live host" True record_exists "$id"
  done
  close_notices
}

# The published inventory supplies actual state for every plugin, including
# required active surfaces not present in a requested state list.
capture_state_record() { # SCENE MODE
  local state theme
  theme="$(ipc smoke themeName)" || { fail "the capture theme is unreadable"; return 1; }
  state="$(ipc shell listPlugins | py_reply 'import json,sys
rows=json.load(sys.stdin).get("plugins")
enabled,disabled=(set(a.split()) for a in sys.argv[1:])
def state(r):
    value={k:r[k] for k in ("id","enabled","kinds","requirements")}
    value["requested"]="on" if r["id"] in enabled else "off" if r["id"] in disabled else "unchanged"
    value["reason"]="active-bar" if value["requested"]=="off" and r["enabled"] and "bar" in r["kinds"] else ""
    return value
print("absent" if not isinstance(rows,list) or not rows else json.dumps([state(r) for r in rows],sort_keys=True,separators=(",",":")))' "${enable_ids[*]}" "${disable_ids[*]}")" || { fail "the capture plugin state is unreadable"; return 1; }
  [[ $state == \[* ]] || { fail "the capture plugin state is $state"; return 1; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$capture_source" "$theme" "${enable_ids[*]}" "${disable_ids[*]}" "$state" >>"$SHOT_DIR/plugin-states.tsv"
}
for scene in "${scenes[@]}"; do
  case $scene in
    bar) need_setup launcher; need_setup panels; need_setup bar ;;
    theme-previews) need_setup launcher; need_setup panels; need_setup bar; need_setup ai-usage ;;
    tooltips) need_setup launcher; need_setup panels; need_setup bar; need_setup tooltips ;;
    jarvis-causes) need_setup bar; need_setup settings; need_setup jarvis-causes ;;
    focus) need_setup settings ;;
    focus-open) need_setup focus-open ;;
    flyout-titles) need_setup panels ;;
    narrow) for s in launcher panels bar devtools dialog notifications gallery; do need_setup "$s"; done
      ! scene_ships lock || need_setup lock ;;
    *) need_setup "$scene" ;;
  esac
done
# What vsys's summary reads as in the warden's panel: one warning, as
# rows/agent-warden.sh's stand-in answers.
shots_vsys_line='vsys found one warning on this computer.'
for scene in "${setups[@]}"; do
  case $scene in
    gallery|manager|polkit|greeter|theme-browser|wallpaper-browser|setup-tab) ;;
    capture)
      expect "enabling Capture for its image is allowed" ok ipc shell setPluginEnabled vgs.capture true
      expect "Capture is hidden from the baseline image" ok ipc shell setPluginPlaced vgs.capture false
      expect_poll "Capture is built for its image" True record_exists vgs.capture ;;
    bluetooth)
      # The scene runs only once the fakes are up, the device guard reads
      # the shell inside the sandbox and the system steps probe the fakes'
      # system tree: enabling vgs.bluetooth starts those probes.
      bluetooth_tree=""
      if devices_ready bluetooth-shot && bluetooth_tree="$(devices_system_tree)"; then
        bluetooth_shot_ready=true
        expect "a nearby keyboard joins the mock" "$bluez_adapter_path/dev_00_1B_66_AA_BB_04" bluez add-device 00:1B:66:AA:BB:04 "Desk Keyboard"
      else
        fail "the Bluetooth shot is skipped: its fakes, the device guard or the fakes' system tree failed: ${bluetooth_tree:-unread}"
      fi ;;
    printers)
      printers_tree=""
      if devices_ready printers-shot && printers_tree="$(devices_system_tree)"; then
        printers_shot_ready=true
        device_reply systemctl 0 "" is-active --quiet cups.service
      else
        fail "the Printers shots are skipped: their fakes, the device guard or the fakes' system tree failed: ${printers_tree:-unread}"
      fi ;;
    clipboard)
      # Copies on the nested instance's own clipboard: wl-copy runs with
      # the nested socket alone and keeps no stream of this run's.
      command -v wl-copy >/dev/null && command -v wl-paste >/dev/null || fail "the clipboard image needs wl-copy and wl-paste"
      clipboard_total() { ipc vgs.clipboard invoke rows '' | py_reply 'import json,sys; print(json.load(sys.stdin)["total"])'; }
      clipboard_copy() { "${shell_env[@]}" wl-copy "$@" >/dev/null 2>&1 </dev/null; }
      solid_png "$sandbox/shots-clipboard.png" 320 200 86 130 150 || fail "drawing the clipboard image's picture failed"
      expect "enabling the clipboard history for its image is allowed" ok ipc shell setPluginEnabled vgs.clipboard true
      expect_poll "the clipboard history is built for its image" True record_exists vgs.clipboard
      expect_poll "the clipboard history's store is ready" '"ready"' ipc smoke readInstance service vgs.clipboard store
      clipboard_before="$(clipboard_total)" || clipboard_before=0
      clipboard_copy "Meeting notes: ship the release on Friday"
      expect_poll "the first copy is recorded" "$((clipboard_before + 1))" clipboard_total
      "${shell_env[@]}" wl-copy --type image/png >/dev/null 2>&1 <"$sandbox/shots-clipboard.png"
      expect_poll "the picture is recorded" "$((clipboard_before + 2))" clipboard_total
      clipboard_copy "https://example.org/docs/getting-started"
      expect_poll "the link is recorded" "$((clipboard_before + 3))" clipboard_total
      clipboard_copy "ssh deploy@staging.example.org"
      expect_poll "the command line is recorded" "$((clipboard_before + 4))" clipboard_total
      clipboard_copy "$(printf 'function greet(name) {\n    return "Hello, " + name + "!";\n}\n\nconsole.log(greet("world"));')"
      expect_poll "the code is recorded" "$((clipboard_before + 5))" clipboard_total
      clipboard_pin="$(ipc vgs.clipboard invoke rows 'Meeting notes' | py_reply 'import json,sys; print(json.load(sys.stdin)["rows"][0]["id"])')" || fail "the entry to pin is unreadable"
      expect "the first copy is pinned" ok ipc vgs.clipboard invoke pin "$clipboard_pin" ;;
    traffic)
      cp -- "$checkout/scripts/smoke/fixtures/traffic/allow.sh" "$shim/bandwhich"
      cp -- "$checkout/scripts/smoke/fixtures/traffic/Service.qml" "$repo/shell/plugins/vgs.traffic/Service.qml"
      mkdir -p -- "$repo/shell/plugins/vgs.traffic/tui"
      cp -- "$checkout/scripts/smoke/fixtures/traffic/allow.sh" "$repo/shell/plugins/vgs.traffic/tui/allow.sh"
      python3 - "$repo/shell/plugins/vgs.traffic/manifest.json" <<'PY2' || fail "planting Traffic's fixture manifest failed"
import json, sys
path = sys.argv[1]
manifest = json.load(open(path))
if "service" not in manifest["kinds"]: manifest["kinds"].append("service")
manifest["entryPoints"]["service"] = "Service.qml"
if "ipc" not in manifest["capabilities"]: manifest["capabilities"].append("ipc")
manifest["tui"] = {"capture": {"script": "tui/allow.sh", "title": "Allow traffic capture"}, "bandwhich": {"script": "tui/allow.sh", "title": "All network traffic"}}
manifest["status"]["capture"]["action"] = {"label": "Allow", "tui": "capture"}
json.dump(manifest, open(path, "w"))
PY2
      tree_rescan "Traffic's fixture is scanned"
      expect "enabling Traffic for its design is allowed" ok ipc shell setPluginEnabled vgs.traffic true
      expect "Traffic's widget is placed" ok ipc shell setPluginPlaced vgs.traffic true
      expect "enabling Settings for Traffic's design is allowed" ok ipc shell setPluginEnabled vgs.settings true
      expect_poll "Traffic's service is built" True record_exists vgs.traffic ;;
    ai-usage)
      # The usage helper of the sandbox's copy asks the endpoint stand-in,
      # its origin edited as rows/ai-usage.sh edits it, and Codex's sign-in
      # is read through the Codex stand-in; spawn's process group ends with
      # the sandbox. Each account's figures and reset times are the
      # stand-ins' answers relative to the request.
      usage_dir="$sandbox/shots-ai-usage"
      mkdir -p -- "$usage_dir"
      printf 'relative\n' >"$usage_dir/mode"
      spawn "$usage_dir/endpoint.log" "$node_bin" "$checkout/scripts/fixtures/ai-usage/endpoint.js" "$usage_dir/port" "$usage_dir/mode" "$usage_dir/requests"
      usage_port() { if [[ -s $usage_dir/port ]]; then echo ready; else echo waiting; fi; }
      expect_poll "the stand-in usage endpoint listens" ready usage_port
      python3 "$checkout/scripts/smoke/fixtures/ai-usage/edit.py" "$repo/shell/plugins/vgs.ai-usage/backend/usage.js" 'const ORIGIN = "https://api.anthropic.com";' "const ORIGIN = \"http://127.0.0.1:$(cat -- "$usage_dir/port")\";" || fail "pointing the usage helper at the stand-in failed"
      ln -sfn -- "$checkout/scripts/fixtures/ai-usage/codex" "$shim/codex"
      # A published gateway-shaped reading plants API billing without a
      # keyring or a live Vercel request, in this sandbox copy alone.
      python3 "$checkout/scripts/smoke/fixtures/ai-usage/edit.py" "$repo/shell/plugins/vgs.ai-usage/backend/usage.js" '    return { accounts, partial, gatewayKey };' '    accounts.push({ id: "gateway-shots", provider: "gateway", label: "AI Gateway", email: "", state: "ok", windows: [{ name: "credits", usedPercent: 64, resetsAt: null }], credits: null, details: { gateway: { balance: 36, totalUsed: 64 } } });
    return { accounts, partial, gatewayKey };' || fail "planting the API gateway reading failed"
      python3 - "$home" <<'PY' || fail "planting the AI Usage sign-ins failed"
import json, os, sys, time
home = sys.argv[1]
for folder, plan in ((".claude", "max"), (".claude-work", "pro")):
    os.makedirs(os.path.join(home, folder), exist_ok=True)
    token = "sk-ant-oat01-shots-" + folder.strip(".") + "-" + "0" * 16
    json.dump({"claudeAiOauth": {"accessToken": token, "refreshToken": "shots-refresh", "expiresAt": int(time.time() * 1000) + 3600000,
               "scopes": ["user:inference"], "subscriptionType": plan}}, open(os.path.join(home, folder, ".credentials.json"), "w"))
os.makedirs(os.path.join(home, ".codex"), exist_ok=True)
json.dump({"OPENAI_API_KEY": None, "tokens": {"access_token": "shots-access"}}, open(os.path.join(home, ".codex", "auth.json"), "w"))
open(os.path.join(home, ".codex", "stand-in-mode"), "w").write("relative\n")
os.makedirs(os.path.join(home, ".codex-api"), exist_ok=True)
json.dump({"OPENAI_API_KEY": "shots-api-key"}, open(os.path.join(home, ".codex-api", "auth.json"), "w"))
open(os.path.join(home, ".codex-api", "stand-in-mode"), "w").write("api-key\n")
PY
      tree_rescan "the AI Usage stand-ins are scanned"
      expect "enabling AI Usage for its dropdown is allowed" ok ipc shell setPluginEnabled vgs.ai-usage true
      expect "AI Usage's widget is placed" ok ipc shell setPluginPlaced vgs.ai-usage true
      expect_poll "AI Usage's service is built" True record_exists vgs.ai-usage
      usage_shot_states() { ipc smoke readInstance service vgs.ai-usage usage | py_reply 'import json,sys; u=json.load(sys.stdin); print("none" if u is None else json.dumps(sorted(a["state"] for a in u["accounts"])))'; }
      expect_poll "every planted account reads as signed in" '["no-plan", "ok", "ok", "ok", "ok"]' usage_shot_states
      expect_poll "AI Usage's widget shows" true ipc smoke readInstance "$(bar_key)" vgs.ai-usage visible ;;
    keyhints)
      for id in vgs.launcher vgs.keyhints; do
        expect "enabling $id for the Key Hints image is allowed" ok ipc shell setPluginEnabled "$id" true
        expect_poll "$id is built for the Key Hints image" True record_exists "$id"
      done ;;
    bar)
      expect "showing the Plugins plug in the bar is allowed" ok ipc shell setPluginPlaced vgs.settings true ;;
    tooltips)
      # Every first-party plugin with a bar widget, enabled and placed; the
      # requirement notices that raises close before any shot.
      for id in "${tooltip_widgets[@]}"; do
        expect "enabling $id for its tooltip is allowed" ok ipc shell setPluginEnabled "$id" true
        expect "$id is placed for its tooltip" ok ipc shell setPluginPlaced "$id" true
      done
      for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
      for _ in $(seq 1 16); do
        shown="$(notice_plugin)" || shown=unread
        [[ $shown == null ]] && break
        expect_poll "the requirement notice of $shown maps" 1 layer_count vgs:notice
        expect_poll "the requirement notice of $shown holds the keyboard" true ipc smoke noticeFocused
        type_keys -k Escape || fail "sending Escape to the requirement notice of $shown failed"
        expect_poll "Escape closes the requirement notice of $shown" closed notice_moved_from "$shown"
      done
      expect_poll "Escape closed every requirement notice" null notice_shown ;;
    panels)
      # The warden reads a fresh status from its runtime dir, with a vsys
      # whose summary names one warning and a notify-send that sends
      # nothing; the updates service reads the planted snapshot, checked
      # now, so no check runs while it is younger than the interval.
      printf '#!/usr/bin/env bash\nexit 0\n' >"$shim/notify-send"
      cat >"$shim/vsys" <<'SH'
#!/usr/bin/env bash
[[ "$*" == "--once --summary" ]] || exit 0
printf '%s\n' '{"schema": "vsys.summary.v1", "time": 1, "verdict": [{"cause": "memory-high", "level": "warn", "subject": "/agents.slice"}], "meters": [], "errors": []}'
SH
      chmod 755 "$shim/notify-send" "$shim/vsys"
      mkdir -p -- "$warden_dir"
      warden_put calm 0 >/dev/null || fail "writing the warden's calm status failed"
      updates_snapshot_plant
      tree_rescan "the panels' stand-ins are scanned"
      for id in vgs.agent-warden vgs.updates; do
        expect "enabling $id is allowed" ok ipc shell setPluginEnabled "$id" true
        expect_poll "$id is built" True record_exists "$id"
      done
      expect_poll "the updates service reads the planted snapshot" 6 updates_pending
      expect "the updates service runs no check" False updates_checking
      expect "enabling vgs.themes for its panel is allowed" ok ipc shell setPluginEnabled vgs.themes true ;;
    devtools)
      devtools_stand_ins
      tree_rescan "the Dev Tools stand-ins are scanned"
      expect "enabling vgs.devtools is allowed" ok ipc shell setPluginEnabled vgs.devtools true
      expect_poll "vgs.devtools is built" True record_exists vgs.devtools ;;
    dialog|by-hand)
      mkdir -p "$home/.config/vgshell/plugins/acme.needs"
      cp -R -- "$fixtures/acme.needs/." "$home/.config/vgshell/plugins/acme.needs/"
      tree_rescan "the needs fixture is scanned"
      expect_poll "the needs fixture is listed" True plugin_known acme.needs ;;
    lock) lock_row_quiet ;;
    page-links)
      # The panel fixture draws one FormRow message holding a page
      # reference to the probe fixture; its handler opens the page only in
      # a tree whose FormRow forwards the reference.
      for fixture in acme.probe acme.surfaces; do
        mkdir -p "$home/.config/vgshell/plugins/$fixture"
        cp -R -- "$fixtures/$fixture/." "$home/.config/vgshell/plugins/$fixture/"
      done
      python3 - "$home/.config/vgshell/plugins/acme.surfaces/Summoned.qml" "$page_links_text" "$page_links_forward" <<'PYEDIT'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
marker = "    Item {\n        id: container\n"
assert text.count(marker) == 1, "the menu anchor container must occur once"
handler = "        onWarningPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)\n" if sys.argv[3] == "true" else ""
row = "    FormRow {\n        id: pageLinkRow\n        width: parent.width\n        labelColumn: false\n        warning: " + repr(sys.argv[2]).replace("'", '"') + "\n        warningTone: \"muted\"\n" + handler + "    }\n"
surface = "    Surface { anchors.fill: parent; z: -1 }\n"
path.write_text(text.replace(marker, surface + row + "    SectionHeader { y: pageLinkRow.height + Theme.stack.section; width: parent.width; text: \"Probe\" }\n" + marker, 1))
PYEDIT
      tree_rescan "the page link fixtures are scanned"
      for id in acme.probe acme.surfaces vgs.settings; do
        expect_poll "$id is listed for the page link" True plugin_known "$id"
        expect "enabling $id for the page link is allowed" ok ipc shell setPluginEnabled "$id" true
        expect_poll "$id is built for the page link" True record_exists "$id"
      done ;;
    tooltip-link)
      # The fixture where the tree ships it; else a widget with the same
      # item and tooltip, which an older tree draws as it drew every line.
      mkdir -p "$home/.config/vgshell/plugins/acme.tiplink"
      if [[ -f $fixtures/acme.tiplink/Widget.qml ]]; then
        cp -R -- "$fixtures/acme.tiplink/." "$home/.config/vgshell/plugins/acme.tiplink/"
      else
        cat >"$home/.config/vgshell/plugins/acme.tiplink/manifest.json" <<'TIPLINK'
{ "schemaVersion": 1, "id": "acme.tiplink", "name": "Tip link", "version": "0.1.0", "author": "acme", "description": "a bar tooltip that names another plugin's page",
  "kinds": ["bar-widget"], "entryPoints": { "bar-widget": "Widget.qml" }, "defaultSection": "right" }
TIPLINK
        cat >"$home/.config/vgshell/plugins/acme.tiplink/Widget.qml" <<'TIPLINK'
import QtQuick
import qs.Ui
BarWidget {
    implicitWidth: item.implicitWidth
    implicitHeight: barSize
    BarItem {
        id: item
        anchors.verticalCenter: parent.verticalCenter
        iconName: "flask-conical"
        label: "Tip link"
        tooltip: "Idle is not set up"
        tooltipDetails: ["Finish on its [Details](page:acme.idle/Details)."]
    }
}
TIPLINK
      fi
      tree_rescan "the tooltip link widget is scanned"
      expect_poll "the tooltip link widget is listed" True plugin_known acme.tiplink
      expect_poll "the tooltip link widget is built in the bar" True record_exists acme.tiplink ;;
    plugin-messages)
      # The clipboard's store needs the nested clipboard's tools, as the
      # clipboard scene does.
      command -v wl-copy >/dev/null && command -v wl-paste >/dev/null || fail "the plugin messages need wl-copy and wl-paste"
      lock_row_quiet
      for id in vgs.notifications vgs.clipboard; do
        expect "enabling $id for the plugin messages is allowed" ok ipc shell setPluginEnabled "$id" true
        expect_poll "$id is built for the plugin messages" True record_exists "$id"
      done ;;
    launcher|notifications)
      # The notifications read the synthetic Slack's workspace list once,
      # when they start, beside a stub libsecret that holds no token: the
      # photo helper refuses any other secret-tool in the sandbox, and with
      # the stub it builds the custom emoji from the synthetic cache alone.
      if [[ $scene == notifications ]]; then
        mkdir -p -- "$home/.config/Slack"
        cp -R -- "$checkout/scripts/smoke/fixtures/slack/." "$home/.config/Slack/"
        printf '#!/usr/bin/env bash\nexit 1\n' >"$shim/secret-tool"
        chmod 755 "$shim/secret-tool"
      fi
      expect "enabling vgs.$scene is allowed" ok ipc shell setPluginEnabled "vgs.$scene" true
      expect_poll "vgs.$scene is built" True record_exists "vgs.$scene" ;;
    focus-open)
      mkdir -p "$home/.config/vgshell/plugins/acme.probe"
      cp -R -- "$fixtures/acme.probe/." "$home/.config/vgshell/plugins/acme.probe/"
      tree_rescan "the comparison fixture is scanned"
      expect_poll "the comparison fixture is listed" True plugin_known acme.probe
      for id in acme.probe vgs.settings; do
        expect "enabling $id for the comparison is allowed" ok ipc shell setPluginEnabled "$id" true
        expect_poll "$id is built for the comparison" True record_exists "$id"
      done ;;
    settings|plugin-pages)
      lock_row_quiet
      # The Settings window lists the probe fixture, a plugin with many
      # grouped settings, and the launcher, a plugin with a key; both
      # enabled, so their pages are editable. Three more fixtures make the
      # plugin list longer than the title menu's nine rows, so the menu
      # scrolls.
      for fixture in acme.probe acme.bare acme.idle acme.locker; do
        mkdir -p "$home/.config/vgshell/plugins/$fixture"
        cp -R -- "$fixtures/$fixture/." "$home/.config/vgshell/plugins/$fixture/"
      done
      # The notifications' page reads the synthetic Slack's workspace list
      # and a stub libsecret, whose `<account> <state>` lines answer the
      # token probe's search as libsecret's secret-tool does: acme's own
      # token stored, globex's absent. A
      # lookup finds no token, so the photo helper calls nothing.
      mkdir -p -- "$home/.config/Slack"
      cp -R -- "$checkout/scripts/smoke/fixtures/slack/." "$home/.config/Slack/"
      printf '%s\n' "slack:T0ACME present" "slack:T0GLOBEX absent" >"$shim/secret-tool.states"
      cat >"$shim/secret-tool" <<SH
#!/usr/bin/env bash
[[ \${1:-} == search && \${2:-} == service && \${3:-} == vgs-notifications && \${4:-} == account && \$# -eq 5 ]] || exit 1
account="\$5" state=absent
while read -r name answer; do [[ \$name == "\$account" ]] && state="\$answer"; done <"$shim/secret-tool.states"
case "\$state" in
  present) printf '[/1]\\nlabel = VGS notifications Slack token\\n'; printf 'attribute.service = vgs-notifications\\nattribute.account = %s\\n' "\$account" >&2 ;;
  locked) printf '[/1]\\nlabel = VGS notifications Slack token\\n'; printf 'secret-tool: Cannot get secret of a locked object\\nattribute.service = vgs-notifications\\nattribute.account = %s\\n' "\$account" >&2 ;;
esac
SH
      chmod 755 "$shim/secret-tool"
      # The Slack token rows belong to the owner-only Slack photos extra
      # (docs/decisions/D075-consumer-features-need-no-developer-setup.md),
      # off by default: the plugins row turns it on, so the page shows the
      # rows. A tree from before the extra passes the key on unread.
      python3 - "$home/.config/vgshell/shell.json" <<'PY'
import json, os, sys
path = sys.argv[1]
config = json.load(open(path))
rows = config.setdefault("plugins", [])
row = next((r for r in rows if r.get("id") == "vgs.notifications"), None)
if row is None:
    row = {"id": "vgs.notifications"}
    rows.append(row)
row["slackPhotos"] = True
with open(path + ".tmp", "w") as out:
    json.dump(config, out)
os.replace(path + ".tmp", path)
PY
      tree_rescan "the fixtures are scanned"
      expect_poll "the probe fixture is listed" True plugin_known acme.probe
      for id in acme.probe vgs.launcher vgs.notifications vgs.settings; do
        expect "enabling $id is allowed" ok ipc shell setPluginEnabled "$id" true
        expect_poll "$id is built" True record_exists "$id"
      done
      if "$has_setup_steps"; then
        # The setup steps' pages: the status fixture, Automations over
        # the harness's loginctl sentinel, which answers lingering off, and
        # a systemctl stand-in that reaches no systemd, and Themes with the
        # chromium target shipped, so a host with a Chromium-family browser
        # and no writer offers its install.
        mkdir -p "$home/.config/vgshell/plugins/acme.status"
        cp -R -- "$fixtures/acme.status/." "$home/.config/vgshell/plugins/acme.status/"
        printf '#!/usr/bin/env bash\nexit 0\n' >"$shim/systemctl"
        chmod 755 "$shim/systemctl"
        cp -R -- "$checkout/themes/targets/chromium" "$repo/themes/targets/chromium"
        tree_rescan "the status fixture is scanned"
        expect_poll "the status fixture is listed" True plugin_known acme.status
        for id in acme.status vgs.automations vgs.agent-warden vgs.devtools; do
          expect "enabling $id is allowed" ok ipc shell setPluginEnabled "$id" true
          expect_poll "$id is built" True record_exists "$id"
        done
        # Agent Warden and Dev Tools require vsys and mise, which the shell
        # finds absent, so enabling them raises the core's requirement
        # notice for each; every one closes before any shot.
        for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
        close_notices
        expect "the themes plugin is disabled to read the shipped target" ok ipc shell setPluginEnabled vgs.themes false
        expect_poll "the themes service is gone" False record_exists vgs.themes
        expect "the themes plugin is enabled with the target shipped" ok ipc shell setPluginEnabled vgs.themes true
        expect_poll "the themes service is built" True record_exists vgs.themes
      fi ;;
  esac
done

sysmon_shot_placed() { ipc shell listShellConfig | py_reply 'import json,sys; l=json.load(sys.stdin)["bar"]["layout"]; print(" ".join(e["id"] for s in ("left","center","right") for e in l.get(s,[])))'; }
# The bar holds System Monitor alone, placed by the shell's own placement
# write: a bar.layout entry holds an id and no setting
# (ConfigLogic.configError). A disabled plugin's entry draws nothing and its
# removal is refused, so it stays.
sysmon_shot_layout() {
  local placed id reply
  placed="$(sysmon_shot_placed)" || { fail "the bar layout is unreadable"; return; }
  [[ $placed != vgs.sysmon ]] || return 0
  for id in $placed; do
    [[ $id != vgs.sysmon ]] || continue
    reply="$(ipc shell setPluginPlaced "$id" false)" || reply="unanswered"
    [[ $reply == ok || $reply == "refused: placed=$id reason=disabled" ]] || fail "the bar gives up $id for the sysmon shots: got $reply"
  done
  expect "System Monitor is placed" ok ipc shell setPluginPlaced vgs.sysmon true
  expect "System Monitor sits at the right" ok ipc shell movePluginWidget vgs.sysmon right 0
  expect_poll "the sysmon layout settles" true ipc smoke configSettled
  # Every write answers with the judge's verdict on the user file as the
  # shell last read it: a refused layout answers user-config=malformed here.
  expect "the judge accepts the written bar layout" ok ipc shell setPluginEnabled vgs.sysmon true
}
# Each setting goes into the plugin's row through the Settings window's own
# write, the one its fields call.
sysmon_shot_settings() { # MASK CPU_TEMP GPU_TEMP UNIT SWAP
  local expected key value
  sysmon_shot_layout
  expect "Settings opens for the sysmon settings" ok ipc shell summon "$settings_kind" vgs.settings '{}'
  while read -r key value; do
    expect "Settings writes System Monitor's $key" ok ipc smoke invokeInstance "$settings_kind" vgs.settings applySetting "{\"id\":\"vgs.sysmon\",\"key\":\"$key\",\"value\":$value}"
  done < <(python3 -c 'import json,sys;m=int(sys.argv[1])
for k,v in [("showCpu",bool(m&1)),("showMemory",bool(m&2)),("showGpu",bool(m&4)),("cpuTemperature",sys.argv[2]=="true"),("gpuTemperature",sys.argv[3]=="true"),("memoryUnit",sys.argv[4]),("showSwap",sys.argv[5]=="true")]: print(k,json.dumps(v))' "$@")
  settings_close
  expect_poll "the sysmon configuration settles" true ipc smoke configSettled
  expected="$(python3 -c 'import json,sys;m=int(sys.argv[1]);print(json.dumps([bool(m&1),bool(m&2),bool(m&4),sys.argv[2]=="true",sys.argv[3]=="true",sys.argv[4],sys.argv[5]=="true"]))' "$@")" || { fail "the sysmon shot settings are unreadable"; return; }
  expect_poll "the sysmon widget has current toggles" "$expected" sysmon_shot_toggles
  expect "the fixture holds the widget status" held ipc smoke holdStatus "$(bar_key)" vgs.sysmon
}
sysmon_shot_toggles() { ipc smoke readInstance "$(bar_key)" vgs.sysmon settings | py_reply 'import json,sys; s=json.load(sys.stdin);print(json.dumps([s.get("showCpu"),s.get("showMemory"),s.get("showGpu"),s.get("cpuTemperature"),s.get("gpuTemperature"),s.get("memoryUnit"),s.get("showSwap")]))'; }
sysmon_shot_fixture() {
  local readings
  readings="$(cat -- "$checkout/scripts/smoke/fixtures/sysmon/$1.json")" || { fail "the $1 fixture is unreadable"; return; }
  expect "the $1 readings publish" ok ipc smoke heldStatusSet readings "$readings"
}
scene_sysmon() {
  local mode="$1" mask name
  tree_rescan "the btop fixture is scanned"
  expect "System Monitor is enabled" ok ipc shell setPluginEnabled vgs.sysmon true
  for mask in 1 2 4 3 5 6 7 0; do
    sysmon_shot_settings "$mask" false false percent false
    sysmon_shot_fixture normal
    name="$(python3 -c 'import sys;m=int(sys.argv[1]);print("-".join(n for b,n in [(1,"cpu"),(2,"memory"),(4,"gpu")] if m&b) or "none")' "$mask")" || { fail "the sysmon reading combination is unreadable"; return; }
    park_pointer
    take "sysmon-$mode-combination-$name"
  done
  sysmon_shot_settings 7 true true percent false
  sysmon_shot_fixture normal
  take "sysmon-$mode-both-temperatures"
  sysmon_shot_settings 7 true false percent false
  take "sysmon-$mode-cpu-temperature"
  sysmon_shot_settings 7 false true percent false
  take "sysmon-$mode-gpu-temperature"
  sysmon_shot_settings 7 true true used true
  take "sysmon-$mode-used-gb-swap"
  sysmon_shot_settings 7 true true percent false
  for name in zero warning danger unknown no-gpu asleep; do
    sysmon_shot_fixture "$name"
    take "sysmon-$mode-$name"
    if [[ $name == asleep || $name == no-gpu || $name == unknown ]]; then
      expect "the widget opens its anchored flyout" ok ipc smoke invokeInstance "$(bar_key)" vgs.sysmon toggle ''
      expect_poll "the System Monitor flyout is built" '"System Monitor"' ipc smoke readDescendant panel vgs.sysmon Pane title
      take "sysmon-$mode-flyout-$name"
      expect "the flyout closes" ok ipc shell hide panel vgs.sysmon
    fi
  done
  sysmon_shot_fixture normal
  expect "the widget opens its detail flyout" ok ipc smoke invokeInstance "$(bar_key)" vgs.sysmon toggle ''
  expect_poll "the System Monitor flyout is built" '"System Monitor"' ipc smoke readDescendant panel vgs.sysmon Pane title
  take "sysmon-$mode-flyout-see-all"
  expect "the flyout closes" ok ipc shell hide panel vgs.sysmon
}

# tui-edges: System Monitor's See all opens the host's btop in the host's
# Ghostty through the real xdg-terminal-exec, first with btop's theme
# target alone shipped and then with Ghostty's beside it, each after one
# `theme apply vgs`. Ghostty pads its grid and keeps the remainder of a
# cell (shell/Core/HyprlandLayer.js, TUI_PADDING) in its own background, so
# the band between the window's edge and btop matches btop only when the
# terminal carries the applied theme. The first window measures that band
# on each side as the lines of the corner's colour, which must differ from
# btop's background there; the second must hold only btop's background in
# the same lines. The launcher runs nothing but System Monitor's btop
# script, byte for byte the sandbox's copy, which execs btop. A last window
# under the catalog's flexoki-light is the light panel. btop draws memory as
# meters (mem_graphs), whose cells up to half the meter hold the gradient's
# start, so the second window's Free meter and the light window's Used
# meter are read as exact colours, as are the light window's process box
# figures, each in a colour of btop's process gradient, and its CPU box
# figures, each in a colour of its CPU or temperature gradient.
tui_edges_windows() { hypr -j clients | py_reply 'import json,sys; print(len([c for c in json.load(sys.stdin) if c["class"] == "org.vgs.tui.wide" and c["mapped"]]))'; }
tui_edges_box() { hypr -j clients | py_reply 'import json,sys; c=[c for c in json.load(sys.stdin) if c["class"] == "org.vgs.tui.wide" and c["mapped"]]; print("%s %d %d %d %d" % (c[0]["address"], c[0]["at"][0], c[0]["at"][1], c[0]["size"][0], c[0]["size"][1]) if len(c) == 1 else "none")'; }
# tui_edges_running COMM: `running` while a process in the fence's PID
# namespace, whose /proc lists no other, is COMM.
tui_edges_running() {
  python3 -c 'import os,sys
names = set()
for p in os.listdir("/proc"):
    if p.isdigit():
        try: names.add(open("/proc/%s/comm" % p).read().strip())
        except OSError: pass
print("running" if sys.argv[1] in names else "absent")' "$1"
}
# tui_edges_file PATH [LINE]: `present` when PATH exists and, given LINE,
# holds it as a whole line; else `absent`.
tui_edges_file() { if [[ -f $1 ]] && { [[ $# -lt 2 ]] || grep -qxF -- "$2" "$1"; }; then echo present; else echo absent; fi; }
# tui_edges_read KIND [ARG...]: one capture of the TUI window at scale 1.
# `drawn BG` once a quarter of the window's middle is BG, which only btop
# paints (theme_background); `band` the depth in pixels of each side's
# lines that hold nothing but the window corner's colour, then that
# colour, as `L R T B RRGGBB`; `sides BG L R T B` the sides whose outer L,
# R, T or B lines hold a pixel other than BG, or `none`; `meter RRGGBB`
# `held` once 16 pixels of the window's lower left, left of two fifths and
# below half, where btop draws memory, disks and network and neither its
# CPU nor its process box, are RRGGBB; `names BG FAINT START MID END` the
# colour of btop's process gradient, drawn on 4 or more pixels of the
# window's lower right quarter, inside its process box, whose contrast on BG
# is lowest, as `lowest=RRGGBB ratio=R.RR`, or `none`. The gradient is
# btop's own: program names, MemB and Cpu% figures take START, MID and END
# by their own share, faded toward FAINT (inactive_fg) in the rows below
# the first. `cpu BG CSTART CMID CEND TSTART TMID TEND` the same reading
# of btop's CPU (cpu_*) and temperature (temp_*) gradients in the window's
# right half above three tenths of its height, inside its CPU box, where
# btop draws the per-core percentages and temperatures.
tui_edges_read() { # drawn BG | band | sides BG L R T B | meter RRGGBB | names BG FAINT START MID END | cpu BG CSTART CMID CEND TSTART TMID TEND
  local box address x y w h
  box="$(tui_edges_box)" || { echo unreadable; return; }
  [[ $box != none ]] || { echo no-window; return; }
  read -r address x y w h <<<"$box"
  # A PPM is binary, which py_reply's text capture would cut at a NUL byte.
  shot_grim "$SHOT_SOCKET" "$SHOT_RUNTIME_DIR" -s 1 -g "$x,$y ${w}x$h" -t ppm - 2>/dev/null | python3 -c '
import sys
data = sys.stdin.buffer.read()
head = data.split(b"\n", 3)
if len(head) != 4 or head[0] != b"P6":
    print("unreadable"); sys.exit()
w, h = map(int, head[1].split())
px = head[3]
if len(px) < w * h * 3:
    print("partial"); sys.exit()
at = lambda x, y: px[3 * (y * w + x):3 * (y * w + x) + 3]
row = lambda y: {at(x, y) for x in range(w)}
col = lambda x: {at(x, y) for y in range(h)}
kind = sys.argv[1]
if kind == "drawn":
    want = bytes.fromhex(sys.argv[2])
    middle = [at(x, y) for y in range(h // 5, h * 4 // 5) for x in range(w // 5, w * 4 // 5)]
    same = sum(1 for p in middle if p == want)
    print("drawn" if middle and same * 4 >= len(middle) else "share=%.3f" % (same / len(middle) if middle else 0))
elif kind == "band":
    corner = at(0, 0)
    def depth(lines):
        n = 0
        for line in lines:
            if line != {corner}: break
            n += 1
        return n
    print(depth(col(x) for x in range(w)), depth(col(x) for x in range(w - 1, -1, -1)),
          depth(row(y) for y in range(h)), depth(row(y) for y in range(h - 1, -1, -1)), corner.hex())
elif kind == "meter":
    want = bytes.fromhex(sys.argv[2])
    same = sum(1 for y in range(h // 2, h) for x in range(w * 2 // 5) if at(x, y) == want)
    print("held" if same >= 16 else "pixels=%d" % same)
elif kind in ("names", "cpu"):
    bg, *stops = (bytes.fromhex(c) for c in sys.argv[2:])
    # btop_theme.cpp generateGradients, its integer division truncating.
    def gradient(a, m, b):
        stops, span = ([a, m, b], 50) if m else ([a, b], 100)
        out = []
        for i in range(101):
            s = 0 if i <= span else 1
            lo, hi, n = stops[s], stops[s + 1], i - span * s
            out.append(bytes(lo[c] + int(n * (hi[c] - lo[c]) / span) for c in range(3)))
        return out
    if kind == "names":
        faint, start, mid, end = stops
        colours, rows = set(gradient(start, mid, end)) | set(gradient(faint, None, start)), range(h // 2, h)
    else:
        colours, rows = set(gradient(*stops[:3])) | set(gradient(*stops[3:])), range(h * 3 // 10)
    count = {}
    for y in rows:
        for x in range(w // 2, w):
            p = at(x, y)
            if p in colours: count[p] = count.get(p, 0) + 1
    def lum(p):
        v = [c / 255 for c in p]
        v = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in v]
        return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
    ratio = lambda p: (max(lum(p), lum(bg)) + 0.05) / (min(lum(p), lum(bg)) + 0.05)
    drawn = [p for p, n in count.items() if n >= 4]
    low = min(drawn, key=ratio, default=None)
    print("none" if low is None else "lowest=%s ratio=%.2f" % (low.hex(), int(ratio(low) * 100) / 100))
else:
    want = bytes.fromhex(sys.argv[2])
    l, r, t, b = map(int, sys.argv[3:7])
    lines = {"left": [col(x) for x in range(l)], "right": [col(w - 1 - x) for x in range(r)],
             "top": [row(y) for y in range(t)], "bottom": [row(h - 1 - y) for y in range(b)]}
    print(",".join(side for side, ls in lines.items() if any(s != {want} for s in ls)) or "none")
' "$@"
}
# tui_edges_band_other BG L R T B RRGGBB: `band` when each depth is above
# zero and the band's colour is not BG.
tui_edges_band_other() {
  [[ $# -eq 6 && $2 =~ ^[1-9][0-9]*$ && $3 =~ ^[1-9][0-9]*$ && $4 =~ ^[1-9][0-9]*$ && $5 =~ ^[1-9][0-9]*$ && $6 != "$1" ]] && echo band || echo "no-band:${*:2}"
}
tui_edges_refused() { if [[ -s $sandbox/tui-edges.refused ]]; then tr '\n' ';' <"$sandbox/tui-edges.refused"; echo; else echo none; fi; }
# tui_edges_slot NAME SLOT: package NAME's terminal colour SLOT, as rrggbb.
tui_edges_slot() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["slots"][sys.argv[2]].lstrip("#").lower())' "$repo/themes/$1/terminal.json" "$2"; }
# tui_edges_key FILE KEY: btop theme FILE's colour KEY, as rrggbb.
tui_edges_key() { sed -n "s/^theme\[$2\]=\"#\([0-9a-fA-F]\{6\}\)\"$/\L\1/p" "$1"; }
# tui_edges_readable KIND BG STOP...: `readable` when the KIND reading's
# lowest colour (names or cpu) reads at 4.5:1 or more on BG, else the
# reading.
tui_edges_readable() {
  local got
  got="$(tui_edges_read "$@")" || return
  if [[ $got =~ ^lowest=[0-9a-f]{6}\ ratio=([0-9]+)\.([0-9]{2})$ ]] && ((10#${BASH_REMATCH[1]}${BASH_REMATCH[2]} >= 450)); then
    echo readable
  else
    echo "$got"
  fi
}
tui_edges_launcher() { ipc shell lent | py_reply 'import json,sys; t=json.load(sys.stdin)["tui"]; print(json.dumps([t["launcher"], t["probing"]]))'; }
tui_edges_open() { # LABEL BG
  expect "$1: no TUI window is open" 0 tui_edges_windows
  expect "$1: the widget opens its flyout" ok ipc smoke invokeInstance "$(bar_key)" vgs.sysmon toggle ''
  expect_poll "$1: the System Monitor flyout is built" '"System Monitor"' ipc smoke readDescendant panel vgs.sysmon Pane title
  settle_hold || { fail "$1: the held mode could not be taken again"; return 1; }
  click_item panel vgs.sysmon Button "See all" || { fail "$1: See all could not be clicked"; return 1; }
  expect_poll "$1: the floating TUI window maps" 1 tui_edges_windows
  expect "$1: the launcher refused no launch" none tui_edges_refused
  expect_poll "$1: btop runs" running tui_edges_running btop
  expect "$1: the flyout closes" ok ipc shell hide panel vgs.sysmon
  expect_poll "$1: btop draws with the applied main_bg #$2" drawn tui_edges_read drawn "$2"
}
tui_edges_close() { # LABEL
  local box address
  box="$(tui_edges_box)" || box=none
  read -r address _ <<<"$box"
  [[ $address == 0x* ]] || { fail "$1: the TUI window's address is unreadable: $box"; return 1; }
  expect "$1: a close dispatch aimed at the TUI window answers ok" ok hypr dispatch "hl.dsp.window.close({ window = \"address:$address\" })"
  expect_poll "$1: the TUI window is gone" 0 tui_edges_windows
  # Ghostty quits with its last window (quit-after-last-window-closed), so
  # the next launch starts a Ghostty that reads its configuration again.
  expect_poll "$1: Ghostty has quit" absent tui_edges_running ghostty
  expect_poll "$1: the core saw the run end" idle key_idle vgs.sysmon/btop
}
scene_tui-edges() { # MODE
  local mode="$1" tool real state="$home/.local/state/vgshell/theme" bg box band before_box status free used light key names cpu
  local light_dir="$home/.config/vgshell/themes/flexoki-light"
  for tool in xdg-terminal-exec ghostty btop; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      printf 'sandbox-shots: scene=tui-edges mode=%s status=not-measured missing=%s\n' "$mode" "$tool"
      unmeasured=$((unmeasured + 1))
      return 0
    fi
  done
  [[ ! -e $shim/btop ]] || { fail "tui-edges: the sysmon scenes' btop stand-in shadows btop"; return; }
  real="$(command -v xdg-terminal-exec)"
  [[ $real != "$tui_terminal" ]] || { fail "tui-edges: the host's xdg-terminal-exec resolves to the stand-in"; return; }
  {
    printf '#!/usr/bin/env bash\n'
    printf 'script=%q refused=%q\n' "$repo/shell/plugins/vgs.sysmon/tui/btop.sh" "$sandbox/tui-edges.refused"
    cat <<'EOF'
plugin="" at=""
args=("$@")
for ((i = 0; i + 1 < ${#args[@]}; i++)); do
  case ${args[i]} in
    --plugin) plugin="${args[i + 1]}" ;;
    --dir) at="${args[i + 1]}" ;;
  esac
done
[[ $plugin == vgs.sysmon && $at == /* && ${!#} == tui/btop.sh && -f $at/tui/btop.sh && ! -L $at/tui/btop.sh ]] &&
  cmp -s -- "$script" "$at/tui/btop.sh" || { printf '%s\n' "$*" >>"$refused"; exit 1; }
EOF
    printf 'exec %q "$@"\n' "$real"
  } >"$tui_terminal.next" && chmod 755 "$tui_terminal.next" && mv -f -- "$tui_terminal.next" "$tui_terminal" || { fail "tui-edges: the terminal launcher could not be put in place"; return; }
  printf 'com.mitchellh.ghostty.desktop\n' >"$home/.config/xdg-terminals.list"
  # Ghostty asks before it closes a window whose program still runs, which
  # would hold the close dispatch below.
  mkdir -p -- "$home/.config/ghostty"
  printf 'confirm-close-surface = false\n' >"$home/.config/ghostty/config"
  mkdir -p -- "$home/.config/btop"
  printf 'color_theme = "vgs"\ntheme_background = true\ntruecolor = true\nmem_graphs = false\n' >"$home/.config/btop/btop.conf"
  expect "System Monitor is enabled" ok ipc shell setPluginEnabled vgs.sysmon true
  expect "System Monitor is placed" ok ipc shell setPluginPlaced vgs.sysmon true
  expect_poll "System Monitor builds its widget" True record_exists vgs.sysmon
  for _ in $(seq 1 25); do [[ $(notice_shown) != null ]] && break; sleep 0.2; done
  close_notices
  # The core probed for xdg-terminal-exec at its start, on the shell's PATH,
  # where the host's stood before any launcher was written.
  expect_poll "tui-edges: the core finds a terminal launcher" '["present", false]' tui_edges_launcher

  cp -R -- "$checkout/themes/targets/btop" "$repo/themes/targets/btop"
  # Under the test-run marker the theme judge refuses every reload hook, so
  # an apply with a target ends partial (3) once the target's files are written.
  status=0; sandbox_vgshell theme apply vgs >/dev/null 2>&1 || status=$?
  expect "btop alone: vgs applies, its reload refused" 3 echo "$status"
  bg="$(sed -n 's/^theme\[main_bg\]="#\([0-9a-fA-F]*\)"$/\1/p' "$state/btop.theme" | tr 'A-F' 'a-f')"
  [[ $bg =~ ^[0-9a-f]{6}$ ]] || { fail "tui-edges: the applied btop.theme names no main_bg"; return; }
  expect "btop alone: Ghostty's theme is not written" absent tui_edges_file "$state/ghostty.conf"
  tui_edges_open "btop alone" "$bg" || return
  settle_hold || { fail "btop alone: the held mode could not be taken again"; return; }
  band="$(tui_edges_read band)"
  before_box="$(tui_edges_box)"
  printf 'sandbox-shots: tui-edges mode=%s case=btop-alone window=%s band=%s main_bg=%s\n' "$mode" "${before_box#* }" "$band" "$bg"
  read -r -a band <<<"$band"
  expect "btop alone: the band is a colour other than btop's" band tui_edges_band_other "$bg" "${band[@]}"
  expect "btop alone: every side holds a pixel other than btop's background" left,right,top,bottom tui_edges_read sides "$bg" "${band[@]:0:4}"
  take "tui-edges-$mode-btop-alone"
  tui_edges_close "btop alone" || return

  cp -R -- "$checkout/themes/targets/ghostty" "$repo/themes/targets/ghostty"
  status=0; sandbox_vgshell theme apply vgs >/dev/null 2>&1 || status=$?
  expect "btop and Ghostty: vgs applies, their reloads refused" 3 echo "$status"
  expect "btop and Ghostty: Ghostty's background is btop's" "#$bg" sed -n 's/^background = \(#[0-9a-fA-F]*\)$/\L\1/p' "$state/ghostty.conf"
  expect "btop and Ghostty: Ghostty's configuration reads the theme" present tui_edges_file "$home/.config/ghostty/config.ghostty" "config-file = ?$state/ghostty.conf"
  tui_edges_open "btop and Ghostty" "$bg" || return
  settle_hold || { fail "btop and Ghostty: the held mode could not be taken again"; return; }
  box="$(tui_edges_box)"
  expect "btop and Ghostty: the window has the first window's size" "${before_box#* }" echo "${box#* }"
  printf 'sandbox-shots: tui-edges mode=%s case=btop-and-ghostty window=%s band=%s\n' "$mode" "${box#* }" "$(tui_edges_read band)"
  expect "btop and Ghostty: no side holds a pixel other than btop's background" none tui_edges_read sides "$bg" "${band[@]:0:4}"
  free="$(tui_edges_slot vgs color2)" || { fail "tui-edges: vgs names no terminal color2"; return; }
  expect_poll "btop and Ghostty: the Free meter is vgs's terminal.color2 #$free" held tui_edges_read meter "$free"
  printf 'sandbox-shots: tui-edges mode=%s case=btop-and-ghostty theme=vgs main_bg=%s free_meter=%s\n' "$mode" "$bg" "$free"
  take "tui-edges-$mode-btop-and-ghostty"
  tui_edges_close "btop and Ghostty" || return

  light="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tokens"]["palette"]["background"].lstrip("#").lower())' "$repo/themes/catalog/flexoki-light/theme.json")" || { fail "tui-edges: flexoki-light names no palette.background"; return; }
  used="$(tui_edges_slot catalog/flexoki-light color1)" || { fail "tui-edges: flexoki-light names no terminal color1"; return; }
  rm -rf -- "${light_dir:?}"
  sandbox_vgshell theme install flexoki-light >/dev/null || { fail "tui-edges: flexoki-light does not install"; return; }
  status=0; sandbox_vgshell theme apply flexoki-light >/dev/null 2>&1 || status=$?
  expect "btop light: flexoki-light applies, its reloads refused" 3 echo "$status"
  expect "btop light: the applied main_bg is flexoki-light's palette.background" "$light" sed -n 's/^theme\[main_bg\]="#\([0-9a-fA-F]*\)"$/\L\1/p' "$state/btop.theme"
  tui_edges_open "btop light" "$light" || return
  settle_hold || { fail "btop light: the held mode could not be taken again"; return; }
  expect_poll "btop light: the Used meter is flexoki-light's terminal.color1 #$used" held tui_edges_read meter "$used"
  names=("$light")
  for key in inactive_fg process_start process_mid process_end; do names+=("$(tui_edges_key "$state/btop.theme" "$key")"); done
  [[ ${names[*]} =~ ^[0-9a-f]{6}( [0-9a-f]{6}){4}$ ]] || { fail "tui-edges: the applied btop.theme lacks a process colour: ${names[*]}"; return; }
  expect_poll "btop light: every program name and MemB colour reads at 4.5:1 or more on main_bg" readable tui_edges_readable names "${names[@]}"
  cpu=("$light")
  for key in cpu_start cpu_mid cpu_end temp_start temp_mid temp_end; do cpu+=("$(tui_edges_key "$state/btop.theme" "$key")"); done
  [[ ${cpu[*]} =~ ^[0-9a-f]{6}( [0-9a-f]{6}){6}$ ]] || { fail "tui-edges: the applied btop.theme lacks a CPU or temperature colour: ${cpu[*]}"; return; }
  expect_poll "btop light: every per-core percentage and temperature colour reads at 4.5:1 or more on main_bg" readable tui_edges_readable cpu "${cpu[@]}"
  printf 'sandbox-shots: tui-edges mode=%s case=btop-flexoki-light theme=flexoki-light main_bg=%s used_meter=%s names=%s cpu=%s\n' "$mode" "$light" "$used" "$(tui_edges_read names "${names[@]}")" "$(tui_edges_read cpu "${cpu[@]}")"
  take "tui-edges-$mode-btop-flexoki-light"
  tui_edges_close "btop light" || return
  rm -rf -- "${light_dir:?}"

  rm -rf -- "${repo:?}/themes/targets/btop" "${repo:?}/themes/targets/ghostty"
  if [[ -f $tui_terminal_written ]]; then cp -- "$tui_terminal_written" "$tui_terminal"; else rm -f -- "$tui_terminal"; fi
  themes_restore "$mode" "the TUI edge shots"
}

# Title-block spacing uses the actual Pane geometry, including the next
# rendered item, so the capture log states pixels rather than a font guess.
flyout_title_measure() { # MODE HOST ID
  local measured token title
  token="$(ipc smoke themeValue stack.titleSpace)" || { fail "the title token is unreadable"; return; }
  title="$(ipc smoke readDescendant "$2" "$3" Pane title)" || { fail "the $3 title is unreadable"; return; }
  measured="$(ipc smoke descendantGeometry "$2" "$3" | py_reply '
import json,sys
rows=json.load(sys.stdin)
if not isinstance(rows,list):
    print("absent")
    sys.exit(0)
pane=next((i for i,row in enumerate(rows) if row.get("type")=="Pane"),None)
if pane is None:
    print("absent")
    sys.exit(0)
children=[i for i,row in enumerate(rows) if row.get("parent")==pane]
if len(children)<5:
    print("partial")
    sys.exit(0)
block,header,scroll,footer=(children[i] for i in [0,2,3,4])
def within(index,parent):
    at=rows[index].get("parent",-1)
    while at>=0:
        if at==parent: return True
        at=rows[at].get("parent",-1)
    return False
column=next((i for i,row in enumerate(rows) if row.get("type")=="QQuickColumn" and within(i,scroll)),None)
body=None if column is None else next((i for i,row in enumerate(rows) if row.get("parent")==column and row.get("visible") and row["box"][3]>0),None)
following=header if rows[header]["box"][3]>0 else footer if body is None else body
box=rows[block]["box"]
print(json.dumps({"paneBox":rows[pane]["box"],"titleBlockBox":box,"titleGap":rows[following]["box"][1]-box[1]-box[3]}))
')" || { fail "the $3 title geometry is unreadable"; return; }
  printf 'sandbox-shots: title-geometry source=%s theme=%s id=%s title=%s token=%s value=%s\n' "$capture_source" "$1" "$3" "$title" "$token" "$measured"
  expect "the $3 rendered title gap equals its token" True py_reply 'import json,sys; d=json.load(sys.stdin); print(isinstance(d,dict) and d.get("titleGap") == float(sys.argv[1]) and d.get("titleGap",0)>0)' "$token" <<<"$measured"
}
scene_flyout-titles() { # MODE
  local mode="$1"
  tree_rescan "the System Monitor stand-in is scanned"
  expect "System Monitor enables for its title shot" ok ipc shell setPluginEnabled vgs.sysmon true
  sysmon_shot_settings 7 true true percent false
  sysmon_shot_fixture normal
  expect "System Monitor opens for its title shot" ok ipc smoke invokeInstance "$(bar_key)" vgs.sysmon toggle ''
  expect_poll "System Monitor draws its title" '"System Monitor"' ipc smoke readDescendant panel vgs.sysmon Pane title
  park_pointer
  flyout_title_measure "$mode" panel vgs.sysmon
  take_posed "flyout-titles-$mode-system-monitor-opened"
  expect "System Monitor closes after its title shot" ok ipc shell hide panel vgs.sysmon

  devices_ready title-shot || return 0
  device_reply systemctl 0 $'LoadState=loaded\nActiveState=active' show --property=LoadState --property=ActiveState NetworkManager.service
  device_reply nmcli 0 'org.freedesktop.NetworkManager.network-control:yes' -t -f PERMISSION,VALUE general permissions
  expect "Network enables for its title shot" ok ipc shell setPluginEnabled vgs.network true
  expect "Network refreshes its title-shot replies" ok ipc vgs.network invoke refresh ''
  expect_poll "Network reads its allowed permission" '"allowed"' ipc smoke readInstance service vgs.network access
  expect_poll "Network reads its running service" '"running"' ipc smoke readInstance service vgs.network serviceState
  expect "Network is placed for its title shot" ok ipc shell setPluginPlaced vgs.network true
  expect_poll "Network builds its title-shot widget" True record_exists vgs.network
  click_centre "$(bar_key)" vgs.network || fail "Network did not open from its widget"
  expect_poll "Network draws its title" '"Network"' ipc smoke readDescendant panel vgs.network Pane title
  park_pointer
  flyout_title_measure "$mode" panel vgs.network
  take_posed "flyout-titles-$mode-network-opened"
  expect "Network closes after its title shot" ok ipc shell hide panel vgs.network
  expect "Network disables after its title shot" ok ipc shell setPluginEnabled vgs.network false
  device_reply_clear nmcli
  device_reply_clear systemctl

  devices_audio_play
  expect "Sound enables for its title shot" ok ipc shell setPluginEnabled vgs.sound true
  expect "Sound is placed for its title shot" ok ipc shell setPluginPlaced vgs.sound true
  expect_poll "Sound builds its title-shot widget" True record_exists vgs.sound
  click_centre "$(bar_key)" vgs.sound || fail "Sound did not open from its widget"
  title_sound_stream() { ipc smoke itemTexts panel vgs.sound FormRow | py_reply 'import json,sys; print(str(any("Smoke Player" in text for row in json.load(sys.stdin) for text in row)).lower())'; }
  expect_poll "Sound draws its test stream" true title_sound_stream
  expect_poll "Sound draws its title" '"Sound"' ipc smoke readDescendant panel vgs.sound Pane title
  park_pointer
  flyout_title_measure "$mode" panel vgs.sound
  take_posed "flyout-titles-$mode-sound-opened"
  expect "Sound closes after its title shot" ok ipc shell hide panel vgs.sound
  expect "Sound disables after its title shot" ok ipc shell setPluginEnabled vgs.sound false
  kill -- "-$devices_player_pid" 2>/dev/null || true

  expect "Updates opens its window for its title shot" ok ipc shell summon window vgs.updates '{}'
  expect_poll "Updates draws its title" '"Updates"' ipc smoke readDescendant window vgs.updates Pane title
  park_pointer
  flyout_title_measure "$mode" window vgs.updates
  take_posed "flyout-titles-$mode-updates-opened"
  expect "Updates closes after its title shot" ok ipc shell hide window vgs.updates

  # These controls have both a System page and their own titled flyout.
  # Use each actual panel entry point, including the device stand-ins the
  # preceding title scene readied, rather than judging only its System page.
  local id label
  for id in vgs.mouse vgs.keyboard vgs.displays; do
    case $id in
      vgs.mouse) label=Mouse ;;
      vgs.keyboard) label=Keyboard ;;
      vgs.displays) label=Displays ;;
    esac
    expect "$label enables for its title shot" ok ipc shell setPluginEnabled "$id" true
    expect "$label opens for its title shot" ok ipc shell summon panel "$id" '{}'
    expect_poll "$label draws its title" "\"$label\"" ipc smoke readDescendant panel "$id" Pane title
    park_pointer
    flyout_title_measure "$mode" panel "$id"
    take_posed "flyout-titles-$mode-${id#vgs.}-opened"
    expect "$label closes after its title shot" ok ipc shell hide panel "$id"
    expect "$label disables after its title shot" ok ipc shell setPluginEnabled "$id" false
  done
}

# The first shot is the bare desktop; every later shot must differ from the
# one before it, which is what proves grim reads the frame being drawn now.
park_pointer
take "00-desktop"
for mode in "${mode_list[@]}"; do
  set_mode "$mode"
  if [[ ${#enable_ids[@]} -gt 0 || ${#disable_ids[@]} -gt 0 ]]; then capture_plugin_states "$mode"; fi
  for scene in "${scenes[@]}"; do
    scene_desktop "$scene" "$mode" || { fail "the $scene $mode desktop could not be set"; continue; }
    capture_state_record "$scene" "$mode"
    "scene_$scene" "$mode"
  done
done

# No scene may authenticate against the host user: harness.sh's sentinels
# log any call, and a logged one fails the run (rows/auth-sentinel.sh).
if [[ -s $auth_log ]]; then fail "a scene reached an authentication sentinel: $(tr '\n' ';' <"$auth_log")"; else ok "no scene reached an authentication sentinel"; fi
echo "sandbox-shots: dir=$SHOT_DIR shots=$(wc -l <"$SHOT_DIR/shots.tsv" 2>/dev/null || echo 0) failures=$failures hidden=$(awk -F '\t' '$5 == "hidden"' "$SHOT_DIR/shots.tsv" 2>/dev/null | wc -l)"
if [[ $failures -gt 0 && $failures -eq $undrawn ]]; then
  printf 'sandbox-shots: status=not-measured nested-window=not-drawn\n'
  exit 77
fi
[[ $failures -eq 0 ]] || exit 1
[[ $unmeasured -eq 0 ]] || exit 77
