pragma Singleton
import QtQuick
import Quickshell

// The one pager of IPC replies that grow with the plugin set. `answer`
// hands back a reply within `replyChars` UTF-16 characters as it is, and
// keeps a longer one as slices, answering `paged=<id>`; `page` hands out
// one slice at a time as `<pages> <slice>`. `bin/lib/ipc-reply.sh`
// `vgs_ipc_pages` is the one reader, through the `shell page` call.
// Quickshell 0.3.1's IPC server deletes its socket after writing, so a
// reply past the socket's send buffer races the read; the bound keeps
// every reply well under it.
Singleton {
    id: root

    // The smoke harness's ipc_reply_chars equals this; the notifications
    // row reads both.
    readonly property int replyChars: 32768
    // The eight newest paged replies, by id; a reader that falls further
    // behind reads `absent`.
    readonly property int keptReplies: 8
    property int nextId: 1
    property var slicesById: ({})
    property var order: []

    function answer(text) {
        if (typeof text !== "string" || text.length <= root.replyChars) return text;
        const id = String(root.nextId++);
        const sliceChars = root.replyChars - 16;
        const slices = [];
        let start = 0;
        while (start < text.length) {
            let end = Math.min(start + sliceChars, text.length);
            // A slice never ends between the two halves of a surrogate pair.
            if (end < text.length) {
                const before = text.charCodeAt(end - 1);
                if (before >= 0xd800 && before <= 0xdbff) end -= 1;
            }
            slices.push(text.slice(start, end));
            start = end;
        }
        root.slicesById[id] = slices;
        root.order = root.order.concat([id]);
        while (root.order.length > root.keptReplies) delete root.slicesById[root.order.shift()];
        return "paged=" + id;
    }

    // Page INDEX of reply ID: `<pages> <slice>`, `absent` for an id no
    // longer kept, or `refused: page=<index> pages=<n>` out of range.
    // Handing out the last page drops the reply.
    function page(id, index) {
        const slices = root.slicesById[id];
        if (slices === undefined) return "absent";
        const pages = slices.length;
        if (index < 0 || index >= pages) return "refused: page=" + index + " pages=" + pages;
        const out = pages + " " + slices[index];
        if (index === pages - 1) {
            delete root.slicesById[id];
            root.order = root.order.filter(kept => kept !== id);
        }
        return out;
    }
}
