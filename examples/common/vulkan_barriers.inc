; Image transitions and global memory barriers. Callers pass stage/access bits
; that exist in both forms, so one argument list serves vkCmdPipelineBarrier2
; and vkCmdPipelineBarrier; a synchronization2-only bit would need translating.
section '.text$barriers' code readable executable align 16
proc transition_image image,aspect,old_layout,new_layout,source_stage,source_access,destination_stage,destination_access
	route CAP_SYNC,.legacy
		mov [transition2.image],rcx
		mov [transition2.subresourceRange.aspectMask],edx
		mov [transition2.oldLayout],r8d
		mov [transition2.newLayout],r9d
		mov eax,dword [source_stage]
		mov [transition2.srcStageMask],rax
		mov eax,dword [destination_stage]
		mov [transition2.dstStageMask],rax
		mov eax,dword [source_access]
		mov [transition2.srcAccessMask],rax
		mov eax,dword [destination_access]
		mov [transition2.dstAccessMask],rax
		vkCmdPipelineBarrier2 [command_buffer],addr transition_dependency
		ret
	end route
	alternate CAP_SYNC
	.legacy:
		mov [transition1.image],rcx
		mov [transition1.subresourceRange.aspectMask],edx
		mov [transition1.oldLayout],r8d
		mov [transition1.newLayout],r9d
		mov eax,dword [source_access]
		mov [transition1.srcAccessMask],eax
		mov eax,dword [destination_access]
		mov [transition1.dstAccessMask],eax
		vkCmdPipelineBarrier [command_buffer],[source_stage],[destination_stage],0,0,0,0,0,1,addr transition1
		ret
	end alternate
endp

proc memory_barrier source_stage,source_access,destination_stage,destination_access
	route CAP_SYNC,.legacy
		mov eax,ecx
		mov [global_barrier2.srcStageMask],rax
		mov eax,r8d
		mov [global_barrier2.dstStageMask],rax
		mov eax,edx
		mov [global_barrier2.srcAccessMask],rax
		mov eax,r9d
		mov [global_barrier2.dstAccessMask],rax
		vkCmdPipelineBarrier2 [command_buffer],addr global_dependency
		ret
	end route
	alternate CAP_SYNC
	.legacy:
		mov [source_stage],rcx
		mov [destination_stage],r8
		mov [global_barrier1.srcAccessMask],edx
		mov [global_barrier1.dstAccessMask],r9d
		vkCmdPipelineBarrier [command_buffer],[source_stage],[destination_stage],0,1,addr global_barrier1,0,0,0,0
		ret
	end alternate
endp

section '.data$barriers' data readable writeable align 8
route CAP_SYNC
	transition2 VkImageMemoryBarrier2 sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,subresourceRange: <levelCount: 1,layerCount: 1>
	transition_dependency VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,imageMemoryBarrierCount: 1,pImageMemoryBarriers: transition2
	global_barrier2 VkMemoryBarrier2 sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER_2
	global_dependency VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,memoryBarrierCount: 1,pMemoryBarriers: global_barrier2
end route
alternate CAP_SYNC
	transition1 VkImageMemoryBarrier sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,subresourceRange: <levelCount: 1,layerCount: 1>
	global_barrier1 VkMemoryBarrier sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER
end alternate
