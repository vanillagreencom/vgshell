# Shared package-review tool admission through the existing fixture consumer.
# The harness terminal records the core argv and substitutes true. Production
# interaction and one-use bindings live in test-package-review-runtime.js.
# Waits use the harness's bounded expect_poll/expect_run_end; this row adds
# no latency or resident-size claim.
# inputs: scripts/smoke/fixtures/plugins/acme.tui/* scripts/smoke/rows/capabilities.sh shell/Core/PluginLogic.js shell/Core/ConfigLogic.js shell/Core/Config.qml shell/Core/TuiRunner.qml shell/Core/TuiRecords.qml bin/vgshell bin/vgshell-pkg bin/vgshell-tui bin/lib/pkg-review.js bin/lib/pkg-review.sh bin/lib/pkg-review-settings.sh shell/Core/PackageReview.js shell/Core/PackageManagers.js config/shell.json
set -euo pipefail
package_review_fixture="$home/.config/vgshell/plugins/acme.tui"
mkdir -p -- "$package_review_fixture"
cp -R -- "$repo/scripts/smoke/fixtures/plugins/acme.tui/." "$package_review_fixture/"
terminal_stand_in
rescan "package review fixture discovery"
expect_poll "package review fixture is known" True plugin_known acme.tui
expect "package review fixture enablement" ok ipc shell setPluginEnabled acme.tui true
expect_poll "package review fixture service is built" True record_exists acme.tui
forget_record
expect "a plugin can open the shared core review editor" ok ipc acme.tui invoke open core/pkg-review-settings
expect_poll "review editor is the one core argv" "$(words core/pkg-review-settings "$core_vgshell" pkg review-settings)" recorded_tail
expect_run_end "shared review editor fixture ends" core/pkg-review-settings
rm -rf -- "${package_review_fixture:?}"
rescan "package review fixture removal"
expect_poll "package review fixture is gone" False plugin_known acme.tui
