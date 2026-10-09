; Same exported API as iat.asm; function-name imports request linker thunks.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/loader/thunk.inc'
public mainCRTStartup
include 'instance.inc'
include 'device.inc'
binding_text GLOBSTR 'named imports: direct calls to linker jump thunks',0
