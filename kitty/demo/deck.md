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

Where did the cursor go?
========================

<!-- end_slide -->

<!-- jump_to_middle -->

Your mouse gets a spotlight
===========================

<!-- end_slide -->

Clicks ripple
=============

Every click sends a ring out through the text around it:
the letters bend as the wave passes, then settle.
On an empty background there is nothing to bend.

```
startgroup
    animation_start pointer-left-button-press
    animation_stop 400
    animation_curve ease-out
    var float WAVE_SPEED = 0.12
    var float AMPLITUDE = 0.0015
    shaders pond-ripple
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

Which window am I typing in?
============================

<!-- end_slide -->

<!-- jump_to_middle -->

Click a link, land in a terminal app
====================================

<!-- end_slide -->

<!-- jump_to_middle -->

gentle.pipeline
===============

kitty ≥ 0.49 · custom_shaders

