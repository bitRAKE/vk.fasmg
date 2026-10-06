include 'newcoff.inc'
struc? TCHAR args:?&
	. du args
end struc
macro TCHAR args:?&
	du args
end macro
sizeof.TCHAR = 2
include 'equates/kernel64.inc'
include '..\examples\strings.inc'
iterate function,VirtualAlloc,VirtualFree,GetLargePageMinimum,GetLastError,SetLastError,OpenProcessToken,LookupPrivilegeValueW,AdjustTokenPrivileges,CloseHandle
	extrn function:qword
end iterate
include '..\examples\common\cpu_arena.inc'
include '..\examples\common\range_allocator.inc'
iterate function,range_test_create,range_test_allocate,range_test_offset,range_test_free,range_test_destroy,range_test_capacity
	public function
end iterate
section '.text$probe' code readable executable align 16
proc range_test_create uses rbx,bytes
	mov rbx,rcx
	mov [large_pages_requested],0
	fastcall create_cpu_arena
	test eax,eax
	jz .done
	fastcall create_range_nodes
	test eax,eax
	jz .done
	fastcall range_initialize,addr test_ranges,rbx
.done:
	ret
endp
proc range_test_allocate bytes,alignment
	; Preserve arguments before assigning the heap as the first argument.
	mov r8,rdx
	mov rdx,rcx
	fastcall range_allocate,addr test_ranges,rdx,r8
	ret
endp
proc range_test_offset token
	mov rax,[rcx+RangeNode.binding]
	ret
endp
proc range_test_free token
	fastcall range_free,rcx
	ret
endp
proc range_test_destroy
	fastcall range_destroy,addr test_ranges
	fastcall destroy_cpu_arena
	ret
endp
proc range_test_capacity
	mov eax,RANGE_NODE_LIMIT
	ret
endp
section '.data$probe' data readable writeable align 8
test_ranges RangeHeap
