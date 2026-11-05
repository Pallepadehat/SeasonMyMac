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
