; What a running program can take again from a file: so that a number changed
; in a source is on the screen a second after it is saved, in the program
; that was already running, and not after a build and a restart and the
; playing it takes to get back to where the number matters.
;
; A program includes this after machine.inc and tables.inc, with files.inc,
; which says whether a file has been written since it was last looked at and
; brings the whole of one into memory. What is here is what to make of it
; when it is an image of the tables:
;
;	tables_fit	image, bytes, print, room
;				what kind of image `bytes` at `image` are, to a program
;				whose own image has that print and that much room for
;				tables: TABLES_FIT, TABLES_BROKEN (not a whole image:
;				perhaps still being written) or TABLES_OTHER (a whole
;				image of other names, or too large: one for a build)
;	tables_sound	image, own, pictures
;				whether everything in the image that points at
;				something points inside it: a kind's moves, its
;				picture, what follows it; what a move fires, and how
;				far one goes back; a squad's kind; where each sound
;				is in the bank; how long a thing said is. And that
;				the moves end as a program ends, and no table is
;				empty that the program's own image (`own`) has lines
;				in. An image the tools assembled is all of that. One
;				that is not would have the device read what is not
;				there, and a device that does that can take the
;				display down with it: so it is asked first, here.
;	tables_place	image, address, block	fills a Tables: where each table of the
;				image is, if the first is at `address`, and how many
;				lines it has
;	tables_sum	image		a sum of the tables' words, which a device holding
;				them can be held to
;	tables_counted	image		a number made of how many lines each table has and
;				what the sounds come to: what a device should make
;				of its own Tables
;
; What a program does with an image that fits is its own business, and so is
; what it does about whatever was running by the old one.
TABLES_FIT := 1
TABLES_BROKEN := 0
TABLES_OTHER := 2
; Tables has its seven places together, in the order an image has its tables in, and then its seven counts.
assert Tables.says = (TABLE_SORTS-1)*8 & Tables.move_count = TABLE_SORTS*8 & Tables.say_count = Tables.move_count+(TABLE_SORTS-1)*4 & Tables.sound_samples = Tables.move_count+TABLE_SORTS*4

section '.text$reload' code readable executable align 16

proc tables_fit uses rbx rsi,image,bytes,print,room
	mov eax,TABLES_BROKEN
	cmp edx,sizeof.TableImage
	jb .done
	cmp dword [rcx+TableImage.magic],TABLE_MAGIC
	jne .done
	sub edx,sizeof.TableImage
	cmp [rcx+TableImage.bytes],edx
	jne .done
	; Whole, then. Its tables must come to what it says they do,
	xor ebx,ebx
	xor esi,esi
	lea r10,[tables_sizes]
.sort:
	mov eax,[rcx+TableImage.counts+rbx*4]
	mov r11d,[r10+rbx*4]
	mul r11
	add rsi,rax
	inc ebx
	cmp ebx,TABLE_SORTS
	jb .sort
	mov eax,TABLES_BROKEN
	mov edx,[rcx+TableImage.bytes]
	cmp rsi,rdx
	jne .done
	; and it must be of this program's names, and not too much for it.
	mov eax,TABLES_OTHER
	cmp [rcx+TableImage.print],r8d
	jne .done
	cmp edx,r9d
	ja .done
	mov eax,TABLES_FIT
.done:
	ret
endp

proc tables_sound uses rbx rsi rdi r12,image,own,pictures
	mov rbx,rcx
	mov r12d,r8d
	xor eax,eax
.sort:
	cmp dword [rdx+TableImage.counts+rax*4],0
	je .had_none
	cmp dword [rbx+TableImage.counts+rax*4],0
	je .unsound
.had_none:
	inc eax
	cmp eax,TABLE_SORTS
	jb .sort
	lea rdx,[rbx+sizeof.TableImage]
	fastcall tables_place,rbx,rdx,addr sound_tables
	; What a move fires is a kind; one that goes back does not go back past the first.
	mov rsi,qword [sound_tables+Tables.moves]
	mov edi,dword [sound_tables+Tables.move_count]
	xor ecx,ecx
.move:
	cmp ecx,edi
	jae .moved
	mov eax,[rsi+Move.action]
	cmp eax,MOVE_FIRE
	jne .not_fire
	mov eax,[rsi+Move.target]
	cmp eax,dword [sound_tables+Tables.kind_count]
	jae .unsound
	jmp .next_move
.not_fire:
	cmp eax,MOVE_AGAIN
	jne .next_move
	cmp [rsi+Move.target],ecx
	ja .unsound
.next_move:
	add rsi,sizeof.Move
	inc ecx
	jmp .move
.moved:
	; The last move ends a program, so that none runs off the table.
	test edi,edi
	jz .kinds
	cmp dword [rsi-sizeof.Move+Move.action],MOVE_HOLD
	jne .unsound
	cmp dword [rsi-sizeof.Move+Move.ticks],0
	jne .unsound
.kinds:
	mov rsi,qword [sound_tables+Tables.kinds]
	mov ecx,dword [sound_tables+Tables.kind_count]
.kind:
	test ecx,ecx
	jz .waves
	cmp [rsi+Kind.first],edi
	jae .unsound
	cmp [rsi+Kind.wounded_first],edi
	jae .unsound
	cmp [rsi+Kind.picture],r12d
	jae .unsound
	mov eax,dword [sound_tables+Tables.kind_count]
	cmp [rsi+Kind.link_kind],eax
	jae .unsound
	cmp [rsi+Kind.tail_kind],eax
	jae .unsound
	add rsi,sizeof.Kind
	dec ecx
	jmp .kind
.waves:
	mov rsi,qword [sound_tables+Tables.waves]
	mov ecx,dword [sound_tables+Tables.wave_count]
	mov eax,dword [sound_tables+Tables.kind_count]
.wave:
	test ecx,ecx
	jz .sounds
	cmp [rsi+Wave.kind],eax
	jae .unsound
	add rsi,sizeof.Wave
	dec ecx
	jmp .wave
.sounds:
	; Each sound begins where the ones before it end, and all of them come to what the image says.
	mov rsi,qword [sound_tables+Tables.sounds]
	mov ecx,dword [sound_tables+Tables.sound_count]
	xor eax,eax
.sound:
	test ecx,ecx
	jz .sounded
	cmp [rsi+Recipe.first],eax
	jne .unsound
	cmp dword [rsi+Recipe.samples],0
	je .unsound
	add eax,[rsi+Recipe.samples]
	jc .unsound
	add rsi,sizeof.Recipe
	dec ecx
	jmp .sound
.sounded:
	cmp eax,[rbx+TableImage.samples]
	jne .unsound
	mov rsi,qword [sound_tables+Tables.says]
	mov ecx,dword [sound_tables+Tables.say_count]
.say:
	test ecx,ecx
	jz .all_sound
	cmp dword [rsi+Say.count],SAY_LETTERS
	ja .unsound
	add rsi,sizeof.Say
	dec ecx
	jmp .say
.all_sound:
	mov eax,1
	ret
.unsound:
	xor eax,eax
	ret
endp

proc tables_place image,address,block
	xor eax,eax
	lea r10,[tables_sizes]
.sort:
	mov [r8+rax*8],rdx
	mov r9d,[rcx+TableImage.counts+rax*4]
	mov [r8+Tables.move_count+rax*4],r9d
	imul r9d,[r10+rax*4]
	add rdx,r9
	inc eax
	cmp eax,TABLE_SORTS
	jb .sort
	mov eax,[rcx+TableImage.samples]
	mov [r8+Tables.sound_samples],eax
	ret
endp

; (As a program's own shader sums what the device holds: tables_held in myhits.slang.)
proc tables_sum image
	mov edx,[rcx+TableImage.bytes]
	shr edx,2
	add rcx,sizeof.TableImage
	xor eax,eax
	test edx,edx
	jz .done
.word:
	imul eax,eax,16777619
	xor eax,[rcx]
	add rcx,4
	dec edx
	jnz .word
.done:
	ret
endp

; (As tables_counted in common.slang.)
proc tables_counted image
	mov eax,[rcx+TableImage.samples]
	xor edx,edx
.sort:
	imul eax,eax,31
	add eax,[rcx+TableImage.counts+rdx*4]
	inc edx
	cmp edx,TABLE_SORTS
	jb .sort
	ret
endp

section '.data$reload' data readable writeable align 8
sound_tables:
	rb sizeof.Tables
tables_sizes dd sizeof.Move,sizeof.Kind,sizeof.Style,sizeof.Recipe,sizeof.Wave,sizeof.Stem,sizeof.Say
