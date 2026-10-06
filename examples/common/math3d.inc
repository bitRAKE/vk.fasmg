; Row-major 4x4 matrices. Destination must not alias either input.
section '.text$math3d' code readable executable align 16
proc matrix_multiply destination,left,right
	movups xmm2,[r8]
	movups xmm3,[r8+16]
	movups xmm4,[r8+32]
	movups xmm5,[r8+48]
	mov r9d,4
.row:
	movss xmm0,[rdx]
	shufps xmm0,xmm0,0
	mulps xmm0,xmm2
	movss xmm1,[rdx+4]
	shufps xmm1,xmm1,0
	mulps xmm1,xmm3
	addps xmm0,xmm1
	movss xmm1,[rdx+8]
	shufps xmm1,xmm1,0
	mulps xmm1,xmm4
	addps xmm0,xmm1
	movss xmm1,[rdx+12]
	shufps xmm1,xmm1,0
	mulps xmm1,xmm5
	addps xmm0,xmm1
	movups [rcx],xmm0
	add rdx,16
	add rcx,16
	dec r9d
	jnz .row
	ret
endp
