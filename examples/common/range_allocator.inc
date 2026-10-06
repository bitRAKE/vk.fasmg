; Single-threaded, segregated free ranges. Nodes come from the startup arena;
; splitting and adjacent-range coalescing never call an OS allocator.
RANGE_NODE_LIMIT = 8192
struct RangeNode
	offset dq 0
	bytes dq 0
	binding dq 0
	previous dq 0
	next dq 0
	free_previous dq 0
	free_next dq 0
	heap dq 0
	used dd 0
	rb 4
ends
struct RangeHeap
	mask dq 0
	first dq 0
	bins rq 64
ends

section '.text$ranges' code readable executable align 16
proc create_range_nodes uses rbx rsi
	fastcall arena_take,RANGE_NODE_LIMIT*sizeof.RangeNode
	test rax,rax
	jz .failed
	mov [range_nodes],rax
	mov rsi,rax
	mov ebx,RANGE_NODE_LIMIT
.node:
	mov rax,[range_unused]
	mov [rsi+RangeNode.free_next],rax
	mov [range_unused],rsi
	add rsi,sizeof.RangeNode
	dec ebx
	jnz .node
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc range_acquire_node
	mov rax,[range_unused]
	test rax,rax
	jz .done
	mov rdx,[rax+RangeNode.free_next]
	mov [range_unused],rdx
	mov [rax+RangeNode.free_next],0
.done:
	ret
endp

proc range_release_node node
	mov rax,[range_unused]
	mov [rcx+RangeNode.free_next],rax
	mov [range_unused],rcx
	ret
endp

proc range_insert_free node
	mov r8,[rcx+RangeNode.heap]
	bsr rdx,[rcx+RangeNode.bytes]
	bts [r8+RangeHeap.mask],rdx
	mov rax,[r8+rdx*8+RangeHeap.bins]
	mov [rcx+RangeNode.free_next],rax
	mov [rcx+RangeNode.free_previous],0
	mov [rcx+RangeNode.used],0
	test rax,rax
	jz .head
	mov [rax+RangeNode.free_previous],rcx
.head:
	mov [r8+rdx*8+RangeHeap.bins],rcx
	ret
endp

proc range_remove_free node
	mov r8,[rcx+RangeNode.heap]
	mov rax,[rcx+RangeNode.free_previous]
	mov rdx,[rcx+RangeNode.free_next]
	test rax,rax
	jz .head
	mov [rax+RangeNode.free_next],rdx
	jmp .next
.head:
	bsr r9,[rcx+RangeNode.bytes]
	mov [r8+r9*8+RangeHeap.bins],rdx
	test rdx,rdx
	jnz .next
	btr [r8+RangeHeap.mask],r9
.next:
	test rdx,rdx
	jz .done
	mov [rdx+RangeNode.free_previous],rax
.done:
	mov [rcx+RangeNode.free_previous],0
	mov [rcx+RangeNode.free_next],0
	ret
endp

proc range_initialize uses rbx rsi,heap,bytes
	mov rbx,rcx
	mov rsi,rdx
	test rsi,rsi
	jz .failed
	fastcall range_acquire_node
	test rax,rax
	jz .failed
	mov [rbx+RangeHeap.first],rax
	mov [rax+RangeNode.offset],0
	mov [rax+RangeNode.bytes],rsi
	mov [rax+RangeNode.previous],0
	mov [rax+RangeNode.next],0
	mov [rax+RangeNode.heap],rbx
	fastcall range_insert_free,rax
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc range_destroy uses rbx rsi rdi,heap
	mov rbx,rcx
	mov rsi,[rbx+RangeHeap.first]
.node:
	test rsi,rsi
	jz .clear
	mov rdi,[rsi+RangeNode.next]
	fastcall range_release_node,rsi
	mov rsi,rdi
	jmp .node
.clear:
	mov rdi,rbx
	mov ecx,sizeof.RangeHeap/8
	xor eax,eax
	rep stosq
	ret
endp

; Alignment must be a nonzero power of two. The allocation owns leading padding
; and exposes binding as its aligned offset; free reclaims the entire range.
proc range_allocate uses rbx rsi rdi r12 r13 r14,heap,bytes,alignment
	mov rbx,rcx
	mov r12,rdx
	mov r13,r8
	test rdx,rdx
	jz .failed
	test r8,r8
	jz .failed
	lea rax,[r8-1]
	test rax,r8
	jnz .failed
	bsr rdi,rdx
.bin:
	mov rcx,rdi
	mov rax,-1
	shl rax,cl
	and rax,[rbx+RangeHeap.mask]
	jz .failed
	bsf rdi,rax
	mov rsi,[rbx+rdi*8+RangeHeap.bins]
.candidate:
	mov rax,[rsi+RangeNode.offset]
	lea rdx,[r13-1]
	add rax,rdx
	jc .next
	mov rdx,r13
	neg rdx
	and rax,rdx
	mov r14,rax
	add rax,r12
	jc .next
	sub rax,[rsi+RangeNode.offset]
	cmp rax,[rsi+RangeNode.bytes]
	jbe .fit
.next:
	mov rsi,[rsi+RangeNode.free_next]
	test rsi,rsi
	jnz .candidate
	inc edi
	cmp edi,64
	jb .bin
.failed:
	xor eax,eax
	ret
.fit:
	mov r12,rax
	cmp rax,[rsi+RangeNode.bytes]
	je .whole
	fastcall range_acquire_node
	test rax,rax
	jz .failed
	mov r13,rax
	fastcall range_remove_free,rsi
	mov rax,[rsi+RangeNode.offset]
	add rax,r12
	mov [r13+RangeNode.offset],rax
	mov rax,[rsi+RangeNode.bytes]
	sub rax,r12
	mov [r13+RangeNode.bytes],rax
	mov [r13+RangeNode.heap],rbx
	mov [r13+RangeNode.previous],rsi
	mov rax,[rsi+RangeNode.next]
	mov [r13+RangeNode.next],rax
	test rax,rax
	jz .tail
	mov [rax+RangeNode.previous],r13
.tail:
	mov [rsi+RangeNode.next],r13
	mov [rsi+RangeNode.bytes],r12
	fastcall range_insert_free,r13
	jmp .used
.whole:
	fastcall range_remove_free,rsi
.used:
	mov [rsi+RangeNode.used],1
	mov [rsi+RangeNode.binding],r14
	mov rax,rsi
	ret
endp

proc range_free uses rbx rsi,node
	mov rbx,rcx
	mov rsi,[rbx+RangeNode.previous]
	test rsi,rsi
	jz .next
	cmp [rsi+RangeNode.used],0
	jne .next
	fastcall range_remove_free,rsi
	mov rax,[rbx+RangeNode.bytes]
	add [rsi+RangeNode.bytes],rax
	mov rax,[rbx+RangeNode.next]
	mov [rsi+RangeNode.next],rax
	test rax,rax
	jz .previous_joined
	mov [rax+RangeNode.previous],rsi
.previous_joined:
	fastcall range_release_node,rbx
	mov rbx,rsi
.next:
	mov rsi,[rbx+RangeNode.next]
	test rsi,rsi
	jz .done
	cmp [rsi+RangeNode.used],0
	jne .done
	fastcall range_remove_free,rsi
	mov rax,[rsi+RangeNode.bytes]
	add [rbx+RangeNode.bytes],rax
	mov rax,[rsi+RangeNode.next]
	mov [rbx+RangeNode.next],rax
	test rax,rax
	jz .next_joined
	mov [rax+RangeNode.previous],rbx
.next_joined:
	fastcall range_release_node,rsi
.done:
	fastcall range_insert_free,rbx
	ret
endp

section '.data$ranges' data readable writeable align 8
range_nodes dq 0
range_unused dq 0
