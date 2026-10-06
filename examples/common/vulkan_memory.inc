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

include 'vulkan_pools.inc'
