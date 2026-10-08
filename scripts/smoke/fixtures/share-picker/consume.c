/* One frame from the portal's PipeWire descriptor, with no video device.
 * Format negotiation follows PipeWire's src/examples/video-play.c.
 * https://github.com/PipeWire/pipewire/blob/master/src/examples/video-play.c
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>
struct capture {
    struct pw_main_loop *loop;
    struct pw_core *core;
    struct pw_core *policy;
    int link_sync;
    struct pw_proxy *link;
    uint32_t target;
    struct pw_stream *stream;
    struct spa_video_info_raw format;
    const char *path;
    int result;
};
static void format(void *userdata, uint32_t id, const struct spa_pod *param) {
    struct capture *capture = userdata;
    if (id != SPA_PARAM_Format || param == NULL) return;
    if (spa_format_video_raw_parse(param, &capture->format) < 0) {
        capture->result = 1;
        pw_main_loop_quit(capture->loop);
    }
    fprintf(stderr, "consume: format=%u size=%ux%u\n", capture->format.format,
            capture->format.size.width, capture->format.size.height);
}
static void core_error(void *userdata, uint32_t id, int seq, int result, const char *message) {
    (void)seq;
    struct capture *capture = userdata;
    fprintf(stderr, "consume: core object=%u result=%d error=%s\n", id, result, message);
    capture->result = 1;
    pw_main_loop_quit(capture->loop);
}
static void policy_done(void *userdata, uint32_t id, int seq) {
    struct capture *capture = userdata;
    if (id != PW_ID_CORE || seq != capture->link_sync || capture->link) return;
    /* OpenPipeWireRemote hides the link factory from the application.
     * This private connection does the session manager's link operation.
     * The application still reads through the portal's restricted descriptor.
     * https://github.com/flatpak/xdg-desktop-portal/blob/main/desktop-portal/screen-cast.c
     */
    struct pw_properties *properties = pw_properties_new(NULL, NULL);
    pw_properties_setf(properties, PW_KEY_LINK_OUTPUT_NODE, "%u", capture->target);
    pw_properties_setf(properties, PW_KEY_LINK_INPUT_NODE, "%u", pw_stream_get_node_id(capture->stream));
    capture->link = pw_core_create_object(capture->policy, "link-factory", PW_TYPE_INTERFACE_Link,
                                          PW_VERSION_LINK, &properties->dict, 0);
    pw_properties_free(properties);
    if (!capture->link) pw_main_loop_quit(capture->loop);
}
static void state(void *userdata, enum pw_stream_state old, enum pw_stream_state current, const char *error) {
    struct capture *capture = userdata;
    fprintf(stderr, "consume: state=%s->%s node=%u\n", pw_stream_state_as_string(old),
            pw_stream_state_as_string(current), pw_stream_get_node_id(capture->stream));
    if (current == PW_STREAM_STATE_PAUSED && capture->link == NULL) {
        /* No session manager is started. The documented link factory chooses
         * the single free port on each video node when ports are omitted.
         * https://github.com/PipeWire/pipewire/blob/master/src/modules/module-link-factory.c
         */
        capture->link_sync = pw_core_sync(capture->policy, PW_ID_CORE, capture->link_sync);
    }
    if (current == PW_STREAM_STATE_ERROR) {
        fprintf(stderr, "consume: stream=%s\n", error ? error : "failed");
        capture->result = 1;
        pw_main_loop_quit(capture->loop);
    }
}
static void process(void *userdata) {
    struct capture *capture = userdata;
    struct pw_buffer *buffer = pw_stream_dequeue_buffer(capture->stream);
    if (buffer == NULL) return;
    struct spa_buffer *spa = buffer->buffer;
    fprintf(stderr, "consume: frame datas=%u\n", spa->n_datas);
    uint32_t width = capture->format.size.width, height = capture->format.size.height;
    if (!spa->n_datas || !spa->datas[0].data || !spa->datas[0].chunk || !width || !height) goto done;
    struct spa_data *data = &spa->datas[0];
    int32_t stride = data->chunk->stride;
    if (stride <= 0 || stride < (int32_t)(width * 4) ||
        (uint64_t)data->chunk->offset + (uint64_t)stride * height > data->maxsize) goto done;
    FILE *file = fopen(capture->path, "wb");
    if (!file) { capture->result = 1; pw_main_loop_quit(capture->loop); goto done; }
    int failed = fprintf(file, "P6\n%u %u\n255\n", width, height) < 0;
    int blue_first = capture->format.format == SPA_VIDEO_FORMAT_BGRx || capture->format.format == SPA_VIDEO_FORMAT_BGRA;
    for (uint32_t y = 0; y < height && !failed; y++) {
        uint8_t *row = (uint8_t *)data->data + data->chunk->offset + y * stride;
        for (uint32_t x = 0; x < width; x++) {
            uint8_t rgb[3] = {row[x * 4 + (blue_first ? 2 : 0)], row[x * 4 + 1], row[x * 4 + (blue_first ? 0 : 2)]};
            if (fwrite(rgb, 1, sizeof(rgb), file) != sizeof(rgb)) { failed = 1; break; }
        }
    }
    if (fclose(file)) failed = 1;
    capture->result = failed;
    pw_main_loop_quit(capture->loop);
done:
    pw_stream_queue_buffer(capture->stream, buffer);
}
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    pw_init(&argc, &argv);
    struct capture capture = {.path = argv[3], .result = 1};
    capture.loop = pw_main_loop_new(NULL);
    if (!capture.loop) return 1;
    struct pw_context *context = pw_context_new(pw_main_loop_get_loop(capture.loop), NULL, 0);
    if (!context) return 1;
    struct pw_core *core = pw_context_connect_fd(context, atoi(argv[1]), NULL, 0);
    if (!core) return 1;
    capture.core = core;
    capture.policy = pw_context_connect(context, NULL, 0);
    if (!capture.policy) return 1;
    static const struct pw_core_events core_events = {PW_VERSION_CORE_EVENTS, .error = core_error};
    static const struct pw_core_events policy_events = {PW_VERSION_CORE_EVENTS, .error = core_error, .done = policy_done};
    struct spa_hook core_listener, policy_listener;
    pw_core_add_listener(core, &core_listener, &core_events, &capture);
    pw_core_add_listener(capture.policy, &policy_listener, &policy_events, &capture);
    capture.target = (uint32_t)strtoul(argv[2], NULL, 10);
    capture.stream = pw_stream_new(core, "VGS portal fixture", pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY, "Capture", PW_KEY_MEDIA_ROLE, "Screen", NULL));
    if (!capture.stream) return 1;
    static const struct pw_stream_events events = {
        PW_VERSION_STREAM_EVENTS, .state_changed = state, .param_changed = format, .process = process};
    struct spa_hook listener;
    pw_stream_add_listener(capture.stream, &listener, &events, &capture);
    uint8_t buffer[1024];
    struct spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
    const struct spa_pod *parameters[] = {spa_pod_builder_add_object(&builder,
        SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat,
        SPA_FORMAT_mediaType, SPA_POD_Id(SPA_MEDIA_TYPE_video),
        SPA_FORMAT_mediaSubtype, SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw),
        SPA_FORMAT_VIDEO_format, SPA_POD_CHOICE_ENUM_Id(4, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRA, SPA_VIDEO_FORMAT_RGBx, SPA_VIDEO_FORMAT_RGBA),
        SPA_FORMAT_VIDEO_size, SPA_POD_CHOICE_RANGE_Rectangle(&SPA_RECTANGLE(320, 200), &SPA_RECTANGLE(1, 1), &SPA_RECTANGLE(8192, 8192)),
        SPA_FORMAT_VIDEO_framerate, SPA_POD_CHOICE_RANGE_Fraction(&SPA_FRACTION(30, 1), &SPA_FRACTION(0, 1), &SPA_FRACTION(240, 1)))};
    if (pw_stream_connect(capture.stream, PW_DIRECTION_INPUT, PW_ID_ANY,
                          PW_STREAM_FLAG_MAP_BUFFERS, parameters, 1) < 0) return 1;
    pw_main_loop_run(capture.loop);
    pw_stream_destroy(capture.stream);
    if (capture.link) pw_proxy_destroy(capture.link);
    pw_core_disconnect(capture.policy);
    pw_core_disconnect(core);
    pw_context_destroy(context);
    pw_main_loop_destroy(capture.loop);
    pw_deinit();
    return capture.result;
}
