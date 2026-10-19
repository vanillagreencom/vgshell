/* The compositor the nested Hyprland draws to, so the sandbox needs no host
 * display: the nested compositor's Wayland backend (aquamarine 0.15.1,
 * src/backend/Wayland.cpp) connects here and shows no window on the live
 * desktop.
 *
 *   sink SOCKET MAIN_DEVICE
 *
 * Listens on SOCKET, an absolute path, and serves exactly the globals the
 * backend binds, at the versions it binds them: wl_seat 9, xdg_wm_base 6,
 * wl_compositor 6, wl_shm 1 and zwp_linux_dmabuf_v1 4. It never reads,
 * imports or draws a buffer. It reads the render formats through EGL on
 * MAIN_DEVICE before it listens; the GPU driver then keeps its own
 * descriptors to that node and its control nodes for the sink's whole
 * life: renderD128 once, nvidia0 five times and nvidiactl twice, at 77.7
 * MB resident, read from /proc/<pid>/fd and status after listen inside the
 * fence on cachy (NVIDIA 615.78.08) on 2026-10-19. The sink runs only inside
 * scripts/smoke/gpu-fence.sh, which keeps every amdgpu node out of its
 * reach (docs/decisions/D099-no-amdgpu-node-in-validation-runs.md).
 *
 * - The seat states a pointer and a keyboard and never sends an input
 *   event, so no input but the harness's virtual devices reaches the
 *   nested seat.
 * - Each toplevel gets one configure, at SINK_WIDTH x SINK_HEIGHT, on its
 *   first commit, and no other: nothing resizes the output under a mode a
 *   row holds.
 * - Each buffer is released at the commit that attaches it, and frame
 *   callbacks are done on a SINK_FRAME_NS clock of the sink's own.
 * - Every client gets an xdg_wm_base ping each SINK_PING_MS for its whole
 *   life (ping_tick).
 * - The dmabuf feedback names MAIN_DEVICE, a DRM render node, as the main
 *   device and its one tranche, over the modifiers EGL on that node renders
 *   to for SINK_FORMATS (make_format_table).
 * - Every file descriptor a request carries is closed once the request is
 *   handled (dispatch).
 *
 * SOCKET appears only once the sink listens on it, so a caller may connect
 * as soon as the path exists. Runs until it is signalled. Exit 2 on a bad
 * invocation or MAIN_DEVICE that is no character device, 1 when its
 * formats cannot be read, or the socket or the event loop cannot be set
 * up, printed as `sink: refused: <key>=<value>`.
 */
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <errno.h>
#include <fcntl.h>
#include <gbm.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/timerfd.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <wayland-server.h>
#include <xf86drm.h>
#include "xdg-shell-server-protocol.h"
#include "linux-dmabuf-v1-server-protocol.h"

/* 1920x1080 divides by 2, 3 and 4, so a hold at any whole scale of the
 * output's own mode leaves whole logical pixels. */
#define SINK_WIDTH 1920
#define SINK_HEIGHT 1080
/* 60 Hz. `qml-smoke.sh --rows bar` at this rate, the run that started at
 * 2026-10-19T05:57:47Z on cachy (AMD Ryzen 9 9950X), passed its bar row in
 * 249 s with its reconcile reading at cpu_some_pct=0.0 and its first bar
 * at 677 ms. */
#define SINK_FRAME_NS (1000000000L / 60)
/* aquamarine 0.15.1 queues a new output's requests and its announcement
 * in createOutput and sends them only once its display fd turns readable
 * (CWaylandBackend::dispatchEvents). The first output's start and every
 * `hyprctl output create wayland` after it wait for the next event the
 * sink sends, and an idle output gets none but a ping. This interval ping
 * stands in for aquamarine upstream 7bb8bdf, which flushes in createOutput
 * and lands after 0.15.1; the wait it bounds is this interval. */
#define SINK_PING_MS 100

/* The DRM fourcc codes (drm_fourcc.h) the table offers: XR24, AR24, XB24
 * and AB24. A table of these with DRM_FORMAT_MOD_INVALID alone made the
 * nested compositor allocate modifier-less buffers it could not render to
 * on NVIDIA (`rbo: glCheckFramebufferStatus failed`, `no RBO could be
 * obtained` in a `qml-smoke.sh --rows bar` run on cachy, 2026-10-19), so
 * the table carries the explicit modifiers EGL renders to instead. */
#define FOURCC(a, b, c, d) ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) | ((uint32_t)(d) << 24))
static const uint32_t SINK_FORMATS[] = {FOURCC('X', 'R', '2', '4'), FOURCC('A', 'R', '2', '4'), FOURCC('X', 'B', '2', '4'), FOURCC('A', 'B', '2', '4')};
#define SINK_FORMAT_COUNT (sizeof(SINK_FORMATS) / sizeof(SINK_FORMATS[0]))
/* The 16-byte entries of a dmabuf format table: format, padding, modifier. */
struct format_entry {
	uint32_t format;
	uint32_t pad;
	uint64_t modifier;
};
_Static_assert(sizeof(struct format_entry) == 16, "dmabuf format table entries are 16 bytes");

static struct wl_display *display;
static dev_t main_device;
static int format_table = -1;
static uint16_t format_entries;
/* Frame callbacks committed and waiting for the next frame tick. */
static struct wl_list due_frames;
/* Every bound xdg_wm_base, which ping_tick pings. */
static struct wl_list wm_bases;

/* One wl_surface. The xdg resources point back at it while it lives. */
struct surface {
	struct wl_resource *resource;
	struct wl_resource *xdg_surface;
	struct wl_resource *toplevel;
	bool configured;
	/* The buffer attached since the last commit, released at the next. */
	struct wl_resource *buffer;
	struct wl_listener buffer_destroy;
	/* Frame callbacks requested since the last commit. */
	struct wl_list frames;
};

/* A request's handler: NAME is the request's protocol name. */
struct handler {
	void (*request)(struct wl_resource *resource, const char *name, union wl_argument *args);
};

static void close_fds(const struct wl_message *message, union wl_argument *args) {
	int index = 0;
	for (const char *type = message->signature; *type; type++) {
		if (*type == '?' || (*type >= '0' && *type <= '9'))
			continue;
		if (*type == 'h')
			close(args[index].h);
		index++;
	}
}

/* Every resource of the sink dispatches here. The sink uses no fd a request
 * carries, so each one is closed here, whatever the request; a request
 * named destroy or release is each protocol's destructor here. */
static int dispatch(const void *data, void *target, uint32_t opcode, const struct wl_message *message, union wl_argument *args) {
	const struct handler *handler = data;
	struct wl_resource *resource = target;
	(void)opcode;
	if (handler && handler->request)
		handler->request(resource, message->name, args);
	close_fds(message, args);
	if (strcmp(message->name, "destroy") == 0 || strcmp(message->name, "release") == 0)
		wl_resource_destroy(resource);
	return 0;
}

/* A new resource ID of PARENT's client at PARENT's version. */
static struct wl_resource *child(struct wl_resource *parent, const struct wl_interface *interface, uint32_t id,
                                 const struct handler *handler, void *data, wl_resource_destroy_func_t destroy) {
	struct wl_resource *resource = wl_resource_create(wl_resource_get_client(parent), interface, wl_resource_get_version(parent), id);
	if (!resource) {
		wl_client_post_no_memory(wl_resource_get_client(parent));
		return NULL;
	}
	wl_resource_set_dispatcher(resource, dispatch, handler, data, destroy);
	return resource;
}

static void unlink_resource(struct wl_resource *resource) { wl_list_remove(wl_resource_get_link(resource)); }

static void buffer_destroyed(struct wl_listener *listener, void *data) {
	struct surface *surface = wl_container_of(listener, surface, buffer_destroy);
	(void)data;
	surface->buffer = NULL;
	wl_list_remove(&listener->link);
	wl_list_init(&listener->link);
}

static void surface_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	struct surface *surface = wl_resource_get_user_data(resource);
	if (strcmp(name, "attach") == 0) {
		wl_list_remove(&surface->buffer_destroy.link);
		wl_list_init(&surface->buffer_destroy.link);
		surface->buffer = (struct wl_resource *)args[0].o;
		if (surface->buffer)
			wl_resource_add_destroy_listener(surface->buffer, &surface->buffer_destroy);
	} else if (strcmp(name, "frame") == 0) {
		struct wl_resource *callback = wl_resource_create(wl_resource_get_client(resource), &wl_callback_interface, 1, args[0].n);
		if (!callback) {
			wl_client_post_no_memory(wl_resource_get_client(resource));
			return;
		}
		wl_resource_set_implementation(callback, NULL, NULL, unlink_resource);
		wl_list_insert(surface->frames.prev, wl_resource_get_link(callback));
	} else if (strcmp(name, "commit") == 0) {
		if (surface->toplevel && !surface->configured) {
			struct wl_array states;
			wl_array_init(&states);
			xdg_toplevel_send_configure(surface->toplevel, SINK_WIDTH, SINK_HEIGHT, &states);
			wl_array_release(&states);
			xdg_surface_send_configure(surface->xdg_surface, wl_display_next_serial(display));
			surface->configured = true;
		}
		if (surface->buffer) {
			wl_buffer_send_release(surface->buffer);
			wl_list_remove(&surface->buffer_destroy.link);
			wl_list_init(&surface->buffer_destroy.link);
			surface->buffer = NULL;
		}
		wl_list_insert_list(due_frames.prev, &surface->frames);
		wl_list_init(&surface->frames);
	}
}
static const struct handler surface_handler = {surface_request};

static void surface_destroyed(struct wl_resource *resource) {
	struct surface *surface = wl_resource_get_user_data(resource);
	wl_list_remove(&surface->buffer_destroy.link);
	if (surface->xdg_surface)
		wl_resource_set_user_data(surface->xdg_surface, NULL);
	if (surface->toplevel)
		wl_resource_set_user_data(surface->toplevel, NULL);
	/* Callbacks it never committed are done at the next tick. */
	wl_list_insert_list(due_frames.prev, &surface->frames);
	free(surface);
}

static void compositor_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	if (strcmp(name, "create_surface") == 0) {
		struct surface *surface = calloc(1, sizeof(*surface));
		if (!surface) {
			wl_client_post_no_memory(wl_resource_get_client(resource));
			return;
		}
		wl_list_init(&surface->frames);
		wl_list_init(&surface->buffer_destroy.link);
		surface->buffer_destroy.notify = buffer_destroyed;
		surface->resource = child(resource, &wl_surface_interface, args[0].n, &surface_handler, surface, surface_destroyed);
		if (!surface->resource)
			free(surface);
	} else if (strcmp(name, "create_region") == 0) {
		child(resource, &wl_region_interface, args[0].n, NULL, NULL, NULL);
	}
}
static const struct handler compositor_handler = {compositor_request};

static void shm_pool_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	if (strcmp(name, "create_buffer") == 0)
		child(resource, &wl_buffer_interface, args[0].n, NULL, NULL, NULL);
}
static const struct handler shm_pool_handler = {shm_pool_request};

static void shm_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	if (strcmp(name, "create_pool") == 0)
		child(resource, &wl_shm_pool_interface, args[0].n, &shm_pool_handler, NULL, NULL);
}
static const struct handler shm_handler = {shm_request};

static void params_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	if (strcmp(name, "create_immed") == 0) {
		child(resource, &wl_buffer_interface, args[0].n, NULL, NULL, NULL);
	} else if (strcmp(name, "create") == 0) {
		struct wl_resource *buffer = child(resource, &wl_buffer_interface, 0, NULL, NULL, NULL);
		if (buffer)
			zwp_linux_buffer_params_v1_send_created(resource, buffer);
	}
}
static const struct handler params_handler = {params_request};

static void send_feedback(struct wl_resource *feedback) {
	struct wl_array device, indices;
	wl_array_init(&device);
	wl_array_init(&indices);
	dev_t *slot = wl_array_add(&device, sizeof(main_device));
	if (slot)
		*slot = main_device;
	for (uint16_t i = 0; i < format_entries; i++) {
		uint16_t *index = wl_array_add(&indices, sizeof(*index));
		if (index)
			*index = i;
	}
	zwp_linux_dmabuf_feedback_v1_send_format_table(feedback, format_table, format_entries * sizeof(struct format_entry));
	zwp_linux_dmabuf_feedback_v1_send_main_device(feedback, &device);
	zwp_linux_dmabuf_feedback_v1_send_tranche_target_device(feedback, &device);
	zwp_linux_dmabuf_feedback_v1_send_tranche_formats(feedback, &indices);
	zwp_linux_dmabuf_feedback_v1_send_tranche_flags(feedback, 0);
	zwp_linux_dmabuf_feedback_v1_send_tranche_done(feedback);
	zwp_linux_dmabuf_feedback_v1_send_done(feedback);
	wl_array_release(&device);
	wl_array_release(&indices);
}

static void dmabuf_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	if (strcmp(name, "create_params") == 0) {
		child(resource, &zwp_linux_buffer_params_v1_interface, args[0].n, &params_handler, NULL, NULL);
	} else if (strcmp(name, "get_default_feedback") == 0 || strcmp(name, "get_surface_feedback") == 0) {
		struct wl_resource *feedback = child(resource, &zwp_linux_dmabuf_feedback_v1_interface, args[0].n, NULL, NULL, NULL);
		if (feedback)
			send_feedback(feedback);
	}
}
static const struct handler dmabuf_handler = {dmabuf_request};

static void seat_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	if (strcmp(name, "get_pointer") == 0)
		child(resource, &wl_pointer_interface, args[0].n, NULL, NULL, NULL);
	else if (strcmp(name, "get_keyboard") == 0)
		child(resource, &wl_keyboard_interface, args[0].n, NULL, NULL, NULL);
	else if (strcmp(name, "get_touch") == 0)
		child(resource, &wl_touch_interface, args[0].n, NULL, NULL, NULL);
}
static const struct handler seat_handler = {seat_request};

static void xdg_role_destroyed(struct wl_resource *resource) {
	struct surface *surface = wl_resource_get_user_data(resource);
	if (!surface)
		return;
	if (surface->toplevel == resource)
		surface->toplevel = NULL;
	if (surface->xdg_surface == resource) {
		surface->xdg_surface = NULL;
		if (surface->toplevel)
			wl_resource_set_user_data(surface->toplevel, NULL);
		surface->toplevel = NULL;
	}
}

static void xdg_surface_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	struct surface *surface = wl_resource_get_user_data(resource);
	if (strcmp(name, "get_toplevel") == 0) {
		struct wl_resource *toplevel = child(resource, &xdg_toplevel_interface, args[0].n, NULL, surface, xdg_role_destroyed);
		if (toplevel && surface)
			surface->toplevel = toplevel;
	} else if (strcmp(name, "get_popup") == 0) {
		child(resource, &xdg_popup_interface, args[0].n, NULL, NULL, NULL);
	}
}
static const struct handler xdg_surface_handler = {xdg_surface_request};

static void wm_base_request(struct wl_resource *resource, const char *name, union wl_argument *args) {
	if (strcmp(name, "create_positioner") == 0) {
		child(resource, &xdg_positioner_interface, args[0].n, NULL, NULL, NULL);
	} else if (strcmp(name, "get_xdg_surface") == 0) {
		struct surface *surface = wl_resource_get_user_data((struct wl_resource *)args[1].o);
		struct wl_resource *xdg_surface = child(resource, &xdg_surface_interface, args[0].n, &xdg_surface_handler, surface, xdg_role_destroyed);
		if (xdg_surface)
			surface->xdg_surface = xdg_surface;
	}
}
static const struct handler wm_base_handler = {wm_base_request};

static void bind_seat(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
	struct wl_resource *resource = wl_resource_create(client, &wl_seat_interface, version, id);
	(void)data;
	if (!resource) {
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_dispatcher(resource, dispatch, &seat_handler, NULL, NULL);
	wl_seat_send_capabilities(resource, WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD);
	if (version >= WL_SEAT_NAME_SINCE_VERSION)
		wl_seat_send_name(resource, "sink");
}

static void bind_wm_base(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
	struct wl_resource *resource = wl_resource_create(client, &xdg_wm_base_interface, version, id);
	(void)data;
	if (!resource) {
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_dispatcher(resource, dispatch, &wm_base_handler, NULL, unlink_resource);
	wl_list_insert(wm_bases.prev, wl_resource_get_link(resource));
}

static void bind_compositor(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
	struct wl_resource *resource = wl_resource_create(client, &wl_compositor_interface, version, id);
	(void)data;
	if (!resource) {
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_dispatcher(resource, dispatch, &compositor_handler, NULL, NULL);
}

static void bind_shm(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
	struct wl_resource *resource = wl_resource_create(client, &wl_shm_interface, version, id);
	(void)data;
	if (!resource) {
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_dispatcher(resource, dispatch, &shm_handler, NULL, NULL);
	wl_shm_send_format(resource, WL_SHM_FORMAT_ARGB8888);
	wl_shm_send_format(resource, WL_SHM_FORMAT_XRGB8888);
}

static void bind_dmabuf(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
	struct wl_resource *resource = wl_resource_create(client, &zwp_linux_dmabuf_v1_interface, version, id);
	(void)data;
	if (!resource) {
		wl_client_post_no_memory(client);
		return;
	}
	wl_resource_set_dispatcher(resource, dispatch, &dmabuf_handler, NULL, NULL);
}

static uint32_t now_ms(void) {
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return (uint32_t)(now.tv_sec * 1000 + now.tv_nsec / 1000000);
}

static void drain_timer(int fd) {
	uint64_t expirations;
	if (read(fd, &expirations, sizeof(expirations)) < 0 && errno != EAGAIN)
		fprintf(stderr, "sink: timer=read-failed errno=%d\n", errno);
}

static int frame_tick(int fd, uint32_t mask, void *data) {
	struct wl_resource *callback, *next;
	uint32_t time = now_ms();
	(void)mask;
	(void)data;
	drain_timer(fd);
	wl_resource_for_each_safe(callback, next, &due_frames) {
		wl_callback_send_done(callback, time);
		wl_resource_destroy(callback);
	}
	return 0;
}

static int ping_tick(int fd, uint32_t mask, void *data) {
	struct wl_resource *wm_base;
	(void)mask;
	(void)data;
	drain_timer(fd);
	wl_resource_for_each(wm_base, &wm_bases) xdg_wm_base_send_ping(wm_base, wl_display_next_serial(display));
	return 0;
}

static bool add_timer(struct wl_event_loop *loop, long interval_ns, wl_event_loop_fd_func_t tick) {
	struct itimerspec spec = {.it_interval = {interval_ns / 1000000000L, interval_ns % 1000000000L}};
	int fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
	spec.it_value = spec.it_interval;
	if (fd < 0 || timerfd_settime(fd, 0, &spec, NULL) < 0)
		return false;
	return wl_event_loop_add_fd(loop, fd, WL_EVENT_READABLE, tick, NULL) != NULL;
}

/* make_format_table NODE: the format table, every modifier EGL on the
 * render node NODE renders SINK_FORMATS with, those it can only sample
 * (external_only) left out: aquamarine 0.15.1 reads the table and no
 * tranche flag. Returns the step that failed, NULL once the table is
 * written. It closes its own descriptor and terminates its EGL display;
 * the driver's descriptors stay open (see the header). */
static const char *make_format_table(const char *node) {
	PFNEGLQUERYDMABUFMODIFIERSEXTPROC query_modifiers;
	struct format_entry entries[256];
	struct gbm_device *gbm = NULL;
	EGLDisplay egl = EGL_NO_DISPLAY;
	const char *failed = NULL;
	int fd = open(node, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return "open";
	if (drmGetNodeTypeFromFd(fd) != DRM_NODE_RENDER)
		failed = "not-a-render-node";
	else if (!(gbm = gbm_create_device(fd)))
		failed = "gbm-device";
	else if ((egl = eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm, NULL)) == EGL_NO_DISPLAY || !eglInitialize(egl, NULL, NULL))
		failed = "egl-display";
	else if (!strstr(eglQueryString(egl, EGL_EXTENSIONS), "EGL_EXT_image_dma_buf_import_modifiers") ||
	         !(query_modifiers = (PFNEGLQUERYDMABUFMODIFIERSEXTPROC)eglGetProcAddress("eglQueryDmaBufModifiersEXT")))
		failed = "egl-modifiers";
	for (size_t f = 0; !failed && f < SINK_FORMAT_COUNT; f++) {
		EGLuint64KHR modifiers[64];
		EGLBoolean external_only[64];
		EGLint count = 0;
		if (!query_modifiers(egl, (EGLint)SINK_FORMATS[f], 64, modifiers, external_only, &count))
			failed = "egl-query";
		for (EGLint m = 0; !failed && m < count; m++)
			if (!external_only[m] && format_entries < sizeof(entries) / sizeof(entries[0]))
				entries[format_entries++] = (struct format_entry){SINK_FORMATS[f], 0, modifiers[m]};
	}
	if (egl != EGL_NO_DISPLAY)
		eglTerminate(egl);
	if (gbm)
		gbm_device_destroy(gbm);
	close(fd);
	if (failed)
		return failed;
	if (format_entries == 0)
		return "no-format";
	format_table = memfd_create("vgs-sink-formats", MFD_CLOEXEC);
	if (format_table < 0 || write(format_table, entries, format_entries * sizeof(entries[0])) != (ssize_t)(format_entries * sizeof(entries[0])))
		return "memfd";
	return NULL;
}

/* Bind and listen on PATH.part, then rename it to PATH, so PATH exists only
 * once a connect to it succeeds. */
static int listen_socket(const char *path) {
	struct sockaddr_un address = {.sun_family = AF_UNIX};
	char part[sizeof(address.sun_path)];
	int fd;
	if (snprintf(part, sizeof(part), "%s.part", path) >= (int)sizeof(part)) {
		errno = ENAMETOOLONG;
		return -1;
	}
	strcpy(address.sun_path, part);
	fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return -1;
	unlink(part);
	if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0 || listen(fd, 16) < 0 || rename(part, path) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

int main(int argc, char **argv) {
	struct stat device;
	struct wl_event_loop *loop;
	int socket_fd;
	if (argc != 3 || argv[1][0] != '/') {
		fprintf(stderr, "sink: refused: usage=sink-SOCKET-MAIN_DEVICE\n");
		return 2;
	}
	if (stat(argv[2], &device) < 0 || !S_ISCHR(device.st_mode)) {
		fprintf(stderr, "sink: refused: main-device=%s\n", argv[2]);
		return 2;
	}
	main_device = device.st_rdev;
	wl_list_init(&due_frames);
	wl_list_init(&wm_bases);
	const char *format_failed = make_format_table(argv[2]);
	if (format_failed) {
		fprintf(stderr, "sink: refused: format-table=%s node=%s\n", format_failed, argv[2]);
		return 1;
	}
	display = wl_display_create();
	if (!display) {
		fprintf(stderr, "sink: refused: display=create-failed\n");
		return 1;
	}
	loop = wl_display_get_event_loop(display);
	if (!wl_global_create(display, &wl_seat_interface, 9, NULL, bind_seat) ||
	    !wl_global_create(display, &xdg_wm_base_interface, 6, NULL, bind_wm_base) ||
	    !wl_global_create(display, &wl_compositor_interface, 6, NULL, bind_compositor) ||
	    !wl_global_create(display, &wl_shm_interface, 1, NULL, bind_shm) ||
	    !wl_global_create(display, &zwp_linux_dmabuf_v1_interface, 4, NULL, bind_dmabuf)) {
		fprintf(stderr, "sink: refused: globals=create-failed\n");
		return 1;
	}
	if (!add_timer(loop, SINK_FRAME_NS, frame_tick) || !add_timer(loop, SINK_PING_MS * 1000000L, ping_tick)) {
		fprintf(stderr, "sink: refused: timer=errno-%d\n", errno);
		return 1;
	}
	socket_fd = listen_socket(argv[1]);
	if (socket_fd < 0 || wl_display_add_socket_fd(display, socket_fd) < 0) {
		fprintf(stderr, "sink: refused: socket=%s errno=%d\n", argv[1], errno);
		return 1;
	}
	fprintf(stderr, "sink: listening socket=%s main-device=%u:%u formats=%u size=%dx%d\n", argv[1], major(main_device), minor(main_device), format_entries, SINK_WIDTH, SINK_HEIGHT);
	wl_display_run(display);
	return 0;
}
