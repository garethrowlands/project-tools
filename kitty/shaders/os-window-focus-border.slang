#language slang 2026
// OS window focus look
// While the OS window doesn't have keyboard focus it is slightly dimmed, tinted
// cool and given a soft inner shadow (vignette) along its edges; focusing it
// fades that away. (The file keeps its old name, from when it also drew an
// accent border around the OS window; that border is gone: it was straight
// while kitty's pane borders are rounded.)
//
// The shader has no notion of focus itself: the pipeline decides when each
// pass runs. gentle.pipeline uses it in two groups, selected by OSW_FOCUS_PASS:
//   0 unfocused: always active; applies the dim, tint and vignette.
//   1 focused:   started by os-window-focus-in, stopped by os-window-focus-out,
//                with animation_duration (fade in) and animation_reverse (fade
//                out), so animation_progress runs 0 → 1 as focus arrives and
//                back 1 → 0 as it leaves, then the group turns off. Undoes
//                pass 0, blended in by animation_progress: 0 is the unfocused
//                look pass 0 left, 1 the focused look.
// Applying the unfocused look always and undoing it in the focus-gated pass
// (rather than starting a group on os-window-focus-out) means an OS window
// that is unfocused when the pipeline loads gets it straight away: kitty only
// synthesizes os-window-focus-in on load, never focus-out. kitty's
// intermediate buffers are 16 bit, so the round trip doesn't band.

import kitty_custom_shader_types;

// Fraction of the original colour kept while the OS window is unfocused (1 = no dim).
static const float OSW_UNFOCUSED_DIM = 0.93;
// How far every colour is pulled toward its own grey while unfocused (0 = off, < 1).
static const float OSW_UNFOCUSED_DESATURATION = 0.0;
// Colour (linear RGB) blended in while unfocused, and how much (0 = off, < 1).
// A dark colour here lowers contrast and tints without lifting the background.
static const float3 OSW_UNFOCUSED_TINT_COLOR = float3(0.1022, 0.162, 0.2789);
static const float OSW_UNFOCUSED_TINT = 0.0;
static const float3 LUMA_WEIGHTS = float3(0.2126, 0.7152, 0.0722);
// Darkening at the very edge while unfocused (0 = off, < 1), fading out over
// OSW_UNFOCUSED_VIGNETTE_WIDTH_PX framebuffer pixels from each edge.
static const float OSW_UNFOCUSED_VIGNETTE = 0.0;
static const float OSW_UNFOCUSED_VIGNETTE_WIDTH_PX = 120.0;
// 0 = unfocused, 1 = focused fade (see above).
static const int OSW_FOCUS_PASS = 0;

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

// The unfocused look (pass 0) for a pixel with the given vignette factor.
static float3
apply_unfocused(float3 rgb, float vignette) {
    rgb = lerp(rgb, float3(dot(rgb, LUMA_WEIGHTS)), OSW_UNFOCUSED_DESATURATION);
    rgb *= OSW_UNFOCUSED_DIM;
    rgb = lerp(rgb, OSW_UNFOCUSED_TINT_COLOR, OSW_UNFOCUSED_TINT);
    return rgb * vignette;
}

// Inverse of the unfocused pass for a pixel with the given vignette factor.
static float3
undo_unfocused(float3 rgb, float vignette) {
    rgb /= max(vignette, 1e-4);
    rgb = (rgb - OSW_UNFOCUSED_TINT_COLOR * OSW_UNFOCUSED_TINT) / max(1.0 - OSW_UNFOCUSED_TINT, 1e-4);
    rgb = max(rgb, 0.0) / max(OSW_UNFOCUSED_DIM, 1e-4);
    // Desaturation keeps luma, so the inverse follows from luma(y) = luma(x).
    float luma = dot(rgb, LUMA_WEIGHTS);
    return max((rgb - OSW_UNFOCUSED_DESATURATION * luma) / max(1.0 - OSW_UNFOCUSED_DESATURATION, 1e-4), 0.0);
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float dist = edge_distance_px(t, d);
    float vignette = 1.0 - OSW_UNFOCUSED_VIGNETTE * edge_falloff(dist, OSW_UNFOCUSED_VIGNETTE_WIDTH_PX);
    float3 rgb = color.rgb;

    if (OSW_FOCUS_PASS == 0) {
        return float4(apply_unfocused(rgb, vignette), color.a);
    }
    // Focused, faded: from the unfocused look pass 0 applied (progress 0) to
    // the original colours (progress 1).
    return float4(lerp(rgb, undo_unfocused(rgb, vignette), t.animation_progress), color.a);
}
