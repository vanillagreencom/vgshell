/* One pointer click on the Wayland display WAYLAND_DISPLAY names, through
 * the compositor's virtual pointer protocol, so the seat it moves is the
 * nested compositor's and never the live session's: the helper connects to
 * the socket it is given and to nothing else.
 *
 *   click X Y WIDTH HEIGHT [move | right | middle | drag X2 Y2 [hold] | wheel STEPS | swipe LENGTH]
 *
 * Moves the pointer to (X, Y) on a layout WIDTH by HEIGHT, presses and
 * releases the left button, and prints `clicked X Y`. With `move` it only
 * moves the pointer and prints `moved X Y`, so a row can hover an item.
 * With `right` it clicks the right button, as a context menu wants, and
 * with `middle` the middle button, as a bar widget's mute wants; each
 * prints `clicked X Y`.
 * With `drag X2 Y2` it presses at (X, Y), moves to (X2, Y2) in ten steps
 * DRAG_STEP_MS apart with the button held, releases there and prints
 * `dragged X Y X2 Y2`. With `hold`, it prints `holding X2 Y2` after the
 * moves, flushes stdout, waits for a newline or EOF on stdin, then releases.
 * The steps are paced as a hand moves a mouse, one
 * 60 Hz frame apart: sent back to back, a loaded client can read the
 * press, the moves and the release in one batch, and a Flickable that
 * takes the left button then reads no drag.
 * With `wheel STEPS` it turns a vertical wheel STEPS notches at (X, Y),
 * positive down, as one discrete axis event of WHEEL_NOTCH per notch, and
 * prints `wheeled X Y STEPS`.
 * With `swipe LENGTH` it scrolls as two fingers on a touchpad do at (X, Y):
 * a vertical axis length of LENGTH, positive down, in SWIPE_STEPS axis
 * events of finger source SWIPE_STEP_MS apart, as a touchpad reports them,
 * the fingers speeding up to the middle of the swipe and slowing to rest,
 * then the axis stop of the lift, and prints `swiped X Y LENGTH`. The
 * compositor reads the source of an axis event from the request after it,
 * so each event names its source after its length: Hyprland 0.56.2 sends a
 * client `axis_source(wheel)` for a source named before the axis.
 * Exit 2 on a bad invocation, 1 when the display cannot be opened or lacks
 * the protocol, printed as `click: refused: <key>=<value>`.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

#define BTN_LEFT 0x110
#define BTN_RIGHT 0x111
#define BTN_MIDDLE 0x112
/* The axis length of one wheel notch, libinput's 15 degrees. */
#define WHEEL_NOTCH 15
#define DRAG_STEP_MS 16
#define SWIPE_STEPS 30
#define SWIPE_STEP_MS 10

static struct wl_seat *seat = NULL;
static struct zwlr_virtual_pointer_manager_v1 *manager = NULL;

static void on_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, wl_seat_interface.name) == 0 && seat == NULL)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (strcmp(interface, zwlr_virtual_pointer_manager_v1_interface.name) == 0 && manager == NULL)
        manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}

static void on_global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = { on_global, on_global_remove };

static uint32_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static int number(const char *text, uint32_t *out) {
    char *end = NULL;
    long value = strtol(text, &end, 10);
    if (*text == '\0' || *end != '\0' || value < 0) return 0;
    *out = (uint32_t)value;
    return 1;
}

/* A signed count that is not zero and no further from it than LIMIT. */
static int steps_of(const char *text, long limit, int *out) {
    char *end = NULL;
    long value = strtol(text, &end, 10);
    if (*text == '\0' || *end != '\0' || value == 0 || value < -limit || value > limit) return 0;
    *out = (int)value;
    return 1;
}

/* The share of a swipe done at share T of its time: the fingers speed up
 * to the middle and slow to rest at the end. */
static double swipe_share(double t) { return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t); }

int main(int argc, char **argv) {
    uint32_t x, y, width, height, x2 = 0, y2 = 0;
    int steps = 0;
    int move_only = argc == 6 && strcmp(argv[5], "move") == 0;
    int right = argc == 6 && strcmp(argv[5], "right") == 0;
    int middle = argc == 6 && strcmp(argv[5], "middle") == 0;
    int drag = (argc == 8 || (argc == 9 && strcmp(argv[8], "hold") == 0)) && strcmp(argv[5], "drag") == 0;
    int hold_drag = argc == 9 && drag;
    int wheel = argc == 7 && strcmp(argv[5], "wheel") == 0;
    int swipe = argc == 7 && strcmp(argv[5], "swipe") == 0;
    uint32_t button = right ? BTN_RIGHT : middle ? BTN_MIDDLE : BTN_LEFT;
    if ((argc != 5 && !move_only && !right && !middle && !drag && !wheel && !swipe) || !number(argv[1], &x) || !number(argv[2], &y) || !number(argv[3], &width) || !number(argv[4], &height) || width == 0 || height == 0
        || (drag && (!number(argv[6], &x2) || !number(argv[7], &y2))) || (wheel && !steps_of(argv[6], 100, &steps)) || (swipe && !steps_of(argv[6], 2000, &steps))) {
        fprintf(stderr, "click: refused: usage=X Y WIDTH HEIGHT [move | right | middle | drag X2 Y2 [hold] | wheel STEPS | swipe LENGTH]\n");
        return 2;
    }
    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL) {
        fprintf(stderr, "click: refused: display=%s\n", getenv("WAYLAND_DISPLAY") ? getenv("WAYLAND_DISPLAY") : "unset");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (seat == NULL || manager == NULL) {
        fprintf(stderr, "click: refused: protocol=zwlr_virtual_pointer_manager_v1 seat=%d manager=%d\n", seat != NULL, manager != NULL);
        wl_display_disconnect(display);
        return 1;
    }
    struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
    zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), x, y, width, height);
    zwlr_virtual_pointer_v1_frame(pointer);
    wl_display_roundtrip(display);
    if (wheel) {
        zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
        zwlr_virtual_pointer_v1_axis_discrete(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(WHEEL_NOTCH * steps), steps);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
    } else if (swipe) {
        double sent = 0;
        for (int step = 1; step <= SWIPE_STEPS; step++) {
            double upto = steps * swipe_share((double)step / SWIPE_STEPS);
            zwlr_virtual_pointer_v1_axis(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(upto - sent));
            zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_FINGER);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            sent = upto;
            nanosleep(&(struct timespec){ .tv_nsec = SWIPE_STEP_MS * 1000000L }, NULL);
        }
        zwlr_virtual_pointer_v1_axis_stop(pointer, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL);
        zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_FINGER);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
    } else if (!move_only) {
        zwlr_virtual_pointer_v1_button(pointer, now_ms(), button, WL_POINTER_BUTTON_STATE_PRESSED);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        for (int step = 1; drag && step <= 10; step++) {
            uint32_t at_x = (uint32_t)((int64_t)x + ((int64_t)x2 - (int64_t)x) * step / 10);
            uint32_t at_y = (uint32_t)((int64_t)y + ((int64_t)y2 - (int64_t)y) * step / 10);
            zwlr_virtual_pointer_v1_motion_absolute(pointer, now_ms(), at_x, at_y, width, height);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            nanosleep(&(struct timespec){ .tv_nsec = DRAG_STEP_MS * 1000000L }, NULL);
        }
        if (hold_drag) {
            printf("holding %u %u\n", x2, y2);
            fflush(stdout);
            int ch;
            while ((ch = getchar()) != EOF && ch != '\n') {}
        }
        zwlr_virtual_pointer_v1_button(pointer, now_ms(), button, WL_POINTER_BUTTON_STATE_RELEASED);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
    }
    zwlr_virtual_pointer_v1_destroy(pointer);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    if (drag) printf("dragged %u %u %u %u\n", x, y, x2, y2);
    else if (swipe) printf("swiped %u %u %d\n", x, y, steps);
    else if (wheel) printf("wheeled %u %u %d\n", x, y, steps);
    else printf("%s %u %u\n", move_only ? "moved" : "clicked", x, y);
    return 0;
}
