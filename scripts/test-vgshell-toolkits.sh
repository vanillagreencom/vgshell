#!/usr/bin/env bash
# The toolkit targets under themes/targets/, accent-color, color-scheme,
# gtk-theme, icons, kcolorscheme, qt5ct and qt6ct, through `vgshell theme
# apply`: each renders its colours with its encoder, is skipped when its
# command is not on PATH, keeps its link where its toolkit reads it, takes a
# package's curated file byte for byte, the qt targets run their reload
# hook, and the four GNOME desktop keys, accent-color, color-scheme,
# gtk-theme and icon-theme, are asserted on every apply, with the icon and
# GTK themes VGS ships linked where GTK looks for them. Every detect command
# and gsettings are stubs on the rows' PATH, XDG_DATA_DIRS is a scratch
# directory, and the hooks' `sh`, `cat`, `touch`, `mkdir` and `ln` act only
# under the temporary HOME and XDG_CONFIG_HOME, so no row reaches a toolkit,
# dconf or the developer's session. The controls at the end apply a tree
# copy whose target.json lacks one rule and require the row's assertion to
# turn.
set -euo pipefail

source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/vgshell-rows.sh"
theme_tree accent-color color-scheme gtk-theme icons kcolorscheme qt5ct qt6ct
live="$state/theme"; home="$tmp/home"
data="$home/.local/share"
shipped_icons="$tree/themes/targets/icons"
shipped_themes="$tree/themes/targets/gtk-theme"

# Detection never runs a command: each detect stub records a run and exits 1.
detected=(kreadconfig6 qt5ct qt6ct)
for stub in "${detected[@]}"; do
  printf '#!/bin/sh\n: >"%s/ran-$(basename "$0")"\nexit 1\n' "$tmp" >"$stubs/$stub"
  chmod +x "$stubs/$stub"
done
for tool in sh cat touch ln; do
  tool_bin="$(command -v "$tool")" || { echo "test-vgshell-toolkits: status=not-measured missing=$tool"; exit 77; }
  ln -s -- "$tool_bin" "$stubs/$tool"
done
# gsettings answers `get SCHEMA KEY` with $gs/KEY, `range SCHEMA KEY` with
# $gs/range-KEY, failing as gsettings does on a key the schema lacks when
# that file is absent, and appends each `set`'s arguments, one line per
# call, to $gs/sets-KEY. Detection never runs it.
gs="$tmp/gsettings"; mkdir -p "$gs"
gs_current="$gs/icon-theme"; gs_sets="$gs/sets-icon-theme"
cs_current="$gs/color-scheme"; cs_sets="$gs/sets-color-scheme"
gt_current="$gs/gtk-theme"; gt_sets="$gs/sets-gtk-theme"
ac_current="$gs/accent-color"; ac_sets="$gs/sets-accent-color"; ac_range="$gs/range-accent-color"
printf "'Adwaita'\n" >"$gs_current"; printf "'default'\n" >"$cs_current"
printf "'adw-gtk3-dark'\n" >"$gt_current"; printf "'blue'\n" >"$ac_current"
# The enum gsettings 50.1 prints for accent-color.
all_accents="$(printf "enum\n'blue'\n'teal'\n'green'\n'yellow'\n'orange'\n'red'\n'pink'\n'purple'\n'slate'")"
printf '%s\n' "$all_accents" >"$ac_range"
cat >"$stubs/gsettings" <<EOF
#!/bin/sh
case "\$1" in
  get) cat -- "$gs/\$3" ;;
  set) printf '%s\n' "\$*" >>"$gs/sets-\$3" ;;
  range) [ -e "$gs/range-\$3" ] || exit 1; cat -- "$gs/range-\$3" ;;
  *) : >"$tmp/ran-gsettings"; exit 1 ;;
esac
EOF
chmod +x "$stubs/gsettings"
with_stubs="$stubs:$theme_path"
# The system data directories a hook searches for an installed theme.
data_dirs="$tmp/data-dirs"; mkdir -p "$data_dirs"
inst_env=(XDG_DATA_DIRS="$data_dirs")

# `dusk` sets only the accent, so every other colour is the shipped default:
# background #000000, text #d7d7d9. `curated` ships toolkit files.
theme_pkg "$tree/themes/dusk" '{ "schemaVersion": 1, "name": "dusk", "tokens": { "palette": { "accent": "#111111" } } }'
theme_pkg "$tree/themes/curated" '{ "schemaVersion": 1, "name": "curated", "tokens": {} }'
mkdir -p "$tree/themes/curated/targets"
printf '[ColorScheme]\nactive_colors=#123456\n' >"$tree/themes/curated/targets/qt6ct.conf"
printf '[General]\nName=Curated\n' >"$tree/themes/curated/targets/kcolorscheme.colors"
printf 'teal\n' >"$tree/themes/curated/targets/accent-color.name"
# flexoki-light, a light package with a blue accent: the tree copy's
# catalog package, copied beside the shipped packages so every tree copy
# below can apply it.
cp -R -- "$tree/themes/catalog/flexoki-light" "$tree/themes/flexoki-light"

cfg="$tmp/cfg-toolkits"; mkdir -p "$cfg/vgshell"
states() { # the apply's `name=state` per target, from $tmp/out's JSON line
  python3 -c 'import json,sys; print(" ".join(t["name"] + "=" + t["state"] for t in json.loads(sys.argv[1])["targets"]))' "$(tail -n 1 "$tmp/out")"
}
file_is() { cmp -s -- "$1" <(printf '%s' "$2"); } # FILE TEXT
links_to() { test -L "$1" && test "$(readlink -- "$1")" == "$2"; } # LINK TARGET
# Every shipped directory under SHIPPED is linked by its own name under INTO.
all_linked() { # SHIPPED INTO
  local dir n=0
  for dir in "$1"/*/; do
    dir="${dir%/}"; n=$((n + 1))
    links_to "$2/${dir##*/}" "$dir" || return 1
  done
  [[ $n -gt 0 ]]
}
# The qt scheme's three role lists each hold 21 `#rrggbb` colours, and the
# active Highlight, role 12, is COLOUR.
qt_scheme_is() { # FILE COLOUR
  python3 - "$1" "$2" <<'PY'
import re, sys
rows = dict(l.rstrip("\n").split("=", 1) for l in open(sys.argv[1]) if "=" in l)
lists = [rows.get(k, "").split(", ") for k in ("active_colors", "inactive_colors", "disabled_colors")]
ok = all(len(l) == 21 and all(re.fullmatch(r"#[0-9a-f]{6}", c) for c in l) for l in lists)
sys.exit(0 if ok and lists[0][12] == sys.argv[2] else 1)
PY
}
# Every colour of the KDE scheme is `#rrggbb`, and the selection's
# background is COLOUR.
kde_scheme_is() { # FILE COLOUR
  python3 - "$1" "$2" <<'PY'
import re, sys
group, colours, selection = None, [], None
for line in open(sys.argv[1]):
    line = line.rstrip("\n")
    if line.startswith("["):
        group = line
    elif "=#" in line:
        key, value = line.split("=", 1)
        colours.append(value)
        if group == "[Colors:Selection]" and key == "BackgroundNormal":
            selection = value
sys.exit(0 if len(colours) > 90 and all(re.fullmatch(r"#[0-9a-f]{6}", c) for c in colours) and selection == sys.argv[2] else 1)
PY
}
mtime() { stat -c %Y -- "$1"; }

tinst "an apply with no toolkit on PATH" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json dusk
check "an apply with no toolkit on PATH skips every toolkit" test "$(states)" == "accent-color=skipped color-scheme=skipped gtk-theme=skipped icons=skipped kcolorscheme=skipped qt5ct=skipped qt6ct=skipped"
check "an undetected toolkit gets no file" test ! -e "$cfg/qt5ct" -a ! -e "$cfg/qt6ct" -a ! -e "$data"

# qt6ct.conf stands with an old mtime, qt5ct.conf does not stand at all.
# Yaru-blue is installed in a system data directory, a dangling link stands
# at Yaru-magenta, and a file of the user's own at Yaru-olive.
mkdir -p "$cfg/qt6ct" "$data_dirs/icons/Yaru-blue" "$data/icons"
printf 'mine\n' >"$data/icons/Yaru-olive"
printf '[Appearance]\nstyle=Fusion\n' >"$cfg/qt6ct/qt6ct.conf"
touch -d @0 -- "$cfg/qt6ct/qt6ct.conf"
ln -s -- "$tmp/gone/Yaru-magenta" "$data/icons/Yaru-magenta"
THEME_PATH="$with_stubs" tinst "every toolkit on PATH applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json dusk
check "every detected toolkit is written" test "$(states)" == "accent-color=written color-scheme=written gtk-theme=written icons=written kcolorscheme=written qt5ct=written qt6ct=written"
check "qt5ct's scheme is linked into qt5ct/colors" links_to "$cfg/qt5ct/colors/vgs.conf" "$live/qt5ct.conf"
check "qt6ct's scheme is linked into qt6ct/colors" links_to "$cfg/qt6ct/colors/vgs.conf" "$live/qt6ct.conf"
check "qt5ct's scheme holds 21 #rrggbb roles with the accent as Highlight" qt_scheme_is "$live/qt5ct.conf" "#111111"
check "qt6ct's scheme holds 21 #rrggbb roles with the accent as Highlight" qt_scheme_is "$live/qt6ct.conf" "#111111"
check "the qt6ct hook touches qt6ct.conf, which qt6ct's watcher reads" test "$(mtime "$cfg/qt6ct/qt6ct.conf")" -gt 0
check "the qt6ct hook leaves qt6ct.conf's settings as they were" file_is "$cfg/qt6ct/qt6ct.conf" $'[Appearance]\nstyle=Fusion\n'
check "the qt5ct hook creates no qt5ct.conf" test ! -e "$cfg/qt5ct/qt5ct.conf"
check "the KDE scheme is linked into the home's color-schemes" links_to "$home/.local/share/color-schemes/Vgs.colors" "$live/kcolorscheme.colors"
check "the KDE scheme is #rrggbb with the accent as the selection" kde_scheme_is "$live/kcolorscheme.colors" "#111111"

# icons: each icon theme VGS ships is linked into the data home's icons/
# unless one of that name resolves there or in a system data directory, and
# a package without an icon theme of its own takes the shipped default.
check "a shipped icon theme installed in the system is not linked" test ! -e "$data/icons/Yaru-blue" -a ! -L "$data/icons/Yaru-blue"
check "a dangling link at a shipped icon theme's name is replaced" links_to "$data/icons/Yaru-magenta" "$shipped_icons/Yaru-magenta"
check "a file of the user's own at a shipped name stays" file_is "$data/icons/Yaru-olive" $'mine\n'
rm -rf -- "${data_dirs:?}/icons/Yaru-blue" "${data:?}/icons/Yaru-olive"
check "the default icon theme is written" file_is "$live/icons.theme" $'Yaru-red\n'
check "the default icon theme is set" test "$(cat -- "$gs_sets")" == "set org.gnome.desktop.interface icon-theme Yaru-red"
# gtk-theme: Adwaita-dark for a dark package, linked into the data home's
# themes/ since no Adwaita-dark is installed.
check "a dark package's GTK theme is Adwaita-dark" file_is "$live/gtk-theme.name" $'Adwaita-dark\n'
check "a dark package sets Adwaita-dark" test "$(cat -- "$gt_sets")" == "set org.gnome.desktop.interface gtk-theme Adwaita-dark"
check "the shipped Adwaita-dark is linked where GTK 3 looks" all_linked "$shipped_themes" "$data/themes"
check "the shipped Adwaita-dark imports GTK 3's own dark stylesheet" grep -qxF '@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css");' "$data/themes/Adwaita-dark/gtk-3.0/gtk.css"
# accent-color: dusk's #111111 has no hue, so it takes slate.
check "a grey accent is GNOME's slate" file_is "$live/accent-color.name" $'slate\n'
check "a grey accent sets slate" test "$(cat -- "$ac_sets")" == "set org.gnome.desktop.interface accent-color slate"

: >"$gs_sets"
THEME_PATH="$with_stubs" tinst "the shipped icon themes link again" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json dusk
check "every shipped icon theme is linked where GTK looks" all_linked "$shipped_icons" "$data/icons"

touch -d @0 -- "$cfg/qt6ct/qt6ct.conf"
THEME_PATH="$with_stubs" tinst "a package's curated toolkit files land" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json curated
for file in qt6ct.conf kcolorscheme.colors accent-color.name; do
  check "$file takes the curated file byte for byte" cmp -s -- "$tree/themes/curated/targets/$file" "$live/$file"
done
check "qt6ct's changed bytes run its hook again" test "$(mtime "$cfg/qt6ct/qt6ct.conf")" -gt 0
check "a curated accent is set" test "$(tail -n 1 -- "$ac_sets")" == "set org.gnome.desktop.interface accent-color teal"

printf '{ "disabledTargets": ["gtk-theme", "kcolorscheme", "qt6ct"] }\n' >"$cfg/vgshell/shell.json"
: >"$gt_sets"; printf "'adw-gtk3-dark'\n" >"$gt_current"
THEME_PATH="$with_stubs" tinst "disabled toolkits" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json dusk
check "the disabled toolkits are skipped" test "$(states)" == "accent-color=written color-scheme=unchanged gtk-theme=skipped icons=unchanged kcolorscheme=skipped qt5ct=written qt6ct=skipped"
check "a disabled gtk-theme sets no GTK theme" test ! -s "$gt_sets"
check "a disabled qt6ct loses its link and keeps its colors directory" test ! -e "$cfg/qt6ct/colors/vgs.conf" -a ! -L "$cfg/qt6ct/colors/vgs.conf" -a -d "$cfg/qt6ct/colors"
check "a disabled KDE scheme loses its link and keeps color-schemes" test ! -L "$home/.local/share/color-schemes/Vgs.colors" -a -d "$home/.local/share/color-schemes"
check "the disabled toolkits' files leave theme/" test ! -e "$live/gtk-theme.name" -a ! -e "$live/qt6ct.conf" -a ! -e "$live/kcolorscheme.colors"
for stub in "${detected[@]}"; do
  check "detection never ran $stub" test ! -e "$tmp/ran-$stub"
done
rm -f -- "$cfg/vgshell/shell.json"

# icons: the package's curated icons.theme names the icon theme, asserted
# through gsettings on every apply once it is installed and not already set.
check "detection never ran gsettings" test ! -e "$tmp/ran-gsettings"
icon_pkg() { # NAME ICON_THEME
  theme_pkg "$tree/themes/$1" "{ \"schemaVersion\": 1, \"name\": \"$1\", \"tokens\": {} }"
  mkdir -p "$tree/themes/$1/targets"; printf '%s\n' "$2" >"$tree/themes/$1/targets/icons.theme"
}
icon_pkg iconic Papirus-Dark
icon_pkg uninstalled vgs-no-such-icons
icon_pkg traversal ../x
icon_pkg shipped Yaru-sage-dark
mkdir -p "$home/.local/share/icons/Papirus-Dark"
set_line="set org.gnome.desktop.interface icon-theme Papirus-Dark"
sets_are() { [[ "$(cat -- "$gs_sets" 2>/dev/null)" == "$1" ]]; }
: >"$gs_sets"
THEME_PATH="$with_stubs" tinst "a package's icon theme applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json iconic
check "the curated icon theme is written" file_is "$live/icons.theme" $'Papirus-Dark\n'
check "the installed icon theme is set" sets_are "$set_line"
printf "'Papirus-Dark'\n" >"$gs_current"; : >"$gs_sets"
THEME_PATH="$with_stubs" tinst "an icon theme already set" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json iconic
check "an icon theme already set is not set again" sets_are ""
printf "'Adwaita'\n" >"$gs_current"
THEME_PATH="$with_stubs" tinst "an icon theme changed by hand" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json iconic
check "unchanged bytes keep icons unchanged" test "$(states)" == "accent-color=unchanged color-scheme=unchanged gtk-theme=unchanged icons=unchanged kcolorscheme=unchanged qt5ct=unchanged qt6ct=unchanged"
check "unchanged bytes assert the icon theme again" sets_are "$set_line"
: >"$gs_sets"
THEME_PATH="$with_stubs" tinst "a shipped icon theme a package names" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json shipped
check "a shipped icon theme a package names is set" sets_are "set org.gnome.desktop.interface icon-theme Yaru-sage-dark"
: >"$gs_sets"
THEME_PATH="$with_stubs" tinst "an icon theme that is not installed" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json uninstalled
check "an icon theme that is not installed is not set" sets_are ""
THEME_PATH="$with_stubs" tinst "an icon theme name holding a path" "$cfg" "$rt_empty" 3 "$any_out" "vgshell: refused: target=icons reason=reload-failed command=sh status=1" theme apply --json traversal
check "an icon theme name holding a path is reload-pending" python3 -c 'import json,sys; t = {x["name"]: x for x in json.loads(sys.argv[1])["targets"]}; sys.exit(0 if t["icons"]["state"] == "reload-pending" else 1)' "$(tail -n 1 "$tmp/out")"
check "an icon theme name holding a path is not set" sets_are ""
THEME_PATH="$with_stubs" tinst "a package with the default icon theme clears the pending icons" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json dusk

# color-scheme and gtk-theme: the package's scheme.mode, asserted as GTK's
# colour scheme and GTK theme through gsettings on every apply unless the
# value already holds.
dark_line="set org.gnome.desktop.interface color-scheme prefer-dark"
light_line="set org.gnome.desktop.interface color-scheme prefer-light"
scheme_sets_are() { [[ "$(cat -- "$cs_sets" 2>/dev/null)" == "$1" ]]; }
gtk_sets_are() { [[ "$(cat -- "$gt_sets" 2>/dev/null)" == "$1" ]]; }
accent_sets_are() { [[ "$(cat -- "$ac_sets" 2>/dev/null)" == "$1" ]]; }
: >"$cs_sets"; : >"$gt_sets"; printf "'Adwaita-dark'\n" >"$gt_current"
THEME_PATH="$with_stubs" tinst "a dark package" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json dusk
check "a dark package sets prefer-dark" scheme_sets_are "$dark_line"
check "the dark package's mode file is prefer-dark" file_is "$live/color-scheme.mode" $'prefer-dark\n'
check "a GTK theme already set is not set again" gtk_sets_are ""
: >"$cs_sets"; : >"$ac_sets"; : >"$gs_sets"; printf "'slate'\n" >"$ac_current"
THEME_PATH="$with_stubs" tinst "a light package" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json flexoki-light
check "a light package's mode is written" test "$(states)" == "accent-color=written color-scheme=written gtk-theme=written icons=written kcolorscheme=written qt5ct=written qt6ct=written"
check "a light package sets prefer-light" scheme_sets_are "$light_line"
check "a light package sets Adwaita" gtk_sets_are "set org.gnome.desktop.interface gtk-theme Adwaita"
check "a light package's catalog icon theme is set" sets_are "set org.gnome.desktop.interface icon-theme Yaru-blue"
check "a blue accent is GNOME's blue" accent_sets_are "set org.gnome.desktop.interface accent-color blue"
printf "'prefer-light'\n" >"$cs_current"; printf "'Adwaita'\n" >"$gt_current"; printf "'blue'\n" >"$ac_current"
: >"$cs_sets"; : >"$gt_sets"; : >"$ac_sets"
THEME_PATH="$with_stubs" tinst "a colour scheme already set" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json flexoki-light
check "a colour scheme already set is not set again" scheme_sets_are ""
check "an accent already set is not set again" accent_sets_are ""
printf "'prefer-dark'\n" >"$cs_current"; printf "'Adwaita-dark'\n" >"$gt_current"; printf "'red'\n" >"$ac_current"
THEME_PATH="$with_stubs" tinst "a colour scheme changed by hand" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json flexoki-light
check "unchanged bytes keep color-scheme unchanged" test "$(states)" == "accent-color=unchanged color-scheme=unchanged gtk-theme=unchanged icons=unchanged kcolorscheme=unchanged qt5ct=unchanged qt6ct=unchanged"
check "unchanged bytes assert the colour scheme again" scheme_sets_are "$light_line"
check "unchanged bytes assert the GTK theme again" gtk_sets_are "set org.gnome.desktop.interface gtk-theme Adwaita"
check "unchanged bytes assert the accent again" accent_sets_are "set org.gnome.desktop.interface accent-color blue"

# accent-color is set only where the schema has the key and lists the value.
rm -f -- "$ac_range"; : >"$ac_sets"
THEME_PATH="$with_stubs" tinst "a schema without accent-color" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json flexoki-light
check "a schema without accent-color sets none" accent_sets_are ""
printf "enum\n'teal'\n" >"$ac_range"
THEME_PATH="$with_stubs" tinst "a schema whose accents lack blue" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json flexoki-light
check "an accent the schema does not list is not set" accent_sets_are ""
printf '%s\n' "$all_accents" >"$ac_range"

# An Adwaita-dark installed in a system data directory is not linked.
rm -f -- "${data:?}/themes/Adwaita-dark"; mkdir -p "$data_dirs/themes/Adwaita-dark"
THEME_PATH="$with_stubs" tinst "an installed Adwaita-dark" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply --json dusk
check "an installed Adwaita-dark is not linked" test ! -e "$data/themes/Adwaita-dark" -a ! -L "$data/themes/Adwaita-dark"
rm -rf -- "${data_dirs:?}/themes/Adwaita-dark"

# Controls: each mutant target.json drops one rule, and the assertion that
# pins it must turn. The rows above use the same assertions.
# Each starts from no state directory, so every target's bytes change and
# its hook is due.
control_cfg() { cfg="$tmp/cfg-$1"; mkdir -p "$cfg/vgshell"; rm -rf -- "${state:?}"; }
tree_control qt6ct-encoder themes/targets/qt6ct/target.json '"encoder": "hex6"' '"encoder": "hex8"'
control_cfg qt6ct-encoder
THEME_PATH="$with_stubs" tinst "the qt6ct hex8 mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the qt6ct hex8 mutant's roles are not #rrggbb" test "$(qt_scheme_is "$live/qt6ct.conf" "#111111"; echo $?)" == 1
tree_control qt5ct-reload themes/targets/qt5ct/target.json '"touch -c -- ' '"touch -- '
control_cfg qt5ct-reload
THEME_PATH="$with_stubs" tinst "the creating qt5ct hook mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the creating qt5ct hook mutant creates qt5ct.conf" test -e "$cfg/qt5ct/qt5ct.conf"
tree_control kcolorscheme-base themes/targets/kcolorscheme/target.json '"base": "home"' '"base": "config"'
control_cfg kcolorscheme-base; rm -rf -- "$home/.local/share/color-schemes"
THEME_PATH="$with_stubs" tinst "the configuration-home KDE mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the configuration-home KDE mutant links no scheme where KDE reads it" test ! -L "$home/.local/share/color-schemes/Vgs.colors"
tree_control icons-always themes/targets/icons/target.json '"always": true' '"always": false'
control_cfg icons-always
THEME_PATH="$with_stubs" tinst "the changed-only icons mutant lands iconic" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply iconic
printf "'Adwaita'\n" >"$gs_current"; : >"$gs_sets"
THEME_PATH="$with_stubs" tinst "the changed-only icons mutant applies unchanged bytes" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply iconic
check "the changed-only icons mutant never asserts the icon theme again" sets_are ""
tree_control icons-installed themes/targets/icons/target.json 'found \"$name\" || exit 0; ' ''
control_cfg icons-installed
THEME_PATH="$with_stubs" tinst "the installed-check mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply uninstalled
check "the installed-check mutant sets an icon theme that is not installed" sets_are "set org.gnome.desktop.interface icon-theme vgs-no-such-icons"
# The link mutants act on a data home that holds no link yet.
tree_control icons-link themes/targets/icons/target.json '[ -e \"$at\" ] || found' '[ ! -e \"$at\" ] || found'
control_cfg icons-link; rm -rf -- "${data:?}/icons"
THEME_PATH="$with_stubs" tinst "the no-link icons mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the no-link icons mutant links no shipped icon theme" test "$(all_linked "$shipped_icons" "$data/icons"; echo $?)" == 1
tree_control icons-system themes/targets/icons/target.json '[ -e \"$at\" ] || found \"${dir##*/}\" ||' '[ -e \"$at\" ] ||'
control_cfg icons-system; rm -rf -- "${data:?}/icons"; mkdir -p "$data_dirs/icons/Yaru-blue"
THEME_PATH="$with_stubs" tinst "the system-blind icons mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the system-blind icons mutant links over an installed icon theme" test -L "$data/icons/Yaru-blue"
rm -rf -- "${data_dirs:?}/icons/Yaru-blue"
tree_control icons-occupied themes/targets/icons/target.json '[ -e \"$at\" ] || found' 'found'
control_cfg icons-occupied; rm -rf -- "${data:?}/icons"; mkdir -p "$data/icons"; printf 'mine\n' >"$data/icons/Yaru-olive"
THEME_PATH="$with_stubs" tinst "the occupying icons mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the occupying icons mutant replaces the user's own file" test -L "$data/icons/Yaru-olive"
tree_control gtk-theme-link themes/targets/gtk-theme/target.json '[ -e \"$at\" ] || found' '[ ! -e \"$at\" ] || found'
control_cfg gtk-theme-link; rm -rf -- "${data:?}/themes"
THEME_PATH="$with_stubs" tinst "the no-link GTK theme mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the no-link GTK theme mutant links no Adwaita-dark" test "$(all_linked "$shipped_themes" "$data/themes"; echo $?)" == 1
tree_control gtk-theme-skip themes/targets/gtk-theme/target.json '[ \"$(gsettings get org.gnome.desktop.interface gtk-theme)\" = \"'"'"'$gtk'"'"'\" ] && exit 0; ' ''
control_cfg gtk-theme-skip
printf "'Adwaita-dark'\n" >"$gt_current"; : >"$gt_sets"
THEME_PATH="$with_stubs" tinst "the no-skip GTK theme mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the no-skip GTK theme mutant sets a GTK theme already set" gtk_sets_are "set org.gnome.desktop.interface gtk-theme Adwaita-dark"
tree_control gtk-theme-mode themes/targets/gtk-theme/gtk-theme.name 'dark=Adwaita-dark|light=Adwaita' 'dark=Adwaita|light=Adwaita'
control_cfg gtk-theme-mode
printf "'Adwaita'\n" >"$gt_current"; : >"$gt_sets"
THEME_PATH="$with_stubs" tinst "the one-mode GTK theme mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply dusk
check "the one-mode GTK theme mutant never sets Adwaita-dark" gtk_sets_are ""
tree_control accent-range themes/targets/accent-color/target.json 'range=$(gsettings range org.gnome.desktop.interface accent-color) || exit 0; case $range in *\"'"'"'$name'"'"'\"*) ;; *) exit 0;; esac; ' ''
control_cfg accent-range; rm -f -- "$ac_range"; : >"$ac_sets"
THEME_PATH="$with_stubs" tinst "the range-blind accent mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply flexoki-light
check "the range-blind accent mutant sets accent-color on a schema without it" accent_sets_are "set org.gnome.desktop.interface accent-color blue"
printf '%s\n' "$all_accents" >"$ac_range"
tree_control accent-encoder themes/targets/accent-color/target.json '"encoder": "gnome-accent"' '"encoder": "hex6"'
control_cfg accent-encoder; : >"$ac_sets"
THEME_PATH="$with_stubs" tinst "the hex accent mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply flexoki-light
check "the hex accent mutant sets no accent name" accent_sets_are ""
tree_control color-scheme-skip themes/targets/color-scheme/target.json '[ \"$(gsettings get org.gnome.desktop.interface color-scheme)\" = \"'"'"'$mode'"'"'\" ] && exit 0; ' ''
control_cfg color-scheme-skip
printf "'prefer-light'\n" >"$cs_current"; : >"$cs_sets"
THEME_PATH="$with_stubs" tinst "the no-skip colour scheme mutant applies" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply flexoki-light
check "the no-skip colour scheme mutant sets a colour scheme already set" scheme_sets_are "$light_line"
tree_control color-scheme-always themes/targets/color-scheme/target.json '"always": true' '"always": false'
control_cfg color-scheme-always
THEME_PATH="$with_stubs" tinst "the changed-only colour scheme mutant lands flexoki-light" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply flexoki-light
printf "'prefer-dark'\n" >"$cs_current"; : >"$cs_sets"
THEME_PATH="$with_stubs" tinst "the changed-only colour scheme mutant applies unchanged bytes" "$cfg" "$rt_empty" 0 "$any_out" "" theme apply flexoki-light
check "the changed-only colour scheme mutant never asserts the colour scheme again" scheme_sets_are ""
unset THEME_BIN

rows_done test-vgshell-toolkits
