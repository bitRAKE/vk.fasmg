; myhits: a horizontal shooter whose world lives on the GPU. The CPU reads the
; controls, sends 72 bytes a frame, reads 512 back, and plays the sounds they
; ask for. Everything else is in myhits.slang and the tables.
;
;	build\myhits.exe		play: arrows or WASD or a pad move, Space or the
;					left button fires, Shift or the right button
;					launches a pair of missiles at the crosshair
;					for a quarter of the charge, Ctrl or the
;					middle button dashes for a fifth of it, Enter
;					begins again when a run is over; P pauses, F11
;					or Alt+Enter takes or gives back the whole
;					monitor, Esc ends
;	build\myhits.exe --windowed	the same, as a window whatever it was last
;	build\myhits.exe --fullscreen	the same, over the whole monitor whatever it was last
;	build\myhits.exe --watch	the same, but it goes on when it is left for another
;					program, and takes its tables again whenever
;					build\myhits_tables.bin changes: tools\watch.ps1
;					makes that file anew when tables.inc is saved
;	build\myhits.exe --record	the same, and every frame's controls go to
;					build\myhits_last.run as it is played
;	build\myhits.exe --replay	that run again, from the record, and then on from
;					where it ended, in the player's hands
;	    --record file, --replay file	the same, to or from a file of that name;
;					both together, a run played back and kept
;					again, with whatever is then played after it
;	    --self-test --replay file --strip n	that run unseen, but for a picture of it
;					every n seconds: tools\strip.ps1 makes a
;					page of them
;	build\myhits.exe --self-test	a scripted run of four games, every claim checked
;
; Its window has no caption. While it plays the pointer is the crosshair and
; cannot leave; paused, or left for another program (which pauses it), the
; pointer is free and the window moves by a press and hold anywhere on it.
; The first time it has the whole of its monitor; after that it is as it was
; left, which the registry keeps.
;
; What the scripted run holds the game to is in proofs\README.md, under 07.
MACHINE_NAME equ 'myhits'
MACHINE_TAG equ 'game'
MACHINE_SNAPSHOT := 1
MACHINE_BARE := 1
include '..\common\machine.inc'
include '..\common\pictures.inc'
include 'tables.inc'
include '..\common\files.inc'
include '..\common\reload.inc'
include '..\common\audio.inc'

; These are myhits.slang's.
BODIES := 1024
SHOTS := 256
PELLETS := 384
HOSTILES := 384
PARTICLES := 16384
TRAILS := 32
REQUESTS := HOSTILES * 6			; a hostile's own cells to ask the director from
INSTANCES := 160 + BODIES + 16 + PELLETS + HOSTILES + 21 + 8 + 5 * 9
GAME_BYTES := 512
POOL_BYTES := 8 + STYLE_LIMIT * 4
WORLD_BYTES := GAME_BYTES + POOL_BYTES + 2 * BODIES * BODY_BYTES + BODIES * 4 + (TRAILS + 1) * TRAIL_POINTS * 8 + REQUESTS * REQUEST_BYTES + HOSTILES / 8 + PARTICLES * PARTICLE_BYTES
TICK_DISPATCHES := 5			; the director, the bodies, the shots, the struck, the particles
; What the measuring run tells apart: the five passes of a tick, the report,
; and the four draws.
iterate name, DIRECT,UPDATE,COLLIDE,RESOLVE,DRIFT,REPORT,BACKDROP,SCENE,PARTICLES,VEIL
	STAMP_#name := %
end iterate
STARTUP_DISPATCHES := PICTURES_PASSES + 3	; and the settling, the sounds, the beginning
GAME_TICKS := 8				; a scripted frame of the game runs this many: it has far to go
SCRIPT_FRAMES := 1330
RESTART_FRAME := 400			; the script presses Enter here; the first game is over by then
STAGE_FRAME := 1000			; and here: the second is over, and the third is on a bare stage
assert STAGE_FRAME = 1000		; the script's frames of the third are written out from it too
LAST_FRAME := 1250			; and here: the third is ended for it, and the fourth is a game like the first,
assert LAST_FRAME = 1250		; for the tables to be changed under: three times.
DUE_FRAME := LAST_FRAME+15		; In the very tick its first squad is due;
MID_FRAME := LAST_FRAME+23		; with that squad half out;
RELOAD_FRAME := LAST_FRAME+39		; and with a squad out and done
PAUSED_FRAME := 950			; and this frame's picture is a paused one's
assert RESTART_FRAME = 400		; the script's later frames are written out from it
public mainCRTStartup

; The world's header, which the CPU writes once: World in myhits.slang.
boundary GameWorld
	block pictures,Pictures
	block tables,Tables
	ptr bodies,Body
	ptr game,Game
	ptr damage,uint
	ptr particles,Particle
	ptr pool,ParticlePool
	ptr trails,float2
	ptr queue,Request
	ptr bank,float
	ptr ship_trail,float2
	u32 capacity
	u32 particle_capacity
	ptr staged,uint			; this header and the tables, where the CPU wrote them,
	ptr home,uint			; and where the device keeps them
	u32 words
	u32 table_words			; the last of the words are the tables
	ptr asking,uint
end boundary

section '.text$game' code readable executable align 16

; The first failed check, by number, and the frame (ESI) it failed in.
proc record_failure check
	cmp [proof_failure],0
	jne .already
	mov [proof_failure],ecx
	mov [proof_failure_frame],esi
.already:
	mov [app_io_failed],1
	ret
endp
macro fail check*
	fastcall record_failure,check
end macro
; Leave to `target` unless the float at `place` is within `slack` of the one at `value`.
macro unless_near place*,value*,slack*,target*
	movss xmm0,place
	subss xmm0,[value]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[slack]
	ja target
end macro
; At frame `when`, leave to `target` unless the count at `offset` of the events (RBX) is `value`.
macro at_frame when*,offset*,value*,target*
	local later
	cmp esi,when
	jne later
	cmp dword [rbx+offset],value
	jne target
later:
end macro

proc create_world uses rsi rdi
	mov [failure_stage],3
	; Only shaders touch the world: device-local memory, reached by address.
	require_ok fastcall create_buffer,addr world_buffer,WORLD_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_DEVICE
	; The CPU writes the header and the tables once, into memory it can see;
	; the device's first pass copies them to memory of its own, and that is
	; where every pass after reads them.
	; Both have room for tables larger than the ones the game was built with:
	; a running game may be given others.
	require_ok fastcall create_buffer,addr header_buffer,HOME_ROOM,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_UPLOAD
	require_ok fastcall create_buffer,addr home_buffer,HOME_ROOM,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_DEVICE
	; And the device writes the sounds where the CPU, and so the voices, can read them.
	require_ok fastcall create_buffer,addr bank_buffer,BANK_ROOM*4,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_READBACK
	mov rdi,[header_buffer.mapped]
	require_ok fastcall pictures_create,rdi
	mov rax,[header_buffer.address]
	mov [rdi+GameWorld.staged],rax
	mov rax,[home_buffer.address]
	mov [rdi+GameWorld.home],rax
	mov rax,[world_buffer.address]
	iterate <pool,bytes>, game,GAME_BYTES, pool,POOL_BYTES, bodies,2*BODIES*BODY_BYTES, damage,BODIES*4, trails,TRAILS*TRAIL_POINTS*8, ship_trail,TRAIL_POINTS*8, queue,REQUESTS*REQUEST_BYTES, asking,HOSTILES/8, particles,PARTICLES*PARTICLE_BYTES
		mov [rdi+GameWorld.pool],rax
		add rax,bytes
	end iterate
	mov rax,[bank_buffer.address]
	mov [rdi+GameWorld.bank],rax
	mov dword [rdi+GameWorld.capacity],BODIES
	mov dword [rdi+GameWorld.particle_capacity],PARTICLES
	; The tables the game was built with, by the way any others would come.
	require_ok fastcall machine_compute,addr settle_code,settle_code.size,addr settle_pipeline
	require_ok fastcall lay_tables,addr game_image
	iterate name, begin,direct,update,collide,resolve,drift,report,render
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	require_ok fastcall machine_graphics,addr scene_vertex_code,scene_vertex_code.size,addr scene_fragment_code,scene_fragment_code.size,BLEND_PREMULTIPLIED,addr scene_pipeline
	require_ok fastcall machine_graphics,addr particle_vertex_code,particle_vertex_code.size,addr particle_fragment_code,particle_fragment_code.size,BLEND_PREMULTIPLIED,addr particle_pipeline
	require_ok fastcall machine_graphics,addr veil_vertex_code,veil_vertex_code.size,addr veil_fragment_code,veil_fragment_code.size,BLEND_PREMULTIPLIED,addr veil_pipeline
	require_ok fastcall machine_graphics,addr backdrop_vertex_code,backdrop_vertex_code.size,addr backdrop_fragment_code,backdrop_fragment_code.size,BLEND_OPAQUE,addr backdrop_pipeline
	require_ok fastcall pictures_develop
	require_ok fastcall machine_serial_open
	; The sounds and the music first: nothing of them is uploaded but their
	; recipes and their notes. Then the game, which listens to what was made.
	fastcall machine_dispatch,[render_pipeline],[bank_groups]
	fastcall machine_settle
	fastcall machine_dispatch,[begin_pipeline],1
	require_ok fastcall machine_serial_close
	require_ok fastcall invalidate_buffer,addr bank_buffer
	mov eax,[dispatch_count]
	mov [startup_dispatches],eax
	mov [dispatch_count],0
	mov [failure_stage],0
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

; Lay an image of the tables down. The header says where each table will be
; on the device and how many lines it has; the tables follow the header; and
; one pass settles both into memory that is the device's own. The CPU goes on
; reading the image where it is: live_tables says where that is.
proc lay_tables uses rsi rdi,image
	mov rsi,rcx
	mov [live_image],rsi
	mov rdi,[header_buffer.mapped]
	mov rdx,[home_buffer.address]
	add rdx,sizeof.GameWorld
	lea r8,[rdi+GameWorld.tables]
	fastcall tables_place,rsi,rdx,r8
	lea rdx,[rsi+sizeof.TableImage]
	fastcall tables_place,rsi,rdx,addr live_tables
	mov eax,[rsi+TableImage.bytes]
	shr eax,2
	mov [rdi+GameWorld.table_words],eax
	add eax,sizeof.GameWorld/4
	mov [rdi+GameWorld.words],eax
	add eax,63
	shr eax,6
	mov [home_groups],eax
	mov eax,[rsi+TableImage.samples]
	add eax,TABLE_STEMS*MUSIC_SAMPLES+63
	shr eax,6
	mov [bank_groups],eax
	mov ecx,[rsi+TableImage.bytes]
	add rsi,sizeof.TableImage
	add rdi,sizeof.GameWorld
	rep movsb
	require_ok fastcall flush_buffer,addr header_buffer
	; For this pass alone the world is where the CPU wrote it.
	mov rax,[header_buffer.address]
	mov [root+Root.world],rax
	require_ok fastcall machine_serial_open
	fastcall machine_dispatch,[settle_pipeline],[home_groups]
	require_ok fastcall machine_serial_close
	mov rax,[home_buffer.address]
	mov [root+Root.world],rax
	mov eax,1
.failed:
	ret
endp

; The music is in the bank after the sounds, wherever that now is.
proc play_music
	mov eax,dword [live_tables+Tables.sound_samples]
	mov rcx,[bank_buffer.mapped]
	lea rcx,[rcx+rax*4]
	fastcall audio_music,rcx
	ret
endp

; Take the tables again, from a file. Returns what the file was: TABLES_FIT,
; and they are taken; TABLES_SAME, the ones in force already, and nothing is
; done; TABLES_OTHER, a whole image this game cannot take, which it will say;
; or TABLES_BROKEN, no whole image: none there, or one still being written.
;
; Taken: the voices are stopped, since they play from the bank; the image is
; laid down and settled; the bank is rendered again, and the music begun
; again from it; and the next frame that runs a tick tells the device, which
; lets go of whatever was running by the old tables. None of this is a
; frame's traffic, and none of it is counted as one.
TABLES_SAME := 3
TABLES_UNSEEN := 4			; (what the watcher made of a file it had no cause to look at)
proc reload_tables uses rbx rsi rdi,name
	fastcall file_take,rcx,addr taken_image,TAKEN_ROOM
	mov ebx,eax
	fastcall tables_fit,addr taken_image,rbx,TABLE_PRINT,TABLE_ROOM
	cmp eax,TABLES_FIT
	jne .unfit
	; As many stems as ever follow the sounds: is there room in the bank?
	mov eax,dword [taken_image+TableImage.samples]
	add eax,TABLE_STEMS*MUSIC_SAMPLES
	cmp eax,BANK_ROOM
	ja .other
	; And nothing in it points outside it: the device would read what is not there.
	fastcall tables_sound,addr taken_image,addr game_image,ART_FRAMES
	test eax,eax
	jz .other
	; The same as is in force, byte for byte, is no change.
	mov rsi,[live_image]
	mov eax,[rsi+TableImage.bytes]
	add eax,sizeof.TableImage
	cmp eax,ebx
	jne .take
	lea rdi,[taken_image]
	mov ecx,ebx
	repe cmpsb
	jne .take
	mov eax,TABLES_SAME
	ret
.take:
	fastcall take_tables,addr taken_image,rbx
	test eax,eax
	jz .lost
	; A run that is being recorded has them in its record, whole.
	fastcall record_image,addr kept_image,rbx
	or [reload_owed],ROOT_RELOADED
	inc [reloads_taken]
	add [reload_bytes],ebx
	mov eax,TABLES_FIT
	ret
.unfit:
	cmp eax,TABLES_OTHER
	jne .done
.other:
	or [reload_owed],ROOT_REFUSED
	inc [reloads_refused]
	mov eax,TABLES_OTHER
.done:
	ret
.lost:
	; The device would not: there is no going on from that.
	mov [app_io_failed],1
	fastcall PostQuitMessage,0
	mov eax,TABLES_BROKEN
	ret
endp

; An image that fits, in place of the one in force: kept, laid down and
; settled, the bank rendered again from it, and the music begun again.
; Returns zero if the device would not.
proc take_tables uses rbx rsi rdi,image,bytes
	mov rsi,rcx
	mov ebx,edx
	fastcall audio_hush
	lea rdi,[kept_image]
	mov ecx,ebx
	rep movsb
	mov esi,[dispatch_count]
	fastcall lay_tables,addr kept_image
	test eax,eax
	jz .done
	fastcall machine_serial_open
	test eax,eax
	jz .done
	fastcall machine_dispatch,[render_pipeline],[bank_groups]
	fastcall machine_serial_close
	test eax,eax
	jz .done
	fastcall invalidate_buffer,addr bank_buffer
	mov eax,[dispatch_count]
	sub eax,esi
	add [reload_dispatches],eax
	mov [dispatch_count],esi
	fastcall play_music
	mov eax,1
.done:
	ret
endp

; A run, kept: what the device was given in every frame, as it was given it,
; and whatever tables were taken on the way. A world that is the same for
; the same controls needs nothing else to be the same run again. Each frame
; goes to the file as it is played, so that the record of a run that ended
; badly has its last frame in it.
;
;	a head: 'MRUN', a version, the print of the tables' names, ticks a second
;	a frame: its ticks, where it was steered, where it aimed, what was held
;		and pressed, and its flags
;	tables: RUN_IMAGE, how many bytes, and the image
;	what a frame came to: RUN_CAME, its number, and the device's sum of the
;		world after it, which comes back a frame later
;
; The last is what a playing back is held to as it goes: the first frame
; that comes to something else is where it left its record (replay_left).
; A record of the first version has none, and is played back unheld.
RUN_VERSION := 2
RUN_HEAD := 16
RUN_FRAME := 32
RUN_IMAGE := 0FFFFFFFFh
RUN_CAME := 0FFFFFFFEh
RUN_ROOM := 16*1024*1024		; the longest record that is played back: some hours

proc record_start name
	fastcall file_begin,rcx
	mov [run_file],rax
	test rax,rax
	jz .done
	fastcall file_more,rax,addr run_head,RUN_HEAD
.done:
	ret
endp

proc record_frame
	cmp [run_file],0
	je .done
	mov eax,[root+Root.ticks]
	mov [run_record],eax
	mov rax,qword [root+Root.move]
	mov qword [run_record+4],rax
	mov rax,qword [root+Root.aim]
	mov qword [run_record+12],rax
	mov eax,[root+Root.held]
	mov [run_record+20],eax
	mov eax,[root+Root.pressed]
	mov [run_record+24],eax
	mov eax,[root+Root.flags]
	mov [run_record+28],eax
	fastcall file_more,[run_file],addr run_record,RUN_FRAME
.done:
	ret
endp

proc record_image uses rbx,image,bytes
	cmp [run_file],0
	je .done
	mov rbx,rcx
	mov [run_mark+4],edx
	fastcall file_more,[run_file],addr run_mark,8
	mov r8d,[run_mark+4]
	add r8d,3
	and r8d,not 3
	fastcall file_more,[run_file],rbx,r8
.done:
	ret
endp

; What a frame came to, as its events say: into the record of a run being
; kept; and, of a run being played back, beside what its record says.
proc record_came frame,sum
	cmp [run_file],0
	je .done
	mov [run_came+4],ecx
	mov [run_came+8],edx
	fastcall file_more,[run_file],addr run_came,16
.done:
	ret
endp

; ECX a frame, EDX what it came to; R8 which side says so: nothing, this
; playing; otherwise, the record. When both have spoken of a frame and do
; not agree, that is where the playing left its record, if it had not yet.
proc replay_came frame,sum,side
	cmp [replayed],0
	je .done
	mov eax,ecx
	and eax,15
	inc ecx
	lea r9,[came_now]
	lea r10,[came_then]
	test r8d,r8d
	jz .said
	xchg r9,r10
.said:
	mov [r9+rax*8],ecx
	mov [r9+rax*8+4],edx
	cmp [r10+rax*8],ecx
	jne .done
	cmp [r10+rax*8+4],edx
	je .agreed
	cmp [replay_left],0
	jne .done
	mov [replay_left],ecx
	ret
.agreed:
	inc [replay_held]
.done:
	ret
endp

; The file a record goes to or comes from: the one named after the option
; (RCX), or the usual one.
proc run_file_name uses rsi rdi,option
	fastcall command_value,rcx,addr run_path,260
	test eax,eax
	jnz .done
	lea rsi,[run_name]
	cmp [test_mode],0
	je .usual
	lea rsi,[run_test_name]
.usual:
	lea rdi,[run_path]
.copy:
	lodsw
	stosw
	test ax,ax
	jnz .copy
.done:
	ret
endp

proc record_stop
	cmp [run_file],0
	je .done
	fastcall file_done,[run_file]
	mov [run_file],0
.done:
	ret
endp

; A record to play back: nonzero if there is one, and it is of this game's names.
proc replay_start name
	fastcall file_take,rcx,addr run_taken,RUN_ROOM
	cmp eax,RUN_HEAD
	jb .none
	mov [run_end],eax
	lea rdx,[run_taken]
	cmp dword [rdx],'MRUN'
	jne .none
	cmp dword [rdx+4],0
	je .none
	cmp dword [rdx+4],RUN_VERSION
	ja .none
	mov eax,[rdx+8]
	cmp eax,[run_head+8]
	jne .none
	mov [run_at],RUN_HEAD
	mov [replaying],1
	mov [replayed],1
	mov eax,1
	ret
.none:
	xor eax,eax
	ret
endp

; The record's next frame into Root, tables that were taken before it taken
; again first. Returns zero when the record is over, or cannot be gone on with.
proc replay_frame uses rbx rsi
.next:
	mov eax,[run_at]
	lea rsi,[run_taken]
	add rsi,rax
	add eax,8
	cmp eax,[run_end]
	ja .over
	cmp dword [rsi],RUN_CAME
	jne .not_came
	mov eax,[run_at]
	add eax,16
	cmp eax,[run_end]
	ja .over
	mov [run_at],eax
	fastcall replay_came,[rsi+4],[rsi+8],1
	jmp .next
.not_came:
	cmp dword [rsi],RUN_IMAGE
	jne .frame
	mov ebx,[rsi+4]
	lea eax,[rbx+3]
	and eax,not 3
	add eax,8
	add eax,[run_at]
	cmp eax,[run_end]
	ja .over
	mov [run_at],eax
	add rsi,8
	; (Whatever the record says, nothing is laid down that would not be taken from a file.)
	fastcall tables_fit,rsi,rbx,TABLE_PRINT,TABLE_ROOM
	cmp eax,TABLES_FIT
	jne .over
	mov eax,[rsi+TableImage.samples]
	add eax,TABLE_STEMS*MUSIC_SAMPLES
	cmp eax,BANK_ROOM
	ja .over
	fastcall tables_sound,rsi,addr game_image,ART_FRAMES
	test eax,eax
	jz .over
	fastcall take_tables,rsi,rbx
	test eax,eax
	jz .over
	fastcall record_image,addr kept_image,rbx
	jmp .next
.frame:
	mov eax,[run_at]
	add eax,RUN_FRAME
	cmp eax,[run_end]
	ja .over
	mov [run_at],eax
	mov rax,[rsi+4]
	mov qword [root+Root.move],rax
	mov rax,[rsi+12]
	mov qword [root+Root.aim],rax
	mov eax,[rsi+20]
	mov [root+Root.held],eax
	mov eax,[rsi+24]
	mov [root+Root.pressed],eax
	mov eax,[rsi+28]
	mov [root+Root.flags],eax
	mov ecx,[rsi]
	fastcall machine_given,rcx
	mov eax,1
	ret
.over:
	mov [replaying],0
	xor eax,eax
	ret
endp

; What the device is owed word of goes down with the first frame that runs a
; tick: only a tick can act on it.
proc reload_flags
	and dword [root+Root.flags],not (ROOT_RELOADED or ROOT_REFUSED)
	mov eax,[reload_owed]
	test eax,eax
	jz .done
	cmp dword [root+Root.ticks],0
	je .done
	or dword [root+Root.flags],eax
	mov [reload_owed],0
.done:
	ret
endp

; A game that is watching looks at its tables' file once a second, and takes
; it when it has been written since it last looked. A file that is not whole
; is looked at again: it may be half-way to being written.
proc watch_tables
	cmp [watching],0
	je .done
	mov rax,[clock_last]
	cmp rax,[watch_due]
	jb .done
	add rax,[clock_frequency]
	mov [watch_due],rax
	fastcall file_stamp,addr tables_name
	test rax,rax
	jz .done
	cmp rax,[watch_stamp]
	je .done
	mov [watch_seen],rax
	fastcall reload_tables,addr tables_name
	mov [watch_result],eax
	cmp eax,TABLES_BROKEN
	je .done
	mov rax,[watch_seen]
	mov [watch_stamp],rax
.done:
	ret
endp

proc release_world
	fastcall audio_stop
	iterate name, settle,begin,direct,update,collide,resolve,drift,report,render,scene,particle,veil,backdrop
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	fastcall pictures_release
	fastcall destroy_buffer,addr bank_buffer
	fastcall destroy_buffer,addr header_buffer
	fastcall destroy_buffer,addr home_buffer
	fastcall destroy_buffer,addr world_buffer
	ret
endp

; One frame: as many ticks as real time has earned, the report, two draws.
proc play_frame uses rbx
	fastcall machine_await
	test eax,eax
	jz .stopped
	; A run being played back: the frame is as the record has it.
	cmp [replaying],0
	je .live
	fastcall replay_frame
	test eax,eax
	jnz .given
	; The record is over. A check ends there; a game goes on from there, in
	; the player's hands.
	cmp [test_mode],0
	je .handed
	mov eax,3
	ret
.handed:
	mov dword [root+Root.flags],0
	fastcall QueryPerformanceCounter,addr clock_last
.live:
	test dword [root+Root.flags],ROOT_SCRIPTED
	jz .sample
	; The script, in frames of eight ticks. The first game: up out of the way,
	; eight shots at nothing, a long wait, down to a turret's row, seven shots
	; at it; and then nothing, until it is over. The second: up to the worm's
	; row; three frames of fire with RAPID in force, and three with SPREAD
	; too; fire at the worm's head as it comes, which brings the companion;
	; then four frames to the right, for it to follow. The crosshair stays
	; where the companion's gun will be asked to point. The third, on a bare
	; stage: a pair of missiles; a dash upward, through a shot set down in its
	; way; down a little while the first diver fixes on the ship, and then
	; still, to be caught; a dash downward once the second has locked, to
	; get clear; and when the charge is nearly gone, a launch it can pay for
	; and then a launch and a dash it cannot. The fourth: up out of the way,
	; as in the first, and then nothing.
	;
	; And the tables are taken again from a file, between frames. In the
	; first game, before anything has come: others; then others the game
	; cannot take; then its own again, and this time by the watcher, as a
	; game started with --watch takes them; the watcher once more, which has
	; nothing new to look at; then its own offered outright, which is no
	; change. In the fourth: the others, in the tick the first squad is due;
	; its own, with that squad half out; and the others, with it out and done.
	iterate <when,name>, 3,tables_alt_name, 5,tables_bad_name, 7,0, 9,0, 11,tables_name, DUE_FRAME,tables_alt_name, MID_FRAME,tables_name, RELOAD_FRAME,tables_alt_name
		cmp dword [root+Root.frame],when
		jne .kept_#when
		match =0, name
			fastcall script_watch,%-1
		else
			fastcall script_reload,addr name,%-1
		end match
	.kept_#when:
	end iterate
	mov dword [root+Root.aim],1500.0
	mov dword [root+Root.aim+4],300.0
	mov dword [root+Root.move],0
	mov dword [root+Root.move+4],0
	mov dword [root+Root.held],0
	mov dword [root+Root.pressed],0
	mov eax,[root+Root.frame]
	iterate <from,to,way>, 0,10,-1.0, 250,255,1.0, 401,403,-1.0, 1010,1010,-1.0, 1050,1053,1.0, 1125,1125,1.0, 1251,1260,-1.0
		cmp eax,from
		jb .still_#from
		cmp eax,to
		ja .still_#from
		mov dword [root+Root.move+4],way
	.still_#from:
	end iterate
	cmp eax,570
	jb .along
	cmp eax,573
	ja .along
	mov dword [root+Root.move],1.0
.along:
	iterate <from,to>, 11,16, 290,294, 430,432, 442,444, 543,566
		cmp eax,from
		jb .quiet_#from
		cmp eax,to
		ja .quiet_#from
		mov dword [root+Root.held],BUTTON_FIRE
	.quiet_#from:
	end iterate
	; One frame is drawn as a paused one is, for its picture; the run goes on under it.
	and dword [root+Root.flags],not ROOT_PAUSED
	cmp eax,PAUSED_FRAME
	jne .unpaused
	or dword [root+Root.flags],ROOT_PAUSED
.unpaused:
	iterate <when,button>, 400,BUTTON_START, 1000,BUTTON_START, 1003,BUTTON_SECOND, 1010,BUTTON_THIRD, \
		1125,BUTTON_THIRD, 1200,BUTTON_SECOND, 1206,BUTTON_SECOND, 1212,BUTTON_THIRD, LAST_FRAME,BUTTON_START
		cmp eax,when
		jne .unpressed_#when
		mov dword [root+Root.pressed],button
	.unpressed_#when:
	end iterate
.sample:
	fastcall machine_sample
	fastcall reload_flags
	fastcall record_frame
	; The beat goes down with the controls: how lately the music struck one,
	; so the picture can strike with it. A scripted run hears none.
	mov dword [root+Root.beat],0
	test dword [root+Root.flags],ROOT_SCRIPTED
	jnz .open
	fastcall audio_beat
	xorps xmm1,xmm1
	ucomiss xmm0,xmm1
	jb .open
	movss xmm1,[felt_all]
	subss xmm1,xmm0
	movaps xmm0,xmm1
	mulss xmm0,xmm1
	mulss xmm0,xmm1
	movss dword [root+Root.beat],xmm0
	jmp .open
.given:
	; (A run being played back may be kept again as it goes.)
	fastcall record_frame
	mov dword [root+Root.beat],0
	; And a strip may be being made of it: then a frame is shown, to be
	; pictured, each time so much more of the run has gone by, and no other is.
	cmp [strip_every],0
	je .open
	mov [machine_unseen],1
	mov rax,[ticks_run]
	cmp rax,[strip_next]
	jb .open
	mov [machine_unseen],0
	mov [strip_now],1
	mov eax,[strip_every]
	add [strip_next],rax
.open:
	fastcall machine_open
	cmp eax,1
	jne .skipped
	mov ebx,[root+Root.ticks]
.tick:
	test ebx,ebx
	jz .ticked
	fastcall machine_dispatch,[direct_pipeline],1
	fastcall machine_settle
	fastcall machine_stamp,STAMP_DIRECT
	fastcall machine_dispatch,[update_pipeline],BODIES/64
	fastcall machine_settle
	fastcall machine_stamp,STAMP_UPDATE
	fastcall machine_dispatch,[collide_pipeline],(SHOTS+PELLETS)/64
	fastcall machine_settle
	fastcall machine_stamp,STAMP_COLLIDE
	fastcall machine_dispatch,[resolve_pipeline],HOSTILES/32
	fastcall machine_settle
	fastcall machine_stamp,STAMP_RESOLVE
	fastcall machine_dispatch,[drift_pipeline],PARTICLES/64
	fastcall machine_settle
	fastcall machine_stamp,STAMP_DRIFT
	dec ebx
	jmp .tick
.ticked:
	fastcall machine_dispatch,[report_pipeline],1
	fastcall machine_stamp,STAMP_REPORT
	fastcall machine_canvas
	fastcall draw_world
	; The scripted run leaves pictures of itself: the swoopers, the weavers,
	; the worm coming and turning, the turrets with the level stopped, the run
	; over; and of the second game three volleys with RAPID and SPREAD, the
	; nova going off, the shield about to take a rammer, and the worm's head
	; under fire.
	; And of the third: the dash, through a shot; a diver's fix on the ship,
	; shaking; its lock; its heavy shot on the way and the crosshairs fading;
	; the burst; the second's shot coming for where the ship no longer is; and
	; the third's, loosed as it died, coming for a ship that only killed it.
	; And of the fourth: the tables just taken again, which is said along the
	; top, and nothing left of the three that had come; and the five that
	; came in their place.
	cmp [replayed],0
	jne .strip
	iterate when, 37,110,165,235,300,320,395,444,468,500,555,568,596,625,900,PAUSED_FRAME, \
		1011,1056,1066,1082,1091,1136,1176,1290,1313
		cmp dword [root+Root.frame],when
		jne .no_#when
		fastcall snapshot_take,when
	.no_#when:
	end iterate
.strip:
	; A run being played back for a strip: this is one of its pictures.
	cmp [strip_now],0
	je .unpictured
	mov [strip_now],0
	fastcall snapshot_take,[strip_index]
	; Its line is written when its own events are in hand: how the run
	; stood in the picture, and not a frame before it.
	mov eax,[root+Root.frame]
	inc eax
	mov [strip_frame],eax
	mov eax,dword [ticks_run]
	mov [strip_ticks],eax
.unpictured:
	fastcall machine_close
	ret
.skipped:
	; 2: no image this turn, which is not a failure.
	shr eax,1
.stopped:
	ret
endp

; Everything a frame draws: the backdrop; the sprites and the HUD among them;
; the light; then the veil a hurt or the end of a run draws over it all.
proc draw_world
	fastcall machine_draw,[backdrop_pipeline],6,1
	fastcall machine_stamp,STAMP_BACKDROP
	fastcall machine_draw,[scene_pipeline],6,INSTANCES
	fastcall machine_stamp,STAMP_SCENE
	fastcall machine_draw,[particle_pipeline],6,PARTICLES
	fastcall machine_stamp,STAMP_PARTICLES
	fastcall machine_draw,[veil_pipeline],6,1
	fastcall machine_stamp,STAMP_VEIL
	ret
endp

; A finished frame's events: its sounds to the voices, its numbers to the
; title, and in a scripted run every one of them held to the rules.
proc consume_events uses rbx rsi rdi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	fastcall audio_events,rbx,qword [live_tables+Tables.sounds],[bank_buffer.mapped]
	; And what should be felt, to the pad.
	movss xmm0,dword [rbx+Events.rumble_low]
	movss xmm1,dword [rbx+Events.rumble_high]
	cmp [paused],0
	je .felt_now
	; A hurt does not go on being felt for as long as a pause lasts.
	xorps xmm0,xmm0
	xorps xmm1,xmm1
.felt_now:
	fastcall pad_rumble
	; And how much is happening, to the music.
	movss xmm0,dword [rbx+Events.intensity]
	fastcall audio_mix
	xor edi,edi
	repeat TABLE_SOUNDS
		cmp dword [rbx+Events.sound+(%-1)*sizeof.Trigger+Trigger.count],0
		setne al
		movzx eax,al
		add edi,eax
	end repeat
	add [sounds_asked],edi
	mov eax,[rbx+Events.sound+SOUND_HURT*sizeof.Trigger+Trigger.count]
	add [heard_hurts],eax
	iterate <name,offset>, last_score,Events.score, last_lives,Events.lives, last_wave,Events.wave, last_state,Events.state, last_rank,Events.rank, \
		last_fired,Events.reserved+4, last_struck,Events.reserved+12, last_kills,Events.reserved+20, last_hurts,Events.reserved+24, last_alive,Events.reserved+28
		mov eax,[rbx+offset]
		mov [name],eax
	end iterate
	mov eax,[root+Root.frame]
	sub eax,esi
	mov [last_latency],eax
	cmp eax,[worst_latency]
	jbe .counted
	mov [worst_latency],eax
.counted:
	fastcall strip_line,rsi
	; What the frame came to: kept, in a run that is being kept; and held to
	; its record, in a run that is being played back.
	fastcall record_came,rsi,[rbx+Events.debug+12]
	fastcall replay_came,rsi,[rbx+Events.debug+12],0
	cmp [test_mode],0
	je .done
	; Every frame's sum of the world, folded into one: what a run played back
	; from its record is held to, and held to nothing else.
	imul eax,[frames_sum],16777619
	xor eax,[rbx+Events.debug+12]
	mov [frames_sum],eax
	cmp [replayed],0
	jne .done
	; What this frame asked of the voices, and of the music: kept, for the
	; run to be played back from.
	cmp esi,SCRIPT_FRAMES
	jae .unheard
	imul eax,esi,HEARD_BYTES
	lea r8,[heard_log]
	add r8,rax
	mov [r8],esi
	mov eax,[rbx+Events.intensity]
	mov [r8+4],eax
	lea r9,[rbx+Events.sound]
	mov ecx,SOUND_KINDS*sizeof.Trigger/8
.heard:
	mov rax,[r9]
	mov [r8+8],rax
	add r9,8
	add r8,8
	dec ecx
	jnz .heard
.unheard:
	; 1: events arrive once each, in frame order, in hand when the next frame begins.
	cmp esi,[events_seen]
	jne .order_wrong
	cmp [last_latency],1
	je .order
.order_wrong:
	fail 1
.order:
	; The fourth game is for the tables' sake: it is held to that and to
	; nothing else, and what the run's end is held to is how the third stood.
	cmp esi,LAST_FRAME
	jb .earlier
	fastcall check_reload,rbx,rsi
	cmp esi,SCRIPT_FRAMES-1
	jne .done
	mov eax,[rbx+Events.debug+12]
	mov [sum_fourth],eax
	jmp .done
.earlier:
	; 2: what comes is what the table says, when it says: three swoopers by
	; frame 37 and nothing else; the fourth squad's turn by frame 145.
	at_frame 12,Events.reserved+28,0,.waves_wrong
	at_frame 37,Events.reserved+28,3,.waves_wrong
	at_frame 37,Events.wave,1,.waves_wrong
	at_frame 100,Events.wave,2,.waves_wrong
	at_frame 145,Events.wave,3,.waves_wrong
	jmp .waves
.waves_wrong:
	fail 2
.waves:
	; 3: every shot is accounted for, in every frame.
	mov eax,[rbx+Events.reserved+8]
	add eax,[rbx+Events.reserved+12]
	add eax,[rbx+Events.reserved+16]
	cmp eax,[rbx+Events.reserved+4]
	je .accounted
	fail 3
.accounted:
	; 4: rank reads the shooting. A second survived is a hundredth. Eight
	; shots at nothing, all escaped, take six thousandths off, twice, to
	; nothing. Shots that all struck add thirty-four thousandths. A hurt takes
	; fifteen hundredths, down to nothing.
	cmp esi,14
	jne .rank_missed
	unless_near dword [rbx+Events.rank],rank_one,rank_slack,.rank_wrong
.rank_missed:
	cmp esi,29
	jne .rank_floor
	unless_near dword [rbx+Events.rank],rank_two,rank_slack,.rank_wrong
.rank_floor:
	cmp esi,44
	jne .rank_struck
	cmp dword [rbx+Events.rank],0
	jne .rank_wrong
.rank_struck:
	mov eax,[rbx+Events.reserved+24]
	cmp eax,[hurts_before]
	jb .rank			; a new run
	jne .rank_hurt
	cmp esi,299
	jne .rank
	movss xmm0,dword [rbx+Events.rank]
	subss xmm0,[rank_before]
	subss xmm0,[rank_rise]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[rank_slack]
	ja .rank_wrong
	mov [rise_checked],1
	jmp .rank
.rank_hurt:
	; A hurt in a frame that held no look: fifteen hundredths, or all there was.
	mov eax,esi
	xor edx,edx
	mov ecx,15
	div ecx
	cmp edx,14
	je .rank
	movss xmm0,[rank_before]
	subss xmm0,[rank_fall]
	xorps xmm1,xmm1
	maxss xmm0,xmm1
	subss xmm0,dword [rbx+Events.rank]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[rank_slack]
	ja .rank_wrong
	inc [falls_checked]
	jmp .rank
.rank_wrong:
	fail 4
.rank:
	; 5: a chain follows its head exactly. While the worm comes straight on,
	; its first segment is one spacing behind where the head stood a tick ago,
	; on the head's own line. Once all of it is out and turning, no two
	; neighbors are farther apart than the spacing, nor nearer than a turn that
	; tight can bring them. (Not in a frame the world stood still in: the
	; head "a tick ago" is then where it is.)
	mov eax,[rbx+Events.report+4]
	cmp eax,[last_stopped]
	jne .chain
	cmp esi,150
	jb .chain
	cmp esi,163
	ja .curled
	movss xmm0,dword [rbx+Events.reserved+56]
	subss xmm0,dword [rbx+Events.reserved+48]
	subss xmm0,[spacing]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	ja .chain_wrong
	movss xmm0,dword [rbx+Events.reserved+60]
	subss xmm0,dword [rbx+Events.reserved+52]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	ja .chain_wrong
.curled:
	cmp esi,200
	jb .chain
	cmp esi,245
	ja .chain
	cmp dword [rbx+Events.debug],9
	jne .chain_wrong
	movss xmm0,dword [rbx+Events.debug+4]
	ucomiss xmm0,[spacing_least]
	jb .chain_wrong
	movss xmm0,dword [rbx+Events.debug+8]
	ucomiss xmm0,[spacing_most]
	jbe .chain
.chain_wrong:
	fail 5
.chain:
	; 6: a body cannot make a body. The first turret's FIRE is a request in
	; one tick and a pellet in the next: none by frame 258, one in frame 259.
	at_frame 258,Events.reserved+44,0,.fire_wrong
	at_frame 259,Events.reserved+44,1,.fire_wrong
	at_frame 259,Events.reserved+32,1,.fire_wrong
	jmp .fire
.fire_wrong:
	fail 6
.fire:
	; 7: a hurt costs a life, one at a time and never two within the grace;
	; with none left the run is over, and stays over until Enter.
	mov eax,[rbx+Events.reserved+24]
	mov edx,eax
	sub edx,[hurts_before]
	jz .lives
	js .lives			; a new run
	cmp edx,1
	jne .lives_wrong
	inc [hurts_total]
	mov ecx,esi
	sub ecx,[hurt_frame]
	cmp ecx,30
	jb .lives_wrong
	mov [hurt_frame],esi
.lives:
	add eax,[rbx+Events.lives]
	cmp eax,3
	jne .lives_wrong
	cmp dword [rbx+Events.lives],0
	sete al
	cmp dword [rbx+Events.state],1
	sete dl
	cmp al,dl
	jne .lives_wrong
	at_frame RESTART_FRAME-1,Events.state,1,.lives_wrong
	at_frame RESTART_FRAME+2,Events.state,0,.lives_wrong
	at_frame RESTART_FRAME+2,Events.lives,3,.lives_wrong
	at_frame RESTART_FRAME+2,Events.score,0,.lives_wrong
	jmp .lived
.lives_wrong:
	fail 7
.lived:
	; 8: the level stops for what is anchored to it, and moves on. From frame
	; 290 to 335 its pace is nothing and it has not come a bit farther; by
	; frame 352 it is at full pace again.
	cmp esi,290
	jb .pace
	cmp esi,335
	ja .moved
	cmp dword [rbx+Events.reserved+36],0
	jne .pace_wrong
	mov eax,[rbx+Events.reserved+40]
	cmp eax,[scroll_before]
	jne .pace_wrong
.moved:
	cmp esi,352
	jne .pace
	unless_near dword [rbx+Events.reserved+36],full_pace,tolerance,.pace_wrong
	jmp .pace
.pace_wrong:
	fail 8
.pace:
	; 9: kill the head and the chain goes with it. In the second game the
	; worm's head is shot as it comes; five frames after the frame it dies in,
	; ten fewer are alive than the frame before.
	cmp esi,RESTART_FRAME+140
	jb .ripple
	cmp [head_died],0
	jne .rippling
	cmp dword [rbx+Events.debug],9
	jne .dying
	mov eax,[rbx+Events.reserved+28]
	mov [alive_before],eax
	mov [chain_seen],1
	jmp .ripple
.dying:
	cmp [chain_seen],0
	je .ripple
	mov [head_died],esi
	jmp .ripple
.rippling:
	mov eax,[head_died]
	add eax,5
	cmp esi,eax
	jne .ripple
	mov eax,[alive_before]
	sub eax,10
	cmp [rbx+Events.reserved+28],eax
	jle .ripple
	fail 9
.ripple:
	; 15: a bonus is taken by coming near it, once. The second game is given
	; one of each in front of the ship: each is in hand, and only one of it, a
	; few frames after it was set down.
	at_frame 418,Events.report+16,1,.bonus_wrong
	at_frame 429,Events.report+8,1,.bonus_wrong
	at_frame 441,Events.report+12,1,.bonus_wrong
	at_frame 454,Events.report+24,1,.bonus_wrong
	at_frame 471,Events.report+20,1,.bonus_wrong
	jmp .bonus
.bonus_wrong:
	fail 15
.bonus:
	; 16: the shield takes the next hurt. It is held from frame 418; a rammer
	; comes along the ship's row; by frame 505 the shield is spent on it, and
	; no life was.
	at_frame 418,Events.report+28,1,.shield_wrong
	at_frame 505,Events.report+32,1,.shield_wrong
	at_frame 505,Events.report+28,0,.shield_wrong
	at_frame 505,Events.lives,3,.shield_wrong
	jmp .shield
.shield_wrong:
	fail 16
.shield:
	; 17: RAPID halves the wait between shots and SPREAD makes each three.
	; Three frames of fire are four shots without either; they are eight with
	; RAPID, and twenty-four with both.
	mov eax,[rbx+Events.reserved+4]
	cmp esi,429
	je .mark
	cmp esi,441
	jne .rapid
.mark:
	mov [fired_mark],eax
.rapid:
	sub eax,[fired_mark]
	cmp esi,432
	jne .spread
	cmp eax,8
	jne .rate_wrong
.spread:
	cmp esi,444
	jne .rate
	cmp eax,24
	je .rate
.rate_wrong:
	fail 17
.rate:
	; 18: a nova strikes everything at once, and DOUBLE doubles what a kill is
	; worth. In the frame the nova is taken or the next, the drone set down
	; for it dies, and whatever swoopers were left; nothing that can be hit is
	; alive after; and the score has grown by exactly twice their worth at the
	; rank of the moment.
	mov eax,[rbx+Events.report+20]
	cmp [nova_frame],0
	jne .nova_after
	test eax,eax
	jz .nova
	mov [nova_frame],esi
	mov eax,[score_before]
	mov [nova_score],eax
	mov eax,[kills_before]
	mov [nova_kills],eax
	jmp .nova
.nova_after:
	mov eax,[nova_frame]
	inc eax
	cmp esi,eax
	jne .nova
	cmp dword [rbx+Events.reserved+28],0
	jne .nova_wrong
	mov ecx,[rbx+Events.reserved+20]
	sub ecx,[nova_kills]
	jle .nova_wrong
	dec ecx					; the swoopers among them
	movss xmm1,dword [rbx+Events.rank]
	addss xmm1,[rank_unit]
	movss xmm0,[worth_swooper]
	mulss xmm0,xmm1
	addss xmm0,[rank_round]
	cvttss2si eax,xmm0
	imul eax,ecx
	movss xmm0,[worth_drone]
	mulss xmm0,xmm1
	addss xmm0,[rank_round]
	cvttss2si edx,xmm0
	add eax,edx
	shl eax,1
	mov edx,[rbx+Events.score]
	sub edx,[nova_score]
	cmp eax,edx
	je .nova
.nova_wrong:
	fail 18
.nova:
	; 19: the companion is a surprise: there is none until the worm's head is
	; killed, and two frames after that there is.
	at_frame 500,Events.report+36,0,.mate_wrong
	mov eax,[head_died]
	test eax,eax
	jz .mate_place
	add eax,2
	cmp esi,eax
	jne .mate_place
	cmp dword [rbx+Events.report+36],1
	jne .mate_wrong
.mate_place:
	; 20: it is where you were. The ship has stood still since it came up 120
	; from where the run began, so 150 back along its path is the first point
	; it laid, 8 on from there; and the companion fired when the ship did.
	; Then the ship goes 160 to the right, and 150 back along its path is 10
	; to the right of where it turned.
	cmp esi,568
	jne .mate_followed
	unless_near dword [rbx+Events.report+40],mate_x_first,mate_slack,.mate_wrong
	unless_near dword [rbx+Events.report+44],mate_y_first,mate_slack,.mate_wrong
	cmp dword [rbx+Events.report+56],0
	je .mate_wrong
.mate_followed:
	cmp esi,579
	jne .mate_own
	unless_near dword [rbx+Events.report+40],mate_x_after,mate_slack,.mate_wrong
	unless_near dword [rbx+Events.report+44],mate_y_after,mate_slack,.mate_wrong
	mov eax,[rbx+Events.reserved+12]
	mov [struck_mark],eax
.mate_own:
	; 21: then it acts for itself. Its guard turns to a shot coming at it and
	; stops it; its gun turns to what is nearest and its shots strike, while
	; the player fires nothing.
	at_frame 582,Events.report+36,2,.mate_wrong
	at_frame 600,Events.report+64,1,.mate_wrong
	cmp esi,610
	jne .mate_aimed
	cmp dword [rbx+Events.report+60],0
	je .mate_wrong
	mov eax,[rbx+Events.reserved+12]
	cmp eax,[struck_mark]
	jne .mate_wrong
.mate_aimed:
	; 22: and then its gun takes your aim: it points from where it is to the crosshair.
	at_frame 614,Events.report+36,3,.mate_wrong
	cmp esi,630
	jne .mate
	movss xmm0,[aim_y]
	subss xmm0,dword [rbx+Events.report+44]
	movss [scratch],xmm0
	movss xmm0,[aim_x]
	subss xmm0,dword [rbx+Events.report+40]
	movss [scratch+4],xmm0
	fld dword [scratch]
	fld dword [scratch+4]
	fpatan
	fstp dword [scratch]
	unless_near dword [rbx+Events.report+48],scratch,centi,.mate_wrong
	jmp .mate
.mate_wrong:
	fail 19
.mate:
	; 20: the level waits for a boss. The dragon is the sixth squad of the
	; second game. Long after it has come, it and its twelve segments are all
	; there, nothing more has come, and the level stands; the script strikes
	; its head dead, and then the chain goes, the table begins again, and the
	; level moves.
	at_frame 900,Events.wave,6,.boss_wrong
	at_frame 940,Events.wave,6,.boss_wrong
	at_frame 940,Events.reserved+36,0,.boss_wrong
	at_frame 940,Events.debug,12,.boss_wrong
	at_frame 960,Events.debug,0,.boss_wrong
	cmp esi,995
	jne .boss
	cmp dword [rbx+Events.wave],7
	jb .boss_wrong
	unless_near dword [rbx+Events.reserved+36],full_pace,tolerance,.boss_wrong
	jmp .boss
.boss_wrong:
	fail 20
.boss:
	mov eax,[rbx+Events.score]
	mov [score_before],eax
	mov eax,[rbx+Events.reserved+20]
	mov [kills_before],eax
	; 13: the score the HUD shows chases the real one and never passes it.
	mov eax,[rbx+Events.report]
	cmp eax,[rbx+Events.score]
	jbe .shown
	fail 13
.shown:
	mov [last_shown],eax
	mov eax,[rbx+Events.report+4]
	mov [last_stopped],eax
	mov eax,[rbx+Events.report+72]
	mov [last_music_faults],eax
	fastcall check_reload,rbx,rsi
	cmp esi,STAGE_FRAME
	jb .staged
	fastcall check_stage,rbx,rsi
.staged:
	; The sum over the world at the end of each game: the proof runner holds
	; one run's to another's.
	iterate <when,name>, 399,sum_first, 999,sum_second, 1249,sum_third
		cmp esi,when
		jne .unsummed_#when
		mov eax,[rbx+Events.debug+12]
		mov [name],eax
	.unsummed_#when:
	end iterate
	cmp esi,LAST_FRAME-1
	jne .unkept
	iterate name, score,kills,rank
		mov eax,[last_#name]
		mov [stage_#name],eax
	end iterate
.unkept:
	iterate <name,offset>, hurts_before,Events.reserved+24, rank_before,Events.rank, scroll_before,Events.reserved+40, \
		last_counts,Events.report+80, stage_ship_y,Events.report+92
		mov eax,[rbx+offset]
		mov [name],eax
	end iterate
.done:
	inc [events_seen]
	ret
endp

; The scripted run offers itself tables from a file, and keeps what came of
; it for the frame that is to show it: ECX the file's name, EDX which time
; this is.
proc script_reload uses rbx,name,which
	mov ebx,edx
	fastcall reload_tables,rcx
	fastcall script_record,rax,rbx
	ret
endp

; Or lets the watcher look, as it does once a second in a game that is
; watching: ECX which time this is.
proc script_watch uses rbx,which
	mov ebx,ecx
	mov [watching],1
	mov [watch_due],0
	mov [watch_result],TABLES_UNSEEN
	fastcall watch_tables
	mov [watching],0
	mov eax,[watch_result]
	fastcall script_record,rax,rbx
	ret
endp

proc script_record uses rbx,result,which
	mov ebx,edx
	lea rdx,[reload_results]
	mov [rdx+rbx*4],ecx
	mov rcx,[live_image]
	fastcall tables_sum,rcx
	lea rdx,[reload_sums]
	mov [rdx+rbx*4],eax
	mov rcx,[live_image]
	fastcall tables_counted,rcx
	lea rdx,[reload_counts]
	mov [rdx+rbx*4],eax
	fastcall bank_sum
	lea rdx,[reload_banks]
	mov [rdx+rbx*4],eax
	fastcall music_sum
	lea rdx,[reload_musics]
	mov [rdx+rbx*4],eax
	; And whether the music is playing from where it now is in the bank.
	fastcall audio_music_at
	mov ecx,dword [live_tables+Tables.sound_samples]
	mov rdx,[bank_buffer.mapped]
	lea rdx,[rdx+rcx*4]
	xor ecx,ecx
	cmp rax,rdx
	sete cl
	lea rdx,[reload_played]
	mov [rdx+rbx*4],ecx
	ret
endp

; A sum of the bank as it stands: the sounds, and the stems after them.
proc bank_sum
	mov ecx,dword [live_tables+Tables.sound_samples]
	add ecx,TABLE_STEMS*MUSIC_SAMPLES
	mov rdx,[bank_buffer.mapped]
	xor eax,eax
.sample:
	imul eax,eax,16777619
	xor eax,[rdx]
	add rdx,4
	dec ecx
	jnz .sample
	ret
endp

; And of the music alone, wherever in the bank it is.
proc music_sum
	mov eax,dword [live_tables+Tables.sound_samples]
	mov rdx,[bank_buffer.mapped]
	lea rdx,[rdx+rax*4]
	mov ecx,TABLE_STEMS*MUSIC_SAMPLES
	xor eax,eax
.sample:
	imul eax,eax,16777619
	xor eax,[rdx]
	add rdx,4
	dec ecx
	jnz .sample
	ret
endp

; 32: the tables are taken again while the game runs. RCX a frame's events,
; EDX which frame.
;
; Before a frame, an image is offered: one the game can take, with two things
; changed. It is taken. The frame after says so, and the device's own sum of
; the tables it holds is the image's; the bank, rendered again, is another
; bank, in which the music is sample for sample what it was, further in,
; where the longer sounds have put it; and it is playing from there, each
; stem on its voice once. An image of other names is refused, the frame says that, and what the
; device holds and the bank are as they were. The game's own image, taken
; back, by the watcher, which finds the file written since it last looked:
; the device holds it, and the bank is to the bit the bank it rendered at
; start. The watcher again: the file is as it was, and is not looked into.
; Offered outright once more, it is no change: nothing is told and nothing is
; counted. None of it disturbs a game in which nothing has yet come: the
; three games that follow are held to everything they were, and sum to what
; they did.
;
; Then the fourth game, where there is something to let go of. The changed
; image is taken in the very tick the first squad is due: the squad comes
; whole, a tick later, and as the new tables have it. With two of its five
; out, the game's own image: the two are gone within the frame and the squad
; has begun again, as three. With those three out and their squad done, the
; changed image once more: the three are gone, the squad has begun again,
; and five come.
proc check_reload uses rbx rsi rdi,events,which
	mov rbx,rcx
	mov esi,edx
	; What each offer came to, by which it was.
	iterate <when,which,result,told,taken>, 3,0,TABLES_FIT,ROOT_RELOADED,1, 5,1,TABLES_OTHER,ROOT_REFUSED,1, 7,2,TABLES_FIT,ROOT_RELOADED,2, 9,3,TABLES_UNSEEN,0,2, \
		11,4,TABLES_SAME,0,2, DUE_FRAME,5,TABLES_FIT,ROOT_RELOADED,3, MID_FRAME,6,TABLES_FIT,ROOT_RELOADED,4, RELOAD_FRAME,7,TABLES_FIT,ROOT_RELOADED,5
		cmp esi,when
		jne .not_#when
		cmp [reload_results+which*4],result
		jne .wrong
		; How many times the device has been told the tables were taken; and
		; in a frame that told it anything, what it then held.
		cmp byte [rbx+Events.flags],taken
		jne .wrong
		if told
			mov eax,[reload_sums+which*4]
			cmp eax,[rbx+Events.debug+4]
			jne .wrong
			; And what it made of how many lines each table has.
			mov eax,[reload_counts+which*4]
			cmp eax,[rbx+Events.debug+8]
			jne .wrong
		end if
	.not_#when:
	end iterate
	; What is said: nothing before; then taken; then refused; then taken.
	iterate <when,said>, 2,0, 3,SAY_TABLES_TAKEN+1, 5,SAY_TABLES_REFUSED+1, 7,SAY_TABLES_TAKEN+1, 9,SAY_TABLES_TAKEN+1, 11,SAY_TABLES_TAKEN+1
		cmp esi,when
		jne .unsaid_#when
		cmp byte [rbx+Events.flags+1],said
		jne .wrong
	.unsaid_#when:
	end iterate
	cmp esi,11
	jne .later
	; The other image is another image, with a table that is longer, and so
	; is its bank; what was refused changed neither; and the game's own,
	; taken back, is what it was at start, bank and all.
	mov eax,[reload_counts]
	cmp eax,[reload_counts+8]
	je .wrong
	mov eax,[reload_sums]
	cmp eax,[sum_at_start]
	je .wrong
	cmp eax,[reload_sums+4]
	jne .wrong
	mov eax,[reload_banks]
	cmp eax,[bank_at_start]
	je .wrong
	cmp eax,[reload_banks+4]
	jne .wrong
	iterate which, 2,3,4
		mov eax,[sum_at_start]
		cmp eax,[reload_sums+which*4]
		jne .wrong
		mov eax,[bank_at_start]
		cmp eax,[reload_banks+which*4]
		jne .wrong
	end iterate
	; Whatever was taken, the music is the music: only where it is has changed.
	iterate which, 0,1,2,3,4
		mov eax,[music_at_start]
		cmp eax,[reload_musics+which*4]
		jne .wrong
	end iterate
	; The watcher remembers the file it took as it was written then.
	cmp [watch_stamp],0
	je .wrong
	; Where there is a device to play, the music is playing from where it is
	; in the bank, each time: begun again when the tables were taken, and
	; left alone when they were not.
	cmp [audio_ready],0
	je .played
	iterate which, 0,1,2,3,4
		cmp [reload_played+which*4],1
		jne .wrong
	end iterate
.played:
	; Two were taken, one refused, one not looked into, one no change; and none of it was a frame's traffic.
	cmp [reloads_taken],2
	jne .wrong
	cmp [reloads_refused],1
	jne .wrong
	cmp [reload_dispatches],4
	jne .wrong
.later:
	; The fourth game. Nothing has come when the tables are first taken, in
	; the tick the squad is due; and the squad loses none to that: two of it
	; are out when the second taking comes.
	at_frame DUE_FRAME-1,Events.reserved+28,0,.wrong
	at_frame MID_FRAME-1,Events.reserved+28,2,.wrong
	at_frame MID_FRAME-1,Events.wave,0,.wrong
	; Told in the frame's first tick: by its last the two are gone and the
	; squad's first has come again.
	at_frame MID_FRAME,Events.reserved+28,1,.wrong
	at_frame MID_FRAME,Events.wave,0,.wrong
	; As the game's own tables have it: three, and their squad done.
	at_frame RELOAD_FRAME-1,Events.reserved+28,3,.wrong
	at_frame RELOAD_FRAME-1,Events.wave,1,.wrong
	; The third taking: the three are gone, the squad is to come again, and
	; its first has.
	at_frame RELOAD_FRAME,Events.reserved+28,1,.wrong
	at_frame RELOAD_FRAME,Events.wave,0,.wrong
	; And it comes as the changed tables have it: five.
	at_frame RELOAD_FRAME+24,Events.reserved+28,5,.wrong
	at_frame RELOAD_FRAME+24,Events.wave,1,.wrong
	ret
.wrong:
	fail 32
	ret
endp

; What an offer of tables is taken for, whatever is wrong with it: ECX what
; tables_fit is to say of the image in taken_image, as it has just been spoiled.
proc check_fit expected
	mov [fit_expected],ecx
	fastcall tables_fit,addr taken_image,sizeof.TableImage+TABLE_IMAGE_BYTES,TABLE_PRINT,TABLE_ROOM
	cmp eax,[fit_expected]
	je .right
	mov esi,0
	fail 32
.right:
	; As it was, for the next.
	fastcall take_own
	ret
endp

; And whether tables_sound says of the image in taken_image, as it has just
; been spoiled, what it should: ECX nonzero if it is still sound.
proc check_sound expected
	mov [fit_expected],ecx
	fastcall tables_sound,addr taken_image,addr game_image,ART_FRAMES
	cmp eax,[fit_expected]
	je .right
	xor esi,esi
	fail 32
.right:
	fastcall take_own
	ret
endp

proc take_own uses rsi rdi
	lea rsi,[game_image]
	lea rdi,[taken_image]
	mov ecx,sizeof.TableImage+TABLE_IMAGE_BYTES
	rep movsb
	ret
endp

; 32, in part, before the run: an image that is not whole is not taken for
; one, and a whole one that is not this game's is told from one that is.
proc check_fits uses rsi rdi
	fastcall take_own
	fastcall check_fit,TABLES_FIT
	; Not an image at all; one whose tables do not come to what it says; and
	; one whose file is shorter than it says: half-way to being written.
	mov dword [taken_image+TableImage.magic],0
	fastcall check_fit,TABLES_BROKEN
	inc dword [taken_image+TableImage.counts]
	fastcall check_fit,TABLES_BROKEN
	fastcall tables_fit,addr taken_image,sizeof.TableImage+TABLE_IMAGE_BYTES-4,TABLE_PRINT,TABLE_ROOM
	cmp eax,TABLES_BROKEN
	jne .mistaken
	; A whole one of other names.
	xor dword [taken_image+TableImage.print],1
	fastcall check_fit,TABLES_OTHER
	; And a whole one of these names is too much when there is less room than it needs.
	fastcall tables_fit,addr taken_image,sizeof.TableImage+TABLE_IMAGE_BYTES,TABLE_PRINT,TABLE_IMAGE_BYTES-4
	cmp eax,TABLES_OTHER
	jne .mistaken
	; And a whole image of these names is still not taken if anything in it
	; points outside it. The game's own does not. Then: a kind whose moves
	; begin past the last move; one whose picture is no picture; a squad of
	; a kind there is not; a move that goes back past the first; a move that
	; fires a kind there is not; a sound that does not begin where the ones
	; before it end; moves that do not end as a program ends; and squads,
	; which the game has, gone altogether.
	fastcall check_sound,1
	mov dword [taken_image+IMAGE_KINDS+sizeof.Kind+Kind.first],TABLE_MOVES
	fastcall check_sound,0
	mov dword [taken_image+IMAGE_KINDS+sizeof.Kind+Kind.picture],ART_FRAMES
	fastcall check_sound,0
	mov dword [taken_image+IMAGE_WAVES+Wave.kind],TABLE_KINDS
	fastcall check_sound,0
	mov dword [taken_image+sizeof.TableImage+Move.action],MOVE_AGAIN
	mov dword [taken_image+sizeof.TableImage+Move.target],1
	fastcall check_sound,0
	mov dword [taken_image+sizeof.TableImage+Move.action],MOVE_FIRE
	mov dword [taken_image+sizeof.TableImage+Move.target],TABLE_KINDS
	fastcall check_sound,0
	inc dword [taken_image+IMAGE_SOUNDS+Recipe.first]
	fastcall check_sound,0
	mov dword [taken_image+IMAGE_KINDS-sizeof.Move+Move.ticks],1
	fastcall check_sound,0
	; (The image with its squads taken out of it, and otherwise well made:
	; what follows them moved up, and its counts and its length to match.)
	lea rsi,[taken_image+IMAGE_WAVES+TABLE_WAVES*sizeof.Wave]
	lea rdi,[taken_image+IMAGE_WAVES]
	mov ecx,TABLE_STEMS*sizeof.Stem+TABLE_SAYS*sizeof.Say
	rep movsb
	mov dword [taken_image+TableImage.counts+4*4],0
	sub dword [taken_image+TableImage.bytes],TABLE_WAVES*sizeof.Wave
	fastcall check_sound,0
	jmp .right
.mistaken:
	xor esi,esi
	fail 32
.right:
	ret
endp

; The third game's frames: RCX a frame's events, EDX which frame.
proc check_stage uses rbx rsi rdi,events,which
	mov rbx,rcx
	mov esi,edx
	; 24: charge is earned and spent. A new game has all of it. A pair of
	; missiles costs a quarter. A dash costs a fifth, takes the ship exactly
	; 320 the way it was going, and a shot it crosses on the way passes
	; through it: nothing is lost. A shot that passes close and does not
	; strike pays three hundredths, once. A kill pays six. With a quarter
	; left a launch is paid for; with less, a launch and a dash are each
	; refused, and nothing leaves and nothing moves.
	at_frame STAGE_FRAME+2,Events.state,0,.charge_wrong
	at_frame STAGE_FRAME+2,Events.lives,3,.charge_wrong
	iterate <when,amount,fired,dashes,slipped,grazes,empties>, 2,charge_all,0,0,0,0,0, 6,charge_launched,2,0,0,0,0, 14,charge_dashed,2,1,1,0,0, \
		36,charge_grazed,2,1,1,1,0, 204,charge_last,4,2,1,1,0, 210,charge_last,4,2,1,1,1, 216,charge_last,4,2,1,1,2
		cmp esi,STAGE_FRAME+when
		jne .not_#when
		unless_near dword [rbx+Events.report+76],amount,charge_slack,.charge_wrong
		cmp dword [rbx+Events.reserved+4],fired
		jne .charge_wrong
		mov eax,[rbx+Events.report+80]
		and eax,0FFFFFFh
		cmp eax,(dashes)+((slipped) shl 8)+((grazes) shl 16)
		jne .charge_wrong
		cmp byte [rbx+Events.report+85],empties
		jne .charge_wrong
	.not_#when:
	end iterate
	iterate <when,high>, 14,dash_up, 216,dash_down
		cmp esi,STAGE_FRAME+when
		jne .elsewhere_#when
		unless_near dword [rbx+Events.report+88],ship_column,stage_slack,.charge_wrong
		unless_near dword [rbx+Events.report+92],high,stage_slack,.charge_wrong
	.elsewhere_#when:
	end iterate
	at_frame STAGE_FRAME+14,Events.lives,3,.charge_wrong
	jmp .charged
.charge_wrong:
	fail 24
.charged:
	; 25: the hail-mary. A diver hurt to half fixes on the ship, and the fix
	; is where the ship is though the ship moves. It locks where the ship
	; then was, and stays there. A heavy shot comes for the lock: its mark is
	; the lock, and fades every frame it comes nearer; what loosed it goes the
	; other way. It bursts at the lock. The first time the ship has stayed,
	; and the burst costs it a life; the second it has dashed away, and it
	; costs nothing. The third diver is struck dead while it is still fixing,
	; and that stops nothing: its shot comes as it dies, for where the fix
	; was, and the ship, which killed it and stayed, loses a life to it.
	mov edi,[rbx+Events.report+96]
	mov eax,edi
	mov ecx,[stage_phase]
	cmp ecx,1
	je .fixing
	cmp ecx,2
	je .locked
	cmp ecx,3
	je .flying
	cmp ecx,4
	je .landed
	cmp al,MARK_FOCUS
	jne .staged_done
	mov [stage_phase],1
.fixing:
	cmp al,MARK_FOCUS
	jne .fixed
	unless_near dword [rbx+Events.report+100],rbx+Events.report+88,stage_slack,.stage_wrong
	unless_near dword [rbx+Events.report+104],rbx+Events.report+92,stage_slack,.stage_wrong
	mov eax,[rbx+Events.report+92]
	cmp eax,[stage_ship_y]
	je .staged_done
	mov [stage_followed],1
	jmp .staged_done
.fixed:
	test edi,256
	jnz .fixed_alive
	; Dead while it was fixing: that is the third's part, and nobody else's.
	; Its shot is owed all the same, for where its fix was: on the ship,
	; which has not moved.
	cmp [stage_round],2
	jne .stage_wrong
	mov eax,[rbx+Events.report+88]
	mov [lock_x],eax
	mov eax,[rbx+Events.report+92]
	mov [lock_y],eax
	mov [stage_phase],2
	jmp .locked
.fixed_alive:
	cmp al,MARK_LOCKED
	jne .stage_wrong
	cmp [stage_round],2
	je .stage_wrong
	mov eax,[rbx+Events.report+100]
	mov [lock_x],eax
	mov eax,[rbx+Events.report+104]
	mov [lock_y],eax
	unless_near dword [lock_x],rbx+Events.report+88,stage_slack,.stage_wrong
	unless_near dword [lock_y],rbx+Events.report+92,stage_slack,.stage_wrong
	mov [stage_phase],2
	jmp .staged_done
.locked:
	test edi,1024
	jnz .loosed
	; (The third is dead, and between a death and its shot there is a tick.)
	cmp [stage_round],2
	je .staged_done
	test edi,256
	jz .stage_wrong
	; (Between its mark going with the shot and the shot being made there is a tick.)
	test al,al
	jz .staged_done
	unless_near dword [rbx+Events.report+100],lock_x,stage_slack,.stage_wrong
	unless_near dword [rbx+Events.report+104],lock_y,stage_slack,.stage_wrong
	jmp .staged_done
.loosed:
	mov eax,[rbx+Events.report+108]
	mov [fire_x],eax
	mov eax,[rbx+Events.report+112]
	mov [fire_y],eax
	mov eax,[rbx+Events.reserved+24]
	mov [stage_hurts],eax
	mov [fade_before],2.0
	mov [stage_recoiled],0
	mov [stage_phase],3
.flying:
	test edi,1024
	jz .burst
	unless_near dword [rbx+Events.report+100],lock_x,stage_slack,.stage_wrong
	unless_near dword [rbx+Events.report+104],lock_y,stage_slack,.stage_wrong
	movss xmm0,dword [rbx+Events.report+124]
	ucomiss xmm0,[fade_before]
	jae .stage_wrong
	movss [fade_before],xmm0
	test edi,256
	jz .staged_done
	; How far it has gone since, along the way the shot went: never forward.
	movss xmm0,dword [rbx+Events.report+108]
	subss xmm0,[fire_x]
	movss xmm1,[lock_x]
	subss xmm1,[fire_x]
	mulss xmm0,xmm1
	movss xmm2,dword [rbx+Events.report+112]
	subss xmm2,[fire_y]
	movss xmm1,[lock_y]
	subss xmm1,[fire_y]
	mulss xmm2,xmm1
	addss xmm0,xmm2
	xorps xmm1,xmm1
	ucomiss xmm0,xmm1
	ja .stage_wrong
	jae .staged_done
	mov [stage_recoiled],1
	jmp .staged_done
.burst:
	movzx eax,byte [rbx+Events.report+83]
	mov ecx,[stage_round]
	inc ecx
	cmp eax,ecx
	jne .stage_wrong
	unless_near dword [rbx+Events.report+116],lock_x,stage_near,.stage_wrong
	unless_near dword [rbx+Events.report+120],lock_y,stage_near,.stage_wrong
	movss xmm0,[fade_before]
	ucomiss xmm0,[stage_little]
	ja .stage_wrong
	; What loosed it was seen to go the other way, if it lived to.
	cmp [stage_round],2
	je .burst_seen
	cmp [stage_recoiled],1
	jne .stage_wrong
.burst_seen:
	mov [stage_phase],4
	jmp .staged_done
.landed:
	; The first caught the ship, which had stayed. The second did not: the
	; ship had gone. The third caught it: killing was all the ship had done.
	mov ecx,[stage_round]
	lea rdx,[stage_caught]
	movzx eax,byte [rdx+rcx]
	cmp byte [rbx+Events.report+84],al
	jne .stage_wrong
	mov eax,[rbx+Events.reserved+24]
	sub eax,[stage_hurts]
	lea rdx,[stage_cost]
	movzx ecx,byte [rdx+rcx]
	cmp eax,ecx
	jne .stage_wrong
	inc [stage_round]
	mov [stage_phase],0
	jmp .staged_done
.stage_wrong:
	fail 25
.staged_done:
	; 27: nothing alive is written over. A worm's head is struck dead and
	; something else set down in its slot the tick after: the nine segments
	; die of it all the same. Then a flood: of four hundred hostile shots
	; 384 are made and sixteen refused; of four hundred drones as many are
	; made as there were places free, and the rest refused; with five places
	; emptied side by side a worm, which needs ten, is refused whole; and of
	; ten drones asked for then, five are made and five refused. Every drone
	; is still itself afterwards, and at the end it is all as it was.
	at_frame 1219,Events.reserved+60,10,.room_wrong
	cmp esi,1228
	jne .room_before
	cmp word [rbx+Events.reserved+60],0
	jne .room_wrong
	cmp dword [rbx+Events.reserved+48],0
	je .room_wrong
.room_before:
	cmp esi,1230
	jne .room_after
	mov eax,[rbx+Events.reserved+48]
	mov [room_occupied],eax
	mov eax,[rbx+Events.reserved+52]
	mov [room_refused],eax
.room_after:
	cmp esi,1236
	je .room_full
	cmp esi,1249
	jne .roomed
.room_full:
	cmp dword [rbx+Events.reserved+32],384
	jne .room_wrong
	cmp dword [rbx+Events.reserved+48],384
	jne .room_wrong
	; As many drones as there were places, numbered from one: their numbers sum to n(n+1)/2.
	mov ecx,384
	sub ecx,[room_occupied]
	movzx eax,word [rbx+Events.reserved+62]
	cmp eax,ecx
	jne .room_wrong
	lea eax,[ecx+1]
	imul eax,ecx
	shr eax,1
	cmp eax,[rbx+Events.reserved+56]
	jne .room_wrong
	; Sixteen shots more refused than before; and of hostiles, the drones
	; that did not fit, the worm, and the five too many.
	mov eax,[rbx+Events.reserved+52]
	sub eax,[room_refused]
	mov edx,406
	sub edx,ecx
	shl edx,16
	or edx,16 shl 8
	cmp eax,edx
	je .roomed
.room_wrong:
	fail 27
.roomed:
	ret
endp

; The bank as the device rendered it, for the proof runner: the music, to be
; held to its notes and written out as something a player can open; and the
; sounds, for the mix of the run.
proc write_bank
	mov eax,dword [live_tables+Tables.sound_samples]
	mov rdx,[bank_buffer.mapped]
	lea rdx,[rdx+rax*4]
	fastcall file_put,<W,'build\myhits_game.music.bin'>,rdx,TABLE_STEMS*MUSIC_SAMPLES*4
	test eax,eax
	jz .failed
	mov r8d,dword [live_tables+Tables.sound_samples]
	shl r8d,2
	fastcall file_put,<W,'build\myhits_game.sounds.bin'>,[bank_buffer.mapped],r8
	test eax,eax
	jnz .done
.failed:
	mov [app_io_failed],1
.done:
	ret
endp

; What every frame of the run asked of the voices and of the music, for the
; proof runner to play back into a file (tools\mix.cs).
proc write_heard uses rbx rsi
	fastcall file_begin,<W,'build\myhits_game.heard.bin'>
	mov rsi,rax
	fastcall file_more,rsi,addr heard_head,HEARD_HEAD
	mov ebx,eax
	fastcall file_more,rsi,addr heard_log,SCRIPT_FRAMES*HEARD_BYTES
	and ebx,eax
	fastcall file_done,rsi
	test eax,ebx
	jnz .done
	mov [app_io_failed],1
.done:
	ret
endp

; A thousand frames by the script, then the totals no frame could show alone.
proc scripted_run uses rbx rsi
	fastcall record_start,addr run_test_name
	fastcall write_bank
	fastcall check_fits
	mov rcx,[live_image]
	fastcall tables_sum,rcx
	mov [sum_at_start],eax
	fastcall bank_sum
	mov [bank_at_start],eax
	fastcall music_sum
	mov [music_at_start],eax
	or dword [root+Root.flags],ROOT_SCRIPTED
	mov [script_ticks],GAME_TICKS
	mov ebx,SCRIPT_FRAMES
.frame:
	fastcall play_frame
	test eax,eax
	jz .broken
	dec ebx
	jnz .frame
	fastcall machine_drain
	test eax,eax
	jz .broken
	fastcall machine_write_measure
	fastcall write_heard
	fastcall record_stop
	mov esi,SCRIPT_FRAMES
	; 4 and 9, in part: the rises and falls of rank were seen, and the head did die.
	cmp [rise_checked],0
	je .unseen
	cmp [falls_checked],0
	je .unseen
	cmp [head_died],0
	jne .seen
.unseen:
	fail 10
	cmp [nova_frame],0
	jne .seen
	fail 10
.seen:
	; 13, in part: by the third game's end the HUD has caught up, and there is a score to show.
	mov eax,[stage_score]
	test eax,eax
	jz .hud_wrong
	cmp eax,[last_shown]
	je .hud
.hud_wrong:
	fail 13
.hud:
	; 14: a hurt is felt. Each stopped the world for four ticks, no more and
	; no fewer; and what the pad is told is what the events say: all of the
	; heavy motor is 65535, half of the light one 32768.
	mov eax,[hurts_total]
	shl eax,2
	cmp eax,[last_stopped]
	jne .felt_wrong
	movss xmm0,[felt_all]
	movss xmm1,[felt_half]
	fastcall pad_rumble
	cmp dword [pad_vibration],80000000h+0FFFFh
	je .felt
.felt_wrong:
	fail 14
.felt:
	xorps xmm0,xmm0
	xorps xmm1,xmm1
	fastcall pad_rumble
	; 22: the music. The device found every stem it rendered loud enough and
	; no louder than its gain. With nothing happening only the bass is wanted;
	; with everything, all three, each at its own level. And where there is a
	; device the stems are playing, and say where in the beat they are.
	cmp byte [last_music_faults],0
	jne .music_wrong
	xorps xmm0,xmm0
	fastcall audio_levels
	cmp dword [audio_wanted],0.5
	jne .music_wrong
	mov eax,dword [audio_wanted+4]
	or eax,dword [audio_wanted+8]
	jnz .music_wrong
	movss xmm0,[felt_all]
	fastcall audio_levels
	cmp dword [audio_wanted+4],0.55
	jne .music_wrong
	cmp dword [audio_wanted+8],0.5
	jne .music_wrong
	cmp [audio_ready],0
	je .music
	cmp [audio_playing],1
	jne .music_wrong
	fastcall audio_beat
	xorps xmm1,xmm1
	ucomiss xmm0,xmm1
	jb .music_wrong
	ucomiss xmm0,[felt_all]
	jb .music
.music_wrong:
	fail 22
.music:
	; 30: the level's distance is exact however far the level has come. At
	; start the device asked it of the functions the backdrop is drawn by,
	; with the level three thousand million units on: what repeats was to
	; the bit what it is at the start, what does not repeat still changed
	; from each pixel to the next, and every speck was where it would be.
	cmp byte [last_music_faults+1],0
	je .exact
	fail 30
.exact:
	; 11: the sounds are the events: each sound a frame asked for went to a
	; voice once, none was refused, and every hurt was heard.
	mov eax,[sounds_asked]
	cmp [audio_plays],eax
	jne .sounds_wrong
	cmp [audio_failures],0
	jne .sounds_wrong
	mov eax,[hurts_total]
	cmp eax,3
	jb .sounds_wrong
	cmp [heard_hurts],eax
	je .sounds
.sounds_wrong:
	fail 11
.sounds:
	; 12: every frame's events were read; Root and Events were all the
	; traffic; and a frame of eight ticks is forty-one passes and two draws.
	cmp [events_seen],SCRIPT_FRAMES
	jne .commands
	cmp [traffic_down],SCRIPT_FRAMES*sizeof.Root
	jne .commands
	cmp [traffic_up],SCRIPT_FRAMES*sizeof.Events
	jne .commands
	cmp [startup_dispatches],STARTUP_DISPATCHES
	jne .commands
	cmp [dispatch_count],SCRIPT_FRAMES*(GAME_TICKS*TICK_DISPATCHES+1)
	jne .commands
	cmp [draw_count],SCRIPT_FRAMES*4
	je .manners
.commands:
	fail 12
.manners:
	; 25, in part: all three divers had their turn, the dead one too; the fix
	; was seen to follow the ship; and three shots burst, no more.
	cmp [stage_round],3
	jne .stage_short
	cmp [stage_phase],0
	jne .stage_short
	cmp [stage_followed],1
	jne .stage_short
	cmp byte [last_counts+3],3
	je .staged
.stage_short:
	fail 25
.staged:
	fastcall check_manners
	jmp .report
.broken:
	mov [app_io_failed],1
.report:
	cvtss2sd xmm0,[stage_rank]
	mulsd xmm0,[thousand]
	cvtsd2si eax,xmm0
	mov [title_rank],eax
	fastcall wsprintfW,addr report_text,<W,'proof=game',13,10,'failure=%u',13,10,'failure_frame=%u',13,10,'frames=%u',13,10,'events=%u',13,10, \
		'ticks_a_frame=%u',13,10,'bodies=%u',13,10,'particles=%u',13,10,'kinds=%u',13,10,'moves=%u',13,10,'squads=%u',13,10,'world_bytes=%u',13,10, \
		'head_died_frame=%u',13,10,'nova_frame=%u',13,10,'rise_checked=%u',13,10,'falls_checked=%u',13,10,'hurts_heard=%u',13,10,'sounds_asked=%u',13,10,'plays=%u',13,10,'refused=%u',13,10,'device=%u',13,10, \
		'score=%u',13,10,'kills=%u',13,10,'rank_thousandths=%u',13,10,'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10,'startup_dispatches=%u',13,10,'dispatches=%u',13,10,'draws=%u',13,10, \
		'worst_latency=%u',13,10,'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10,'sums=%08X-%08X-%08X-%08X',13,10, \
		'reloads=%u',13,10,'reloads_refused=%u',13,10,'reload_bytes=%u',13,10,'reload_dispatches=%u',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],GAME_TICKS,BODIES,PARTICLES,TABLE_KINDS,TABLE_MOVES,TABLE_WAVES,WORLD_BYTES, \
		[head_died],[nova_frame],[rise_checked],[falls_checked],[heard_hurts],[sounds_asked],[audio_plays],[audio_failures],[audio_ready],[stage_score],[stage_kills],[title_rank], \
		[traffic_down],[traffic_up],[startup_dispatches],[dispatch_count],[draw_count],[worst_latency],[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage], \
		[sum_first],[sum_second],[sum_third],[sum_fourth],[reloads_taken],[reloads_refused],[reload_bytes],[reload_dispatches]
	; And what each offer of tables came to: what it was taken for, and how
	; whether the music was then playing from where it is in the bank.
	mov ebx,eax
	lea rcx,[report_text]
	lea rcx,[rcx+rbx*2]
	fastcall wsprintfW,rcx,<W,'offers=%u,%u,%u,%u,%u,%u,%u,%u',13,10,'played=%u,%u,%u,%u,%u,%u,%u,%u',13,10,'banks=%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X,%08X',13,10,'frames_sum=%08X',13,10>, \
		[reload_results],[reload_results+4],[reload_results+8],[reload_results+12],[reload_results+16],[reload_results+20],[reload_results+24],[reload_results+28], \
		[reload_played],[reload_played+4],[reload_played+8],[reload_played+12],[reload_played+16],[reload_played+20],[reload_played+24],[reload_played+28], \
		[bank_at_start],[reload_banks],[reload_banks+4],[reload_banks+8],[reload_banks+12],[reload_banks+16],[reload_banks+20],[reload_banks+24],[reload_banks+28],[frames_sum]
	add eax,ebx
	fastcall machine_write_report,rax
	ret
endp

; The scripted run again, from its record and not from its script: every
; frame as the record has it, until the record is over. What it comes to is
; one number, made of every frame's sum of the world; the proof runner holds
; it to the scripted run's own.
; A line for a picture of the strip, from the events of the frame that was
; pictured (ECX which frame these are): which picture it is, how far into
; the run, and how the run stood: its score, the squads begun, the lives,
; what is alive.
proc strip_line frame
	inc ecx
	cmp ecx,[strip_frame]
	jne .done
	mov [strip_frame],0
	cmp [strip_file],0
	je .counted
	fastcall wsprintfW,addr title_text,<W,'%u %u %u %u %u %u',13,10>,[strip_index],[strip_ticks],[last_score],[last_wave],[last_lives],[last_alive]
	lea r8d,[eax*2]
	fastcall file_more,[strip_file],addr title_text,r8
.counted:
	inc [strip_index]
.done:
	ret
endp

proc replayed_run
	; Nobody is watching: its frames are run and not shown, which is as
	; quick as the device is, and not as slow as a monitor.
	mov [machine_unseen],1
	cmp [strip_every],0
	je .frame
	fastcall file_begin,<W,'build\myhits_game.strip.txt'>
	mov [strip_file],rax
.frame:
	fastcall play_frame
	cmp eax,3
	je .over
	test eax,eax
	jnz .frame
	mov [app_io_failed],1
.over:
	fastcall machine_drain
	test eax,eax
	jnz .report
	mov [app_io_failed],1
.report:
	fastcall file_done,[strip_file]
	mov [strip_file],0
	fastcall wsprintfW,addr report_text,<W,'proof=game_replay',13,10,'failure=%u',13,10,'frames=%u',13,10,'events=%u',13,10,'frames_sum=%08X',13,10, \
		'replay_left=%u',13,10,'replay_held=%u',13,10,'ticks=%u',13,10,'score=%u',13,10,'kills=%u',13,10,'squads=%u',13,10,'lives=%u',13,10,'state=%u',13,10, \
		'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		[proof_failure],[root+Root.frame],[events_seen],[frames_sum],[replay_left],[replay_held],dword [ticks_run],[last_score],[last_kills],[last_wave],[last_lives],[last_state], \
		[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage]
	fastcall machine_write_report,rax
	ret
endp

; 23: the window's manners, asked of the window itself by its own messages,
; with no one at it. P pauses: the next frame is paid no ticks and says it is
; paused. Paused, the window answers that its middle is a handle to move it
; by and its edges are edges to size it by; playing, or over the whole
; monitor, that all of it is the game's. F11 takes exactly the monitor and
; gives back exactly what it had. And through all of it the pointer is never
; taken: a scripted run has no one to take it from.
proc check_manners uses rbx rsi
	mov esi,SCRIPT_FRAMES
	and dword [root+Root.flags],not ROOT_SCRIPTED
	fastcall GetWindowRect,[window],addr manners_rect
	mov eax,[manners_rect.left]
	add eax,[manners_rect.right]
	sar eax,1
	mov edx,[manners_rect.top]
	add edx,[manners_rect.bottom]
	sar edx,1
	shl edx,16
	movzx eax,ax
	or eax,edx
	mov [manners_middle],rax
	mov eax,[manners_rect.left]
	add eax,2
	movzx eax,ax
	or eax,edx
	mov [manners_side],rax
	mov eax,[manners_rect.right]
	sub eax,2
	movzx eax,ax
	mov edx,[manners_rect.bottom]
	sub edx,2
	shl edx,16
	or eax,edx
	mov [manners_corner],rax
	; Playing: all of it is the game's.
	fastcall window_proc,[window],WM_NCHITTEST,0,[manners_middle]
	cmp eax,HTCLIENT
	jne .wrong
	fastcall window_proc,[window],WM_KEYDOWN,50h,0
	cmp [paused],1
	jne .wrong
	mov dword [root+Root.ticks],7
	fastcall machine_sample
	cmp dword [root+Root.ticks],0
	jne .wrong
	test dword [root+Root.flags],ROOT_PAUSED
	jz .wrong
	; Paused: a handle, and edges.
	iterate <point,part>, manners_middle,HTCAPTION, manners_side,HTLEFT, manners_corner,HTBOTTOMRIGHT
		fastcall window_proc,[window],WM_NCHITTEST,0,[point]
		cmp eax,part
		jne .wrong
	end iterate
	; The whole monitor, and nothing of it a handle.
	fastcall window_proc,[window],WM_KEYDOWN,VK_F11,0
	cmp [fullscreen],1
	jne .wrong
	fastcall GetWindowRect,[window],addr window_rect
	fastcall window_monitor
	iterate side, left,top,right,bottom
		mov eax,[window_rect.side]
		cmp eax,[monitor_info.rcMonitor.side]
		jne .wrong
	end iterate
	fastcall window_proc,[window],WM_NCHITTEST,0,[manners_middle]
	cmp eax,HTCLIENT
	jne .wrong
	; And back: where it was, as large as it was, and paused still.
	fastcall window_proc,[window],WM_KEYDOWN,VK_F11,0
	cmp [fullscreen],0
	jne .wrong
	fastcall GetWindowRect,[window],addr window_rect
	iterate side, left,top,right,bottom
		mov eax,[window_rect.side]
		cmp eax,[manners_rect.side]
		jne .wrong
	end iterate
	cmp [paused],1
	jne .wrong
	; P again: it plays, and says so.
	fastcall window_proc,[window],WM_KEYDOWN,50h,0
	cmp [paused],0
	jne .wrong
	fastcall machine_sample
	test dword [root+Root.flags],ROOT_PAUSED
	jnz .wrong
	; Leaving it for another program pauses it; coming back does not resume it.
	fastcall window_proc,[window],WM_ACTIVATEAPP,0,0
	cmp [paused],1
	jne .wrong
	fastcall window_proc,[window],WM_ACTIVATEAPP,1,0
	cmp [paused],1
	jne .wrong
	fastcall machine_pause,0
	cmp [confined],0
	je .remembers
.wrong:
	fail 23
.remembers:
	; 26: the window is remembered. Under a name of the check's own, so that
	; what a player left is not disturbed: with nothing remembered it is to
	; have the whole monitor; left as a window somewhere, it comes back there
	; as a window; left over the whole monitor, it comes back so, and to the
	; same place when that is given up.
	lea rax,[manners_value]
	mov [window_state_name],rax
	fastcall state_drop,[window_state_name]
	fastcall window_recall
	cmp eax,1
	jne .forgets
	fastcall SetWindowPos,[window],0,137,91,800,450,SWP_NOZORDER or SWP_NOACTIVATE
	fastcall window_remember
	fastcall SetWindowPos,[window],0,0,0,640,360,SWP_NOZORDER or SWP_NOACTIVATE
	fastcall window_recall
	test eax,eax
	jnz .forgets
	fastcall check_place
	test eax,eax
	jz .forgets
	fastcall machine_fullscreen
	fastcall window_remember
	fastcall machine_fullscreen
	fastcall SetWindowPos,[window],0,0,0,640,360,SWP_NOZORDER or SWP_NOACTIVATE
	fastcall window_recall
	cmp eax,1
	jne .forgets
	fastcall check_place
	test eax,eax
	jnz .done
.forgets:
	fail 26
.done:
	fastcall state_drop,[window_state_name]
	lea rax,[window_state_value]
	mov [window_state_name],rax
	or dword [root+Root.flags],ROOT_SCRIPTED
	ret
endp

; Whether the window is at 137, 91 and 800 by 450.
proc check_place
	fastcall GetWindowRect,[window],addr window_rect
	xor eax,eax
	iterate <side,value>, left,137, top,91, right,937, bottom,541
		cmp [window_rect.side],value
		jne .elsewhere
	end iterate
	mov eax,1
.elsewhere:
	ret
endp

proc mainCRTStartup
	fastcall read_options
	test rax,rax
	jz .failed
	fastcall command_option,<W,'--self-test'>
	mov [test_mode],eax
	fastcall machine_start
	test eax,eax
	jz .failed
	fastcall create_world
	test eax,eax
	jz .failed
	; The checks make no noise; and no device is not a failure.
	fastcall audio_start,[test_mode]
	fastcall play_music
	; A scripted run is always measured; a played one when it is asked to be.
	fastcall command_option,<W,'--measure'>
	or eax,[test_mode]
	jz .unmeasured
	fastcall machine_measure
.unmeasured:
	cmp [test_mode],0
	je .show
	; A check is the scripted run; or, asked to, that run again from the
	; record the scripted run left.
	fastcall command_option,<W,'--replay'>
	test eax,eax
	jz .scripted
	fastcall run_file_name,<W,'--replay'>
	fastcall replay_start,addr run_path
	test eax,eax
	jz .failed
	fastcall command_option,<W,'--record'>
	test eax,eax
	jz .played_back
	fastcall run_file_name,<W,'--record'>
	fastcall record_start,addr run_path
.played_back:
	; A picture of it every so many seconds, if a strip is being made.
	fastcall command_number,<W,'--strip'>
	imul eax,eax,TICK_RATE
	mov [strip_every],eax
	test eax,eax
	jz .unpictured
	fastcall snapshot_start
.unpictured:
	fastcall replayed_run
	jmp .finish
.scripted:
	fastcall snapshot_start
	fastcall scripted_run
	jmp .finish
.show:
	; As it was left; the first time, over the whole monitor; and either way
	; as the command line says, if it says.
	fastcall window_recall
	mov [start_whole],eax
	fastcall command_option,<W,'--windowed'>
	test eax,eax
	jz .as_asked
	mov [start_whole],0
.as_asked:
	fastcall command_option,<W,'--fullscreen'>
	test eax,eax
	jz .as_left
	mov [start_whole],1
.as_left:
	; Watched: it goes on when it is left, and looks at its tables' file.
	fastcall command_option,<W,'--watch'>
	mov [watching],eax
	mov [machine_stays],eax
	; Played back from the last record, if there is one; or recorded.
	fastcall command_option,<W,'--replay'>
	test eax,eax
	jz .not_replayed
	fastcall run_file_name,<W,'--replay'>
	fastcall replay_start,addr run_path
.not_replayed:
	fastcall command_option,<W,'--record'>
	test eax,eax
	jz .unrecorded
	fastcall run_file_name,<W,'--record'>
	fastcall record_start,addr run_path
.unrecorded:
	cmp [start_whole],0
	je .placed
	fastcall machine_fullscreen
.placed:
	fastcall ShowWindow,[window],SW_SHOWNORMAL
	fastcall UpdateWindow,[window]
	; Shown behind another program, or as an icon, it waits to be come to.
	fastcall GetForegroundWindow
	cmp rax,[window]
	je .begin
	fastcall machine_pause,1
.begin:
	fastcall QueryPerformanceCounter,addr clock_last
.messages:
	fastcall PeekMessageW,addr message,0,0,0,PM_REMOVE
	test eax,eax
	jz .idle
	cmp [message.message],WM_QUIT
	je .finish
	fastcall TranslateMessage,addr message
	fastcall DispatchMessageW,addr message
	jmp .messages
.idle:
	; Draw only while there is someone to draw for: not minimized, and either
	; playing in front or showing something other than the last frame. A
	; paused window draws the one frame that says so, and then waits.
	cmp [minimized],0
	jne .wait
	cmp [stale],0
	jne .draw
	cmp [paused],0
	jne .wait
	cmp [watching],0
	jne .draw
	fastcall GetForegroundWindow
	cmp rax,[window]
	jne .wait
.draw:
	fastcall watch_tables
	fastcall play_frame
	test eax,eax
	jz .failed
	mov [stale],0
	jmp .messages
.wait:
	fastcall WaitMessage
	fastcall QueryPerformanceCounter,addr clock_last
	jmp .messages
.failed:
	mov [app_io_failed],1
.finish:
	fastcall record_stop
	cmp [test_mode],0
	jne .measured
	cmp [device],0
	je .measured
	; What a played run cost, if it was measured.
	fastcall machine_drain
	fastcall machine_write_measure
.measured:
	fastcall free_options
	fastcall machine_stop
	fastcall machine_report_exit
	fastcall ExitProcess,rax
	int3
endp

section '.data$game' data readable writeable align 16
absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
thousand dq 1000.0
tolerance dd 0.05
rank_slack dd 0.00002
rank_one dd 0.01
rank_two dd 0.004
rank_rise dd 0.034
rank_fall dd 0.15
spacing dd 112.0
spacing_least dd 104.0			; what the worm's tightest turn can bring two neighbors to
spacing_most dd 112.6
rank_unit dd 1.0
rank_round dd 0.5
worth_swooper dd 200.0
worth_drone dd 150.0
mate_x_first dd 300.0
mate_y_first dd 532.0
mate_x_after dd 310.0
mate_y_after dd 420.0
mate_slack dd 1.5
aim_x dd 1500.0
aim_y dd 300.0
centi dd 0.01
scratch dd 0,0
felt_all dd 1.0
felt_half dd 0.5
full_pace dd 240.0
manners_rect RECT
manners_middle dq 0
manners_side dq 0
manners_corner dq 0
manners_value GLOBWSTR 'window.check',0
charge_all dd 1.0
charge_launched dd 0.75
charge_dashed dd 0.55
charge_grazed dd 0.58
charge_last dd 0.19
charge_slack dd 0.0005
ship_column dd 300.0
dash_up dd 220.0
dash_down dd 700.0
stage_slack dd 0.05
stage_near dd 1.0
stage_little dd 0.1
fade_before dd 2.0
; By which diver: how many bursts have caught the ship once its own has, and what its own cost in lives.
stage_caught db 1,1,2,0
stage_cost db 1,0,1,0
world_buffer GpuBuffer
header_buffer GpuBuffer
home_buffer GpuBuffer
bank_buffer GpuBuffer
iterate name, settle,begin,direct,update,collide,resolve,drift,report,render,scene,particle,veil,backdrop
	name#_pipeline dq 0
end iterate
iterate name, events_seen,proof_failure,proof_failure_frame,startup_dispatches,last_latency,worst_latency,title_rank,sounds_asked,heard_hurts, \
	last_score,last_lives,last_wave,last_state,last_rank,last_fired,last_struck,last_kills,last_hurts,last_alive, \
	hurts_before,rank_before,scroll_before,hurt_frame,hurts_total,rise_checked,falls_checked,chain_seen,head_died,alive_before,last_shown,last_stopped, \
	fired_mark,nova_frame,nova_score,nova_kills,score_before,kills_before,struck_mark,last_music_faults, \
	start_whole,last_counts,stage_ship_y,stage_phase,stage_round,stage_followed,stage_hurts,stage_recoiled,room_occupied,room_refused, \
	sum_first,sum_second,sum_third,sum_fourth,stage_score,stage_kills,stage_rank, \
	strip_every,strip_now,strip_index,strip_frame,strip_ticks,replaying,replayed,replay_left,replay_held,frames_sum,run_at,run_end,watching,watch_result,reload_owed,reloads_taken,reloads_refused,reload_bytes,reload_dispatches,home_groups,bank_groups,fit_expected,sum_at_start,bank_at_start,music_at_start, \
	lock_x,lock_y,fire_x,fire_y
	name dd 0
end iterate

run_file dq 0				; the record being written, if one is
strip_file dq 0				; the lines that go with a strip's pictures
strip_next dq 0				; the tick the next of them is due at
run_head dd 'MRUN',RUN_VERSION,TABLE_PRINT,TICK_RATE
run_mark dd RUN_IMAGE,0
run_came dd RUN_CAME,0,0,0
came_now rq 16				; what each of the last frames came to in this playing: its number and one, and its sum;
came_then rq 16				; and what the record says it came to
run_record rd 8
run_name GLOBWSTR 'build\myhits_last.run',0
run_test_name GLOBWSTR 'build\myhits_game.run',0
reload_results rd 8			; what each of the script's offers of tables came to,
reload_sums rd 8			; the sum of the image then in force,
reload_counts rd 8			; what its tables' lengths come to,
reload_banks rd 8			; of the bank,
reload_musics rd 8			; of the music in it,
reload_played rd 8			; and whether the music was playing from where it is in it
live_image dq game_image		; the image in force: the one built in, until another is taken
; What a run heard, as a file: this, and then a frame's number, how much was
; happening, and its triggers, for every frame.
HEARD_BYTES := 8 + SOUND_KINDS * sizeof.Trigger
HEARD_HEAD := 32
heard_head dd 'HERD',SCRIPT_FRAMES,GAME_TICKS,SOUND_KINDS,HEARD_BYTES,TICK_RATE,SOUND_RATE,TABLE_SOUNDS
watch_due dq 0				; when the tables' file is next looked at, by the frames' clock
watch_stamp dq 0			; when it was written, as it was last taken or refused
watch_seen dq 0
tables_name GLOBWSTR 'build\myhits_tables.bin',0
tables_alt_name GLOBWSTR 'build\myhits_tables_alt.bin',0
tables_bad_name GLOBWSTR 'build\myhits_tables_bad.bin',0

; The game's tables, as the device reads them: an image, as a file of them is.
section '.rdata$game_tables' data readable align 16
game_image:
	include 'tables_image.inc'
assert TABLE_IMAGE_BYTES = TABLE_MOVES * sizeof.Move + TABLE_KINDS * sizeof.Kind + TABLE_STYLES * sizeof.Style + TABLE_SOUNDS * sizeof.Recipe + TABLE_WAVES * sizeof.Wave + TABLE_STEMS * sizeof.Stem + TABLE_SAYS * sizeof.Say
; What a running game may be given in their place has room to be larger: the
; tables to twice what they are and a little, and the sounds to twice what
; they are and two seconds. Past that it is a matter for a build.
TABLE_ROOM := 2 * TABLE_IMAGE_BYTES + 4096
HOME_ROOM := sizeof.GameWorld + TABLE_ROOM	; the header and the tables, in whole words
assert HOME_ROOM and 3 = 0
TAKEN_ROOM := 2 * (sizeof.TableImage + TABLE_ROOM)	; a file up to this is looked at; a larger one is not there
; Where three of the tables are in the game's own image, for the checks that spoil one.
IMAGE_KINDS := sizeof.TableImage + TABLE_MOVES * sizeof.Move
IMAGE_SOUNDS := IMAGE_KINDS + TABLE_KINDS * sizeof.Kind + TABLE_STYLES * sizeof.Style
IMAGE_WAVES := IMAGE_SOUNDS + TABLE_SOUNDS * sizeof.Recipe
BANK_ROOM := 2 * BANK_SAMPLES + 2 * SOUND_RATE + TABLE_STEMS * MUSIC_SAMPLES	; the sounds, then the stems

section '.bss$game_tables' readable writeable align 16
live_tables rb sizeof.Tables		; where the CPU reads each table of the image in force
taken_image rb TAKEN_ROOM		; what a file held
kept_image rb TAKEN_ROOM		; and what was taken from one, which is then the image in force
heard_log rb SCRIPT_FRAMES*HEARD_BYTES
run_taken rb RUN_ROOM			; a record being played back
run_path rw 260				; and the name of its file

section '.rdata$game_spirv' data readable align 4
iterate <name,module>, develop_code,develop, chart_code,chart, census_code,census, settle_code,settle, begin_code,begin, direct_code,direct, update_code,update, \
	collide_code,collide, resolve_code,resolve, drift_code,drift, report_code,report, render_code,render, scene_vertex_code,scene_vertex, \
	scene_fragment_code,scene_fragment, particle_vertex_code,particle_vertex, particle_fragment_code,particle_fragment, veil_vertex_code,veil_vertex, veil_fragment_code,veil_fragment, backdrop_vertex_code,backdrop_vertex, backdrop_fragment_code,backdrop_fragment
	align 4
	name file 'build\myhits_game_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
