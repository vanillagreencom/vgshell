# D093: Jarvis screenshots are taken on a user turn, with private windows painted out

[← Decision Index](INDEX.md)

**Date**: 2026-10-02
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D070](D070-jarvis-action-policy.md), [D082](D082-jarvis-approval-bound-to-the-action.md)

**Decision**: One executor captures the screen only during the live thinking turn the user started, reads Hyprland before and after `grim`, paints every window matching `privateWindows` black before the image leaves the executor, and refuses when the readings disagree or the session locked. It registers only when both `grim` and `magick` exist.

**Why**: A screenshot can hold a password manager and the image leaves the machine, so painting must happen before any consumer, audit included, holds the pixels. `grim` composes outputs upright, so a transform-rotated mask would cover the wrong pixels, and `hyprctl` reports animation goals, so two readings prove the masks against the goals. `scripts/test-jarvis-vision.js` holds the masks.

**Rejected**: Falling back to ImageMagick 6's `convert`. A second command spelling; a distribution without `magick` gets no screen tools instead.

**Revisit when**: `grim` hands over output buffers, Hyprland reports drawn rectangles, animation state or a window's capture exclusion, or a brain needs resized images.
