; Memory for the machine. An application of this kind makes a handful of
; buffers, once, and keeps them until it ends; so each is its own allocation,
; and nothing here pools, splits or defers. A buffer is asked for by who
; touches it:
;
;	MEMORY_DEVICE		only shaders: device-local, never mapped
;	MEMORY_UPLOAD		the CPU writes it and the device reads it: mapped
;	MEMORY_READBACK		the device writes it and the CPU reads it: mapped,
;				and in cached memory, which reads at memory's speed
;
; Every buffer has a device address, since an address is how anything of the
; machine's reaches anything.
;
;	create_buffer	owner, bytes, usage, domain	nonzero when it stands
;	flush_buffer	owner		after the CPU wrote, before the device reads
;	invalidate_buffer owner		after the device wrote, before the CPU reads
;	destroy_buffer	owner		the device has finished with it: the caller's to know
;	create_image	owner, info, view_info	device-local, with its view
;	destroy_image	owner
;
; Include after the context: this reads the memory types it found.
MEMORY_DEVICE := 0
MEMORY_UPLOAD := 1
MEMORY_READBACK := 2
MEMORY_DOMAINS := 3

struct GpuBuffer
	handle dq 0
	memory dq 0
	mapped dq 0			; none for MEMORY_DEVICE
	bytes dq 0			; as asked for
	allocated dq 0			; as the device gave
	address dq 0
	coherent dd 0			; mapped, and needs no flush or invalidate
	domain dd 0
ends
struct GpuImage
	handle dq 0
	memory dq 0
	view dq 0
ends

section '.text$memory' code readable executable align 16

; The first memory type among `bits` with all of `wanted` and none of
; `unwanted`, or -1.
proc memory_type uses rbx rsi,bits,wanted,unwanted
	mov ebx,ecx
	lea rsi,[memory_properties2.memoryProperties.memoryTypes]
	xor eax,eax
.type:
	cmp eax,[memory_properties2.memoryProperties.memoryTypeCount]
	jae .none
	bt ebx,eax
	jnc .next
	mov ecx,[rsi+VkMemoryType.propertyFlags]
	test ecx,r8d
	jnz .next
	and ecx,edx
	cmp ecx,edx
	je .done
.next:
	inc eax
	add rsi,sizeof.VkMemoryType
	jmp .type
.none:
	mov eax,-1
.done:
	ret
endp

; The best type among `bits` for a domain (EDX): its choices in order. Returns
; the type, or -1, and its property flags in EDX.
proc memory_choose uses rbx rsi rdi,bits,domain
	mov ebx,ecx
	lea rsi,[memory_choices]
	lea eax,[edx+edx*2]
	lea rsi,[rsi+rax*8]
	mov edi,3
.choice:
	mov edx,[rsi]
	mov r8d,[rsi+4]
	fastcall memory_type,rbx,rdx,r8
	cmp eax,-1
	jne .chosen
	add rsi,8
	dec edi
	jnz .choice
	ret
.chosen:
	imul edx,eax,sizeof.VkMemoryType
	lea rcx,[memory_properties2.memoryProperties.memoryTypes]
	mov edx,[rcx+rdx+VkMemoryType.propertyFlags]
	ret
endp

proc create_buffer uses rbx rsi,owner,bytes,usage,domain
	mov rbx,rcx
	mov [rbx+GpuBuffer.bytes],rdx
	mov [rbx+GpuBuffer.domain],r9d
	mov [memory_buffer_info.size],rdx
	or r8d,VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT
	mov [memory_buffer_info.usage],r8d
	vkCreateBuffer [device],addr memory_buffer_info,0,rbx
	test eax,eax
	jnz .failed
	mov rax,[rbx+GpuBuffer.handle]
	mov [memory_buffer_requirements.buffer],rax
	vkGetBufferMemoryRequirements2 [device],addr memory_buffer_requirements,addr memory_requirements2
	mov edx,[rbx+GpuBuffer.domain]
	fastcall memory_choose,[memory_requirements2.memoryRequirements.memoryTypeBits],rdx
	cmp eax,-1
	je .failed
	mov esi,edx
	mov [memory_allocate.memoryTypeIndex],eax
	mov rax,[memory_requirements2.memoryRequirements.size]
	mov [memory_allocate.allocationSize],rax
	vkAllocateMemory [device],addr memory_allocate,0,addr rbx+GpuBuffer.memory
	test eax,eax
	jnz .failed
	mov eax,[rbx+GpuBuffer.domain]
	lea rdx,[memory_held]
	mov rcx,[memory_allocate.allocationSize]
	mov [rbx+GpuBuffer.allocated],rcx
	add [rdx+rax*8],rcx
	inc [memory_allocations]
	vkBindBufferMemory [device],[rbx+GpuBuffer.handle],[rbx+GpuBuffer.memory],0
	test eax,eax
	jnz .failed
	mov rax,[rbx+GpuBuffer.handle]
	mov [memory_address_info.buffer],rax
	vkGetBufferDeviceAddress [device],addr memory_address_info
	test rax,rax
	jz .failed
	mov [rbx+GpuBuffer.address],rax
	cmp [rbx+GpuBuffer.domain],MEMORY_DEVICE
	je .ready
	vkMapMemory [device],[rbx+GpuBuffer.memory],0,VK_WHOLE_SIZE,0,addr rbx+GpuBuffer.mapped
	test eax,eax
	jnz .failed
	and esi,VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
	mov [rbx+GpuBuffer.coherent],esi
.ready:
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

; A buffer is its whole allocation, so the whole of it is the range.
proc flush_buffer owner
	cmp [rcx+GpuBuffer.mapped],0
	je .ready
	cmp [rcx+GpuBuffer.coherent],0
	jne .ready
	mov rax,[rcx+GpuBuffer.memory]
	mov [memory_range.memory],rax
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
	cmp [rcx+GpuBuffer.mapped],0
	je .ready
	cmp [rcx+GpuBuffer.coherent],0
	jne .ready
	mov rax,[rcx+GpuBuffer.memory]
	mov [memory_range.memory],rax
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

; Freeing the memory unmaps it.
proc destroy_buffer uses rbx rdi,owner
	mov rbx,rcx
	cmp [rbx+GpuBuffer.handle],0
	je .memory
	vkDestroyBuffer [device],[rbx+GpuBuffer.handle],0
.memory:
	cmp [rbx+GpuBuffer.memory],0
	je .clear
	vkFreeMemory [device],[rbx+GpuBuffer.memory],0
	mov eax,[rbx+GpuBuffer.domain]
	lea rdx,[memory_held]
	mov rcx,[rbx+GpuBuffer.allocated]
	sub [rdx+rax*8],rcx
.clear:
	mov rdi,rbx
	mov ecx,sizeof.GpuBuffer/8
	xor eax,eax
	rep stosq
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
	fastcall memory_choose,[memory_requirements2.memoryRequirements.memoryTypeBits],MEMORY_DEVICE
	cmp eax,-1
	je .failed
	mov [memory_image_allocate.memoryTypeIndex],eax
	mov rax,[memory_requirements2.memoryRequirements.size]
	mov [memory_image_allocate.allocationSize],rax
	vkAllocateMemory [device],addr memory_image_allocate,0,addr rbx+GpuImage.memory
	test eax,eax
	jnz .failed
	mov rax,[memory_image_allocate.allocationSize]
	add [memory_held+MEMORY_DEVICE*8],rax
	inc [memory_allocations]
	vkBindImageMemory [device],[rbx+GpuImage.handle],[rbx+GpuImage.memory],0
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

proc destroy_image uses rbx,owner
	mov rbx,rcx
	cmp [rbx+GpuImage.view],0
	je .image
	vkDestroyImageView [device],[rbx+GpuImage.view],0
.image:
	cmp [rbx+GpuImage.handle],0
	je .memory
	vkDestroyImage [device],[rbx+GpuImage.handle],0
.memory:
	cmp [rbx+GpuImage.memory],0
	je .clear
	vkFreeMemory [device],[rbx+GpuImage.memory],0
.clear:
	mov [rbx+GpuImage.view],0
	mov [rbx+GpuImage.handle],0
	mov [rbx+GpuImage.memory],0
	ret
endp

; The command and presentation modules borrowed from the examples ask, after
; every wait, for resources whose deletion was put off until the device had
; finished with them. Here nothing is deleted while frames run.
proc collect_gpu_deletes
	ret
endp

section '.data$memory' data readable writeable align 8
memory_held rq MEMORY_DOMAINS		; bytes held now, by domain (an image's stay counted)
memory_allocations dd 0
	dd 0
; A domain's choices, best first: what a type must have, and must not.
memory_choices:
	dd VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
	dd VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,0
	dd 0,0
	dd VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,0
	dd VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,0
	dd VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,0
	dd VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_CACHED_BIT,0
	dd VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,0
	dd VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,0
memory_buffer_info VkBufferCreateInfo sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,sharingMode: VK_SHARING_MODE_EXCLUSIVE
memory_address_flags VkMemoryAllocateFlagsInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,flags: VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT
memory_allocate VkMemoryAllocateInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,pNext: memory_address_flags
memory_image_allocate VkMemoryAllocateInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
memory_address_info VkBufferDeviceAddressInfo sType: VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO
memory_range VkMappedMemoryRange sType: VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,size: VK_WHOLE_SIZE
memory_buffer_requirements VkBufferMemoryRequirementsInfo2 sType: VK_STRUCTURE_TYPE_BUFFER_MEMORY_REQUIREMENTS_INFO_2
memory_image_requirements VkImageMemoryRequirementsInfo2 sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_REQUIREMENTS_INFO_2
memory_requirements2 VkMemoryRequirements2 sType: VK_STRUCTURE_TYPE_MEMORY_REQUIREMENTS_2
