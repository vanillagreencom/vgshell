# shell/Commons/

Shared QML singletons and JavaScript helpers, module `qs.Commons`.

## Rules

- Keep helpers shared with Node as `.pragma library` files without Qt objects. Their Node readers use `bin/lib/qml-library.js`; review holds the cross-runtime boundary.
- Use the shared helpers for session-lock state, desktop launches, account discovery, replies and timestamp wording. Keep one interpretation for their QML and Node callers.
- Keep `ThemeSource.qml` internal. `Config` alone binds `Theme.appearanceInput`; `scripts/check-plugin-boundary.py` refuses plugin access to that input.

## Read when

- Before changing tokens, the theme judge or `Theme`: [design-system.md § Tokens](../../docs/architecture/design-system.md#tokens).
- Before changing theme-file reads or Appearance input: [configuration.md § Theme file](../../docs/architecture/configuration.md#theme-file).
- Before changing a shared watcher, popup tracker or other resource owner: [runtime.md](../../docs/architecture/runtime.md).
