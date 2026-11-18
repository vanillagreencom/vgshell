#version 440
#extension GL_GOOGLE_include_directive : require
#include "orb.glsl"

// Ribbons: a glowing ring of light round a dark lens: a tube with a hot
// core, a slight colour fringe and a bloom, brightest on two arcs that
// turn. Two bundles of fine ribbons twist through and beyond it, in front
// of the ring on one side and behind it on the other. Each strand changes
// weight and brightness along its length, a faint sheet joins the strands,
// the strands burn where a bundle turns edge-on, and the strands behind the
// ring are softer and dimmer. A scatter of dots and short dashes of
// different sizes trails round the outside. The voice level thickens the
// ring, swings the ribbons wider and spreads their strands.

// One bundle of seven strands round the closed curve r = base(theta),
// spaced by a gap that changes sign along the curve, so the bundle twists.
// Returns the strand cover at the pixel (its brightness along its length
// included) and sets the faint sheet between the strands, its visibility,
// its depth and how far it is turned edge-on.
float bundle(float r, float ang, float R0, float R, float px, float lv, int k, float soft,
             out float sheet, out float vis, out float front, out float edgeOn) {
    float fk = float(k);
    float sg = k == 0 ? 1.0 : -1.0;
    float th = ang - sg * uSwirl;
    float m = 2.0 + fk;
    // Its halves and its seven tenths below are whole cycles too.
    float ph = flowPhase(120.0 * (1.0 + fk)) + fk * 1.7;
    float A = 0.22 + 0.35 * uShape.w + 0.10 * lv;
    float s1 = sin(m * th + ph), c1 = cos(m * th + ph);
    float s2 = sin((m + 1.0) * th - ph + 1.0), c2 = cos((m + 1.0) * th - ph + 1.0);
    float base = R0 * (1.0 + A * (s1 + 0.3 * s2));
    float slope = R0 * A * (m * c1 + 0.3 * (m + 1.0) * c2) / max(r, 1e-3);
    float tw = sin(th + ph * 0.5 + fk * 2.0);
    float gap = R * 0.026 * (1.0 + 0.5 * lv) * tw;
    float corr = inversesqrt(1.0 + slope * slope);
    float d0 = r - base;
    float ag = max(abs(gap), 1e-5);
    // Past this distance both strokes below clamp to zero: the nearest
    // strand sits at least abs(d0) - 3 ag away, the span's edge at 3 ag,
    // a strand's half-width w is at most px (0.90 + 0.40 soft) and each
    // stroke's soft edge reaches at most px (1 + soft) / 2 past it. The last
    // px / 10 is margin for rounding, so a pixel left out here is one the
    // bundle covers with exactly zero.
    if (abs(d0) * corr > 3.0 * ag * corr + px * (0.90 + 0.40 * soft) + 0.5 * px * (1.0 + soft) + 0.1 * px) {
        sheet = 0.0; vis = 0.0; front = 0.0; edgeOn = 0.0;
        return 0.0;
    }
    float j = clamp(floor(d0 / (sign(gap) * ag) + 0.5), -3.0, 3.0);
    // Each strand's weight and brightness run along its length.
    float wv = 0.5 + 0.5 * sin(3.0 * th + j * 1.3 + ph);
    float w = px * (0.35 + 0.55 * wv) + soft * 0.4 * px;
    float lum = 0.35 + 0.65 * smoothstep(-0.5, 0.8, sin(2.0 * th - j * 0.8 - ph * 0.7 + fk));
    float cov = stroke(abs(d0 - j * gap) * corr, w, px * (1.0 + soft)) * lum;
    // Where the strands crowd closer than a few pixels, draw their average.
    float span = stroke(abs(d0) * corr, 3.0 * ag * corr + w, px);
    float avg = min(1.3 * w / (ag * corr), 0.7) * span * lum;
    cov = mix(avg, cov, smoothstep(2.0 * px, 4.0 * px, ag * corr));
    sheet = span * 0.10 * (0.4 + 0.6 * abs(tw));
    vis = 0.25 + 0.75 * smoothstep(-0.4, 0.7, sin(th + ph * 0.5 + 2.0 + fk * 2.0));
    front = step(0.0, sin(th + fk * 1.3));
    edgeOn = 1.0 - smoothstep(0.0, 0.35, abs(tw));
    return cov;
}

void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    uv.y = -uv.y;
    float px = fwidth(uv.x);
    float r = length(uv);
    float R = uShape.x;
    if (r > R * 1.5) { fragColor = vec4(0.0); return; }
    float b = clamp(uExtra.x, 0.0, 1.5);
    float lv = uLevel;
    float ang = atan(uv.y, uv.x);

    float R0 = R * (0.80 + 0.02 * lv);
    float tw = R * (0.026 + 0.018 * lv);
    float dr = r - R0;
    float ringH = 0.95 * sin(ang + uSwirl + 0.6);
    vec3 ringT = litTone(ringH);
    // The ring burns on two arcs that turn, and dims between them.
    float ringI = 0.40 + 0.60 * pow(0.5 + 0.5 * sin(ang + uSwirl + 2.2), 2.0)
                + 0.45 * pow(0.5 + 0.5 * sin(ang + uSwirl - 0.9), 6.0);

    // The dark lens inside the ring.
    float a = 1.0 - smoothstep(R0 - 0.05 * R, R0 + 0.01 * R, r);
    vec3 col = vec3(0.0);
    // Every term of the lens is scaled by its cover, so where that is zero
    // the lens adds exactly nothing and is not shaded.
    if (a > 0.0) {
        vec2 q = uv / R0;
        float z = sqrt(1.0 - min(dot(q, q), 0.998));
        col = ink(z, tone(q.y)) * a;
        // The ring's light on the lens's inner face: a tight bloom and a
        // wide one, and a faint far reflection of the bright arc.
        col += ringT * (exp(-abs(dr) / (0.035 * R)) * 0.35 + exp(-abs(dr) / (0.14 * R)) * 0.18) * ringI * a * (0.8 + 0.4 * lv) * b;
        col += tone(-ringH) * glint(q, vec2(0.0), 0.75, 0.75, 0.0) * 0.035 * a * b;
    }

    // The ribbons, split by depth round the ring.
    vec3 backC = vec3(0.0); float backA = 0.0;
    vec3 frontC = vec3(0.0); float frontA = 0.0;
    float gain = clamp(b, 0.4, 1.3) * mix(0.6, 1.0, uTone.w);
    for (int k = 0; k < 2; k++) {
        float sheet, vis, fr, eo;
        // The side behind the ring draws softer.
        float soft = 1.0 - step(0.0, sin(ang - (k == 0 ? 1.0 : -1.0) * uSwirl + float(k) * 1.3));
        float cv0 = bundle(r, ang, R0, R, px, lv, k, soft, sheet, vis, fr, eo);
        // A bundle with no cover here composites as the identity.
        if (cv0 <= 0.0 && sheet <= 0.0) continue;
        vec3 c = saturate3(litTone(0.95 - 0.55 * float(k)), 1.15) * gain;
        vec3 cHot = burn(c, 1.0 + 0.5 * eo);
        float cv = cv0 * vis;
        float sh = sheet * vis;
        if (fr > 0.5) {
            frontC = c * sh + frontC * (1.0 - sh); frontA = sh + frontA * (1.0 - sh);
            frontC = cHot * cv + frontC * (1.0 - cv); frontA = cv + frontA * (1.0 - cv);
        } else {
            // Behind the ring: dimmer and softer.
            cv *= 0.7; sh *= 0.6;
            backC = c * sh + backC * (1.0 - sh); backA = sh + backA * (1.0 - sh);
            backC = c * cv + backC * (1.0 - cv); backA = cv + backA * (1.0 - cv);
        }
    }
    col = backC + col * (1.0 - backA);
    a = backA + a * (1.0 - backA);

    // The ring: a lit tube with a hot core and a slight colour fringe.
    vec3 rc = fringe(dr, tw, px, 0.9 * px);
    float hotc = core(dr, tw * 0.38);
    vec3 tube = burn(ringT, (0.65 + 0.35 * ringI + 0.75 * hotc * ringI) * clamp(b, 0.45, 1.3));
    tube = mix(tube, tube * 0.7, smoothstep(0.3 * tw, tw, abs(dr)));
    layStroke(col, a, tube, rc);

    col = frontC + col * (1.0 - frontA);
    a = frontA + a * (1.0 - frontA);

    // The scatter of dots and short dashes outside the ring, turning with
    // it: each with its own size, a hot core and a twinkle.
    if (r > R0 * 1.02 && r < R * 1.42) {
        float g = mod((ang + PI + uSwirl) / TAU * 96.0, 96.0);
        float gr = (r - R0) / (R * 0.05);
        vec2 cell = vec2(g, gr);
        vec2 id = floor(cell);
        float h = hash13(vec3(id, 3.0));
        float dens = (0.18 + 6.0 * uField.w + 0.25 * lv) * exp(-pow((r - R * 1.02) / (0.24 * R), 2.0));
        // Only a share dens of the cells holds one; a cell without one, or
        // a pixel its stroke does not reach, composites as the identity.
        if (h >= 1.0 - dens) {
            vec2 jit = (vec2(hash13(vec3(id, 5.3)), hash13(vec3(id, 9.1))) - 0.5) * 0.5;
            vec2 f = (fract(cell) - 0.5 - jit) * vec2(TAU * r / 96.0, R * 0.05);
            // A share of them are dashes along the turn.
            float dash = step(0.72, fract(h * 13.7));
            f.x /= 1.0 + 2.5 * dash;
            float tws = 0.5 + 0.5 * sin(uTime * 2.0 + h * 50.0);
            float size = px * (0.6 + 0.9 * fract(h * 31.1));
            float dl = length(f);
            float dc = tws * stroke(dl, size, px);
            if (dc > 0.0) {
                vec3 c = burn(litTone(h > 0.5 ? 0.9 : 0.3), 1.0 + 0.6 * core(dl, size * 0.6)) * gain;
                col = c * dc + col * (1.0 - dc);
                a = dc + a * (1.0 - dc);
            }
        }
    }

    fragColor = finish(col, a, uv, r, R0 + tw, ringT * (0.5 + 0.5 * ringI), 0.46 * b * (1.0 + 0.6 * lv));
}
