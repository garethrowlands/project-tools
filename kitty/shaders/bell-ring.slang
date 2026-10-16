#language slang 2026
// Bell ring
// When a bell (BEL) arrives, the edges of the kitty window (pane) it arrived in
// flash red-orange and die away, and the pane's text shakes like a struck
// panel (mostly side to side, with a lag down the pane so it wobbles rather
// than moving rigidly) and settles. The glow follows a rounded rectangle
// (BELL_RADIUS_PX) and reaches BELL_OUTSET_PX outside the pane too, because
// kitty gives only the pane's text area and draws its borders just outside it.
// The pane need not be focused. If it isn't visible (e.g. it is in another
// tab), kitty gives the whole central area instead, so the tab area's edges
// ring and its contents shake.
//
// Two groups use it (see BELL_MODE). The burst is started by bell-in-window
// with a duration-bounded animation_stop and a linear curve: the flash and
// the shake are computed here from animation_progress (0 → 1). The hold is a
// second group, static, that keeps the rang pane's edges lit until a pane
// gains focus; it draws nothing when the pane that rang is the focused one, or
// when kitty gave the whole central area. kitty only fires bell-in-window when
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
// 0 = burst: an edge flash, and the text shaking and settling.
// 1 = hold: a steady edge glow for the pane that rang, while it is not the
//     focused pane. Group is static (animation_step 0) and stops on
//     window-focus-in, so it costs nothing while it lingers.
static const int BELL_MODE = 0;
// Burst: peak text displacement, framebuffer pixels (side to side; up and down
// is a third of it).
static const float BELL_SHAKE_PX = 9.0;
// Oscillations over the animation (cycles / duration = frequency).
static const float BELL_SHAKE_CYCLES = 7.0;
// How fast the shake dies away (higher = quicker); it is also faded out
// linearly so it ends at exactly zero.
static const float BELL_SHAKE_DECAY = 3.0;
// Lag down the pane, radians from the top to the bottom: 0 moves the text
// rigidly, larger wobbles like jelly. Lower text also moves a bit more.
static const float BELL_SHAKE_LAG = 1.6;
// Corner radius of the glow's rounded rectangle, in framebuffer pixels.
static const float BELL_RADIUS_PX = 20.0;
// Hold: blend amount at the pane edge, and how far in it fades out.
static const float BELL_HOLD_INTENSITY = 0.3;
static const float BELL_HOLD_WIDTH_PX = 22.0;

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float4 g = d.bell_window_geometry;
    // All zero until the first bell.
    if (g.z <= 0.0 || g.w <= 0.0) return color;
    if (BELL_MODE == 1) {
        // Nothing to hold for the focused pane, or for a pane in another tab.
        if (all(abs(g - d.active_window_geometry) < 1e-4)) return color;
        if (all(abs(g - d.central_area) < 1e-4)) return color;
    }
    float2 pixelDims = float2(d.viewport_size_pixels) * t.viewport.zw;
    float2 winMin = g.xy;
    float2 winMax = g.xy + g.zw;

    // Distance in from the nearest pane edge, in pixels so all four edges match;
    // negative in the outset band. The pane is cut out as a plain rectangle, so
    // the glow also covers the square corners of kitty's window border, and the
    // text shakes right to the corners.
    float2 halfPx = 0.5 * g.zw * pixelDims;
    float2 offPx = (t.pos - (winMin + 0.5 * g.zw)) * pixelDims;
    float2 edgePx = halfPx - abs(offPx);
    if (min(edgePx.x, edgePx.y) < -BELL_OUTSET_PX) return color;

    // The glow fades in along a rounded rectangle: s is the distance in from
    // its edge (negative outside it, in the corners, where the glow is full).
    float radius = min(BELL_RADIUS_PX, min(halfPx.x, halfPx.y));
    float2 q = abs(offPx) - (halfPx - radius);
    float s = radius - (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));

    if (BELL_MODE == 1) {
        float f = 1.0 - saturate(s / max(BELL_HOLD_WIDTH_PX, 1e-4));
        float amount = saturate(BELL_HOLD_INTENSITY * f * f);
        return float4(lerp(color.rgb, BELL_COLOR, amount), color.a);
    }

    float p = t.animation_progress;

    // The text: shaken side to side, lagging down the pane (u = 0 at the top,
    // 1 at the bottom), inside the pane only and never reading from outside it.
    float4 result = color;
    if (min(edgePx.x, edgePx.y) >= 0.0) {
        float u = saturate((winMax.y - t.pos.y) / g.w);
        float swing = exp(-BELL_SHAKE_DECAY * p) * (1.0 - p) * (0.6 + 0.4 * u);
        float phase = 6.2831853 * BELL_SHAKE_CYCLES * p - BELL_SHAKE_LAG * u;
        float2 shift = float2(sin(phase), 0.33 * sin(phase + 1.0)) * (BELL_SHAKE_PX * swing);
        float2 warped = clamp(t.pos + shift / pixelDims, winMin, winMax);
        result = t.backbuffer.Sample(warped);
    }

    // The flash at the edge: strikes at full strength and dies away.
    float f = 1.0 - saturate(s / max(BELL_WIDTH_PX, 1e-4));
    float decay = (1.0 - p) * (1.0 - p);
    float pulse = 0.5 + 0.5 * cos(6.2831853 * BELL_RINGS * p);
    float amount = saturate(BELL_INTENSITY * decay * pulse * f * f);
    return float4(lerp(result.rgb, BELL_COLOR, amount), result.a);
}
