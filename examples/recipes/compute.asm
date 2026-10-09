; Headless GPU compute, Windows x64, no C runtime or graphics/presentation API.
; build.cmd compute       builds this and its embedded shader
; build\recipe_compute.exe runs and checks every result
;
; Two input arrays and one output live in one device-local working buffer.
; One mapped staging buffer uploads the inputs and reads back the output.
; No device extensions/features are required beyond Vulkan 1.1; a queue must
; support compute. CPU Vulkan adapters are skipped. All resource lifetimes end
; after completion, before the explicitly loaded Vulkan DLL is released.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/static.inc'
include 'vk/loader/runtime.inc'
vk_runtime.bootstrap
include 'examples/strings.inc'

ELEMENTS := 1048576
WORKGROUP := 64
ARRAY_BYTES := ELEMENTS*4
BUFFER_BYTES := ARRAY_BYTES*3
assert (ELEMENTS+WORKGROUP-1)/WORKGROUP <= 65535

; Win32 defaults to direct IAT calls; see docs/binary-layout.md.
extrn '__imp_ExitProcess' as ExitProcess:qword
extrn '__imp_OutputDebugStringA' as OutputDebugStringA:qword
extrn console_initialize:qword
extrn console_write_line:qword
public mainCRTStartup

struct ComputeBuffer
        handle dq ?
        memory dq ?
        mapped dq ?
        properties dd ?
        dd ?
ends

include 'examples/recipes/host.inc'

macro checked stage*,statement&
        mov [failure_stage],stage
        statement
        test eax,eax
        jnz .failed
end macro

section '.text$compute' code readable executable align 16

proc mainCRTStartup uses rbx rsi rdi
        fastcall console_initialize
        checked 1,fastcall vk_runtime_open
        ; Global calls are first resolved before creating the instance.
        checked 2,fastcall find_debug_extension,addr instance_info
.instance:
        checked 3,vkCreateInstance addr instance_info,0,addr instance
        cmp [instance_info.enabledExtensionCount],0
        je .adapter
        checked 4,vkCreateDebugUtilsMessengerEXT [instance],addr debug_info,0,addr messenger
.adapter:
        checked 5,fastcall choose_device
        checked 6,vkCreateDevice [physical_device],addr device_info,0,addr device
        vkGetDeviceQueue [device],[queue_info.queueFamilyIndex],0,addr queue
        checked 7,fastcall create_buffers
        checked 9,vkMapMemory [device],[staging_buffer.memory],0,VK_WHOLE_SIZE,0,addr staging_buffer.mapped
        ; A[i] = i; B[i] = 3*i+1. The CPU oracle expects C[i] = 4*i+1.
        mov rdi,[staging_buffer.mapped]
        xor ecx,ecx
.input:
        mov [rdi+rcx*4],ecx
        lea eax,[ecx+ecx*2+1]
        mov [rdi+rcx*4+ARRAY_BYTES],eax
        inc ecx
        cmp ecx,ELEMENTS
        jb .input
        mov rax,[staging_buffer.memory]
        mov [mapped_range.memory],rax
        test [staging_buffer.properties],VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
        jnz .objects
        checked 10,vkFlushMappedMemoryRanges [device],1,addr mapped_range
.objects:
        checked 11,fastcall make_pipeline
        checked 12,vkCreateCommandPool [device],addr pool_info,0,addr command_pool
        mov rax,[command_pool]
        mov [command_info.commandPool],rax
        checked 13,vkAllocateCommandBuffers [device],addr command_info,addr command_buffer
        checked 14,vkCreateFence [device],addr fence_info,0,addr fence
        ; Timestamp support is optional, including on compute-only queues.
        cmp [timestamp_bits],0
        je .record
        vkCreateQueryPool [device],addr query_info,0,addr query_pool
        test eax,eax
        jz .record
        mov [query_pool],0
.record:
        checked 15,vkBeginCommandBuffer [command_buffer],addr begin_info
        cmp [query_pool],0
        je .upload
        vkCmdResetQueryPool [command_buffer],[query_pool],0,2
        vkCmdWriteTimestamp [command_buffer],VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,[query_pool],0
.upload:
        vkCmdCopyBuffer [command_buffer],[staging_buffer.handle],[working_buffer.handle],1,addr upload_region
        ; Transfer writes are available to the following compute reads.
        vkCmdPipelineBarrier [command_buffer],VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,0,1,addr upload_barrier,0,0,0,0
        vkCmdBindPipeline [command_buffer],VK_PIPELINE_BIND_POINT_COMPUTE,[pipeline]
        vkCmdBindDescriptorSets [command_buffer],VK_PIPELINE_BIND_POINT_COMPUTE,[pipeline_layout],0,1,addr descriptor_set,0,0
        vkCmdPushConstants [command_buffer],[pipeline_layout],VK_SHADER_STAGE_COMPUTE_BIT,0,4,addr element_count
        vkCmdDispatch [command_buffer],(ELEMENTS+WORKGROUP-1)/WORKGROUP,1,1
        vkCmdPipelineBarrier [command_buffer],VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,0,1,addr readback_barrier,0,0,0,0
        vkCmdCopyBuffer [command_buffer],[working_buffer.handle],[staging_buffer.handle],1,addr readback_region
        vkCmdPipelineBarrier [command_buffer],VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_HOST_BIT,0,1,addr host_barrier,0,0,0,0
        cmp [query_pool],0
        je .end
        vkCmdWriteTimestamp [command_buffer],VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,[query_pool],1
.end:
        checked 16,vkEndCommandBuffer [command_buffer]
        checked 17,vkQueueSubmit [queue],1,addr submit_info,[fence]
        checked 18,vkWaitForFences [device],1,addr fence,VK_TRUE,5000000000
        ; Waiting for completion precedes cache invalidation and CPU access.
        test [staging_buffer.properties],VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
        jnz .verify
        checked 19,vkInvalidateMappedMemoryRanges [device],1,addr mapped_range
.verify:
        mov rdi,[staging_buffer.mapped]
        xor ecx,ecx
.element:
        lea eax,[rcx*4+1]
        cmp [rdi+rcx*4+2*ARRAY_BYTES],eax
        jne .mismatch
        inc ecx
        cmp ecx,ELEMENTS
        jb .element
        fastcall console_write_line,addr verified_text
        checked 20,fastcall report_timing
.success:
        xor ebx,ebx
        jmp .cleanup
.mismatch:
        mov [failure_stage],21
        mov eax,-1
.failed:
        mov ebx,1
        fastcall report_line,addr error_format,[failure_stage],rax,0,0
.cleanup:
        fastcall release_compute
        cmp [validation_failed],0
        je .exit
        fastcall console_write_line,addr validation_text
        mov ebx,1
.exit:
        fastcall [ExitProcess],rbx
        int3
endp

; Memory query data is shared only by the two allocations in this frame.
proc create_buffers
        locals
                memory_properties VkPhysicalDeviceMemoryProperties2
        endl
        mov [memory_properties.sType],VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2
        mov [memory_properties.pNext],0
        vkGetPhysicalDeviceMemoryProperties2 [physical_device],addr memory_properties
        fastcall make_buffer,addr working_buffer,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT or VK_BUFFER_USAGE_TRANSFER_SRC_BIT or VK_BUFFER_USAGE_TRANSFER_DST_BIT,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,0,addr memory_properties
        test eax,eax
        jnz buffers_done
        mov [failure_stage],8
        fastcall make_buffer,addr staging_buffer,VK_BUFFER_USAGE_TRANSFER_SRC_BIT or VK_BUFFER_USAGE_TRANSFER_DST_BIT,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT,VK_MEMORY_PROPERTY_HOST_CACHED_BIT,addr memory_properties
buffers_done:
        ret
endp

proc report_timing
        locals
                timestamps rq 2
        endl
        cmp [query_pool],0
        je timing_unavailable
        vkGetQueryPoolResults [device],[query_pool],0,2,16,addr timestamps,8,VK_QUERY_RESULT_64_BIT
        test eax,eax
        jnz timing_done
        mov rax,[timestamps+8]
        sub rax,[timestamps]
        mov ecx,[timestamp_bits]
        cmp ecx,64
        jae timing_convert
        mov rdx,-1
        shl rdx,cl
        not rdx
        and rax,rdx
timing_convert:
        cvtsi2sd xmm0,rax
        cvtss2sd xmm1,[timestamp_period]
        mulsd xmm0,xmm1
        divsd xmm0,[ns_per_us]
        cvtsd2si eax,xmm0
        fastcall report_line,addr time_format,rax,0,0,0
        xor eax,eax
timing_done:
        ret
timing_unavailable:
        fastcall console_write_line,addr no_time_text
        xor eax,eax
        ret
endp

; Evaluate every candidate before choosing it. A compute queue is required;
; graphics and presentation are not. Bounds match the shader's fixed workload.
proc choose_device uses rbx rsi rdi
        locals
                properties VkPhysicalDeviceProperties2
                adapter_count dd ?
                family_count dd ?
                adapters rq 16
                families rb 32*sizeof.VkQueueFamilyProperties
        endl
        mov [adapter_count],16
        mov [properties.sType],VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2
        mov [properties.pNext],0
        vkEnumeratePhysicalDevices [instance],addr adapter_count,addr adapters
        test eax,eax
        jnz choose_done
        xor ebx,ebx
choose_adapter:
        cmp ebx,[adapter_count]
        jae choose_unavailable
        lea rax,[adapters]
        mov rax,[rax+rbx*8]
        mov [physical_device],rax
        vkGetPhysicalDeviceProperties2 rax,addr properties
        cmp [properties.properties.apiVersion],VK_API_VERSION_1_1
        jb choose_next_adapter
        cmp [properties.properties.deviceType],VK_PHYSICAL_DEVICE_TYPE_CPU
        je choose_next_adapter
        cmp [properties.properties.limits.maxStorageBufferRange],BUFFER_BYTES
        jb choose_next_adapter
        mov [family_count],32
        vkGetPhysicalDeviceQueueFamilyProperties [physical_device],addr family_count,addr families
        xor edi,edi
        lea rsi,[families]
choose_family:
        cmp edi,[family_count]
        jae choose_next_adapter
        cmp [rsi+VkQueueFamilyProperties.queueCount],0
        je choose_next_family
        test [rsi+VkQueueFamilyProperties.queueFlags],VK_QUEUE_COMPUTE_BIT
        jnz choose_chosen
choose_next_family:
        inc edi
        add rsi,sizeof.VkQueueFamilyProperties
        jmp choose_family
choose_next_adapter:
        inc ebx
        jmp choose_adapter
choose_chosen:
        mov [queue_info.queueFamilyIndex],edi
        mov [pool_info.queueFamilyIndex],edi
        mov eax,[rsi+VkQueueFamilyProperties.timestampValidBits]
        mov [timestamp_bits],eax
        mov eax,[properties.properties.limits.timestampPeriod]
        mov [timestamp_period],eax
        fastcall console_write_line,addr properties.properties.deviceName
        xor eax,eax
choose_done:
        ret
choose_unavailable:
        mov eax,VK_ERROR_FEATURE_NOT_PRESENT
        ret
endp

; Memory type bits constrain the search. Prefer the requested flags, then
; accept any type having the required ones. Creation is safe to unwind partly.
proc make_buffer uses rbx rsi rdi r12 r13 r14,owner,usage,required,preferred,memory
        locals
                requirements VkMemoryRequirements
        endl
        mov rbx,rcx
        mov r12d,r8d
        mov r13d,r9d
        mov r14,[memory]
        mov [buffer_info.usage],edx
        vkCreateBuffer [device],addr buffer_info,0,addr rbx+ComputeBuffer.handle
        test eax,eax
        jnz buffer_done
        vkGetBufferMemoryRequirements [device],[rbx+ComputeBuffer.handle],addr requirements
        mov edi,r12d
        or edi,r13d
buffer_search:
        lea rsi,[r14+VkPhysicalDeviceMemoryProperties2.memoryProperties.memoryTypes]
        xor ecx,ecx
buffer_type:
        cmp ecx,[r14+VkPhysicalDeviceMemoryProperties2.memoryProperties.memoryTypeCount]
        jae buffer_fallback
        bt [requirements.memoryTypeBits],ecx
        jnc buffer_next
        mov eax,[rsi+VkMemoryType.propertyFlags]
        mov edx,eax
        and edx,edi
        cmp edx,edi
        je buffer_found
buffer_next:
        inc ecx
        add rsi,sizeof.VkMemoryType
        jmp buffer_type
buffer_fallback:
        cmp edi,r12d
        je buffer_unavailable
        mov edi,r12d
        jmp buffer_search
buffer_found:
        mov [rbx+ComputeBuffer.properties],eax
        mov [allocate_info.memoryTypeIndex],ecx
        mov rax,[requirements.size]
        mov [allocate_info.allocationSize],rax
        vkAllocateMemory [device],addr allocate_info,0,addr rbx+ComputeBuffer.memory
        test eax,eax
        jnz buffer_done
        vkBindBufferMemory [device],[rbx+ComputeBuffer.handle],[rbx+ComputeBuffer.memory],0
buffer_done:
        ret
buffer_unavailable:
        mov eax,VK_ERROR_FEATURE_NOT_PRESENT
        ret
endp

proc make_pipeline
        vkCreateDescriptorSetLayout [device],addr set_info,0,addr descriptor_layout
        test eax,eax
        jnz .done
        vkCreatePipelineLayout [device],addr layout_info,0,addr pipeline_layout
        test eax,eax
        jnz .done
        vkCreateShaderModule [device],addr shader_info,0,addr shader
        test eax,eax
        jnz .done
        mov rax,[shader]
        mov [pipeline_info.stage.module],rax
        mov rax,[pipeline_layout]
        mov [pipeline_info.layout],rax
        vkCreateComputePipelines [device],0,1,addr pipeline_info,0,addr pipeline
        test eax,eax
        jnz .done
        vkCreateDescriptorPool [device],addr descriptor_pool_info,0,addr descriptor_pool
        test eax,eax
        jnz .done
        mov rax,[descriptor_pool]
        mov [set_allocate.descriptorPool],rax
        vkAllocateDescriptorSets [device],addr set_allocate,addr descriptor_set
        test eax,eax
        jnz .done
        mov rax,[descriptor_set]
        mov [write_set.dstSet],rax
        mov rax,[working_buffer.handle]
        mov [descriptor_buffer.buffer],rax
        vkUpdateDescriptorSets [device],1,addr write_set,0,0
        xor eax,eax
.done:
        ret
endp

proc debug_callback uses rbx,severity,types,data,user
        mov rbx,r8
        test edx,VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT
        jz .message
        test ecx,VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
        jz .message
        mov [validation_failed],1
.message:
        fastcall [OutputDebugStringA],[rbx+VkDebugUtilsMessengerCallbackDataEXT.pMessage]
        xor eax,eax
        ret
endp

proc release_compute
        cmp [device],0
        je .instance
        ; Also handles a timed-out/failed submission before freeing its inputs.
        vkDeviceWaitIdle [device]
        iterate <function,owner>, vkDestroyQueryPool,query_pool, vkDestroyFence,fence, vkDestroyCommandPool,command_pool, vkDestroyDescriptorPool,descriptor_pool, \
                vkDestroyPipeline,pipeline, vkDestroyShaderModule,shader, vkDestroyPipelineLayout,pipeline_layout, vkDestroyDescriptorSetLayout,descriptor_layout
                cmp [owner],0
                je .skip_#owner
                function [device],[owner],0
        .skip_#owner:
        end iterate
        iterate owner, staging_buffer,working_buffer
                cmp [owner.handle],0
                je .memory_#owner
                vkDestroyBuffer [device],[owner.handle],0
        .memory_#owner:
                cmp [owner.memory],0
                je .skip_#owner
                vkFreeMemory [device],[owner.memory],0
        .skip_#owner:
        end iterate
        vkDestroyDevice [device],0
.instance:
        cmp [messenger],0
        je .without_messenger
        vkDestroyDebugUtilsMessengerEXT [instance],[messenger],0
.without_messenger:
        cmp [instance],0
        je .runtime
        vkDestroyInstance [instance],0
.runtime:
        fastcall vk_runtime_close
        ret
endp

section '.rdata$compute' data readable align 16
shader_code file 'build/recipe_compute.spv'
shader_bytes := $-shader_code
entry_name db 'main',0
debug_extension db VK_EXT_DEBUG_UTILS_EXTENSION_NAME,0
time_format db '[compute] GPU upload + dispatch + readback: %u us (one batch)',0
error_format db '[compute] failed at step %u, result %d',0
verified_text db '[compute] verified 1048576 sums: C[i] = A[i] + B[i]',0
no_time_text db '[compute] queue timestamps unavailable; results verified',0
validation_text db '[compute] validation emitted a warning or error',0
ns_per_us dq 1000.0

section '.data$compute' data readable writeable align 16
element_count dd ELEMENTS
queue_priority dd 1.0
application_info VkApplicationInfo sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,apiVersion: VK_API_VERSION_1_1
debug_names dq debug_extension
debug_info VkDebugUtilsMessengerCreateInfoEXT sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
        messageSeverity: VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT, \
        messageType: VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT, \
        pfnUserCallback: debug_callback
instance_info VkInstanceCreateInfo sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,pApplicationInfo: application_info,ppEnabledExtensionNames: debug_names
queue_info VkDeviceQueueCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,queueCount: 1,pQueuePriorities: queue_priority
device_info VkDeviceCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,queueCreateInfoCount: 1,pQueueCreateInfos: queue_info
buffer_info VkBufferCreateInfo sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,size: BUFFER_BYTES,sharingMode: VK_SHARING_MODE_EXCLUSIVE
allocate_info VkMemoryAllocateInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
mapped_range VkMappedMemoryRange sType: VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,size: VK_WHOLE_SIZE
binding VkDescriptorSetLayoutBinding binding: 0,descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,descriptorCount: 1,stageFlags: VK_SHADER_STAGE_COMPUTE_BIT
set_info VkDescriptorSetLayoutCreateInfo sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,bindingCount: 1,pBindings: binding
push_range VkPushConstantRange stageFlags: VK_SHADER_STAGE_COMPUTE_BIT,size: 4
layout_info VkPipelineLayoutCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,setLayoutCount: 1,pSetLayouts: descriptor_layout,pushConstantRangeCount: 1,pPushConstantRanges: push_range
shader_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: shader_bytes,pCode: shader_code
pipeline_info VkComputePipelineCreateInfo sType: VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO, \
        stage.sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,stage.stage: VK_SHADER_STAGE_COMPUTE_BIT,stage.pName: entry_name
descriptor_size VkDescriptorPoolSize type: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,descriptorCount: 1
descriptor_pool_info VkDescriptorPoolCreateInfo sType: VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,maxSets: 1,poolSizeCount: 1,pPoolSizes: descriptor_size
set_allocate VkDescriptorSetAllocateInfo sType: VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,descriptorSetCount: 1,pSetLayouts: descriptor_layout
descriptor_buffer VkDescriptorBufferInfo range: BUFFER_BYTES
write_set VkWriteDescriptorSet sType: VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,descriptorCount: 1,descriptorType: VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,pBufferInfo: descriptor_buffer
pool_info VkCommandPoolCreateInfo sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
command_info VkCommandBufferAllocateInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,commandBufferCount: 1
begin_info VkCommandBufferBeginInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
fence_info VkFenceCreateInfo sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
query_info VkQueryPoolCreateInfo sType: VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,queryType: VK_QUERY_TYPE_TIMESTAMP,queryCount: 2
upload_region VkBufferCopy size: ARRAY_BYTES*2
readback_region VkBufferCopy srcOffset: ARRAY_BYTES*2,dstOffset: ARRAY_BYTES*2,size: ARRAY_BYTES
upload_barrier VkMemoryBarrier sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER,srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,dstAccessMask: VK_ACCESS_SHADER_READ_BIT
readback_barrier VkMemoryBarrier sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER,srcAccessMask: VK_ACCESS_SHADER_WRITE_BIT,dstAccessMask: VK_ACCESS_TRANSFER_READ_BIT
host_barrier VkMemoryBarrier sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER,srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,dstAccessMask: VK_ACCESS_HOST_READ_BIT
submit_info VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,commandBufferCount: 1,pCommandBuffers: command_buffer

section '.bss$compute' readable writeable align 16
instance dq ?
device dq ?
physical_device dq ?
queue dq ?
messenger dq ?
working_buffer ComputeBuffer
staging_buffer ComputeBuffer
descriptor_layout dq ?
pipeline_layout dq ?
shader dq ?
pipeline dq ?
descriptor_pool dq ?
descriptor_set dq ?
command_pool dq ?
command_buffer dq ?
fence dq ?
query_pool dq ?
timestamp_bits dd ?
timestamp_period dd ?
validation_failed dd ?
failure_stage dd ?
