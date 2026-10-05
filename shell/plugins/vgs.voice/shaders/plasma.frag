#version 440

// Voxtype voice-chat bubble OSD.
//  - OUTER: thin transparent glass membrane -- soft electric-blue refraction
//    lobes around the rim, a violet Fresnel edge, and a glassy highlight.
//  - INNER: a turbulent ball of luminous plasma filaments. A short volumetric
//    raymarch through flow-warped ridged noise gives dense, fine, sweeping
//    field-line wisps (hollow-ish core, white-hot crests, magenta/violet up top,
//    gold below). This is a noise/curl-flow field, NOT a few analytic loops.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uAmp;
    float uEnergy;
    float uSwirl;  // accumulated clockwise swirl phase (advances faster with voice)
    vec4  uColA;   // electric blue  (membrane / caustics)
    vec4  uColB;   // magenta / pink (plasma low)
    vec4  uColC;   // orange         (plasma mid)
    vec4  uColD;   // white-yellow   (plasma hot)
};

const float TAU = 6.2831853;
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }

// ---- value noise / fbm (iq) ----
float hash13(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 x) {
    vec3 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash13(i + vec3(0,0,0)), hash13(i + vec3(1,0,0)), f.x),
                   mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
                   mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
    float f = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        f += a * vnoise(p);
        p.xy = rot(0.5) * p.xy; p.yz = rot(0.7) * p.yz;
        p *= 2.02; a *= 0.5;
    }
    return f;
}
float fbm2(vec3 p) {   // cheap 2-octave field used to warp the domain
    float f = 0.65 * vnoise(p);
    p.xy = rot(0.6) * p.xy; p *= 2.1;
    f += 0.35 * vnoise(p);
    return f;
}

// plasma emission colour: magenta -> coral -> orange -> white-hot, with a violet
// bias toward the top and a gold bias toward the bottom (matching the reference).
vec3 plasmaCol(float fil, float up) {
    vec3 c = uColB.rgb;                                            // magenta/pink edge
    c = mix(c, mix(uColB.rgb, uColC.rgb, 0.5), smoothstep(0.12, 0.40, fil)); // pink-coral (less pure orange)
    c = mix(c, uColC.rgb, smoothstep(0.45, 0.68, fil));           // orange band (kept narrow)
    c = mix(c, uColD.rgb, smoothstep(0.72, 0.92, fil));           // white-hot cores (smaller, less blown out)
    vec3 crown = mix(uColB.rgb, vec3(0.66, 0.40, 0.95), 0.5);      // orchid/violet
    c = mix(c, crown, smoothstep(0.72, 1.0, up) * 0.5 * (1.0 - smoothstep(0.85, 1.0, fil)));
    return c;
}

void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    uv.y = -uv.y;
    uv *= 1.36;   // canvas enlarged ~1.36x; scale coords back so the orb keeps its size,
                  // leaving a wide transparent margin for the backdrop to fade into naturally
    float amp = clamp(uAmp, 0.0, 1.0);
    float vamp = smoothstep(0.02, 0.5, amp);   // expand typical speech range -> stronger, more visible response
    float t = uTime;
    float r = length(uv);
    float ang = atan(uv.y, uv.x);

    // ---- membrane geometry: breathe + elastic wobble ----
    float Rb = 0.80 + 0.016 * sin(t * 0.5) + 0.009 * sin(t * 0.8 + 1.0);
    float wob = 0.011 * sin(ang * 2.0 - t * 0.55) + 0.007 * sin(ang * 3.0 + t * 0.9);
    float Reff = Rb + wob;
    float rn = min(r / Reff, 1.0);
    float nz = sqrt(max(0.0, 1.0 - rn * rn));
    float inside = smoothstep(Reff + 0.012, Reff - 0.012, r);
    vec2 uvc = uv * (1.0 - 0.06 * rn * rn);             // gentle lens refraction

    // ---- inner plasma: raymarch a flow-warped ridged-noise field. Brightness is a
    //  maximum-intensity projection so the brightest vein at each pixel stays a SHARP
    //  thin line (plain summation smears veins into smoke); a small integrated glow
    //  fills around them, drives the alpha, and lights pink-white pile-up hotspots. ----
    float Rp = 0.58;                                    // raymarch extent (well beyond the visible nucleus
                                                        // so its soft edge is never hard-clipped)
    float mx = 0.0;                                     // sharpest/brightest single vein
    float glow = 0.0;                                   // integrated soft glow / alpha
    float rr = dot(uvc, uvc);
    float up = clamp(0.5 + uvc.y * 1.05, 0.0, 1.0);     // screen-space height for the crown
    if (rr < Rp * Rp) {
        float zext = sqrt(Rp * Rp - rr);
        const int STEPS = 34;
        float dz = 2.0 * zext / float(STEPS);
        for (int k = 0; k < STEPS; k++) {
            float z = -zext + dz * (float(k) + 0.5);
            vec3 P = vec3(uvc, z);
            P.xz = rot(0.22 * sin(t * 0.13)) * P.xz;        // gentle tilt wobble (loop stays ~face-on)
            P.xy = rot(0.12 * sin(t * 0.10)) * P.xy;        // gentle wobble
            // gentle differential swirl: a touch faster toward the centre so filaments shear/curl
            // (fluid, not a rigid spin) -- kept subtle so it never becomes a hypnotic spiral.
            // Split so it can NEVER wind into concentric rings however large uSwirl grows:
            //   - a RIGID whole-field rotation (same angle at every radius -> just spins the
            //     pattern; uniform rotation adds no relative winding);
            //   - a BOUNDED differential shear (oscillates within a fixed band via sin) so the
            //     centre still curls faster than the rim without accumulating turns.
            // (Previously uSwirl multiplied the radius-dependent factor directly, so the
            //  centre-vs-rim winding grew without limit and eventually became tight rings.)
            float r2 = length(P.xy);
            float diff  = 0.18 / (r2 * 2.5 + 0.6);          // stronger toward the centre
            float shear = 0.9 * sin(uSwirl * 0.5) * diff;   // bounded: |shear| <= 0.9*diff
            P.xy = rot(-(uSwirl * 0.45 + shear)) * P.xy;
            float rad = length(P) / Rp;

            // circulate primarily around the VIEW axis (Z) so cords wrap into a visible
            // in-plane LOOP/ring (not an upright flame); 2nd tilted axis adds 3D weave
            vec3 swirl  = cross(normalize(vec3(0.18, 0.28, 1.0)), P);
            vec3 swirl2 = cross(normalize(vec3(1.0, 0.35, 0.0)), P);  // 2nd axis -> woven
            // flowing domain warp adds organic, reconnecting detail on top
            float ft = t + uSwirl * 0.3;                    // turbulent flow churns a bit faster with voice
            vec3 flow = vec3(fbm2(P * 1.3 + vec3(0.0, ft * 0.16, 0.0)),
                             fbm2(P * 1.3 + vec3(3.1, 1.3, -ft * 0.12)),
                             fbm2(P * 1.3 + vec3(-2.7, ft * 0.10, 5.2)));
            // the torus makes the loop now, so the swirl only needs to nudge cords around it;
            // keep it modest + more turbulent flow so cords stay organic (no contour banding)
            float n = fbm(P * 1.55 + 1.9 * swirl + 0.3 * swirl2 + 0.55 * flow);
            float dd = abs(2.0 * n - 1.0);              // 0 exactly on a field line
            float th = fbm2(P * 1.2 + 1.2 * swirl + vec3(2.0, t * 0.08, -1.0));
            float eps = mix(0.035, 0.12, th * th);      // thick cords, strong width variation
            float fil = pow(eps / (dd + eps), 1.9);     // white-hot cord
            fil *= (0.6 + 0.75 * th);                   // thick cords glow brighter
            fil += 0.16 * pow(0.14 / (dd + 0.14), 1.2); // modest bloom (less interior haze)

            // filled tangled core with an UNEVEN organic edge (noise-perturbed, not a clean
            // circular mask) + a brighter loop ring; cords crisscross the centre too.
            float lp = length(P);
            float edgeN = fbm2(P * 2.2 + vec3(1.0, t * 0.08, 3.0));         // ragged edge noise
            float core = smoothstep(0.48, 0.16, lp + 0.20 * (edgeN - 0.5)); // soft, ragged edge (no hard circle)
            float ringEmph = smoothstep(0.10, 0.30, lp) * smoothstep(0.48, 0.28, lp); // brighter loop ring
            float shell = core * (0.82 + 0.4 * ringEmph)
                        * (0.86 + 0.16 * cos(ang - 3.9 - 0.3 * sin(t * 0.1)));
            float depthw = 0.55 + 0.45 * smoothstep(-zext, zext, z); // front a bit brighter
            float v = fil * shell * depthw;
            mx   = max(mx, v);                          // MIP -> sharp line
            glow += v;                                  // soft glow / alpha
        }
        float pulse = 1.0 + 1.1 * vamp + 0.35 * uEnergy;   // brightness pulses clearly with the voice
        mx   *= pulse;
        glow *= dz * 4.5 * pulse;
    }
    // (no central hole — the hot tangle lives in the centre)
    // colour ramps by the SHARP line intensity; soft glow fills around it
    vec3 emis = plasmaCol(mx, up) * (mx * 2.0 + glow * 0.26);
    // orchid crown through the top third
    emis += mix(uColB.rgb, vec3(0.6, 0.4, 0.95), 0.5) * (mx * 0.5 + glow * 0.4)
            * smoothstep(0.6, 1.0, up) * 0.22;
    // voice response: cords flare white-hot as you speak (clear, lively colour lift)
    emis += uColD.rgb * smoothstep(0.45, 1.2, mx) * vamp * 0.6;
    // voice particles: embers from the plasma, drifting out and swirling, brighter as you speak.
    // ~40% are BLUE and float OUT past the membrane; the rest are warm and stay inside.
    float emit = smoothstep(0.04, 0.42, amp);                        // appears readily once you speak
    float pclock = t + uSwirl * 0.6;                                 // particles cycle/emit faster while speaking
    float partA = 0.0;
    for (int i = 0; i < 16; i++) {
        float fi = float(i);
        float s1 = hash13(vec3(fi, 1.3, 2.7));
        float s2 = hash13(vec3(fi, 4.1, 0.9));
        float s3 = hash13(vec3(fi, 7.7, 5.2));
        float blue = step(0.6, s3);                                  // ~40% blue
        float maxR = mix(0.52, 0.95, blue);                         // blue ones float past the membrane
        float life = fract(pclock * (0.30 + 0.25 * s1) + s2);
        float ea   = s3 * 6.2831853 - uSwirl + life * (0.7 + 0.5 * s1); // swirl as it drifts
        float erad = 0.18 + life * (maxR - 0.18);                    // drift outward
        vec2  pp   = vec2(cos(ea), sin(ea)) * erad;
        float pd   = length(uv - pp);
        float psz  = 0.0035 + 0.002 * s1;                            // small
        float pf   = sin(life * 3.14159);                            // fade in, then out
        float spark = exp(-pd * pd / (2.0 * psz * psz))              // sharp core
                    + 0.12 * exp(-pd * pd / (2.0 * (psz * 1.7) * (psz * 1.7))); // tiny glow only
        float pv   = spark * pf * emit;
        vec3 pcol  = (blue > 0.5) ? mix(uColA.rgb, vec3(0.55, 0.78, 1.0), 0.55)  // blue spark
                                  : mix(uColC.rgb, uColD.rgb, s2);               // warm ember
        emis += pcol * pv * 1.8;
        partA += pv;
    }
    // (no separate hotspot blob -- cord cores already ramp to white-yellow in plasmaCol)
    float dens = mx * 1.2 + glow * 0.5;                 // brightness measure for alpha

    // ---- outer translucent GLASS ORB: a real sphere with light bending around it.
    //  A soft Fresnel rim (brighter/translucent at grazing angles) that wobbles organically,
    //  plus bright glassy highlight spots sliding around it -> "spots of pure translucency".
    //  The interior stays clear, preserving the empty gap to the nucleus. NOT a flat halo. ----
    float Rorb = 0.60 + 0.015 * sin(t * 0.25) + 0.011 * sin(ang * 3.0 - t * 0.35)
                      + 0.006 * sin(ang * 5.0 + t * 0.22);        // gently organic, close to a circle
    float rnO = r / Rorb;
    float nzO = sqrt(max(0.0, 1.0 - min(rnO * rnO, 1.0)));        // sphere normal.z
    float inO = smoothstep(Rorb + 0.06, Rorb - 0.06, r);         // soft membrane presence
    float fres = pow(1.0 - nzO, 2.6) * inO;                      // light bends at the rim (soft, no hard line)
    float rimMove = 0.38 + 0.62 * pow(0.5 + 0.5 * sin(ang * 2.0 - t * 0.4), 1.6); // translucent spots sliding round
    float rim = fres * rimMove;
    // proper specular reflections on the glass sphere: Blinn-Phong from several light
    // directions at different angles -> bright spots that sit ON the surface and shimmer as
    // the lights drift, instead of bands crawling around the rim. Strictly contained (x inO).
    // restored clean glass orb (blue-violet rim)
    vec3 orbCol = mix(uColA.rgb, vec3(0.38, 0.72, 1.0), 0.45); // less purple, a bit toward cyan-blue
    vec3 caustic = orbCol * rim * 0.74;                    // blue orb ~20% brighter/more present
    // Fresnel-weighted reflected ENVIRONMENT: a soft studio (sky + a couple of window panes)
    // mirrored in the curved glass. Modulated by Fresnel so the reflection concentrates toward
    // the grazing rim and fades to nothing face-on -- it sits ON the glass surface like a real
    // reflection instead of paint floating over the orb. The panes appear as curved highlights
    // that bend with the surface (light across glass / a monitor) and drift slowly.
    vec3 N = vec3(uv / Rorb, nzO);                                     // sphere surface normal
    vec3 R = reflect(vec3(0.0, 0.0, -1.0), N);                         // reflected view ray
    // inset the reflection into a band INSIDE the membrane (not hugging the edge)
    float reflZone = exp(-pow((rnO - 0.56) / 0.125, 2.0)) * inO;      // tighter band (sharper)
    float sky  = smoothstep(-0.2, 1.0, R.y);                          // bright sky reflected up high
    float win1 = exp(-pow((R.y - (0.62 + 0.06 * sin(t * 0.10))) / 0.07, 2.0)); // crisp window pane -> sharp curved highlight
    float win2 = exp(-pow((R.x - (-0.50 + 0.07 * cos(t * 0.08))) / 0.06, 2.0)); // crisp crossing pane
    float env  = 0.22 * sky + 0.95 * win1 + 0.7 * win2;
    float refl = env * reflZone;                                       // inset on-surface reflection
    vec3 reflCol = mix(vec3(0.78, 0.62, 1.0), vec3(1.0, 0.55, 0.92), smoothstep(0.2, 0.85, refl)); // lavender -> neon pink
    vec3 glassHi = reflCol * refl * 0.30;                             // +20% opacity

    // ---- compose: fire + glass orb + Fresnel-weighted surface reflections ----
    vec3 outc = emis + caustic + glassHi;
    outc = vec3(1.0) - exp(-outc * 1.4);
    outc = clamp(mix(vec3(dot(outc, vec3(0.299, 0.587, 0.114))), outc, 1.35 + 0.35 * amp), 0.0, 1.0); // chroma, livelier with voice

    // ---- alpha: nucleus + glass rim + translucent refractions; interior clear (empty gap) ----
    float a = clamp(dens * 0.7, 0.0, 1.0);
    a = max(a, clamp(rim * 0.6, 0.0, 1.0));                 // soft glass rim (~20% more opaque)
    a = max(a, clamp(refl * 0.18, 0.0, 1.0));              // inset neon-pink reflections (+20%)
    a = max(a, clamp(partA * 1.4, 0.0, 1.0));             // ember particles (incl. ones outside the membrane)
    // dark scrim so the orb reads on any desktop: nearly-solid black CONCENTRATED behind the orb
    // itself, then a long gradual fade out to transparent that finishes inside the canvas.
    // solid behind the orb, then a gaussian falloff with a soft tail (no harsh edge ring)
    float backdrop = exp(-pow(max(0.0, r - 0.53) / 0.15, 2.0)) * 0.9;   // ~15% smaller footprint
    a = max(a, backdrop);

    fragColor = vec4(outc, clamp(a, 0.0, 1.0)) * qt_Opacity;
}
