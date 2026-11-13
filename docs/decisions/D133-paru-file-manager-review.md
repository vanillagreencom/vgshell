# D133: The AUR review runs as paru's file-manager review

[← Decision Index](INDEX.md)

**Date**: 2026-11-13

**Status**: Active

**Research**: [VGS-2482](https://linear.app/vanillagreen/issue/VGS-2482/package-review-the-aur-review-runs-inside-parus-own-review-step), [VGS-2472 approved design](https://linear.app/vanillagreen/issue/VGS-2472), [approval through Jarvis under the owner's delegated authority](https://linear.app/vanillagreen/issue/VGS-2482#comment-d72a05e4-4179-44d9-89ba-da9dc65a50c6)

**Decision**: Paru installs and updates use its file-manager review step for the agent review. The agent reads a private copy of the tracked recipe files and paru's diff. Paru builds the clones it supplied to that step. VGS keeps no receipt or later binding check. Yay keeps its own review menus.

**Why**: A review before paru fetched its recipes could approve different files from those it built. Later comparisons stopped updates when mirrors or AUR metadata changed, yet version comparisons missed recipe changes without a version increase. Paru owns the reviewed clones and the build order. The private copy keeps agent writes away from those clones and from the run's verdict store. A named skip repeats paru's two review questions once so a changed recipe still receives review.

**Rejected**: Gathering a separate recipe copy and admitting later package steps with a receipt. That adds a second content judge without proving that paru builds the reviewed commit.

**Revisit when**: Paru changes its file-manager contract so it no longer builds the reviewed clones, or another supported helper provides an equivalent review step.
