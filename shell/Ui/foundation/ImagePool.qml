pragma Singleton
import QtQuick

// The shared loader of the local images `ImageText` draws inline. An entry
// is one asynchronous `Image` per URL and device-pixel size, shared by every
// holder in the shell. The pool owns every image it creates: a released
// entry stays, idle, so the next holder of the same image draws it at once;
// the pool destroys an idle entry when `idleCeiling` newer releases push it
// out, and an entry whose load failed, at its last release or at the next
// `acquire` of a load that failed while idle. A re-created
// entry decodes its image again: in the notifications row's emoji toast
// (scripts/qml-smoke.sh, host cachy, 2026-10-10) that decode held the
// toast's first frame 42-79 ms after its text, against 27 ms for a held one.
//
// The entry is what makes the inline image load off the GUI thread. A
// StyledText `<img>` loads its image synchronously, and first looks for it
// in Qt's pixmap cache under its URL, its request size in device pixels,
// no clip region, frame 0 and default provider options. An asynchronous
// `Image` with those values puts its entry into that cache before its
// reader thread decodes it, so a text that names the image after the entry
// exists waits for that load instead of decoding it itself
// (Qt 6.11). An entry's `Image` therefore keeps
// the default fill mode and no clip, and sets `sourceSize` before its
// `source`.
//
// `acquire` answers the entry's `Image`, whose `status` the holder watches;
// every `acquire` is matched by one `release` of the same image.
QtObject {
    id: pool

    // The most images one ImageText names: a Slack body substitutes at
    // most EMOJI_PER_BODY emoji (vgs.notifications/NotificationLogic.js).
    readonly property int idleCeiling: 64

    // "<device size>@<url>" -> { image, holders }.
    property var entries: ({})
    // The keys of the entries no holder holds, oldest release first.
    property var idle: []

    readonly property Component loader: Component {
        Image {
            property string poolKey: ""
            asynchronous: true
            cache: true
            visible: false
        }
    }

    function keyOf(url, deviceSize) {
        return deviceSize + "@" + url;
    }

    function acquire(url, deviceSize) {
        const key = keyOf(url, deviceSize);
        let entry = entries[key];
        if (entry !== undefined && entry.holders === 0) {
            idle.splice(idle.indexOf(key), 1);
            // A load that failed after its last release is tried again.
            if (entry.image.status === Image.Error) {
                drop(key);
                entry = undefined;
            }
        }
        if (entry === undefined) {
            const image = loader.createObject(null, { poolKey: key, sourceSize: Qt.size(deviceSize, deviceSize), source: url });
            if (image === null) {
                console.error("ImagePool: image not created url=" + url);
                return null;
            }
            entry = { image: image, holders: 0 };
            entries[key] = entry;
        }
        entry.holders += 1;
        return entry.image;
    }

    function release(image) {
        const key = image.poolKey;
        const entry = entries[key];
        if (entry === undefined || entry.holders === 0 || entry.image !== image) {
            console.error("ImagePool: release of an image no holder holds url=" + image.source);
            return;
        }
        entry.holders -= 1;
        if (entry.holders > 0) return;
        // A failed load is not kept: the file may appear later.
        if (image.status === Image.Error) {
            drop(key);
            return;
        }
        idle.push(key);
        if (idle.length > idleCeiling) drop(idle.shift());
    }

    function drop(key) {
        entries[key].image.destroy();
        delete entries[key];
    }
}
