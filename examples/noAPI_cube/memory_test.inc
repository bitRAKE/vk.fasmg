; GPU lifetime probe: hold a submission behind a host-signaled timeline, destroy
; its source buffer, and prove that its range cannot be recycled prematurely.
section '.text$cube_memory_test' code readable executable align 16
proc memory_test uses rbx rsi rdi
	require_vk fastcall wsi_wait_work
	fastcall create_buffer,addr test_source,4096,VK_BUFFER_USAGE_TRANSFER_SRC_BIT or VK_BUFFER_USAGE_TRANSFER_DST_BIT,0
	test eax,eax
	jz .failed
	fastcall create_buffer,addr test_destination,4096,VK_BUFFER_USAGE_TRANSFER_DST_BIT,0
	test eax,eax
	jz .failed
	mov rax,[test_source.memory]
	mov [test_old_memory],rax
	mov rax,[test_source.offset]
	mov [test_old_offset],rax
	mov rax,[test_source.pool]
	mov eax,[rax+MemoryPool.dedicated]
	mov [test_was_dedicated],eax
	mov rax,[capture_command_buffer]
	mov [command_buffer],rax
	require_vk fastcall begin_commands
	vkCmdFillBuffer [command_buffer],[test_source.handle],0,4096,1234ABCDh
	fastcall memory_barrier,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_READ_BIT
	vkCmdCopyBuffer [command_buffer],[test_source.handle],[test_destination.handle],1,addr test_copy
	fastcall memory_barrier,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT
	test [active_caps],CAP_TIMELINE
	jz .fence
	require_vk vkCreateSemaphore [device],addr semaphore_info,0,addr test_gate
	mov rax,[test_gate]
	mov [test_gate_wait.semaphore],rax
	mov [test_gate_signal.semaphore],rax
	require_vk vkEndCommandBuffer [command_buffer]
	fastcall reserve_submission
	mov [test_reserved],1
	test [active_caps],CAP_SYNC
	jz .submit1
	vkQueueSubmit2 [queue],2,addr test_submit2,0
	jmp .submitted
.submit1:
	vkQueueSubmit [queue],2,addr test_submit1,0
.submitted:
	test eax,eax
	jnz .failed
	mov [test_reserved],0
	mov rax,[retirement_value]
	mov [serial_retirement],rax
	fastcall destroy_buffer,addr test_source
	cmp [gpu_delete_count],0
	je .failed
	fastcall create_buffer,addr test_other,4096,VK_BUFFER_USAGE_TRANSFER_SRC_BIT or VK_BUFFER_USAGE_TRANSFER_DST_BIT,0
	test eax,eax
	jz .failed
	mov rax,[test_other.memory]
	cmp rax,[test_old_memory]
	jne .quarantined
	mov rax,[test_other.offset]
	cmp rax,[test_old_offset]
	je .failed
.quarantined:
	mov [test_quarantine],1
	require_vk vkSignalSemaphore [device],addr test_gate_signal
	mov [test_gate_released],1
	require_vk fastcall wait_retirement,[retirement_value]
	jmp .payload
.fence:
	require_vk fastcall submit_commands
.payload:
	fastcall invalidate_buffer,addr test_destination
	test eax,eax
	jz .failed
	mov rsi,[test_destination.mapped]
	mov ecx,1024
.word:
	cmp dword [rsi],1234ABCDh
	jne .failed
	add rsi,4
	loop .word
	fastcall destroy_buffer,addr test_source
	fastcall destroy_buffer,addr test_destination
	fastcall destroy_buffer,addr test_other
	fastcall create_buffer,addr test_recycled,4096,VK_BUFFER_USAGE_TRANSFER_SRC_BIT or VK_BUFFER_USAGE_TRANSFER_DST_BIT,0
	test eax,eax
	jz .failed
	cmp [test_was_dedicated],0
	jne .passed
	mov rax,[test_recycled.memory]
	cmp rax,[test_old_memory]
	jne .failed
	mov rax,[test_recycled.offset]
	cmp rax,[test_old_offset]
	jne .failed
.passed:
	fastcall wsprintfW,addr title_text,<W,'[cube allocator] quarantine=%u recycled=1 payload=ok',13,10>,[test_quarantine]
	fastcall OutputDebugStringW,addr title_text
	jmp .cleanup
.failed:
	mov [app_io_failed],1
	fastcall OutputDebugStringW,<W,'[cube allocator] FAILED lifetime or payload check',13,10>
.cleanup:
	cmp [test_reserved],0
	je .gate
	fastcall cancel_submission
.gate:
	cmp [test_gate],0
	je .buffers
	cmp [test_gate_released],0
	jne .wait
	vkSignalSemaphore [device],addr test_gate_signal
.wait:
	fastcall wait_retirement,[retirement_value]
	vkDestroySemaphore [device],[test_gate],0
	mov [test_gate],0
.buffers:
	iterate owner,test_source,test_destination,test_other,test_recycled
		fastcall destroy_buffer,addr owner
	end iterate
	fastcall write_report
	ret
endp

section '.data$cube_memory_test' data readable writeable align 8
test_source GpuBuffer
test_destination GpuBuffer
test_other GpuBuffer
test_recycled GpuBuffer
test_old_memory dq 0
test_old_offset dq 0
test_gate dq 0
test_was_dedicated dd 0
test_reserved dd 0
test_gate_released dd 0
test_quarantine dd 0
test_copy VkBufferCopy size: 4096
test_gate_value dq 1
test_gate_stage dd VK_PIPELINE_STAGE_ALL_COMMANDS_BIT
test_gate_wait VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,value: 1,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
test_gate_signal VkSemaphoreSignalInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SIGNAL_INFO,value: 1
test_submit2:
	VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,waitSemaphoreInfoCount: 1,pWaitSemaphoreInfos: test_gate_wait,commandBufferInfoCount: 1,pCommandBufferInfos: command_submit,signalSemaphoreInfoCount: 1,pSignalSemaphoreInfos: signal_info
	VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,signalSemaphoreInfoCount: 1,pSignalSemaphoreInfos: retirement_signal
test_timeline VkTimelineSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,waitSemaphoreValueCount: 1,pWaitSemaphoreValues: test_gate_value,signalSemaphoreValueCount: 1,pSignalSemaphoreValues: completion_value
test_submit1:
	VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,pNext: test_timeline,waitSemaphoreCount: 1,pWaitSemaphores: test_gate,pWaitDstStageMask: test_gate_stage,commandBufferCount: 1,pCommandBuffers: command_buffer,signalSemaphoreCount: 1,pSignalSemaphores: timeline_semaphore
	VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,pNext: serial_retirement_timeline,signalSemaphoreCount: 1,pSignalSemaphores: retirement_semaphore
