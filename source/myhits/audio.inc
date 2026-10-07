; Sound out: XAudio2, called through its interfaces' tables. One mastering
; voice and a ring of source voices, each mono float at the bank's rate. A
; sound is a run of the bank's samples, which the device rendered into memory
; the CPU can read (sounds.slang); a voice plays it from there, uncopied.
;
; A program includes this after machine.inc and tables.inc, lays down
; game_sounds, links xaudio2.lib and ole32.lib, and calls:
;
;	audio_start	ECX nonzero: make no noise (the checks). Returns 0 when there
;			is no way to make sound; everything else here then does
;			its sums and plays nothing.
;	audio_events	RCX = a frame's Events, RDX = the recipes as laid down,
;			R8 = the bank. Plays what the frame asked for.
;	audio_stop
iterate function, XAudio2Create,CoInitializeEx,CoUninitialize,Sleep
	extrn function:qword
end iterate

AUDIO_VOICES := 16			; a power of two
; Where each method is in its interface's table. A voice is not a COM object:
; its table begins with its own methods.
XAUDIO2_Release := 2*8
XAUDIO2_CreateSourceVoice := 5*8
XAUDIO2_CreateMasteringVoice := 7*8
XAUDIO2_GetPerformanceData := 11*8
VOICE_SetVolume := 12*8
VOICE_SetOutputMatrix := 16*8
VOICE_DestroyVoice := 18*8
SOURCE_Start := 19*8
SOURCE_Stop := 20*8
SOURCE_SubmitSourceBuffer := 21*8
SOURCE_FlushSourceBuffers := 22*8
SOURCE_GetState := 25*8
SOURCE_SetFrequencyRatio := 26*8
XAUDIO2_END_OF_STREAM := 40h
XAUDIO2_VOICE_NOSAMPLESPLAYED := 100h

; Call a method of an object: its first word points at its table. (fastcall
; uses RAX for its own purposes and leaves R11 alone.)
macro method object*,slot*,arguments&
	mov r11,object
	mov r11,[r11]
	match any, arguments
		fastcall qword [r11+slot],object,arguments
	else
		fastcall qword [r11+slot],object
	end match
end macro

section '.text$audio' code readable executable align 16

proc audio_start uses rbx rsi,muted
	mov esi,ecx
	fastcall CoInitializeEx,0,0
	fastcall XAudio2Create,addr audio_engine,0,1
	test eax,eax
	js .none
	; Stereo at the bank's rate, as game effects.
	method [audio_engine],XAUDIO2_CreateMasteringVoice,addr audio_master,2,SOUND_RATE,0,0,0,6
	test eax,eax
	js .release
	test esi,esi
	jz .voices
	xorps xmm1,xmm1
	method [audio_master],VOICE_SetVolume,0,0
.voices:
	xor ebx,ebx
.voice:
	lea rdx,[audio_voices]
	lea rdx,[rdx+rbx*8]
	; A voice may be played up to twice as fast as it was made.
	method [audio_engine],XAUDIO2_CreateSourceVoice,rdx,addr audio_format,0,40000000h,0,0,0
	test eax,eax
	js .stop
	inc ebx
	cmp ebx,AUDIO_VOICES
	jb .voice
	mov [audio_ready],1
	mov eax,1
	ret
.stop:
	fastcall audio_stop
	xor eax,eax
	ret
.release:
	method [audio_engine],XAUDIO2_Release
.none:
	mov [audio_engine],0
	xor eax,eax
	ret
endp

; Play a run of samples: RCX = the first, EDX = how many, R8D = where on the
; playfield it happened (a float's bits), R9D = how many times it was asked
; for this frame. Many are one voice, louder; it sits between the speakers
; where it happened on the screen, at equal power; and it is a little off
; pitch, a different little each time, so a run of one sound is not a machine.
proc audio_play uses rbx rsi rdi,samples,length,where,count
	mov rsi,rcx
	mov edi,edx
	mov [audio_scratch],r8d
	lea eax,[r9+3]
	cvtsi2ss xmm0,eax
	mulss xmm0,[audio_quarter]
	minss xmm0,[audio_two]
	mulss xmm0,[audio_gain]
	movss [audio_level],xmm0
	movss xmm1,[audio_scratch]
	divss xmm1,[playfield_PLAYFIELD_WIDTH]
	xorps xmm2,xmm2
	maxss xmm1,xmm2
	minss xmm1,[audio_one]
	mulss xmm1,[audio_quarter_turn]
	movss [audio_scratch],xmm1
	fld dword [audio_scratch]
	fsincos
	fmul dword [audio_level]
	fstp dword [audio_matrix]
	fmul dword [audio_level]
	fstp dword [audio_matrix+4]
	inc [audio_plays]
	cmp [audio_ready],0
	je .done
	mov eax,[audio_next]
	inc [audio_next]
	and eax,AUDIO_VOICES-1
	lea rbx,[audio_voices]
	mov rbx,[rbx+rax*8]
	method rbx,SOURCE_Stop,0,0
	method rbx,SOURCE_FlushSourceBuffers
	imul eax,[audio_seed],1664525
	add eax,1013904223
	mov [audio_seed],eax
	shr eax,8
	cvtsi2ss xmm1,eax
	mulss xmm1,[audio_pitch_spread]
	addss xmm1,[audio_pitch_low]
	method rbx,SOURCE_SetFrequencyRatio,0,0
	method rbx,VOICE_SetOutputMatrix,0,1,2,addr audio_matrix,0
	test eax,eax
	js .failed
	shl edi,2
	mov [audio_buffer.bytes],edi
	mov [audio_buffer.data],rsi
	method rbx,SOURCE_SubmitSourceBuffer,addr audio_buffer,0
	test eax,eax
	js .failed
	method rbx,SOURCE_Start,0,0
	test eax,eax
	jns .done
.failed:
	inc [audio_failures]
.done:
	ret
endp

; What one frame's events asked for. A trigger is a count and a sum of
; offsets from the middle of the playfield: the sound is played once, where
; their mean is.
proc audio_events uses rbx rsi rdi r12,events,recipes,bank
	mov rbx,rcx
	mov rsi,rdx
	mov rdi,r8
	xor r12d,r12d
.sound:
	mov eax,r12d
	imul eax,sizeof.Trigger
	mov r9d,[rbx+Events.sound+rax+Trigger.count]
	test r9d,r9d
	jz .next
	cvtsi2ss xmm0,dword [rbx+Events.sound+rax+Trigger.pan]
	cvtsi2ss xmm1,r9d
	divss xmm0,xmm1
	addss xmm0,[audio_middle]
	movd r8d,xmm0
	mov eax,r12d
	imul eax,sizeof.Recipe
	mov ecx,[rsi+rax+Recipe.first]
	lea rcx,[rdi+rcx*4]
	mov edx,[rsi+rax+Recipe.samples]
	fastcall audio_play,rcx,rdx,r8,r9
.next:
	inc r12d
	cmp r12d,TABLE_SOUNDS
	jb .sound
	ret
endp

; Wait until every voice has played out what it was given, or a second and a
; half has passed. Returns how many buffers are still waiting.
proc audio_idle uses rbx rsi rdi
	xor eax,eax
	cmp [audio_ready],0
	je .done
	mov edi,150
.again:
	xor esi,esi
	xor ebx,ebx
.voice:
	lea rcx,[audio_voices]
	mov rcx,[rcx+rbx*8]
	mov [audio_voice],rcx
	method [audio_voice],SOURCE_GetState,addr audio_state,XAUDIO2_VOICE_NOSAMPLESPLAYED
	add esi,dword [audio_state+8]
	inc ebx
	cmp ebx,AUDIO_VOICES
	jb .voice
	mov eax,esi
	test esi,esi
	jz .done
	dec edi
	jz .done
	fastcall Sleep,10
	jmp .again
.done:
	ret
endp

; What the engine itself adds between a voice starting and the sound leaving, in samples.
proc audio_latency
	xor eax,eax
	cmp [audio_ready],0
	je .done
	method [audio_engine],XAUDIO2_GetPerformanceData,addr audio_performance
	mov eax,dword [audio_performance+28]
.done:
	ret
endp

proc audio_stop uses rbx
	cmp [audio_engine],0
	je .done
	mov [audio_ready],0
	xor ebx,ebx
.voice:
	lea rcx,[audio_voices]
	mov rcx,[rcx+rbx*8]
	test rcx,rcx
	jz .next
	mov [audio_voice],rcx
	method [audio_voice],VOICE_DestroyVoice
	lea rcx,[audio_voices]
	mov qword [rcx+rbx*8],0
.next:
	inc ebx
	cmp ebx,AUDIO_VOICES
	jb .voice
	cmp [audio_master],0
	je .engine
	method [audio_master],VOICE_DestroyVoice
	mov [audio_master],0
.engine:
	method [audio_engine],XAUDIO2_Release
	mov [audio_engine],0
	fastcall CoUninitialize
.done:
	ret
endp

section '.data$audio' data readable writeable align 16
audio_engine dq 0
audio_master dq 0
audio_voice dq 0
audio_voices rq AUDIO_VOICES
audio_ready dd 0
audio_next dd 0
audio_plays dd 0			; sounds asked of the voices
audio_failures dd 0			; and how many a voice refused
audio_seed dd 2463534242
audio_scratch dd 0
audio_level dd 0
audio_matrix dd 0,0			; how much of a voice goes left, and right
audio_gain dd 0.5
audio_quarter dd 0.25
audio_one dd 1.0
audio_two dd 2.0
audio_middle dd 960.0
audio_quarter_turn dd 1.5707964
audio_pitch_low dd 0.96
audio_pitch_spread dd 4.7683716e-9	; 0.08 over 2^24: the ratio runs 0.96 to 1.04
; WAVEFORMATEX and XAUDIO2_BUFFER are packed to the byte.
audio_format:
	dw 3,1				; IEEE float, one channel
	dd SOUND_RATE,SOUND_RATE*4
	dw 4,32,0
audio_buffer:
	dd XAUDIO2_END_OF_STREAM
audio_buffer.bytes dd 0
audio_buffer.data dq 0
	dd 0,0,0,0,0
	dq 0
audio_state:
	rb 24
audio_performance:
	rb 64
