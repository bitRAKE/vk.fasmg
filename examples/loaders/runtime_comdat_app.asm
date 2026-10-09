; COMDAT's device object is unchanged; this object owns the bootstrap.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/comdat.inc'
include 'vk/loader/runtime.inc'
vk_runtime.bootstrap
LOADER_RUNTIME := 1
public mainCRTStartup
public instance
public device
extrn run_device:qword
include 'instance.inc'
binding_text GLOBSTR 'explicit runtime: lazy slots merged by the linker',0
