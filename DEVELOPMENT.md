# Development

[AGENTS.md](AGENTS.md) lists the commands, conventions and the architecture docs to read before each kind of work.

## Writing a plugin

Read [docs/architecture/plugins.md](docs/architecture/plugins.md). An agent loads the `vgs-plugin` skill, which scaffolds a plugin from templates and checks it.

## Validation

`scripts/validate` runs the checks a change affects. The `qml` area runs the whole shell inside a nested Hyprland, the validation sandbox, and never touches your session: [docs/architecture/validation.md](docs/architecture/validation.md) and [docs/architecture/validation-smoke.md](docs/architecture/validation-smoke.md).

## README

The README's plugin table is generated from each shipped plugin's `name` and `description` in `manifest.json`. After a plugin is added, removed or renamed, or its description changes, run `node scripts/check-readme.js --write-plugins`. `node scripts/check-readme.js` fails while the table differs: [docs/architecture/install-guide.md](docs/architecture/install-guide.md).

## Licence

VGS is under the MIT licence: [LICENSE](LICENSE). The bundled fonts, JetBrains Mono and Inter, are under the SIL Open Font License 1.1 (`shell/assets/fonts/*-OFL.txt`), and the Lucide icons under ISC ([shell/Ui/icons/LICENSE](shell/Ui/icons/LICENSE)). The browser discovery stub is under Apache-2.0 ([licence](shell/plugins/vgs.jarvis/backend/skills/browser/LICENSE)). The package recipes hold the package licence expression.
