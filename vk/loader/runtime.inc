; Explicit Vulkan runtime bootstrap for static, dynamic, and COMDAT loaders.
; Invoke vk_runtime.bootstrap in exactly one object. Call vk_runtime_open
; before Vulkan, and close after all Vulkan objects and callers have gone away.
; Link kernel32.lib; do not link vulkan-1.lib for this bootstrap.
;
; open returns VkResult: zero, or VK_ERROR_INITIALIZATION_FAILED (-3).
; Missing DLL and missing vkGetInstanceProcAddr both leave the bootstrap empty.
; Once lazy slots have been filled, closing ends their lifetime: do not reopen
; and call those old slots. One instance/device lifetime per process remains.
; The optional bootstrap argument overrides the DLL name (tests).
macro vk_runtime.bootstrap library:'vulkan-1.dll'

; Win32 binding policy: direct IAT calls (docs/binary-layout.md).
extrn '__imp_LoadLibraryW' as LoadLibraryW:qword
extrn '__imp_GetProcAddress' as GetProcAddress:qword
extrn '__imp_FreeLibrary' as FreeLibrary:qword
public vk_runtime_open
public vk_runtime_close
public vk_runtime_resolver as '__imp_vkGetInstanceProcAddr'

section '.text$vkrt' code readable executable align 16
proc vk_runtime_open
        cmp [vk_runtime_module],0
        jne .ready
        fastcall [LoadLibraryW],addr vk_runtime_library
        test rax,rax
        jz .failed
        mov [vk_runtime_module],rax
        fastcall [GetProcAddress],rax,addr vk_runtime_name
        test rax,rax
        jz .unload
        mov [vk_runtime_resolver],rax
.ready:
        xor eax,eax
        ret
.unload:
        fastcall vk_runtime_close
.failed:
        mov eax,-3
        ret
endp

proc vk_runtime_close
        mov [vk_runtime_resolver],0
        cmp [vk_runtime_module],0
        je .done
        fastcall [FreeLibrary],[vk_runtime_module]
        mov [vk_runtime_module],0
.done:
        ret
endp

section '.rdata$vkrt' data readable align 2
vk_runtime_library du library,0
vk_runtime_name db 'vkGetInstanceProcAddr',0
section '.bss$vkrt' readable writeable align 8
vk_runtime_module dq ?
vk_runtime_resolver dq ?
end macro
