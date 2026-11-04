import QtQuick

// Probe.popupLoad supplies the real service. Read its existing AppSounds
// owner without another tracker or a signal observer between audio reads.
Item {
    visible: false

    required property var service
    property string attachmentStatus: "unavailable:attaching"

    function owners() {
        if (service === null) {
            attachmentStatus = "unavailable:service-absent";
            return null;
        }
        // Probe.typeName uses this suffix normalization for QML instances.
        const found = [service];
        for (let i = 0; i < found.length; i++)
            for (const child of found[i].children || []) found.push(child);
        const matches = found.filter(object => String(object).split("(")[0].replace(/(_QML(TYPE)?_\d+)+$/, "") === "AppSounds");
        if (matches.length !== 1) {
            attachmentStatus = "unavailable:app-sounds-count=" + matches.length;
            return null;
        }
        const sounds = matches[0];
        const writers = Array.from(sounds.children).filter(object => String(object).split("(")[0].replace(/(_QML(TYPE)?_\d+)+$/, "") === "Supervised" && object.label === "app sounds: writer");
        if (writers.length !== 1) {
            attachmentStatus = "unavailable:writer-count=" + writers.length;
            return null;
        }
        attachmentStatus = "attached";
        return { sounds: sounds, writer: writers[0] };
    }

    function nodeFields(node) {
        if (node === null || node === undefined) return null;
        // AppSounds owns the binding. PwNode exposes the id, name and bound
        // properties: https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.Pipewire/PwNode
        const serial = (node.properties || {})["object.serial"];
        return { name: node.name, id: node.id, serial: typeof serial === "string" ? serial : null, identity: String(node) };
    }

    function capture() {
        const current = owners();
        const record = { at: Date.now(), status: attachmentStatus, claims: null, streams: null, writer: null };
        if (current !== null) {
            const sounds = current.sounds;
            record.claims = Object.keys(sounds.holds).filter(serial => sounds.holds[serial].node !== null && sounds.holds[serial].node.name === "smoke-ping-held").map(serial => {
                const claim = sounds.holds[serial];
                return { serial: serial, phase: claim.hold.phase, until: claim.hold.until, role: claim.hold.role, node: nodeFields(claim.node), tracked: sounds.streams.some(entry => entry.node === claim.node) };
            });
            record.streams = sounds.streams.filter(entry => entry.node !== null && entry.node.name === "smoke-ping-held").map(entry => ({ serial: entry.serial, node: nodeFields(entry.node), free: entry.free, judged: entry.judged }));
            record.writer = { pid: current.writer.processId, running: current.writer.running };
        }
        console.info("VGS_APP_SOUND_READ " + JSON.stringify(record));
    }

    Component.onCompleted: owners()
}
