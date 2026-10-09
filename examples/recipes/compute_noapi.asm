; NoAPI-style buffer compute: establish one modern contract, then change data.
; build.cmd compute-noapi; build\recipe_compute_noapi.exe
; Vulkan 1.4, BDA, scalar layout, timeline semaphores, synchronization2,
; maintenance5, and device-local/host-visible/coherent memory are required.
; No descriptor, staging, shader-module, fence, or compatibility path exists.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/static.inc'
include 'vk/loader/runtime.inc'
vk_runtime.bootstrap

ELEMENTS := 1048576
WORKGROUP := 64
BATCHES := 3
A_OFFSET := 64
B_OFFSET := A_OFFSET + ELEMENTS*4
C_OFFSET := B_OFFSET + ELEMENTS*4
HEAP_BYTES := C_OFFSET + ELEMENTS*4
GPU_MEMORY := VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT or VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT or VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
assert ELEMENTS mod WORKGROUP = 0
assert ELEMENTS/WORKGROUP <= 65535
assert BATCHES < WORKGROUP

struct NoApiArguments
        input_a dq ?
        input_b dq ?
        output dq ?
        count dd ?
        bias dd ?
ends
struct NoApiRoot
        arguments dq ?
ends
struct NoApiHeap
        buffer dq ?
        memory dq ?
        mapped dq ?
        address dq ?
ends
assert sizeof.NoApiArguments = 32
assert NoApiArguments.input_a = 0 & NoApiArguments.input_b = 8 & NoApiArguments.output = 16
assert NoApiArguments.count = 24 & NoApiArguments.bias = 28
assert sizeof.NoApiRoot = 8 & NoApiRoot.arguments = 0

; Win32 defaults to direct IAT calls; see docs/binary-layout.md.
extrn '__imp_ExitProcess' as ExitProcess:qword
extrn '__imp_OutputDebugStringA' as OutputDebugStringA:qword
extrn console_initialize:qword
extrn console_write_line:qword
public mainCRTStartup

include 'examples/recipes/host.inc'

macro checked stage*,statement&
        mov [failure_stage],stage
        statement
        test eax,eax
        jnz .failed
end macro

section '.text$noapi' code readable executable align 16

proc mainCRTStartup uses rbx rsi rdi r12
        fastcall console_initialize
        checked 1,fastcall vk_runtime_open
        ; Version lookup is explicit: an older loader may not export it.
        checked 2,fastcall require_modern_loader
        ; Both global queries happen before there is an instance.
        checked 3,fastcall find_debug_extension,addr instance_info
.instance:
        checked 4,vkCreateInstance addr instance_info,0,addr instance
        cmp [instance_info.enabledExtensionCount],0
        je .adapter
        checked 4,vkCreateDebugUtilsMessengerEXT [instance],addr debug_info,0,addr messenger
.adapter:
        checked 5,fastcall create_base
        checked 8,vkCreatePipelineLayout [device],addr layout_info,0,addr pipeline_layout
        mov rax,[pipeline_layout]
        mov [pipeline_info.layout],rax
        checked 9,vkCreateComputePipelines [device],0,1,addr pipeline_info,0,addr pipeline
        checked 10,vkCreateCommandPool [device],addr pool_info,0,addr command_pool
        mov rax,[command_pool]
        mov [command_info.commandPool],rax
        checked 10,vkAllocateCommandBuffers [device],addr command_info,addr command_buffer
        checked 11,vkCreateSemaphore [device],addr timeline_info,0,addr timeline
        mov rax,[timeline]
        mov [signal_info.semaphore],rax
        mov rax,[command_buffer]
        mov [command_submit.commandBuffer],rax
        checked 12,fastcall resolve_hot_calls
        ; This bounded workload has fixed commands and a GPU-resident root.
        ; Record once; each submission reads the then-current argument memory.
        checked 13,vkBeginCommandBuffer [command_buffer],addr begin_info
        vkCmdBindPipeline [command_buffer],VK_PIPELINE_BIND_POINT_COMPUTE,[pipeline]
        vkCmdPushConstants [command_buffer],[pipeline_layout],VK_SHADER_STAGE_COMPUTE_BIT,0,sizeof.NoApiRoot,addr root
        vkCmdDispatch [command_buffer],ELEMENTS/WORKGROUP,1,1
        vkCmdPipelineBarrier2 [command_buffer],addr host_dependency
        checked 13,vkEndCommandBuffer [command_buffer]
        fastcall console_write_line,addr ready_text
        mov ebx,1
.batch:
        fastcall prepare_batch,rbx
        mov [signal_info.value],rbx
        mov [wait_value],rbx
        ; Coherent mapped GPU memory can be write-combined on the CPU.
        sfence
        checked 14,vkQueueSubmit2 [queue],1,addr submit_info,0
        checked 15,vkWaitSemaphores [device],addr wait_info,5000000000
        fastcall verify_batch,rbx
        test eax,eax
        jz .mismatch
        mov eax,ELEMENTS
        sub eax,ebx
        imul r12d,ebx,1000
        fastcall report_line,addr batch_format,rbx,rax,rbx,r12
        inc ebx
        cmp ebx,BATCHES
        jbe .batch
        fastcall console_write_line,addr success_text
        xor ebx,ebx
        jmp .cleanup
.mismatch:
        mov [failure_stage],16
        mov eax,-1
.failed:
        mov ebx,1
        fastcall report_line,addr error_format,[failure_stage],rax,[missing_contract],0
        fastcall console_write_line,addr contract_text
.cleanup:
        fastcall release_noapi
        cmp [validation_failed],0
        je .exit
        fastcall console_write_line,addr validation_text
        mov ebx,1
.exit:
        fastcall [ExitProcess],rbx
        int3
endp

proc require_modern_loader
        locals
                version dd ?
        endl
        fastcall [vk_runtime_resolver],0,addr version_name
        test rax,rax
        jz loader_too_old
        fastcall rax,addr version
        test eax,eax
        jnz loader_done
        cmp [version],VK_API_VERSION_1_4
        jb loader_too_old
loader_done:
        ret
loader_too_old:
        mov [missing_contract],1
        mov eax,VK_ERROR_INCOMPATIBLE_DRIVER
        ret
endp

; This frame owns memory properties across selection and allocation only.
proc create_base
        locals
                memory_properties VkPhysicalDeviceMemoryProperties2
        endl
        mov [memory_properties.sType],VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2
        mov [memory_properties.pNext],0
        fastcall choose_device,addr memory_properties
        test eax,eax
        jnz base_done
        mov [failure_stage],6
        vkCreateDevice [physical_device],addr device_info,0,addr device
        test eax,eax
        jnz base_done
        vkGetDeviceQueue [device],[queue_info.queueFamilyIndex],0,addr queue
        mov [failure_stage],7
        fastcall create_heap,addr memory_properties
base_done:
        ret
endp

; Capability tests select one fixed model. Missing requirements reject a
; candidate; they do not select alternate shader/binding/command protocols.
proc choose_device uses rbx rsi rdi r12 r13,memory
        locals
                properties VkPhysicalDeviceProperties2
                query_features VkPhysicalDeviceFeatures2
                query12 VkPhysicalDeviceVulkan12Features
                query13 VkPhysicalDeviceVulkan13Features
                query14 VkPhysicalDeviceVulkan14Features
                adapter_count dd ?
                family_count dd ?
                adapters rq 16
                families rb 32*sizeof.VkQueueFamilyProperties
        endl
        mov r13,rcx
        mov [adapter_count],16
        mov [properties.sType],VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2
        mov [properties.pNext],0
        mov [query14.pNext],0
        iterate <owner,type>, query_features,PHYSICAL_DEVICE_FEATURES_2, query12,PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, \
                query13,PHYSICAL_DEVICE_VULKAN_1_3_FEATURES, query14,PHYSICAL_DEVICE_VULKAN_1_4_FEATURES
                mov [owner.sType],VK_STRUCTURE_TYPE_#type
        end iterate
        iterate <owner,next>, query_features,query12, query12,query13, query13,query14
                lea rax,[next]
                mov [owner.pNext],rax
        end iterate
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
        mov [missing_contract],1
        cmp [properties.properties.apiVersion],VK_API_VERSION_1_4
        jb choose_next_adapter
        mov [missing_contract],2
        cmp [properties.properties.deviceType],VK_PHYSICAL_DEVICE_TYPE_CPU
        je choose_next_adapter
        vkGetPhysicalDeviceFeatures2 [physical_device],addr query_features
        xor r12d,r12d
        iterate <owner,member,bit>, query12,bufferDeviceAddress,4, query12,scalarBlockLayout,8, \
                query12,timelineSemaphore,16, query13,synchronization2,32, query14,maintenance5,64
                cmp [owner.member],VK_TRUE
                je choose_has_#member
                or r12d,bit
        choose_has_#member:
        end iterate
        vkGetPhysicalDeviceMemoryProperties2 [physical_device],r13
        lea rsi,[r13+VkPhysicalDeviceMemoryProperties2.memoryProperties.memoryTypes]
        xor edi,edi
choose_memory_type:
        cmp edi,[r13+VkPhysicalDeviceMemoryProperties2.memoryProperties.memoryTypeCount]
        jae choose_no_memory
        mov eax,[rsi+VkMemoryType.propertyFlags]
        and eax,GPU_MEMORY
        cmp eax,GPU_MEMORY
        jne choose_next_memory
        mov eax,[rsi+VkMemoryType.heapIndex]
        imul eax,sizeof.VkMemoryHeap
        lea rdx,[r13+VkPhysicalDeviceMemoryProperties2.memoryProperties.memoryHeaps]
        cmp qword [rdx+rax+VkMemoryHeap.size],HEAP_BYTES
        jae choose_queues
choose_next_memory:
        inc edi
        add rsi,sizeof.VkMemoryType
        jmp choose_memory_type
choose_no_memory:
        or r12d,128
choose_queues:
        mov [family_count],32
        vkGetPhysicalDeviceQueueFamilyProperties [physical_device],addr family_count,addr families
        xor edi,edi
        lea rsi,[families]
choose_family:
        cmp edi,[family_count]
        jae choose_no_queue
        cmp [rsi+VkQueueFamilyProperties.queueCount],0
        je choose_next_family
        test [rsi+VkQueueFamilyProperties.queueFlags],VK_QUEUE_COMPUTE_BIT
        jnz choose_checked
choose_next_family:
        inc edi
        add rsi,sizeof.VkQueueFamilyProperties
        jmp choose_family
choose_no_queue:
        or r12d,256
choose_checked:
        mov [missing_contract],r12d
        test r12d,r12d
        jnz choose_next_adapter
        mov [queue_info.queueFamilyIndex],edi
        mov [pool_info.queueFamilyIndex],edi
        fastcall console_write_line,addr properties.properties.deviceName
        xor eax,eax
choose_done:
        ret
choose_next_adapter:
        inc ebx
        jmp choose_adapter
choose_unavailable:
        mov eax,VK_ERROR_FEATURE_NOT_PRESENT
        ret
endp

; A Vulkan buffer backs the allocation, once at setup. Shader work sees
; addresses. Select a compatible type having the exact mapped-GPU contract.
proc create_heap uses rbx rsi rdi r12,memory
        locals
                requirements VkMemoryRequirements
        endl
        mov r12,rcx
        vkCreateBuffer [device],addr buffer_info,0,addr heap.buffer
        test eax,eax
        jnz heap_done
        vkGetBufferMemoryRequirements [device],[heap.buffer],addr requirements
        lea rsi,[r12+VkPhysicalDeviceMemoryProperties2.memoryProperties.memoryTypes]
        xor ebx,ebx
heap_memory_type:
        cmp ebx,[r12+VkPhysicalDeviceMemoryProperties2.memoryProperties.memoryTypeCount]
        jae heap_unavailable
        bt [requirements.memoryTypeBits],ebx
        jnc heap_next_type
        mov eax,[rsi+VkMemoryType.propertyFlags]
        and eax,GPU_MEMORY
        cmp eax,GPU_MEMORY
        jne heap_next_type
        mov eax,[rsi+VkMemoryType.heapIndex]
        imul eax,sizeof.VkMemoryHeap
        lea rdx,[r12+VkPhysicalDeviceMemoryProperties2.memoryProperties.memoryHeaps]
        mov rcx,[requirements.size]
        cmp [rdx+rax+VkMemoryHeap.size],rcx
        jae heap_chosen
heap_next_type:
        inc ebx
        add rsi,sizeof.VkMemoryType
        jmp heap_memory_type
heap_chosen:
        mov [allocate_info.memoryTypeIndex],ebx
        mov rax,[requirements.size]
        mov [allocate_info.allocationSize],rax
        vkAllocateMemory [device],addr allocate_info,0,addr heap.memory
        test eax,eax
        jnz heap_done
        vkBindBufferMemory [device],[heap.buffer],[heap.memory],0
        test eax,eax
        jnz heap_done
        mov rax,[heap.buffer]
        mov [address_info.buffer],rax
        vkGetBufferDeviceAddress [device],addr address_info
        test rax,rax
        jz heap_unavailable
        mov [heap.address],rax
        mov [root.arguments],rax
        vkMapMemory [device],[heap.memory],0,VK_WHOLE_SIZE,0,addr heap.mapped
        test eax,eax
        jnz heap_done
        mov rdi,[heap.mapped]
        mov rax,[heap.address]
        lea rdx,[rax+A_OFFSET]
        mov [rdi+NoApiArguments.input_a],rdx
        lea rdx,[rax+B_OFFSET]
        mov [rdi+NoApiArguments.input_b],rdx
        lea rdx,[rax+C_OFFSET]
        mov [rdi+NoApiArguments.output],rdx
        xor ecx,ecx
heap_input_a:
        mov [rdi+rcx*4+A_OFFSET],ecx
        inc ecx
        cmp ecx,ELEMENTS
        jb heap_input_a
        xor eax,eax
heap_done:
        ret
heap_unavailable:
        mov [missing_contract],128
        mov eax,VK_ERROR_FEATURE_NOT_PRESENT
        ret
endp

; Warm the only two Vulkan calls made by the recurring batch loop.
proc resolve_hot_calls
        iterate function, vkQueueSubmit2,vkWaitSemaphores
                vkGetDeviceProcAddr [device],addr name_#function
                test rax,rax
                jz .missing
                mov [function],rax
        end iterate
        xor eax,eax
        ret
.missing:
        mov eax,VK_ERROR_INITIALIZATION_FAILED
        ret
endp

; RCX = batch, 1..3. Root and arrays change through ordinary CPU stores.
proc prepare_batch uses rdi
        mov rdi,[heap.mapped]
        mov eax,ELEMENTS
        sub eax,ecx
        mov [rdi+NoApiArguments.count],eax
        imul eax,ecx,1000
        mov [rdi+NoApiArguments.bias],eax
        xor edx,edx
.element:
        lea eax,[edx+edx*2]
        add eax,ecx
        mov [rdi+rdx*4+B_OFFSET],eax
        mov dword [rdi+rdx*4+C_OFFSET],0DEADBEEFh
        inc edx
        cmp edx,ELEMENTS
        jb .element
        ret
endp

; Independent oracle: 4*i + 1001*batch, then unchanged guarded tail.
proc verify_batch uses rdi
        mov rdi,[heap.mapped]
        add rdi,C_OFFSET
        mov edx,ELEMENTS
        sub edx,ecx
        imul eax,ecx,1001
        xor ecx,ecx
.element:
        cmp [rdi+rcx*4],eax
        jne .mismatch
        add eax,4
        inc ecx
        cmp ecx,edx
        jb .element
.tail:
        cmp dword [rdi+rcx*4],0DEADBEEFh
        jne .mismatch
        inc ecx
        cmp ecx,ELEMENTS
        jb .tail
        mov eax,1
        ret
.mismatch:
        xor eax,eax
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

proc release_noapi
        cmp [device],0
        je .instance
        vkDeviceWaitIdle [device]
        iterate <function,owner>, vkDestroyCommandPool,command_pool, vkDestroyPipeline,pipeline, \
                vkDestroyPipelineLayout,pipeline_layout, vkDestroySemaphore,timeline, vkDestroyBuffer,heap.buffer, vkFreeMemory,heap.memory
                cmp [owner],0
                je .skip_#function
                function [device],[owner],0
        .skip_#function:
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

section '.rdata$noapi' data readable align 16
shader_code file 'build/recipe_compute_noapi.spv'
shader_bytes := $-shader_code
assert shader_bytes mod 4 = 0
entry_name db 'main',0
version_name db 'vkEnumerateInstanceVersion',0
debug_extension db VK_EXT_DEBUG_UTILS_EXTENSION_NAME,0
name_vkQueueSubmit2 db 'vkQueueSubmit2',0
name_vkWaitSemaphores db 'vkWaitSemaphores',0
ready_text db '[noapi] setup: one GPU allocation, one pipeline, commands recorded once',0
batch_format db '[noapi] batch %u: verified %u sums + %u guarded tail elements; bias %u',0
success_text db '[noapi] verified 3 resident-pointer batches; 1 command recording, 3 submissions',0
error_format db '[noapi] failed at step %u, result %d, rejected requirements 0x%X',0
contract_text db '[noapi] fixed contract: Vulkan 1.4, BDA, scalar layout, timeline, sync2, maintenance5, coherent mapped GPU memory, compute queue',0
validation_text db '[noapi] validation emitted a warning or error',0

section '.data$noapi' data readable writeable align 16
queue_priority dd 1.0
enabled12 VkPhysicalDeviceVulkan12Features sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,pNext: enabled13, \
        bufferDeviceAddress: VK_TRUE,scalarBlockLayout: VK_TRUE,timelineSemaphore: VK_TRUE
enabled13 VkPhysicalDeviceVulkan13Features sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,pNext: enabled14,synchronization2: VK_TRUE
enabled14 VkPhysicalDeviceVulkan14Features sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,maintenance5: VK_TRUE
application_info VkApplicationInfo sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,apiVersion: VK_API_VERSION_1_4
debug_names dq debug_extension
debug_info VkDebugUtilsMessengerCreateInfoEXT sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
        messageSeverity: VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT, \
        messageType: VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT, \
        pfnUserCallback: debug_callback
instance_info VkInstanceCreateInfo sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,pApplicationInfo: application_info,ppEnabledExtensionNames: debug_names
queue_info VkDeviceQueueCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,queueCount: 1,pQueuePriorities: queue_priority
device_info VkDeviceCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,pNext: enabled12,queueCreateInfoCount: 1,pQueueCreateInfos: queue_info
buffer_info VkBufferCreateInfo sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,size: HEAP_BYTES, \
        usage: VK_BUFFER_USAGE_STORAGE_BUFFER_BIT or VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,sharingMode: VK_SHARING_MODE_EXCLUSIVE
allocation_flags VkMemoryAllocateFlagsInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,flags: VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT
allocate_info VkMemoryAllocateInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,pNext: allocation_flags
address_info VkBufferDeviceAddressInfo sType: VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO
push_range VkPushConstantRange stageFlags: VK_SHADER_STAGE_COMPUTE_BIT,size: sizeof.NoApiRoot
layout_info VkPipelineLayoutCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,pushConstantRangeCount: 1,pPushConstantRanges: push_range
shader_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: shader_bytes,pCode: shader_code
pipeline_info VkComputePipelineCreateInfo sType: VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO, \
        stage.sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,stage.pNext: shader_info,stage.stage: VK_SHADER_STAGE_COMPUTE_BIT,stage.pName: entry_name
pool_info VkCommandPoolCreateInfo sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
command_info VkCommandBufferAllocateInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,commandBufferCount: 1
begin_info VkCommandBufferBeginInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
timeline_type VkSemaphoreTypeCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,semaphoreType: VK_SEMAPHORE_TYPE_TIMELINE
timeline_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,pNext: timeline_type
signal_info VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
command_submit VkCommandBufferSubmitInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,deviceMask: 1
submit_info VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,commandBufferInfoCount: 1,pCommandBufferInfos: command_submit,signalSemaphoreInfoCount: 1,pSignalSemaphoreInfos: signal_info
wait_info VkSemaphoreWaitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,semaphoreCount: 1,pSemaphores: timeline,pValues: wait_value
host_barrier VkMemoryBarrier2 sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,srcStageMask: VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, \
        srcAccessMask: VK_ACCESS_2_SHADER_WRITE_BIT,dstStageMask: VK_PIPELINE_STAGE_2_HOST_BIT,dstAccessMask: VK_ACCESS_2_HOST_READ_BIT
host_dependency VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,memoryBarrierCount: 1,pMemoryBarriers: host_barrier

; Reserved COFF storage: Windows supplies the initial zeros without file bytes.
section '.bss$noapi' readable writeable align 16
instance dq ?
device dq ?
physical_device dq ?
queue dq ?
messenger dq ?
heap NoApiHeap
root NoApiRoot
pipeline_layout dq ?
pipeline dq ?
command_pool dq ?
command_buffer dq ?
timeline dq ?
wait_value dq ?
validation_failed dd ?
failure_stage dd ?
missing_contract dd ?
