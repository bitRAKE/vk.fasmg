; Persistent memory blocks, compatible memory types and segregated free ranges.
; Buffers and optimal images occupy separate blocks (bufferImageGranularity).
; Destruction retires through the command timeline before a range is reusable.
include 'range_allocator.inc'
MEMORY_POOL_LIMIT = 64
GPU_DELETE_LIMIT = 256
struct MemoryPool
	memory dq 0
	mapped dq 0
	bytes dq 0
	memory_type dd 0
	flags dd 0
	kind dd 0
	dedicated dd 0
	ranges RangeHeap
ends
struct GpuBuffer
	handle dq 0
	memory dq 0
	mapped dq 0
	offset dq 0
	bytes dq 0
	pool dq 0
	range dq 0
	coherent dd 0
	rb 4
	address dq 0
ends
struct GpuImage
	handle dq 0
	memory dq 0
	mapped dq 0
	offset dq 0
	bytes dq 0
	pool dq 0
	range dq 0
	coherent dd 0
	rb 4
	view dq 0
ends
assert GpuBuffer.memory = GpuImage.memory
assert sizeof.GpuBuffer = sizeof.GpuImage
struct GpuDelete
	retirement dq 0
	handle dq 0
	view dq 0
	pool dq 0
	range dq 0
	kind dd 0
	rb 4
ends

section '.text$pools' code readable executable align 16
proc create_memory_pools
	fastcall create_range_nodes
	test eax,eax
	jz .done
	fastcall arena_take,MEMORY_POOL_LIMIT*sizeof.MemoryPool
	mov [memory_pools],rax
	test rax,rax
	jz .failed
	fastcall arena_take,GPU_DELETE_LIMIT*sizeof.GpuDelete
	mov [gpu_deletes],rax
	test rax,rax
	jz .failed
	mov eax,1
.done:
	ret
.failed:
	xor eax,eax
	ret
endp

proc allocate_gpu_memory uses rbx rsi rdi r12 r13 r14 r15,owner,memory_type,kind,flags
	mov rbx,rcx
	mov r12d,edx
	mov r13d,r8d
	mov r14d,r9d
	mov rax,[memory_requirements2.memoryRequirements.size]
	mov [rbx+GpuBuffer.bytes],rax
	mov r15,[memory_requirements2.memoryRequirements.alignment]
	imul eax,r12d,sizeof.VkMemoryType
	lea rdx,[memory_properties2.memoryProperties.memoryTypes]
	mov edi,[rdx+rax+VkMemoryType.propertyFlags]
	mov eax,edi
	and eax,VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
	cmp [force_noncoherent],0
	je .coherence
	xor eax,eax
.coherence:
	mov [rbx+GpuBuffer.coherent],eax
	cmp r13d,2
	je .search
	test eax,eax
	jnz .search
	mov rax,[properties2.properties.limits.nonCoherentAtomSize]
	cmp r15,rax
	jae .round_size
	mov r15,rax
.round_size:
	lea rdx,[rax-1]
	add rdx,[rbx+GpuBuffer.bytes]
	jc .failed
	neg rax
	and rdx,rax
	mov [rbx+GpuBuffer.bytes],rdx
.search:
	cmp [memory_dedicated.requiresDedicatedAllocation],VK_TRUE
	je .new_dedicated
	cmp [force_dedicated],0
	jne .new_dedicated
	mov rsi,[memory_pools]
	xor edi,edi
.pool:
	cmp [rsi+MemoryPool.memory],0
	je .next
	cmp [rsi+MemoryPool.dedicated],0
	jne .next
	cmp [rsi+MemoryPool.memory_type],r12d
	jne .next
	cmp [rsi+MemoryPool.kind],r13d
	jne .next
	cmp [rsi+MemoryPool.flags],r14d
	jne .next
	fastcall range_allocate,addr rsi+MemoryPool.ranges,[rbx+GpuBuffer.bytes],r15
	test rax,rax
	jnz .reused
.next:
	add rsi,sizeof.MemoryPool
	inc edi
	cmp edi,MEMORY_POOL_LIMIT
	jb .pool
	xor edi,edi
	jmp .new
.new_dedicated:
	mov rax,[memory_requirements2.memoryRequirements.size]
	mov [rbx+GpuBuffer.bytes],rax
	mov edi,1
.new:
	mov rsi,[memory_pools]
	mov ecx,MEMORY_POOL_LIMIT
.slot:
	cmp [rsi+MemoryPool.memory],0
	je .create
	add rsi,sizeof.MemoryPool
	dec ecx
	jnz .slot
	jmp .failed
.create:
	mov [rsi+MemoryPool.memory_type],r12d
	mov [rsi+MemoryPool.kind],r13d
	mov [rsi+MemoryPool.flags],r14d
	mov [rsi+MemoryPool.dedicated],edi
	mov rax,[rbx+GpuBuffer.bytes]
	test edi,edi
	jnz .size
	mov edx,[buffer_pool_bytes]
	cmp r13d,2
	jne .capacity
	mov edx,[image_pool_bytes]
.capacity:
	cmp rdx,rax
	jae .capacity_ready
	add rdx,rdx
	jc .failed
	jmp .capacity
.capacity_ready:
	mov rax,rdx
.size:
	mov [memory_allocate.allocationSize],rax
	mov [memory_allocate.memoryTypeIndex],r12d
	mov [memory_allocate.pNext],0
	mov [memory_address_flags.pNext],0
	test edi,edi
	jz .flags
	mov [memory_dedicated_allocate.image],0
	mov [memory_dedicated_allocate.buffer],0
	mov rax,[rbx+GpuBuffer.handle]
	cmp r13d,2
	je .dedicated_image
	mov [memory_dedicated_allocate.buffer],rax
	jmp .dedicated_chain
.dedicated_image:
	mov [memory_dedicated_allocate.image],rax
.dedicated_chain:
	lea rax,[memory_dedicated_allocate]
	mov [memory_allocate.pNext],rax
	mov [memory_address_flags.pNext],rax
.flags:
	test r14d,r14d
	jz .allocate
	mov [memory_address_flags.flags],r14d
	lea rax,[memory_address_flags]
	mov [memory_allocate.pNext],rax
.allocate:
	vkAllocateMemory [device],addr memory_allocate,0,addr rsi+MemoryPool.memory
	test eax,eax
	jz .allocated
	; A modest block may still exceed a small heap's available budget.
	mov rax,[rbx+GpuBuffer.bytes]
	cmp [memory_allocate.allocationSize],rax
	je .failed
	mov [memory_allocate.allocationSize],rax
	vkAllocateMemory [device],addr memory_allocate,0,addr rsi+MemoryPool.memory
	test eax,eax
	jnz .failed
.allocated:
	inc [memory_allocations]
	inc [memory_live_allocations]
	mov rax,[memory_allocate.allocationSize]
	mov [rsi+MemoryPool.bytes],rax
	add [memory_reserved_bytes],rax
	cmp r13d,2
	je .ranges
	vkMapMemory [device],[rsi+MemoryPool.memory],0,VK_WHOLE_SIZE,0,addr rsi+MemoryPool.mapped
	test eax,eax
	jnz .release_failed
.ranges:
	test edi,edi
	jnz .dedicated_ready
	fastcall range_initialize,addr rsi+MemoryPool.ranges,[rsi+MemoryPool.bytes]
	test eax,eax
	jz .release_failed
	fastcall range_allocate,addr rsi+MemoryPool.ranges,[rbx+GpuBuffer.bytes],r15
	test rax,rax
	jz .release_failed
	jmp .bind
.reused:
	inc [memory_reuses]
.bind:
	mov [rbx+GpuBuffer.range],rax
	mov rax,[rax+RangeNode.binding]
	mov [rbx+GpuBuffer.offset],rax
.dedicated_ready:
	mov [rbx+GpuBuffer.pool],rsi
	mov rax,[rsi+MemoryPool.memory]
	mov [rbx+GpuBuffer.memory],rax
	mov rax,[rsi+MemoryPool.mapped]
	test rax,rax
	jz .mapping
	add rax,[rbx+GpuBuffer.offset]
.mapping:
	mov [rbx+GpuBuffer.mapped],rax
	mov eax,1
	ret
.release_failed:
	fastcall release_memory_pool,rsi
	test edi,edi
	jz .new_dedicated
.failed:
	xor eax,eax
	ret
endp

proc create_buffer uses rbx rsi rdi,owner,bytes,usage,addressable
	mov rbx,rcx
	mov [memory_buffer_info.size],rdx
	mov [memory_buffer_info.usage],r8d
	mov edi,r9d
	test edi,edi
	jz .create
	or [memory_buffer_info.usage],VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT
.create:
	vkCreateBuffer [device],addr memory_buffer_info,0,rbx
	test eax,eax
	jnz .failed
	mov rax,[rbx+GpuBuffer.handle]
	mov [memory_buffer_requirements.buffer],rax
	vkGetBufferMemoryRequirements2 [device],addr memory_buffer_requirements,addr memory_requirements2
	test [memory_buffer_info.usage],VK_BUFFER_USAGE_TRANSFER_DST_BIT
	jz .host_visible
	test [memory_buffer_info.usage],VK_BUFFER_USAGE_TRANSFER_SRC_BIT
	jnz .host_visible
	fastcall memory_index,[memory_requirements2.memoryRequirements.memoryTypeBits],VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_CACHED_BIT
	cmp eax,-1
	jne .type
.host_visible:
	fastcall memory_index,[memory_requirements2.memoryRequirements.memoryTypeBits],VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
	cmp eax,-1
	je .failed
.type:
	xor r9d,r9d
	test edi,edi
	jz .allocate
	mov r9d,VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT
.allocate:
	mov esi,1
	test [memory_buffer_info.usage],VK_BUFFER_USAGE_DESCRIPTOR_HEAP_BIT_EXT
	jz .ordinary
	mov esi,3
.ordinary:
	fastcall allocate_gpu_memory,rbx,rax,rsi,r9
	test eax,eax
	jz .failed
	vkBindBufferMemory [device],[rbx+GpuBuffer.handle],[rbx+GpuBuffer.memory],[rbx+GpuBuffer.offset]
	test eax,eax
	jnz .failed
	test edi,edi
	jz .ready
	mov rax,[rbx+GpuBuffer.handle]
	mov [memory_address_info.buffer],rax
	vkGetBufferDeviceAddress [device],addr memory_address_info
	test rax,rax
	jz .failed
	mov [rbx+GpuBuffer.address],rax
.ready:
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc mapped_buffer_range owner
	mov rax,[rcx+GpuBuffer.memory]
	mov [memory_range.memory],rax
	mov rax,[rcx+GpuBuffer.offset]
	mov [memory_range.offset],rax
	mov rax,[rcx+GpuBuffer.bytes]
	mov rdx,[rcx+GpuBuffer.pool]
	cmp [rdx+MemoryPool.dedicated],0
	je .size
	mov rax,VK_WHOLE_SIZE
.size:
	mov [memory_range.size],rax
	ret
endp

proc flush_buffer owner
	cmp [rcx+GpuBuffer.coherent],0
	jne .ready
	fastcall mapped_buffer_range,rcx
	vkFlushMappedMemoryRanges [device],1,addr memory_range
	test eax,eax
	jnz .failed
.ready:
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc invalidate_buffer owner
	cmp [rcx+GpuBuffer.coherent],0
	jne .ready
	fastcall mapped_buffer_range,rcx
	vkInvalidateMappedMemoryRanges [device],1,addr memory_range
	test eax,eax
	jnz .failed
.ready:
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc create_image uses rbx rsi,owner,info,view_info
	mov rbx,rcx
	mov rsi,r8
	vkCreateImage [device],rdx,0,rbx
	test eax,eax
	jnz .failed
	mov rax,[rbx+GpuImage.handle]
	mov [memory_image_requirements.image],rax
	vkGetImageMemoryRequirements2 [device],addr memory_image_requirements,addr memory_requirements2
	fastcall memory_index,[memory_requirements2.memoryRequirements.memoryTypeBits],VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
	cmp eax,-1
	jne .allocate
	fastcall memory_index,[memory_requirements2.memoryRequirements.memoryTypeBits],0
	cmp eax,-1
	je .failed
.allocate:
	fastcall allocate_gpu_memory,rbx,rax,2,0
	test eax,eax
	jz .failed
	vkBindImageMemory [device],[rbx+GpuImage.handle],[rbx+GpuImage.memory],[rbx+GpuImage.offset]
	test eax,eax
	jnz .failed
	mov rax,[rbx+GpuImage.handle]
	mov [rsi+VkImageViewCreateInfo.image],rax
	vkCreateImageView [device],rsi,0,addr rbx+GpuImage.view
	test eax,eax
	jnz .failed
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc release_memory_pool uses rbx,pool
	mov rbx,rcx
	cmp [rbx+MemoryPool.mapped],0
	je .free
	vkUnmapMemory [device],[rbx+MemoryPool.memory]
.free:
	cmp [rbx+MemoryPool.memory],0
	je .done
	vkFreeMemory [device],[rbx+MemoryPool.memory],0
	dec [memory_live_allocations]
	mov rax,[rbx+MemoryPool.bytes]
	sub [memory_reserved_bytes],rax
.done:
	cmp [rbx+MemoryPool.dedicated],0
	jne .clear
	fastcall range_destroy,addr rbx+MemoryPool.ranges
.clear:
	mov [rbx+MemoryPool.memory],0
	mov [rbx+MemoryPool.mapped],0
	ret
endp

proc execute_gpu_delete uses rbx,record
	mov rbx,rcx
	cmp [rbx+GpuDelete.kind],2
	jne .buffer
	cmp [rbx+GpuDelete.view],0
	je .image
	vkDestroyImageView [device],[rbx+GpuDelete.view],0
.image:
	cmp [rbx+GpuDelete.handle],0
	je .memory
	vkDestroyImage [device],[rbx+GpuDelete.handle],0
	jmp .memory
.buffer:
	cmp [rbx+GpuDelete.handle],0
	je .memory
	vkDestroyBuffer [device],[rbx+GpuDelete.handle],0
.memory:
	cmp [rbx+GpuDelete.range],0
	je .dedicated
	fastcall range_free,[rbx+GpuDelete.range]
	ret
.dedicated:
	mov rcx,[rbx+GpuDelete.pool]
	test rcx,rcx
	jz .done
	fastcall release_memory_pool,rcx
.done:
	ret
endp

proc collect_gpu_deletes uses rbx
.record:
	cmp [gpu_delete_count],0
	je .done
	mov eax,[gpu_delete_head]
	imul eax,sizeof.GpuDelete
	mov rbx,[gpu_deletes]
	add rbx,rax
	mov rax,[rbx+GpuDelete.retirement]
	cmp rax,[completed_retirement]
	ja .done
	fastcall execute_gpu_delete,rbx
	inc [gpu_delete_head]
	and [gpu_delete_head],GPU_DELETE_LIMIT-1
	dec [gpu_delete_count]
	jmp .record
.done:
	ret
endp

proc retire_gpu_resource uses rbx rsi rdi,owner,kind
	mov rbx,rcx
	mov edi,edx
	mov rax,[rbx+GpuBuffer.handle]
	or rax,[rbx+GpuBuffer.memory]
	jz .done
	cmp [gpu_delete_count],GPU_DELETE_LIMIT
	jb .slot
	fastcall wait_retirement,[retirement_value]
	test eax,eax
	jnz .wait_failed
	fastcall collect_gpu_deletes
.slot:
	mov eax,[gpu_delete_tail]
	imul eax,sizeof.GpuDelete
	mov rsi,[gpu_deletes]
	add rsi,rax
	mov rax,[retirement_value]
	mov [rsi+GpuDelete.retirement],rax
	mov rax,[rbx+GpuBuffer.handle]
	mov [rsi+GpuDelete.handle],rax
	mov [rsi+GpuDelete.kind],edi
	mov [rsi+GpuDelete.view],0
	cmp edi,2
	jne .allocation
	mov rax,[rbx+GpuImage.view]
	mov [rsi+GpuDelete.view],rax
.allocation:
	mov rax,[rbx+GpuBuffer.pool]
	mov [rsi+GpuDelete.pool],rax
	mov rax,[rbx+GpuBuffer.range]
	mov [rsi+GpuDelete.range],rax
	mov rdi,rbx
	mov ecx,sizeof.GpuBuffer/8
	xor eax,eax
	rep stosq
	inc [gpu_delete_tail]
	and [gpu_delete_tail],GPU_DELETE_LIMIT-1
	inc [gpu_delete_count]
	fastcall collect_gpu_deletes
.done:
	ret
.wait_failed:
	mov [gpu_error],eax
	mov [app_io_failed],1
	ret
endp

proc destroy_buffer owner
	fastcall retire_gpu_resource,rcx,1
	ret
endp
proc destroy_image owner
	fastcall retire_gpu_resource,rcx,2
	ret
endp

proc destroy_memory_pools uses rbx rsi
	fastcall collect_gpu_deletes
	mov rsi,[memory_pools]
	test rsi,rsi
	jz .done
	mov ebx,MEMORY_POOL_LIMIT
.pool:
	fastcall release_memory_pool,rsi
	add rsi,sizeof.MemoryPool
	dec ebx
	jnz .pool
.done:
	ret
endp

section '.data$pools' data readable writeable align 8
memory_pools dq 0
gpu_deletes dq 0
memory_reserved_bytes dq 0
memory_allocations dd 0
memory_live_allocations dd 0
memory_reuses dd 0
gpu_delete_count dd 0
gpu_delete_head dd 0
gpu_delete_tail dd 0
force_dedicated dd 0
force_noncoherent dd 0
buffer_pool_bytes dd 1024*1024
image_pool_bytes dd 4*1024*1024
memory_buffer_info VkBufferCreateInfo sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,sharingMode: VK_SHARING_MODE_EXCLUSIVE
memory_allocate VkMemoryAllocateInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
memory_address_flags VkMemoryAllocateFlagsInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO
memory_address_info VkBufferDeviceAddressInfo sType: VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO
memory_range VkMappedMemoryRange sType: VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
memory_buffer_requirements VkBufferMemoryRequirementsInfo2 sType: VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2
memory_image_requirements VkImageMemoryRequirementsInfo2 sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2
memory_dedicated VkMemoryDedicatedRequirements sType: VK_STRUCTURE_TYPE_MEMORY_DEDICATED_REQUIREMENTS
memory_requirements2 VkMemoryRequirements2 sType: VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2,pNext: memory_dedicated
memory_dedicated_allocate VkMemoryDedicatedAllocateInfo sType: VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO
