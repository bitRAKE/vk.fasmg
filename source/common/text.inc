; Text. The system shapes it; the device draws it.
;
; DirectWrite, which every Windows since 7 carries, lays a string out: it
; chooses a font for what the font asked for lacks, orders what runs right to
; left, joins and reorders and ligates as each script wants, kerns, and breaks
; lines. It is asked through a text layout, and answers by calling back with
; runs of glyphs and where each run's baseline begins. Nothing else is linked
; for any of it: dwrite.dll is the system's.
;
; A glyph's outline is asked of its font face once, an em to the unit, and
; kept as quadratic curves. A TrueType outline is quadratics, which
; DirectWrite hands over raised to cubics: each is put back exactly. A cubic
; that is one in earnest is cut in eight and each piece given the quadratic
; nearest it. The curves go up to the device, which makes the bands they are
; found by and draws them, by the Slug algorithm (text.slang). Nothing is
; rasterized here, and nothing is kept as texels anywhere.
;
;	text_start	the factory; nonzero when it stands
;	text_create	the memory: returns where the device will find the Text,
;			for a program to put in its world, or nothing
;	text_format	RCX = a family's name (UTF-16), EDX = its size on the
;			playfield (a float's bits), R8D = its weight (400 is
;			ordinary, 700 bold), R9D = its stretch (5 is ordinary, 3
;			condensed): a format, or nothing
;	text_set	RCX = a string (UTF-16), EDX = how many units of it,
;			R8 = a format, R9D = x, then y, the width it is laid
;			out in (floats' bits) and its color: sets its glyphs
;			down, after whatever was set down before. What came of
;			it is in text_metrics, text_runs and the rest
;	text_keep	ECX = which line, RDX = a string, R8D = its units, R9 = a
;			format: the string laid out once and kept as that line,
;			for the device to say wherever and as often as it likes
;			(text_said in text.slang). How many glyphs it came to
;	text_lines_clear	no line is kept any more
;	text_shape	RCX = a routine that gives an outline to the sink as a
;			font gives a glyph's, EDX = a number it is given: a shape
;			of the program's own, kept as a glyph is. Which glyph
;	text_put	ECX = a glyph (what text_shape gave), EDX and R8D = where
;			its origin goes, R9D = the size of its em (floats' bits),
;			then its color: that one glyph, set down
;	text_turn	ECX = the first glyph set down that is to turn, EDX and
;			R8D = a point of the playfield, R9D = an angle in radians
;			(floats' bits): those glyphs, and all after, about it
;	text_clear	nothing is set down any more; the glyphs known stay known
;	text_build	what is new since it was last called is taken by the
;			device into memory of its own, and the bands of the new
;			glyphs built: one pass, or four, between frames. Nothing
;			new is drawn, and no line is said, until it has been
;	text_inspect	the device examines every glyph it has: its bands against
;			all its curves, and what it encloses and covers against
;			its area. For a program that proves this; two passes,
;			between frames
;	text_stop
;
; A glyph whose font has colors is set down, or kept, as the layers the
; system makes of it, one over another, each in a color of the font's.
;
; A program includes this after machine.inc, has a pointer to a Text in its
; world, links dwrite.lib, and compiles text.slang's four building passes
; (text_take, text_count, text_place, text_fill) with its own shaders. Setting text down is not a
; frame's traffic: it is what a program does when what it says changes.
extrn DWriteCreateFactory:qword

; Where each method is in its interface's table: dwrite.h, d2d1.h.
COM_AddRef := 1*8
COM_Release := 2*8
FACTORY_CreateTextFormat := 15*8
FACTORY_CreateTextLayout := 18*8
FACTORY_TranslateColorGlyphRun := 28*8	; IDWriteFactory2's: dwrite_2.h
LAYERS_MoveNext := 3*8			; IDWriteColorGlyphRunEnumerator's
LAYERS_GetCurrentRun := 4*8
LAYOUT_Draw := 58*8
LAYOUT_GetMetrics := 60*8
FACE_GetGlyphRunOutline := 14*8
; DWRITE_GLYPH_RUN
RUN_FACE := 0
RUN_SIZE := 8
RUN_COUNT := 12
RUN_INDICES := 16
RUN_ADVANCES := 24
RUN_OFFSETS := 32
RUN_LEVEL := 44
; DWRITE_COLOR_GLYPH_RUN: a run, and after it
LAYER_X := 56
LAYER_Y := 60
LAYER_COLOR := 64			; four floats: red, green, blue, and how much of them
LAYER_PALETTE := 80			; which of the font's colors, or 0FFFFh: none, the text's own
TEXT_FACES := 64			; font faces kept alive at once
TEXT_PIECES := 8			; what a cubic that is no raised quadratic is cut into
TEXT_PASSES := 4			; text_build's, when there are bands to build: one when there are none

; Call a method of an object: its first word points at its table. (fastcall
; uses RAX for its own purposes and leaves R11 alone; and it loads no XMM
; register, so a float a method takes in one is put there first, by hand,
; with nothing in its place among the arguments.)
macro com object*,slot*,arguments&
	mov r11,object
	mov r11,[r11]
	match any, arguments
		fastcall qword [r11+slot],object,arguments
	else
		fastcall qword [r11+slot],object
	end match
end macro
define TEXT_BUFFERS text_block_buffer,text_curve_buffer,text_curve_home,text_glyph_buffer,text_glyph_home,text_laid_buffer,text_laid_home,text_line_buffer,text_line_home, \
	text_placed_buffer,text_band_buffer,text_list_buffer,text_census_buffer,text_sum_buffer
macro text_guid name*,first*,second*,third*,rest*&
	name:
		dd first
		dw second,third
		db rest
end macro

section '.text$text' code readable executable align 16

proc text_start
	fastcall DWriteCreateFactory,0,addr text_iid_factory,addr text_factory
	test eax,eax
	js .failed
	mov eax,1
	ret
.failed:
	mov [text_factory],0
	xor eax,eax
	ret
endp

; The curves, the glyphs and the lines the CPU writes are staged, where it can
; see them, and the device takes them into memory of its own. What is set down
; for the moment is read where it was written. The bands and their lists are
; the device's from the first; and what it found, the CPU reads.
proc text_create uses rbx rdi
	iterate <buffer,bytes,domain>, text_block_buffer,sizeof.Text,MEMORY_UPLOAD, \
		text_curve_buffer,TEXT_CURVES*sizeof.Curve,MEMORY_UPLOAD, text_curve_home,TEXT_CURVES*sizeof.Curve,MEMORY_DEVICE, \
		text_glyph_buffer,TEXT_GLYPHS*sizeof.Glyph,MEMORY_UPLOAD, text_glyph_home,TEXT_GLYPHS*sizeof.Glyph,MEMORY_DEVICE, \
		text_laid_buffer,TEXT_LAID*sizeof.Laid,MEMORY_UPLOAD, text_laid_home,TEXT_LAID*sizeof.Laid,MEMORY_DEVICE, \
		text_line_buffer,TEXT_LINES*sizeof.Line,MEMORY_UPLOAD, text_line_home,TEXT_LINES*sizeof.Line,MEMORY_DEVICE, \
		text_placed_buffer,TEXT_PLACED*sizeof.Placed,MEMORY_UPLOAD, text_band_buffer,TEXT_BANDS*sizeof.Band,MEMORY_DEVICE, \
		text_list_buffer,TEXT_LISTS*4,MEMORY_DEVICE, text_census_buffer,sizeof.TextCensus,MEMORY_READBACK, text_sum_buffer,TEXT_GLYPHS*sizeof.Examined,MEMORY_UPLOAD
		fastcall create_buffer,addr buffer,bytes,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,domain
		test eax,eax
		jz .failed
	end iterate
	mov rbx,[text_block_buffer.mapped]
	mov [text_block],rbx
	xor eax,eax
	iterate <where,bytes>, text_block_buffer,sizeof.Text, text_line_buffer,TEXT_LINES*sizeof.Line, text_census_buffer,sizeof.TextCensus
		mov rdi,[where.mapped]
		mov ecx,bytes
		rep stosb
	end iterate
	iterate <member,buffer>, curves,text_curve_home, glyphs,text_glyph_home, laid,text_laid_home, lines,text_line_home, bands,text_band_buffer, lists,text_list_buffer, \
		placed,text_placed_buffer, census,text_census_buffer, examined,text_sum_buffer, \
		staged_curves,text_curve_buffer, staged_glyphs,text_glyph_buffer, staged_laid,text_laid_buffer, staged_lines,text_line_buffer
		mov rax,[buffer.address]
		mov [rbx+Text.member],rax
	end iterate
	fastcall flush_buffer,addr text_census_buffer
	fastcall text_flush
	mov rax,[text_block_buffer.address]
	ret
.failed:
	xor eax,eax
	ret
endp

proc text_format family,size,weight,stretch
	mov [text_string],rcx
	mov [text_size],edx
	mov [text_weight],r8d
	mov [text_stretch],r9d
	com [text_factory],FACTORY_CreateTextFormat,[text_string],0,[text_weight],0,[text_stretch],[text_size],addr text_locale,addr text_made
	test eax,eax
	js .failed
	mov rax,[text_made]
	ret
.failed:
	xor eax,eax
	ret
endp

; Lay a string out and set its glyphs down. Returns how many were set down,
; or less than none if the system would not lay it out.
proc text_set uses rbx rsi,string,units,format,x,y,width,color
	mov [text_string],rcx
	mov [text_units],edx
	mov [text_form],r8
	mov [text_x],r9d
	mov eax,dword [y]
	mov [text_y],eax
	mov eax,dword [width]
	mov [text_width],eax
	mov eax,dword [color]
	mov [text_color],eax
	mov rax,[text_block]
	mov esi,[rax+Text.placed_count]
	fastcall text_lay
	test eax,eax
	js .failed
	fastcall text_flush
	mov rax,[text_block]
	mov eax,[rax+Text.placed_count]
	sub eax,esi
	ret
.failed:
	mov eax,-1
	ret
endp

; The string in text_string, laid out by the system in the format and the
; width given, and drawn through the renderer below: which sets its glyphs
; down, or keeps them, or only counts them.
proc text_lay uses rbx
	; (A float among the arguments on the stack is its bits, like any other.)
	com [text_factory],FACTORY_CreateTextLayout,[text_string],[text_units],[text_form],[text_width],[text_tall],addr text_layout
	test eax,eax
	js .failed
	xor eax,eax
	iterate name, text_runs,text_backward,text_advance,text_glyphs,text_ink,text_first_x,text_last_x,text_based,text_layered
		mov [name],eax
	end iterate
	; The layout calls back with every run of glyphs: text_draw_run.
	movss xmm3,[text_x]
	com [text_layout],LAYOUT_Draw,0,addr text_renderer,0,[text_y]
	mov ebx,eax
	com [text_layout],LAYOUT_GetMetrics,addr text_metrics
	com [text_layout],COM_Release
	mov [text_layout],0
	mov eax,ebx
	ret
.failed:
	mov eax,-1
	ret
endp

; A string laid out once, on one row, and kept as a line: where each glyph of
; it lies from the left end of its baseline, in ems, and what color the font
; gives it, if it gives one. Nothing of it is set down. Returns how many
; glyphs it came to, or less than none.
proc text_keep uses rbx rsi,line,string,units,format
	mov ebx,ecx
	cmp ebx,TEXT_LINES
	jae .failed
	mov [text_string],rdx
	mov [text_units],r8d
	mov [text_form],r9
	xor eax,eax
	mov [text_x],eax
	mov [text_y],eax
	mov [text_line_step],eax
	mov eax,[text_tall]
	mov [text_width],eax
	mov rax,qword [text_far]
	mov [text_line_low],rax
	mov rax,qword [text_far+8]
	mov [text_line_high],rax
	mov esi,[text_laid_count]
	mov [text_keeping],1
	fastcall text_lay
	mov [text_keeping],0
	test eax,eax
	js .failed
	imul eax,ebx,sizeof.Line
	mov rdx,[text_line_buffer.mapped]
	add rdx,rax
	mov [rdx+Line.first],esi
	mov eax,[text_laid_count]
	sub eax,esi
	mov [rdx+Line.count],eax
	xorps xmm0,xmm0
	movq [rdx+Line.low],xmm0
	movq [rdx+Line.high],xmm0
	movss dword [rdx+Line.wide],xmm0
	movss dword [rdx+Line.step],xmm0
	movss dword [rdx+Line.rise],xmm0
	movss dword [rdx+Line.tall],xmm0
	test eax,eax
	jz .kept
	movss xmm0,[text_baseline]
	divss xmm0,[text_run_size]
	movss dword [rdx+Line.rise],xmm0
	movss xmm0,[text_metrics.height]
	divss xmm0,[text_run_size]
	movss dword [rdx+Line.tall],xmm0
	movss xmm0,[text_metrics.width_with_trailing]
	divss xmm0,[text_run_size]
	movss dword [rdx+Line.wide],xmm0
	mov ecx,[text_line_step]
	mov dword [rdx+Line.step],ecx
	mov rcx,[text_line_low]
	mov [rdx+Line.low],rcx
	mov rcx,[text_line_high]
	mov [rdx+Line.high],rcx
.kept:
	mov [text_dirty],1
	ret
.failed:
	mov eax,-1
	ret
endp

; No line is kept any more: for a program whose lines have all changed.
proc text_lines_clear uses rdi
	mov rdi,[text_line_buffer.mapped]
	mov ecx,TEXT_LINES*sizeof.Line
	xor eax,eax
	rep stosb
	mov [text_laid_count],eax
	mov rdx,[text_block]
	mov [rdx+Text.laid_count],eax
	mov [rdx+Text.laid_from],eax
	mov [text_dirty],1
	ret
endp

; What the CPU wrote, where the device will read it or take it from.
proc text_flush
	iterate buffer, text_curve_buffer,text_glyph_buffer,text_laid_buffer,text_line_buffer,text_placed_buffer,text_block_buffer
		fastcall flush_buffer,addr buffer
	end iterate
	ret
endp

proc text_clear
	mov rax,[text_block]
	mov dword [rax+Text.placed_count],0
	fastcall flush_buffer,addr text_block_buffer
	ret
endp

; One glyph set down by itself, upright: a shape of the program's own, which
; no string has in it. Nothing, if there is no such glyph or no more room.
proc text_put uses rbx,glyph,x,y,size,color
	mov rbx,[text_block]
	cmp ecx,[rbx+Text.glyph_count]
	jae .none
	mov eax,[rbx+Text.placed_count]
	cmp eax,TEXT_PLACED
	jae .crowded
	imul eax,eax,sizeof.Placed
	mov r10,[text_placed_buffer.mapped]
	add r10,rax
	mov dword [r10+Placed.at],edx
	mov dword [r10+Placed.at+4],r8d
	mov dword [r10+Placed.across],r9d
	mov dword [r10+Placed.across+4],0
	mov [r10+Placed.glyph],ecx
	mov eax,dword [color]
	mov [r10+Placed.color],eax
	inc dword [rbx+Text.placed_count]
	fastcall text_flush
	ret
.crowded:
	inc [text_lost]
.none:
	ret
endp

; Turn what was set down, from the glyph numbered ECX on, about a point: each
; glyph's place goes round the point, and its own em turns with it.
proc text_turn uses rbx,first,x,y,angle
	mov ebx,ecx
	mov [text_pen],edx
	mov [text_base],r8d
	mov [text_slot],r9d
	fld dword [text_slot]
	fsincos
	fstp dword [text_cos]
	fstp dword [text_sin]
	mov r8,[text_block]
	mov r9,[text_placed_buffer.mapped]
.glyph:
	cmp ebx,[r8+Text.placed_count]
	jae .done
	imul eax,ebx,sizeof.Placed
	lea rdx,[r9+rax]
	; Its place, about the point; then its em: (x cos - y sin, x sin + y cos).
	movss xmm0,dword [rdx+Placed.at]
	subss xmm0,[text_pen]
	movss xmm1,dword [rdx+Placed.at+4]
	subss xmm1,[text_base]
	iterate <member,add_x,add_y>, at,text_pen,text_base, across,text_nothing,text_nothing
		if % = 2
			movss xmm0,dword [rdx+Placed.across]
			movss xmm1,dword [rdx+Placed.across+4]
		end if
		movaps xmm2,xmm0
		mulss xmm2,[text_cos]
		movaps xmm3,xmm1
		mulss xmm3,[text_sin]
		subss xmm2,xmm3
		addss xmm2,[add_x]
		mulss xmm0,[text_sin]
		mulss xmm1,[text_cos]
		addss xmm0,xmm1
		addss xmm0,[add_y]
		movss dword [rdx+Placed.member],xmm2
		movss dword [rdx+Placed.member+4],xmm0
	end iterate
	inc ebx
	jmp .glyph
.done:
	fastcall flush_buffer,addr text_placed_buffer
	ret
endp

; What is new is taken, and the bands of the glyphs that are new are built:
; counted, given their places in the lists, and filled. The taking, the
; counting and the filling are a thread to each thing; the placing is one
; thread, since a place depends on every place before it. With nothing new,
; nothing is done; with no new band, only the taking.
proc text_build uses rbx rsi
	mov rbx,[text_block]
	mov eax,[text_curve_count]
	mov [rbx+Text.curve_count],eax
	mov eax,[text_laid_count]
	mov [rbx+Text.laid_count],eax
	fastcall text_flush
	mov esi,[rbx+Text.band_count]
	sub esi,[rbx+Text.band_from]
	mov ecx,[rbx+Text.glyph_count]
	sub ecx,[rbx+Text.glyph_from]
	mov eax,esi
	or eax,ecx
	or eax,[text_dirty]
	jz .built
	; As many threads as the most there is of any one thing to take.
	mov eax,TEXT_LINES
	cmp eax,ecx
	cmovb eax,ecx
	iterate <from,count>, curve_from,curve_count, laid_from,laid_count
		mov ecx,[rbx+Text.count]
		sub ecx,[rbx+Text.from]
		cmp eax,ecx
		cmovb eax,ecx
	end iterate
	add eax,63
	shr eax,6
	mov [text_taking],eax
	lea eax,[esi+63]
	shr eax,6
	mov [text_groups],eax
	fastcall machine_serial_open
	test eax,eax
	jz .failed
	fastcall machine_dispatch,[text_take_pipeline],[text_taking]
	inc [text_dispatched]
	test esi,esi
	jz .taken
	fastcall machine_settle
	fastcall machine_dispatch,[text_count_pipeline],[text_groups]
	fastcall machine_settle
	fastcall machine_dispatch,[text_place_pipeline],1
	fastcall machine_settle
	fastcall machine_dispatch,[text_fill_pipeline],[text_groups]
	add [text_dispatched],3
	inc [text_builds]
.taken:
	fastcall machine_serial_close
	test eax,eax
	jz .failed
	iterate <from,count>, curve_from,curve_count, glyph_from,glyph_count, laid_from,laid_count, band_from,band_count
		mov eax,[rbx+Text.count]
		mov [rbx+Text.from],eax
	end iterate
	inc dword [rbx+Text.taken]
	inc [text_takes]
	mov [text_dirty],0
	fastcall flush_buffer,addr text_block_buffer
	fastcall invalidate_buffer,addr text_census_buffer
.built:
	mov eax,1
.failed:
	ret
endp

; Every glyph examined: a thread to each row of places over it, each adding
; what it found to its glyph's sum, which begins at nothing; and then a
; thread to a glyph, to judge the sums.
proc text_inspect uses rbx rdi
	mov rbx,[text_block]
	mov rdi,[text_sum_buffer.mapped]
	mov ecx,TEXT_GLYPHS*sizeof.Examined
	xor eax,eax
	rep stosb
	fastcall flush_buffer,addr text_sum_buffer
	fastcall text_flush
	mov eax,[rbx+Text.glyph_count]
	imul eax,eax,TEXT_EXAMINED_MOST
	add eax,63
	shr eax,6
	mov [text_groups],eax
	mov eax,[rbx+Text.glyph_count]
	add eax,63
	shr eax,6
	mov [text_judged],eax
	fastcall machine_serial_open
	test eax,eax
	jz .failed
	fastcall machine_dispatch,[text_examine_pipeline],[text_groups]
	fastcall machine_settle
	fastcall machine_dispatch,[text_judge_pipeline],[text_judged]
	add [text_dispatched],2
	fastcall machine_serial_close
	test eax,eax
	jz .failed
	fastcall invalidate_buffer,addr text_census_buffer
	mov eax,1
.failed:
	ret
endp

proc text_stop uses rbx
	xor ebx,ebx
.face:
	cmp ebx,[text_face_count]
	jae .faces
	lea rax,[text_faces]
	mov rax,[rax+rbx*8]
	mov [text_made],rax
	com [text_made],COM_Release
	inc ebx
	jmp .face
.faces:
	mov [text_face_count],0
	cmp [text_factory],0
	je .buffers
	com [text_factory],COM_Release
	mov [text_factory],0
.buffers:
	match buffers, TEXT_BUFFERS
		iterate buffer, buffers
			fastcall destroy_buffer,addr buffer
		end iterate
	end match
	ret
endp

; A font face that glyphs are known by is kept alive, so that no other can
; come to have its address while they are.
proc text_face face
	xor eax,eax
	lea rdx,[text_faces]
.known:
	cmp eax,[text_face_count]
	jae .new
	cmp [rdx+rax*8],rcx
	je .done
	inc eax
	jmp .known
.new:
	cmp eax,TEXT_FACES
	jae .done
	mov [rdx+rax*8],rcx
	inc [text_face_count]
	mov [text_made],rcx
	com [text_made],COM_AddRef
.done:
	ret
endp

; A shape of the program's own, kept as a glyph is and drawn as one. RCX is a
; routine that gives its outline to the sink the way a font gives a glyph's:
; text_sink_begin with where a figure starts, text_sink_lines and
; text_sink_cubics with what follows from there, text_sink_end; an em to the
; unit, y downward, as many figures as it likes. EDX is a number the routine is
; given in ECX, so that one routine may give several shapes. Which glyph it
; is, of all that are known: asked for again it is the same one, and the
; routine is not called. Its bands are built with the rest, by text_build.
proc text_shape outline,number
	mov [text_own],1
	fastcall text_glyph,rcx,rdx
	mov [text_own],0
	ret
endp

; Which glyph of all that are known this one of this face is: found, or its
; outline asked for and kept. Less than none if there is no more room.
proc text_glyph uses rbx rsi rdi,face,index
	mov rsi,rcx
	mov edi,edx
	mov rax,[text_block]
	mov ecx,[rax+Text.glyph_count]
	lea rdx,[text_keys]
	xor ebx,ebx
.known:
	cmp ebx,ecx
	jae .new
	cmp [rdx+8],edi
	jne .next
	cmp [rdx],rsi
	je .found
.next:
	add rdx,16
	inc ebx
	jmp .known
.found:
	mov eax,ebx
	ret
.new:
	cmp ebx,TEXT_GLYPHS
	jae .none
	mov [rdx],rsi
	mov [rdx+8],edi
	; Its outline, an em to the unit: the sink below takes it.
	mov eax,[text_curve_count]
	mov [text_first],eax
	mov [text_measuring],0
	mov dword [text_scale],1.0
	fastcall text_open
	cmp [text_own],0
	jne .own
	mov word [text_one],di
	movss xmm1,[text_scale]
	com rsi,FACE_GetGlyphRunOutline,0,addr text_one,0,0,1,0,0,addr text_sink
	jmp .given
.own:
	; (Not a font's: the program's routine is what it is known by, and gives it.)
	fastcall rsi,rdi
.given:
	; What it came to: its curves, their box, their area, and bands for them.
	imul eax,ebx,sizeof.Glyph
	mov rdx,[text_glyph_buffer.mapped]
	add rdx,rax
	mov eax,[text_first]
	mov [rdx+Glyph.curves],eax
	mov ecx,[text_curve_count]
	sub ecx,eax
	mov [rdx+Glyph.curve_count],ecx
	mov qword [rdx+Glyph.low],0
	mov qword [rdx+Glyph.high],0
	mov eax,[text_area]
	mov [rdx+Glyph.area],eax
	mov r8,[text_block]
	mov eax,[r8+Text.band_count]
	mov [rdx+Glyph.bands],eax
	; A band to every two curves, each way; at most TEXT_BANDS_MOST, and none for nothing.
	xor eax,eax
	test ecx,ecx
	jz .banded
	mov rax,[text_low]
	mov [rdx+Glyph.low],rax
	mov rax,[text_high]
	mov [rdx+Glyph.high],rax
	mov eax,ecx
	shr eax,1
	mov r9d,1
	cmp eax,r9d
	cmovb eax,r9d
	mov r9d,TEXT_BANDS_MOST
	cmp eax,r9d
	cmova eax,r9d
	; (And none if there is no room left for them: it is then a glyph of no curves.)
	mov r9d,[r8+Text.band_count]
	lea r9d,[r9+rax*2]
	cmp r9d,TEXT_BANDS
	jbe .banded
	xor eax,eax
	mov dword [rdx+Glyph.curve_count],0
.banded:
	mov [rdx+Glyph.rows],eax
	mov [rdx+Glyph.columns],eax
	shl eax,1
	add [r8+Text.band_count],eax
	inc dword [r8+Text.glyph_count]
	mov eax,ebx
	ret
.none:
	inc [text_lost]
	mov eax,-1
	ret
endp

; The sink is about to be given an outline: nothing of one has come yet.
proc text_open
	mov rax,qword [text_far]
	mov [text_low],rax
	mov rax,qword [text_far+8]
	mov [text_high],rax
	mov [text_area],0
	ret
endp

; One curve of an outline: XMM0 where it begins, XMM1 its middle point, XMM2
; where it ends, each an x and a y. Its box and its area are added to; and,
; unless the outline is only being measured, it is kept.
proc text_curve
	movaps xmm3,xmm0
	minps xmm3,xmm1
	minps xmm3,xmm2
	movq xmm4,[text_low]
	minps xmm4,xmm3
	movq [text_low],xmm4
	movaps xmm3,xmm0
	maxps xmm3,xmm1
	maxps xmm3,xmm2
	movq xmm4,[text_high]
	maxps xmm4,xmm3
	movq [text_high],xmm4
	cmp [text_measuring],0
	jne .done
	mov eax,[text_curve_count]
	cmp eax,TEXT_CURVES
	jae .full
	imul eax,eax,sizeof.Curve
	mov rdx,[text_curve_buffer.mapped]
	movq [rdx+rax+Curve.p1],xmm0
	movq [rdx+rax+Curve.p2],xmm1
	movq [rdx+rax+Curve.p3],xmm2
	inc [text_curve_count]
	; What it encloses with the origin: (2 p1 x p2 + 2 p2 x p3 + p1 x p3) / 6.
	iterate <from,to,weight>, xmm0,xmm1,text_third, xmm1,xmm2,text_third, xmm0,xmm2,text_sixth
		movaps xmm3,to
		shufps xmm3,xmm3,1
		mulps xmm3,from
		movaps xmm4,xmm3
		shufps xmm4,xmm4,1
		subss xmm3,xmm4
		mulss xmm3,[weight]
		addss xmm3,[text_area]
		movss [text_area],xmm3
	end iterate
.done:
	ret
.full:
	inc [text_lost]
	ret
endp

; DirectWrite's side of the layout: IDWriteTextRenderer. It is told that
; nothing is snapped to pixels, since a glyph here may stand anywhere.
proc text_renderer_query this,iid,out
	mov rax,[rdx]
	mov r10,[rdx+8]
	iterate known, text_iid_unknown,text_iid_snapping,text_iid_renderer
		cmp rax,qword [known]
		jne .not_#known
		cmp r10,qword [known+8]
		je .is
	.not_#known:
	end iterate
	mov qword [r8],0
	mov eax,80004002h		; E_NOINTERFACE
	ret
.is:
	mov [r8],rcx
	xor eax,eax
	ret
endp

proc text_sink_query this,iid,out
	mov rax,[rdx]
	mov r10,[rdx+8]
	iterate known, text_iid_unknown,text_iid_sink
		cmp rax,qword [known]
		jne .not_#known
		cmp r10,qword [known+8]
		je .is
	.not_#known:
	end iterate
	mov qword [r8],0
	mov eax,80004002h
	ret
.is:
	mov [r8],rcx
	xor eax,eax
	ret
endp

; (Neither is ever freed: they are this program's own.)
proc text_counted this
	mov eax,1
	ret
endp

proc text_unsnapped this,context,disabled
	mov dword [r8],1
	xor eax,eax
	ret
endp

proc text_untransformed this,context,matrix
	mov dword [r8],1.0
	mov dword [r8+4],0
	mov dword [r8+8],0
	mov dword [r8+12],1.0
	mov qword [r8+16],0
	xor eax,eax
	ret
endp

proc text_unscaled this,context,pixels
	mov dword [r8],1.0
	xor eax,eax
	ret
endp

; (Underlines, strikings-through and things set in the line: none are asked for.)
proc text_undrawn
	xor eax,eax
	ret
endp

; A run of glyphs, of one font face at one size, going one way: where its
; baseline begins is in XMM2 and XMM3. What the system made of the string is
; counted from it. Then it is set down: as it is, in the color the text was
; given; or, if its font has colors, as the layers the system makes of it,
; one over another, each a run of its own in a color of the font's.
proc text_draw_run uses rbx rsi rdi,this,context,origin_x,origin_y,mode,run,description,effect
	movss [text_run_x],xmm2
	movss [text_run_y],xmm3
	mov rsi,[run]
	mov eax,[rsi+RUN_LEVEL]
	and eax,1
	add [text_backward],eax
	inc [text_runs]
	mov ecx,[rsi+RUN_COUNT]
	mov rdx,[rsi+RUN_INDICES]
	mov r8,[rsi+RUN_ADVANCES]
	xor ebx,ebx
.count:
	cmp ebx,ecx
	jae .counted
	; (The first few glyphs of what is being laid, by their numbers in their
	; fonts: for a program that asks what the system made of a string.)
	mov eax,[text_glyphs]
	inc [text_glyphs]
	cmp eax,16
	jae .unseen
	movzx r9d,word [rdx+rbx*2]
	lea r10,[text_seen]
	mov [r10+rax*4],r9d
.unseen:
	movss xmm0,[text_advance]
	addss xmm0,dword [r8+rbx*4]
	movss [text_advance],xmm0
	inc ebx
	jmp .count
.counted:
	; The first run's baseline is the line's: what a kept line is measured from.
	cmp [text_based],0
	jne .based
	mov [text_based],1
	mov eax,[text_run_y]
	mov [text_baseline],eax
.based:
	mov [text_layers],0
	movss xmm1,[text_run_x]
	movss xmm2,[text_run_y]
	com [text_factory],FACTORY_TranslateColorGlyphRun,0,0,[run],[description],0,0,0,addr text_layers
	test eax,eax
	js .plain			; most often DWRITE_E_NOCOLOR: a font of one color
	cmp [text_layers],0
	je .plain
.layer:
	mov [text_has],0
	com [text_layers],LAYERS_MoveNext,addr text_has
	test eax,eax
	js .layered
	cmp [text_has],0
	je .layered
	com [text_layers],LAYERS_GetCurrentRun,addr text_layer
	test eax,eax
	js .layered
	mov rdi,[text_layer]
	; Its color: the text's own if the font names none; or the font's, four
	; floats made the four bytes of a texel.
	mov edx,[text_color]
	xor ebx,ebx
	cmp word [rdi+LAYER_PALETTE],0FFFFh
	je .hued
	xor edx,edx
	iterate <channel,place>, 0,0, 4,8, 8,16, 12,24
		movss xmm0,dword [rdi+LAYER_COLOR+channel]
		mulss xmm0,[text_bytes]
		cvtss2si eax,xmm0
		mov ecx,255
		cmp eax,ecx
		cmovg eax,ecx
		xor ecx,ecx
		test eax,eax
		cmovs eax,ecx
		shl eax,place
		or edx,eax
	end iterate
	mov ebx,1
	; (A layer there is nothing of is not one.)
	test edx,0FF000000h
	jz .layer
.hued:
	; (The first few layers of what is being laid: each one's first glyph,
	; its color, and which of its font's colors that is.)
	mov eax,[text_layered]
	inc [text_layered]
	inc [text_layers_made]
	cmp eax,TEXT_LAYERS_SEEN
	jae .unlisted
	lea rcx,[text_layers_seen]
	lea rax,[rax+rax*2]
	lea rcx,[rcx+rax*4]
	mov r8,[rdi+RUN_INDICES]
	movzx r8d,word [r8]
	mov [rcx],r8d
	mov [rcx+4],edx
	movzx r8d,word [rdi+LAYER_PALETTE]
	mov [rcx+8],r8d
.unlisted:
	mov eax,dword [rdi+LAYER_X]
	mov [text_pen],eax
	mov [text_origin],eax
	mov eax,dword [rdi+LAYER_Y]
	mov [text_base],eax
	fastcall text_place_run,rdi,rdx,rbx
	jmp .layer
.layered:
	com [text_layers],COM_Release
	mov [text_layers],0
	jmp .done
.plain:
	mov eax,[text_run_x]
	mov [text_pen],eax
	mov [text_origin],eax
	mov eax,[text_run_y]
	mov [text_base],eax
	fastcall text_place_run,rsi,[text_color],0
.done:
	xor eax,eax
	ret
endp

; A run's glyphs, set down or kept: RCX the run, EDX its color, R8D whether
; that color is its font's own; where its baseline begins is in text_pen and
; text_base. Each glyph goes at the pen and the pen moves on by its advance;
; a run that goes right to left begins at its right-hand end, and its pen
; moves left before each glyph, not after.
proc text_place_run uses rbx rsi rdi r12 r13 r14 r15,run,color,own
	mov rsi,rcx
	mov [text_run_color],edx
	mov [text_run_own],r8d
	mov r12,[rsi+RUN_FACE]
	mov r13d,[rsi+RUN_COUNT]
	mov r14,[rsi+RUN_INDICES]
	mov r15,[rsi+RUN_ADVANCES]
	mov rdi,[rsi+RUN_OFFSETS]
	mov eax,[rsi+RUN_SIZE]
	mov [text_run_size],eax
	mov eax,[rsi+RUN_LEVEL]
	and eax,1
	mov [text_run_backward],eax
	fastcall text_face,r12
	mov rax,qword [text_far]
	mov [text_run_low],rax
	mov rax,qword [text_far+8]
	mov [text_run_high],rax
	xor ebx,ebx
.glyph:
	cmp ebx,r13d
	jae .run_done
	movzx edx,word [r14+rbx*2]
	fastcall text_glyph,r12,rdx
	mov [text_slot],eax
	movss xmm0,dword [r15+rbx*4]
	movss [text_one_advance],xmm0
	xorps xmm1,xmm1
	xorps xmm2,xmm2
	test rdi,rdi
	jz .pen
	movss xmm1,dword [rdi+rbx*8]	; along the run, the way it goes
	movss xmm2,dword [rdi+rbx*8+4]	; and up
.pen:
	movss xmm3,[text_pen]
	cmp [text_run_backward],0
	je .forward
	subss xmm3,xmm0
	movss [text_pen],xmm3
	subss xmm3,xmm1
	jmp .at
.forward:
	movaps xmm4,xmm3
	addss xmm4,xmm0
	movss [text_pen],xmm4
	addss xmm3,xmm1
.at:
	movss xmm4,[text_base]
	subss xmm4,xmm2
	mov eax,[text_slot]
	test eax,eax
	js .next
	; A glyph of no curves is not set down: a space is only its advance.
	imul eax,eax,sizeof.Glyph
	mov rdx,[text_glyph_buffer.mapped]
	add rdx,rax
	cmp dword [rdx+Glyph.curve_count],0
	je .next
	; (Where the first and the last of what is being set were put: which
	; way it went is which of them is further right.)
	cmp [text_ink],0
	jne .not_first
	movss [text_first_x],xmm3
.not_first:
	movss [text_last_x],xmm3
	; What it should come to on the page: its area, at its size.
	movss xmm0,dword [rdx+Glyph.area]
	andps xmm0,xword [text_absolute]
	mulss xmm0,[text_run_size]
	mulss xmm0,[text_run_size]
	addss xmm0,[text_ink]
	movss [text_ink],xmm0
	cmp [text_placing],0
	je .next
	cmp [text_keeping],0
	jne .keep
	mov r8,[text_block]
	mov ecx,[r8+Text.placed_count]
	cmp ecx,TEXT_PLACED
	jae .crowded
	imul ecx,ecx,sizeof.Placed
	mov r9,[text_placed_buffer.mapped]
	add r9,rcx
	movss dword [r9+Placed.at],xmm3
	movss dword [r9+Placed.at+4],xmm4
	mov eax,[text_run_size]
	mov dword [r9+Placed.across],eax
	mov dword [r9+Placed.across+4],0
	mov eax,[text_slot]
	mov [r9+Placed.glyph],eax
	mov eax,[text_run_color]
	mov [r9+Placed.color],eax
	inc dword [r8+Text.placed_count]
	; Where its box is in the run: at its place, and its size times its box in ems.
	unpcklps xmm3,xmm4
	movss xmm5,[text_run_size]
	shufps xmm5,xmm5,0
	movq xmm0,[rdx+Glyph.low]
	mulps xmm0,xmm5
	addps xmm0,xmm3
	movq xmm1,[text_run_low]
	minps xmm1,xmm0
	movq [text_run_low],xmm1
	movq xmm0,[rdx+Glyph.high]
	mulps xmm0,xmm5
	addps xmm0,xmm3
	movq xmm1,[text_run_high]
	maxps xmm1,xmm0
	movq [text_run_high],xmm1
	jmp .next
.keep:
	; Kept: where it is from the left end of the line's baseline, in ems;
	; and its font's color, if this is one.
	mov ecx,[text_laid_count]
	cmp ecx,TEXT_LAID
	jae .crowded
	imul ecx,ecx,sizeof.Laid
	mov r9,[text_laid_buffer.mapped]
	add r9,rcx
	movss xmm5,[text_run_size]
	divss xmm3,xmm5
	subss xmm4,[text_baseline]
	divss xmm4,xmm5
	movss dword [r9+Laid.at],xmm3
	movss dword [r9+Laid.at+4],xmm4
	mov eax,[text_slot]
	mov [r9+Laid.glyph],eax
	xor eax,eax
	cmp [text_run_own],0
	je .hue
	mov eax,[text_run_color]
.hue:
	mov [r9+Laid.color],eax
	inc [text_laid_count]
	; The line's box takes in the glyph's, and its step the glyph's advance.
	unpcklps xmm3,xmm4
	movq xmm0,[rdx+Glyph.low]
	addps xmm0,xmm3
	movq xmm1,[text_line_low]
	minps xmm1,xmm0
	movq [text_line_low],xmm1
	movq xmm0,[rdx+Glyph.high]
	addps xmm0,xmm3
	movq xmm1,[text_line_high]
	maxps xmm1,xmm0
	movq [text_line_high],xmm1
	movss xmm0,[text_one_advance]
	divss xmm0,xmm5
	maxss xmm0,[text_line_step]
	movss [text_line_step],xmm0
	jmp .next
.crowded:
	inc [text_lost]
.next:
	inc ebx
	jmp .glyph
.run_done:
	cmp [text_checking],0
	je .done
	cmp [text_placing],0
	je .done
	cmp [text_keeping],0
	jne .done
	; A program that is checking asks the system for the whole run's outline,
	; set down as the system sets it, and holds the box of that to the box of
	; the glyphs as they were set down here.
	mov [text_measuring],1
	mov eax,[text_run_size]
	mov [text_scale],eax
	fastcall text_open
	movss xmm1,[text_scale]
	mov eax,[text_run_backward]
	mov [text_way],eax
	com r12,FACE_GetGlyphRunOutline,0,r14,r15,rdi,r13,0,[text_way],addr text_sink
	mov [text_measuring],0
	mov eax,dword [text_low]
	cmp eax,dword [text_far]
	je .done			; a run of nothing but spaces has no box
	inc [text_runs_held]
	; The system's is about the run's own origin; ours is on the page.
	movss xmm0,[text_origin]
	movss xmm1,[text_base]
	unpcklps xmm0,xmm1
	movq xmm1,[text_low]
	addps xmm1,xmm0
	movq xmm2,[text_run_low]
	subps xmm1,xmm2
	andps xmm1,xword [text_absolute]
	movq xmm3,[text_high]
	addps xmm3,xmm0
	movq xmm2,[text_run_high]
	subps xmm3,xmm2
	andps xmm3,xword [text_absolute]
	maxps xmm1,xmm3
	movaps xmm2,xmm1
	shufps xmm2,xmm2,1
	maxss xmm1,xmm2
	maxss xmm1,[text_apart]
	movss [text_apart],xmm1
	ucomiss xmm1,[text_near]
	jbe .done
	inc [text_runs_apart]
.done:
	ret
endp

; DirectWrite's side of an outline: ID2D1SimplifiedGeometrySink. A figure
; begins at a point; lines and cubics follow, each from where the last ended;
; and it ends by closing, with a line if it is not where it began.
proc text_sink_ignored
	ret
endp

proc text_sink_begin this,start,how
	mov [text_current],rdx
	mov [text_figure],rdx
	ret
endp

proc text_sink_lines uses rbx rsi,this,points,count
	mov rsi,rdx
	mov ebx,r8d
.line:
	test ebx,ebx
	jz .done
	movq xmm0,[text_current]
	movq xmm1,qword [rsi]
	movaps xmm2,xmm1
	mov rax,[rsi]
	mov [text_current],rax
	fastcall text_curve
	add rsi,8
	dec ebx
	jmp .line
.done:
	ret
endp

proc text_sink_cubics uses rbx rsi rdi,this,cubics,count
	mov rsi,rdx
	mov ebx,r8d
.cubic:
	test ebx,ebx
	jz .done
	; The quadratic it would be if it were one raised: its middle point is
	; (3 c1 - c0) / 2 from one end and (3 c2 - c3) / 2 from the other, and
	; where the two agree, it is.
	movq xmm0,[text_current]
	movq xmm1,qword [rsi]
	movq xmm2,qword [rsi+8]
	movq xmm3,qword [rsi+16]
	movaps xmm4,xmm1
	mulps xmm4,xword [text_three_halves]
	movaps xmm5,xmm0
	mulps xmm5,xword [text_halves]
	subps xmm4,xmm5
	movaps xmm5,xmm2
	mulps xmm5,xword [text_three_halves]
	movaps xmm1,xmm3
	mulps xmm1,xword [text_halves]
	subps xmm5,xmm1
	movaps xmm1,xmm4
	subps xmm1,xmm5
	andps xmm1,xword [text_absolute]
	movaps xmm2,xmm1
	shufps xmm2,xmm2,1
	maxss xmm1,xmm2
	movss xmm2,[text_exactly]
	mulss xmm2,[text_scale]
	ucomiss xmm1,xmm2
	ja .earnest
	mov eax,[text_measuring]
	xor eax,1
	add [text_raised],eax
	movaps xmm1,xmm4
	addps xmm1,xmm5
	mulps xmm1,xword [text_halves]
	movaps xmm2,xmm3
	fastcall text_curve
	jmp .next
.earnest:
	; A cubic in earnest, as a polynomial in t: ((a t + b) t + c) t + d.
	mov eax,[text_measuring]
	xor eax,1
	add [text_cut],eax
	movq xmm0,[text_current]
	movq xmm1,qword [rsi]
	movq xmm2,qword [rsi+8]
	movq xmm3,qword [rsi+16]
	movq [text_poly+24],xmm0	; d = c0
	movaps xmm4,xmm1
	subps xmm4,xmm0
	mulps xmm4,xword [text_threes]
	movq [text_poly+16],xmm4	; c = 3 (c1 - c0)
	movaps xmm5,xmm2
	subps xmm5,xmm1
	mulps xmm5,xword [text_threes]
	subps xmm5,xmm4
	movq [text_poly+8],xmm5		; b = 3 (c2 - c1) - c
	subps xmm3,xmm0
	subps xmm3,xmm4
	subps xmm3,xmm5
	movq [text_poly],xmm3		; a = c3 - c0 - c - b
	xor edi,edi
.piece:
	; From t to t + 1/8: the quadratic through both ends whose middle point
	; is half-way between where the tangent at each end would put it.
	fastcall text_cubic_at,rdi
	movq [text_piece],xmm0
	movaps xmm4,xmm1
	mulps xmm4,xword [text_half_step]
	addps xmm4,xmm0
	movq [text_piece+8],xmm4
	lea ecx,[edi+1]
	fastcall text_cubic_at,rcx
	movaps xmm2,xmm0
	mulps xmm1,xword [text_half_step]
	movaps xmm4,xmm0
	subps xmm4,xmm1
	movq xmm1,[text_piece+8]
	addps xmm1,xmm4
	mulps xmm1,xword [text_halves]
	movq xmm0,[text_piece]
	fastcall text_curve
	inc edi
	cmp edi,TEXT_PIECES
	jb .piece
.next:
	mov rax,[rsi+16]
	mov [text_current],rax
	add rsi,24
	dec ebx
	jmp .cubic
.done:
	ret
endp

; The cubic in text_poly at ECX eighths along: XMM0 where it is, XMM1 the way
; it is going, to the whole of t.
proc text_cubic_at eighths
	cvtsi2ss xmm5,ecx
	mulss xmm5,[text_eighth]
	shufps xmm5,xmm5,0
	movq xmm0,[text_poly]
	movaps xmm1,xmm0
	mulps xmm0,xmm5
	movq xmm2,[text_poly+8]
	addps xmm0,xmm2
	mulps xmm0,xmm5
	movq xmm3,[text_poly+16]
	addps xmm0,xmm3
	mulps xmm0,xmm5
	movq xmm4,[text_poly+24]
	addps xmm0,xmm4
	; (3 a t + 2 b) t + c
	mulps xmm1,xword [text_threes]
	mulps xmm1,xmm5
	addps xmm2,xmm2
	addps xmm1,xmm2
	mulps xmm1,xmm5
	addps xmm1,xmm3
	ret
endp

proc text_sink_end this,how
	mov rax,[text_figure]
	cmp rax,[text_current]
	je .closed
	movq xmm0,[text_current]
	movq xmm1,[text_figure]
	movaps xmm2,xmm1
	mov [text_current],rax
	fastcall text_curve
.closed:
	ret
endp

proc text_sink_close this
	xor eax,eax
	ret
endp

section '.data$text' data readable writeable align 16
text_absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
text_halves dd 0.5,0.5,0.5,0.5
text_three_halves dd 1.5,1.5,1.5,1.5
text_threes dd 3.0,3.0,3.0,3.0
text_half_step dd 0.0625,0.0625,0.0625,0.0625	; half of an eighth
text_far dd 1.0e30,1.0e30,-1.0e30,-1.0e30	; a box before anything is in it: its low, its high
text_third dd 0.33333334
text_sixth dd 0.16666667
text_eighth dd 0.125
text_exactly dd 0.0001			; of an em: how nearly a cubic's two middle points agree when it is a raised quadratic
text_near dd 0.02			; of a unit of the playfield: how nearly a run's box is the system's
text_tall dd 100000.0
text_scale dd 1.0
text_nothing dd 0.0
text_placing dd 1			; cleared, a string is laid out and measured and nothing of it is set down
text_bytes dd 255.0
text_stretch dd 5
text_factory dq 0
text_layers dq 0
text_layer dq 0
text_layout dq 0
text_made dq 0
text_string dq 0
text_form dq 0
match buffers, TEXT_BUFFERS
	iterate buffer, buffers
		buffer GpuBuffer
	end iterate
end match
text_block dq 0
text_current dq 0
text_figure dq 0
text_low dq 0
text_high dq 0
text_run_low dq 0
text_run_high dq 0
text_line_low dq 0
text_line_high dq 0
text_poly rq 4
text_piece rq 2
text_faces rq TEXT_FACES
text_count_pipeline dq 0
text_place_pipeline dq 0
text_fill_pipeline dq 0
text_take_pipeline dq 0
text_examine_pipeline dq 0
text_judge_pipeline dq 0
; What the layout calls back through, and what an outline is taken by.
text_renderer dq text_renderer_table
text_sink dq text_sink_table
text_renderer_table dq text_renderer_query,text_counted,text_counted,text_unsnapped,text_untransformed,text_unscaled,text_draw_run,text_undrawn,text_undrawn,text_undrawn
text_sink_table dq text_sink_query,text_counted,text_counted,text_sink_ignored,text_sink_ignored,text_sink_begin,text_sink_lines,text_sink_cubics,text_sink_end,text_sink_close
; (IDWriteFactory2, which is in every Windows since 8.1: the first that makes layers of a glyph of colors.)
text_guid text_iid_factory,0439fc60h,0ca44h,4994h,8dh,0eeh,3ah,9ah,0f7h,0b7h,32h,0ech
text_guid text_iid_unknown,0,0,0,0c0h,0,0,0,0,0,0,46h
text_guid text_iid_snapping,0eaf3a2dah,0ecf4h,4d24h,0b6h,44h,0b3h,4fh,68h,42h,02h,4bh
text_guid text_iid_renderer,0ef8a8135h,5cc6h,45feh,88h,25h,0c5h,0a0h,72h,4eh,0b8h,19h
text_guid text_iid_sink,2cd9069eh,12e2h,11dch,9fh,0edh,00h,11h,43h,0a0h,55h,0f9h
text_locale du 'en-us',0
	align 4
text_metrics:				; DWRITE_TEXT_METRICS
.left dd 0
.top dd 0
.width dd 0
.width_with_trailing dd 0
.height dd 0
.layout_width dd 0
.layout_height dd 0
.depth dd 0
.lines dd 0
iterate name, text_units,text_size,text_weight,text_x,text_y,text_width,text_color,text_pen,text_base,text_origin,text_run_size,text_run_backward,text_way,text_slot,text_first,text_area, \
	text_curve_count,text_face_count,text_groups,text_judged,text_measuring,text_checking,text_own, \
	text_run_x,text_run_y,text_run_color,text_run_own,text_one_advance,text_baseline,text_based,text_has,text_layered,text_layers_made,text_keeping,text_laid_count, \
	text_line_step,text_dirty,text_taking,text_takes,text_dispatched, \
	text_runs,text_backward,text_advance,text_glyphs,text_ink,text_first_x,text_last_x,text_cos,text_sin,text_builds,text_raised,text_cut,text_lost,text_runs_held,text_runs_apart,text_apart
	name dd 0
end iterate
text_one dw 0,0
text_seen rd 16
TEXT_LAYERS_SEEN := 16
text_layers_seen rd TEXT_LAYERS_SEEN*3

section '.bss$text' readable writeable align 16
text_keys rb TEXT_GLYPHS*16		; a face and a glyph of it, for every glyph known
