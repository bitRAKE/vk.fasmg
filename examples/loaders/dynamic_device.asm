; Lazy slots in a loader object, second of two objects; see dynamic_app.asm.
; This object includes only what it uses, and reports only what it calls.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/loader/dynamic.inc'

public run_device
extrn instance:qword
extrn device:qword

include 'device.inc'
