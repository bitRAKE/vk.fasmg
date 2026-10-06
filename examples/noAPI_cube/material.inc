section '.text$cube_material' code readable executable align 16
proc create_heap uses rbx rsi rdi,owner,bind_info,sizes,alignments
	; sizes = descriptor/reserved/max; alignments = descriptor/heap.
	mov rbx,rcx
	mov rsi,rdx
	mov rdi,r9
	mov rax,[r8]
	mov rcx,[rdi]
	dec rcx
	add rax,rcx
	not rcx
	and rax,rcx
	mov [rsi+VkBindHeapInfoEXT.reservedRangeOffset],rax
	mov rcx,[r8+8]
	mov [rsi+VkBindHeapInfoEXT.reservedRangeSize],rcx
	add rax,rcx
	cmp rax,[r8+16]
	ja .failed
	mov [rsi+VkBindHeapInfoEXT.heapRange.size],rax
	mov rdx,[rdi+8]
	dec rdx
	add rdx,rax
	fastcall create_buffer,rbx,rdx,VK_BUFFER_USAGE_DESCRIPTOR_HEAP_BIT_EXT or VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1
	test eax,eax
	jz .failed
	mov rax,[rbx+GpuBuffer.address]
	mov rcx,[rdi+8]
	dec rcx
	add rax,rcx
	not rcx
	and rax,rcx
	mov [rsi+VkBindHeapInfoEXT.heapRange.address],rax
	sub rax,[rbx+GpuBuffer.address]
	add rax,[rbx+GpuBuffer.mapped]
	; Return the aligned CPU descriptor destination, leaving ownership intact.
	ret
.failed:
	xor eax,eax
	ret
endp

proc create_material uses rbx rsi rdi
	xor r9d,r9d
	test [active_caps],CAP_ADDRESS
	setnz r9b
	fastcall create_buffer,addr data_buffer,1024+TEXTURE_BYTES,VK_BUFFER_USAGE_VERTEX_BUFFER_BIT or VK_BUFFER_USAGE_INDEX_BUFFER_BIT or VK_BUFFER_USAGE_TRANSFER_SRC_BIT or VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,r9
	test eax,eax
	jz .failed
	mov rdi,[data_buffer.mapped]
	lea rsi,[cube_vertices]
	mov ecx,CUBE_VERTEX_BYTES/4
	rep movsd
	lea rsi,[cube_indices]
	mov ecx,CUBE_INDEX_BYTES/4
	rep movsd
	mov rdi,[data_buffer.mapped]
	add rdi,1024
	lea rsi,[texture_pixels]
	mov ecx,TEXTURE_BYTES/4
	rep movsd
	fastcall flush_buffer,addr data_buffer
	test eax,eax
	jz .failed
	mov rax,[data_buffer.address]
	mov [cube_root.vertices],rax
	add rax,CUBE_VERTEX_BYTES
	mov [address_index.addressRange.address],rax
	mov rax,[data_buffer.address]
	add rax,1024
	mov [upload_address_region.addressRange.address],rax
	fastcall create_image,addr texture_image,addr texture_image_info,addr texture_view_info
	test eax,eax
	jz .failed
	require_vk fastcall begin_commands
	fastcall transition_image,[texture_image.handle],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,0,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT
	test [active_caps],CAP_COMMAND_ADDRESS
	jz .copy_buffer
	mov rax,[texture_image.handle]
	mov [upload_address.image],rax
	vkCmdCopyMemoryToImageKHR [command_buffer],addr upload_address
	jmp .sampled
.copy_buffer:
	vkCmdCopyBufferToImage [command_buffer],[data_buffer.handle],[texture_image.handle],VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,1,addr upload_region
.sampled:
	fastcall transition_image,[texture_image.handle],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_ACCESS_SHADER_READ_BIT
	require_vk fastcall submit_commands
	test [active_caps],CAP_HEAP
	jnz .heaps
	require_vk vkCreateSampler [device],addr sampler_info,0,addr sampler
	require_vk vkCreateDescriptorSetLayout [device],addr descriptor_layout_info,0,addr descriptor_layout
	mov rax,[descriptor_layout]
	mov [descriptor_allocate.pSetLayouts],0
	lea rax,[descriptor_layout]
	mov [descriptor_allocate.pSetLayouts],rax
	require_vk vkCreateDescriptorPool [device],addr descriptor_pool_info,0,addr descriptor_pool
	mov rax,[descriptor_pool]
	mov [descriptor_allocate.descriptorPool],rax
	require_vk vkAllocateDescriptorSets [device],addr descriptor_allocate,addr descriptor_set
	mov rax,[texture_image.view]
	mov [descriptor_image.imageView],rax
	mov rax,[sampler]
	mov [descriptor_sampler.sampler],rax
	mov rax,[descriptor_set]
	mov [texture_write.dstSet],rax
	mov [sampler_write.dstSet],rax
	vkUpdateDescriptorSets [device],2,addr descriptor_writes,0,0
	mov eax,1
	ret
.heaps:
	cmp [heap_properties.maxPushDataSize],ROOT_BYTES
	jb .failed
	mov rax,[heap_properties.imageDescriptorSize]
	mov [resource_sizes],rax
	mov rax,[heap_properties.minResourceHeapReservedRange]
	mov [resource_sizes+8],rax
	mov rax,[heap_properties.maxResourceHeapSize]
	mov [resource_sizes+16],rax
	mov rax,[heap_properties.imageDescriptorAlignment]
	cmp rax,[heap_properties.bufferDescriptorAlignment]
	jae .resource_alignment
	mov rax,[heap_properties.bufferDescriptorAlignment]
.resource_alignment:
	mov [resource_alignments],rax
	mov rax,[heap_properties.resourceHeapAlignment]
	mov [resource_alignments+8],rax
	fastcall create_heap,addr resource_heap,addr resource_bind,addr resource_sizes,addr resource_alignments
	test rax,rax
	jz .failed
	mov [heap_destination.address],rax
	mov rax,[heap_properties.imageDescriptorSize]
	mov [heap_destination.size],rax
	lea rax,[heap_image]
	mov qword [texture_descriptor.data],rax
	require_vk vkWriteResourceDescriptorsEXT [device],1,addr texture_descriptor,addr heap_destination
	fastcall flush_buffer,addr resource_heap
	test eax,eax
	jz .failed
	mov rax,[heap_properties.samplerDescriptorSize]
	mov [sampler_sizes],rax
	mov rax,[heap_properties.minSamplerHeapReservedRange]
	mov [sampler_sizes+8],rax
	mov rax,[heap_properties.maxSamplerHeapSize]
	mov [sampler_sizes+16],rax
	mov rax,[heap_properties.samplerDescriptorAlignment]
	mov [sampler_alignments],rax
	mov rax,[heap_properties.samplerHeapAlignment]
	mov [sampler_alignments+8],rax
	fastcall create_heap,addr sampler_heap,addr sampler_bind,addr sampler_sizes,addr sampler_alignments
	test rax,rax
	jz .failed
	mov [heap_destination.address],rax
	mov rax,[heap_properties.samplerDescriptorSize]
	mov [heap_destination.size],rax
	require_vk vkWriteSamplerDescriptorsEXT [device],1,addr sampler_info,addr heap_destination
	fastcall flush_buffer,addr sampler_heap
	test eax,eax
	jz .failed
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc destroy_material
	iterate <handle,function>,descriptor_pool,vkDestroyDescriptorPool,descriptor_layout,vkDestroyDescriptorSetLayout,sampler,vkDestroySampler
		cmp [handle],0
		je .skip#handle
		function [device],[handle],0
		mov [handle],0
	.skip#handle:
	end iterate
	fastcall destroy_image,addr texture_image
	fastcall destroy_buffer,addr data_buffer
	fastcall destroy_buffer,addr resource_heap
	fastcall destroy_buffer,addr sampler_heap
	ret
endp

section '.data$cube_material' data readable writeable align 8
data_buffer GpuBuffer
texture_image GpuImage
resource_heap GpuBuffer
sampler_heap GpuBuffer
resource_sizes rq 3
resource_alignments rq 2
sampler_sizes rq 3
sampler_alignments rq 2
sampler dq 0
descriptor_layout dq 0
descriptor_pool dq 0
descriptor_set dq 0
vertex_offset dq 0
texture_image_info VkImageCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,imageType: VK_IMAGE_TYPE_2D,extent: <width: 256,height: 256,depth: 1>,mipLevels: 1,arrayLayers: 1,samples: VK_SAMPLE_COUNT_1_BIT,tiling: VK_IMAGE_TILING_OPTIMAL,usage: VK_IMAGE_USAGE_SAMPLED_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT
texture_view_info VkImageViewCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,viewType: VK_IMAGE_VIEW_TYPE_2D,subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
upload_region VkBufferImageCopy bufferOffset: 1024,imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageExtent: <width: 256,height: 256,depth: 1>
upload_address_region VkDeviceMemoryImageCopyKHR sType: VK_STRUCTURE_TYPE_DEVICE_MEMORY_IMAGE_COPY_KHR,addressRange: <size: TEXTURE_BYTES>,addressFlags: VK_ADDRESS_COMMAND_FULLY_BOUND_BIT_KHR or VK_ADDRESS_COMMAND_STORAGE_BUFFER_USAGE_BIT_KHR,imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,imageExtent: <width: 256,height: 256,depth: 1>
upload_address VkCopyDeviceMemoryImageInfoKHR sType: VK_STRUCTURE_TYPE_COPY_DEVICE_MEMORY_IMAGE_INFO_KHR,regionCount: 1,pRegions: upload_address_region
address_index VkBindIndexBuffer3InfoKHR sType: VK_STRUCTURE_TYPE_BIND_INDEX_BUFFER_3_INFO_KHR,addressRange: <size: CUBE_INDEX_BYTES>,addressFlags: VK_ADDRESS_COMMAND_FULLY_BOUND_BIT_KHR or VK_ADDRESS_COMMAND_STORAGE_BUFFER_USAGE_BIT_KHR,indexType: VK_INDEX_TYPE_UINT16
sampler_info VkSamplerCreateInfo sType: VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,magFilter: VK_FILTER_NEAREST,minFilter: VK_FILTER_NEAREST,mipmapMode: VK_SAMPLER_MIPMAP_MODE_NEAREST,addressModeU: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,addressModeV: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,addressModeW: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
descriptor_bindings:
	VkDescriptorSetLayoutBinding binding: 0,descriptorType: VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,descriptorCount: 1,stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT
	VkDescriptorSetLayoutBinding binding: 1,descriptorType: VK_DESCRIPTOR_TYPE_SAMPLER,descriptorCount: 1,stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT
descriptor_layout_info VkDescriptorSetLayoutCreateInfo sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,bindingCount: 2,pBindings: descriptor_bindings
descriptor_pool_sizes:
	VkDescriptorPoolSize type: VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,descriptorCount: 1
	VkDescriptorPoolSize type: VK_DESCRIPTOR_TYPE_SAMPLER,descriptorCount: 1
descriptor_pool_info VkDescriptorPoolCreateInfo sType: VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,maxSets: 1,poolSizeCount: 2,pPoolSizes: descriptor_pool_sizes
descriptor_allocate VkDescriptorSetAllocateInfo sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,descriptorSetCount: 1
descriptor_image VkDescriptorImageInfo imageLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
descriptor_sampler VkDescriptorImageInfo
descriptor_writes:
texture_write VkWriteDescriptorSet sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,dstBinding: 0,descriptorCount: 1,descriptorType: VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,pImageInfo: descriptor_image
sampler_write VkWriteDescriptorSet sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,dstBinding: 1,descriptorCount: 1,descriptorType: VK_DESCRIPTOR_TYPE_SAMPLER,pImageInfo: descriptor_sampler
resource_bind VkBindHeapInfoEXT sType: VK_STRUCTURE_TYPE_BIND_HEAP_INFO_EXT
sampler_bind VkBindHeapInfoEXT sType: VK_STRUCTURE_TYPE_BIND_HEAP_INFO_EXT
heap_destination VkHostAddressRangeEXT
heap_image VkImageDescriptorInfoEXT sType: VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,pView: texture_view_info,layout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
texture_descriptor VkResourceDescriptorInfoEXT sType: VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,type: VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
