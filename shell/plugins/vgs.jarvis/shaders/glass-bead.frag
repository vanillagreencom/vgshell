#version 440
#extension GL_GOOGLE_include_directive : require
#include "orb.glsl"

// Glass bead, the default orb style: the particle orb's points inside a
// dark, soft-edged glass disc that moves with the orb, so the points always
// have a dark ground behind them. A thin glass rim and a glow carry the
// disc on a dark wallpaper and a soft shadow seats it on a light one.
//
// The points are four concentric shells of dots. Shell 0 is the lattice the
// interior shows; shells 1-3 draw only near the silhouette, where their
// noise-displaced outlines stack into the warped bright band and the spray
// beyond it. Each shell is hit twice (front and back of the sphere), each
// rim hit is moved once by a two-octave value-noise radius, mapped to a
// cube-sphere lattice cell, and tested against the 2x2 nearest cells' dots.
// Work per pixel is constant and bounded: 4 shells x 2 faces x (2 noise
// octaves + 3 lattice-warp noises + 4 dot tests), plus one fold noise on
// shell 0's front; a rim shell stops after its 2 octaves where it is not
// near its silhouette. The disc adds one noise read. Past the spray's reach
// only the disc's glow and shadow draw, and past those the pixel returns at
// once. The reduced look (uReduce above 0.5) skips the inner rim shell and
// the rim shells' back faces: 2 rim hits a pixel instead of 6. Every loop
// bound stays a constant either way.

// The radius field: a low octave every shell shares, so the band's lobes
// stay one band, and a rough octave each shell takes at its own phase.
float field(vec3 o, float k, float rough) {
    vec3 q = o * uField.x + vec3(0.0, uFlow, 0.0);
    float n = (1.0 - rough) * vnoise(q)
            + rough * vnoise(q * 2.3 + vec3(3.1 + k * 4.3, -uFlow * 0.7, 1.7 + k * 2.9));
    return n - 0.5;
}

// The interior's deeper palette: each stop pulled toward its own square,
// which keeps its hue and raises its chroma.
vec3 deep(vec3 c) { return mix(c, c * c, 0.6) * 0.8; }

void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    uv.y = -uv.y;
    float px = fwidth(uv.x);
    float r = length(uv);
    float R = uShape.x;
    if (r > R * 1.55) { fragColor = vec4(0.0); return; }
    float b = clamp(uExtra.x, 0.0, 1.5);

    // The disc: deep ink tinted by the palette, its edge wavering with the
    // field and swelling with the level. The shift along y of 0.8 flow
    // units a unit is eight lattice periods a flow turn, so the field
    // closes as the flow clock wraps.
    // The unit direction from the centre, the cosine and sine of the angle
    // of uv. The centre has no angle and takes the direction of angle 0;
    // any finite direction draws the same pixel there, since the edge Re
    // it moves reaches no term at r = 0, and the rim light it sets is
    // scaled by a rim band that is 0 near the centre.
    vec2 dir = r > 0.0 ? uv / r : vec2(1.0, 0.0);
    vec3 rimDir = vec3(dir, 0.3);
    float wob = (vnoise(rimDir * 1.7 + vec3(0.0, uFlow * 0.8, 0.0)) - 0.5) * (0.05 + 0.08 * uLevel) * R;
    float Re = R * (1.07 + 0.04 * uLevel) + wob;
    vec3 tint = palette(uv.y / R * 0.95 + uv.x / R * 0.1);
    float body = 1.0 - smoothstep(Re - 0.16 * R, Re + 0.10 * R, r);
    float discA = body;
    vec3 disc = ink(clamp(1.0 - r / Re, 0.0, 1.0), tint) * discA;
    // A thin glass rim, brighter toward the upper left.
    float rimBand = core(r - Re * 0.955, 0.02 * R);
    float rimLight = 0.35 + 0.65 * clamp(dot(dir, normalize(vec2(-0.55, 0.85))), 0.0, 1.0);
    disc += tint * rimBand * rimLight * 0.45 * b;
    disc += tint * glow(r, Re, 0.92, 0.8, 0.11) * 0.30 * b;
    discA += (1.0 - discA) * shadow(uv, Re);
    if (r > R * 1.3) { fragColor = vec4(disc, discA) * qt_Opacity; return; }

    mat3 M = orbMatrix();
    mat3 MT = transpose(M);

    vec3 top = uTop.rgb, upper = uUpper.rgb, lower = uLower.rgb, bottom = uBottom.rgb;
    vec3 col = vec3(0.0);
    float alpha = 0.0;
    float rr = max(r, 1e-6);

    for (int k = 0; k < 4; k++) {
        float fk = float(k);
        // The reduced look drops the inner rim strand; the bound stays 4.
        if (k == 1 && uReduce > 0.5) continue;
        // radius, displacement, presence, dot size, lattice scale, jitter,
        // hue offset, rough octave, outward scatter
        float rs   = k == 0 ? 1.000 : k == 1 ? 1.025 : k == 2 ? 1.055 : 1.095;
        float amps = k == 0 ? 1.00  : k == 1 ? 1.20  : k == 2 ? 1.60  : 2.20;
        float pres = k == 0 ? 1.00  : k == 1 ? 0.65  : k == 2 ? 0.50  : 0.35;
        float dsc  = k == 0 ? 1.00  : k == 1 ? 0.90  : k == 2 ? 0.85  : 0.75;
        float lat  = k == 0 ? 1.00  : k == 1 ? 1.17  : k == 2 ? 1.31  : 0.93;
        float jit  = k == 0 ? 0.06  : k == 1 ? 0.40  : k == 2 ? 0.45  : 0.50;
        float hue  = k == 0 ? 0.00  : k == 1 ? 0.55  : k == 2 ? -0.25 : 0.15;
        float rough= k == 0 ? 0.30  : k == 1 ? 0.45  : k == 2 ? 0.55  : 0.65;
        float out_ = k == 0 ? 0.00  : k == 1 ? 0.00  : k == 2 ? 0.02  : 0.05;
        float Rk = R * rs;
        // The centre is a round sphere of moving dots. Only the outer
        // strands displace their radius.
        float amp = k == 0 ? 0.0 : min(uShape.w * amps * (k == 3 ? uField.z : 1.0), 0.45);
        float N = uShape.y * lat;

        for (int fi = 0; fi < 2; fi++) {
            float face = fi == 0 ? 1.0 : -1.0;
            // The reduced look draws the rim shells' front faces only.
            if (k > 0 && fi == 1 && uReduce > 0.5) continue;
            // The radius field is read on the shell, with its depth held
            // at 0.3 or more: near the limb depth changes fastest along the
            // screen, and an unbounded change would drag a dot's centre
            // with the pixel into a streak.
            float s0 = min(r / Rk, 1.0);
            vec3 g = normalize(vec3(uv / rr * s0, face * max(sqrt(1.0 - s0 * s0), 0.3)));
            float n = field(M * g, fk, rough);
            float Rp = Rk * (1.0 + amp * n * 2.0);
            vec3 P = r < Rp ? vec3(uv, face * sqrt(Rp * Rp - r * r)) : vec3(uv / rr * Rp, 0.0);
            float nz = abs(P.z) / Rp;
            float graze = 1.0 - nz;
            float wface = k > 0 ? pow(clamp((r / Rp - 0.84) / 0.15, 0.0, 1.0), 2.0)
                        : fi == 0 ? 1.0 : 0.35 * graze * graze * graze;
            if (k == 0) wface *= 1.0 - smoothstep(Rk - px, Rk + px, r);
            if (wface <= 0.0) continue;

            vec3 opix = M * (P / Rp);
            vec3 wq = opix * (uField.x * 0.92) + vec3(0.0, uFlow * 0.5 + fk * 2.3, 0.0);
            // The warp eases toward the limb, where depth changes fastest
            // along the screen and a full warp would streak.
            vec3 o = normalize(opix + (vec3(vnoise(wq), vnoise(wq + 5.2), vnoise(wq + 9.7)) - 0.5) * uField.y * (0.4 + 0.6 * nz));

            float fold = 1.0;
            if (k == 0 && fi == 0) {
                float e = abs(vnoise(o * 2.1 + vec3(uFlow * 0.6, 1.3, -uFlow * 0.4)) - 0.5);
                fold = clamp((e - 0.025) / 0.03, 0.0, 1.0)
                     * (1.0 + 1.2 * clamp(1.0 - abs(e - 0.06) / 0.03, 0.0, 1.0));
                fold = mix(1.0, 0.35 + 0.65 * fold, uExtra.z);
            }

            // Cube-sphere cell: the major axis picks the face, and an
            // equal-angle warp evens the cells over it.
            vec3 a = abs(o);
            int axis = a.x >= a.y && a.x >= a.z ? 0 : a.y >= a.z ? 1 : 2;
            float major = axis == 0 ? a.x : axis == 1 ? a.y : a.z;
            float sgn = (axis == 0 ? o.x : axis == 1 ? o.y : o.z) < 0.0 ? -1.0 : 1.0;
            vec2 fuv = axis == 0 ? o.yz : axis == 1 ? o.zx : o.xy;
            vec2 t = atan(fuv / major) * (4.0 / PI);
            vec2 gg = (t * 0.5 + 0.5) * N;
            vec2 cell = floor(gg);
            vec2 stp = sign(gg - cell - 0.5 + 1e-6);
            float fid = float(axis * 2) + (sgn < 0.0 ? 1.0 : 0.0);

            for (int q = 0; q < 4; q++) {
                // GLSL 1.20, the pack's OpenGL 2.1 target, has no integer
                // bit or remainder operators.
                float fq = float(q);
                vec2 c = cell + vec2(mod(fq, 2.0), floor(fq * 0.5)) * stp;
                if (c.x < 0.0 || c.y < 0.0 || c.x >= N || c.y >= N) continue;
                vec3 seed = vec3(c, fid * 7.0 + fk * 31.0);
                float h1 = hash13(seed);
                if (h1 >= pres * uTone.w) continue;
                float h2 = hash13(seed + 17.3);
                float h3 = hash13(seed + 41.7);
                float h4 = hash13(seed + 73.1);
                float h5 = hash13(seed + 91.9);
                vec2 tc = ((c + 0.5 + (vec2(h2, h3) - 0.5) * jit) / N) * 2.0 - 1.0;
                vec2 fu = tan(tc * (PI / 4.0));
                vec3 oc = axis == 0 ? vec3(sgn, fu.x, fu.y) : axis == 1 ? vec3(fu.y, sgn, fu.x) : vec3(fu.x, fu.y, sgn);
                oc = normalize(oc);
                // Measure in the warped lattice: the dot keeps its offset
                // from this pixel's warped point.
                vec3 dc = MT * (opix + (oc - o));
                vec2 pc = dc.xy * Rp * (1.0 + out_ * uField.z * h5 * h5);
                float dist = length(uv - pc);
                float size = uShape.z * dsc * (0.7 + 0.6 * h4);
                float cov = clamp((size - dist) / px + 0.5, 0.0, 1.0);
                if (cov <= 0.0) continue;

                vec2 hp = pc / R;
                float hh = hp.y * 0.92 + hp.x * 0.12 + hue;
                vec3 base = ramp(hh, top, upper, lower, bottom);
                float bright;
                if (k > 0) {
                    bright = (0.75 + 0.45 * pow(clamp(abs(hh), 0.0, 1.0), 1.5)) * uTone.y;
                } else {
                    bright = uTone.x * (0.45 + 0.55 * nz) * fold;
                    vec3 dp = ramp(hh, deep(top), deep(upper), deep(lower), deep(bottom));
                    base = mix(dp, base, graze * graze);
                    float cw = fi == 0 ? nz * nz * nz : 0.0;
                    base = mix(base, uCore.rgb, cw * 0.8);
                }
                float spark = step(1.0 - uField.w, h4);
                float tw = 0.6 + 0.4 * sin(uTime * 3.0 + h2 * 40.0);
                vec3 cc = mix(base, (vec3(0.5) + uHot.rgb * 0.5) * 1.8 * tw, spark);
                float w = cov * mix(bright, 1.0, spark) * wface;
                col += cc * w;
                alpha += w;
            }
        }
    }
    col *= uExtra.x;
    col = 1.0 - exp(-col * 1.5);
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = clamp(mix(vec3(luma), col, uTone.z), 0.0, 1.0);
    float pointA = clamp(alpha * uExtra.x, 0.0, 1.0);
    // Premultiplied: colour never exceeds its coverage. The points lie over
    // the disc.
    vec3 points = min(col, vec3(pointA));
    fragColor = vec4(points + disc * (1.0 - pointA), pointA + discA * (1.0 - pointA)) * qt_Opacity;
}
