# Beat 1: two panes split off; focus hops deck -> A -> B -> deck and each
# card says what is happening to it. A and B stay open for beat 2.
slide goto 2 'Focus follows you'
beat-pause 1.5
card open A $'New pane.\nI just got focus —\nsee my edges glow.' --location=vsplit
focus A
beat-pause 2
card open B $'Another one.\nNow I glow,\nand A is dimmed.' --location=hsplit
focus B
card say A $'Not focused any more,\nso I\'m slightly dimmed.'
beat-pause 2
focus deck
card say B $'Dimmed too.\nThe slides have focus.'
card say A $'Dimmed too.'
beat-pause 2.5
