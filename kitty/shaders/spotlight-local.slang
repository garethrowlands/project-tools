#language slang 2026
// Copyright (C) 2026 Kovid Goyal <kovid at kovidgoyal.net>
// Distributed under terms of the GPLv3 license.
//
// Spotlight effect
// Original GLSL by Paul Robello, ported to Slang for kitty
//
// Local copy of kitty 0.49.1's kitty/shaders/custom/spotlight.slang, adding a
// faint additive glow inside the spot (GLOW_*). The stock shader only dims
// pixels outside the spot, so over an empty dark background the spot shows
// nothing; the glow adds light, so it shows there too. With GLOW_STRENGTH = 0
// it behaves exactly like the stock shader.

import kitty_custom_shader_types;

static const float SPOTLIGHT_RADIUS = 0.25;   // spotlight radius in UV units
static const float SPOTLIGHT_SOFTNESS = 20.0; // edge sharpness; higher = sharper
static const float AMBIENT_LIGHT = 0.5;       // minimum brightness outside the spotlight
static const float SPOTLIGHT_SPEED = 1.0;     // oscillation speed in random-motion mode
// Set to 1 to follow the mouse, 0 to use random oscillation
static const int USE_MOUSE = 1;
// When USE_MOUSE=1 and the mouse leaves the window:
//   0 = fall back to random oscillation
//   1 = clamp spotlight to the nearest window edge
//   2 = disable spotlight (pass through unchanged pixels)
static const int MOUSE_LEAVE_BEHAVIOR = 2;
// Set to 1 to pass through unchanged pixels when the mouse pointer is hidden
static const int HIDE_WHEN_POINTER_HIDDEN = 1;
// Local additions. Light added at the spot's centre (0 = off) and its colour in
// linear RGB. It fades to 0 at the spot's edge, within the same soft edge.
static const float GLOW_STRENGTH = 0.0;
static const float3 GLOW_COLOR = float3(1.0);

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    if (HIDE_WHEN_POINTER_HIDDEN == 1 && d.mouse_pointer_hidden != 0.0) return color;
    float2 uv = t.pos;

    // Viewport pixel dimensions for aspect-ratio correction
    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float aspectRatio = pixelDims.x / pixelDims.y;

    // Random oscillating center (different frequencies and phases on each axis)
    float time = d.timestamp * SPOTLIGHT_SPEED;
    float2 randomCenter = float2(0.5 + 0.4 * sin(time), 0.5 + 0.4 * sin(time * 1.3 + 3.14159));

    // Mouse is valid only when both coords are inside the OS window [0, 1]
    float2 mp = d.mouse_pos.xy;
    float mouseInWindow = float(all(mp >= float2(0.0)) && all(mp <= float2(1.0)));

    // Disable spotlight entirely when mouse leaves the window
    if (USE_MOUSE == 1 && MOUSE_LEAVE_BEHAVIOR == 2 && mouseInWindow == 0.0) return color;

    // When mouse leaves the window: clamp to nearest edge or fall back to random
    float2 outsideFallback = lerp(randomCenter, clamp(mp, float2(0.0), float2(1.0)), float(MOUSE_LEAVE_BEHAVIOR == 1 ? 1 : 0));

    // Branchless center selection
    float2 mouseCenter = lerp(outsideFallback, mp, mouseInWindow);
    float2 spotlightCenter = lerp(randomCenter, mouseCenter, float(USE_MOUSE));

    // Euclidean distance in aspect-ratio-corrected space (produces a circular spotlight)
    float distToCenter = length((uv - spotlightCenter) * float2(aspectRatio, 1.0));

    // Soft spotlight edge
    float spotlightIntensity = smoothstep(SPOTLIGHT_RADIUS, SPOTLIGHT_RADIUS - (1.0 / SPOTLIGHT_SOFTNESS), distToCenter);

    // Blend between ambient and full illumination
    float3 result = color.rgb * lerp(float3(AMBIENT_LIGHT), float3(1.0), spotlightIntensity);

    // Local addition: additive glow, peaking at the centre and fading to 0 at
    // the spot edge (shaped by the spot's own soft edge, too)
    float glowFalloff = spotlightIntensity * smoothstep(SPOTLIGHT_RADIUS, 0.0, distToCenter);
    result += GLOW_COLOR * (GLOW_STRENGTH * glowFalloff);

    return float4(result, color.a);
}
