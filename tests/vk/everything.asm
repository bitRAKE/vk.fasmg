; Assembles the whole projection as one unit: a definition emitted by two files
; or a struct whose embedded type no file defines fails here.  The assembler's
; alignment check is switched on and must stay silent, which takes the
; project's macro/struct.inc.  iat.inc turns every gathered function into an
; instruction and imports none of them.
include 'newcoff.inc'

Struct.CheckAlignment = 1

include 'tests/vk/everything.inc'
include 'tests/vk/layout_asserts.inc'
include 'vk/loader/iat.inc'

; The check ran: it is what records a struct's alignment.
assert VkApplicationInfo.__alignment = 8 & VkExtent2D.__alignment = 4
