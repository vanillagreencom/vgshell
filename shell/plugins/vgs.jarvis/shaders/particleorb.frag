#version 440

// The Jarvis particle orb in one fragment pass (ParticleOrb.qml).
//
// The orb is four concentric shells of dots. Shell 0 is the lattice the
// interior shows; shells 1-3 draw only near the silhouette, where their
// noise-displaced outlines stack into the warped bright band and the spray
// beyond it. Each shell is hit twice (front and back of the sphere), each
// hit is moved once by a two-octave value-noise radius, mapped to a
// cube-sphere lattice cell, and tested against the 2x2 nearest cells' dots.
// Work per pixel is constant and bounded: 4 shells x 2 faces x (2 noise
// octaves + 3 lattice-warp noises + 4 dot tests), plus one fold noise on
// shell 0's front; a rim shell stops after its 2 octaves where it is not
// near its silhouette. Pixels past the spray's reach return at once.
// The reduced look (uReduce above 0.5) skips the inner rim shell and the
// rim shells' back faces: 2 rim hits a pixel instead of 6. Every loop
// bound stays a constant either way.
//
// The default Qt Quick vertex shader shares this uniform buffer, so
// qt_Matrix and qt_Opacity stay first. Output is premultiplied.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;   // spark twinkle clock, seconds
    float uFlow;   // noise-field clock
    float uSwirl;  // lattice turn about the vertical axis, radians
    vec4 uTop;     // rim palette, top to bottom
    vec4 uUpper;
    vec4 uLower;
    vec4 uBottom;
    vec4 uCore;    // interior centre tint
    vec4 uHot;     // spark colour
    vec4 uShape;   // radius share, cells per cube edge, dot radius share, displacement
    vec4 uField;   // noise frequency, lattice warp, scatter, spark share
    vec4 uTone;    // interior gain, rim gain, saturation, presence
    vec4 uExtra;   // brightness, tilt, fold depth, lattice period in cells
    float uReduce; // above 0.5: the reduced look
};

const float PI = 3.14159265;

float hash13(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Value noise on a lattice that repeats every uExtra.w cells on each axis,
// so the flow clock wraps at a whole number of periods with no jump
// (ParticleOrb.qml `flowTurn`), and the hash reads small coordinates.
float vnoise(vec3 x) {
    vec3 i = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    vec3 i0 = mod(i, uExtra.w);
    vec3 i1 = mod(i + 1.0, uExtra.w);
    float a = mix(hash13(i0), hash13(vec3(i1.x, i0.y, i0.z)), f.x);
    float b = mix(hash13(vec3(i0.x, i1.y, i0.z)), hash13(vec3(i1.x, i1.y, i0.z)), f.x);
    float c = mix(hash13(vec3(i0.x, i0.y, i1.z)), hash13(vec3(i1.x, i0.y, i1.z)), f.x);
    float d = mix(hash13(vec3(i0.x, i1.y, i1.z)), hash13(i1), f.x);
    return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

// The radius field: a low octave every shell shares, so the band's lobes
// stay one band, and a rough octave each shell takes at its own phase.
float field(vec3 o, float k, float rough) {
    vec3 q = o * uField.x + vec3(0.0, uFlow, 0.0);
    float n = (1.0 - rough) * vnoise(q)
            + rough * vnoise(q * 2.3 + vec3(3.1 + k * 4.3, -uFlow * 0.7, 1.7 + k * 2.9));
    return n - 0.5;
}

vec3 ramp(float h, vec3 top, vec3 upper, vec3 lower, vec3 bottom) {
    if (h > 0.35) return mix(upper, top, clamp((h - 0.35) / 0.65, 0.0, 1.0));
    if (h > -0.25) return mix(lower, upper, clamp((h + 0.25) / 0.60, 0.0, 1.0));
    return mix(bottom, lower, clamp((h + 0.80) / 0.55, 0.0, 1.0));
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
    if (r > R * 1.3) { fragColor = vec4(0.0); return; }

    float cy = cos(uSwirl), sy = sin(uSwirl);
    float cx = cos(uExtra.y), sx = sin(uExtra.y);
    // Object from view: a turn about y after a fixed tilt about x.
    mat3 M = mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy)
           * mat3(1.0, 0.0, 0.0, 0.0, cx, sx, 0.0, -sx, cx);
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
        float amp = min(uShape.w * amps * (k == 3 ? uField.z : 1.0), 0.45);
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
                vec3 base = ramp(clamp(hh, -1.0, 1.0), top, upper, lower, bottom);
                float b;
                if (k > 0) {
                    b = (0.75 + 0.45 * pow(clamp(abs(hh), 0.0, 1.0), 1.5)) * uTone.y;
                } else {
                    b = uTone.x * (0.45 + 0.55 * nz) * fold;
                    vec3 dp = ramp(clamp(hh, -1.0, 1.0), deep(top), deep(upper), deep(lower), deep(bottom));
                    base = mix(dp, base, graze * graze);
                    float cw = fi == 0 ? nz * nz * nz : 0.0;
                    base = mix(base, uCore.rgb, cw * 0.8);
                }
                float spark = step(1.0 - uField.w, h4);
                float tw = 0.6 + 0.4 * sin(uTime * 3.0 + h2 * 40.0);
                vec3 cc = mix(base, (vec3(0.5) + uHot.rgb * 0.5) * 1.8 * tw, spark);
                float w = cov * mix(b, 1.0, spark) * wface;
                col += cc * w;
                alpha += w;
            }
        }
    }
    col *= uExtra.x;
    col = 1.0 - exp(-col * 1.5);
    float luma = dot(col, vec3(0.299, 0.587, 0.114));
    col = clamp(mix(vec3(luma), col, uTone.z), 0.0, 1.0);
    float a = clamp(alpha * uExtra.x, 0.0, 1.0);
    // Premultiplied: colour never exceeds its coverage.
    fragColor = vec4(min(col, vec3(a)), a) * qt_Opacity;
}
