#language slang 2026
// Bell ring
// When a bell (BEL) arrives, the edges of the kitty window (pane) it arrived in
// glow and pulse BELL_RINGS times (0 = a single flash), dying away like a
// struck bell. The glow reaches BELL_OUTSET_PX outside the pane too, because
// kitty gives only the pane's text area and draws its borders just outside it. The pane
// need not be focused. If it isn't visible (e.g. it is in another tab), kitty
// gives the whole central area instead, so the tab area's edges ring.
//
// Meant for a group started by bell-in-window with a duration-bounded
// animation_stop and a linear curve: the decay and pulses are computed here
// from animation_progress (0 → 1). kitty only fires bell-in-window when
// visual_bell_duration > 0 in kitty.conf; a tiny value such as 0.01 keeps
// kitty's own full-pane flash too short to see.
//
// Blends toward BELL_COLOR rather than adding light, so it stays its own
// colour over kitty's near-white active border and the white pane focus glow
// (added light would saturate to white there), and shows on light themes too.

import kitty_custom_shader_types;

// Glow colour in linear RGB. Default: a muted red-orange (sRGB #f0703c).
static const float3 BELL_COLOR = float3(0.8714, 0.162, 0.0452);
// Blend amount toward BELL_COLOR at the pane edge at the first strike (0..1).
static const float BELL_INTENSITY = 0.5;
// How far in from the pane edge the glow fades out, in framebuffer pixels.
static const float BELL_WIDTH_PX = 6.0;
// How far the glow reaches outward past the pane's text area at full strength,
// in framebuffer pixels, to cover kitty's window border.
static const float BELL_OUTSET_PX = 4.0;
// Number of pulses over the animation; 0 = a single decaying flash.
static const float BELL_RINGS = 3.0;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 g = d.bell_window_geometry;
    // All zero until the first bell.
    if (g.z <= 0.0 || g.w <= 0.0) return color;
    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 outset = BELL_OUTSET_PX / pixelDims;
    float2 winMin = g.xy;
    float2 winMax = g.xy + g.zw;
    if (any(t.pos < winMin - outset) || any(t.pos > winMax + outset)) return color;

    // Distance in from the nearest pane edge, in pixels so all four edges match;
    // negative in the outset band, which gets the full glow.
    float2 edgePx = min(t.pos - winMin, winMax - t.pos) * pixelDims;
    float f = 1.0 - saturate(min(edgePx.x, edgePx.y) / max(BELL_WIDTH_PX, 1e-4));
    float profile = f * f;

    // Strikes at full strength, then BELL_RINGS pulses under a decaying envelope.
    float p = t.animation_progress;
    float decay = (1.0 - p) * (1.0 - p);
    float pulse = 0.5 + 0.5 * cos(6.2831853 * BELL_RINGS * p);
    float amount = saturate(BELL_INTENSITY * decay * pulse * profile);
    return float4(lerp(color.rgb, BELL_COLOR, amount), color.a);
}
