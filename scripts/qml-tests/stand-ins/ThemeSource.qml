import QtQuick
import qs.Unit
import "Tokens.js" as Tokens
import "ThemeLogic.js" as ThemeLogic

// The unit tests' theme source: the same members as the shipped
// ThemeSource, with a document handed over by UnitTheme in place of the
// file. It calls the shipped accept and publication, so a test proves the
// shipped judge and publication and never a copy.
QtObject {
    id: source

    readonly property var defaults: ThemeLogic.defaults(Tokens.TOKENS)
    property string userText: ""
    property var accepted: defaults
    property string name: defaults.name
    property var values: defaults.values
    property var appearance: ThemeLogic.published(Tokens.TOKENS, defaults, "").appearance
    property int revision: 0
    property int documentRevision: 0
    property string state: "unit"

    onUserTextChanged: publish(accepted)

    function publish(next) {
        const result = ThemeLogic.published(Tokens.TOKENS, next, userText);
        for (const line of result.logs) console.error(line);
        const document = next !== accepted;
        accepted = next;
        name = next.name;
        values = result.values;
        appearance = result.appearance;
        revision += 1;
        if (document) documentRevision += 1;
    }

    // Accept one document; answers "ok" or the refusal line, which is also
    // what a refused document leaves published.
    function load(text) {
        const judged = ThemeLogic.accept(Tokens.TOKENS, text);
        if (!judged.ok) return ThemeLogic.refusalLine(judged);
        publish(judged);
        return "ok";
    }

    function reset() {
        publish(defaults);
    }

    Component.onCompleted: UnitTheme.attach(source)
}
