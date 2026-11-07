import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/Commons/Tokens.js" as Tokens
import "../../shell/Commons/ThemeLogic.js" as Logic

// Shared hint reuse preserves the executing solver's exact answer. The
// getter counts real solver reads, not elapsed time: equivalent delegates
// must not solve again, and eviction must release older grounds.
Item {
    width: 400
    height: 100

    KeyHints {
        id: hint
        hints: [{ key: "Ctrl+K", text: "Open" }]
        backgroundContext: ({ fill: Theme.color.surfaceRaised })
    }

    TestCase {
        name: "hintInk"
        when: windowShown

        function init() {
            Theme.appearanceInput = "";
            UnitTheme.reset();
            compare(UnitTheme.override({}), "ok");
        }
        function cleanup() { Theme.appearanceInput = ""; UnitTheme.reset(); }

        function context(fill, plate, sheen) {
            return { fill: Qt.color(fill), plate: Qt.color(plate || "transparent"), sheen: Qt.color(sheen || "transparent") };
        }

        function test_reuse_keeps_exact_solver_answers_data() {
            return [
                { tag: "default", ground: null },
                { tag: "solid", ground: context("#17191c") },
                { tag: "glass", ground: context("#b017191c") },
                { tag: "selected", ground: context("#17191c", "#24ffffff", "#08ffffff") },
                { tag: "light", ground: context("#faf8f3", "#18000000", "#08ffffff") },
                { tag: "unreachable-margin", ground: context("#777777") }
            ];
        }

        function test_reuse_keeps_exact_solver_answers(row) {
            for (const overrides of [{}, { "scheme.mode": "light", "palette.background": "#faf8f3" }]) {
                const accepted = Logic.resolve(Tokens.TOKENS, overrides);
                verify(accepted.ok);
                const resolve = Logic.keyHintResolver(accepted.values);
                for (const part of Object.keys(Logic.KEY_HINT_PARTS)) {
                    const expected = Logic.keyHintInk(accepted.values, row.ground, part);
                    compare(resolve(row.ground, part), expected);
                    // A newly constructed delegate supplies another object.
                    const copy = row.ground === null ? null : context(row.ground.fill, row.ground.plate, row.ground.sheen);
                    compare(resolve(copy, part), expected);
                }
            }
        }

        function test_equivalent_delegates_do_not_solve_again_and_history_is_bounded() {
            const values = Logic.defaults(Tokens.TOKENS).values;
            const kbd = values.kbd;
            const reads = { count: 0 };
            Object.defineProperty(values, "kbd", { get: function () { reads.count++; return kbd; } });
            const resolve = Logic.keyHintResolver(values);
            const first = context("#17191c", "#24ffffff", "#08ffffff");
            const expected = resolve(first, "key");
            const afterFirst = reads.count;
            verify(afterFirst > 0, "the shipped solver read its inputs");
            for (let i = 0; i < 50; i++)
                compare(resolve(context(first.fill, first.plate, first.sheen), "key"), expected);
            compare(reads.count, afterFirst, "equivalent delegate grounds do not enter the solver");
            for (let i = 0; i < Logic.KEY_HINT_CACHE_LIMIT; i++)
                resolve({ fill: Qt.rgba(i / Logic.KEY_HINT_CACHE_LIMIT, 0, 0, 1), plate: Qt.color("transparent"), sheen: Qt.color("transparent") }, "key");
            const afterChurn = reads.count;
            compare(resolve(first, "key"), expected);
            verify(reads.count > afterChurn, "the evicted ground is no longer retained");
        }

        // All channels, including alpha below a byte, participate. Mutable
        // records occur when a caller rebuilds a supplied context in place.
        function test_every_context_component_and_part_is_an_input() {
            const values = Logic.defaults(Tokens.TOKENS).values;
            const kbd = values.kbd;
            const reads = { count: 0 };
            Object.defineProperty(values, "kbd", { get: function () { reads.count++; return kbd; } });
            const resolve = Logic.keyHintResolver(values);
            for (const field of ["fill", "plate", "sheen"]) {
                for (const channel of ["r", "g", "b", "a"]) {
                    const ground = {
                        fill: { r: 0.1, g: 0.1, b: 0.1, a: 0.9 },
                        plate: { r: 0.2, g: 0.2, b: 0.2, a: 0.1 },
                        sheen: { r: 0.3, g: 0.3, b: 0.3, a: 0.1 }
                    };
                    resolve(ground, "key");
                    ground[field][channel] += 0.00001;
                    const before = reads.count;
                    const actual = resolve(ground, "key");
                    verify(reads.count > before, field + "." + channel + " is not rounded out of the key");
                    compare(actual, Logic.keyHintInk(values, ground, "key"));
                }
            }
            const ground = context("#17191c");
            for (const part of ["word", "key", "value"])
                compare(resolve(ground, part), Logic.keyHintInk(values, ground, part));
        }

        function test_publication_replaces_cached_inks_and_updates_drawn_hints() {
            const ground = context("#17191c");
            const before = Theme.keyHintInk(ground, "word");
            // Same document name, different inputs: name is no cache key.
            compare(UnitTheme.override({ text: { keyHint: { color: "#ffffff" } }, kbd: { foreground: "#ffffff", valueForeground: "#ffffff" } }), "ok");
            compare(Theme.keyHintInk(ground, "word"), "#ffffffff");
            verify(before !== Theme.keyHintInk(ground, "word"));
            const resolver = Theme.keyHintResolver;
            Theme.appearanceInput = JSON.stringify({ glass: "on", interfaceFont: "Inter Variable" });
            verify(Theme.keyHintResolver !== resolver, "Appearance publication replaces the resolver too");
            compare(hint.wordInk, Qt.color(Theme.keyHintInk(hint.ground, "word")));
            UnitTheme.reset();
            compare(Theme.keyHintInk(ground, "word"), before, "returning to the previous theme restores its ink");
        }

        function test_each_solver_token_reaches_the_shared_owner_data() {
            return [
                { tag: "word-ink", tokens: { text: { keyHint: { color: "#ffffff" } } } },
                { tag: "key-ink", tokens: { kbd: { foreground: "#ffffff" } } },
                { tag: "value-ink", tokens: { kbd: { valueForeground: "#ffffff" } } },
                { tag: "cap-fill", tokens: { kbd: { background: "#ffffff80" } } },
                { tag: "word-margin", tokens: { kbd: { wordMargin: 9 } } },
                { tag: "key-margin", tokens: { kbd: { capMargin: 9 } } },
                { tag: "value-margin", tokens: { kbd: { valueMargin: 9 } } }
            ];
        }

        function test_each_solver_token_reaches_the_shared_owner(row) {
            const ground = context("#202429", "#24ffffff", "#08ffffff");
            for (const part of Object.keys(Logic.KEY_HINT_PARTS))
                Theme.keyHintInk(ground, part);
            const previous = Theme.keyHintResolver;
            compare(UnitTheme.override(row.tokens), "ok");
            verify(Theme.keyHintResolver !== previous);
            const accepted = Logic.accept(Tokens.TOKENS, JSON.stringify({ schemaVersion: 1, name: "unit", tokens: row.tokens }));
            verify(accepted.ok);
            for (const part of Object.keys(Logic.KEY_HINT_PARTS)) {
                for (const supplied of [null, ground]) {
                    const expected = Theme.toColor(Logic.formatColor(Logic.keyHintInk(accepted.values, supplied, part)));
                    compare(Theme.keyHintInk(supplied, part), expected);
                }
            }
        }
    }
}
