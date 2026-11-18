// The head every Jarvis orb style includes: the uniform block
// ParticleOrb.qml feeds each style's shader, and the helpers more than one
// style draws with. qsb resolves `#include` beside the including file under
// GL_GOOGLE_include_directive (qsb 6.12.0, a compile run in this tree).
//
// The clocks wrap where every style's motion closes (ParticleOrb.qml):
// uTime at 2π, so a style reads it at whole multiples; uFlow at ten
// lattice periods, which flowPhase turns into whole cycles; uSwirl at
// twenty turns, so a style reads it at whole multiples of a twentieth. A
// phase read any other way jumps each time its clock wraps.
//
// The default Qt Quick vertex shader shares this uniform buffer, so
// qt_Matrix and qt_Opacity stay first. Output is premultiplied.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;   // twinkle clock, seconds
    float uFlow;   // noise-field clock
    float uSwirl;  // turn about the vertical axis, radians
    vec4 uTop;     // palette, top to bottom
    vec4 uUpper;
    vec4 uLower;
    vec4 uBottom;
    vec4 uCore;    // interior centre tint
    vec4 uHot;     // spark colour
    vec4 uShape;   // radius share, cells per cube edge, dot radius share, displacement
    vec4 uField;   // noise frequency, lattice warp, scatter, spark share
    vec4 uTone;    // interior gain, rim gain, saturation, presence
    vec4 uExtra;   // brightness (throb and level included), tilt, fold depth, lattice period in cells
    float uReduce; // above 0.5: the reduced look
    float uLevel;  // the eased driving level through the input curve, 0 to 1
};

const float PI = 3.14159265;
const float TAU = 6.2831853;

// The phase of a wave that runs TURNS whole cycles in one turn of the flow
// clock, ten lattice periods.
float flowPhase(float turns) { return uFlow * turns * TAU / (10.0 * uExtra.w); }

float hash13(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Value noise on a lattice that repeats every uExtra.w cells on each axis,
// so a flow offset of a whole number of periods draws the same field, and
// the hash reads small coordinates.
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

// Four stops over a height from -1 (bottom) to 1 (top).
vec3 ramp(float h, vec3 top, vec3 upper, vec3 lower, vec3 bottom) {
    h = clamp(h, -1.0, 1.0);
    if (h > 0.35) return mix(upper, top, (h - 0.35) / 0.65);
    if (h > -0.25) return mix(lower, upper, (h + 0.25) / 0.60);
    return mix(bottom, lower, clamp((h + 0.80) / 0.55, 0.0, 1.0));
}

// The state's palette at height h.
vec3 palette(float h) { return ramp(h, uTop.rgb, uUpper.rgb, uLower.rgb, uBottom.rgb); }

vec3 saturate3(vec3 c, float s) {
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    return clamp(mix(vec3(l), c, s), 0.0, 1.0);
}

// The palette at height h at the state's saturation, so muting draws grey.
vec3 tone(float h) { return saturate3(palette(h), uTone.z); }

// A colour at full value: what a stroke of light draws, so a dark stop
// still reads as light. Hue and saturation stay; a grey turns near white.
vec3 lit(vec3 c) { return c * (0.95 / max(max(c.r, max(c.g, c.b)), 0.25)); }
vec3 litTone(float h) { return lit(tone(h)); }
// The spark colour at the state's saturation, never above its own.
vec3 hot() { return saturate3(uHot.rgb, min(uTone.z, 1.0)); }

// Object from view: a turn about y after the fixed tilt about x.
mat3 orbMatrix() {
    float cy = cos(uSwirl), sy = sin(uSwirl);
    float cx = cos(uExtra.y), sx = sin(uExtra.y);
    return mat3(cy, 0.0, -sy, 0.0, 1.0, 0.0, sy, 0.0, cy)
         * mat3(1.0, 0.0, 0.0, 0.0, cx, sx, 0.0, -sx, cx);
}

// The deep ink disc a style stands on, which carries it on a light ground:
// lighter toward the centre, where depth is 1, so it reads round, and
// tinted by the palette and its core. A style covers its disc by its edge
// mask alone, whole inside the edge: a disc drawn part clear lets the
// window show through, and over a half-light window the orb then reads as
// two halves. Only its soft edge, glow and shadow are part cover.
vec3 ink(float depth, vec3 tint) {
    return vec3(0.016, 0.020, 0.046) + tint * 0.06 + uCore.rgb * 0.20 * depth * depth;
}

// Coverage of a stroke of half-width w at distance d, antialiased over px.
float stroke(float d, float w, float px) { return clamp((w - d) / px + 0.5, 0.0, 1.0); }

// A line's hot core and its soft bloom, at distance d from its centre.
float core(float d, float w) { return exp(-(d * d) / (w * w)); }
float bloom(float d, float w) { return exp(-abs(d) / w); }

// Per-channel cover of a thin bright edge: red a little outside, blue a
// little inside, as a lens fringes a bright edge.
vec3 fringe(float d, float w, float px, float k) {
    return vec3(stroke(abs(d - k), w, px), stroke(abs(d), w, px), stroke(abs(d + k), w, px));
}
vec3 fringeCore(float d, float w, float k) {
    return vec3(core(d - k, w), core(d, w), core(d + k, w));
}

// Lays a bright stroke of colour lineC over (col, a): the centre cover fr.g
// composites, and the fringe (fr.r outside, fr.b inside) adds light only,
// so it shows on a dark ground and leaves a light one clean.
void layStroke(inout vec3 col, inout float a, vec3 lineC, vec3 fr) {
    float c = fr.g;
    col = lineC * c + col * (1.0 - c);
    a = c + a * (1.0 - c);
    float L = max(lineC.r, max(lineC.g, lineC.b)) * 0.7;
    col += vec3(max(fr.r - c, 0.0), 0.0, max(fr.b - c, 0.0)) * L;
}

// A colour at intensity i: its hue while dim, its core burning toward
// white past 1, as a hot highlight does.
vec3 burn(vec3 c, float i) { return c * i + vec3(max(i - 0.75, 0.0) * 0.5 * i); }

// A soft highlight of size (a, b) at c, turned by rot: a hot core in a
// soft bloom, q in the body's units.
float glint(vec2 q, vec2 c, float a, float b, float rot) {
    vec2 d = q - c;
    float cs = cos(rot), sn = sin(rot);
    d = vec2(cs * d.x + sn * d.y, -sn * d.x + cs * d.y) / vec2(a, b);
    float e = dot(d, d);
    return exp(-e * 3.0) + 0.25 * exp(-sqrt(e) * 2.2);
}

// Highlights roll off toward white instead of clipping each channel flat.
vec3 shoulder(vec3 c) {
    float m = max(c.r, max(c.g, c.b));
    if (m <= 0.72) return c;
    float k = 0.72 + 0.28 * (1.0 - exp(-(m - 0.72) / 0.28));
    float over = clamp((m - 0.95) / 1.4, 0.0, 1.0);
    return mix(c * (k / m), vec3(k), over * 0.75);
}

// The light round a body of edge radius Re: it rises from FADE of Re,
// leaves at FROM of Re and falls off over FALL of the orb's radius. It
// adds light alone, so it lifts the orb on a dark ground and changes
// nothing on a light one.
float glow(float r, float Re, float from, float fade, float fall) {
    return exp(-max(r - Re * from, 0.0) / (fall * uShape.x)) * smoothstep(Re * fade, Re, r);
}

// The soft shadow under a body of edge radius Re: coverage with no colour,
// which seats the orb on a light ground and is lost on a dark one.
float shadow(vec2 uv, float Re) {
    return (1.0 - smoothstep(Re * 0.9, Re * 1.35, length(uv - vec2(0.0, -0.035 * uShape.x)))) * 0.22;
}

// The finish of a style drawn as light on its disc: its glow outside the
// body, its shadow under it and its highlights rolled off. col is
// premultiplied; a is the drawn cover.
vec4 finish(vec3 col, float a, vec2 uv, float r, float Re, vec3 glowCol, float glowGain) {
    col += glowCol * glow(r, Re, 1.0, 0.82, 0.10) * (1.0 - a) * glowGain;
    return vec4(shoulder(col), a + (1.0 - a) * shadow(uv, Re)) * qt_Opacity;
}
