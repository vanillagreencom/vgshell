// Only add-key, remove-key and presence are public CLI verbs. A key never
// reaches stdout. add-key new|replace PROVIDER ACCOUNT reads the key from
// its stdin, the pipe the Providers and keys editor's save writes
// (KeyEditor.qml), to its end, with one trailing line feed dropped: `new`
// for an Add, which refuses a key the list holds, and `replace` for an
// Edit (Secrets.addKey); remove-key PROVIDER ACCOUNT
// removes one remembered key; presence prints each key's presence.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const tty = require("node:tty");
const { Secrets, ownReference } = require("./Secrets.js");
const { PROVIDERS, storedKeyProvider } = require("../AccountProviders.js");

// The exit status of each refusal the key editor words by its cause
// (AccountStatus.saveFailure): an empty field, a paste too long for a key,
// a name too long, a full key list, an Add of a key the list holds. Every
// other refusal exits 1.
const EXIT_STATUS = {
    "store=empty": 3,
    "store=oversize": 4,
    "reference=identity": 5,
    "references=limit": 6,
    "references=size": 6,
    "store=exists": 8
};

// The key on stdin, to its end and at most one byte past secret-tool's
// buffer, with one trailing line feed dropped. The caller zeroes it
// (Secrets.addKey).
function pastedKey() {
    const chunks = [];
    let length = 0;
    const chunk = Buffer.alloc(4096);
    for (;;) {
        let read;
        try { read = fs.readSync(0, chunk, 0, chunk.length, null); }
        catch {
            chunk.fill(0);
            throw new Error("jarvis-keys: store=stdin-unreadable");
        }
        if (read === 0) break;
        chunks.push(Buffer.from(chunk.subarray(0, read)));
        length += read;
        if (length > 8193) break;
    }
    chunk.fill(0);
    const key = Buffer.concat(chunks, length);
    for (const part of chunks) part.fill(0);
    return key.length > 0 && key[key.length - 1] === 0x0a ? key.subarray(0, key.length - 1) : key;
}

// The mode and reference add-key takes from MODE, PROVIDER and ACCOUNT. The
// key is bound to the provider's own origin, so a typed id that names no
// stored key provider would store a key no AI model or voice can use.
function addedReference() {
    if (process.argv.length !== 6 || !["new", "replace"].includes(process.argv[3])) throw new Error("jarvis-keys: arguments=metadata");
    const [mode, provider, account] = process.argv.slice(3);
    const row = PROVIDERS.find(item => item.id === provider && storedKeyProvider(item));
    if (row === undefined) throw new Error("jarvis-keys: provider=unknown");
    return { mode, ref: ownReference(row.id, account, row.origin) };
}

function main() {
    const directory = path.join(process.env.XDG_STATE_HOME || path.join(process.env.HOME, ".local/state"), "vgshell/jarvis");
    const store = new Secrets(directory, process.env);
    switch (process.argv[2]) {
    case "presence":
        if (process.argv.length !== 3) throw new Error("jarvis-keys: arguments=verb");
        process.stdout.write(JSON.stringify(store.rows()) + "\n");
        break;
    case "add-key": {
        const { mode, ref } = addedReference();
        // isatty, not process.stdin.isTTY: the stdin getter opens fd 0 as a
        // libuv pipe stream, which sets O_NONBLOCK on it, and pastedKey's
        // readSync would then fail with EAGAIN while the writer has not
        // sent the key yet, instead of blocking in the kernel.
        if (tty.isatty(0)) throw new Error("jarvis-keys: store=pipe-required");
        store.addKey(ref, pastedKey(), mode);
        process.stdout.write("jarvis-keys: stored=libsecret\n");
        break;
    }
    case "remove-key": {
        if (process.argv.length !== 5) throw new Error("jarvis-keys: arguments=metadata");
        const own = store.removeKey(process.argv[3], process.argv[4]);
        process.stdout.write("jarvis-keys: removed=" + (own ? "libsecret" : "reference") + "\n");
        break;
    }
    default: throw new Error("jarvis-keys: arguments=verb");
    }
}
try { main(); }
catch (error) {
    const reason = error.message.startsWith("jarvis-keys:") ? error.message : "jarvis-keys: operation=failed";
    process.stderr.write(reason + "\n");
    process.exitCode = EXIT_STATUS[reason.slice("jarvis-keys: ".length)] ?? 1;
}
