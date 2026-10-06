; These shared transitions use stage/access bits common to sync1 and sync2.
section '.text$barriers' code readable executable align 16
proc transition_image image,aspect,old_layout,new_layout,source_stage,source_access,destination_stage,destination_access
	mov [transition1.image],rcx
	mov [transition2.image],rcx
	mov [transition1.subresourceRange.aspectMask],edx
	mov [transition2.subresourceRange.aspectMask],edx
	mov [transition1.oldLayout],r8d
	mov [transition2.oldLayout],r8d
	mov [transition1.newLayout],r9d
	mov [transition2.newLayout],r9d
	mov eax,dword [source_stage]
	mov [transition2.srcStageMask],rax
	mov eax,dword [destination_stage]
	mov [transition2.dstStageMask],rax
	mov eax,dword [source_access]
	mov [transition1.srcAccessMask],eax
	mov [transition2.srcAccessMask],rax
	mov eax,dword [destination_access]
	mov [transition1.dstAccessMask],eax
	mov [transition2.dstAccessMask],rax
	test [active_caps],CAP_SYNC
	jz .legacy
	vkCmdPipelineBarrier2 [command_buffer],addr transition_dependency
	ret
.legacy:
	vkCmdPipelineBarrier [command_buffer],[source_stage],[destination_stage],0,0,0,0,0,1,addr transition1
	ret
endp

proc memory_barrier source_stage,source_access,destination_stage,destination_access
	mov [source_stage],rcx
	mov [destination_stage],r8
	mov eax,ecx
	mov [global_barrier2.srcStageMask],rax
	mov eax,r8d
	mov [global_barrier2.dstStageMask],rax
	mov eax,edx
	mov [global_barrier1.srcAccessMask],eax
	mov [global_barrier2.srcAccessMask],rax
	mov eax,r9d
	mov [global_barrier1.dstAccessMask],eax
	mov [global_barrier2.dstAccessMask],rax
	test [active_caps],CAP_SYNC
	jz .legacy
	vkCmdPipelineBarrier2 [command_buffer],addr global_dependency
	ret
.legacy:
	vkCmdPipelineBarrier [command_buffer],[source_stage],[destination_stage],0,1,addr global_barrier1,0,0,0,0
	ret
endp

section '.data$barriers' data readable writeable align 8
transition1 VkImageMemoryBarrier sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,subresourceRange: <levelCount: 1,layerCount: 1>
transition2 VkImageMemoryBarrier2 sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,subresourceRange: <levelCount: 1,layerCount: 1>
transition_dependency VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,imageMemoryBarrierCount: 1,pImageMemoryBarriers: transition2
global_barrier1 VkMemoryBarrier sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER
global_barrier2 VkMemoryBarrier2 sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER_2
global_dependency VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,memoryBarrierCount: 1,pMemoryBarriers: global_barrier2
