; Synchronous host work owns its scratch; no pointer escapes either procedure.
extrn '__imp_lstrcmpA' as lstrcmpA:qword
extrn '__imp_wsprintfA' as wsprintfA:qword

section '.text$recipe_host' code readable executable align 16

; RCX = instance create info. Only static debug names survive this lookup.
proc find_debug_extension uses rbx rsi rdi,info
        locals
                count dd ?
                entries rb 256*sizeof.VkExtensionProperties
        endl
        mov rbx,rcx
        ; newcoff.inc probes this known large frame before local initialization.
        mov [count],256
        vkEnumerateInstanceExtensionProperties 0,addr count,addr entries
        test eax,eax
        jnz extension_done
        xor esi,esi
        lea rdi,[entries]
extension_next:
        cmp esi,[count]
        jae extension_success
        fastcall [lstrcmpA],rdi,addr debug_extension
        test eax,eax
        jz extension_found
        inc esi
        add rdi,sizeof.VkExtensionProperties
        jmp extension_next
extension_found:
        mov dword [rbx+VkInstanceCreateInfo.enabledExtensionCount],1
        lea rax,[debug_info]
        mov [rbx+VkInstanceCreateInfo.pNext],rax
extension_success:
        xor eax,eax
extension_done:
        ret
endp

; Format and consume the line synchronously. No shared or retained text buffer.
proc report_line format,a,b,c,d
        locals
                text rb 256
        endl
        mov [format],rcx
        mov [a],rdx
        mov [b],r8
        mov [c],r9
        fastcall [wsprintfA],addr text,[format],[a],[b],[c],[d]
        fastcall console_write_line,addr text
        ret
endp
