; Device half of the loader examples, the same source under every loader:
; creates a device on the first adapter, waits for it to idle, destroys it.
; Returns 0, or the number of the step that failed.

MAX_ADAPTERS := 16

section '.text$t' code readable executable align 16

proc run_device uses rbx
	mov ebx,4
	mov [adapters_listed],MAX_ADAPTERS
	vkEnumeratePhysicalDevices [instance], addr adapters_listed, addr adapters
	test eax,eax
	js .done
	cmp [adapters_listed],0
	je .done

	inc ebx
	vkCreateDevice [adapters], addr device_info, 0, addr device
	test eax,eax
	jnz .done

	inc ebx
	vkDeviceWaitIdle [device]
	test eax,eax
	jnz .destroy_device
	xor ebx,ebx
.destroy_device:
	vkDestroyDevice [device], 0
.done:
	mov eax,ebx
	ret
endp

section '.data$t' data readable writeable align 16

adapters rq MAX_ADAPTERS
adapters_listed dd 0

queue_priority dd 1.0

align 8
queue_info VkDeviceQueueCreateInfo \
	sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, \
	queueCount: 1, \
	pQueuePriorities: queue_priority

device_info VkDeviceCreateInfo \
	sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, \
	queueCreateInfoCount: 1, \
	pQueueCreateInfos: queue_info
