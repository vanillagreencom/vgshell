#version 440
#extension GL_GOOGLE_include_directive : require
#include "orb.glsl"

// Bubble: a thick glass bubble. Its shell has two faces, a bright outer
// edge of the palette's top colour and a fainter inner edge, with the glass
// between them lit; the back wall's edge shows through, shifted by the
// glass, and light bent through the bubble gathers in a bright crescent
// opposite the light. A thin film of colour runs over the glass, three
// bands curve round inside it (a hot line with a bloom and a soft sheet off
// one side, fainter on the back face), a window highlight sits on top, and
// a cloud of sparks in two depths turns at the centre. The voice level
// swells the film, widens the bands and spreads the cloud.
//
// The back wall turns at fourteen twentieths of the swirl: a whole multiple
// of a twentieth, so it closes as the swirl clock wraps (orb.glsl).

// One layer of the spark cloud: a jittered dot in each grid cell, lit in
// a share `density` of the cells, those whose hash is at least
// 1 - density. sparkHash is the cell's hash, sparkDist the distance to its
// dot.
float sparkHash(vec2 p, float cells, float seed) {
    return hash13(vec3(floor(p * cells), seed));
}
float sparkDist(vec2 p, float cells, float seed) {
    vec2 g = p * cells;
    vec2 id = floor(g);
    vec2 jit = (vec2(hash13(vec3(id, seed + 1.7)), hash13(vec3(id, seed + 3.1))) - 0.5) * 0.5;
    return length(fract(g) - 0.5 - jit) / cells;
}

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
    vec2 dir = uv / max(r, 1e-5);
    // The film quivers, more with the level.
    float Re = R * (0.98 + 0.025 * lv)
             + R * (0.004 + 0.014 * lv) * sin(3.0 * ang + flowPhase(300.0)) * sin(2.0 * ang - flowPhase(225.0) + 1.0);
    float inside = stroke(r - Re, 0.0, px);
    vec3 rimC = litTone(0.85 + 0.15 * dir.y);
    // How much a point of the edge faces the light (upper left).
    float facing = dot(dir, vec2(-0.555, 0.832));

    vec3 col = vec3(0.0);
    float a = 0.0;
    // Every term of the interior is scaled by its cover, so where that is
    // zero, from half a pixel past the edge, it adds exactly nothing and is
    // not shaded.
    if (inside > 0.0) {
        vec2 q = uv / Re;
        float z = sqrt(1.0 - min(dot(q, q), 0.998));
        a = inside;
        col = ink(z, tone(q.y)) * a;
        float gl = b * inside;

        // The thin film: a colour that runs with the viewing angle and
        // drifts, strongest toward the edge, as a soap film's does.
        float ph = 4.5 * z + 1.2 * q.x - 0.8 * q.y + flowPhase(60.0);
        vec3 film = litTone(0.9 * sin(ph));
        col += film * (0.035 + 0.30 * pow(1.0 - z, 2.5)) * gl;

        // The shell: the glass between the outer and the inner face lit
        // by the rim's colour, and the inner face as a fine bright line.
        float shell = R * (0.075 + 0.02 * lv);
        float di = r - (Re - shell);
        col += rimC * smoothstep(-0.01 * R, shell, di) * 0.32 * gl;
        col += burn(rimC, 0.8) * (core(di, 0.7 * px + 0.002 * R) * (0.45 + 0.35 * facing)
                                 + core(di, 0.02 * R) * 0.12) * gl;

        // The back wall's edge through the glass, shifted and shrunk by it,
        // turning slowly the other way.
        vec2 bo = 0.05 * vec2(cos(-uSwirl * 0.7 + 2.4), sin(-uSwirl * 0.7 + 2.4));
        float db = (length(q - bo) - 0.88) * Re;
        float backWin = 0.35 + 0.65 * smoothstep(-0.2, 0.8, dot(normalize(q - bo + 1e-5), vec2(0.6, -0.8)));
        col += litTone(0.4) * (core(db, 0.9 * px) * 0.5 + core(db, 0.03 * R) * 0.10) * backWin * gl;

        // Light bent through the bubble gathers in a crescent on the far
        // side from the light: a hot core in a soft bloom.
        float cr = r - Re * 0.83;
        float gather = smoothstep(0.25, 0.95, -facing);
        col += burn(mix(rimC, vec3(1.0), 0.15), (core(cr, 0.018 * R) * 0.9 + core(cr, 0.07 * R) * 0.3) * gather * gather * 1.2) * gl;

        // The bands: three planes that turn at their own rates. Each draws
        // a hot line with a bloom and a sheet fading off one side, with a
        // slight colour fringe on the line, brightest along part of its run.
        mat3 M = orbMatrix();
        vec3 of = M * vec3(q, z);
        vec3 ob = M * vec3(q, -z);
        float bw = 0.09 + 0.07 * lv;
        float lw = 0.9 * px / (Re * max(z, 0.25));
        vec3 bands = vec3(0.0);
        for (int k = 0; k < 3; k++) {
            float fk = float(k);
            float t = fk * 2.1 + flowPhase(30.0 * (1.0 + fk));
            vec3 nrm = normalize(vec3(cos(t), 0.55 * (fk - 1.0) + 0.2, sin(t)));
            vec3 c = litTone(0.55 - 0.6 * fk);
            vec3 ax = normalize(cross(nrm, vec3(0.0, 1.0, 0.0)) + 1e-4);
            float run = 0.35 + 0.65 * smoothstep(-0.7, 0.9, sin(3.0 * dot(of, ax) + t * 2.0 + fk));
            float df = dot(of, nrm);
            float dbk = dot(ob, nrm);
            vec3 line = fringeCore(df, lw * 1.1, lw * 0.9);
            float sheet = smoothstep(0.0, 0.025, df) * exp(-df / bw);
            vec3 front = c * (sheet * 0.26 + core(df, lw * 4.0) * 0.22) * run + burn(c, 0.9 * run) * line * 0.75;
            float back = smoothstep(0.0, 0.025, dbk) * exp(-dbk / bw) * 0.06 + core(dbk, lw * 2.2) * 0.12;
            bands += front + c * back;
        }
        col += bands * (0.9 + 0.3 * lv) * mix(0.6, 1.0, uTone.w) * gl;

        // The window highlight: a soft bright pane on the upper left with a
        // hot core, and a small sharp point of light beside it.
        float win = glint(q, vec2(-0.42, 0.52), 0.30, 0.13, 0.62);
        float pt = core(length(q - vec2(-0.20, 0.70)), 0.035);
        col += burn(mix(rimC, vec3(1.0), 0.55), win * 0.45 + pt * 0.9) * gl;

        // The spark cloud in two depths: a near layer of larger, hotter
        // sparks with a bloom, and a far one, smaller and dimmer, turning
        // the other way.
        float cloud = R * 0.24 * (1.0 + 0.5 * lv);
        if (r < cloud * 2.3) {
            float dens = clamp(exp(-(r * r) / (cloud * cloud)) * (0.55 + 0.35 * lv + 6.0 * uField.w), 0.0, 0.85);
            float cs = cos(uSwirl), sn = sin(uSwirl);
            vec2 p1 = mat2(cs, sn, -sn, cs) * uv;
            vec2 p2 = mat2(cs, -sn, sn, cs) * uv * 1.07;
            // A layer's light is zero in a cell with no spark, so it is
            // only evaluated in a lit cell, and summed before it lands so
            // two lit layers round as one sum.
            vec3 sparks = vec3(0.0);
            float h1 = sparkHash(p1, 26.0, 1.0);
            if (h1 >= 1.0 - dens) {
                float d1 = sparkDist(p1, 26.0, 1.0);
                float tw1 = 0.45 + 0.55 * sin(uTime * 3.0 + h1 * 40.0);
                float size1 = px * (0.7 + 1.1 * fract(h1 * 7.3));
                float s1 = (core(d1, size1) + 0.35 * bloom(d1, size1 * 1.8)) * tw1;
                vec3 sc = mix(litTone(-0.75), mix(hot(), vec3(1.0), 0.3), h1 * h1);
                sparks = burn(sc, s1 * 1.3) * gl;
            }
            float h2 = sparkHash(p2, 38.0, 7.0);
            if (h2 >= 1.0 - dens * 0.9) {
                float d2 = sparkDist(p2, 38.0, 7.0);
                float tw2 = 0.55 + 0.45 * sin(uTime * 2.0 + h2 * 33.0);
                float s2 = (core(d2, px * 0.75) * 0.55 + 0.15 * bloom(d2, px * 1.5)) * tw2;
                sparks += litTone(-0.3) * s2 * 0.8 * gl;
            }
            col += sparks;
            // A faint glow of the cloud as a whole.
            col += litTone(-0.75) * exp(-(r * r) / (cloud * cloud * 1.6)) * 0.06 * gl;
        }
    }

    // The outer face: a lit tube of the top colour with a hot core and a
    // slight colour fringe, brighter toward the light. Drawn over, so it
    // reads on any ground.
    float rw = R * (0.024 + 0.012 * lv);
    float dr = r - (Re - rw * 0.5 + 0.5 * px);
    float facingLight = 0.78 + 0.22 * facing;
    vec3 rc = fringe(dr, rw * 0.5, px, 0.7 * px);
    float hotc = core(dr, rw * 0.22);
    vec3 tube = burn(rimC, (0.85 + 0.7 * hotc * (0.4 + 0.6 * max(facing, 0.0))) * facingLight * clamp(b, 0.45, 1.3));
    layStroke(col, a, tube, rc);
    // A sharp glint where the outer face meets the light.
    float spark = core(dr, rw * 0.3) * pow(max(facing, 0.0), 12.0);
    col += vec3(1.0) * spark * 0.8 * b;

    fragColor = finish(col, a, uv, r, Re, rimC, 0.42 * b * (1.0 + 0.5 * lv));
}
