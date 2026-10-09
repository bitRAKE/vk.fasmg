; Static lazy slots with an explicitly loaded Vulkan runtime, no Vulkan import.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/static.inc'
include 'vk/loader/runtime.inc'
vk_runtime.bootstrap
LOADER_RUNTIME := 1
public mainCRTStartup
include 'instance.inc'
include 'device.inc'
binding_text GLOBSTR 'explicit runtime: lazy slots in this object',0
