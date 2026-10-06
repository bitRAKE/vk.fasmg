CAP_ADDRESS := 64
CAP_HEAP := 128
CAP_COMMAND_ADDRESS := 256
GPU_EXTRA_FEATURES := 1
GPU_EXTRA_FORMATS := 1
GPU_HARDWARE_ONLY := 1
GPU_APP_NAME equ 'NoGraphicsAPI cube'

section '.text$cube_features' code readable executable align 16
proc query_extra_features
	mov [address_candidate],0
	mov [heap_candidate],0
	mov [command_candidate],0
	test [requested_caps],CAP_ADDRESS
	jz .done
	cmp [device_api],VK_API_VERSION_1_2
	jb .done
	fastcall chain_feature,addr address_feature
	mov [address_candidate],1
	; The native Slang heap ABI uses scalar layout and the BaseVertex built-in.
	test [requested_caps],CAP_HEAP
	jz .commands
	cmp [device_api],VK_API_VERSION_1_4
	jb .commands
	fastcall extension_present,'VK_EXT_descriptor_heap',[device_extension_count],addr device_extensions
	test eax,eax
	jz .commands
	fastcall extension_present,'VK_KHR_shader_untyped_pointers',[device_extension_count],addr device_extensions
	test eax,eax
	jz .commands
	fastcall chain_feature,addr heap_feature
	fastcall chain_feature,addr untyped_feature
	fastcall chain_feature,addr scalar_feature
	fastcall chain_feature,addr draw_parameters_feature
	mov [heap_candidate],1
.commands:
	test [requested_caps],CAP_COMMAND_ADDRESS
	jz .done
	cmp [device_api],VK_API_VERSION_1_3
	jb .done
	fastcall extension_present,'VK_KHR_device_address_commands',[device_extension_count],addr device_extensions
	test eax,eax
	jz .done
	fastcall chain_feature,addr command_feature
	mov [command_candidate],1
.done:
	ret
endp

proc append_extension name
	mov eax,[device_info.enabledExtensionCount]
	lea rdx,[enabled_extensions]
	mov [rdx+rax*8],rcx
	inc [device_info.enabledExtensionCount]
	ret
endp

proc enable_extra_features
	cmp [address_candidate],0
	je .done
	cmp [address_feature.bufferDeviceAddress],VK_TRUE
	jne .done
	mov [address_feature.bufferDeviceAddressCaptureReplay],0
	mov [address_feature.bufferDeviceAddressMultiDevice],0
	fastcall chain_feature,addr address_feature
	or [active_caps],CAP_ADDRESS
	cmp [heap_candidate],0
	je .commands
	cmp [heap_feature.descriptorHeap],VK_TRUE
	jne .commands
	cmp [untyped_feature.shaderUntypedPointers],VK_TRUE
	jne .commands
	cmp [scalar_feature.scalarBlockLayout],VK_TRUE
	jne .commands
	cmp [draw_parameters_feature.shaderDrawParameters],VK_TRUE
	jne .commands
	; Native heap pipelines here require the 1.4 rendering/inline routes.
	mov eax,[active_caps]
	and eax,CAP_RENDER or CAP_INLINE
	cmp eax,CAP_RENDER or CAP_INLINE
	jne .commands
	mov [heap_feature.descriptorHeapCaptureReplay],0
	fastcall chain_feature,addr heap_feature
	fastcall chain_feature,addr untyped_feature
	fastcall chain_feature,addr scalar_feature
	fastcall chain_feature,addr draw_parameters_feature
	fastcall append_extension,'VK_EXT_descriptor_heap'
	fastcall append_extension,'VK_KHR_shader_untyped_pointers'
	or [active_caps],CAP_HEAP
	lea rax,[heap_properties]
	mov [properties2.pNext],rax
	vkGetPhysicalDeviceProperties2 [physical_device],addr properties2
	mov [properties2.pNext],0
.commands:
	cmp [command_candidate],0
	je .done
	cmp [command_feature.deviceAddressCommands],VK_TRUE
	jne .done
	test [active_caps],CAP_SYNC
	jz .done
	fastcall chain_feature,addr command_feature
	fastcall append_extension,'VK_KHR_device_address_commands'
	or [active_caps],CAP_COMMAND_ADDRESS
.done:
	ret
endp

proc resolve_extra_commands
	iterate <bit,function,name>,CAP_ADDRESS,vkGetBufferDeviceAddress,'vkGetBufferDeviceAddress', \
		CAP_HEAP,vkCmdBindResourceHeapEXT,'vkCmdBindResourceHeapEXT',CAP_HEAP,vkCmdBindSamplerHeapEXT,'vkCmdBindSamplerHeapEXT', \
		CAP_HEAP,vkCmdPushDataEXT,'vkCmdPushDataEXT',CAP_HEAP,vkWriteResourceDescriptorsEXT,'vkWriteResourceDescriptorsEXT', \
		CAP_HEAP,vkWriteSamplerDescriptorsEXT,'vkWriteSamplerDescriptorsEXT',CAP_COMMAND_ADDRESS,vkCmdBindIndexBuffer3KHR,'vkCmdBindIndexBuffer3KHR', \
		CAP_COMMAND_ADDRESS,vkCmdCopyMemoryToImageKHR,'vkCmdCopyMemoryToImageKHR',CAP_COMMAND_ADDRESS,vkCmdCopyImageToMemoryKHR,'vkCmdCopyImageToMemoryKHR'
		test [active_caps],bit
		jz .skip#function
		.local_name#function GLOBSTR name,0
		vkGetDeviceProcAddr [device],addr .local_name#function
		test rax,rax
		jz .failed
		mov [function],rax
	.skip#function:
	end iterate
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

section '.data$cube_features' data readable writeable align 8
address_candidate dd 0
heap_candidate dd 0
command_candidate dd 0
address_feature VkPhysicalDeviceBufferDeviceAddressFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES
heap_feature VkPhysicalDeviceDescriptorHeapFeaturesEXT sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_FEATURES_EXT
untyped_feature VkPhysicalDeviceShaderUntypedPointersFeaturesKHR sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_UNTYPED_POINTERS_FEATURES_KHR
scalar_feature VkPhysicalDeviceScalarBlockLayoutFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES
draw_parameters_feature VkPhysicalDeviceShaderDrawParametersFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_DRAW_PARAMETERS_FEATURES
command_feature VkPhysicalDeviceDeviceAddressCommandsFeaturesKHR sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DEVICE_ADDRESS_COMMANDS_FEATURES_KHR
heap_properties VkPhysicalDeviceDescriptorHeapPropertiesEXT sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_PROPERTIES_EXT
