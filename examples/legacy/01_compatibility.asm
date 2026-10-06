; Hide modern operations and restrict render targets to 128 pixels.
; The same application uses render passes, old sync/copy/submit, and tiled output.
PROFILE_NAME equ 'Compatibility'
PROFILE_TAG equ 'compatibility'
CAP_MASK = 0
FORCE_CPU = 0
TILE_CEILING = 128
include 'explorer.inc'
