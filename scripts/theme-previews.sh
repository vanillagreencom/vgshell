#!/usr/bin/env bash
# Make each theme package's preview.jpg, the image its card shows in the
# theme browser, from a real desktop: scripts/sandbox-shots.sh's
# theme-previews scene.
#
# Usage: scripts/theme-previews.sh [--dotfiles DIR] [--from DIR] [THEME...]
#
# THEME is vgs or a catalog package name; with none, vgs and every entry of
# themes/catalog/index.json. A catalog theme's wallpaper, the image its
# archive applies first, is fetched once for each pin into
# tmp/theme-previews/wallpapers by scripts/theme-preview-wallpaper.js, which
# prints the path the scene is handed. --dotfiles is the stow tree whose
# tmux/ and nvim/ the scene's terminal runs, ~/dotfiles by default. The
# scene runs with --modes dark --size 1920x1190 --scale 2, the theme card's
# shape (carousel.expandedWidth by expandedHeight in shell/Commons/Tokens.js)
# at 3840x2380 device pixels, into tmp/theme-previews/<UTC time>; --from DIR
# reads a run that holds a theme-preview-<name>.png for every THEME
# instead. Each shot is scaled to the card's shape at carousel.decodeCap on
# its long side, the largest a card decodes its picture at, and written as
# a JPEG to themes/vgs/preview.jpg or themes/catalog/<name>/preview.jpg.
#
# Each image written prints `theme-previews: wrote=<path> bytes=<n>`. A
# refusal is one line `theme-previews: refused: <key>=<value>` on stderr
# and exit 2; a sandbox-shots run that does not exit 0 ends this one with
# its status, so a run that could not start (77) writes nothing.
set -euo pipefail

JPEG_OPTIONS=(-strip -sampling-factor 4:4:4 -quality 88)

repo="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"
dotfiles="$HOME/dotfiles"
from=""
themes=()
refuse() { printf 'theme-previews: refused: %s=%s\n' "$1" "$2" >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dotfiles) dotfiles="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*) refuse argument "$1" ;;
    *) themes+=("$1"); shift ;;
  esac
done
imagemagick="$(command -v magick 2>/dev/null || command -v convert 2>/dev/null)" || {
  printf 'theme-previews: status=not-measured missing=magick\n'
  exit 77
}
preview_size="$(node -e '
const carousel = require(process.argv[1]).load(process.argv[2]).TOKENS.carousel;
const [width, height, cap] = [carousel.expandedWidth.value, carousel.expandedHeight.value, carousel.decodeCap.value];
const scale = cap / Math.max(width, height);
console.log(Math.round(width * scale) + "x" + Math.round(height * scale));' "$repo/bin/lib/qml-library.js" "$repo/shell/Commons/Tokens.js")"
if [[ ${#themes[@]} -eq 0 ]]; then
  mapfile -t themes < <(python3 -c 'import json,sys; [print(e["name"]) for e in json.load(open(sys.argv[1]))["entries"]]' "$repo/themes/catalog/index.json")
  themes=(vgs "${themes[@]}")
fi
package_dir() { if [[ $1 == vgs ]]; then echo "$repo/themes/vgs"; else echo "$repo/themes/catalog/$1"; fi; }
for name in "${themes[@]}"; do
  [[ $name =~ ^[a-z0-9][a-z0-9-]*$ && -f $(package_dir "$name")/theme.json ]] || refuse theme "$name"
done

work="$repo/tmp/theme-previews"
if [[ -z $from ]]; then
  mkdir -p -- "$work/wallpapers"
  wallpapers=()
  for name in "${themes[@]}"; do
    [[ $name == vgs ]] && continue
    wallpaper="$(node "$repo/scripts/theme-preview-wallpaper.js" "$name" "$work/wallpapers" "$work/cache")"
    wallpapers+=(--preview-wallpaper "$name=$wallpaper")
  done
  from="$work/$(date -u +%Y%m%dT%H%M%SZ)"
  status=0
  "$repo/scripts/sandbox-shots.sh" --modes dark --size 1920x1190 --scale 2 --out "$from" \
    --preview-themes "$(IFS=,; echo "${themes[*]}")" "${wallpapers[@]}" --dotfiles "$dotfiles" \
    theme-previews || status=$?
  [[ $status -eq 0 ]] || exit "$status"
fi
for name in "${themes[@]}"; do
  [[ -f $from/theme-preview-$name.png ]] || refuse shot "$from/theme-preview-$name.png"
done
for name in "${themes[@]}"; do
  target="$(package_dir "$name")/preview.jpg"
  "$imagemagick" "$from/theme-preview-$name.png" -filter Lanczos -resize "$preview_size!" "${JPEG_OPTIONS[@]}" "jpg:$target.part"
  mv -f -- "$target.part" "$target"
  printf 'theme-previews: wrote=%s bytes=%s\n' "${target#"$repo"/}" "$(stat -c %s -- "$target")"
done
