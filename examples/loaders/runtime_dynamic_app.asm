; Dynamic's shared loader object is unchanged; this object owns the bootstrap.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/dynamic.inc'
include 'vk/loader/runtime.inc'
vk_runtime.bootstrap
LOADER_RUNTIME := 1
public mainCRTStartup
public instance
public device
extrn run_device:qword
include 'instance.inc'
binding_text GLOBSTR 'explicit runtime: one shared lazy loader object',0
