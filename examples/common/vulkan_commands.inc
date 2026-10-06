if definite GPU_RETIREMENT
include 'vulkan_retirement.inc'
else
; One serial command buffer. Reuse starts only after the timeline/fence completes.
section '.text$commands' code readable executable align 16
proc create_commands
	vkCreateCommandPool [device],addr pool_info,0,addr command_pool
	test eax,eax
	jnz .done
	mov rax,[command_pool]
	mov [command_allocate.commandPool],rax
	vkAllocateCommandBuffers [device],addr command_allocate,addr command_buffer
	test eax,eax
	jnz .done
	mov rax,[command_buffer]
	mov [command_submit.commandBuffer],rax
	test [active_caps],CAP_TIMELINE
	jz .fence
	vkCreateSemaphore [device],addr semaphore_info,0,addr timeline_semaphore
	test eax,eax
	jnz .done
	mov rax,[timeline_semaphore]
	mov [signal_info.semaphore],rax
	mov [submit1.signalSemaphoreCount],1
	lea rax,[timeline_submit]
	mov [submit1.pNext],rax
	mov [submit2.signalSemaphoreInfoCount],1
	xor eax,eax
	ret
.fence:
	vkCreateFence [device],addr fence_info,0,addr completion_fence
.done:
	ret
endp

proc begin_commands
	vkResetCommandBuffer [command_buffer],0
	test eax,eax
	jnz .done
	vkBeginCommandBuffer [command_buffer],addr command_begin
.done:
	ret
endp

proc submit_commands
	vkEndCommandBuffer [command_buffer]
	test eax,eax
	jnz .done
	test [active_caps],CAP_TIMELINE
	jz .reset_fence
	inc [completion_value]
	mov rax,[completion_value]
	mov [signal_info.value],rax
	jmp .submit
.reset_fence:
	vkResetFences [device],1,addr completion_fence
	test eax,eax
	jnz .done
.submit:
	test [active_caps],CAP_SYNC
	jz .legacy
	vkQueueSubmit2 [queue],1,addr submit2,[completion_fence]
	jmp .submitted
.legacy:
	vkQueueSubmit [queue],1,addr submit1,[completion_fence]
.submitted:
	test eax,eax
	jnz .done
	test [active_caps],CAP_TIMELINE
	jz .wait_fence
	vkWaitSemaphores [device],addr timeline_wait,5000000000
	ret
.wait_fence:
	vkWaitForFences [device],1,addr completion_fence,VK_TRUE,5000000000
.done:
	ret
endp

proc destroy_commands
	iterate <handle,function>,timeline_semaphore,vkDestroySemaphore,completion_fence,vkDestroyFence,command_pool,vkDestroyCommandPool
		cmp [handle],0
		je .skip#handle
		function [device],[handle],0
		mov [handle],0
	.skip#handle:
	end iterate
	mov [command_buffer],0
	ret
endp

section '.data$commands' data readable writeable align 8
command_pool dq 0
command_buffer dq 0
timeline_semaphore dq 0
completion_fence dq 0
completion_value dq 0
pool_info VkCommandPoolCreateInfo sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
command_allocate VkCommandBufferAllocateInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,commandBufferCount: 1
command_begin VkCommandBufferBeginInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
semaphore_type VkSemaphoreTypeCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,semaphoreType: VK_SEMAPHORE_TYPE_TIMELINE
semaphore_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,pNext: semaphore_type
fence_info VkFenceCreateInfo sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
signal_info VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
command_submit VkCommandBufferSubmitInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO
submit2 VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,commandBufferInfoCount: 1,pCommandBufferInfos: command_submit,pSignalSemaphoreInfos: signal_info
timeline_submit VkTimelineSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,signalSemaphoreValueCount: 1,pSignalSemaphoreValues: completion_value
submit1 VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,commandBufferCount: 1,pCommandBuffers: command_buffer,pSignalSemaphores: timeline_semaphore
timeline_wait VkSemaphoreWaitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,semaphoreCount: 1,pSemaphores: timeline_semaphore,pValues: completion_value
end if
