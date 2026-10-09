; A DLL that loads but lacks Vulkan's resolver must leave no bootstrap state.
include 'newcoff.inc'
include 'vk/loader/runtime.inc'
vk_runtime.bootstrap 'kernel32.dll'
extrn '__imp_ExitProcess' as ExitProcess:qword
public mainCRTStartup
section '.text' code readable executable
proc mainCRTStartup uses rbx
        mov ebx,1
        fastcall vk_runtime_open
        cmp eax,-3
        jne .failed
        inc ebx
        cmp [vk_runtime_module],0
        jne .failed
        inc ebx
        cmp [vk_runtime_resolver],0
        jne .failed
        fastcall vk_runtime_close
        inc ebx
        cmp [vk_runtime_module],0
        jne .failed
        cmp [vk_runtime_resolver],0
        jne .failed
        xor ebx,ebx
.failed:
        fastcall [ExitProcess],rbx
        int3
endp
