#include <metal_stdlib>
using namespace metal;

// Layouts must match ShaderTypes.swift. Every fragment shader outputs
// premultiplied alpha.

struct SceneUniforms {
    float2 viewportSize;
};

struct FlakeInstance {
    float2 center;
    float radius;
    float opacity;
};

struct PileSegment {
    float2 start;
    float2 end;
    float baseY;
    float opacity;
};

struct WireSegment {
    float2 start;
    float2 end;
    float width;
    float isShadow;   // 1 for the soft shadow drawn beneath the wire
};

struct BulbInstance {
    float2 anchor;
    float angle;
    float size;
    float4 color;   // rgb + brightness
};

/// Converts a point in top-left-origin screen points to clip space.
static float4 clipPosition(float2 point, float2 viewportSize) {
    float2 normalized = point / viewportSize * 2.0 - 1.0;
    return float4(normalized.x, -normalized.y, 0.0, 1.0);
}

/// Paints `color` (straight alpha) over `destination` (premultiplied).
static float4 over(float4 destination, float3 color, float alpha) {
    return float4(color * alpha + destination.rgb * (1.0 - alpha), alpha + destination.a * (1.0 - alpha));
}

// MARK: - Flakes

struct FlakeFragmentInput {
    float4 position [[position]];
    float2 offset;   // distance from the flake centre, in points
    float radius;
    float opacity;
};

/// Expands each flake into a small quad (drawn as a 4-vertex triangle strip).
vertex FlakeFragmentInput flakeVertex(uint vertexID [[vertex_id]],
                                      uint instanceID [[instance_id]],
                                      const device FlakeInstance *flakes [[buffer(0)]],
                                      constant SceneUniforms &uniforms [[buffer(1)]]) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    FlakeInstance flake = flakes[instanceID];

    // One extra point of padding leaves room for the soft edge.
    float2 offset = corners[vertexID] * (flake.radius + 1.0);

    FlakeFragmentInput out;
    out.position = clipPosition(flake.center + offset, uniforms.viewportSize);
    out.offset = offset;
    out.radius = flake.radius;
    out.opacity = flake.opacity;
    return out;
}

/// A bright core that fades into a soft rim.
fragment float4 flakeFragment(FlakeFragmentInput in [[stage_in]]) {
    float distanceFromCenter = length(in.offset);
    float alpha = (1.0 - smoothstep(in.radius * 0.35, in.radius + 0.75, distanceFromCenter)) * in.opacity;
    return float4(alpha);
}

// MARK: - Snow piles

struct PileFragmentInput {
    float4 position [[position]];
    float4 color;   // premultiplied
};

/// Draws a pile segment as a 10-vertex triangle strip, in five rows:
///
///     row 4  feather: fades out 1 pt above the snow (cheap anti-aliasing)
///     row 3  top of the snow (bright white)
///     row 2  bottom of the snow (cool blue-white)
///     row 1  where the snow meets the surface: start of the contact shadow
///     row 0  end of the shadow, a few points below the surface
///
/// Rows 1 and 2 share a y position; the triangles between them have no area.
/// Even vertex IDs are on the left column, odd ones on the right.
vertex PileFragmentInput pileVertex(uint vertexID [[vertex_id]],
                                    uint instanceID [[instance_id]],
                                    const device PileSegment *segments [[buffer(0)]],
                                    constant SceneUniforms &uniforms [[buffer(1)]]) {
    PileSegment segment = segments[instanceID];
    bool isRight = (vertexID & 1) != 0;
    uint row = vertexID >> 1;

    float2 top = isRight ? segment.end : segment.start;
    float height = segment.baseY - top.y;

    const float3 white = float3(1.0);
    const float3 shade = float3(0.80, 0.86, 0.96);
    float shadowStrength = 0.22 * saturate(height / 3.0) * segment.opacity;

    float y;
    float4 color;
    switch (row) {
        case 0:  y = segment.baseY + 3.0; color = float4(0.0); break;
        case 1:  y = segment.baseY;       color = float4(0.0, 0.0, 0.0, shadowStrength); break;
        case 2:  y = segment.baseY;       color = float4(shade * segment.opacity, segment.opacity); break;
        case 3:  y = top.y;               color = float4(white * segment.opacity, segment.opacity); break;
        default: y = top.y - 1.0;         color = float4(0.0); break;
    }

    PileFragmentInput out;
    out.position = clipPosition(float2(top.x, y), uniforms.viewportSize);
    out.color = color;
    return out;
}

fragment float4 pileFragment(PileFragmentInput in [[stage_in]]) {
    return in.color;
}

// MARK: - Light wire

struct WireFragmentInput {
    float4 position [[position]];
    float across;      // signed distance from the wire's centre line, in points
    float halfWidth;
    float isShadow;
};

/// Expands a wire segment into a quad, overlapping its neighbours slightly so
/// the joints don't show gaps. Shadow segments are offset down and softened.
vertex WireFragmentInput wireVertex(uint vertexID [[vertex_id]],
                                    uint instanceID [[instance_id]],
                                    const device WireSegment *segments [[buffer(0)]],
                                    constant SceneUniforms &uniforms [[buffer(1)]]) {
    WireSegment segment = segments[instanceID];
    float2 direction = normalize(segment.end - segment.start + float2(1e-5, 0));
    float2 normal = float2(-direction.y, direction.x);
    float halfWidth = segment.width * 0.5;
    float extent = halfWidth + (segment.isShadow > 0.5 ? 2.0 : 1.0);
    float2 offset = segment.isShadow > 0.5 ? float2(0.5, 1.5) : float2(0.0);

    float2 along = (vertexID & 1) != 0 ? segment.end + direction * halfWidth : segment.start - direction * halfWidth;
    float side = (vertexID >> 1) != 0 ? 1.0 : -1.0;

    WireFragmentInput out;
    out.position = clipPosition(along + offset + normal * side * extent, uniforms.viewportSize);
    out.across = side * extent;
    out.halfWidth = halfWidth;
    out.isShadow = segment.isShadow;
    return out;
}

fragment float4 wireFragment(WireFragmentInput in [[stage_in]]) {
    if (in.isShadow > 0.5) {
        float alpha = (1.0 - smoothstep(in.halfWidth - 0.5, in.halfWidth + 1.8, abs(in.across))) * 0.3;
        return float4(0.0, 0.0, 0.0, alpha);
    }
    float coverage = saturate(in.halfWidth + 0.5 - abs(in.across));
    // A dark green cable, slightly lighter along its upper edge so it reads as round.
    float3 color = mix(float3(0.05, 0.12, 0.06), float3(0.2, 0.32, 0.2), saturate(-in.across / max(in.halfWidth, 0.01)));
    return float4(color * coverage, coverage);
}

// MARK: - Bulbs

struct BulbFragmentInput {
    float4 position [[position]];
    float2 local;    // bulb space: the socket at (0, 0), the glass hanging along +y
    float size;
    float4 color;
};

/// Distance-like value for the glass: below 1 inside. A C9-style bulb, round at
/// the bottom and tapering toward the socket.
static float glassShape(float2 local, float size) {
    float2 fromCenter = local - float2(0.0, size * 1.75);
    float taper = mix(1.0, 0.6, saturate(-fromCenter.y / (size * 1.15)));
    return length(fromCenter / float2(size * 0.58 * taper, size * 1.05));
}

/// Signed distance to the socket, a small rounded box below the wire.
static float socketDistance(float2 local, float size) {
    float2 box = abs(local - float2(0.0, size * 0.42)) - float2(size * 0.3, size * 0.48);
    return length(max(box, 0.0)) + min(max(box.x, box.y), 0.0) - size * 0.08;
}

/// Covers the bulb, its shadow and its glow with one quad, rotated by the swing angle.
vertex BulbFragmentInput bulbVertex(uint vertexID [[vertex_id]],
                                    uint instanceID [[instance_id]],
                                    const device BulbInstance *bulbs [[buffer(0)]],
                                    constant SceneUniforms &uniforms [[buffer(1)]]) {
    BulbInstance bulb = bulbs[instanceID];
    float size = bulb.size;
    float reach = size * 3.2;

    float2 corner = float2(vertexID & 1, vertexID >> 1);
    float2 local = mix(float2(-reach, -size * 0.6), float2(reach, size * 1.75 + reach), corner);

    // Positive angles swing the bulb toward +x.
    float s = sin(bulb.angle);
    float c = cos(bulb.angle);
    float2 rotated = float2(c * local.x + s * local.y, -s * local.x + c * local.y);

    BulbFragmentInput out;
    out.position = clipPosition(bulb.anchor + rotated, uniforms.viewportSize);
    out.local = local;
    out.size = size;
    out.color = bulb.color;
    return out;
}

fragment float4 bulbFragment(BulbFragmentInput in [[stage_in]]) {
    float size = in.size;
    float brightness = in.color.a;
    float3 hue = in.color.rgb;
    float2 p = in.local;
    float edge = 1.0 / (size * 0.58);

    // 1. A tight, soft glow. It reaches exactly zero inside the quad, so no edges show.
    float2 fromCenter = p - float2(0.0, size * 1.75);
    float distanceFromCenter = length(fromCenter);
    float glowSize = size * 1.35;
    float window = 1.0 - smoothstep(size * 2.0, size * 3.0, distanceFromCenter);
    float halo = exp(-distanceFromCenter * distanceFromCenter / (2.0 * glowSize * glowSize)) * brightness * window;
    float4 result = float4(hue * halo * 0.7, halo * 0.2);

    // 2. A soft drop shadow, so the bulb sits on the screen instead of floating.
    float2 shadowPoint = p - float2(0.5, 1.5);
    float glassShadow = 1.0 - smoothstep(0.75, 1.35, glassShape(shadowPoint, size));
    float socketShadow = 1.0 - smoothstep(-0.8, 1.2, socketDistance(shadowPoint, size));
    result = over(result, float3(0.0), max(glassShadow, socketShadow) * 0.28);

    // 3. The glass: coloured when off, glowing from a warm core when lit, with a
    //    slightly darker rim so it stays defined on light backgrounds.
    float radius = glassShape(p, size);
    float glass = 1.0 - smoothstep(1.0 - edge, 1.0 + edge, radius);
    float core = saturate(1.0 - radius);
    float3 base = hue * (0.4 + 0.6 * brightness);
    float3 litCore = mix(hue, float3(1.0), 0.6);
    float3 glassColor = mix(base, litCore, core * core * brightness);
    glassColor *= mix(1.0, 0.72, smoothstep(0.55, 1.0, radius));
    result = over(result, glassColor, glass);

    // 4. A small specular highlight on the glass.
    float2 highlight = (p - float2(-size * 0.2, size * 1.35)) / float2(size * 0.12, size * 0.26);
    float shine = (1.0 - smoothstep(0.6, 1.0, length(highlight))) * glass;
    result = over(result, float3(1.0), shine * 0.55);

    // 5. The socket clipping the bulb to the wire.
    float socketEdge = socketDistance(p, size);
    float socket = 1.0 - smoothstep(-0.5, 0.5, socketEdge);
    float3 socketColor = mix(float3(0.16, 0.3, 0.17), float3(0.06, 0.13, 0.07), saturate(p.y / (size * 0.9)));
    result = over(result, socketColor, socket);

    return result;
}

// MARK: - Shared helpers for the winter extras

struct SnowballInstance {
    float2 center;
    float radius;
    float rotation;
    float squash;
    float opacity;
    float seed;
    float kind;
};

struct SnowmanInstance {
    float2 base;
    float tilt;
    float decorations;
    float4 radii;
    float4 scarf;
    float hat;
    float arms;
    float nose;
    float opacity;
};

struct SparkleInstance {
    float2 center;
    float size;
    float opacity;
    float4 color;
};

struct SpriteInstance {
    float2 center;
    float2 size;
    float2 uvMin;
    float2 uvMax;
    float rotation;
    float opacity;
    float flip;
    float padding;
};

struct FrostInstance {
    float2 corner;
    float2 extent;
    float amount;
    float seed;
    float time;
    float padding;
};

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Coverage of a shape from its signed distance (negative inside), anti-aliased over about a point.
static float coverage(float distance) {
    return 1.0 - smoothstep(-0.6, 0.6, distance);
}

static float segmentDistance(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}

/// Distance to a segment whose thickness tapers from `ra` at `a` to `rb` at `b`.
static float taperedDistance(float2 p, float2 a, float2 b, float ra, float rb) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h) - mix(ra, rb, h);
}

static float boxDistance(float2 p, float2 center, float2 halfSize, float rounding) {
    float2 q = abs(p - center) - halfSize + rounding;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rounding;
}

/// Packed snow lit from the upper left. `p` is relative to the centre, y up.
static float3 snowShade(float2 p, float radius) {
    float d = saturate(length(p) / radius);
    float3 normal = float3(p / radius, sqrt(max(0.0, 1.0 - d * d)));
    float3 light = normalize(float3(-0.45, 0.6, 0.75));
    float diffuse = saturate(dot(normal, light));
    float3 shadow = float3(0.70, 0.78, 0.92);
    float3 color = mix(shadow, float3(1.0), smoothstep(0.0, 0.85, diffuse));
    // A cool rim where the ball curves away.
    color = mix(color, float3(0.80, 0.86, 0.97), smoothstep(0.8, 1.0, d) * 0.5);
    return color;
}

// MARK: - Snowballs and splats

struct SnowballFragmentInput {
    float4 position [[position]];
    float2 local;   // points from the centre, y up
    float radius;
    float rotation;
    float squash;
    float opacity;
    float seed;
    float kind;
};

vertex SnowballFragmentInput snowballVertex(uint vertexID [[vertex_id]],
                                            uint instanceID [[instance_id]],
                                            const device SnowballInstance *balls [[buffer(0)]],
                                            constant SceneUniforms &uniforms [[buffer(1)]]) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    SnowballInstance ball = balls[instanceID];
    float reach = ball.radius * (ball.kind > 0.5 ? 1.7 : 1.35) + 3.0;
    float2 offset = corners[vertexID] * reach;

    SnowballFragmentInput out;
    out.position = clipPosition(ball.center + offset, uniforms.viewportSize);
    out.local = float2(offset.x, -offset.y);
    out.radius = ball.radius;
    out.rotation = ball.rotation;
    out.squash = ball.squash;
    out.opacity = ball.opacity;
    out.seed = ball.seed;
    out.kind = ball.kind;
    return out;
}

fragment float4 snowballFragment(SnowballFragmentInput in [[stage_in]]) {
    float r = in.radius;
    float2 p = in.local;

    if (in.kind > 0.5) {
        // A splat: a lumpy blob spread away from what it hit, with a few droplets.
        float2 normal = float2(cos(in.rotation), sin(in.rotation));
        float angle = atan2(p.y, p.x);
        float lumps = 0.62 + 0.22 * sin(angle * 5.0 + in.seed) + 0.16 * sin(angle * 9.0 + in.seed * 1.7);
        float facing = dot(normalize(p + 1e-4), normal);
        float shape = r * lumps * mix(0.55, 1.0, saturate(facing * 0.5 + 0.5));
        float blob = coverage(length(p) - shape) * step(-0.25 * r, dot(p, normal));
        float drops = 0.0;
        for (int i = 0; i < 5; i++) {
            float a = in.seed + float(i) * 1.37;
            float2 direction = normalize(normal + float2(cos(a * 3.1), sin(a * 2.3)) * 0.9);
            float2 center = direction * r * (1.05 + 0.35 * fract(a * 7.1));
            drops = max(drops, coverage(length(p - center) - r * (0.08 + 0.06 * fract(a * 3.7))));
        }
        float alpha = max(blob, drops) * in.opacity * 0.95;
        float3 color = mix(float3(0.82, 0.88, 0.98), float3(1.0), smoothstep(0.0, r * 0.6, shape - length(p)));
        return float4(color * alpha, alpha);
    }

    // Squashed a little after landing, sitting on its bottom.
    float2 axes = float2(1.0 + in.squash * 0.5, 1.0 - in.squash * 0.5);
    float2 q = (p + float2(0.0, r * in.squash * 0.5)) / axes;
    float d = length(q);

    float4 result = float4(0.0);
    // Soft contact shadow below.
    float2 shadowPoint = (p - float2(0.0, -r * 0.92)) / float2(r * 0.95, r * 0.22);
    float shadow = (1.0 - smoothstep(0.4, 1.0, length(shadowPoint))) * 0.22;
    result = over(result, float3(0.0), shadow * in.opacity);

    // Specks of packed snow that turn as it rolls.
    float s = sin(in.rotation), c = cos(in.rotation);
    float2 turned = float2(c * q.x - s * q.y, s * q.x + c * q.y);
    float specks = smoothstep(0.82, 0.95, valueNoise(turned * (6.0 / max(r, 4.0)) * 2.2 + in.seed));
    float3 color = snowShade(q, r) * (1.0 - specks * 0.08);
    result = over(result, color, coverage(d - r) * in.opacity);
    return result;
}

// MARK: - Snowmen

struct SnowmanFragmentInput {
    float4 position [[position]];
    float2 local;   // points from the base, y up, before leaning
    float decorations;
    float4 radii;
    float4 scarf;
    float hat;
    float arms;
    float nose;
    float opacity;
};

vertex SnowmanFragmentInput snowmanVertex(uint vertexID [[vertex_id]],
                                          uint instanceID [[instance_id]],
                                          const device SnowmanInstance *snowmen [[buffer(0)]],
                                          constant SceneUniforms &uniforms [[buffer(1)]]) {
    SnowmanInstance man = snowmen[instanceID];
    float3 r = man.radii.xyz;
    float biggest = max(r.x, max(r.y, r.z));
    float height = r.x * 1.8 + r.y * 1.6 + r.z * 1.6 + r.z * 2.4 + 6.0;
    float halfWidth = biggest * 2.3 + 6.0;

    float2 corner = float2(vertexID & 1, vertexID >> 1);
    float2 local = mix(float2(-halfWidth, -r.x * 0.5 - 4.0), float2(halfWidth, height), corner);

    // Lean around the base: screen space has y down.
    float2 screen = float2(local.x, -local.y);
    float s = sin(man.tilt), c = cos(man.tilt);
    float2 leaned = float2(screen.x * c - screen.y * s, screen.x * s + screen.y * c);

    SnowmanFragmentInput out;
    out.position = clipPosition(man.base + leaned, uniforms.viewportSize);
    out.local = local;
    out.decorations = man.decorations;
    out.radii = man.radii;
    out.scarf = man.scarf;
    out.hat = man.hat;
    out.arms = man.arms;
    out.nose = man.nose;
    out.opacity = man.opacity;
    return out;
}

fragment float4 snowmanFragment(SnowmanFragmentInput in [[stage_in]]) {
    float2 p = in.local;
    float r0 = in.radii.x, r1 = in.radii.y, r2 = in.radii.z;
    int count = int(in.radii.w + 0.5);
    float deco = in.decorations;

    float2 c0 = float2(0.0, r0 * 0.9);
    float2 c1 = c0 + float2(0.0, r0 * 0.78 + r1 * 0.8);
    float2 c2 = c1 + float2(0.0, r1 * 0.78 + r2 * 0.8);

    float4 result = float4(0.0);

    // Contact shadow.
    float2 shadowPoint = p / float2(r0 * 1.15, r0 * 0.24);
    result = over(result, float3(0.0), (1.0 - smoothstep(0.35, 1.0, length(shadowPoint))) * 0.25);

    // Stick arms, behind the body.
    if (count >= 3 && in.arms > 0.5 && deco > 0.01) {
        float arm = 1e5;
        for (int side = -1; side <= 1; side += 2) {
            float sx = float(side);
            float2 shoulder = c1 + float2(sx * r1 * 0.6, r1 * 0.15);
            float2 hand = c1 + float2(sx * r1 * (1.0 + 0.9 * deco), r1 * (0.15 + 0.75 * deco));
            arm = min(arm, segmentDistance(p, shoulder, hand) - 1.1);
            float2 twigStart = mix(shoulder, hand, 0.72);
            arm = min(arm, segmentDistance(p, twigStart, twigStart + float2(sx * r1 * 0.12, r1 * 0.32) * deco) - 0.8);
            arm = min(arm, segmentDistance(p, hand, hand + float2(sx * r1 * 0.25, -r1 * 0.05) * deco) - 0.7);
        }
        result = over(result, float3(0.33, 0.21, 0.12), coverage(arm));
    }

    // The balls, bottom up.
    result = over(result, snowShade(p - c0, r0), coverage(length(p - c0) - r0));
    if (count >= 2) {
        result = over(result, snowShade(p - c1, r1), coverage(length(p - c1) - r1));
    }
    if (count >= 3) {
        result = over(result, snowShade(p - c2, r2), coverage(length(p - c2) - r2));
    }

    if (count >= 3 && deco > 0.01) {
        const float3 coal = float3(0.07, 0.07, 0.09);
        float pop = smoothstep(0.0, 1.0, deco);

        // Coal buttons.
        for (int i = -1; i <= 1; i++) {
            float2 button = c1 + float2(r1 * 0.05, -float(i) * r1 * 0.42);
            result = over(result, coal, coverage(length(p - button) - r1 * 0.09 * pop));
        }

        // Scarf around the neck, with a tail hanging down.
        if (in.scarf.w > 0.5) {
            float neck = c1.y + r1 * 0.72;
            float band = boxDistance(p, float2(0.0, neck), float2(r2 * 0.98, r2 * 0.2) * float2(1.0, pop), r2 * 0.12);
            float2 tailTop = float2(r2 * 0.45, neck);
            float tail = taperedDistance(p, tailTop, tailTop + float2(r2 * 0.25, -r1 * 0.75 * pop), r2 * 0.2, r2 * 0.17);
            float scarf = min(band, tail);
            float stripes = step(0.5, fract((p.x + p.y) / max(r2 * 0.35, 2.0)));
            float3 color = in.scarf.rgb * mix(0.82, 1.0, stripes);
            color *= mix(0.78, 1.0, saturate((p.y - neck + r2 * 0.2) / (r2 * 0.4)));
            result = over(result, color, coverage(scarf));
        }

        // Face: coal eyes, a carrot nose and a coal smile.
        for (int side = -1; side <= 1; side += 2) {
            float2 eye = c2 + float2(float(side) * r2 * 0.32 + r2 * 0.06, r2 * 0.28);
            result = over(result, coal, coverage(length(p - eye) - r2 * 0.11 * pop));
            result = over(result, float3(1.0), coverage(length(p - eye - float2(-r2 * 0.03, r2 * 0.04)) - r2 * 0.03 * pop) * 0.8);
        }
        if (in.nose > 0.5) {
            float2 noseStart = c2 + float2(r2 * 0.05, r2 * 0.02);
            float carrot = taperedDistance(p, noseStart, noseStart + float2(r2 * 0.95 * pop, -r2 * 0.1), r2 * 0.13, r2 * 0.02);
            float3 orange = mix(float3(0.95, 0.45, 0.08), float3(1.0, 0.62, 0.2), saturate((p.y - noseStart.y) / (r2 * 0.1) + 0.5));
            result = over(result, orange, coverage(carrot));
        }
        for (int i = 0; i < 5; i++) {
            float a = mix(-2.3, -0.84, float(i) / 4.0);
            float2 smileDot = c2 + float2(r2 * 0.06, -r2 * 0.05) + float2(cos(a), sin(a)) * r2 * 0.52;
            result = over(result, coal, coverage(length(p - smileDot) - r2 * 0.06 * pop));
        }

        // Hat.
        int hat = int(in.hat + 0.5);
        if (hat == 1) {
            // A top hat with a red band.
            float brimY = c2.y + r2 * 0.78;
            float brim = boxDistance(p, float2(0.0, brimY), float2(r2 * 1.02, r2 * 0.09), r2 * 0.06);
            float crownHeight = r2 * 1.05 * pop;
            float crown = boxDistance(p, float2(0.0, brimY + crownHeight * 0.5), float2(r2 * 0.66, crownHeight * 0.5), r2 * 0.06);
            float3 felt = mix(float3(0.06, 0.06, 0.08), float3(0.2, 0.2, 0.24), smoothstep(-r2 * 0.6, r2 * 0.3, -p.x));
            result = over(result, felt, coverage(min(brim, crown)));
            float band = boxDistance(p, float2(0.0, brimY + r2 * 0.2), float2(r2 * 0.67, r2 * 0.1 * pop), 0.5);
            result = over(result, float3(0.78, 0.1, 0.12), coverage(band));
        } else if (hat == 2) {
            // A Santa hat flopping to one side, with a fur trim and a pompom.
            float baseY = c2.y + r2 * 0.62;
            float2 tip = float2(r2 * 1.05, baseY + r2 * 1.35 * pop);
            float2 middle = float2(r2 * 0.15, baseY + r2 * 1.05 * pop);
            float cone = min(taperedDistance(p, float2(0.0, baseY), middle, r2 * 0.9, r2 * 0.45),
                             taperedDistance(p, middle, tip, r2 * 0.45, r2 * 0.12));
            cone = max(cone, baseY - p.y);
            float3 red = mix(float3(0.62, 0.05, 0.08), float3(0.9, 0.14, 0.14), smoothstep(-r2, r2 * 0.6, -p.x + p.y - baseY));
            result = over(result, red, coverage(cone));
            float fur = boxDistance(p, float2(0.0, baseY + r2 * 0.05), float2(r2 * 1.0, r2 * 0.2), r2 * 0.18);
            result = over(result, snowShade(p - float2(0.0, baseY + r2 * 0.05), r2 * 1.2), coverage(fur));
            result = over(result, snowShade(p - tip, r2 * 0.25), coverage(length(p - tip) - r2 * 0.25 * pop));
        } else if (hat == 3) {
            // A knitted beanie in the scarf's colour, with a pompom.
            float3 wool = in.scarf.w > 0.5 ? in.scarf.rgb : float3(0.85, 0.15, 0.2);
            float baseY = c2.y + r2 * 0.42;
            float2 domePoint = (p - float2(0.0, baseY)) / float2(r2 * 1.0, r2 * 0.82 * max(pop, 0.01));
            float dome = max(length(domePoint) - 1.0, (baseY - p.y) / r2);
            float ribs = 0.88 + 0.12 * step(0.5, fract(p.x / max(r2 * 0.18, 1.5)));
            result = over(result, wool * ribs * mix(0.8, 1.0, saturate(-p.x / r2 + 0.5)), coverage(dome * r2));
            float cuff = boxDistance(p, float2(0.0, baseY + r2 * 0.08), float2(r2 * 1.02, r2 * 0.17), r2 * 0.1);
            result = over(result, wool * 0.82, coverage(cuff));
            float2 pompom = float2(0.0, baseY + r2 * 0.88 * pop);
            result = over(result, mix(float3(1.0), wool, 0.15), coverage(length(p - pompom) - r2 * 0.24 * pop));
        }
    }

    return result * in.opacity;
}

// MARK: - Sparkles

struct SparkleFragmentInput {
    float4 position [[position]];
    float2 offset;
    float size;
    float opacity;
    float4 color;
};

vertex SparkleFragmentInput sparkleVertex(uint vertexID [[vertex_id]],
                                          uint instanceID [[instance_id]],
                                          const device SparkleInstance *sparkles [[buffer(0)]],
                                          constant SceneUniforms &uniforms [[buffer(1)]]) {
    const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    SparkleInstance sparkle = sparkles[instanceID];
    float2 offset = corners[vertexID] * sparkle.size * 4.0;

    SparkleFragmentInput out;
    out.position = clipPosition(sparkle.center + offset, uniforms.viewportSize);
    out.offset = offset;
    out.size = sparkle.size;
    out.opacity = sparkle.opacity;
    out.color = sparkle.color;
    return out;
}

/// A bright core with a soft halo and a four-pointed glint.
fragment float4 sparkleFragment(SparkleFragmentInput in [[stage_in]]) {
    float2 p = in.offset / in.size;
    float d2 = dot(p, p);
    float core = exp(-d2 * 1.6);
    float halo = exp(-d2 * 0.25) * 0.35;
    float glint = (exp(-abs(p.x) * 1.2) * exp(-p.y * p.y * 9.0) + exp(-abs(p.y) * 1.2) * exp(-p.x * p.x * 9.0)) * 0.6 * in.color.w;
    float window = 1.0 - smoothstep(3.0, 4.0, max(abs(p.x), abs(p.y)));
    float intensity = (core + halo + glint) * window * in.opacity;
    float3 color = mix(in.color.rgb, float3(1.0), core * 0.7);
    return float4(color * intensity, intensity * 0.75);
}

// MARK: - Sprites

struct SpriteFragmentInput {
    float4 position [[position]];
    float2 uv;
    float opacity;
};

vertex SpriteFragmentInput spriteVertex(uint vertexID [[vertex_id]],
                                        uint instanceID [[instance_id]],
                                        const device SpriteInstance *sprites [[buffer(0)]],
                                        constant SceneUniforms &uniforms [[buffer(1)]]) {
    SpriteInstance sprite = sprites[instanceID];
    float2 corner = float2(vertexID & 1, vertexID >> 1);
    float2 offset = (corner - 0.5) * sprite.size;
    float s = sin(sprite.rotation), c = cos(sprite.rotation);
    float2 turned = float2(offset.x * c - offset.y * s, offset.x * s + offset.y * c);

    float u = sprite.flip > 0.5 ? 1.0 - corner.x : corner.x;
    SpriteFragmentInput out;
    out.position = clipPosition(sprite.center + turned, uniforms.viewportSize);
    out.uv = mix(sprite.uvMin, sprite.uvMax, float2(u, corner.y));
    out.opacity = sprite.opacity;
    return out;
}

fragment float4 spriteFragment(SpriteFragmentInput in [[stage_in]],
                               texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler linearSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);
    return atlas.sample(linearSampler, in.uv) * in.opacity;
}

// MARK: - Frost

struct FrostFragmentInput {
    float4 position [[position]];
    float2 uv;       // 0 at the corner, 1 at the far edge of the frost
    float2 point;    // screen points, for noise that doesn't stretch
    float amount;
    float seed;
    float time;
};

vertex FrostFragmentInput frostVertex(uint vertexID [[vertex_id]],
                                      uint instanceID [[instance_id]],
                                      const device FrostInstance *corners [[buffer(0)]],
                                      constant SceneUniforms &uniforms [[buffer(1)]]) {
    FrostInstance frost = corners[instanceID];
    float2 corner = float2(vertexID & 1, vertexID >> 1);
    float2 point = frost.corner + frost.extent * corner;

    FrostFragmentInput out;
    out.position = clipPosition(point, uniforms.viewportSize);
    out.uv = corner;
    out.point = point;
    out.amount = frost.amount;
    out.seed = frost.seed;
    out.time = frost.time;
    return out;
}

/// Distance to the nearest and second-nearest cell centres of a jittered grid.
static float2 voronoi(float2 p) {
    float2 cell = floor(p);
    float2 f = fract(p);
    float first = 8.0, second = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbour = float2(x, y);
            float2 center = neighbour + float2(hash21(cell + neighbour), hash21(cell + neighbour + 17.0)) - f;
            float d = dot(center, center);
            if (d < first) { second = first; first = d; } else if (d < second) { second = d; }
        }
    }
    return float2(sqrt(first), sqrt(second));
}

/// Ice crystals: faceted plates edged with bright lines and fine feathery
/// needles, thickest in the corner and breaking up toward the middle.
fragment float4 frostFragment(FrostFragmentInput in [[stage_in]]) {
    float2 p = in.point + in.seed * 37.0;

    // Where the frost reaches: a ragged edge, so it never looks like a vignette.
    float n = 0.0, amplitude = 0.5;
    float2 q = p * 0.018;
    for (int i = 0; i < 4; i++) {
        n += amplitude * valueNoise(q);
        q = q * 2.1 + float2(1.7, 9.2);
        amplitude *= 0.5;
    }
    float reach = length(in.uv);
    float growth = 1.0 - reach + (n - 0.5) * 0.55;
    float threshold = 1.0 - in.amount;
    float frost = smoothstep(threshold, threshold + 0.22, growth);
    if (frost <= 0.001) { return float4(0.0); }

    // Large crystal plates with bright edges...
    float2 plates = voronoi(p * 0.045);
    float plateEdges = 1.0 - smoothstep(0.0, 0.07, plates.y - plates.x);
    // ...and fine needles of frost.
    float2 fine = voronoi(p * 0.16 + n * 2.0);
    float needles = 1.0 - smoothstep(0.0, 0.12, fine.y - fine.x);
    float grain = valueNoise(p * 0.6);

    float density = frost * frost;
    float alpha = density * 0.10 + frost * (0.22 * plateEdges + 0.16 * needles) + density * grain * 0.06;

    float glints = step(0.997, hash21(floor(in.point * 0.5) + in.seed)) * (0.5 + 0.5 * sin(in.time * 2.0 + hash21(floor(in.point)) * 40.0));
    alpha += glints * frost * 0.9;
    alpha = saturate(alpha);
    float3 color = mix(float3(0.80, 0.89, 1.0), float3(1.0), saturate(plateEdges + needles * 0.5));
    return float4(color * alpha, alpha);
}
