; Object names, rename/clear, binary tags, nested command and queue labels.
; Submit a real command buffer containing only labels; no shaders or rendering.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/static.inc'
include 'context.inc'

public mainCRTStartup

; The projection represents C arrays as reserved storage. Patch float-array
; bytes in assembled data while deriving the field offset from the SDK type.
macro label_color item*,red*,green*,blue*,alpha*
	local low,high
	virtual at 0
		dd red,green,blue,alpha
		load low:qword from 0
		load high:qword from 8
	end virtual
	store qword low at item+VkDebugUtilsLabelEXT.color
	store qword high at item+VkDebugUtilsLabelEXT.color+8
end macro

section '.text$debug_example' code readable executable align 16
proc mainCRTStartup uses rbx rsi
	fastcall console_initialize
	mov ebx,1
	fastcall debug_initialize,addr bootstrap_sink,0
	test eax,eax
	jnz .finish
	mov rax,[bootstrap_sink.handle]
	mov [names_sink.handle],rax
	fastcall create_instance
	test eax,eax
	jnz .finish
	inc ebx
	vkCreateDebugUtilsMessengerEXT [instance],addr names_info,0,addr messenger
	test eax,eax
	jnz .instance
	inc ebx
	fastcall create_device
	test eax,eax
	jnz .messenger

	inc ebx
	mov eax,[family_index]
	mov [pool_info.queueFamilyIndex],eax
	vkCreateCommandPool [device],addr pool_info,0,addr command_pool
	test eax,eax
	jnz .resources
	inc ebx
	mov rax,[command_pool]
	mov [allocate_info.commandPool],rax
	vkAllocateCommandBuffers [device],addr allocate_info,addr command_buffer
	test eax,eax
	jnz .resources
	inc ebx
	vkCreateBuffer [device],addr buffer_info,0,addr buffer
	test eax,eax
	jnz .resources

	mov rax,[device]
	mov [device_name.objectHandle],rax
	mov rax,[queue]
	mov [queue_name.objectHandle],rax
	mov rax,[command_pool]
	mov [pool_name.objectHandle],rax
	mov rax,[command_buffer]
	mov [commands_name.objectHandle],rax
	mov rax,[buffer]
	mov [buffer_name.objectHandle],rax
	mov [tag_info.objectHandle],rax
	lea rsi,[object_names]
.name:
	vkSetDebugUtilsObjectNameEXT [device],rsi
	test eax,eax
	jnz .resources
	add rsi,sizeof.VkDebugUtilsObjectNameInfoEXT
	lea rax,[object_names.end]
	cmp rsi,rax
	jb .name
	mov [event_data.objectCount],object_names.count
	lea rax,[object_names]
	mov [event_data.pObjects],rax
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'objects.named: five live Vulkan handles',DEBUG_DEMO_ID+11

	inc ebx
	vkSetDebugUtilsObjectTagEXT [device],addr tag_info
	test eax,eax
	jnz .resources
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'objects.tagged: buffer carries asset-id:42',DEBUG_DEMO_ID+12

	inc ebx
	vkBeginCommandBuffer [command_buffer],addr begin_info
	test eax,eax
	jnz .resources
	vkQueueBeginDebugUtilsLabelEXT [queue],addr queue_region
	vkCmdBeginDebugUtilsLabelEXT [command_buffer],addr command_regions
	vkCmdBeginDebugUtilsLabelEXT [command_buffer],addr command_regions+sizeof.VkDebugUtilsLabelEXT
	vkCmdInsertDebugUtilsLabelEXT [command_buffer],addr checkpoint
	; Explicit callback metadata mirrors the active label stacks. This is an
	; application message, not an intentionally triggered validation error.
	mov [event_data.queueLabelCount],1
	lea rax,[queue_region]
	mov [event_data.pQueueLabels],rax
	mov [event_data.cmdBufLabelCount],2
	lea rax,[command_regions]
	mov [event_data.pCmdBufLabels],rax
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'objects.labels: active queue region and nested command regions',DEBUG_DEMO_ID+13
	mov [event_data.queueLabelCount],0
	mov [event_data.cmdBufLabelCount],0
	mov [event_data.pQueueLabels],0
	mov [event_data.pCmdBufLabels],0
	vkCmdEndDebugUtilsLabelEXT [command_buffer]
	vkCmdEndDebugUtilsLabelEXT [command_buffer]
	vkEndCommandBuffer [command_buffer]
	test eax,eax
	jnz .queue_label
	vkQueueInsertDebugUtilsLabelEXT [queue],addr checkpoint
	inc ebx
	vkQueueSubmit [queue],1,addr submit_info,0
	test eax,eax
	jnz .queue_label
	vkQueueEndDebugUtilsLabelEXT [queue]
	vkQueueWaitIdle [queue]
	test eax,eax
	jnz .resources

	inc ebx
	lea rax,[renamed_buffer]
	mov [buffer_name.pObjectName],rax
	vkSetDebugUtilsObjectNameEXT [device],addr buffer_name
	test eax,eax
	jnz .resources
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'objects.renamed: buffer name replaced',DEBUG_DEMO_ID+14
	mov [buffer_name.pObjectName],0
	vkSetDebugUtilsObjectNameEXT [device],addr buffer_name
	test eax,eax
	jnz .resources
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'objects.cleared: buffer name removed with NULL',DEBUG_DEMO_ID+15
	xor ebx,ebx
	jmp .resources
.queue_label:
	vkQueueEndDebugUtilsLabelEXT [queue]
.resources:
	; No callback record may refer to a resource after it has been destroyed.
	mov [event_data.objectCount],0
	mov [event_data.pObjects],0
	cmp [device],0
	je .messenger
	vkDeviceWaitIdle [device]
	test eax,eax
	jz .idle
	mov ebx,101
.idle:
	cmp [buffer],0
	je .pool
	vkDestroyBuffer [device],[buffer],0
.pool:
	cmp [command_pool],0
	je .device
	vkDestroyCommandPool [device],[command_pool],0  ; Frees its command buffer.
.device:
	fastcall destroy_device
	test eax,eax
	jz .messenger
	mov ebx,101
.messenger:
	vkDestroyDebugUtilsMessengerEXT [instance],[messenger],0
.instance:
	fastcall destroy_instance
.finish:
	cmp [debug_io_failed],0
	jne .logging_failed
	cmp [debug_validation_failed],0
	jne .logging_failed
	test ebx,ebx
	jnz .exit
	fastcall console_write_line,'[debug] objects: PASS'
	jmp .exit
.logging_failed:
	mov ebx,100
.exit:
	fastcall ExitProcess,rbx
	int3
endp

section '.data$debug_example' data readable writeable align 8
messenger dq 0
command_pool dq 0
command_buffer dq 0
buffer dq 0
names_label GLOBSTR 'objects',0
names_sink DebugSink kind: DEBUG_CONSOLE, handle: -1, label: names_label
names_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: DEBUG_INFO, messageType: DEBUG_ALL_TYPES, \
	pfnUserCallback: debug_callback, pUserData: names_sink
pool_info VkCommandPoolCreateInfo sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
allocate_info VkCommandBufferAllocateInfo \
	sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, \
	level: VK_COMMAND_BUFFER_LEVEL_PRIMARY, commandBufferCount: 1
buffer_info VkBufferCreateInfo \
	sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, size: 256, \
	usage: VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, sharingMode: VK_SHARING_MODE_EXCLUSIVE
begin_info VkCommandBufferBeginInfo \
	sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, \
	flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
submit_info VkSubmitInfo \
	sType: VK_STRUCTURE_TYPE_SUBMIT_INFO, commandBufferCount: 1, pCommandBuffers: command_buffer

object_names:
device_name VkDebugUtilsObjectNameInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT, \
	objectType: VK_OBJECT_TYPE_DEVICE, pObjectName: device_text
queue_name VkDebugUtilsObjectNameInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT, \
	objectType: VK_OBJECT_TYPE_QUEUE, pObjectName: queue_text
pool_name VkDebugUtilsObjectNameInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT, \
	objectType: VK_OBJECT_TYPE_COMMAND_POOL, pObjectName: pool_text
commands_name VkDebugUtilsObjectNameInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT, \
	objectType: VK_OBJECT_TYPE_COMMAND_BUFFER, pObjectName: commands_text
buffer_name VkDebugUtilsObjectNameInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT, \
	objectType: VK_OBJECT_TYPE_BUFFER, pObjectName: buffer_text
object_names.end:
object_names.count = (object_names.end - object_names) / sizeof.VkDebugUtilsObjectNameInfoEXT
tag_info VkDebugUtilsObjectTagInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_TAG_INFO_EXT, \
	objectType: VK_OBJECT_TYPE_BUFFER, tagName: 564B44424701h, \
	tagSize: tag_bytes.size, pTag: tag_bytes
queue_region VkDebugUtilsLabelEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT, pLabelName: queue_label_text
label_color queue_region,0.2,0.6,0.9,1.0
command_regions:
command_outer VkDebugUtilsLabelEXT sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT, \
	pLabelName: outer_label_text
label_color command_outer,0.2,0.9,0.4,1.0
command_inner VkDebugUtilsLabelEXT sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT, \
	pLabelName: inner_label_text
label_color command_inner,0.9,0.6,0.2,1.0
checkpoint VkDebugUtilsLabelEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT, pLabelName: checkpoint_text
label_color checkpoint,0.9,0.3,0.6,1.0

section '.rdata$debug_example' data readable align 2
tag_bytes db 'asset-id:42',0
tag_bytes.size = $ - tag_bytes
device_text GLOBSTR 'debug.device',0
queue_text GLOBSTR 'debug.queue',0
pool_text GLOBSTR 'debug.command_pool',0
commands_text GLOBSTR 'debug.commands',0
buffer_text GLOBSTR 'debug.buffer',0
renamed_buffer GLOBSTR 'debug.buffer.renamed',0
queue_label_text GLOBSTR 'debug.queue.work',0
outer_label_text GLOBSTR 'debug.commands.outer',0
inner_label_text GLOBSTR 'debug.commands.inner',0
checkpoint_text GLOBSTR 'debug.checkpoint',0
