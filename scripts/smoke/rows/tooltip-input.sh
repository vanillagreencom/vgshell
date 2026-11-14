# A plain tooltip never takes the panel's pointer, including its first
# buffer. The existing tiplink fixture maps its tooltip over its own
# hovered item, forcing compositor refocus at mapping rather than racing
# a timed pointer move. A latched exit catches even a later hover return.
# There is no latency ceiling; state polls use the harness's 200 ms
# interval and bound. Measured on cachy (Ryzen 9 9950X), 2026-11-13:
# VGS-2522's nested WAYLAND_DEBUG recording shows the unfixed first buffer
# before the empty input region and a panel Leave; the fixed recording
# shows the empty region before even the first bufferless commit.
# inputs: shell/Ui/overlay/Tooltip.qml shell/Ui/controls/BarItem.qml shell/Ui/BarWidget.qml shell/Hosts/BarHost.qml scripts/smoke/fixtures/plugins/acme.tiplink/*
set -euo pipefail

tipinput_saved="$sandbox/tooltip-input-saved.json"
tipinput_pointer="$pointer_at"
cp -- "$home/.config/vgshell/shell.json" "$tipinput_saved"
rest_pointer
install_plugin_copy acme.tiplink acme.tipinput "Tooltip input"
tipinput_read() { ipc smoke readInstance "$(bar_key)" acme.tipinput "$1"; }
tipinput_call() { ipc smoke invokeInstance "$(bar_key)" acme.tipinput "$1" ""; }
rescan "install the plain tooltip input fixture"
expect_poll "the tooltip input widget is built" True record_exists acme.tipinput
expect "place the plain tooltip over its panel item" ok tipinput_call overlap
tipinput_box="$(tipinput_call itemGeometry)"
read -r tipinput_x tipinput_y < <(python3 -c 'import json,sys; x,y,w,h=json.loads(sys.argv[1]); print(int(x+w/2),int(y+h/2))' "$tipinput_box")
hover "$tipinput_x" "$tipinput_y"
# Either a queued popup frame or its transient theft of hover acknowledges
# mapping. A missing popup cannot pass by leaving the exit count at zero.
expect_poll "the tooltip mapping is observed" true tipinput_read inputObserved
tipinput_socket="$(shot_socket "$rt_dir" "$nested_socket")"
shot_grim "$tipinput_socket" "$rt_dir" -o "$screen_name" "$sandbox/tooltip-input.png"
expect "mapping a plain tooltip never removes panel hover" 0 tipinput_read inputHoverExits
expect "the panel keeps hover under the plain tooltip" true tipinput_read inputHovered
expect "the plain tooltip stays open under the pointer" true tipinput_read tooltipOpen

rest_pointer
rm -rf -- "${home:?}/.config/vgshell/plugins/acme.tipinput"
cp -- "$tipinput_saved" "$home/.config/vgshell/shell.json"
rescan "remove the plain tooltip input fixture"
expect_poll "the tooltip input fixture is gone" False plugin_known acme.tipinput
read -r tipinput_x tipinput_y <<<"$tipinput_pointer"
hover "$tipinput_x" "$tipinput_y"
