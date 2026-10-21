// Only add-check, add-key, remove-key, providers, key-page, voice-key,
// stored and presence are public CLI verbs. A key never reaches stdout.
// providers WIDTH prints Add key's provider choices,
// AccountProviders.choiceLine lines with each provider's key page; key-page
// PROVIDER prints its label, key page and page name, empty where it has
// none; voice-key PROVIDER prints the key a cloud voice PROVIDER
// (voiceProvider) uses, as `id TAB company TAB product TAB page TAB page
// name TAB the name its next key takes`; stored WIDTH prints Remove key's,
// each remembered key with the provider and name remove-key takes.
// add-check PROVIDER ACCOUNT refuses, before the window asks for the key,
// what add-key would refuse of the key list; add-key PROVIDER ACCOUNT reads
// the key from its stdin, the pipe from the add-key window's masked box, to
// its end, with one trailing line feed dropped.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const tty = require("node:tty");
const { Secrets, ownReference } = require("./Secrets.js");
const { PROVIDERS, cloudVoice, storedKeyProvider, parseWidth, providerChoices, choiceLine } = require("../AccountProviders.js");

// The exit status of each refusal the add-key window words by its cause
// (tui/add-key.sh): an empty box, a paste too long for a key, a name too
// long, a full key list, a voice that takes no key. Every other refusal
// exits 1, and the window points to the log.
const EXIT_STATUS = {
    "store=empty": 3,
    "store=oversize": 4,
    "reference=identity": 5,
    "references=limit": 6,
    "references=size": 6,
    "arguments=voice": 7
};

// The key on stdin, to its end and at most one byte past secret-tool's
// buffer, with one trailing line feed, which gum's masked box ends it
// with, dropped. The caller zeroes it (Secrets.addKey).
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

// The reference add-key and add-check take from PROVIDER and ACCOUNT. The
// key is bound to the provider's own origin, so a typed id that names no
// stored key provider would store a key no AI model or voice can use.
function addedReference() {
    if (process.argv.length !== 5) throw new Error("jarvis-keys: arguments=metadata");
    const [provider, account] = process.argv.slice(3);
    const row = PROVIDERS.find(item => item.id === provider && storedKeyProvider(item));
    if (row === undefined) throw new Error("jarvis-keys: provider=unknown");
    return ownReference(row.id, account, row.origin);
}

function main() {
    const directory = path.join(process.env.XDG_STATE_HOME || path.join(process.env.HOME, ".local/state"), "vgshell/jarvis");
    const store = new Secrets(directory, process.env);
    switch (process.argv[2]) {
    case "presence":
        if (process.argv.length !== 3) throw new Error("jarvis-keys: arguments=verb");
        process.stdout.write(JSON.stringify(store.rows()) + "\n");
        break;
    case "providers": {
        const width = process.argv.length === 4 ? parseWidth(process.argv[3]) : null;
        if (width === null) throw new Error("jarvis-keys: arguments=width");
        process.stdout.write(providerChoices("key", width, true).join("\n") + "\n");
        break;
    }
    case "add-check": {
        store.checkAdd(addedReference());
        break;
    }
    case "add-key": {
        const ref = addedReference();
        // isatty, not process.stdin.isTTY: the stdin getter opens fd 0 as a
        // libuv pipe stream, which sets O_NONBLOCK on it, and pastedKey's
        // readSync would then fail with EAGAIN while the window waits for
        // the key instead of blocking in the kernel.
        if (tty.isatty(0)) throw new Error("jarvis-keys: store=pipe-required");
        store.addKey(ref, pastedKey());
        process.stdout.write("jarvis-keys: stored=libsecret\n");
        break;
    }
    case "key-page": {
        const row = process.argv.length === 4 ? PROVIDERS.find(item => item.id === process.argv[3] && storedKeyProvider(item)) : undefined;
        if (row === undefined) throw new Error("jarvis-keys: arguments=provider");
        process.stdout.write([row.label, row.keyPage ?? "", row.keyPageName ?? ""].join("\t") + "\n");
        break;
    }
    case "voice-key": {
        const voice = process.argv.length === 4 ? cloudVoice(process.argv[3]) : null;
        if (voice === null) throw new Error("jarvis-keys: arguments=voice");
        const row = PROVIDERS.find(item => item.id === voice.provider && storedKeyProvider(item));
        const taken = new Set(store.references().filter(ref => ref.provider === row.id).map(ref => ref.account));
        let next = 1;
        while (taken.has("key " + next)) next += 1;
        process.stdout.write([row.id, row.label, voice.product, row.keyPage, row.keyPageName, "key " + next].join("\t") + "\n");
        break;
    }
    case "stored": {
        const width = process.argv.length === 4 ? parseWidth(process.argv[3]) : null;
        if (width === null) throw new Error("jarvis-keys: arguments=width");
        process.stdout.write(store.references().map(ref =>
            choiceLine(ref.provider + " / " + ref.account, ref.provider + "\t" + ref.account, width) + "\n").join(""));
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
