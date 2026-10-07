#!/usr/bin/env bash
# Keyboard editor and snapshot contracts against the shipped components.
# Each control changes a disposable source copy and must fail its named
# behavior assertion. Syntax or unrelated construction failures do not count.
set -euo pipefail
repo="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd -P)"
self="$repo/scripts/test-keyboard-ui.sh"
"$repo/scripts/smoke/gpu-fence.sh" --check || exec "$repo/scripts/smoke/gpu-fence.sh" "$self" "$@"
TMP_ROOT="$(mktemp -d)" || { echo "test-keyboard-ui: scratch=mktemp-failed"; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo "test-keyboard-ui: scratch=not-a-directory"; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo "test-keyboard-ui: scratch=resolve-failed"; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT

python3 - "$repo" "$TMP_ROOT" <<'PY'
import pathlib, shutil, sys
repo, root = map(pathlib.Path, sys.argv[1:])
cases = [
    ('first-source-move', 'KeyboardControls.qml', '(entry.key !== "up" || Number(row.key) > 0)', 'true', 'test_source_menu_offers_only_possible_actions'),
    ('last-source-move', 'KeyboardControls.qml', '(entry.key !== "down" || Number(row.key) < root.sources.length - 1)', 'true', 'test_source_menu_offers_only_possible_actions'),
    ('last-source-delete', 'KeyboardControls.qml', 'removable: root.sources.length > 1', 'removable: true', 'test_source_menu_offers_only_possible_actions'),
    ('last-source-remove', 'KeyboardControls.qml', '(entry.key !== "remove" || root.sources.length > 1)', 'true', 'test_source_menu_offers_only_possible_actions'),
    ('add-variant', 'KeyboardControls.qml', 'variants[variantChoice].code', '""', 'test_add_keeps_selected_variant'),
    ('source-limit', 'KeyboardLogic.js', 'if (rows.length >= SOURCE_MAX) return { ok: false, reason: "source-limit" };', 'if (false) return { ok: false, reason: "source-limit" };', 'test_fifth_source_keeps_saved_sources'),
    ('reset-variants', 'KeyboardControls.qml', 'root.shell.configure.unset("variants")', '"ok"', 'test_system_layout_unsets_both_values'),
    ('reset-layouts', 'KeyboardControls.qml', 'root.shell.configure.unset("layouts")', '"ok"', 'test_system_layout_unsets_both_values'),
    ('modifier-preset', 'KeyboardControls.qml', 'root.setValue("options", presets[index].value)', '({})', 'test_modifier_preset_and_custom_commit'),
    ('modifier-custom', 'KeyboardControls.qml', 'onEditingFinished: root.setValue("options", text)', 'onEditingFinished: ({})', 'test_modifier_preset_and_custom_commit'),
    ('widget-snapshot', 'Widget.qml', 'shell.status.revision', '(shell.status.values, shell.status.revision)', 'test_status_ignores_other_plugins_and_keeps_models'),
    ('editor-snapshot', 'KeyboardControls.qml', 'shell.status.revision', '(shell.status.values, shell.status.revision)', 'test_status_ignores_other_plugins_and_keeps_models'),
    ('catalog-model', 'KeyboardControls.qml', 'if (key === catalogKey) return;', 'if (false) return;', 'test_status_ignores_other_plugins_and_keeps_models'),
    ('catalog-publish', 'Service.qml', 'onActiveChanged: publishActive()', 'onActiveChanged: { publishCatalog(); publishActive(); }', 'test_catalog_publishes_only_from_its_state'),
]
source = (repo / 'scripts/fixtures/keyboard-ui/tst_keyboard.qml').read_text()
old = '../../../shell/plugins/vgs.keyboard/'
assert source.count(old) == 1
test = source.replace(old, '../plugin/')
assert test != source
for name, file, needle, replacement, assertion in [('base', '', '', '', '')] + cases:
    case = root / name
    shutil.copytree(repo / 'shell/plugins/vgs.keyboard', case / 'plugin')
    (case / 'tests').mkdir()
    (case / 'tests/tst_keyboard.qml').write_text(test)
    if file:
        path = case / 'plugin' / file
        original = path.read_text()
        assert original.count(needle) == 1, name
        changed = original.replace(needle, replacement)
        assert changed != original, name
        path.write_text(changed)
(root / 'cases.tsv').write_text(''.join(f'{name}\t{assertion}\n' for name, _, _, _, assertion in cases))
PY

"$repo/scripts/qml-unit.sh" "$TMP_ROOT/base/tests/tst_keyboard.qml"
while IFS=$'\t' read -r name assertion; do
  status=0
  "$repo/scripts/qml-unit.sh" "$TMP_ROOT/$name/tests/tst_keyboard.qml" >"$TMP_ROOT/$name.log" 2>&1 || status=$?
  if [[ $status == 1 ]] && grep -qE "^FAIL!.*keyboard-ui::$assertion\\(" "$TMP_ROOT/$name.log"; then
    printf '  ok    control: %s fails its Keyboard behavior assertion\n' "$name"
  else
    cat "$TMP_ROOT/$name.log"
    printf 'test-keyboard-ui: control=%s status=%s expected=behavior-failure\n' "$name" "$status"
    exit 1
  fi
done <"$TMP_ROOT/cases.tsv"
echo 'test-keyboard-ui: ok'
