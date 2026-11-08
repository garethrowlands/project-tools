#language slang 2026
// Bell ring
// When a bell (BEL) arrives, the edges of the kitty window (pane) it arrived in
// flash red and die away, and the pane's text shakes like a struck
// panel (mostly side to side, with a lag down the pane so it wobbles rather
// than moving rigidly) and settles. kitty gives only the pane's text area and
// draws its rounded border (WINDOW_RADIUS_PX) outside it, past the padding, so
// the glow follows a rounded rectangle grown by that padding (the active
// window's, which every pane shares) to the border's outer edge, and stays
// out of the square corners beyond the border's arc.
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

// Glow colour in linear RGB. Default: Catppuccin Mocha red (sRGB #F38BA8).
static const float3 BELL_COLOR = float3(0.8963, 0.2582, 0.3916);
// Blend amount toward BELL_COLOR at the pane edge at the first strike (0..1).
static const float BELL_INTENSITY = 0.5;
// How far in from the pane edge the glow fades out, in framebuffer pixels.
static const float BELL_WIDTH_PX = 6.0;
// How far the glow reaches outward past the pane's text area, in framebuffer
// pixels, when the padding to the border isn't known (the whole central area
// ringing, or no active window yet). Otherwise the padding is used.
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
// Corner radius of the glow's rounded rectangle, in framebuffer pixels; match
// kitty.conf's window_border_radius (gentle.pipeline sets it once for all shaders).
static const float WINDOW_RADIUS_PX = 16.0;
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

    // The pane's text area, in pixels so all four edges match. The text shakes
    // inside it as a plain rectangle.
    float2 halfPx = 0.5 * g.zw * pixelDims;
    float2 offPx = (t.pos - (winMin + 0.5 * g.zw)) * pixelDims;
    float2 edgePx = halfPx - abs(offPx);

    // The border's outer edge: the text area grown by the padding, per side
    // (left, bottom, right, top). The active window's padding stands in for
    // this pane's; it is the same for every pane. A tab-wide ring, or no known
    // padding, grows the rectangle by BELL_OUTSET_PX instead.
    float4 pad = float4(d.active_window_padding.xy * pixelDims, d.active_window_padding.zw * pixelDims);
    if (all(abs(g - d.central_area) < 1e-4) || pad.x + pad.y + pad.z + pad.w <= 0.0) {
        pad = float4(BELL_OUTSET_PX);
    }
    float2 outerHalf = halfPx + 0.5 * (pad.xy + pad.zw);
    float2 outerCentre = 0.5 * (pad.zw - pad.xy);
    // so: the distance in from the border's rounded outer edge (negative
    // outside it, in the square corners beyond its arc).
    float radius = min(WINDOW_RADIUS_PX, min(outerHalf.x, outerHalf.y));
    float2 q = abs(offPx - outerCentre) - (outerHalf - radius);
    float so = radius - (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));
    if (so < -1.0) return color;
    // 1 inside the rounded edge, fading over a pixel; 0 in the corners beyond
    // it, so kitty's rounded border isn't flashed as a square.
    float inside = saturate(so + 0.5);
    // The glow is at full strength from the border in to the text area, then
    // fades out over its width.
    float reach = min(min(pad.x, pad.y), min(pad.z, pad.w));
    float s = so - reach;

    if (BELL_MODE == 1) {
        float f = 1.0 - saturate(s / max(BELL_HOLD_WIDTH_PX, 1e-4));
        float amount = saturate(BELL_HOLD_INTENSITY * f * f * inside);
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
    float amount = saturate(BELL_INTENSITY * decay * pulse * f * f * inside);
    return float4(lerp(result.rgb, BELL_COLOR, amount), result.a);
}
