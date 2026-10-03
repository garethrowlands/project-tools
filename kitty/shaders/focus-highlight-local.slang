#language slang 2026
// Copyright (C) 2026 Kovid Goyal <kovid at kovidgoyal.net>
// Distributed under terms of the GPLv3 license.
//
// Focus highlight effect
// Briefly illuminates the active window whenever it gains focus, then fades out.
// Uses d.active_window_geometry to locate the window bounds in UV space.
// animation_progress (0 → 1) drives the fade over the pipeline duration.
//
// Local copy of kitty 0.49.1's kitty/shaders/custom/focus-highlight.slang,
// adding a glow band (GLOW_*) that adds light at the active window's edges, so
// it shows on dark backgrounds too; the stock BORDER_* glow only multiplies
// existing pixels. With GLOW_STRENGTH = 0 it behaves exactly like the stock shader.

import kitty_custom_shader_types;

// Brightness multiplier boost applied to content inside the active window.
// 0.0 = no boost, 0.15 = 15% brighter.
static const float HIGHLIGHT_INTENSITY = 0.30;
// Width of the inner border glow in UV units.
static const float BORDER_WIDTH = 0.04;
// Peak additive brightness multiplier at the window border edge.
static const float BORDER_GLOW = 0.55;
// Fraction of the original color retained outside the active window (1.0 = unchanged, 0.0 = blend target).
static const float INACTIVE_DIM = 0.3;
// Blend target in linear RGB; black preserves the original dimming behavior.
static const float3 INACTIVE_DIM_COLOR = float3(0.0);
// Keep the tab bar outside the effect when requested by a pipeline.
static const bool DIM_CENTRAL_AREA_ONLY = false;
// Include the active window's title bar and padding in its unchanged/highlighted area.
static const bool INCLUDE_WINDOW_PADDING = false;
// Local additions. Peak light added at the window edge (0 = off), its colour
// in linear RGB, and how far in from the edge it fades out, in pixels.
static const float GLOW_STRENGTH = 0.0;
static const float3 GLOW_COLOR = float3(1.0);
static const float GLOW_WIDTH_PX = 8.0;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (DIM_CENTRAL_AREA_ONLY) {
        float4 area = d.central_area;
        if (any(t.pos < area.xy) || any(t.pos > area.xy + area.zw)) return color;
    }
    float4 g = d.active_window_geometry;
    // Pass through unchanged if no active window geometry is known.
    if (g.z <= 0.0 || g.w <= 0.0) return color;
    if (INCLUDE_WINDOW_PADDING) {
        g.xy -= d.active_window_padding.xy;
        g.zw += d.active_window_padding.xy + d.active_window_padding.zw;
    }

    float2 uv = t.pos;
    float2 winMin = g.xy;
    float2 winMax = g.xy + g.zw;

    // Effect strength decays from 1 at animation start to 0 at the end.
    float strength = 1.0 - t.animation_progress;

    bool inWindow = all(uv >= winMin) && all(uv <= winMax);

    if (inWindow) {
        if (HIGHLIGHT_INTENSITY == 0 && BORDER_WIDTH == 0 && GLOW_STRENGTH == 0) return color;
        // Minimum distance from this pixel to any edge of the active window.
        float2 edgeDists = min(uv - winMin, winMax - uv);
        float nearestEdge = min(edgeDists.x, edgeDists.y);

        // Additive border glow: strongest at the edge, falls off over BORDER_WIDTH.
        float borderGlow = smoothstep(BORDER_WIDTH, 0.0, nearestEdge) * BORDER_GLOW;

        float boost = (HIGHLIGHT_INTENSITY + borderGlow) * strength;

        // Additive glow band, measured in pixels so it is equally wide on all four edges.
        float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
        float2 edgePx = edgeDists * pixelDims;
        float glow = smoothstep(GLOW_WIDTH_PX, 0.0, min(edgePx.x, edgePx.y)) * GLOW_STRENGTH * strength;

        return float4(color.rgb * (1.0 + boost) + GLOW_COLOR * glow, color.a);
    }
    // Slightly dim inactive areas to draw the eye to the focused window.
    float dim = lerp(1.0, INACTIVE_DIM, strength);
    return float4(lerp(INACTIVE_DIM_COLOR, color.rgb, dim), color.a);
}
