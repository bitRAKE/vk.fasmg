; Hide modern operations and restrict render targets to 128 pixels.
; The same application uses render passes, old sync/copy/submit, and tiled output.
PROFILE_NAME equ 'Compatibility'
PROFILE_TAG equ 'compatibility'
CAP_MASK = 32                       ; shaderFloat64 is a core 1.0 feature.
FORCE_CPU = 0
TILE_CEILING = 128
include 'explorer.inc'
