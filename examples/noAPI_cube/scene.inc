; Geometry, view, and material match NoGraphicsAPI/examples/cube.
; Match the original 72-byte root ABI: vertex address, then row-major transform.
CUBE_VERTEX_BYTES := 24*24
CUBE_INDEX_BYTES := 36*2
TEXTURE_BYTES := 256*256*4
ROOT_BYTES := 72

include '..\common\math3d.inc'
section '.text$scene' code readable executable align 16
proc update_scene
	movss xmm0,[angle]
	mulss xmm0,[radians]
	movss [angle_radians],xmm0
	fld dword [angle_radians]
	fsincos
	fst dword [rotation]
	fstp dword [rotation+40]
	fst dword [rotation+8]
	fchs
	fstp dword [rotation+32]
	cvtsi2ss xmm0,dword [frame_height]
	mulss xmm0,[focal_length]
	cvtsi2ss xmm1,dword [frame_width]
	divss xmm0,xmm1
	movss [projection],xmm0
	fastcall matrix_multiply,addr view_rotation,addr view,addr rotation
	fastcall matrix_multiply,addr cube_root.transform,addr projection,addr view_rotation
	ret
endp

section '.data$scene' data readable writeable align 16
angle dd 0.0
angle_radians dd 0.0
rotation dd 1.0,0.0,0.0,0.0, 0.0,1.0,0.0,0.0, 0.0,0.0,1.0,0.0, 0.0,0.0,0.0,1.0
projection dd 2.414213562373095,0.0,0.0,0.0, 0.0,-2.414213562373095,0.0,0.0, \
	0.0,0.0,-1.001001001001,-0.1001001001001, 0.0,0.0,-1.0,0.0
view_rotation rd 16
align 16
cube_root:
.vertices dq 0
.transform rb 64
assert cube_root.vertices - cube_root = 0
assert cube_root.transform - cube_root = 8
assert $ - cube_root = ROOT_BYTES

section '.rdata$scene' data readable align 16
view dd 1.0,0.0,0.0,0.0, 0.0,0.857492925712544,-0.514495755427526,0.0, \
	0.0,0.514495755427526,0.857492925712544,-5.830951894845301, 0.0,0.0,0.0,1.0
radians dd 0.017453292519943295
focal_length dd 2.414213562373095
spin_step dd 4.0
full_turn dd 360.0
macro cube_vertex x,y,z,u,v
	dd x*1.0,y*1.0,z*1.0,1.0,u*1.0,v*1.0
end macro
cube_vertices:
	cube_vertex -1,-1,-1,0,1
	cube_vertex -1,-1,1,1,1
	cube_vertex -1,1,1,1,0
	cube_vertex -1,1,-1,0,0
	cube_vertex -1,-1,-1,1,1
	cube_vertex -1,1,-1,1,0
	cube_vertex 1,1,-1,0,0
	cube_vertex 1,-1,-1,0,1
	cube_vertex -1,-1,-1,1,0
	cube_vertex 1,-1,-1,1,1
	cube_vertex 1,-1,1,0,1
	cube_vertex -1,-1,1,0,0
	cube_vertex -1,1,-1,1,0
	cube_vertex -1,1,1,1,1
	cube_vertex 1,1,1,0,1
	cube_vertex 1,1,-1,0,0
	cube_vertex 1,1,-1,1,0
	cube_vertex 1,1,1,1,1
	cube_vertex 1,-1,1,0,1
	cube_vertex 1,-1,-1,0,0
	cube_vertex -1,-1,1,0,1
	cube_vertex 1,-1,1,1,1
	cube_vertex 1,1,1,1,0
	cube_vertex -1,1,1,0,0
assert $ - cube_vertices = CUBE_VERTEX_BYTES
cube_indices dw 0,1,2,2,3,0, 4,5,6,6,7,4, 8,9,10,10,11,8, 12,13,14,14,15,12, 16,17,18,18,19,16, 20,21,22,22,23,20
assert $ - cube_indices = CUBE_INDEX_BYTES
texture_pixels file 'examples\noAPI_cube\lunarg_logo_256x256.rgba8'
assert $ - texture_pixels = TEXTURE_BYTES
