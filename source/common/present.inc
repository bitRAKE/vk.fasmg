; The picture's way to the monitor: the window's surface, and the swapchain
; whose images the frames are drawn to. An image is shown when the monitor
; next refreshes, so a frame is never torn and the machine never runs ahead
; of what can be seen.
;
;	present_surface	the window's surface, for the device to be chosen by
;	present_format	the adapter in hand shows sRGB: target_format is which
;	present_start	what lasts as long as the device does
;	present_size	a swapchain for the window as it is now: 1 when it stands,
;			2 when the window has no area, 0 on failure
;	present_acquire	the image the next frame is drawn to, in present_image:
;			1, or 2 when the swapchain no longer fits and present_size is
;			to be asked again, or 0 on failure
;	present_submit	the frame's work to the device (work_submit), and the image
;			to the monitor when that is done
;	present_stop
;
; present_dirty says the swapchain no longer fits the window; whoever knows
; the window has changed may set it. A swapchain is replaced with the device
; idle: it is the one place the machine waits for everything, and it happens
; when a window changes size, not while a frame is owed.
;
; A failure is a VkResult in gpu_error and zero returned.
PRESENT_IMAGES := 8			; the most a swapchain may have

struct PresentImage
	handle dq 0
	view dq 0
ends

section '.text$present' code readable executable align 16

proc present_surface
	mov rax,[module]
	mov [present_surface_info.hinstance],rax
	mov rax,[window]
	mov [present_surface_info.hwnd],rax
	vkCreateWin32SurfaceKHR [instance],addr present_surface_info,0,addr surface
	test eax,eax
	jnz .result
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; Colors are blended in linear light, so what is drawn to is sRGB: blue
; first, as a bitmap has it, if the surface offers that.
proc present_format uses rbx rsi
	mov [present_format_count],64
	vkGetPhysicalDeviceSurfaceFormatsKHR [physical_device],[surface],addr present_format_count,addr present_formats
	test eax,eax
	js .none
	iterate choice, VK_FORMAT_B8G8R8A8_SRGB,VK_FORMAT_R8G8B8A8_SRGB
		mov ebx,choice
		xor ecx,ecx
		lea rsi,[present_formats]
	.entry_#choice:
		cmp ecx,[present_format_count]
		jae .not_#choice
		cmp [rsi+VkSurfaceFormatKHR.format],ebx
		jne .next_#choice
		cmp [rsi+VkSurfaceFormatKHR.colorSpace],VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
		je .found
	.next_#choice:
		inc ecx
		add rsi,sizeof.VkSurfaceFormatKHR
		jmp .entry_#choice
	.not_#choice:
	end iterate
.none:
	xor eax,eax
	ret
.found:
	mov [target_format],ebx
	mov [swapchain_info.imageFormat],ebx
	mov [present_view_info.format],ebx
	mov eax,1
	ret
endp

; A semaphore for an image's being acquired, and one for each image's being
; drawn. They outlast any swapchain: the images come and go, and are told
; apart by number.
proc present_start uses rbx rsi
	mov rax,[surface]
	mov [swapchain_info.surface],rax
	vkCreateSemaphore [device],addr present_semaphore_info,0,addr present_acquired
	test eax,eax
	jnz .result
	xor ebx,ebx
	lea rsi,[present_rendered]
.image:
	vkCreateSemaphore [device],addr present_semaphore_info,0,rsi
	test eax,eax
	jnz .result
	add rsi,8
	inc ebx
	cmp ebx,PRESENT_IMAGES
	jb .image
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc present_size uses rbx rsi
	vkGetPhysicalDeviceSurfaceCapabilitiesKHR [physical_device],[surface],addr present_caps
	test eax,eax
	jnz .result
	; The surface says how large its images are, or leaves it to the window.
	mov eax,[present_caps.currentExtent.width]
	mov edx,[present_caps.currentExtent.height]
	cmp eax,-1
	jne .extent
	iterate <register,side,ours>, eax,width,frame_width, edx,height,frame_height
		mov register,[ours]
		cmp register,[present_caps.minImageExtent.side]
		jae .least_#side
		mov register,[present_caps.minImageExtent.side]
	.least_#side:
		cmp register,[present_caps.maxImageExtent.side]
		jbe .most_#side
		mov register,[present_caps.maxImageExtent.side]
	.most_#side:
	end iterate
.extent:
	test eax,eax
	jz .nothing
	test edx,edx
	jz .nothing
	mov [swapchain_info.imageExtent.width],eax
	mov [swapchain_info.imageExtent.height],edx
	; One image on the monitor and one being drawn; more if the surface must.
	mov eax,[present_caps.minImageCount]
	cmp eax,2
	jae .enough
	mov eax,2
.enough:
	cmp [present_caps.maxImageCount],0
	je .count
	cmp eax,[present_caps.maxImageCount]
	jbe .count
	mov eax,[present_caps.maxImageCount]
.count:
	mov [swapchain_info.minImageCount],eax
	mov eax,[present_caps.currentTransform]
	mov [swapchain_info.preTransform],eax
	; The lowest way of compositing the surface has is opaque where it can be.
	mov eax,[present_caps.supportedCompositeAlpha]
	mov edx,eax
	neg edx
	and eax,edx
	mov [swapchain_info.compositeAlpha],eax
	; Nothing of the old one is in use once the device is idle.
	vkDeviceWaitIdle [device]
	test eax,eax
	jnz .result
	fastcall present_views_drop
	mov rax,[swapchain]
	mov [swapchain_info.oldSwapchain],rax
	mov [swapchain],0
	vkCreateSwapchainKHR [device],addr swapchain_info,0,addr swapchain
	mov ebx,eax
	cmp [swapchain_info.oldSwapchain],0
	je .made
	vkDestroySwapchainKHR [device],[swapchain_info.oldSwapchain],0
	mov [swapchain_info.oldSwapchain],0
.made:
	mov eax,ebx
	test eax,eax
	jnz .result
	mov [present_image_count],PRESENT_IMAGES
	vkGetSwapchainImagesKHR [device],[swapchain],addr present_image_count,addr present_handles
	test eax,eax
	jnz .result			; more images than there is room for is a failure too
	xor ebx,ebx
	lea rsi,[present_images]
.image:
	cmp ebx,[present_image_count]
	jae .ready
	lea rax,[present_handles]
	mov rax,[rax+rbx*8]
	mov [rsi+PresentImage.handle],rax
	mov [present_view_info.image],rax
	vkCreateImageView [device],addr present_view_info,0,addr rsi+PresentImage.view
	test eax,eax
	jnz .result
	add rsi,sizeof.PresentImage
	inc ebx
	jmp .image
.ready:
	mov [present_dirty],0
	mov eax,1
	ret
.nothing:
	mov eax,2
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc present_views_drop uses rbx rsi
	xor ebx,ebx
	lea rsi,[present_images]
.image:
	cmp ebx,PRESENT_IMAGES
	jae .done
	cmp [rsi+PresentImage.view],0
	je .next
	vkDestroyImageView [device],[rsi+PresentImage.view],0
	mov [rsi+PresentImage.view],0
.next:
	mov [rsi+PresentImage.handle],0
	add rsi,sizeof.PresentImage
	inc ebx
	jmp .image
.done:
	mov [present_image_count],0
	ret
endp

; The semaphore an image is acquired with is the one the last frame's work
; waited for: so that work is done first.
proc present_acquire
	fastcall work_wait,[work_submitted]
	test eax,eax
	jz .done
	vkAcquireNextImageKHR [device],[swapchain],WORK_PATIENCE,[present_acquired],0,addr present_index
	cmp eax,VK_ERROR_OUT_OF_DATE_KHR
	je .stale
	cmp eax,VK_SUBOPTIMAL_KHR
	jne .taken
	; It will still do for this frame.
	mov [present_dirty],1
	xor eax,eax
.taken:
	test eax,eax
	jnz .result			; out of patience is a failure too
	mov eax,[present_index]
	shl eax,4
	lea rdx,[present_images]
	add rax,rdx
	mov [present_image],rax
	mov eax,1
.done:
	ret
.stale:
	mov [present_dirty],1
	mov eax,2
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc present_submit
	mov eax,[present_index]
	lea rdx,[present_rendered]
	mov rax,[rdx+rax*8]
	mov [present_shown],rax
	fastcall work_submit,[present_acquired],[present_shown]
	test eax,eax
	jz .done
	vkQueuePresentKHR [queue],addr present_info
	cmp eax,VK_ERROR_OUT_OF_DATE_KHR
	je .stale
	cmp eax,VK_SUBOPTIMAL_KHR
	je .stale
	test eax,eax
	jnz .result
	mov eax,1
.done:
	ret
.stale:
	; It was shown, or it was not: either way the next is another swapchain's.
	mov [present_dirty],1
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; The device is idle.
proc present_stop uses rbx rsi
	fastcall present_views_drop
	cmp [swapchain],0
	je .semaphores
	vkDestroySwapchainKHR [device],[swapchain],0
	mov [swapchain],0
.semaphores:
	mov [present_dirty],1
	xor ebx,ebx
	lea rsi,[present_rendered]
.image:
	cmp qword [rsi],0
	je .next
	vkDestroySemaphore [device],[rsi],0
	mov qword [rsi],0
.next:
	add rsi,8
	inc ebx
	cmp ebx,PRESENT_IMAGES
	jb .image
	cmp [present_acquired],0
	je .done
	vkDestroySemaphore [device],[present_acquired],0
	mov [present_acquired],0
.done:
	ret
endp

assert sizeof.PresentImage = 16

section '.data$present' data readable writeable align 8
surface dq 0
swapchain dq 0
present_acquired dq 0
present_shown dq 0			; the semaphore of the image now going to the monitor
present_image dq 0			; the PresentImage being drawn to
present_rendered rq PRESENT_IMAGES
present_handles rq PRESENT_IMAGES
present_images:
	rb PRESENT_IMAGES * sizeof.PresentImage
present_index dd 0
present_image_count dd 0
present_format_count dd 0
present_dirty dd 1
target_format dd VK_FORMAT_B8G8R8A8_SRGB
	align 8
present_surface_info VkWin32SurfaceCreateInfoKHR sType: VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR
present_semaphore_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
present_view_info VkImageViewCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,viewType: VK_IMAGE_VIEW_TYPE_2D,subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
swapchain_info VkSwapchainCreateInfoKHR sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,imageColorSpace: VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,imageArrayLayers: 1,imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT, \
	imageSharingMode: VK_SHARING_MODE_EXCLUSIVE,presentMode: VK_PRESENT_MODE_FIFO_KHR,clipped: VK_TRUE
present_info VkPresentInfoKHR sType: VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,waitSemaphoreCount: 1,pWaitSemaphores: present_shown,swapchainCount: 1,pSwapchains: swapchain,pImageIndices: present_index
present_caps VkSurfaceCapabilitiesKHR

section '.bss$present' readable writeable align 8
present_formats rb 64 * sizeof.VkSurfaceFormatKHR
