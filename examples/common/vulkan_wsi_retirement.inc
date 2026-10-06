section '.text$wsi_retirement' code readable executable align 16
proc wsi_poll_fences uses rbx rsi
	xor ebx,ebx
	lea rsi,[wsi_frames]
.frame:
	cmp ebx,[wsi_frame_count]
	jae .serial
	mov rax,[rsi+WsiFrame.retirement]
	cmp rax,[completed_retirement]
	jbe .next
	vkGetFenceStatus [device],[rsi+WsiFrame.fence]
	cmp eax,VK_NOT_READY
	je .next
	test eax,eax
	jnz .done
	mov rax,[rsi+WsiFrame.retirement]
	mov [completed_retirement],rax
.next:
	inc ebx
	add rsi,sizeof.WsiFrame
	jmp .frame
.serial:
	mov rax,[serial_retirement]
	cmp rax,[completed_retirement]
	jbe .ready
	vkGetFenceStatus [device],[completion_fence]
	cmp eax,VK_NOT_READY
	je .ready
	test eax,eax
	jnz .done
	mov rax,[serial_retirement]
	mov [completed_retirement],rax
.ready:
	xor eax,eax
.done:
	ret
endp

proc wsi_wait_work uses rbx rsi
	test [active_caps],CAP_TIMELINE
	jz .fences
	fastcall wait_retirement,[retirement_value]
	ret
.fences:
	xor ebx,ebx
	lea rsi,[wsi_frames]
.frame:
	cmp ebx,[wsi_frame_count]
	jae .serial
	mov rax,[rsi+WsiFrame.retirement]
	cmp rax,[completed_retirement]
	jbe .next
	vkWaitForFences [device],1,addr rsi+WsiFrame.fence,VK_TRUE,5000000000
	test eax,eax
	jnz .done
	mov rax,[rsi+WsiFrame.retirement]
	mov [completed_retirement],rax
.next:
	inc ebx
	add rsi,sizeof.WsiFrame
	jmp .frame
.serial:
	mov rax,[serial_retirement]
	cmp rax,[completed_retirement]
	jbe .ready
	vkWaitForFences [device],1,addr completion_fence,VK_TRUE,5000000000
	test eax,eax
	jnz .done
	mov rax,[serial_retirement]
	mov [completed_retirement],rax
.ready:
	fastcall collect_gpu_deletes
	xor eax,eax
.done:
	ret
endp

proc wsi_wait_present_images uses rbx rsi,images,count
	mov rsi,rcx
	mov ebx,edx
.image:
	test ebx,ebx
	jz .ready
	cmp [rsi+WsiImage.pending],0
	je .next
	vkWaitForFences [device],1,addr rsi+WsiImage.presented,VK_TRUE,5000000000
	test eax,eax
	jnz .done
	mov [rsi+WsiImage.pending],0
.next:
	add rsi,sizeof.WsiImage
	dec ebx
	jmp .image
.ready:
	xor eax,eax
.done:
	ret
endp

proc wsi_destroy_retired uses rbx rsi rdi,record
	mov rbx,rcx
	lea rsi,[rbx+RetiredSwapchain.images]
	mov edi,[rbx+RetiredSwapchain.image_count]
.image:
	test edi,edi
	jz .chain
	iterate <field,function>,view,vkDestroyImageView,rendered,vkDestroySemaphore,presented,vkDestroyFence
		cmp [rsi+WsiImage.field],0
		je .skip#field
		function [device],[rsi+WsiImage.field],0
	.skip#field:
	end iterate
	add rsi,sizeof.WsiImage
	dec edi
	jmp .image
.chain:
	vkDestroySwapchainKHR [device],[rbx+RetiredSwapchain.handle],0
	mov [rbx+RetiredSwapchain.handle],0
	inc [wsi_swapchains_reclaimed]
	ret
endp

proc wsi_collect_swapchains uses rbx rsi rdi
.record:
	cmp [wsi_retired_count],0
	je .ready
	mov eax,[wsi_retired_head]
	imul eax,sizeof.RetiredSwapchain
	mov rbx,[wsi_retired]
	add rbx,rax
	mov rax,[rbx+RetiredSwapchain.handle]
	cmp rax,[wsi_replacement_hold]
	je .ready
	mov rax,[rbx+RetiredSwapchain.retirement]
	cmp rax,[completed_retirement]
	ja .ready
	lea rsi,[rbx+RetiredSwapchain.images]
	mov edi,[rbx+RetiredSwapchain.image_count]
.image:
	test edi,edi
	jz .release
	cmp [rsi+WsiImage.pending],0
	je .next
	vkGetFenceStatus [device],[rsi+WsiImage.presented]
	cmp eax,VK_NOT_READY
	je .ready
	test eax,eax
	jnz .done
	mov [rsi+WsiImage.pending],0
.next:
	add rsi,sizeof.WsiImage
	dec edi
	jmp .image
.release:
	fastcall wsi_destroy_retired,rbx
	inc [wsi_retired_head]
	and [wsi_retired_head],WSI_RETIRED_LIMIT-1
	dec [wsi_retired_count]
	jmp .record
.ready:
	xor eax,eax
.done:
	ret
endp

proc wsi_destroy_swapchain uses rbx rsi rdi
	cmp [swapchain],0
	je .done
	cmp [wsi_present_fences],0
	jne .retire
	; Unextended WSI has no direct present-retirement signal. Preserve the
	; conventional idle fallback only on that route.
	vkDeviceWaitIdle [device]
	fastcall wsi_destroy_swapchain_now
	ret
.retire:
	cmp [wsi_retired_count],WSI_RETIRED_LIMIT
	jb .slot
	mov eax,[wsi_retired_head]
	imul eax,sizeof.RetiredSwapchain
	mov rbx,[wsi_retired]
	add rbx,rax
	fastcall wsi_wait_present_images,addr rbx+RetiredSwapchain.images,[rbx+RetiredSwapchain.image_count]
	test eax,eax
	jnz .failed
	fastcall wsi_collect_swapchains
	test eax,eax
	jnz .failed
.slot:
	mov eax,[wsi_retired_tail]
	imul eax,sizeof.RetiredSwapchain
	mov rbx,[wsi_retired]
	add rbx,rax
	mov rax,[swapchain]
	mov [rbx+RetiredSwapchain.handle],rax
	cmp [wsi_shutdown],0
	jne .no_hold
	mov [wsi_replacement_hold],rax
	mov [wsi_swapchain_info.oldSwapchain],rax
.no_hold:
	mov rax,[retirement_value]
	mov [rbx+RetiredSwapchain.retirement],rax
	mov eax,[wsi_image_count]
	mov [rbx+RetiredSwapchain.image_count],eax
	lea rsi,[wsi_images]
	lea rdi,[rbx+RetiredSwapchain.images]
	mov ecx,WSI_IMAGE_LIMIT*sizeof.WsiImage/8
	rep movsq
	lea rdi,[wsi_images]
	mov ecx,WSI_IMAGE_LIMIT*sizeof.WsiImage/8
	xor eax,eax
	rep stosq
	mov [swapchain],0
	mov [wsi_image_count],0
	mov [wsi_dirty],1
	inc [wsi_retired_tail]
	and [wsi_retired_tail],WSI_RETIRED_LIMIT-1
	inc [wsi_retired_count]
	inc [wsi_swapchains_retired]
	fastcall wsi_collect_swapchains
.done:
	ret
.failed:
	mov [wsi_error],eax
	mov [gpu_error],eax
	mov [app_io_failed],1
	ret
endp

proc wsi_drain uses rbx rsi
	fastcall wsi_wait_work
	test eax,eax
	jnz .done
	cmp [wsi_present_fences],0
	jne .present_fences
	vkDeviceWaitIdle [device]
	ret
.present_fences:
	fastcall wsi_wait_present_images,addr wsi_images,[wsi_image_count]
	test eax,eax
	jnz .done
	xor ebx,ebx
	mov rsi,[wsi_retired]
	test rsi,rsi
	jz .collect
.chain:
	cmp [rsi+RetiredSwapchain.handle],0
	je .next
	fastcall wsi_wait_present_images,addr rsi+RetiredSwapchain.images,[rsi+RetiredSwapchain.image_count]
	test eax,eax
	jnz .done
.next:
	add rsi,sizeof.RetiredSwapchain
	inc ebx
	cmp ebx,WSI_RETIRED_LIMIT
	jb .chain
.collect:
	fastcall wsi_collect_swapchains
.done:
	ret
endp

section '.data$wsi_retirement' data readable writeable align 8
wsi_retired dq 0
wsi_replacement_hold dq 0
wsi_retired_head dd 0
wsi_retired_tail dd 0
wsi_retired_count dd 0
wsi_shutdown dd 0
wsi_swapchains_retired dd 0
wsi_swapchains_reclaimed dd 0
