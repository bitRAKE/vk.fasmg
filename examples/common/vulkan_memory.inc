; Memory type selection uses the negotiated physical-device memory table.
section '.text$memory' code readable executable align 16
proc memory_index uses rbx rsi,bits,required
	mov ebx,ecx
	lea rsi,[memory_properties2.memoryProperties.memoryTypes]
	xor eax,eax
.type:
	cmp eax,[memory_properties2.memoryProperties.memoryTypeCount]
	jae .failed
	bt ebx,eax
	jnc .next
	mov ecx,[rsi+VkMemoryType.propertyFlags]
	and ecx,edx
	cmp ecx,edx
	je .done
.next:
	inc eax
	add rsi,sizeof.VkMemoryType
	jmp .type
.failed:
	mov eax,-1
.done:
	ret
endp

if definite GPU_MEMORY_POOLS
include 'vulkan_pools.inc'
else
struct GpuBuffer
	handle dq 0
	memory dq 0
	mapped dq 0
	address dq 0
	coherent dd 0
	rb 4
ends

struct GpuImage
	handle dq 0
	memory dq 0
	view dq 0
ends

; Keep ownership together: partial creation can always use the matching destroyer.
proc create_buffer uses rbx rsi rdi,owner,bytes,usage,addressable
	mov rbx,rcx
	mov [memory_buffer_info.size],rdx
	mov [memory_buffer_info.usage],r8d
	mov edi,r9d
	mov [memory_allocate.pNext],0
	test edi,edi
	jz .create
	or [memory_buffer_info.usage],VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT
	lea rax,[memory_address_flags]
	mov [memory_allocate.pNext],rax
.create:
	vkCreateBuffer [device],addr memory_buffer_info,0,rbx
	test eax,eax
	jnz .failed
	vkGetBufferMemoryRequirements [device],[rbx+GpuBuffer.handle],addr memory_requirements
	; CPU reads need cached memory; coherent upload memory can be uncached.
	test [memory_buffer_info.usage],VK_BUFFER_USAGE_TRANSFER_DST_BIT
	jz .host_visible
	test [memory_buffer_info.usage],VK_BUFFER_USAGE_TRANSFER_SRC_BIT
	jnz .host_visible
	fastcall memory_index,[memory_requirements.memoryTypeBits],VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_CACHED_BIT
	cmp eax,-1
	jne .memory_type
.host_visible:
	fastcall memory_index,[memory_requirements.memoryTypeBits],VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
	cmp eax,-1
	je .failed
.memory_type:
	mov [memory_allocate.memoryTypeIndex],eax
	imul eax,sizeof.VkMemoryType
	lea rdx,[memory_properties2.memoryProperties.memoryTypes]
	mov eax,[rdx+rax+VkMemoryType.propertyFlags]
	and eax,VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
	mov [rbx+GpuBuffer.coherent],eax
	mov rax,[memory_requirements.size]
	mov [memory_allocate.allocationSize],rax
	vkAllocateMemory [device],addr memory_allocate,0,addr rbx+GpuBuffer.memory
	test eax,eax
	jnz .failed
	vkBindBufferMemory [device],[rbx+GpuBuffer.handle],[rbx+GpuBuffer.memory],0
	test eax,eax
	jnz .failed
	vkMapMemory [device],[rbx+GpuBuffer.memory],0,VK_WHOLE_SIZE,0,addr rbx+GpuBuffer.mapped
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

proc flush_buffer owner
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

proc destroy_buffer uses rbx,owner
	mov rbx,rcx
	cmp [rbx+GpuBuffer.mapped],0
	je .buffer
	vkUnmapMemory [device],[rbx+GpuBuffer.memory]
.buffer:
	cmp [rbx+GpuBuffer.handle],0
	je .memory
	vkDestroyBuffer [device],[rbx+GpuBuffer.handle],0
.memory:
	cmp [rbx+GpuBuffer.memory],0
	je .done
	vkFreeMemory [device],[rbx+GpuBuffer.memory],0
.done:
	mov [rbx+GpuBuffer.handle],0
	mov [rbx+GpuBuffer.memory],0
	mov [rbx+GpuBuffer.mapped],0
	mov [rbx+GpuBuffer.address],0
	ret
endp

proc create_image uses rbx rsi,owner,info,view_info
	mov rbx,rcx
	mov rsi,r8
	vkCreateImage [device],rdx,0,rbx
	test eax,eax
	jnz .failed
	vkGetImageMemoryRequirements [device],[rbx+GpuImage.handle],addr memory_requirements
	fastcall memory_index,[memory_requirements.memoryTypeBits],VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
	cmp eax,-1
	jne .allocate
	fastcall memory_index,[memory_requirements.memoryTypeBits],0
	cmp eax,-1
	je .failed
.allocate:
	mov [memory_allocate.memoryTypeIndex],eax
	mov [memory_allocate.pNext],0
	mov rax,[memory_requirements.size]
	mov [memory_allocate.allocationSize],rax
	vkAllocateMemory [device],addr memory_allocate,0,addr rbx+GpuImage.memory
	test eax,eax
	jnz .failed
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
	je .done
	vkFreeMemory [device],[rbx+GpuImage.memory],0
.done:
	mov [rbx+GpuImage.handle],0
	mov [rbx+GpuImage.memory],0
	mov [rbx+GpuImage.view],0
	ret
endp

section '.data$memory' data readable writeable align 8
memory_requirements VkMemoryRequirements
memory_buffer_info VkBufferCreateInfo sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
memory_allocate VkMemoryAllocateInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
memory_address_flags VkMemoryAllocateFlagsInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,flags: VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT
memory_address_info VkBufferDeviceAddressInfo sType: VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO
memory_range VkMappedMemoryRange sType: VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,size: VK_WHOLE_SIZE
end if
