#version 440
#extension GL_GOOGLE_include_directive : require
#include "orb.glsl"

// Blades: four see-through blades of light in a smoked glass sphere. Each
// blade is a curved, pointed lens: one crisp edge with a hot line and a
// slight colour fringe, the other edge soft, a fill that brightens toward
// the crisp edge and a colour that runs from a hot white at the centre to
// its palette colour at the tip. The blades turn in pairs that go opposite
// ways and add up to a hot centre with a soft bloom and two faint flare
// streaks. Behind them two broad petals of coloured smoke, each with a lit
// edge, drift slower; the glass has a rim that gathers light and the back
// wall's edge showing through. The voice level lengthens and widens the
// blades and lights the centre.
//
// The petals turn at nine twentieths of the swirl, the flare at a quarter
// and the rim's light at a half: whole multiples of a twentieth, so each
// closes as the swirl clock wraps (orb.glsl).

void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    uv.y = -uv.y;
    float px = fwidth(uv.x);
    float r = length(uv);
    float R = uShape.x;
    if (r > R * 1.45) { fragColor = vec4(0.0); return; }
    float b = clamp(uExtra.x, 0.0, 1.5);
    float lv = uLevel;
    vec2 dir = uv / max(r, 1e-5);
    float ang = atan(uv.y, uv.x);

    // The sphere: smoked glass with a soft edge.
    float Re = R * (0.97 + 0.025 * lv);
    float body = 1.0 - smoothstep(Re - 0.05 * R, Re + 0.012 * R, r);
    float a = body;
    vec3 col = vec3(0.0);

    // The glass rim: light gathers toward the edge in the palette's colour
    // there, a fine bright line with a slight fringe, brighter on a side
    // that turns.
    vec3 rimT = litTone(dir.y * 0.8 + 0.2);
    float rimI = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(ang - uSwirl * 0.5 + 2.0), 2.0);
    // The glass and the light it gathers are scaled by its cover, so where
    // that is zero they add exactly nothing and are not shaded.
    if (body > 0.0) {
        vec2 q = uv / Re;
        float z = sqrt(1.0 - min(dot(q, q), 0.998));
        col = ink(z, tone(q.y)) * a;
        col += rimT * pow(1.0 - z, 4.0) * 0.35 * b * body;
    }
    vec3 rimF = fringe(r - Re * 0.975, 0.45 * px + R * 0.0025, px, 0.7 * px);
    col += burn(rimT, 0.6 + 0.6 * rimI) * rimF * 0.55 * b;

    vec3 light = vec3(0.0);
    if (r < Re) {
        // The back wall's edge through the glass, shifted toward the lower
        // right.
        vec2 bo = vec2(0.04, -0.05) * Re;
        float db = length(uv - bo) - Re * 0.90;
        float bwin = smoothstep(0.0, 0.9, dot(normalize(uv - bo + 1e-5), vec2(0.6, -0.8)));
        light += litTone(-0.4) * (core(db, 0.7 * px) * 0.20 + core(db, 0.03 * R) * 0.06) * bwin;

        // Two petals of coloured smoke behind the blades, drifting round
        // slower than them, the two ways: a soft body, brighter toward a
        // lit edge.
        for (int k = 0; k < 2; k++) {
            float fk = float(k);
            float pa = uSwirl * (0.45 - 0.9 * fk) + fk * 3.3 + 0.5;
            vec2 pc = (0.22 - 0.06 * fk) * R * vec2(cos(pa), sin(pa));
            vec2 dp = uv - pc;
            float pr = length(dp);
            float pt = atan(dp.y, dp.x);
            float rb = R * (0.56 - 0.12 * fk) * (1.0 + 0.16 * sin(2.0 * pt + flowPhase(30.0 * (2.0 + fk)) + fk)
                                                     + 0.08 * sin(3.0 * pt - flowPhase(90.0)));
            float fill = 1.0 - smoothstep(rb * 0.86, rb, pr);
            float edge = core(pr - rb * 0.95, 0.035 * R) * smoothstep(-0.3, 0.9, cos(pt - pa - 0.8));
            vec3 pcC = saturate3(tone(fk < 0.5 ? -0.75 : 0.55), 1.15);
            light += pcC * (fill * (0.10 + 0.22 * pr / rb) + edge * 0.24) * (1.0 - 0.35 * fk);
        }

        // The blades: the first pair turns at the swirl, the second twice
        // as fast, each pair's two blades opposite ways.
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            float sgn = (k == 0 || k == 2) ? 1.0 : -1.0;
            float th = fk * 2.3 + sgn * uSwirl * (k < 2 ? 1.0 : 2.0)
                     + 0.22 * sin(flowPhase(300.0) + fk * 1.9);
            vec2 d = vec2(cos(th), sin(th));
            float u = dot(uv, d);
            float v = dot(uv, vec2(-d.y, d.x));
            float L = R * (0.66 + 0.09 * fk - 0.035 * fk * fk + 0.10 * lv);
            float c = L * (0.22 - 0.07 * fk);
            float t = (u - c) / L;
            if (abs(t) < 1.0) {
                float bend = 0.30 * sin(fk * 1.7 + flowPhase(150.0));
                float sv = v - bend * (u - c) * (u - c) / L;
                float vv = abs(sv);
                float W = R * (0.15 + 0.04 * fk - 0.015 * fk * fk) * (1.0 + 0.4 * lv);
                float w = W * (1.0 - t * t);
                // Keep each blade's bright edge on its winding side as the
                // bend passes through zero; its sign would flip the whole
                // edge at that crossing, including the flow clock's wrap.
                float side = sgn;
                float crisp = sv * side > 0.0 ? 1.0 : 0.0;
                float across = clamp(sv / max(w, 1e-5) * side * 0.5 + 0.5, 0.0, 1.0);
                float hard = 1.0 - smoothstep(w - 1.2 * px, w + 0.3 * px, vv);
                float soft = pow(max(1.0 - vv / max(w, 1e-5), 0.0), 1.6);
                float fill = mix(soft, hard, crisp) * (0.35 + 0.65 * across * across);
                float spine = core(vv, w * 0.28 + 1e-5) * (1.0 - abs(t));
                vec3 edge = fringeCore(vv - w, 0.9 * px, 0.8 * px) * crisp * (1.0 - t * t);
                float taper = 1.0 - abs(t * t * t);
                vec3 bc = saturate3(litTone(0.9 - 0.6 * fk), 1.2);
                vec3 tipC = mix(mix(bc, vec3(1.0), 0.45), bc, smoothstep(0.0, 0.7, abs(t)));
                light += tipC * (fill * 0.42 + spine * 0.45) * taper + burn(bc, 0.9) * edge * 0.55 * taper;
            }
        }
        // The hot centre where the blades cross: a white core, a bloom of
        // the hot colour and two faint flare streaks that turn slowly.
        float cr = R * 0.10 * (1.0 + 0.5 * lv);
        float cen = exp(-(r * r) / (cr * cr));
        float blm = exp(-r / (R * 0.22));
        float fa = uSwirl * 0.25 + 0.3;
        vec2 fd = vec2(cos(fa), sin(fa));
        vec2 fn = vec2(-fd.y, fd.x);
        float f1 = exp(-abs(dot(uv, fn)) / (0.006 * R)) * exp(-abs(dot(uv, fd)) / (0.30 * R));
        float f2 = exp(-abs(dot(uv, fd)) / (0.005 * R)) * exp(-abs(dot(uv, fn)) / (0.18 * R));
        vec3 h = hot();
        light += mix(h, vec3(1.0), 0.6) * cen * (0.8 + 0.6 * lv)
               + h * blm * 0.22 * (1.0 + 0.5 * lv)
               + mix(h, vec3(1.0), 0.4) * (f1 * 0.35 + f2 * 0.2) * (0.6 + 0.6 * lv);
        light *= b * mix(0.6, 1.0, uTone.w) * body;
    }
    // Light adds on the smoked glass; a soft knee keeps the colours from
    // washing to white except at the very centre.
    col += light / (1.0 + 0.30 * max(light.r, max(light.g, light.b)));

    fragColor = finish(col, a, uv, r, Re, litTone(dir.y), 0.30 * b * (1.0 + 0.6 * lv));
}
