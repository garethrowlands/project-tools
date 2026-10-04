<!-- jump_to_middle -->

kitty, with shaders
===================

everything you're about to see is live

<!-- end_slide -->

<!-- jump_to_middle -->

Focus follows you
=================

<!-- end_slide -->

<!-- jump_to_middle -->

…and when you switch tabs
=========================

<!-- end_slide -->

<!-- jump_to_middle -->

…and back again
===============

the slides' pane glowed as it got focus back

<!-- end_slide -->

<!-- jump_to_middle -->

Where did the cursor go?
========================

each jump leaves a subtle trail —
watch the right-hand pane

<!-- end_slide -->

Your mouse gets a spotlight
===========================

Wherever the pointer goes, a faint glow brightens the spot
around it and everything else dims a little. It is gentle
on purpose: you can see it on an empty background too,
but it shows best over text, like this paragraph,
a page of code, logs or a man page.

<!-- end_slide -->

Clicks ripple
=============

Every click sends a ring out through the text around it:
the letters bend as the wave passes, then settle.
On an empty background, only a faint ring of light.

```
startgroup
    animation_start pointer-left-button-press
    animation_stop 400
    animation_curve ease-out
    var float LENGTH_UNIT_PX = 23.0
    var float WAVE_SPEED = 6.0
    var float AMPLITUDE = 0.12
    var float GLOW_STRENGTH = 0.015
    shaders pond-ripple-local
endgroup
```

<!-- end_slide -->

<!-- jump_to_middle -->

Which pane rang?
================

<!-- end_slide -->

<!-- jump_to_middle -->

…even in another tab
====================

<!-- end_slide -->

<!-- jump_to_middle -->

Which window has focus?
=======================

kitty has the focus, so it shows
a thin amber border.

<!-- end_slide -->

<!-- jump_to_middle -->

Another app takes the focus
===========================

TextEdit has the focus now,
so kitty steps back:

* a little dimmer
* a cool blue tint
* a soft shadow at its edges (a vignette)

<!-- end_slide -->

<!-- jump_to_middle -->

…and back to kitty
==================

kitty has the focus again: the amber
border pulses, and the dimming, tint
and vignette lift.

<!-- end_slide -->

<!-- jump_to_middle -->

Clicking links in the terminal
==============================

eza and rg print real hyperlinks:
file names, directories, line numbers.

<!-- end_slide -->

<!-- jump_to_middle -->

Cmd+click a search hit…
=======================

…and the file opens at that line,
in micro, right where you clicked.

<!-- end_slide -->

<!-- jump_to_middle -->

Cmd+click a directory…
======================

…and the shell moves into it, no typing.
Proof: pwd, and the file waiting there.

<!-- end_slide -->

<!-- jump_to_middle -->

gentle.pipeline
===============

kitty ≥ 0.49 · custom_shaders

