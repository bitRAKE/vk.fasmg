; The pad, when there is one: XInput's first. Its left stick and d-pad are
; Root.move, its right stick carries the crosshair, its buttons are the
; BUTTON_ bits. machine_sample calls pad_sample after the keys and the mouse,
; so a pad in use has the last word. (Rumble comes with the hits that earn it.)

PAD_BUTTONS := 4			; XINPUT_STATE, by offset
PAD_RIGHT_TRIGGER := 7
PAD_LEFT_X := 8
PAD_LEFT_Y := 10
PAD_RIGHT_X := 12
PAD_RIGHT_Y := 14
PAD_UP := 1
PAD_DOWN := 2
PAD_LEFT := 4
PAD_RIGHT := 8
PAD_START := 10h
PAD_A := 1000h
PAD_B := 2000h
PAD_X := 4000h
PAD_LEFT_DEAD := 7849			; XInput's own dead zones
PAD_RIGHT_DEAD := 8689

section '.text$input' code readable executable align 16

; A stick, EAX and EDX as XInput gives them and ECX its dead zone, as XMM0 and
; XMM1: nothing inside the dead zone, then evenly out to 1 at the rim, with y
; turned to run down the playfield.
proc pad_stick
	cvtsi2ss xmm0,eax
	cvtsi2ss xmm1,edx
	cvtsi2ss xmm4,ecx
	movaps xmm2,xmm0
	mulss xmm2,xmm2
	movaps xmm3,xmm1
	mulss xmm3,xmm3
	addss xmm2,xmm3
	sqrtss xmm2,xmm2
	ucomiss xmm2,xmm4
	jbe .rest
	movaps xmm3,xmm2
	subss xmm3,xmm4
	movss xmm5,[pad_rim]
	subss xmm5,xmm4
	divss xmm3,xmm5
	minss xmm3,[pad_one]
	divss xmm3,xmm2
	mulss xmm0,xmm3
	mulss xmm1,xmm3
	xorps xmm1,xword [pad_sign]
	ret
.rest:
	xorps xmm0,xmm0
	xorps xmm1,xmm1
	ret
endp

; One XINPUT_STATE into Root, over what the keys and the mouse left there.
proc pad_apply uses rbx,state
	mov rbx,rcx
	movsx eax,word [rbx+PAD_LEFT_X]
	movsx edx,word [rbx+PAD_LEFT_Y]
	mov ecx,PAD_LEFT_DEAD
	fastcall pad_stick
	xorps xmm3,xmm3
	ucomiss xmm0,xmm3
	jne .stick
	ucomiss xmm1,xmm3
	je .buttons
.stick:
	movss dword [root+Root.move],xmm0
	movss dword [root+Root.move+4],xmm1
.buttons:
	movzx eax,word [rbx+PAD_BUTTONS]
	iterate <bit,offset,value>, PAD_LEFT,0,-1.0, PAD_RIGHT,0,1.0, PAD_UP,4,-1.0, PAD_DOWN,4,1.0
		test eax,bit
		jz .not_#bit
		mov dword [root+Root.move+offset],value
	.not_#bit:
	end iterate
	iterate <bit,button>, PAD_A,BUTTON_FIRE, PAD_B or PAD_X,BUTTON_SECOND, PAD_START,BUTTON_START
		test eax,bit
		jz .off_#button
		or dword [root+Root.held],button
	.off_#button:
	end iterate
	cmp byte [rbx+PAD_RIGHT_TRIGGER],30
	jbe .aim
	or dword [root+Root.held],BUTTON_FIRE
.aim:
	movsx eax,word [rbx+PAD_RIGHT_X]
	movsx edx,word [rbx+PAD_RIGHT_Y]
	mov ecx,PAD_RIGHT_DEAD
	fastcall pad_stick
	movss xmm2,[pad_aim_speed]
	mulss xmm2,dword [root+Root.dt]
	mulss xmm0,xmm2
	mulss xmm1,xmm2
	xorps xmm3,xmm3
	addss xmm0,dword [root+Root.aim]
	maxss xmm0,xmm3
	minss xmm0,[playfield_PLAYFIELD_WIDTH]
	movss dword [root+Root.aim],xmm0
	addss xmm1,dword [root+Root.aim+4]
	maxss xmm1,xmm3
	minss xmm1,[playfield_PLAYFIELD_HEIGHT]
	movss dword [root+Root.aim+4],xmm1
	ret
endp

proc pad_sample
	cmp [pad_present],0
	jne .poll
	; An empty port is slow to ask: once a second or so is enough.
	test dword [root+Root.frame],63
	jnz .done
.poll:
	fastcall XInputGetState,0,addr pad_state
	mov [pad_present],0
	test eax,eax
	jnz .done
	mov [pad_present],1
	fastcall pad_apply,addr pad_state
.done:
	ret
endp

section '.data$input' data readable writeable align 16
pad_sign dd 80000000h,0,0,0
pad_rim dd 32767.0
pad_one dd 1.0
pad_aim_speed dd 1400.0			; playfield units a second at the rim
pad_present dd 0
pad_state:
	rb 16