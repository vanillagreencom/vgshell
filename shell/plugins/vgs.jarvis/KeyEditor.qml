import QtQuick
import Quickshell
import Quickshell.Io
import "AccountProviders.js" as Providers
import "AccountStatus.js" as Words

// The one owner of Jarvis's key writes, Checks and removals, and of the
// Providers and keys list on Setup (the manifest's `providerKeys`): it
// publishes the list from `accounts`' stored keys and the settings, and
// the editor's Provider choices, and it handles every press of the
// plugin's actions of route `handler` (PluginStatus.handleActions): Add
// API key on the list, on the AI model and Voice steps and in the API key
// field, a row's Edit, Check, Remove and Remove from Jarvis, and the
// editor's save and cancel.
//
// A save hands the typed key to `keys.js add-key` on its stdin and then
// closes stdin (docs/architecture/secrets.md): the key lives only in the
// closure that writes it once the process has started, never in a
// property, an argument, a log line or status. A Check runs the account
// judge's explicit Verify (`accounts.js verify ID user`), whose result
// Accounts.verify records; a removal runs `keys.js remove-key`. Each ends
// by reading the keys again through `accounts` and `keys`. Nothing here
// opens the browser: the editor's key page link is the user's own press.
Item {
    id: root

    property var shell: null
    required property Item accounts
    required property Item keys

    readonly property string keysProgram: String(Qt.resolvedUrl("backend/keys.js")).replace(/^file:\/\//, "")
    readonly property string accountsProgram: String(Qt.resolvedUrl("backend/accounts.js")).replace(/^file:\/\//, "")
    readonly property var keyList: accounts.keyList
    readonly property var settings: shell === null ? null : shell.settings
    readonly property var voice: settings === null ? null : Providers.cloudVoice(settings.voiceProvider)
    // The account id whose Check runs, "" for none.
    property string checking: ""
    // The save that runs, { provider, name, target, done, feed }, or null.
    property var storing: null
    // The Voice provider a choice replaced to open the editor, put back
    // if the user cancels it: { value }, or null.
    property var restore: null
    // The key a finished save serves, { provider, name, target }, until
    // the read that follows it names its account id.
    property var serving: null
    // The key whose removal runs, { id, used }, or null.
    property var removing: null
    // Account id -> the state its row reads in place of its status after a
    // Check or a removal that did not finish, until the user tries again.
    property var faults: ({})
    // Signals the service that a key in use changed, so it ends the
    // conversation that uses it (Service.qml keysChanged).
    signal inUseChanged()

    onKeyListChanged: { publish(); select(); }
    onSettingsChanged: publish()
    onCheckingChanged: publish()
    onFaultsChanged: publish()

    // Register the action handler and publish the Provider choices once,
    // when this item's own `shell` first arrives: the service's shell
    // change runs before this binding takes the new value, so the service
    // starts nothing here. A later shell, one per settings change, belongs
    // to the same instance, whose handler stays registered.
    property bool started: false
    onShellChanged: startOnce()
    Component.onCompleted: startOnce()
    function startOnce() {
        if (shell === null || started) return;
        started = true;
        start();
    }
    function start() {
        const reply = shell.status.handleActions((press, done) => handle(press, done));
        if (reply !== "ok") console.warn("jarvis-keys: actions=" + reply);
        const offered = shell.status.set("keyProviders", Providers.keyProviderChoices());
        if (!shell.status.isOk(offered)) console.warn("jarvis-keys: providers=" + offered);
        publish();
    }

    // While no read of the keys has an answer, the list is withdrawn, and
    // with it its Add API key: a form over an unread list could not tell a
    // new key from one stored already.
    function publish() {
        if (shell === null) return;
        if (keyList === undefined) {
            const cleared = shell.status.set("providerKeys", null);
            if (!shell.status.isOk(cleared)) console.warn("jarvis-keys: list=" + cleared);
            return;
        }
        const rows = Words.keyRows(keyList, checking, settings, voice).map(row =>
            Object.prototype.hasOwnProperty.call(faults, row.id) ? Object.assign({}, row, { state: faults[row.id] }) : row);
        const reply = shell.status.set("providerKeys", rows);
        if (!shell.status.isOk(reply)) console.warn("jarvis-keys: list=" + reply);
    }

    function fault(id, state) {
        const next = Object.assign({}, faults);
        if (state === null) delete next[id];
        else next[id] = state;
        faults = next;
    }

    function keyOf(id) {
        return keyList === undefined ? null : keyList.find(key => key.id === id) || null;
    }

    // The name a new key of PROVIDER takes: its label, or the label and the
    // first free number after it, so no two keys of one provider share it.
    function freshName(provider) {
        const label = Providers.PROVIDERS.find(row => row.id === provider).label;
        const taken = keyList.filter(key => key.provider === provider).map(key => key.name);
        if (taken.indexOf(label) === -1) return label;
        let next = 2;
        while (taken.indexOf(label + " " + next) !== -1) next += 1;
        return label + " " + next;
    }

    // Open the editor for the selected cloud voice's provider, fixed, to
    // save and use for the API key field.
    function openVoice() {
        if (voice === null) return "refused: editor=providerKeys reason=choice";
        if (keyList === undefined) return "refused: action=providerKeys reason=not-offered";
        return shell.status.openEditor("providerKeys", { choice: voice.provider, fixed: true, name: freshName(voice.provider),
            target: "voiceAccount", title: "Add API key for " + voice.product });
    }

    function handle(press, done) {
        if (press.action === "save") return save(press, done);
        if (press.action === "cancel") return cancel(press);
        // Any other open starts no Provider choice, so its Cancel puts
        // nothing back.
        restore = null;
        if (keyList === undefined) return "refused: action=" + press.key + " reason=not-offered";
        switch (press.key + "/" + press.action) {
        case "providerKeys/": return shell.status.openEditor("providerKeys", {});
        case "providerKeys/edit": return shell.status.openEditor("providerKeys", { row: press.row });
        case "providerKeys/check": return check(press.row);
        case "providerKeys/remove":
        case "providerKeys/forget": return remove(press.row);
        case "setupModel/key": return shell.status.openEditor("providerKeys", { target: "brain" });
        case "setupVoice/key":
        case "voiceAccount/add": return openVoice();
        }
        return "refused: action=" + press.key + " reason=undeclared";
    }

    // A choice of PREVIOUS's replacement as the Voice provider with no key
    // of its company stored continues into the editor; Cancel there puts
    // PREVIOUS back (Service.qml voiceChosen).
    function providerNeedsKey(previous) {
        const reply = openVoice();
        if (reply === "ok") restore = { value: previous };
        else console.warn("jarvis-keys: provider-editor=" + reply);
    }

    function cancel(press) {
        const back = restore;
        restore = null;
        if (back !== null && press.target === "voiceAccount" && shell.configure.set("voiceProvider", back.value) !== "ok")
            console.warn("jarvis-keys: provider-restore=refused");
        return "ok";
    }

    // One key operation runs at a time: a save waits for a running save,
    // removal or Check, so a Check never answers for a key replaced under it.
    function save(press, done) {
        if (keyList === undefined) {
            done({ ok: false, text: "Jarvis could not read your keys yet. Try again in a moment." });
            return "ok";
        }
        if (storing !== null || removing !== null || checking !== "") {
            done({ ok: false, text: "Jarvis is busy with another key. Try again when it ends." });
            return "ok";
        }
        let provider = press.choice, name = press.name;
        if (press.row !== "") {
            const key = keyOf(press.row);
            if (key === null || !key.own) {
                done({ ok: false, text: "That key is no longer in the list." });
                return "ok";
            }
            provider = key.provider;
            name = key.name;
        } else if (keyList.some(key => key.provider === provider && key.name === name)) {
            done({ ok: false, text: "A key with that name is already stored. Choose another name, or use Edit to replace it." });
            return "ok";
        }
        const secret = press.secret;
        storing = { provider: provider, name: name, target: press.target, row: press.row, done: done,
            feed: () => { writer.write(secret); writer.stdinEnabled = false; } };
        writer.exitCode = null;
        writer.stdinEnabled = true;
        // keys.js judges the mode: `new` refuses a key the keyring list
        // holds already, so a stale list never overwrites one.
        writer.command = ["node", keysProgram, "add-key", press.row === "" ? "new" : "replace", provider, name];
        writer.running = true;
        return "ok";
    }

    function stored() {
        const record = storing;
        if (record === null) return;
        storing = null;
        const code = writer.exitCode;
        if (code !== 0) {
            console.warn("jarvis-keys: store=" + (code === null ? "start-failed" : "exit=" + code));
            record.done({ ok: false, text: Words.saveFailure(code) });
        } else {
            if (record.target !== "") restore = null;
            serving = { provider: record.provider, name: record.name, target: record.target };
            if (record.row !== "" && Words.usedBy(record.row, settings, voice).length > 0) inUseChanged();
            record.done({ ok: true, text: "" });
        }
        reread();
    }

    // After a save for a field, the read that names the new key's account
    // id selects it there.
    function select() {
        if (serving === null || keyList === undefined) return;
        const wanted = serving;
        const key = keyList.find(item => item.provider === wanted.provider && item.name === wanted.name);
        if (key === undefined) return;
        serving = null;
        if (wanted.target !== "" && settings[wanted.target] !== key.id && shell.configure.set(wanted.target, key.id) !== "ok")
            console.warn("jarvis-keys: select=" + wanted.target + " refused");
    }

    function check(id) {
        const key = keyOf(id);
        if (key === null || checking !== "" || storing !== null || removing !== null) return "refused: action=providerKeys reason=row-changed";
        fault(id, null);
        checking = id;
        checker.exitCode = null;
        checker.command = ["node", accountsProgram, "--tree", Quickshell.shellDir + "/..", "verify", id, "user"];
        checker.running = true;
        return "ok";
    }

    // A removal clears the selections that named the key first, so no
    // field keeps a key that is gone, and none takes another key on its own.
    function remove(id) {
        const key = keyOf(id);
        if (key === null || storing !== null || removing !== null || checking !== "") return "refused: action=providerKeys reason=row-changed";
        fault(id, null);
        removing = { id: id, used: Words.usedBy(id, settings, voice).length > 0 };
        remover.exitCode = null;
        remover.command = ["node", keysProgram, "remove-key", key.provider, key.name];
        remover.running = true;
        return "ok";
    }

    function removed() {
        const record = removing;
        if (record === null) return;
        removing = null;
        if (remover.exitCode !== 0) {
            console.warn("jarvis-keys: remove=" + (remover.exitCode === null ? "start-failed" : "exit=" + remover.exitCode));
            fault(record.id, { tone: "danger", text: "Not removed: unlock your keyring" });
            return;
        }
        if (settings.brain === record.id) shell.configure.set("brain", "");
        const backups = Array.isArray(settings.fallbacks) ? settings.fallbacks : [];
        if (backups.some(backup => backup.brain === record.id))
            shell.configure.set("fallbacks", backups.map(backup => backup.brain === record.id ? Object.assign({}, backup, { brain: "" }) : backup));
        if (settings.voiceAccount === record.id) {
            accounts.voiceCleared = true;
            shell.configure.set("voiceAccount", "");
        }
        if (record.used) inUseChanged();
        reread();
    }

    function reread() {
        accounts.keysChanged();
        keys.refresh();
    }

    // The helpers' explicit environment, the account reader's: no
    // inherited credential variable reaches a helper
    // (docs/architecture/jarvis-outbound.md); the vendor folders let the
    // Check's discovery find the account it checks.
    readonly property var environment: ({
        PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"),
        XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME"), XDG_STATE_HOME: Quickshell.env("XDG_STATE_HOME"),
        XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME"), XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR"),
        DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS"),
        CLAUDE_CONFIG_DIR: Quickshell.env("CLAUDE_CONFIG_DIR"), CODEX_HOME: Quickshell.env("CODEX_HOME"),
        COPILOT_HOME: Quickshell.env("COPILOT_HOME"), PI_CODING_AGENT_DIR: Quickshell.env("PI_CODING_AGENT_DIR"),
        LANG: "C.UTF-8"
    })

    Process {
        id: writer
        // The exit code of the run that ended, null for one that never
        // started, since a failed start emits only runningChanged.
        property var exitCode: null
        clearEnvironment: true
        environment: root.environment
        // keys.js prints only its keyed result; neither stream is read.
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        // As shell/Core/SecretWriter.qml feeds secret-tool: the key goes in
        // once the process runs, then stdin closes, since keys.js reads a
        // stdin that is no terminal to its end.
        onStarted: {
            if (root.storing === null || root.storing.feed === null) return;
            const feed = root.storing.feed;
            root.storing.feed = null;
            feed();
        }
        onExited: code => { exitCode = code; }
        onRunningChanged: if (!running) root.stored()
    }

    Process {
        id: checker
        property var exitCode: null
        clearEnvironment: true
        environment: root.environment
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => { exitCode = code; }
        onRunningChanged: {
            if (running) return;
            // Exit 69 is a Check that ended with its own recorded cause
            // (backend/accounts.js verify); any other failure recorded none.
            if (exitCode !== 0 && exitCode !== 69) {
                console.warn("jarvis-keys: check=" + (exitCode === null ? "start-failed" : "exit=" + exitCode));
                root.fault(root.checking, { tone: "danger", text: "Check failed: the check did not finish" });
            }
            root.checking = "";
            root.reread();
        }
    }

    Process {
        id: remover
        property var exitCode: null
        clearEnvironment: true
        environment: root.environment
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: code => { exitCode = code; }
        onRunningChanged: if (!running) root.removed()
    }
}
