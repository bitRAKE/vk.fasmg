; One serial command buffer, and the two counters every submission advances.
; Public work completion and private command/resource retirement are distinct:
; a second, signal-only batch orders retirement after the work batch's signals.
; Without timeline semaphores a fence tracks the same submission sequence.
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
	route CAP_SYNC
		mov rax,[command_buffer]
		mov [command_submit.commandBuffer],rax
	end route
	route CAP_TIMELINE,.fence
		vkCreateSemaphore [device],addr semaphore_info,0,addr timeline_semaphore
		test eax,eax
		jnz .done
		vkCreateSemaphore [device],addr semaphore_info,0,addr retirement_semaphore
		test eax,eax
		jnz .done
		route CAP_SYNC
			mov rax,[timeline_semaphore]
			mov [signal_info.semaphore],rax
			mov rax,[retirement_semaphore]
			mov [retirement_signal.semaphore],rax
		end route
		xor eax,eax
		ret
	end route
	alternate CAP_TIMELINE
	.fence:
		vkCreateFence [device],addr fence_info,0,addr completion_fence
	end alternate
.done:
	ret
endp

proc reserve_submission
	inc [completion_value]
	inc [retirement_value]
	route CAP_SYNC
		route CAP_TIMELINE
			mov rax,[completion_value]
			mov [signal_info.value],rax
			mov rax,[retirement_value]
			mov [retirement_signal.value],rax
		end route
	end route
	ret
endp

proc cancel_submission
	dec [completion_value]
	dec [retirement_value]
	ret
endp

proc poll_retirement
	route CAP_TIMELINE,.fences
		vkGetSemaphoreCounterValue [device],[retirement_semaphore],addr completed_retirement
		test eax,eax
		jnz .done
		jmp .collect
	end route
	alternate CAP_TIMELINE
	.fences:
		fastcall wsi_poll_fences
		test eax,eax
		jnz .done
	end alternate
.collect:
	fastcall collect_gpu_deletes
	xor eax,eax
.done:
	ret
endp

proc wait_retirement value
	cmp rcx,[completed_retirement]
	jbe .ready
	route CAP_TIMELINE,.fences
		mov [retirement_wait_value],rcx
		vkWaitSemaphores [device],addr retirement_wait,5000000000
		test eax,eax
		jnz .done
		mov rax,[retirement_wait_value]
		mov [completed_retirement],rax
		jmp .ready
	end route
	alternate CAP_TIMELINE
	.fences:
		fastcall wsi_wait_work
		test eax,eax
		jnz .done
	end alternate
.ready:
	fastcall collect_gpu_deletes
	xor eax,eax
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

; Serial: returns once the submission has retired.
proc submit_commands
	vkEndCommandBuffer [command_buffer]
	test eax,eax
	jnz .done
	fastcall reserve_submission
	route CAP_TIMELINE,.fence
		route CAP_SYNC,.timeline_legacy
			vkQueueSubmit2 [queue],2,addr serial_submit2,0
			jmp .submitted
		end route
		alternate CAP_SYNC
		.timeline_legacy:
			vkQueueSubmit [queue],2,addr serial_submit1,0
			jmp .submitted
		end alternate
	end route
	alternate CAP_TIMELINE
	.fence:
		vkResetFences [device],1,addr completion_fence
		test eax,eax
		jnz .cancel
		route CAP_SYNC,.legacy
			vkQueueSubmit2 [queue],1,addr serial_fence_submit2,[completion_fence]
			jmp .submitted
		end route
		alternate CAP_SYNC
		.legacy:
			vkQueueSubmit [queue],1,addr serial_fence_submit1,[completion_fence]
		end alternate
	end alternate
.submitted:
	test eax,eax
	jnz .cancel
	mov rax,[retirement_value]
	mov [serial_retirement],rax
	route CAP_TIMELINE,.wait_fence
		fastcall wait_retirement,rax
		ret
	end route
	alternate CAP_TIMELINE
	.wait_fence:
		vkWaitForFences [device],1,addr completion_fence,VK_TRUE,5000000000
		test eax,eax
		jnz .done
		mov rax,[serial_retirement]
		mov [completed_retirement],rax
		fastcall collect_gpu_deletes
		xor eax,eax
		ret
	end alternate
.cancel:
	mov [retirement_error],eax
	fastcall cancel_submission
	mov eax,[retirement_error]
.done:
	ret
endp

proc destroy_commands
	iterate <handle,function>,timeline_semaphore,vkDestroySemaphore,retirement_semaphore,vkDestroySemaphore,completion_fence,vkDestroyFence,command_pool,vkDestroyCommandPool
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
retirement_semaphore dq 0
completion_fence dq 0
completion_value dq 0
retirement_value dq 0
completed_retirement dq 0
serial_retirement dq 0
retirement_wait_value dq 0
retirement_error dd 0
pool_info VkCommandPoolCreateInfo sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
command_allocate VkCommandBufferAllocateInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,commandBufferCount: 1
command_begin VkCommandBufferBeginInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
fence_info VkFenceCreateInfo sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
route CAP_TIMELINE
	semaphore_type VkSemaphoreTypeCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,semaphoreType: VK_SEMAPHORE_TYPE_TIMELINE
	semaphore_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,pNext: semaphore_type
	retirement_wait VkSemaphoreWaitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,semaphoreCount: 1,pSemaphores: retirement_semaphore,pValues: retirement_wait_value
end route
route CAP_SYNC
	command_submit VkCommandBufferSubmitInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO
	route CAP_TIMELINE
		signal_info VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
		retirement_signal VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
		serial_submit2:
			VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,commandBufferInfoCount: 1,pCommandBufferInfos: command_submit,signalSemaphoreInfoCount: 1,pSignalSemaphoreInfos: signal_info
			VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,signalSemaphoreInfoCount: 1,pSignalSemaphoreInfos: retirement_signal
	end route
	alternate CAP_TIMELINE
		serial_fence_submit2 VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,commandBufferInfoCount: 1,pCommandBufferInfos: command_submit
	end alternate
end route
alternate CAP_SYNC
	route CAP_TIMELINE
		serial_timeline VkTimelineSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,signalSemaphoreValueCount: 1,pSignalSemaphoreValues: completion_value
		serial_retirement_timeline VkTimelineSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,signalSemaphoreValueCount: 1,pSignalSemaphoreValues: retirement_value
		serial_submit1:
			VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,pNext: serial_timeline,commandBufferCount: 1,pCommandBuffers: command_buffer,signalSemaphoreCount: 1,pSignalSemaphores: timeline_semaphore
			VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,pNext: serial_retirement_timeline,signalSemaphoreCount: 1,pSignalSemaphores: retirement_semaphore
	end route
	alternate CAP_TIMELINE
		serial_fence_submit1 VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,commandBufferCount: 1,pCommandBuffers: command_buffer
	end alternate
end alternate
