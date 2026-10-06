import QtQuick

// The catalog wallpapers the theme capability fetched for the theme view's
// cards that had none on disk, one at a time, kept by theme name. The browser owns
// them, not the view: the capability hands its answer to a waiter that
// lives as long as the plugin instance, the browser, while a view switch
// destroys the theme view with a preview still running. The answer lands
// here, and the theme view built next draws it.
Item {
    id: root

    property var shell: null
    // Each finished preview's image path, by theme name.
    property var cache: ({})
    // The name the shown theme view wants a preview of, "" for none or no
    // theme view, and the name whose preview runs, "" for none.
    property string wanted: ""
    property string running: ""

    // Want NAME's preview, "" for none. Answers whether it still has to
    // start: false for none, a kept preview and the one running.
    function want(name) {
        wanted = name;
        return name !== "" && cache[name] === undefined && running !== name;
    }

    // Start the wanted preview, unless one runs or it is kept. A preview
    // that finishes starts the one wanted since, so the last card the view
    // settles on gets its preview.
    function start() {
        const name = wanted;
        if (name === "" || running !== "" || cache[name] !== undefined) return;
        running = name;
        const reply = shell.theme.preview(name, result => {
            root.running = "";
            if (result.state === "ok") {
                const next = Object.assign({}, root.cache);
                next[name] = result.path;
                root.cache = next;
            }
            if (root.wanted !== name) root.start();
        });
        if (reply !== "ok") running = "";
    }
}
