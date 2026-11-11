# Dependency inventory

The dep-radar sweep reads this file: one row per pinned surface, as [sweep.md § Phase 0](../../.agents/skills/dep-radar/workflows/sweep.md#phase-0-inventory-self-maintaining) sets out. Rule keys in the owner rules are the dep-radar [operating policy](../../.agents/skills/dep-radar/SKILL.md#operating-policy-the-contract-with-the-product-owner)'s.

This inventory holds the kendex release pin alone. A later sweep adds the repository's other pinned surfaces under Phase 0's every-run rule, each with its upstream check.

## Surfaces

| Surface | Pin location | Upstream check | Refresh | Verify | Tier and playbook | Owner rules |
|---|---|---|---|---|---|---|
| kendex release for Debian and Fedora | `shell/Core/PackageManagers.js`, rows `deb-file` and `rpm-file`, the `kendex` entry of `files.releases` | `node scripts/kendex-pin.js`: exit 0 current, 1 behind, 2 ahead or refused, which needs the owner, and 77 unreadable, which is never a pass. The `scripts/kendex-pin.js` header owns these exits. | [§ kendex release pin](#kendex-release-pin) | The package-identity read of [§ kendex release pin](#kendex-release-pin) step 4, then `scripts/validate`, by its own selection ([D100](../decisions/D100-validation-selects-by-inputs.md)) | auto-with-fixes; Pinned runtime binary with SHA constants | `one-pr-per-surface`: one PR per surface. When the upstream check reports behind, the newest stable release it names becomes one pin-move item that moves both rows straight to it. Both rows stay on one version. The pinned SHA-256 stays the only trust point. |

## Refresh procedures

### kendex release pin

Run this when the upstream check reports behind, for the newest stable release `<V>` it prints as `newest=<V>`. The move goes straight to `<V>` and skips any release between the pin and `<V>`.

1. Download the release's four package files: the amd64 and arm64 deb and the x86_64 and aarch64 rpm, under the names the release publishes.
2. Take each file's SHA-256 from the downloaded file with `sha256sum`.
3. Check each SHA-256 equals the hex after the `sha256:` prefix of that asset's published `digest` in the release, `https://api.github.com/repos/vanillagreencom/kendex/releases/tags/v<V>`. A mismatch stops the move and becomes a report item.
4. Read each file's package identity with the reads `bin/lib/pkg-file.js` makes before it installs. For each deb, `dpkg-deb --field <file> Package Version Architecture` prints `Package: kendex`, `Version: <V>` and `Architecture: <arch>`. For each rpm, `rpm -qp --queryformat '%{NAME} %{VERSION} %{ARCH}\n' -- <file>` prints `kendex <V> <arch>`. `<arch>` is the asset's key in the row: `amd64` and `arm64` for the debs, `x86_64` and `aarch64` for the rpms. A host without `dpkg-deb` or `rpm` runs the read in a Debian or Fedora container with no network. A mismatch, or a read that cannot run, stops the move and becomes a report item.
5. In `shell/Core/PackageManagers.js`, update the `deb-file` and `rpm-file` rows together: the version, the url, each asset's file and SHA-256, and the digest-date comment above the rows.
6. In `scripts/test-vgshell-pkg-table.js`, move the version literals that equal the pin to `<V>` in the same change. Keep each literal that stands for a newer or an older installed version above or below `<V>`, and raise a newer literal past `<V>` when the move reaches it.
7. Run `node scripts/kendex-pin.js`, which then prints `status=current`, and the verify command.
