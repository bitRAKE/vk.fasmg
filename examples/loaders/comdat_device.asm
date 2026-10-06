; Lazy slots merged by the linker, second of two objects; see comdat_app.asm.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/loader/comdat.inc'

public run_device
extrn instance:qword
extrn device:qword

include 'device.inc'
