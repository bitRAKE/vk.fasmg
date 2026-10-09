include '../newcoff.inc'

extrn '__imp_ExitProcess' as ExitProcess:qword
public mainCRTStartup
public small_frame
public large_frame
public explicit_probe

section '.text$stack_main' code readable executable align 16
proc mainCRTStartup uses rbx
        fastcall small_frame,11h
        test eax,eax
        jnz probe_exit
        mov rbx,[gs:TeStackLimit]
        fastcall large_frame,11h,22h,33h,44h
        test eax,eax
        jnz probe_exit
        cmp rbx,[gs:TeStackLimit]
        ja automatic_grew
        mov eax,6
        jmp probe_exit
automatic_grew:
        mov rbx,[gs:TeStackLimit]
        fastcall explicit_probe
        test eax,eax
        jnz probe_exit
        cmp rbx,[gs:TeStackLimit]
        ja probe_exit
        mov eax,7
probe_exit:
        fastcall [ExitProcess],eax
endp

section '.text$stack_small' code readable executable align 16
proc small_frame input
        locals
                value dq ?
        endl
        mov [value],rcx
        xor eax,eax
        cmp qword [value],11h
        je small_done
        mov eax,1
small_done:
        ret
endp

section '.text$stack_large' code readable executable align 16
proc large_frame uses rbx,a,b,c,d
        locals
                initialized dq 13579BDFh
                first dq ?
                bytes rb 20000h-16
                last dq ?
        endl
        mov eax,2
        cmp rcx,11h
        jne large_done
        cmp rdx,22h
        jne large_done
        cmp r8,33h
        jne large_done
        cmp r9,44h
        jne large_done
        mov eax,3
        cmp qword [initialized],13579BDFh
        jne large_done
        mov qword [first],13579BDFh
        mov qword [last],2468ACE0h
        cmp qword [last],2468ACE0h
        jne large_done
        mov eax,4
        lea rbx,[first]
        cmp rbx,[gs:TeStackLimit]
        jb large_done
        xor eax,eax
large_done:
        ret
endp

section '.text$stack_explicit' code readable executable align 16
proc explicit_probe uses rbx
        mov rbx,rsp
        sub rsp,30000h
        __chkstk
        mov byte [rsp],5Ah
        xor eax,eax
        cmp byte [rsp],5Ah
        je explicit_done
        mov eax,5
explicit_done:
        mov rsp,rbx
        ret
endp
