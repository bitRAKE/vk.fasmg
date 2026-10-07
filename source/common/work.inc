; Work for the device. The machine's frames are one at a time: a frame is
; recorded when the device has finished the one before. So there is one
; command buffer, recorded over and over, and one timeline, which every
; submission raises by one: the value a submission raises it to is that
; submission's name, and to ask whether it is done is to compare two numbers.
;
;	work_start	the pool, the buffer and the timeline; nonzero when they stand
;	work_begin	begin recording into command_buffer, once the device has
;			finished what it was given
;	work_submit	awaited, raised		end and submit: the work waits for the one
;			semaphore, if any, and raises the other, if any; its name is
;			then work_submitted
;	work_wait	value	until the device has done that submission
;	work_poll	how far it has got, without waiting: work_completed
;	work_stop
;
; A failure is a VkResult in gpu_error and zero returned.
;
; And what one pass wrote, the next may read:
;
;	memory_barrier	source_stage, source_access, destination_stage, destination_access
;	transition_image image, aspect, old_layout, new_layout, and the same four
WORK_PATIENCE := 5000000000		; nanoseconds the device is waited for before it is given up on

section '.text$work' code readable executable align 16

proc work_start
	mov eax,[queue_info.queueFamilyIndex]
	mov [work_pool_info.queueFamilyIndex],eax
	vkCreateCommandPool [device],addr work_pool_info,0,addr work_pool
	test eax,eax
	jnz .result
	mov rax,[work_pool]
	mov [work_allocate.commandPool],rax
	vkAllocateCommandBuffers [device],addr work_allocate,addr command_buffer
	test eax,eax
	jnz .result
	mov rax,[command_buffer]
	mov [work_commands.commandBuffer],rax
	vkCreateSemaphore [device],addr work_timeline_info,0,addr work_timeline
	test eax,eax
	jnz .result
	mov rax,[work_timeline]
	mov [work_raises.semaphore],rax
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; (Beginning a buffer of this pool empties it.)
proc work_begin
	fastcall work_wait,[work_submitted]
	test eax,eax
	jz .done
	vkBeginCommandBuffer [command_buffer],addr work_begin_info
	test eax,eax
	jnz .result
	mov eax,1
.done:
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc work_submit awaited,raised
	mov [work_awaits.semaphore],rcx
	mov [work_raises_also.semaphore],rdx
	xor eax,eax
	test rcx,rcx
	setnz al
	mov [work_batch.waitSemaphoreInfoCount],eax
	xor eax,eax
	test rdx,rdx
	setnz al
	inc eax
	mov [work_batch.signalSemaphoreInfoCount],eax
	vkEndCommandBuffer [command_buffer]
	test eax,eax
	jnz .result
	mov rax,[work_submitted]
	inc rax
	mov [work_raises.value],rax
	vkQueueSubmit2 [queue],1,addr work_batch,0
	test eax,eax
	jnz .result
	inc [work_submitted]
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc work_wait value
	cmp rcx,[work_completed]
	jbe .ready
	mov [work_awaited],rcx
	vkWaitSemaphores [device],addr work_wait_info,WORK_PATIENCE
	test eax,eax
	jnz .result			; out of patience is a failure too
	mov rax,[work_awaited]
	cmp rax,[work_completed]
	jbe .ready
	mov [work_completed],rax
.ready:
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc work_poll
	vkGetSemaphoreCounterValue [device],[work_timeline],addr work_completed
	test eax,eax
	jnz .result
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc work_stop
	cmp [work_timeline],0
	je .pool
	vkDestroySemaphore [device],[work_timeline],0
	mov [work_timeline],0
.pool:
	cmp [work_pool],0
	je .done
	vkDestroyCommandPool [device],[work_pool],0
	mov [work_pool],0
.done:
	mov [command_buffer],0
	ret
endp

; Stages and accesses go by their older, shorter names: the bits are the same.
proc memory_barrier source_stage,source_access,destination_stage,destination_access
	mov eax,ecx
	mov [work_barrier.srcStageMask],rax
	mov eax,edx
	mov [work_barrier.srcAccessMask],rax
	mov eax,r8d
	mov [work_barrier.dstStageMask],rax
	mov eax,r9d
	mov [work_barrier.dstAccessMask],rax
	vkCmdPipelineBarrier2 [command_buffer],addr work_barrier_info
	ret
endp

proc transition_image image,aspect,old_layout,new_layout,source_stage,source_access,destination_stage,destination_access
	mov [work_transition.image],rcx
	mov [work_transition.subresourceRange.aspectMask],edx
	mov [work_transition.oldLayout],r8d
	mov [work_transition.newLayout],r9d
	mov eax,dword [source_stage]
	mov [work_transition.srcStageMask],rax
	mov eax,dword [source_access]
	mov [work_transition.srcAccessMask],rax
	mov eax,dword [destination_stage]
	mov [work_transition.dstStageMask],rax
	mov eax,dword [destination_access]
	mov [work_transition.dstAccessMask],rax
	vkCmdPipelineBarrier2 [command_buffer],addr work_transition_info
	ret
endp

section '.data$work' data readable writeable align 8
work_pool dq 0
command_buffer dq 0
work_timeline dq 0
work_submitted dq 0			; the last submission's name
work_completed dq 0			; the last one known to be done
work_awaited dq 0
work_pool_info VkCommandPoolCreateInfo sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
work_allocate VkCommandBufferAllocateInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,commandBufferCount: 1
work_begin_info VkCommandBufferBeginInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
work_timeline_type VkSemaphoreTypeCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,semaphoreType: VK_SEMAPHORE_TYPE_TIMELINE
work_timeline_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,pNext: work_timeline_type
work_wait_info VkSemaphoreWaitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,semaphoreCount: 1,pSemaphores: work_timeline,pValues: work_awaited
; What is waited for is an image to draw to, and all of the work waits, not
; the drawing alone: what a stamp then measures is work, never a monitor.
work_awaits VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
work_commands VkCommandBufferSubmitInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO
; The timeline always; then the other, when there is one.
work_raises VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
work_raises_also VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
work_batch VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,pWaitSemaphoreInfos: work_awaits,commandBufferInfoCount: 1,pCommandBufferInfos: work_commands,pSignalSemaphoreInfos: work_raises
work_barrier VkMemoryBarrier2 sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER_2
work_barrier_info VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,memoryBarrierCount: 1,pMemoryBarriers: work_barrier
work_transition VkImageMemoryBarrier2 sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,subresourceRange: <levelCount: 1,layerCount: 1>
work_transition_info VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,imageMemoryBarrierCount: 1,pImageMemoryBarriers: work_transition
