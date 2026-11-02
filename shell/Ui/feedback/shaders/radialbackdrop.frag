#version 440

// RadialBackdrop: one dark field over up to four rounded boxes, in one pass
// with no loop and no texture, premultiplied.
//
// Each box hands in its own peak opacity, ink, fade and inset. Its distance
// is scaled by its own fade, x = (d + inset) / fade: 0 where its plateau
// ends, 1 where the eased falloff reaches zero. The boxes join by a smooth
// minimum of x (log-sum-exp, width uJoin.x), so the field has no crease
// where two meet, and peak and ink blend by soft weights over the same x
// (width uJoin.y), so the darkness changes gradually from one box to the
// next. The falloff turns that shape into alpha: eased, 1 - smootherstep,
// zero at a finite distance with its first and second derivatives 0 at both
// ends; or Gaussian, exp(-x^2) past the plateau. uJoin.w above 0.5 adds a
// halo past a ring round box 0's centre in a four-stop palette over its
// height.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;      // item size, px
    vec4 uBox0;      // centre x, y and half extents, px; a half extent <= 0 drops the box
    vec4 uBox1;
    vec4 uBox2;
    vec4 uBox3;
    vec4 uCorner;    // corner radius per box, px
    vec4 uPeak;      // peak opacity per box
    vec4 uFade;      // falloff width per box, px
    vec4 uInset;     // where the falloff starts, px inside each box
    vec4 uJoin;      // smooth-union width, blend width (units of x), Gaussian (> 0.5), halo (> 0.5)
    vec4 uInk0;      // ink per box
    vec4 uInk1;
    vec4 uInk2;
    vec4 uInk3;
    vec4 uHalo;      // strength, width px, ring radius px, 0
    vec4 uHaloTop;   // the halo's palette, top to bottom
    vec4 uHaloUpper;
    vec4 uHaloLower;
    vec4 uHaloBottom;
};

float box(vec2 p, vec4 b, float r) {
    vec2 q = abs(p - b.xy) - max(b.zw - r, 0.0);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float spread(vec2 p, vec4 b, float r, float fade, float inset) {
    if (b.z <= 0.0 || b.w <= 0.0) return 1.0e4;
    return (box(p, b, r) + inset) / max(fade, 1e-3);
}

vec3 ramp(float h) {
    if (h > 0.35) return mix(uHaloUpper.rgb, uHaloTop.rgb, clamp((h - 0.35) / 0.65, 0.0, 1.0));
    if (h > -0.25) return mix(uHaloLower.rgb, uHaloUpper.rgb, clamp((h + 0.25) / 0.60, 0.0, 1.0));
    return mix(uHaloBottom.rgb, uHaloLower.rgb, clamp((h + 0.80) / 0.55, 0.0, 1.0));
}

void main() {
    vec2 p = qt_TexCoord0 * uSize;
    vec4 x = vec4(spread(p, uBox0, uCorner.x, uFade.x, uInset.x),
                  spread(p, uBox1, uCorner.y, uFade.y, uInset.y),
                  spread(p, uBox2, uCorner.z, uFade.z, uInset.z),
                  spread(p, uBox3, uCorner.w, uFade.w, uInset.w));
    float m = min(min(x.x, x.y), min(x.z, x.w));
    // Measured from the nearest box, so no exponential underflows to log(0).
    vec4 u = exp(-(x - m) / max(uJoin.x, 1e-3));
    float s = m - uJoin.x * log(u.x + u.y + u.z + u.w);
    vec4 w = exp(-(x - m) / max(uJoin.y, 1e-3));
    w /= (w.x + w.y + w.z + w.w);
    float peak = dot(w, uPeak);
    vec3 ink = w.x * uInk0.rgb + w.y * uInk1.rgb + w.z * uInk2.rgb + w.w * uInk3.rgb;
    float t = clamp(s, 0.0, 1.0);
    float eased = 1.0 - t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
    float g = max(s, 0.0);
    float a = peak * (uJoin.z > 0.5 ? exp(-g * g) : eased);
    vec3 rgb = ink * a;
    if (uJoin.w > 0.5) {
        vec2 o = p - uBox0.xy;
        float ring = length(o) - uHalo.z;
        float h = uHalo.x * exp(-pow(max(0.0, ring) / max(uHalo.y, 1e-3), 2.0)) * smoothstep(-0.25 * uHalo.z, 0.0, ring);
        rgb += ramp(clamp(-o.y / max(uHalo.z, 1.0), -1.0, 1.0)) * h;
    }
    fragColor = vec4(rgb, a) * qt_Opacity;
}
