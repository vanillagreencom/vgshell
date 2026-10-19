/* The client scripts/test-smoke-sink.sh drives the sink compositor with, on
 * the display WAYLAND_DISPLAY names.
 *
 *   probe TOPLEVELS FRAMES FD_PAIRS
 *
 * Binds the five globals the sink serves, reads the dmabuf default
 * feedback, maps TOPLEVELS toplevels, each answering its configure with a
 * 1x1 wl_shm buffer, and then commits FRAMES more frames on the first one,
 * each on the frame callback of the one before. It then sends FD_PAIRS
 * wl_shm pools and FD_PAIRS dmabuf planes, each with a file descriptor of
 * its own, destroys them, and ends with a roundtrip. One line per fact,
 * for the test to read:
 *
 *   global NAME VERSION          each global the registry lists
 *   capabilities N               the seat's capabilities
 *   main-device MAJOR:MINOR      the feedback's main device
 *   format FOURCC MODIFIER       each format table entry, both in hex
 *   configure INDEX WxH          each toplevel configure
 *   release INDEX                each buffer release
 *   ping committed=0|1           each ping, and whether a buffer was
 *                                committed before it
 *   input KIND                   any pointer or keyboard event
 *   frames N ms=ELAPSED          the FRAMES frame callbacks and the time
 *                                from the first framed commit to the last
 *                                done
 *   done
 *
 * Exit 1, printed as `probe: refused: <key>=<value>`, when the display
 * cannot be opened, lacks a global, or a request fails.
 */
#define _GNU_SOURCE
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sysmacros.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"
#include "linux-dmabuf-v1-client-protocol.h"

#define MAX_TOPLEVELS 8

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static struct wl_seat *seat;
static struct zwp_linux_dmabuf_v1 *dmabuf;
static bool committed;
static int frames_left;
static struct timespec frames_start;

struct window {
	int index;
	struct wl_surface *surface;
	struct xdg_surface *xdg_surface;
	struct xdg_toplevel *toplevel;
	bool mapped;
};
static struct window windows[MAX_TOPLEVELS];

static int refuse(const char *key, const char *value) {
	printf("probe: refused: %s=%s\n", key, value);
	return 1;
}

static long elapsed_ms(const struct timespec *since) {
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (now.tv_sec - since->tv_sec) * 1000 + (now.tv_nsec - since->tv_nsec) / 1000000;
}

static int memfd(size_t size) {
	int fd = memfd_create("vgs-sink-probe", MFD_CLOEXEC);
	if (fd >= 0 && ftruncate(fd, (off_t)size) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static void buffer_release(void *data, struct wl_buffer *buffer) {
	printf("release %d\n", ((struct window *)data)->index);
	wl_buffer_destroy(buffer);
}
static const struct wl_buffer_listener buffer_listener = {.release = buffer_release};

/* A fresh 1x1 XRGB8888 buffer on WINDOW's surface, committed. */
static bool commit_buffer(struct window *window, struct wl_callback *frame);
static void frame_done(void *data, struct wl_callback *callback, uint32_t time);
static const struct wl_callback_listener frame_listener = {.done = frame_done};

static bool commit_buffer(struct window *window, struct wl_callback *frame) {
	int fd = memfd(4);
	if (fd < 0)
		return false;
	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, 4);
	struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, 1, 1, 4, WL_SHM_FORMAT_XRGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	wl_buffer_add_listener(buffer, &buffer_listener, window);
	wl_surface_attach(window->surface, buffer, 0, 0);
	wl_surface_damage_buffer(window->surface, 0, 0, 1, 1);
	if (frame)
		wl_callback_add_listener(frame, &frame_listener, window);
	wl_surface_commit(window->surface);
	committed = true;
	return true;
}

static void frame_done(void *data, struct wl_callback *callback, uint32_t time) {
	struct window *window = data;
	(void)time;
	wl_callback_destroy(callback);
	if (--frames_left > 0)
		commit_buffer(window, wl_surface_frame(window->surface));
}

static void toplevel_configure(void *data, struct xdg_toplevel *toplevel, int32_t width, int32_t height, struct wl_array *states) {
	(void)toplevel;
	(void)states;
	printf("configure %d %dx%d\n", ((struct window *)data)->index, width, height);
}
static void toplevel_close(void *data, struct xdg_toplevel *toplevel) {
	(void)data;
	(void)toplevel;
}
static const struct xdg_toplevel_listener toplevel_listener = {.configure = toplevel_configure, .close = toplevel_close};

static void xdg_surface_configure(void *data, struct xdg_surface *xdg_surface, uint32_t serial) {
	struct window *window = data;
	xdg_surface_ack_configure(xdg_surface, serial);
	if (!window->mapped) {
		window->mapped = true;
		commit_buffer(window, NULL);
	}
}
static const struct xdg_surface_listener xdg_surface_listener = {.configure = xdg_surface_configure};

static void wm_base_ping(void *data, struct xdg_wm_base *base, uint32_t serial) {
	(void)data;
	printf("ping committed=%d\n", committed ? 1 : 0);
	xdg_wm_base_pong(base, serial);
}
static const struct xdg_wm_base_listener wm_base_listener = {.ping = wm_base_ping};

static void input_event(const char *kind) { printf("input %s\n", kind); }
static void pointer_enter(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *f, wl_fixed_t x, wl_fixed_t y) { input_event("pointer-enter"); }
static void pointer_leave(void *d, struct wl_pointer *p, uint32_t s, struct wl_surface *f) { input_event("pointer-leave"); }
static void pointer_motion(void *d, struct wl_pointer *p, uint32_t t, wl_fixed_t x, wl_fixed_t y) { input_event("pointer-motion"); }
static void pointer_button(void *d, struct wl_pointer *p, uint32_t s, uint32_t t, uint32_t b, uint32_t st) { input_event("pointer-button"); }
static void pointer_axis(void *d, struct wl_pointer *p, uint32_t t, uint32_t a, wl_fixed_t v) { input_event("pointer-axis"); }
static void pointer_frame(void *d, struct wl_pointer *p) { input_event("pointer-frame"); }
static void pointer_axis_source(void *d, struct wl_pointer *p, uint32_t s) { input_event("pointer-axis-source"); }
static void pointer_axis_stop(void *d, struct wl_pointer *p, uint32_t t, uint32_t a) { input_event("pointer-axis-stop"); }
static void pointer_axis_discrete(void *d, struct wl_pointer *p, uint32_t a, int32_t v) { input_event("pointer-axis-discrete"); }
static void pointer_axis_value120(void *d, struct wl_pointer *p, uint32_t a, int32_t v) { input_event("pointer-axis-value120"); }
static void pointer_axis_relative_direction(void *d, struct wl_pointer *p, uint32_t a, uint32_t v) { input_event("pointer-axis-direction"); }
static const struct wl_pointer_listener pointer_listener = {
	pointer_enter, pointer_leave, pointer_motion, pointer_button, pointer_axis, pointer_frame,
	pointer_axis_source, pointer_axis_stop, pointer_axis_discrete, pointer_axis_value120, pointer_axis_relative_direction,
};
static void keyboard_keymap(void *d, struct wl_keyboard *k, uint32_t f, int32_t fd, uint32_t s) {
	close(fd);
	input_event("keyboard-keymap");
}
static void keyboard_enter(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *f, struct wl_array *keys) { input_event("keyboard-enter"); }
static void keyboard_leave(void *d, struct wl_keyboard *k, uint32_t s, struct wl_surface *f) { input_event("keyboard-leave"); }
static void keyboard_key(void *d, struct wl_keyboard *k, uint32_t s, uint32_t t, uint32_t key, uint32_t st) { input_event("keyboard-key"); }
static void keyboard_modifiers(void *d, struct wl_keyboard *k, uint32_t s, uint32_t a, uint32_t b, uint32_t c, uint32_t g) { input_event("keyboard-modifiers"); }
static void keyboard_repeat_info(void *d, struct wl_keyboard *k, int32_t r, int32_t delay) { input_event("keyboard-repeat-info"); }
static const struct wl_keyboard_listener keyboard_listener = {
	keyboard_keymap, keyboard_enter, keyboard_leave, keyboard_key, keyboard_modifiers, keyboard_repeat_info,
};

static void seat_capabilities(void *data, struct wl_seat *s, uint32_t capabilities) {
	(void)data;
	printf("capabilities %" PRIu32 "\n", capabilities);
	if (capabilities & WL_SEAT_CAPABILITY_POINTER)
		wl_pointer_add_listener(wl_seat_get_pointer(s), &pointer_listener, NULL);
	if (capabilities & WL_SEAT_CAPABILITY_KEYBOARD)
		wl_keyboard_add_listener(wl_seat_get_keyboard(s), &keyboard_listener, NULL);
}
static void seat_name(void *data, struct wl_seat *s, const char *name) {
	(void)data;
	(void)s;
	(void)name;
}
static const struct wl_seat_listener seat_listener = {.capabilities = seat_capabilities, .name = seat_name};

static void feedback_done(void *d, struct zwp_linux_dmabuf_feedback_v1 *f) {}
static void feedback_format_table(void *d, struct zwp_linux_dmabuf_feedback_v1 *f, int32_t fd, uint32_t size) {
	struct {
		uint32_t format;
		uint32_t pad;
		uint64_t modifier;
	} *entries = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
	close(fd);
	if (entries == MAP_FAILED) {
		printf("format unreadable\n");
		return;
	}
	for (uint32_t i = 0; i < size / 16; i++)
		printf("format %08" PRIx32 " %016" PRIx64 "\n", entries[i].format, entries[i].modifier);
	munmap(entries, size);
}
static void feedback_main_device(void *d, struct zwp_linux_dmabuf_feedback_v1 *f, struct wl_array *device) {
	dev_t value;
	if (device->size != sizeof(value)) {
		printf("main-device size=%zu\n", device->size);
		return;
	}
	memcpy(&value, device->data, sizeof(value));
	printf("main-device %u:%u\n", major(value), minor(value));
}
static void feedback_tranche_done(void *d, struct zwp_linux_dmabuf_feedback_v1 *f) {}
static void feedback_tranche_target_device(void *d, struct zwp_linux_dmabuf_feedback_v1 *f, struct wl_array *device) {}
static void feedback_tranche_formats(void *d, struct zwp_linux_dmabuf_feedback_v1 *f, struct wl_array *indices) {}
static void feedback_tranche_flags(void *d, struct zwp_linux_dmabuf_feedback_v1 *f, uint32_t flags) {}
static const struct zwp_linux_dmabuf_feedback_v1_listener feedback_listener = {
	.done = feedback_done,
	.format_table = feedback_format_table,
	.main_device = feedback_main_device,
	.tranche_done = feedback_tranche_done,
	.tranche_target_device = feedback_tranche_target_device,
	.tranche_formats = feedback_tranche_formats,
	.tranche_flags = feedback_tranche_flags,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
	(void)data;
	printf("global %s %" PRIu32 "\n", interface, version);
	if (strcmp(interface, wl_compositor_interface.name) == 0)
		compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 6);
	else if (strcmp(interface, wl_shm_interface.name) == 0)
		shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
	else if (strcmp(interface, xdg_wm_base_interface.name) == 0)
		wm_base = wl_registry_bind(registry, name, &xdg_wm_base_interface, 6);
	else if (strcmp(interface, wl_seat_interface.name) == 0)
		seat = wl_registry_bind(registry, name, &wl_seat_interface, 9);
	else if (strcmp(interface, zwp_linux_dmabuf_v1_interface.name) == 0)
		dmabuf = wl_registry_bind(registry, name, &zwp_linux_dmabuf_v1_interface, 4);
}
static void registry_global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {.global = registry_global, .global_remove = registry_global_remove};

int main(int argc, char **argv) {
	int toplevels, frames, fd_pairs;
	struct wl_display *display;
	setvbuf(stdout, NULL, _IOLBF, 0);
	if (argc != 4 || (toplevels = atoi(argv[1])) < 1 || toplevels > MAX_TOPLEVELS || (frames = atoi(argv[2])) < 1 || (fd_pairs = atoi(argv[3])) < 0)
		return refuse("usage", "probe-TOPLEVELS-FRAMES-FD_PAIRS");
	display = wl_display_connect(NULL);
	if (!display)
		return refuse("display", getenv("WAYLAND_DISPLAY") ? getenv("WAYLAND_DISPLAY") : "unset");
	wl_registry_add_listener(wl_display_get_registry(display), &registry_listener, NULL);
	if (wl_display_roundtrip(display) < 0)
		return refuse("roundtrip", "registry");
	if (!compositor || !shm || !wm_base || !seat || !dmabuf)
		return refuse("globals", "missing");
	xdg_wm_base_add_listener(wm_base, &wm_base_listener, NULL);
	wl_seat_add_listener(seat, &seat_listener, NULL);
	zwp_linux_dmabuf_feedback_v1_add_listener(zwp_linux_dmabuf_v1_get_default_feedback(dmabuf), &feedback_listener, NULL);
	if (wl_display_roundtrip(display) < 0)
		return refuse("roundtrip", "feedback");
	for (int i = 0; i < toplevels; i++) {
		struct window *window = &windows[i];
		window->index = i;
		window->surface = wl_compositor_create_surface(compositor);
		window->xdg_surface = xdg_wm_base_get_xdg_surface(wm_base, window->surface);
		xdg_surface_add_listener(window->xdg_surface, &xdg_surface_listener, window);
		window->toplevel = xdg_surface_get_toplevel(window->xdg_surface);
		xdg_toplevel_add_listener(window->toplevel, &toplevel_listener, window);
		wl_surface_commit(window->surface);
	}
	while (!committed)
		if (wl_display_dispatch(display) < 0)
			return refuse("dispatch", "configure");
	frames_left = frames;
	clock_gettime(CLOCK_MONOTONIC, &frames_start);
	commit_buffer(&windows[0], wl_surface_frame(windows[0].surface));
	while (frames_left > 0)
		if (wl_display_dispatch(display) < 0)
			return refuse("dispatch", "frames");
	printf("frames %d ms=%ld\n", frames, elapsed_ms(&frames_start));
	for (int i = 0; i < fd_pairs; i++) {
		int pool_fd = memfd(4), plane_fd = memfd(4);
		if (pool_fd < 0 || plane_fd < 0)
			return refuse("memfd", "failed");
		wl_shm_pool_destroy(wl_shm_create_pool(shm, pool_fd, 4));
		struct zwp_linux_buffer_params_v1 *params = zwp_linux_dmabuf_v1_create_params(dmabuf);
		zwp_linux_buffer_params_v1_add(params, plane_fd, 0, 0, 4, 0, 0);
		zwp_linux_buffer_params_v1_destroy(params);
		close(pool_fd);
		close(plane_fd);
	}
	if (wl_display_roundtrip(display) < 0)
		return refuse("roundtrip", "fds");
	printf("done\n");
	wl_display_disconnect(display);
	return 0;
}
