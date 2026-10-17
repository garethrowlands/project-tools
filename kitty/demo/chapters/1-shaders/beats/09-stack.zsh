# Beat 9: windows piled on one another, and Hammerspoon's stack keys. kitty
# makes room (left half) and three TextEdit windows open one by one on the
# right half, exactly on top of one another (back, middle, front). Then the
# real keys step down the pile, with Hammerspoon's list overlay showing where
# you are, and back up. The slide is shown before the change. The presses are
# 0.75 s apart: the stack keys reuse one snapshot of the pile only while the
# presses come within a second of each other (stack.lua); any slower and each
# press starts from the new z-order and swaps the top two. (A press shows its
# badge for 0.7 s before the key goes, so they can't be closer than that.)
slide goto 13 'piled on one another'
beat-pause 3
stage open-stack $DEMO_CHAPTER_DIR/scene/stack-back.txt $DEMO_CHAPTER_DIR/scene/stack-middle.txt $DEMO_CHAPTER_DIR/scene/stack-front.txt
beat-pause 2
stage press-other 'ctrl+alt+cmd+]'
beat-pause 0.75
stage press-other 'ctrl+alt+cmd+]'
beat-pause 0.75
stage press-other 'ctrl+alt+cmd+['
beat-pause 0.75
stage press-other 'ctrl+alt+cmd+['
beat-pause 2.5
stage focus-main
stage close-stack
stage fill
beat-pause 1
