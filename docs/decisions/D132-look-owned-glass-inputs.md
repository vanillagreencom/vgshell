# D132: A plugin-owned look supplies the shared glass inputs

[← Decision Index](INDEX.md)

**Date**: 2026-11-12

**Status**: Active

**Research**: [VGS-2433, owner-approved glass design](https://linear.app/vanillagreen/issue/VGS-2433#comment-4fac1c00-6264-4cd7-a2a4-627099428840)

**Supersedes**: [D023](D023-plugin-owned-appearance.md) for the glass inputs and the glass-off surface alone. Its five theme inputs and shared key-hint exception remain active; [D119](D119-plugin-look-binds-per-surface.md) still defines the look's per-surface scope, and [D104](D104-appearance-values-over-the-theme.md) still resolves Appearance values once.

**Decision**: `GlassSurface` remains the one shared glass component. A surface with a plugin-owned look may hand it the look's `fill`, rounding, elevation and `lens` values, and its own glass-off `standard` background, border and radius. The component owns the lens drawing and uses its theme defaults for inputs the surface does not supply. Glass off draws `standard` without a lens pass. These component inputs add no theme input to the look.

**Why**: The owner's approved Jarvis design uses one lens material and a contrast-safe ground in each mode. Shared drawing with look-owned values preserves that design when glass is off and lets later surfaces adopt the same material without a private shader or a second theme resolver.

**Rejected**: Limiting the look to fill, rounding and elevation and forcing the theme's standard surface with glass off. That changes the approved ground and its ink contrast. Private glass components would duplicate the material and its fixes.

**Revisit when**: A look needs a different glass drawing mechanism, a component input reaches an unapproved theme value, or all flat surfaces adopt the lens form and its shared defaults change.
