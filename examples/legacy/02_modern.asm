; Contract: the modern operations, or no program. Dynamic rendering,
; synchronization2, copy commands2, inline shader code and timeline semaphores
; are required; none of what they replace is assembled, and a device without
; them is reported at startup. Core and KHR routes both satisfy the contract.
CONTRACT_NAME equ 'Modern'
CONTRACT_TAG equ 'modern'
CAP_MASK = 63
CAP_REQUIRED = 31                   ; the five routes; shaderFloat64 stays optional
TILE_CEILING = 16384
include 'explorer.inc'
