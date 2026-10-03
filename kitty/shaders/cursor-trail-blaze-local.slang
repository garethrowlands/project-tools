#language slang 2026
// Copyright (C) 2026 Kovid Goyal <kovid at kovidgoyal.net>
// Distributed under terms of the GPLv3 license.
//
// Blaze cursor trail — port of https://gist.github.com/chardskarth/95874c54e29da6b5a36ab7b50ae2d088
// by chardskarth. Draws a fading parallelogram trail from the previous cursor
// position to the current one, coloured with an amber fill and red-orange border.
// Ported to slang for kitty
//
// Local copy of kitty 0.49.1's kitty/shaders/custom/cursor-trail-blaze.slang,
// changed to: animate the trail as a comet travelling from the old cursor
// position to the new one (instead of a whole-path flash fading toward the
// cursor), driven by kitty's trail animation so DURATION is gone and
// cursor_trail_decay sets the speed; skip the trail when focus moves to
// another window; and add
// TRAIL_OPACITY, ACCENT_FROM_CURSOR and MAX_TRAIL_LENGTH. Stock tunable
// constants are unchanged, so pipeline `var` overrides apply.

import kitty_custom_shader_types;

static const float4 TRAIL_COLOR = float4(1.0, 0.725, 0.161, 1.0);
static const float4 TRAIL_COLOR_ACCENT = float4(1.0, 0.0, 0.0, 1.0);
// Local additions (1.0 / false = stock blaze behaviour).
// How strongly the trail covers the pixels underneath, 0..1.
static const float TRAIL_OPACITY = 1.0;
// Use the cursor colour for the edge accent instead of TRAIL_COLOR_ACCENT.
static const bool ACCENT_FROM_CURSOR = false;
// Longest visible trail, in cursor heights (about one line each); the rest of
// the path stays transparent so long jumps leave a short tail, not a bar.
static const float MAX_TRAIL_LENGTH = 1e6;

// SDF of an axis-aligned box.  p = query point, center = box centre, hext = half-extents.
static float
sdBox(float2 p, float2 center, float2 hext) {
    float2 d = abs(p - center) - hext;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
}

// Single edge contribution for the quadrilateral SDF (signed winding accumulation).
static float
seg(float2 p, float2 a, float2 b, inout float s, float d) {
    float2 e = b - a;
    float2 w = p - a;
    float2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    d = min(d, dot(p - proj, p - proj));

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);
    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);
    s *= lerp(1.0, -1.0, step(0.5, allCond + noneCond));
    return d;
}

// SDF of an arbitrary quadrilateral (uses winding number via four edge contributions).
static float
sdQuad(float2 p, float2 v0, float2 v1, float2 v2, float2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);
    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);
    return s * sqrt(d);
}

// Returns 0 for diagonal movement (up-left / down-right), 1 otherwise.
// Selects which corner of the parallelogram aligns with the movement direction.
static float
movementVertexFactor(float2 a, float2 b) {
    float c1 = step(b.x, a.x) * step(a.y, b.y);
    float c2 = step(a.x, b.x) * step(b.y, a.y);
    return 1.0 - max(c1, c2);
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (d.cursor_trail_color.a <= 0.0) return color;

    // No trail when focus moved to another window: the previous cursor
    // position is then outside the active window. (Before the cursor has
    // moved twice prev_edge is all zeros, which also lands outside.)
    float4 win = d.active_window_geometry;
    float2 prevCenterUV = float2(
        (d.cursor_trail_prev_edge.x + d.cursor_trail_prev_edge.y) * 0.5,
        (d.cursor_trail_prev_edge.z + d.cursor_trail_prev_edge.w) * 0.5);
    if (win.z > 0.0 && win.w > 0.0 &&
        (any(prevCenterUV < win.xy) || any(prevCenterUV > win.xy + win.zw))) return color;

    // Work in pixel space for correct aspect-ratio distance measurements.
    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 px = t.pos * pixelDims;

    // Current cursor rect in pixel space (edge: .x=left .y=right .z=top .w=bottom, y-up).
    float curLeft = d.cursor_trail_edge.x * pixelDims.x;
    float curRight = d.cursor_trail_edge.y * pixelDims.x;
    float curTop = d.cursor_trail_edge.z * pixelDims.y;
    float curBottom = d.cursor_trail_edge.w * pixelDims.y;
    float curWidth = curRight - curLeft;
    float curHeight = curTop - curBottom;
    float2 curCenter = float2((curLeft + curRight) * 0.5, (curTop + curBottom) * 0.5);

    float prevLeft = d.cursor_trail_prev_edge.x * pixelDims.x;
    float prevTop = d.cursor_trail_prev_edge.z * pixelDims.y;
    float prevBottom = d.cursor_trail_prev_edge.w * pixelDims.y;
    float2 prevCenter = float2(
        (d.cursor_trail_prev_edge.x + d.cursor_trail_prev_edge.y) * 0.5 * pixelDims.x,
        (d.cursor_trail_prev_edge.z + d.cursor_trail_prev_edge.w) * 0.5 * pixelDims.y);

    float lineLength = length(curCenter - prevCenter);
    float maxLength = MAX_TRAIL_LENGTH * curHeight;
    // Comet: a head travels from the previous cursor to the current one,
    // a slower tail follows (at most maxLength behind) and both meet at
    // the cursor as the trail ends. s is this pixel's distance along the path.
    //
    // Head and tail come from kitty's own trail quad rather than d.timestamp:
    // kitty animates its corners on the CPU every frame (front corners decay
    // fast, back corners slowly, per cursor_trail_decay), whereas timestamp is
    // a float32 of ms since kitty started and gets coarse after a few hours.
    // Projecting the corners onto the path and allowing for the cursor's own
    // extent along it gives the head (front) and tail (back) positions.
    float2 dir = (curCenter - prevCenter) / max(lineLength, 1e-3);
    float s = dot(px - prevCenter, dir);
    float halfExtent = 0.5 * (abs(dir.x) * curWidth + abs(dir.y) * curHeight);
    float4 cornerS = (d.cursor_trail_corners_x * pixelDims.x - prevCenter.x) * dir.x +
                     (d.cursor_trail_corners_y * pixelDims.y - prevCenter.y) * dir.y;
    float head = clamp(max(max(cornerS.x, cornerS.y), max(cornerS.z, cornerS.w)) - halfExtent, 0.0, lineLength);
    float tail = clamp(min(min(cornerS.x, cornerS.y), min(cornerS.z, cornerS.w)) + halfExtent, 0.0, head);
    tail = max(tail, head - maxLength);
    float seg = max(head - tail, 1e-3);
    // 0 at the head, rising to 1 at the tail; 1 outside the segment.
    float alphaModifier = (s > head || s < tail) ? 1.0 : (head - s) / seg;

    // Build parallelogram vertices in pixel space.
    float vf = movementVertexFactor(curCenter, prevCenter);
    float ivf = 1.0 - vf;
    float2 v0 = float2(lerp(curLeft, curRight, vf), curBottom);
    float2 v1 = float2(lerp(curLeft, curRight, ivf), curTop);
    float2 v2 = float2(prevLeft + curWidth * ivf, prevTop);
    float2 v3 = float2(prevLeft + curWidth * vf, prevBottom);

    float sdfCursor = sdBox(px, curCenter, float2(curWidth, curHeight) * 0.5);
    float sdfTrail = sdQuad(px, v0, v1, v2, v3);

    // ~2-pixel anti-aliasing range in pixel space.
    float aaRange = 2.0;
    float4 newColor = color;
    // Inner border accent (red-orange inside the trail edges).
    float4 accent = ACCENT_FROM_CURSOR ? float4(d.cursor_color.rgb, 1.0) : TRAIL_COLOR_ACCENT;
    newColor = lerp(newColor, accent, 1.0 - smoothstep(sdfTrail, -aaRange, aaRange * 0.05));
    // Main amber fill.
    newColor = lerp(newColor, TRAIL_COLOR, 1.0 - smoothstep(0.0, aaRange, sdfTrail));
    // Fade: effect is weakest toward the previous cursor end.
    newColor = lerp(color, newColor, (1.0 - alphaModifier) * TRAIL_OPACITY);
    // Restore original pixels inside the cursor rectangle.
    return lerp(newColor, color, step(sdfCursor, 0.0));
}
