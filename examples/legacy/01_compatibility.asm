; Contract: the original operations alone. Render pass and framebuffer, the
; first barriers, copies and submission, shader modules, fences, and the
; unextended physical-device queries. No modern route is assembled.
; Images the program allocates stay within 128 pixels, so exports are tiled.
CONTRACT_NAME equ 'Compatibility'
CONTRACT_TAG equ 'compatibility'
CAP_MASK = 32                       ; shaderFloat64 only: a core 1.0 feature
CAP_REQUIRED = 0
TILE_CEILING = 128
include 'explorer.inc'
