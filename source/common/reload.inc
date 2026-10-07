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
tables_sizes dd sizeof.Move,sizeof.Kind,sizeof.Style,sizeof.Recipe,sizeof.Wave,sizeof.Stem,sizeof.Say
