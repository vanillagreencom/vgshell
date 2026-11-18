#version 440

// qs.Ui's GlassSurface in one analytic pass: no image read and no loop. A
// rounded box's signed distance gives each pixel its depth inside the
// edge. The pass draws what a layer surface can without reading its
// backdrop, which the compositor blurs under the body:
// - the body's tint, whole to the edge, so an ink's ground is the tint;
// - the rim, one thin line at the edge with no bevel, lit along the
//   light's diagonal from the upper left: brightest on the wall facing it,
//   weaker on the wall it leaves by, and the `ambient` share elsewhere;
// - the edge light, two point lights that orbit outside the surface: the
//   rim catches each where its normal faces it, and a faint glow reaches a
//   few pixels into the body. Only the lights move.
// The rim and the edge light take one colour, the neutral light blended
// to the accent by `uLit`.
//
// Output is valid premultiplied colour, rgb never above alpha: light is
// its colour at an alpha, since a compositor may un-premultiply a surface.
//
// The default Qt Quick vertex shader shares this uniform buffer, so
// qt_Matrix and qt_Opacity stay first.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;     // the surface, in pixels
    float uRadius;  // its corner
    float uMargin;  // the item's reach past the surface on every side, for the edge's antialiasing
    float uRim;     // the rim's width
    vec4 uTint;     // the body's fill, premultiplied, as Qt hands a colour
    vec4 uRimLight; // the glint, the ambient share, the far wall's share, the glow's share
    vec2 uLightA;   // the edge lights, in pixels from the surface's centre
    vec2 uLightB;
    vec4 uEdge;     // the two lights' strengths, their reach in pixels, and 1 while they show
    vec4 uNeutral;  // the light at rest, straight alpha
    vec4 uAccent;   // the light while lit, straight alpha
    float uLit;     // 0 at rest, 1 lit
};

// Toward the light, y down: the upper left.
const vec2 LIGHT = vec2(-0.451219, -0.892413);

float shine(vec2 p, vec2 n, vec2 light, float power) {
    vec2 v = light - p;
    float d = length(v);
    float facing = max(dot(n, v / max(d, 0.001)), 0.0);
    return power * pow(facing, 3.0) * exp(-(d * d) / max(uEdge.z * uEdge.z, 0.0001));
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * (uSize + 2.0 * uMargin);
    vec2 halfSize = uSize * 0.5;
    float radius = min(uRadius, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - (halfSize - radius);
    float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    vec2 corner = max(q, 0.0);
    vec2 outward = corner.x > 0.0 || corner.y > 0.0 ? normalize(corner) * sign(p)
                 : q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
    float cover = clamp(0.5 - sdf, 0.0, 1.0);
    float depth = max(-sdf, 0.0);

    float lit = dot(outward, LIGHT);
    float toward = max(lit, 0.0);
    float away = max(-lit, 0.0);
    // 1 on the two walls of the light's diagonal, 0 on the walls beside.
    float diagonal = min(toward * toward + uRimLight.z * away * away, 1.0);
    float rim = 1.0 - smoothstep(uRim - 0.5, uRim + 0.5, depth);
    float light = uRimLight.x * (uRimLight.y + (1.0 - uRimLight.y) * diagonal) * rim;

    // The edge lights reach only a band at the edge; the body skips them.
    if (uEdge.w > 0.0 && depth < 14.0) {
        float lights = shine(p, outward, uLightA, uEdge.x) + shine(p, outward, uLightB, uEdge.y);
        light += lights * (rim + uRimLight.w * exp(-depth / 5.0));
    }

    vec4 shade = mix(uNeutral, uAccent, uLit);
    float strength = clamp(light, 0.0, 1.0) * shade.a;
    vec4 body = uTint;
    vec4 colour = vec4(body.rgb * (1.0 - strength) + shade.rgb * strength, body.a + (1.0 - body.a) * strength);
    fragColor = colour * cover * qt_Opacity;
}
