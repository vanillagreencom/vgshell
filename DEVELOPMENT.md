# VGS development

Quickshell 0.3.1, Hyprland with Lua configuration, node 18 and python3; `vgshell run` checks the floor before it starts, and `scripts/check-packaging.js` holds the recipes to it.

## Run

```sh
bin/vgshell run                              # the shell from this checkout, in a Hyprland session that runs no other VGS
scripts/qml-smoke.sh --rows bar,launcher     # the shell inside the nested sandbox, running only the named rows
scripts/sandbox-shots.sh gallery settings    # PNGs of named scenes from the sandbox, under tmp/
```

Never start a second shell against the live session, and never kill Quickshell processes by name. Anything that starts a compositor, the shell, `qmltestrunner` or a browser goes through `scripts/smoke/gpu-fence.sh`, as `scripts/qml-smoke.sh` does.

## Test

```sh
scripts/validate                             # the checks the changes since the last pass reach
scripts/validate --list                      # the same selection, printed and not run
scripts/validate --changed <commit>          # a fix round: the checks the changes since that commit reach
scripts/validate unit --full                 # one whole area; unit needs Qt and no Wayland session
scripts/validate package                     # the Arch recipes in a rootless podman container
```

Exit 77 means a check could not run and is not a pass. The `qml` area is the nested sandbox and needs `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`; `scripts/qml-smoke.sh` runs it alone. A new check is a row in `scripts/validate` with its must-fail control beside it.

## Debug

```sh
bin/vgshell log                              # the running shell's log, through qs log
scripts/qml-smoke.sh --keep --rows <row>     # keep the sandbox after the row; the shell's log is under its runtime dir
scripts/sample-shell-memory.sh               # sample the live shell's memory until interrupted, read-only
```

## Regenerate

```sh
node scripts/check-readme.js --write-plugins   # README § Plugins, after a plugin is added, removed or renamed
scripts/readme-shots.sh                        # every plugin README image, after its row is added to docs/images/plugins/shots.tsv
packaging/install-system.sh                    # into a scratch DESTDIR and PREFIX, then:
scripts/check-install-tree.sh --write DESTDIR PREFIX   # packaging/install-tree.manifest, after a shipped file is added
scripts/measure-shader.sh --calibrate scripts/shader/ceilings.json --runs 3   # the shader ceilings
```

## Containers

```sh
scripts/arch-packages.sh                     # build and install both Arch recipes
scripts/fedora-container.sh --image fedora:44   # install the Fedora package from its source RPM
scripts/test-flake.sh                        # build the flake in the nix container
scripts/readme-install.sh                    # every README install command, against what users get from main
```

Each needs podman and the network, and exits 77 when it cannot run. Run `scripts/readme-install.sh` by hand before a release.

## Write a plugin

Read `docs/architecture/overview.md`, then load the `vgs-plugin` skill, which scaffolds a plugin from its templates and checks it. A plugin lands with its row under `scripts/smoke/rows/` in the same change.

## Release

`docs/RELEASING.md`: `scripts/release`, `scripts/publish-aur.sh` and the Fedora rebuild, each from the maintainer's own machine. Both scripts take `--dry-run`.

## Licence

VGS is under the MIT licence, `LICENSE`. The bundled fonts, Inter and JetBrains Mono, are under the SIL Open Font License 1.1 (`shell/assets/fonts/*-OFL.txt`), the Lucide icons under ISC (`shell/Ui/icons/LICENSE`), and the browser discovery stub under Apache-2.0 (`shell/plugins/vgs.jarvis/backend/skills/browser/LICENSE`). The package recipes hold the package licence expression.
