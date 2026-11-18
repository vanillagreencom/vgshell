#version 440
#extension GL_GOOGLE_include_directive : require
#include "orb.glsl"

// Eclipse: a nearly empty dark sphere whose outline is a thin, uneven line
// of light that runs through the palette. Where it burns it has a hot white
// core, a wide bloom inside and out and a slight colour fringe; where it
// fades it thins almost to nothing. The back wall's edge shows through the
// glass as a second, offset line that moves apart from the front one; warm
// glints with hot cores bend along the inside of the edge; a soft warm haze
// fills the glass. The voice level thickens, lights and roughens the
// outline and brightens the glints.
//
// The haze turns at twelve and seven twentieths of the swirl and the back
// wall at twenty-six twentieths: whole multiples of a twentieth, so each
// closes as the swirl clock wraps (orb.glsl).

// The signed angle from a to b, in -pi..pi.
float angDiff(float a, float b) { return mod(a - b + PI, TAU) - PI; }

void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    uv.y = -uv.y;
    float px = fwidth(uv.x);
    float r = length(uv);
    float R = uShape.x;
    if (r > R * 1.45) { fragColor = vec4(0.0); return; }
    float b = clamp(uExtra.x, 0.0, 1.5);
    float lv = uLevel;
    float ang = atan(uv.y, uv.x);

    // The uneven outline: three smooth waves round the rim, turning with
    // the orb and drifting with the field.
    float n = 0.50 * sin(2.0 * ang + uSwirl + flowPhase(90.0))
            + 0.32 * sin(3.0 * ang - 2.0 * uSwirl + flowPhase(150.0) + 1.0)
            + 0.18 * sin(5.0 * ang + flowPhase(210.0) + 2.0);
    float Rb = R * (0.97 + (0.015 + 0.025 * lv) * min(uShape.w * 4.0, 1.4) * n);
    float inside = stroke(r - Rb, 0.0, px);

    // Where the line burns: one long bright arc and a shorter one, turning,
    // and arcs where it fades almost out.
    float arc = 0.5 + 0.5 * sin(ang + uSwirl + 1.5 * n);
    float arc2 = 0.5 + 0.5 * sin(2.0 * ang - uSwirl + 1.0);
    float I = clamp(0.18 + 0.95 * smoothstep(0.25, 0.97, arc) + 0.40 * arc2 * arc2 * arc2 + 0.35 * lv, 0.0, 1.5);
    vec3 lineC = litTone(0.95 * sin(ang - uSwirl + 0.8));

    vec3 col = vec3(0.0);
    float a = 0.0;
    // Every term of the interior is scaled by its cover, so where that is
    // zero, from half a pixel past the edge, it adds exactly nothing and is
    // not shaded.
    if (inside > 0.0) {
        vec2 q = uv / Rb;
        float z = sqrt(1.0 - min(dot(q, q), 0.998));
        float gl = b * inside;
        a = inside;
        col = ink(z * 0.6, tone(q.y)) * a;

        // Soft warm volume in the glass, brighter toward one side and
        // drifting slower than the glints; the centre stays dark.
        vec3 warm = mix(hot(), tone(-1.0), 0.45);
        vec2 vc = 0.45 * vec2(cos(uSwirl * 0.6 + 2.6), sin(uSwirl * 0.6 + 2.6));
        float vol = exp(-dot(q - vc, q - vc) * 2.2) * (1.0 - 0.6 * z * z);
        col += warm * vol * 0.20 * gl;
        // A second, cooler lobe low on the other side, slower still.
        vec2 vc2 = 0.5 * vec2(cos(-uSwirl * 0.35 + 5.4), sin(-uSwirl * 0.35 + 5.4));
        col += tone(0.3) * exp(-dot(q - vc2, q - vc2) * 3.0) * (1.0 - 0.6 * z * z) * 0.12 * gl;
        col += tone(q.y * 0.8 - q.x * 0.3) * pow(1.0 - z, 1.5) * 0.06 * gl;

        // The glass lit from its own edge, by the line's colour there: a
        // wide soft bloom and a tighter one, both stronger where it burns.
        float din = Rb - r;
        col += lineC * (exp(-din / (0.10 * R)) * 0.12 + exp(-din / (0.025 * R)) * (0.30 + 0.30 * lv)) * I * gl;

        // The back wall's edge seen through the glass: a thin line of the
        // palette's lower colours, shifted and smaller, turning the other
        // way at its own speed, so the two faces move apart. Strongest on
        // one side, gone on the other.
        float bt = -1.3 * uSwirl + 0.7 * sin(flowPhase(60.0)) + 0.4;
        vec2 bo = 0.09 * vec2(cos(bt), sin(bt));
        vec2 qb = q - bo;
        float db = (length(qb) - 0.84 - 0.02 * n) * Rb;
        float bang = atan(qb.y, qb.x);
        float bw = smoothstep(-0.2, 1.0, cos(bang - bt - 0.3));
        vec3 bc = litTone(-0.2 + 0.6 * sin(bang + uSwirl));
        col += bc * (core(db, 0.8 * px + 0.003 * R) * 1.2 + core(db, 0.035 * R) * 0.25) * bw * gl;

        // Glints bending along the inside of the edge: each a crescent with
        // a hot white core, a warm bloom and red falling just outside its
        // blue, carried by the turn and the field.
        for (int k = 0; k < 3; k++) {
            float fk = float(k);
            float th = fk * 2.3 + uSwirl * (1.0 + fk) + 0.6 * sin(flowPhase(30.0 * (2.0 + fk)) + fk);
            float rad = Rb * (0.74 + 0.10 * sin(flowPhase(90.0) + fk * 2.0));
            float al = angDiff(ang, th) * rad / (R * (0.24 - 0.05 * fk));
            float across = R * (0.045 + 0.012 * fk);
            float ac = (r - rad) / across;
            float e = al * al + ac * ac;
            float hk = exp(-e);
            float hc = exp(-e * 4.0);
            float hb = exp(-sqrt(e) * 1.2) * 0.30;
            float acR = (r - rad - 0.008 * R) / across;
            float red = exp(-(al * al + acR * acR)) - hk;
            float s = (0.75 - 0.15 * fk) * (0.75 + 0.6 * lv);
            col += (warm * (hk * 0.8 + hb) + vec3(1.0, 0.95, 0.9) * hc * 0.9 + vec3(0.6, 0.1, 0.05) * max(red, 0.0)) * s * gl;
        }

        // A fainter inner arc of the upper colour, sweeping the other way,
        // brightest in its middle and fading to its ends.
        float a0 = -2.0 * uSwirl + 2.0;
        float win = smoothstep(0.55, 1.0, cos(ang - a0));
        float dI = r - Rb * (0.94 + 0.015 * n);
        col += litTone(0.6) * (stroke(abs(dI), 0.5 * px + R * 0.002 * win, px) * 0.8 + core(dI, 0.02 * R) * 0.12) * win * win * gl;

        // A soft gloss on the upper left of the glass.
        col += mix(lineC, vec3(1.0), 0.4) * glint(q, vec2(-0.38, 0.55), 0.38, 0.16, 0.6) * 0.08 * gl;
    }

    // The outline: thin and faint where it fades, a hot core where it
    // burns, a slight colour fringe at its bright edge. Drawn over, never
    // darker than the palette, so it reads on light.
    float lw = 0.55 * px + R * (0.004 + 0.009 * lv) * (0.2 + I * I);
    float d = r - (Rb - 0.5 * lw);
    vec3 cov = fringe(d, lw, px, 0.6 * px * (0.5 + I)) * clamp(0.30 + 0.70 * I, 0.0, 1.0);
    float hotc = core(d, lw * 0.6) * smoothstep(0.55, 1.3, I);
    vec3 lc = burn(lineC, (0.85 + 0.9 * hotc) * clamp(b, 0.45, 1.3));
    layStroke(col, a, lc, cov);
    // A tight halo just outside the line where it burns.
    col += lineC * core(r - Rb, 0.012 * R) * 0.35 * I * I * (1.0 - a) * b;

    fragColor = finish(col, a, uv, r, Rb, lineC * (0.2 + 0.9 * I), 0.50 * b * (1.0 + 0.5 * lv));
}
