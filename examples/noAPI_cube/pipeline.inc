section '.text$cube_pipeline' code readable executable align 16
proc create_pipeline
	test [active_caps],CAP_RENDER
	jnz .layout
	require_vk vkCreateRenderPass [device],addr renderpass_info,0,addr render_pass
	mov rax,[render_pass]
	mov [framebuffer_info.renderPass],rax
	mov [pipeline_info.renderPass],rax
	mov [renderpass_begin.renderPass],rax
.layout:
	test [active_caps],CAP_HEAP
	jnz .native
	lea rax,[descriptor_layout]
	mov [layout_info.pSetLayouts],rax
	require_vk vkCreatePipelineLayout [device],addr layout_info,0,addr pipeline_layout
	mov rax,[pipeline_layout]
	mov [pipeline_info.layout],rax
	test [active_caps],CAP_ADDRESS
	jz .bindings
	lea rax,[pointer_code]
	mov [vertex_module_info.pCode],rax
	mov [vertex_module_info.codeSize],pointer_code.size
	jmp .stages
.bindings:
	mov [vertex_input.vertexBindingDescriptionCount],1
	lea rax,[vertex_binding]
	mov [vertex_input.pVertexBindingDescriptions],rax
	mov [vertex_input.vertexAttributeDescriptionCount],2
	lea rax,[vertex_attributes]
	mov [vertex_input.pVertexAttributeDescriptions],rax
	jmp .stages
.native:
	lea rax,[heap_vertex_code]
	mov [vertex_module_info.pCode],rax
	mov [vertex_module_info.codeSize],heap_vertex_code.size
	lea rax,[heap_fragment_code]
	mov [fragment_module_info.pCode],rax
	mov [fragment_module_info.codeSize],heap_fragment_code.size
	lea rax,[heap_vertex_entry]
	mov [vertex_stage.pName],rax
	lea rax,[heap_fragment_entry]
	mov [fragment_stage.pName],rax
.stages:
	test [active_caps],CAP_INLINE
	jz .modules
	lea rax,[vertex_module_info]
	mov [vertex_stage.pNext],rax
	lea rax,[fragment_module_info]
	mov [fragment_stage.pNext],rax
	jmp .pipeline
.modules:
	require_vk vkCreateShaderModule [device],addr vertex_module_info,0,addr vertex_module
	mov rax,[vertex_module]
	mov [vertex_stage.module],rax
	require_vk vkCreateShaderModule [device],addr fragment_module_info,0,addr fragment_module
	mov rax,[fragment_module]
	mov [fragment_stage.module],rax
.pipeline:
	test [active_caps],CAP_RENDER
	jz .create
	lea rax,[pipeline_rendering]
	mov [pipeline_info.pNext],rax
	test [active_caps],CAP_HEAP
	jz .create
	lea rax,[heap_pipeline_flags]
	mov [pipeline_info.pNext],rax
.create:
	require_vk vkCreateGraphicsPipelines [device],0,1,addr pipeline_info,0,addr pipeline
	cmp [vertex_module],0
	je .ready
	vkDestroyShaderModule [device],[vertex_module],0
	mov [vertex_module],0
	vkDestroyShaderModule [device],[fragment_module],0
	mov [fragment_module],0
.ready:
	mov eax,1
	ret
.failed:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

section '.data$cube_pipeline' data readable writeable align 8
render_pass dq 0
pipeline_layout dq 0
pipeline dq 0
vertex_module dq 0
fragment_module dq 0
push_range VkPushConstantRange stageFlags: VK_SHADER_STAGE_VERTEX_BIT or VK_SHADER_STAGE_FRAGMENT_BIT,size: ROOT_BYTES
layout_info VkPipelineLayoutCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,setLayoutCount: 1,pushConstantRangeCount: 1,pPushConstantRanges: push_range
vertex_module_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: vertex_code.size,pCode: vertex_code
fragment_module_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: fragment_code.size,pCode: fragment_code
main_entry GLOBSTR 'main',0
heap_vertex_entry GLOBSTR 'vertexMain',0
heap_fragment_entry GLOBSTR 'fragmentMain',0
stages:
vertex_stage VkPipelineShaderStageCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,stage: VK_SHADER_STAGE_VERTEX_BIT,pName: main_entry
fragment_stage VkPipelineShaderStageCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,stage: VK_SHADER_STAGE_FRAGMENT_BIT,pName: main_entry,pSpecializationInfo: material_specialization
material_specialization VkSpecializationInfo mapEntryCount: 1,pMapEntries: material_constant_map,dataSize: 4,pData: material_flags
material_constant_map:
	VkSpecializationMapEntry constantID: 0,offset: 0,size: 4
vertex_input VkPipelineVertexInputStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
vertex_binding VkVertexInputBindingDescription binding: 0,stride: 24,inputRate: VK_VERTEX_INPUT_RATE_VERTEX
vertex_attributes:
	VkVertexInputAttributeDescription location: 0,binding: 0,format: VK_FORMAT_R32G32B32A32_SFLOAT,offset: 0
	VkVertexInputAttributeDescription location: 1,binding: 0,format: VK_FORMAT_R32G32_SFLOAT,offset: 16
input_assembly VkPipelineInputAssemblyStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
viewport_state VkPipelineViewportStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,viewportCount: 1,scissorCount: 1
raster_state VkPipelineRasterizationStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,polygonMode: VK_POLYGON_MODE_FILL,cullMode: VK_CULL_MODE_BACK_BIT,frontFace: VK_FRONT_FACE_COUNTER_CLOCKWISE,lineWidth: 1.0
multisample_state VkPipelineMultisampleStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,rasterizationSamples: VK_SAMPLE_COUNT_1_BIT
depth_state VkPipelineDepthStencilStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,depthTestEnable: VK_TRUE,depthWriteEnable: VK_TRUE,depthCompareOp: VK_COMPARE_OP_LESS_OR_EQUAL
blend_attachment VkPipelineColorBlendAttachmentState colorWriteMask: 15
blend_state VkPipelineColorBlendStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,attachmentCount: 1,pAttachments: blend_attachment
dynamic_states dd VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR
dynamic_state VkPipelineDynamicStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,dynamicStateCount: 2,pDynamicStates: dynamic_states
pipeline_rendering VkPipelineRenderingCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,colorAttachmentCount: 1,pColorAttachmentFormats: target_format
heap_pipeline_flags VkPipelineCreateFlags2CreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_CREATE_FLAGS_2_CREATE_INFO,pNext: pipeline_rendering,flags: VK_PIPELINE_CREATE_2_DESCRIPTOR_HEAP_BIT_EXT
pipeline_info VkGraphicsPipelineCreateInfo sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,stageCount: 2,pStages: stages,pVertexInputState: vertex_input,pInputAssemblyState: input_assembly,pViewportState: viewport_state,pRasterizationState: raster_state,pMultisampleState: multisample_state,pDepthStencilState: depth_state,pColorBlendState: blend_state,pDynamicState: dynamic_state,basePipelineIndex: -1
attachments:
color_attachment VkAttachmentDescription samples: VK_SAMPLE_COUNT_1_BIT,loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,storeOp: VK_ATTACHMENT_STORE_OP_STORE,stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,initialLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
depth_attachment VkAttachmentDescription samples: VK_SAMPLE_COUNT_1_BIT,loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,storeOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,initialLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,finalLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
color_ref VkAttachmentReference attachment: 0,layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
depth_ref VkAttachmentReference attachment: 1,layout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
subpass VkSubpassDescription pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,colorAttachmentCount: 1,pColorAttachments: color_ref,pDepthStencilAttachment: depth_ref
renderpass_info VkRenderPassCreateInfo sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,attachmentCount: 2,pAttachments: attachments,subpassCount: 1,pSubpasses: subpass
framebuffer_info VkFramebufferCreateInfo sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,attachmentCount: 2,pAttachments: framebuffer_views,layers: 1
clear_values dd 0.2,0.2,0.2,1.0, 1.0,0,0,0
render_color VkRenderingAttachmentInfo sType: VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,imageLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,storeOp: VK_ATTACHMENT_STORE_OP_STORE
render_depth VkRenderingAttachmentInfo sType: VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,imageLayout: VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,storeOp: VK_ATTACHMENT_STORE_OP_DONT_CARE
rendering_info VkRenderingInfo sType: VK_STRUCTURE_TYPE_RENDERING_INFO,layerCount: 1,colorAttachmentCount: 1,pColorAttachments: render_color,pDepthAttachment: render_depth
renderpass_begin VkRenderPassBeginInfo sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,clearValueCount: 2,pClearValues: clear_values
viewport VkViewport minDepth: 0.0,maxDepth: 1.0
scissor VkRect2D

section '.rdata$cube_spirv' data readable align 4
vertex_code file 'build\noAPI_cube_bindings.spv'
vertex_code.size = $ - vertex_code
align 4
pointer_code file 'build\noAPI_cube_pointer.spv'
pointer_code.size = $ - pointer_code
align 4
fragment_code file 'build\noAPI_cube_fragment.spv'
fragment_code.size = $ - fragment_code
align 4
heap_vertex_code file 'build\noAPI_cube_heap_vertex.spv'
heap_vertex_code.size = $ - heap_vertex_code
align 4
heap_fragment_code file 'build\noAPI_cube_heap_fragment.spv'
heap_fragment_code.size = $ - heap_fragment_code
