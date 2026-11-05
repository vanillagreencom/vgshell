# shell/Ui/

The shared component library, module `qs.Ui`.

## Rules

- A file in a subdirectory imports `qs.Ui` to compose another component.
- A new component lands with a test under `scripts/qml-tests/` and one mutation per guarantee in `scripts/test-qml-unit.sh`.
- Edit `scripts/vendor-lucide`, never its generated `icons/Lucide.js`.

## Read when

- Before changing a component, its tokens, input, focus or overlay anchoring: [design-system.md](../../docs/architecture/design-system.md), including Components, Pointer and Keyboard.
- Before changing a component's test or its Quickshell stand-ins: [validation.md § Test isolation](../../docs/architecture/validation.md#test-isolation) and the header of `scripts/qml-unit.sh`.
