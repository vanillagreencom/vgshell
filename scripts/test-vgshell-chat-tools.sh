#!/usr/bin/env bash
# Controls for the chat and tool targets of `vgshell theme apply`: Vesktop,
# Equibop, Vencord, btop, tmux, Oh My Posh and Obsidian. Each lands its file
# with its encoder and keeps its wiring, links in the application's theme
# directory or tmux's source-file line, and each hook
# reaches only a stub. Obsidian's links stand in every vault its registry
# lists, the entry form's `vaults`. Every detect command, the signal command
# and tmux are stubs on the rows' PATH, under a temporary HOME,
# XDG_CONFIG_HOME and XDG_RUNTIME_DIR, so no row reaches a real application
# or the developer's session. The one real program is a tmux server of the
# suite's own, on a socket under its scratch directory, which reads the
# configuration the apply wired as a login would.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
tmux_bin="$(command -v tmux)" || { echo "test-vgshell-chat-tools: status=not-measured missing=tmux"; exit 77; }
theme_tree btop equibop obsidian oh-my-posh tmux vencord vesktop
live="$state/theme"; uid="$(id -u)"; pending="$state/reload-pending.json"
theme_pkg "$tree/themes/dusk" '{ "schemaVersion": 1, "name": "dusk", "tokens": { "palette": { "accent": "#111111" } } }'
theme_pkg "$tree/themes/nord" '{ "schemaVersion": 1, "name": "nord", "tokens": { "palette": { "accent": "#30a0ff" } } }'

# Each application is detected by a stub of its command, which records a
# run and exits 1, so detection never runs it. The hooks run a real sh, id
# and touch; pkill is a stub recording its arguments that exits with
# $tmp/signal-exit (1, no process matched, when absent). tmux is a stub
# recording every call: `list-sessions` succeeds only while $tmp/tmux-server
# exists, and `source-file` exits with $tmp/tmux-exit, 0 when absent.
hook_tools="$tmp/hook-tools"; mkdir -p "$hook_tools"
for tool in sh id touch; do
  tool_bin="$(command -v "$tool")" || { echo "test-vgshell-chat-tools: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$hook_tools/$tool"
done
for stub in vesktop equibop discord btop oh-my-posh obsidian; do
  printf '#!/bin/sh\n: >"%s/ran-$(basename "$0")"\nexit 1\n' "$tmp" >"$stubs/$stub"
  chmod +x "$stubs/$stub"
done
signals="$tmp/signals"; tmux_calls="$tmp/tmux-calls"
cat >"$stubs/pkill" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$signals"
st=1
[ -f "$tmp/signal-exit" ] && read -r st <"$tmp/signal-exit"
exit "\$st"
EOF
cat >"$stubs/tmux" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmux_calls"
case "\$1" in
list-sessions) [ -f "$tmp/tmux-server" ] ;;
source-file) st=0; [ -f "$tmp/tmux-exit" ] && read -r st <"$tmp/tmux-exit"; exit "\$st" ;;
*) exit 64 ;;
esac
EOF
chmod +x "$stubs/pkill" "$stubs/tmux"
export THEME_PATH="$stubs:$hook_tools:$theme_path"

target_state() { # NAME: the target's state and reason in $tmp/apply.json
  python3 -c 'import json,sys; print(*[(t["state"], t["reason"]) for t in json.load(open(sys.argv[1]))["targets"] if t["name"] == sys.argv[2]][0])' "$tmp/apply.json" "$1"
}
apply_json() { # NAME WANT_EXIT PACKAGE [WANT_FIRST_STDERR]: apply with --json into $tmp/apply.json
  tinst "$1" "$cfg" "$rt_empty" "$2" "$any_out" "${4:-}" theme apply --json "$3"
  tail -n 1 "$tmp/out" >"$tmp/apply.json"
}
links_to() { [[ -L $1 && "$(readlink -- "$1")" == "$2" ]]; } # PATH TARGET
calls_are() { [[ "$(cat "$1")" == "$2" ]]; } # FILE WANT: the lines a stub recorded since the last `: >FILE`
link_time() { stat -c %Y -- "$@" | tr '\n' ' '; } # PATH...: each link's own modification time
none_at_1000() { [[ " $(link_time "$@")" != *" 1000 "* ]]; } # PATH...: no link still holds the time the rows set
disable() { printf '{ "disabledTargets": [%s] }\n' "$1" >"$cfg/vgshell/shell.json"; }
tools="btop equibop obsidian oh-my-posh tmux vencord vesktop"
all_state() { # WANT: every tool target's state and reason, one "name state reason" per target
  local name got=""
  for name in $tools; do got+="$name $(target_state "$name");"; done
  [[ $got == "$1" ]]
}
all_written="btop written None;equibop written None;obsidian written None;oh-my-posh written None;tmux written None;vencord written None;vesktop written None;"

# The configuration home holds the user's own files beside each wiring:
# btop.conf, whose selection alone apply edits, a theme of the user's in Equibop's
# themes directory, a tmux.conf, and an Obsidian registry listing a vault
# with .obsidian, a second one, a vault that is gone, one never opened,
# which has no .obsidian, and a relative path.
cfg="$tmp/cfg-tools"; vaults="$tmp/vaults"
mkdir -p "$cfg/vgshell" "$cfg/btop" "$cfg/equibop/themes" "$cfg/tmux" "$cfg/obsidian" \
  "$vaults/notes/.obsidian/themes" "$vaults/work/.obsidian" "$vaults/fresh"
printf '# owner settings\ncolor_theme = "Default" # choice\nupdate_ms = 1000\n' >"$cfg/btop/btop.conf"
printf '# owner settings\ncolor_theme = "vgs" # choice\nupdate_ms = 1000\n' >"$tmp/btop-selected.conf"
printf '/** @name mine */\n' >"$cfg/equibop/themes/mine.css"
printf 'set -g mouse on\n' >"$cfg/tmux/tmux.conf"
printf 'eval "$(oh-my-posh init bash --config old.json)"\n' >"$tmp/home/.bashrc"
registry() { # VAULT_PATH...: an obsidian.json listing each
  local at=0 path body=""
  for path in "$@"; do body+="${body:+,}\"v$at\":{\"path\":\"$path\",\"ts\":1}"; at=$((at + 1)); done
  printf '{"vaults":{%s}}\n' "$body" >"$cfg/obsidian/obsidian.json"
}
registry "$vaults/notes" "$vaults/work" "$vaults/gone" "$vaults/fresh" "Notes"
notes_theme="$vaults/notes/.obsidian/themes/vgs"; work_theme="$vaults/work/.obsidian/themes/vgs"

: >"$signals"; : >"$tmux_calls"
apply_json "the chat and tool targets land" 0 dusk
check "every tool target is written" all_state "$all_written"
check "the apply is applied" json_is "$tmp/apply.json" 'd["state"] == "applied"'
check "detection never ran an application" test -z "$(find "$tmp" -maxdepth 1 -name 'ran-*' -print)"

# Hex targets retain exact colours; tmux uses readable ANSI roles.
# Each file with the hex6 encoder: dusk's accent is #111111, the table's
# background #000000, foreground #d7d7d9, danger #f43f5e and warning
# #ffb000, and the shipped slots' color1 #f43f5e and color5 #a855f7.
while IFS='|' read -r file want; do
  check "$file holds: $want" grep -qxF -- "$want" "$live/$file"
done <<'EOF'
vesktop.css|    --accent-2: #111111;
vesktop.css|    --bg-4: #000000;
vesktop.css|    --text-2: #d7d7d9;
vesktop.css|    --dnd: #f43f5e;
vesktop.css|    --streaming: #a855f7;
btop.theme|theme[main_bg]="#000000"
btop.theme|theme[hi_fg]="#111111"
btop.theme|theme[used_start]="#f43f5e"
tmux.conf|set -g clock-mode-colour "colour15"
tmux.conf|set -g pane-active-border-style "#{?pane_in_mode,fg=colour3,#{?synchronize-panes,fg=colour1,fg=colour15}}"
oh-my-posh.json|    "accent": "#111111",
obsidian.css|    --interactive-accent: #111111;
obsidian.css|    --text-normal: #d7d7d9;
EOF
check "Equibop and Vencord render the Vesktop file" test "$(cmp -s "$live/vesktop.css" "$live/equibop.css"; echo $?)$(cmp -s "$live/vesktop.css" "$live/vencord.css"; echo $?)" == 00
check "the theme CSS names itself vgs to Vencord's theme list" grep -qxF -- ' * @name vgs' "$live/vesktop.css"
check "the Oh My Posh file is JSON whose segments draw from its palette" python3 -c 'import json,sys; c = json.load(open(sys.argv[1])); s = c["blocks"][0]["segments"]; sys.exit(0 if c["palette"]["danger"] == "#f43f5e" and s[0]["foreground"] == "p:accent" and s[0]["template"] == "{{ .Path }} " else 1)' "$live/oh-my-posh.json"
check "the Obsidian manifest names the theme vgs" python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["name"] == "vgs" else 1)' "$live/obsidian.manifest.json"

# The wiring: a link in each application's own directory, created with its
# parents when absent, and tmux's line last in tmux.conf.
check "Vesktop's theme link stands in its themes directory" links_to "$cfg/vesktop/themes/vgs.css" "$live/vesktop.css"
check "Equibop's theme link stands beside the user's theme" links_to "$cfg/equibop/themes/vgs.css" "$live/equibop.css"
check "the user's Equibop theme stays" test "$(cat "$cfg/equibop/themes/mine.css")" == '/** @name mine */'
check "Vencord's theme link stands in its themes directory" links_to "$cfg/Vencord/themes/vgs.css" "$live/vencord.css"
check "btop's theme link stands in its themes directory" links_to "$cfg/btop/themes/vgs.theme" "$live/btop.theme"
check "btop selects vgs and keeps every other byte" cmp -s "$tmp/btop-selected.conf" "$cfg/btop/btop.conf"
check "Oh My Posh's config link stands in its directory" links_to "$cfg/oh-my-posh/vgs.omp.json" "$live/oh-my-posh.json"
check "tmux.conf takes the source-file line last and keeps its own text" test "$(cat "$cfg/tmux/tmux.conf")" == $'set -g mouse on\n'"source-file -q '$live/tmux.conf'"
check "each opened vault takes the theme's two links" test "$(links_to "$notes_theme/theme.css" "$live/obsidian.css" && links_to "$notes_theme/manifest.json" "$live/obsidian.manifest.json" && links_to "$work_theme/theme.css" "$live/obsidian.css" && echo yes)" == yes
check "a vault that is gone, one never opened and a relative path get nothing" test ! -e "$vaults/gone" -a ! -e "$vaults/fresh/.obsidian" -a ! -e "$cfg/obsidian/Notes" -a ! -e "$cfg/.obsidian"
check "no hookless target is pending" test ! -e "$pending"

# The hooks: btop is signalled by exact name for this user, tmux probes for
# a server before it sources, and with none running nothing is sourced.
check "the btop hook signals btop by exact name for this user" calls_are "$signals" "-USR2 -x -u $uid btop"
check "with no tmux server the hook only probes" calls_are "$tmux_calls" "list-sessions"

# Changed bytes touch the three Discord links, which their clients' watch of
# the themes directory sees, and source the theme into a running tmux
# server. A selection-only btop repair still reloads its settings; unchanged
# Discord and tmux files need no reload.
discord_links=("$cfg/vesktop/themes/vgs.css" "$cfg/equibop/themes/vgs.css" "$cfg/Vencord/themes/vgs.css")
touch -h -d @1000 -- "${discord_links[@]}"
: >"$signals"; : >"$tmux_calls"; : >"$tmp/tmux-server"
apply_json "a changed theme reloads the tool targets" 0 nord
check "a changed theme leaves every tool target written" all_state "$all_written"
check "the Discord hooks touched each link itself" none_at_1000 "${discord_links[@]}"
check "a touched link still names its state file" links_to "$cfg/vesktop/themes/vgs.css" "$live/vesktop.css"
check "a changed theme signals btop again" calls_are "$signals" "-USR2 -x -u $uid btop"
check "a running tmux server sources the theme file" calls_are "$tmux_calls" "list-sessions"$'\n'"source-file -q $live/tmux.conf"
touch -h -d @1000 -- "${discord_links[@]}"
: >"$signals"; : >"$tmux_calls"
printf '# owner settings\ncolor_theme = "Default" # choice\nupdate_ms = 1000\n' >"$cfg/btop/btop.conf"
apply_json "an unchanged theme repairs btop's selection and reloads it" 0 nord
check "a selection-only repair keeps every other btop setting" cmp -s "$tmp/btop-selected.conf" "$cfg/btop/btop.conf"
check "unchanged bytes touch no Discord link" test "$(link_time "${discord_links[@]}")" == "1000 1000 1000 "
check "a selection-only repair signals btop" calls_are "$signals" "-USR2 -x -u $uid btop"
check "unchanged bytes source nothing in tmux" test ! -s "$tmux_calls"

# A source-file that fails leaves tmux pending, and `vgshell theme reload`
# sources it again.
printf '1\n' >"$tmp/tmux-exit"
apply_json "a failing source-file leaves tmux reload-pending" 3 dusk "vgshell: refused: target=tmux reason=reload-failed command=sh status=1"
check "tmux is reload-pending with reload-failed" test "$(target_state tmux)" == "reload-pending reload-failed"
check "the failed reload is pending" test "$(cat "$pending")" == '{"schemaVersion":1,"targets":["tmux"]}'
rm -- "$tmp/tmux-exit"; : >"$tmux_calls"
tinst "reload sources the pending tmux theme" "$cfg" "$rt_empty" 0 "ok reload state=reloaded" "" theme reload
check "reload sourced the theme file" calls_are "$tmux_calls" "list-sessions"$'\n'"source-file -q $live/tmux.conf"
check "a reload that succeeds clears tmux" test ! -e "$pending"
rm -- "$tmp/tmux-server"

# tmux.conf is never created: a plugin manager reading the XDG file first
# would lose its list. With no ~/.tmux.conf either, tmux is skipped.
rm -- "$cfg/tmux/tmux.conf"
apply_json "an absent tmux.conf skips tmux" 0 nord
check "an absent tmux.conf and ~/.tmux.conf skip tmux as unwired" test "$(target_state tmux)" == "skipped wiring-file-absent"
check "an absent tmux.conf stays absent and no ~/.tmux.conf appears" test ! -e "$cfg/tmux/tmux.conf" -a ! -e "$tmp/home/.tmux.conf"
tree_control tmux-creates themes/targets/tmux/target.json '"create": false' '"create": true'
apply_json "the creating tmux mutant applies" 0 dusk
check "the creating tmux mutant writes a tmux.conf" test -f "$cfg/tmux/tmux.conf"
unset THEME_BIN
rm -f -- "$cfg/tmux/tmux.conf"

# A ~/.tmux.conf user is wired there, with the line after every line of
# their own: tmux reads its configuration top to bottom, and inline colours
# in a status-left, as in the owner's line below, beat any style option, so
# the theme drops inline colour styles after the user's lines.
# Flexoki Light comes from the shipped catalog; its label takes the bar's
# active fill, colour4 reversed against the terminal page. tmux_read prints the status-left-style and status-left that
# a fresh server of the suite's own reads from the files a login reads, and
# tmux_options [-f /dev/null] every global session and window option it
# holds, with no configuration file under -f /dev/null. Each server takes a
# socket name of its own, which a file mktemp makes reserves: kill-server
# returns before the server has left its socket, and a server started on
# that socket then exits at once. The sockets stand in $tmp/tmux-<uid>, a
# short path, since a socket path holds at most 107 bytes.
mkdir -p "$tmp/tmux-names"
tmux_run() { env -i PATH="$base_path" HOME="$tmp/home" XDG_CONFIG_HOME="$cfg" TMUX_TMPDIR="$XDG_RUNTIME_DIR/owned" "$tmux_bin" -L "$tmux_name" "$@"; }
tmux_read() {
  tmux_name="$(basename -- "$(mktemp "$tmp/tmux-names/XXXXXX")")"
  tmux_run new-session -d -s probe || return 1
  tmux_run show -gv status-left-style && tmux_run show -gv status-left
  tmux_run kill-server
}
tmux_options() {
  tmux_name="$(basename -- "$(mktemp "$tmp/tmux-names/XXXXXX")")"
  tmux_run "$@" new-session -d -s probe || return 1
  tmux_run show -g && tmux_run show -gw
  tmux_run kill-server
}
user_left='#[fg=black,bg=blue,bold] #S #[bg=default] '
tmux_own=$'set -g mouse on\nset -g status-left "'"$user_left"$'"\nset -g status-right-length 40'
tmux_line="source-file -q '$live/tmux.conf'"
theme_reads=$'fg=colour4,reverse,bold\n #S  '
printf '%s\n' "$tmux_own" >"$tmp/home/.tmux.conf"
tinst "Flexoki Light installs from the catalog" "$cfg" "$rt_empty" 0 "ok installed=flexoki-light path=$cfg/vgshell/themes/flexoki-light" "" theme install flexoki-light
# Controls: the target without fallbacks and last skips a ~/.tmux.conf
# user, and without last puts the line first, where the user's line wins.
tree_control tmux-unwired themes/targets/tmux/target.json ', "fallbacks": [".tmux.conf"], "last": true' ''
apply_json "the fallback-less tmux mutant applies Flexoki Light" 0 flexoki-light
check "the fallback-less tmux mutant skips a ~/.tmux.conf user as unwired" test "$(target_state tmux)" == "skipped wiring-file-absent" -a "$(cat "$tmp/home/.tmux.conf")" == "$tmux_own"
check "the fallback-less tmux mutant leaves the user's session label" test "$(tmux_read | tail -n 1)" == "$user_left"
tree_control tmux-first themes/targets/tmux/target.json ', "last": true' ''
apply_json "the first-line tmux mutant applies Flexoki Light" 0 flexoki-light
check "the first-line tmux mutant puts the line ahead of the user's text" test "$(cat "$tmp/home/.tmux.conf")" == "$tmux_line"$'\n'"$tmux_own"
check "the first-line tmux mutant leaves the user's session label" test "$(tmux_read | tail -n 1)" == "$user_left"
unset THEME_BIN
# The shipped target moves a line an earlier apply put first to the end.
apply_json "Flexoki Light applies over a ~/.tmux.conf wired first" 0 flexoki-light
check "an unchanged tmux file still repairs ~/.tmux.conf" test "$(target_state tmux)" == "unchanged None" -a ! -e "$cfg/tmux/tmux.conf"
check "~/.tmux.conf keeps its text and holds the line once, last" test "$(cat "$tmp/home/.tmux.conf")" == "$tmux_own"$'\n'"$tmux_line"
check "tmux reads Flexoki Light's session label over the user's line" test "$(tmux_read)" == "$theme_reads"
touch -d @1000 -- "$tmp/home/.tmux.conf"
apply_json "Flexoki Light applies again" 0 flexoki-light
check "a line already last is not written again" test "$(stat -c %Y -- "$tmp/home/.tmux.conf")" == 1000
# With both files, tmux reads ~/.tmux.conf and then the XDG tmux.conf, and
# only the XDG file, which the fallback stands behind, takes the line.
printf '%s\n' "$tmux_own" >"$tmp/home/.tmux.conf"
printf 'set -g status-left "#[fg=black,bg=blue] #S "\n' >"$cfg/tmux/tmux.conf"
apply_json "Flexoki Light applies with both tmux files" 0 flexoki-light
check "with both files the XDG tmux.conf takes the line last" test "$(cat "$cfg/tmux/tmux.conf")" == 'set -g status-left "#[fg=black,bg=blue] #S "'$'\n'"$tmux_line"
check "with both files ~/.tmux.conf is left byte for byte" test "$(cat "$tmp/home/.tmux.conf")" == "$tmux_own"
check "with both files tmux keeps the XDG label with Flexoki Light's styles" test "$(tmux_read)" == "${theme_reads% }"
rm -- "$cfg/tmux/tmux.conf" "$tmp/home/.tmux.conf"
# A ~/.tmux.conf that is a relative link into a dotfiles repository is
# written through: the link stays, and the file it names takes the line.
mkdir -p "$tmp/home/.dot/tmux"
printf '%s\n' "$tmux_own" >"$tmp/home/.dot/tmux/.tmux.conf"
ln -s .dot/tmux/.tmux.conf "$tmp/home/.tmux.conf"
apply_json "Flexoki Light applies over a linked ~/.tmux.conf" 0 flexoki-light
check "the linked ~/.tmux.conf stays the same link" test -L "$tmp/home/.tmux.conf" -a "$(readlink -- "$tmp/home/.tmux.conf")" == .dot/tmux/.tmux.conf
check "the file the link names keeps its text and takes the line last" test "$(cat "$tmp/home/.dot/tmux/.tmux.conf")" == "$tmux_own"$'\n'"$tmux_line"
check "tmux reads Flexoki Light's session label through the link" test "$(tmux_read)" == "$theme_reads"
rm -- "$tmp/home/.tmux.conf"

# Every colour a user's lines can set loses to the theme. The colour options
# come from tmux itself: each option of a server with no configuration file
# whose name ends in -style, -colour or -colours, but the cursor shapes and
# the clock's hour format, which hold no colour. The formats are those drawn
# on the status line, the pane borders and the area outside a window. A
# ~/.tmux.conf sets each to colour196: a server reads it from the user's
# lines alone, and none keeps it once the theme is wired.
tmux_options -f /dev/null >"$tmp/tmux-defaults"
colour_options="$(awk '{ sub(/\[[0-9]+\]$/, "", $1); print $1 }' "$tmp/tmux-defaults" | grep -E -- '-(style|colours?)$' | grep -Ev -- '(cursor-style|^clock-mode-style)$' | sort -u)"
formats="status-left status-right status-format[0] message-format window-status-format window-status-current-format window-status-separator pane-border-format window-pane-status-format window-pane-current-status-format fill-character"
lists_all() { # LIST NAME...: whether the newline list LIST holds every NAME
  local name
  for name in "${@:2}"; do grep -qxF -- "$name" <<<"$1" || return 1; done
}
check "tmux lists the colour options the theme sets" lists_all "$colour_options" status-style status-right-style window-status-last-style menu-style popup-style copy-mode-match-style mode-style pane-colours cursor-colour clock-mode-colour
{
  for option in $colour_options; do
    case $option in
      *-colours) printf 'set -g %s[0] colour196\n' "$option" ;;
      *-colour) printf 'set -g %s colour196\n' "$option" ;;
      *) printf 'set -g %s "fg=colour196,bg=colour196"\n' "$option" ;;
    esac
  done
  for option in $formats; do printf 'set -g %s "#[fg=colour196]x"\n' "$option"; done
} >"$tmp/home/.tmux.conf"
user_colours() { # FILE: the option names whose value in FILE holds colour196, one a line
  awk '/colour196/ { sub(/\[[0-9]+\]$/, "", $1); print $1 }' "$1" | sort -u
}
no_user_colour() { # FILE: whether no option in FILE holds colour196; prints each that does
  local kept
  kept="$(user_colours "$1")" || return 1
  [[ -z $kept ]] || { printf '    user colour kept: %s\n' $kept; return 1; }
}
tmux_options >"$tmp/tmux-user"
check "the user's lines alone set every colour option and format" test "$(user_colours "$tmp/tmux-user")" == "$(printf '%s\n' $colour_options ${formats//\[0\]/} | sort -u)"
apply_json "Flexoki Light applies over every user colour" 0 flexoki-light
tmux_options >"$tmp/tmux-themed"
check "no user colour shows through the theme" no_user_colour "$tmp/tmux-themed"
rm -- "$tmp/home/.tmux.conf"

# Obsidian's registry: absent, or listing no opened vault, skips it;
# one that is no vault list fails it and leaves every vault as it stands.
mv -- "$cfg/obsidian/obsidian.json" "$tmp/obsidian.json"
apply_json "an absent vault registry skips Obsidian" 0 dusk
check "an absent registry skips Obsidian as unwired" test "$(target_state obsidian)" == "skipped wiring-file-absent"
registry "$vaults/gone" "$vaults/fresh"
apply_json "a registry of no opened vault skips Obsidian" 0 nord
check "a registry of no opened vault skips Obsidian as unwired" test "$(target_state obsidian)" == "skipped wiring-file-absent"
printf '{"vaults":[' >"$cfg/obsidian/obsidian.json"
apply_json "a registry that is no JSON fails Obsidian" 3 dusk "vgshell: refused: target=obsidian reason=unreadable path=$cfg/obsidian/obsidian.json error=unparseable"
check "an unparseable registry fails Obsidian unreadable" test "$(target_state obsidian)" == "failed unreadable"
check "a failed Obsidian keeps its links in the vault" links_to "$notes_theme/theme.css" "$live/obsidian.css"
cp -- "$tmp/obsidian.json" "$cfg/obsidian/obsidian.json"

# Disabled, Obsidian loses its links and its owned vgs directory in every
# vault, and never a file of the user's there.
printf 'mine\n' >"$work_theme/notes.css"
disable '"obsidian"'
apply_json "a disabled Obsidian" 0 nord
check "a disabled Obsidian is skipped" test "$(target_state obsidian)" == "skipped disabled"
check "a disabled Obsidian removes its vgs directory from a vault holding only its links" test ! -e "$notes_theme" -a -d "$vaults/notes/.obsidian/themes"
check "a disabled Obsidian leaves the user's file and its directory in the other vault" test "$(find "$work_theme" -mindepth 1 -printf '%P ')" == "notes.css "
disable ''
rm -- "$work_theme/notes.css"
apply_json "Obsidian enabled again" 0 dusk
check "the vault links come back" links_to "$notes_theme/theme.css" "$live/obsidian.css"

# Controls: each judge copy drops one rule of the vault wiring, and the row
# that pins it turns.
fresh_vaults() { rm -rf -- "$notes_theme" "$work_theme" "$vaults/gone" "$cfg/.obsidian"; }
fresh_vaults
judge_control vaults-ignored 'if (wiring.vaults === undefined) return (Array.isArray(wiring.dir) ? wiring.dir : [wiring.dir]).map(dir => path.join(base, dir));' 'return (Array.isArray(wiring.dir) ? wiring.dir : [wiring.dir]).map(dir => path.join(base, dir));'
apply_json "the vaults-ignoring mutant applies" 0 nord
check "the vaults-ignoring mutant links under the configuration home, not the vault" test -L "$cfg/.obsidian/themes/vgs/theme.css" -a ! -e "$notes_theme"
fresh_vaults
judge_control unopened-vaults 'vaults.filter(vault => fs.statSync(path.join(vault, first), { throwIfNoEntry: false })?.isDirectory() === true)' 'vaults'
apply_json "the unopened-vaults mutant applies" 0 dusk
check "the unopened-vaults mutant recreates a vault that is gone" test -d "$vaults/gone/.obsidian/themes/vgs"
fresh_vaults
judge_control first-vault-only 'writing(dir, key, () => fs.mkdirSync(dir, { recursive: true }));' 'if (dir !== plan.dirs[0]) continue; writing(dir, key, () => fs.mkdirSync(dir, { recursive: true }));'
apply_json "the first-vault mutant applies" 0 nord
check "the first-vault mutant leaves the second vault unlinked" test -L "$notes_theme/theme.css" -a ! -e "$work_theme"
unset THEME_BIN
apply_json "every vault linked again" 0 dusk
disable '"obsidian"'
judge_control first-vault-dropped 'if (entryState(file, item) === "managed") writing(file, key, () => fs.unlinkSync(file));' 'if (dir === plan.dirs[0] && entryState(file, item) === "managed") writing(file, key, () => fs.unlinkSync(file));'
apply_json "the first-vault-dropping mutant disables Obsidian" 0 nord
check "the first-vault-dropping mutant leaves the second vault's links" test ! -e "$notes_theme" -a -L "$work_theme/theme.css"
disable ''
registry "$vaults/gone"
judge_control no-vault-lands 'if (dirs.length === 0) return "wiring-file-absent";' 'if (false) return "wiring-file-absent";'
apply_json "the no-vault mutant applies" 0 dusk
check "the no-vault mutant reports an unwired Obsidian written" test "$(target_state obsidian)" == "written None"
printf '{"vaults":[' >"$cfg/obsidian/obsidian.json"
judge_control unparseable-as-empty 'if (vaults === null) throw' 'if (vaults === null) return []; if (false) throw'
apply_json "the unparseable-as-empty mutant applies" 0 nord
check "the unparseable-as-empty mutant skips Obsidian instead of failing it" test "$(target_state obsidian)" == "skipped wiring-file-absent"
unset THEME_BIN

rows_done test-vgshell-chat-tools
