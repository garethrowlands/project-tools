#language slang 2026
// OS window focus border
// Adds a thin accent glow around the outer edge of the whole OS window
// viewport (all panes and the tab bar together) while it has keyboard focus.
// While it doesn't, the OS window is slightly dimmed, tinted cool and given a
// soft inner shadow (vignette) along its edges.
//
// The shader has no notion of focus itself: the pipeline decides when each
// pass runs. gentle.pipeline uses it in four groups, selected by OSW_FOCUS_PASS:
//   0 unfocused: always active; applies the dim, tint and vignette.
//   1 steady:    started by os-window-focus-in, stopped by os-window-focus-out,
//                animation_step 0. Undoes pass 0 exactly and adds the border
//                at OSW_FOCUS_STEADY_INTENSITY.
//   2 pulse:     started by os-window-focus-in, duration bounded. Adds the
//                extra light that takes the border from
//                OSW_FOCUS_STEADY_INTENSITY up to OSW_FOCUS_PULSE_INTENSITY,
//                easing back as animation_progress goes 0 → 1.
//   3 fade out:  started by os-window-focus-out, duration bounded, stopped
//                early by os-window-focus-in. Fades from the focused look
//                (steady border, no dim/tint/vignette) to the unfocused one as
//                animation_progress goes 0 → 1.
// Applying the unfocused look always and undoing it in the focus-gated pass
// (rather than starting a group on os-window-focus-out) means an OS window
// that is unfocused when the pipeline loads gets it straight away: kitty only
// synthesizes os-window-focus-in on load, never focus-out (so pass 3 doesn't
// run on load either). kitty's
// intermediate buffers are 16 bit, so the round trip doesn't band.
//
// The border adds light, like the pane focus glow, so the two sum where they
// overlap. Added light barely shows on very light backgrounds.

import kitty_custom_shader_types;

// Border colour in linear RGB. Default: the cursor trail's amber.
static const float3 OSW_FOCUS_COLOR = float3(0.8, 0.5, 0.12);
// Width of the solid part of the border, in framebuffer pixels (2 per point on Retina).
static const float OSW_FOCUS_BORDER_WIDTH_PX = 1.0;
// How far the glow fades inward beyond the solid border, in framebuffer pixels.
static const float OSW_FOCUS_GLOW_RADIUS_PX = 3.0;
// Light added at the border while focused, as a fraction of OSW_FOCUS_COLOR.
static const float OSW_FOCUS_STEADY_INTENSITY = 0.35;
// Light added at the start of the focus-in pulse.
static const float OSW_FOCUS_PULSE_INTENSITY = 0.9;
// Fraction of the original colour kept while the OS window is unfocused (1 = no dim).
static const float OSW_UNFOCUSED_DIM = 0.93;
// Colour (linear RGB) blended in while unfocused, and how much (0 = off, < 1).
static const float3 OSW_UNFOCUSED_TINT_COLOR = float3(0.1022, 0.162, 0.2789);
static const float OSW_UNFOCUSED_TINT = 0.0;
// Darkening at the very edge while unfocused (0 = off, < 1), fading out over
// OSW_UNFOCUSED_VIGNETTE_WIDTH_PX framebuffer pixels from each edge.
static const float OSW_UNFOCUSED_VIGNETTE = 0.0;
static const float OSW_UNFOCUSED_VIGNETTE_WIDTH_PX = 120.0;
// 0 = unfocused, 1 = steady, 2 = pulse, 3 = fade out (see above).
static const int OSW_FOCUS_PASS = 1;

// Distance from this pixel to the nearest edge of the OS window viewport, in pixels.
static float
edge_distance_px(KittyTextures t, KittyCustomShaderData d) {
    float2 size = float2(d.viewport_size_pixels);
    float2 px = t.pos * size;
    float2 edgeDists = min(px, size - px);
    return min(edgeDists.x, edgeDists.y);
}

// 1 at the edge, falling off quadratically to 0 at width pixels in.
static float
edge_falloff(float dist, float width) {
    float f = 1.0 - saturate(dist / max(width, 1e-4));
    return f * f;
}

// Inverse of the unfocused pass for a pixel with the given vignette factor.
static float3
undo_unfocused(float3 rgb, float vignette) {
    rgb /= max(vignette, 1e-4);
    rgb = (rgb - OSW_UNFOCUSED_TINT_COLOR * OSW_UNFOCUSED_TINT) / max(1.0 - OSW_UNFOCUSED_TINT, 1e-4);
    return max(rgb, 0.0) / max(OSW_UNFOCUSED_DIM, 1e-4);
}

// Light added by a border of the given intensity, dist pixels from the edge.
static float3
border_light(float dist, float intensity) {
    if (dist >= OSW_FOCUS_BORDER_WIDTH_PX + OSW_FOCUS_GLOW_RADIUS_PX) return float3(0.0);
    // 1 across the solid border, then a quadratic falloff over the glow radius.
    float profile = edge_falloff(dist - OSW_FOCUS_BORDER_WIDTH_PX, OSW_FOCUS_GLOW_RADIUS_PX);
    return OSW_FOCUS_COLOR * (intensity * profile);
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float dist = edge_distance_px(t, d);
    float vignette = 1.0 - OSW_UNFOCUSED_VIGNETTE * edge_falloff(dist, OSW_UNFOCUSED_VIGNETTE_WIDTH_PX);
    float3 rgb = color.rgb;

    if (OSW_FOCUS_PASS == 0) {
        rgb *= OSW_UNFOCUSED_DIM;
        rgb = lerp(rgb, OSW_UNFOCUSED_TINT_COLOR, OSW_UNFOCUSED_TINT);
        return float4(rgb * vignette, color.a);
    }
    if (OSW_FOCUS_PASS == 1) {
        rgb = undo_unfocused(rgb, vignette) + border_light(dist, OSW_FOCUS_STEADY_INTENSITY);
        return float4(rgb, color.a);
    }
    if (OSW_FOCUS_PASS == 3) {
        // Fade out: from the focused look with its steady border back to the
        // unfocused look pass 0 already applied.
        float3 focused = undo_unfocused(rgb, vignette) + border_light(dist, OSW_FOCUS_STEADY_INTENSITY);
        return float4(lerp(focused, rgb, t.animation_progress), color.a);
    }
    // Pulse: only the excess over the steady pass, which has already added its share.
    float intensity = max(lerp(OSW_FOCUS_PULSE_INTENSITY, OSW_FOCUS_STEADY_INTENSITY, t.animation_progress) - OSW_FOCUS_STEADY_INTENSITY, 0.0);
    return float4(rgb + border_light(dist, intensity), color.a);
}
