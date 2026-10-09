; Named-function imports: the linker supplies a jump thunk for each function
; referenced by name. Call sites use a direct CALL; the thunk jumps through
; the import table. The runtime/export requirements are the same as iat.inc.
; This is not an adapter for the return-address-based lazy resolvers.
iterate class, instance,device
        irpv functions, loader_functions_#class
                iterate function, functions
                        calminstruction function line&
                                arrange line, =fastcall =function, line
                                assemble line
                        end calminstruction
                        if used function
                                extrn `function as function:qword
                        end if
                end iterate
                restore loader_functions_#class
        end irpv
end iterate
