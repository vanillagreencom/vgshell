# D123: Standard Arch VCS source and recipe versions

[← Decision Index](INDEX.md)

**Date**: 2026-11-05

**Status**: Active

**Research**: [VGS-2319](https://linear.app/vanillagreen/issue/VGS-2319), [Arch VCS guidelines](https://manual.archlinux.page/package-guidelines/vcs/)

**Decision**: Reverse [VGS-759](https://linear.app/vanillagreen/issue/VGS-759)'s `prepare()` clone. Let makepkg fetch main through a standard `git+` source. Publish actual recipe changes with the current `pkgver()` output, or a higher pkgrel when that output has not changed; never publish for a pkgver bump alone.

**Why**: AUR helpers need the VCS source to track main and a higher stored version to fetch changed dependencies. VGS-2319's owner evidence no longer supports the mirror-size reason for the custom clone. Standard makepkg fetching accepts its mirror cost without hiding the source from helpers.

**Rejected**: Keep the filtered single-branch clone in `prepare()`. Its smaller fetch does not expose a VCS source to AUR helpers, so their development tracking misses VGS.

**Revisit when**: Arch changes its VCS-source contract or a measured repository size makes standard fetching impractical.
