#version 440

// The lens form of qs.Ui's GlassSurface in one analytic pass: no texture
// and no loop. A rounded box's signed distance gives each pixel its depth
// inside the rim. The pass draws what a lens shows without reading the
// backdrop, which a layer surface cannot:
// - the body's tint, whole from the bezel's inner end inward, so the
//   compositor's blur always lies under it;
// - the bezel band, where the tint steps down under the layer rule's blur
//   threshold within one pixel, so the band shows the backdrop sharp, with
//   a faint line drawn on the step;
// - the glint, a bright line on the rim along the light's diagonal: the
//   wall facing the light and, weaker, the wall the light leaves by, with
//   the walls beside them dark, and a glow inside those two walls;
// - a dark line just outside the rim, which parts a light plate from a
//   light ground. The item is `uMargin` larger than the plate for it.
// The compositor draws the blur under the body. Nothing is drawn inside
// the bezel's inner end but the tint, so an ink's ground is the tint alone.
//
// Output is valid premultiplied colour, rgb never above alpha: light is
// white at an alpha and shade is black at an alpha, since a compositor may
// un-premultiply a surface.
//
// The default Qt Quick vertex shader shares this uniform buffer, so
// qt_Matrix and qt_Opacity stay first.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uSize;    // the plate, in pixels
    float uRadius; // its corner
    float uMargin; // the item's reach past the plate on every side
    vec4 uTint;    // the body's fill, premultiplied, as Qt hands a colour
    vec4 uLens;    // the band's width, 1 or more; the share of the tint it loses; glint; glow
    vec4 uLight;   // the far wall's share of the light, the outer line, the step's line
};

// Toward the light, y down: the upper left.
const vec2 LIGHT = vec2(-0.451219, -0.892413);

float smoother(float a, float b, float x) {
    float t = clamp((x - a) / max(b - a, 0.0001), 0.0, 1.0);
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
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
    float lit = dot(outward, LIGHT);
    float toward = max(lit, 0.0);
    float away = max(-lit, 0.0);
    // 1 on the two walls of the light's diagonal, 0 on the walls beside.
    float diagonal = min(toward * toward + uLight.x * away * away, 1.0);

    // Outside the plate: the dark line alone, strongest off the diagonal.
    float cover = clamp(0.5 - sdf, 0.0, 1.0);
    float outer = uLight.y * (1.0 - smoothstep(0.0, 1.5, sdf)) * (1.0 - 0.6 * diagonal) * (1.0 - cover);

    float depth = max(-sdf, 0.0);
    float bezel = uLens.x;
    // The tint: thin across the band, whole from the bezel's inner end.
    float body = smoothstep(bezel - 0.5, bezel + 0.5, depth);
    float alpha = uTint.a * (1.0 - uLens.y * (1.0 - body));
    vec3 colour = uTint.rgb / max(uTint.a, 0.0001) * alpha;

    // Light: the glint on the rim, the glow inside the lit walls, falling
    // off across the band, and the line on the step.
    float fall = 1.0 - smoother(0.0, 1.0, depth / bezel);
    float glint = 1.0 - smoothstep(0.0, 1.2, depth);
    float step_ = 1.0 - smoothstep(0.0, 1.0, abs(depth - bezel));
    float light = uLens.z * glint * (0.06 + 0.94 * diagonal)
                + uLens.w * fall * fall * diagonal * (1.0 - body)
                + uLight.z * step_ * (0.35 + 0.65 * diagonal);
    light = clamp(light, 0.0, 1.0);
    colour = colour * (1.0 - light) + vec3(light);
    alpha += (1.0 - alpha) * light;

    fragColor = (vec4(colour, alpha) * cover + vec4(0.0, 0.0, 0.0, outer)) * qt_Opacity;
}
