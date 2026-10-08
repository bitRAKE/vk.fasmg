; Proof 08, text: strings the system shaped, drawn from their outlines on the
; device, by the Slug algorithm. Three pages: one of scripts, one of sizes,
; one of angles. And one shape that is no font's, on the first.
;
;	build\myhits_text.exe			watch it; the pages turn by themselves
;	build\myhits_text.exe --self-test	60 scripted frames, every claim checked
;
; What each check settles is in ..\README.md.
MACHINE_NAME equ 'myhits proof 08: text'
MACHINE_TAG equ 'text'
MACHINE_SNAPSHOT := 1
include '..\..\..\common\machine.inc'
include '..\..\..\common\files.inc'
include '..\..\..\common\text.inc'

PAGES := 3
PAGE_FRAMES := 20			; a scripted run shows each page this long
SCRIPT_FRAMES := PAGES * PAGE_FRAMES
STAMP_DIRECT := 1
STAMP_PAGE := 2				; and the two after it: what each page's draw cost
public mainCRTStartup

; The world's header, which the CPU writes: World in page.slang.
boundary PageWorld
	block text,Text
end boundary

; A line of a page, as the tables below have it.
LINE_PAGE := 0
LINE_FACE := 4
LINE_X := 8
LINE_Y := 12
LINE_WIDTH := 16
LINE_COLOR := 20
LINE_UNITS := 24
LINE_TURN := 28
LINE_STRING := 32
LINE_BYTES := 40
FACE_BYTES := 16
page.faces = 0
page.lines = 0
macro page_face name*,family*,size*,weight:400
	FACE_#name := page.faces
	page.faces = page.faces + 1
	dq family
	dd size,weight
end macro
macro page_line number*,face_name*,x*,y*,wide*,ink*,turn*,string*
	dd number,FACE_#face_name
	dd x,y,wide,ink
	dd string#.units
	dd turn
	dq string
	page.lines = page.lines + 1
end macro
; (A parameter is replaced after a dot too: so it is not called what the constant is.)
macro page_said name*,content&
	name du content
	name.units := ($ - name) / 2
end macro

section '.text$page' code readable executable align 16

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

proc create_world uses rbx rsi rdi
	mov [failure_stage],3
	require_ok fastcall create_buffer,addr header_buffer,sizeof.PageWorld,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_UPLOAD
	require_ok fastcall text_start
	mov rcx,[header_buffer.mapped]
	require_ok fastcall text_create,rcx,addr header_buffer
	mov rax,[header_buffer.address]
	mov [root+Root.world],rax
	iterate name, text_count,text_place,text_fill,text_examine,text_judge,direct
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	require_ok fastcall machine_graphics,addr text_vertex_code,text_vertex_code.size,addr text_fragment_code,text_fragment_code.size,BLEND_PREMULTIPLIED,addr text_pipeline
	; Every format the pages are set in.
	lea rsi,[faces]
	lea rdi,[formats]
	mov ebx,FACES
.format:
	fastcall text_format,qword [rsi],dword [rsi+8],dword [rsi+12]
	test rax,rax
	jz .failed
	mov [rdi],rax
	add rsi,FACE_BYTES
	add rdi,8
	dec ebx
	jnz .format
	; What the system makes of a few strings is asked first, with nothing
	; set down; then each page is set once, so that every glyph any of them
	; has is known and its bands are built: three builds, each of what the
	; one before had not met. A program that is checking has every run's
	; box held to the system's as it goes.
	mov eax,[test_mode]
	mov [text_checking],eax
	fastcall check_shaping
	fastcall check_cubic
	; A shape of this program's own, which the device will examine with the
	; rest: its curves are cubics in earnest, and are cut.
	mov eax,[text_cut]
	mov [shape_cut],eax
	fastcall text_shape,addr give_discs,0
	mov [shape_glyph],eax
	mov eax,[text_cut]
	sub eax,[shape_cut]
	mov [shape_cut],eax
	xor ebx,ebx
.page:
	fastcall page_set,rbx
	require_ok fastcall text_build
	inc ebx
	cmp ebx,PAGES
	jb .page
	; And the device examines every glyph it was given.
	require_ok fastcall text_inspect
	fastcall page_set,0
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

proc release_world uses rbx
	iterate name, text_count,text_place,text_fill,text_examine,text_judge,direct,text
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	xor ebx,ebx
.format:
	lea rax,[formats]
	mov rax,[rax+rbx*8]
	test rax,rax
	jz .next
	mov [text_made],rax
	com [text_made],COM_Release
.next:
	inc ebx
	cmp ebx,FACES
	jb .format
	fastcall text_stop
	fastcall destroy_buffer,addr header_buffer
	ret
endp

; Set a page: everything that was set down goes, and each of the page's
; lines is laid out and set down, and turned if it is to be. The first time a
; line is set, what came of it is kept for the checks.
proc page_set uses rbx rsi rdi r12,number
	mov r12d,ecx
	mov [page_now],ecx
	fastcall text_clear
	lea rsi,[lines]
	xor ebx,ebx
.line:
	cmp ebx,LINES
	jae .done
	cmp [rsi+LINE_PAGE],r12d
	jne .next
	mov rax,[text_block]
	mov edi,[rax+Text.placed_count]
	mov eax,[rsi+LINE_FACE]
	lea rdx,[formats]
	mov rax,[rdx+rax*8]
	mov [line_format],rax
	fastcall text_set,qword [rsi+LINE_STRING],dword [rsi+LINE_UNITS],[line_format],dword [rsi+LINE_X],dword [rsi+LINE_Y],dword [rsi+LINE_WIDTH],dword [rsi+LINE_COLOR]
	iterate <kept,value>, line_glyphs,eax, line_runs,[text_runs], line_backward,[text_backward], line_advance,[text_advance], line_wide,[text_metrics.width_with_trailing], \
		line_rows,[text_metrics.lines], line_top,[text_metrics.top], line_tall,[text_metrics.height], line_ink,[text_ink]
		match =eax, value
		else
			mov eax,value
		end match
		lea rdx,[kept]
		mov [rdx+rbx*4],eax
	end iterate
	cmp dword [rsi+LINE_TURN],0
	je .next
	fastcall text_turn,rdi,dword [rsi+LINE_X],dword [rsi+LINE_Y],dword [rsi+LINE_TURN]
.next:
	add rsi,LINE_BYTES
	inc ebx
	jmp .line
.done:
	; The first page has the shape on it too.
	test r12d,r12d
	jnz .set
	fastcall text_put,[shape_glyph],[shape_x],[shape_y],[shape_size],WHITE
.set:
	ret
endp

; The shape: two discs, each over part of the other, both going round the
; same way. Each is the four cubics that draw a circle.
proc give_discs uses rbx rsi,number
	lea rsi,[discs]
	mov ebx,2
.disc:
	mov rdx,[rsi]
	fastcall text_sink_begin,0,rdx,0
	lea rdx,[rsi+8]
	fastcall text_sink_cubics,0,rdx,4
	fastcall text_sink_end,0,1
	add rsi,DISC_BYTES
	dec ebx
	jnz .disc
	ret
endp

; Lay a string out with nothing set down: RCX the string, EDX its units, R8D
; which face. What came of it is in text.inc's own numbers.
proc measure string,units,which
	lea rax,[formats]
	mov rax,[rax+r8*8]
	mov [line_format],rax
	mov [measured_string],rcx
	mov [measured_units],edx
	mov [text_placing],0
	fastcall text_set,[measured_string],[measured_units],[line_format],0,0,[far_wide],-1
	mov [text_placing],1
	ret
endp

; 4: the system shaped it. Asked of five small strings, with nothing set down.
proc check_shaping
	; Kerned: in Arial, AV is narrower than an A and a V.
	fastcall measure,addr said_a,1,FACE_arial48
	movss xmm0,[text_metrics.width_with_trailing]
	movss [shaped_a],xmm0
	fastcall measure,addr said_v,1,FACE_arial48
	movss xmm0,[text_metrics.width_with_trailing]
	addss xmm0,[shaped_a]
	movss [shaped_a],xmm0
	fastcall measure,addr said_av,2,FACE_arial48
	movss xmm0,[text_metrics.width_with_trailing]
	movss [shaped_av],xmm0
	addss xmm0,[one]
	ucomiss xmm0,[shaped_a]
	jae .wrong
	or [shaped],1
	; Ligated: in Calibri, f and i are one glyph.
	fastcall measure,addr said_fi,2,FACE_calibri48
	mov eax,[text_glyphs]
	mov [shaped_fi],eax
	cmp eax,1
	jne .wrong
	or [shaped],2
	; Joined, and right to left: an Arabic lam alone is one glyph; three in
	; a row are three that are not all that one, in a run that goes
	; backward, the first of them furthest right.
	fastcall measure,addr said_lam,1,FACE_segoe56
	mov eax,[text_seen]
	mov [shaped_lam],eax
	fastcall measure,addr said_lams,3,FACE_segoe56
	cmp [text_glyphs],3
	jne .wrong
	cmp [text_backward],1
	jb .wrong
	movss xmm0,[text_first_x]
	ucomiss xmm0,[text_last_x]
	jbe .wrong
	mov eax,[text_seen]
	cmp eax,[text_seen+4]
	je .wrong
	mov eax,[text_seen+4]
	cmp eax,[text_seen+8]
	je .wrong
	cmp eax,[shaped_lam]
	je .wrong
	or [shaped],4
	; Conjoined: ka, a virama and ssa in Devanagari are fewer than three glyphs.
	fastcall measure,addr said_ksha,3,FACE_segoe56
	mov eax,[text_glyphs]
	mov [shaped_ksha],eax
	cmp eax,3
	jae .wrong
	test eax,eax
	jz .wrong
	or [shaped],8
	ret
.wrong:
	xor esi,esi
	fail 4
	ret
endp

; 2, in part: a cubic that is no raised quadratic is cut in eight, and the
; eight lie on it. A quarter of a circle is given to the sink as the cubic
; that draws one, which is itself within three ten-thousandths of the circle:
; every piece's ends are within five of it, and its middle within a
; thousandth. The pieces are then forgotten.
proc check_cubic uses rbx
	mov eax,[text_curve_count]
	mov [cubic_first],eax
	mov eax,[text_cut]
	mov [cubic_cut],eax
	mov [text_measuring],0
	mov dword [text_scale],1.0
	fastcall text_open
	mov rdx,qword [circle]
	fastcall text_sink_begin,0,rdx,0
	fastcall text_sink_cubics,0,addr circle+8,1
	mov ebx,[text_curve_count]
	sub ebx,[cubic_first]
	mov [cubic_pieces],ebx
	cmp ebx,TEXT_PIECES
	jne .wrong
	mov eax,[cubic_first]
	imul eax,eax,sizeof.Curve
	mov rdx,[text_curve_buffer.mapped]
	add rdx,rax
.piece:
	; |p1| and |p3| are 1; and so, nearly, is |(p1 + 2 p2 + p3) / 4|.
	iterate <point,slack>, Curve.p1,circle_exact, Curve.p3,circle_exact, 0,circle_near
		match =0, point
			movq xmm0,[rdx+Curve.p1]
			movq xmm1,[rdx+Curve.p2]
			addps xmm0,xmm1
			addps xmm0,xmm1
			movq xmm1,[rdx+Curve.p3]
			addps xmm0,xmm1
			mulps xmm0,xword [quarters]
		else
			movq xmm0,[rdx+point]
		end match
		mulps xmm0,xmm0
		movaps xmm1,xmm0
		shufps xmm1,xmm1,1
		addss xmm0,xmm1
		sqrtss xmm0,xmm0
		subss xmm0,[one]
		andps xmm0,xword [text_absolute]
		maxss xmm0,[cubic_worst]
		movss [cubic_worst],xmm0
		ucomiss xmm0,[slack]
		ja .wrong
	end iterate
	add rdx,sizeof.Curve
	dec ebx
	jnz .piece
	mov eax,[text_cut]
	sub eax,[cubic_cut]
	cmp eax,1
	jne .wrong
	jmp .forget
.wrong:
	xor esi,esi
	fail 2
.forget:
	; None of this was a glyph: the curves and the count go back as they were.
	mov eax,[cubic_first]
	mov [text_curve_count],eax
	mov eax,[cubic_cut]
	mov [text_cut],eax
	ret
endp

; One frame: the last one's events in, Root down, one compute pass, one draw.
proc play_frame
	fastcall machine_await
	test eax,eax
	jz .stopped
	test dword [root+Root.flags],ROOT_SCRIPTED
	jz .turning
	; The script: each page for twenty frames. Setting one is not a frame's
	; traffic, and is not done in one: it is done between two.
	iterate <when,number>, PAGE_FRAMES,1, 2*PAGE_FRAMES,2
		cmp dword [root+Root.frame],when
		jne .kept_#number
		fastcall page_set,number
		fastcall text_build
	.kept_#number:
	end iterate
	jmp .sample
.turning:
	; Watched, the pages turn every three seconds or so.
	mov eax,[root+Root.frame]
	xor edx,edx
	mov ecx,240
	div ecx
	test edx,edx
	jnz .sample
	xor edx,edx
	mov ecx,PAGES
	div ecx
	cmp edx,[page_now]
	je .sample
	fastcall page_set,rdx
	fastcall text_build
.sample:
	fastcall machine_sample
	fastcall machine_open
	cmp eax,1
	jne .skipped
	fastcall machine_dispatch,[direct_pipeline],1
	fastcall machine_stamp,STAMP_DIRECT
	fastcall machine_canvas
	fastcall draw_world
	; The scripted run leaves a picture of each page.
	iterate when, 5,25,45
		cmp dword [root+Root.frame],when
		jne .no_#when
		fastcall snapshot_take,when
	.no_#when:
	end iterate
	fastcall machine_close
	ret
.skipped:
	; 2: no image this turn, which is not a failure.
	shr eax,1
.stopped:
	ret
endp

; Everything a frame draws: the glyphs that are set down, six vertices to each.
proc draw_world
	mov rax,[text_block]
	mov r8d,[rax+Text.placed_count]
	fastcall machine_draw,[text_pipeline],6,r8
	mov ecx,[page_now]
	add ecx,STAMP_PAGE
	fastcall machine_stamp,rcx
	ret
endp

; A finished frame's events: what the device found when it built and examined.
proc consume_events uses rbx rsi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	iterate <name,offset>, found_listed,0, found_crowded,4, found_longest,8, found_unplaced,12, found_examined,16, found_band_faults,20, found_area_faults,24, \
		found_worst_area,28, found_samples,32, found_glyphs,36, found_bands,40, found_placed,44, found_built,48, found_cover_faults,52, found_overlapped,56
		mov eax,[rbx+Events.reserved+offset]
		mov [name],eax
	end iterate
	mov eax,[root+Root.frame]
	sub eax,esi
	mov [last_latency],eax
	cmp eax,[worst_latency]
	jbe .counted
	mov [worst_latency],eax
.counted:
	cmp [test_mode],0
	je .done
	; 1: events arrive once each, in frame order, in hand when the next frame begins.
	cmp esi,[events_seen]
	jne .order_wrong
	cmp [last_latency],1
	je .done
.order_wrong:
	fail 1
.done:
	inc [events_seen]
	ret
endp

; Sixty frames by the script, then what no frame could show alone.
proc scripted_run uses rbx rsi rdi
	or dword [root+Root.flags],ROOT_SCRIPTED
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
	mov esi,SCRIPT_FRAMES
	; 2: every cubic the system gave for these fonts was a quadratic raised,
	; and was put back; none had to be cut. What was cut was this program's
	; own: the eight cubics of its two discs.
	mov eax,[text_cut]
	cmp eax,[shape_cut]
	jne .outlines_wrong
	cmp eax,8
	jne .outlines_wrong
	cmp [text_raised],100
	jae .outlines
.outlines_wrong:
	fail 2
.outlines:
	; 3: every run was set down where the system sets it: the box of the run's
	; outline as the system draws it is the box of its glyphs as set down here.
	cmp [text_runs_apart],0
	jne .runs_wrong
	cmp [text_runs_held],20
	jae .runs
.runs_wrong:
	fail 3
.runs:
	; 4, the rest: a line that is one row is as wide as its advances come to;
	; and the scripts the font asked for has not were found in others.
	lea rdi,[lines]
	xor ebx,ebx
.line:
	lea rax,[line_rows]
	cmp dword [rax+rbx*4],1
	jne .next_line
	lea rax,[line_advance]
	movss xmm0,dword [rax+rbx*4]
	lea rax,[line_wide]
	subss xmm0,dword [rax+rbx*4]
	andps xmm0,xword [text_absolute]
	ucomiss xmm0,[half]
	ja .shaped_wrong
.next_line:
	inc ebx
	cmp ebx,LINES
	jb .line
	cmp [text_face_count],5
	jb .shaped_wrong
	cmp [shaped],15
	je .shaped
.shaped_wrong:
	fail 4
.shaped:
	; 5: the bands lose nothing. Wherever it was examined, a glyph's bands gave
	; what all its curves give; no band had more curves than one is walked
	; for, and none went without room.
	cmp [found_band_faults],0
	jne .bands_wrong
	cmp [found_crowded],0
	jne .bands_wrong
	cmp [found_unplaced],0
	jne .bands_wrong
	cmp [found_samples],100000
	jb .bands_wrong
	cmp [found_examined],100
	jae .bands
.bands_wrong:
	fail 5
.bands:
	; 6: how often the rays find a glyph's places enclosed comes to what its
	; curves enclose, whatever lies over what; and what is drawn of it comes
	; to the same where nothing is enclosed twice, and to less where something
	; is. The shape is the case with an answer known beforehand: its curves
	; enclose what two discs do, the rays find the same, and what is drawn is
	; what the two cover together.
	fastcall read_shape
	cmp [found_area_faults],0
	jne .areas_wrong
	cmp [found_cover_faults],0
	jne .areas_wrong
	cmp [found_overlapped],1
	jb .areas_wrong
	cmp [shape_glyph],0
	jl .areas_wrong
	iterate <found,wanted,slack>, shape_area,discs_enclose,shape_exact, shape_wound,discs_enclose,shape_near, shape_covered,discs_cover,shape_near
		movss xmm0,[found]
		subss xmm0,[wanted]
		andps xmm0,xword [text_absolute]
		ucomiss xmm0,[slack]
		ja .areas_wrong
	end iterate
	jmp .areas
.areas_wrong:
	fail 6
.areas:
	; 8: every frame's events were read, and Root and Events were all a frame's traffic.
	cmp [events_seen],SCRIPT_FRAMES
	jne .traffic_wrong
	cmp [traffic_down],SCRIPT_FRAMES*sizeof.Root
	jne .traffic_wrong
	cmp [traffic_up],SCRIPT_FRAMES*sizeof.Events
	je .traffic
.traffic_wrong:
	fail 8
.traffic:
	; 9: builds of three passes each, more than one of them, and two passes of
	; examining made the text ready; after that a frame is one pass and one draw, and
	; setting a page whose glyphs are all known builds nothing.
	cmp [text_builds],2
	jb .commands
	imul eax,[text_builds],TEXT_PASSES
	add eax,2
	cmp [startup_dispatches],eax
	jne .commands
	cmp [dispatch_count],SCRIPT_FRAMES
	jne .commands
	cmp [draw_count],SCRIPT_FRAMES
	je .lines
.commands:
	fail 9
.lines:
	fastcall write_lines
	fastcall write_glyphs
	jmp .report
.broken:
	mov [app_io_failed],1
.report:
	iterate <whole,from>, shaped_a_whole,shaped_a, shaped_av_whole,shaped_av, apart_whole,text_apart, cubic_whole,cubic_worst
		movss xmm0,[from]
		mulss xmm0,[thousand]
		cvtss2si eax,xmm0
		mov [whole],eax
	end iterate
	iterate <whole,from>, shape_area_whole,shape_area, shape_wound_whole,shape_wound, shape_covered_whole,shape_covered
		movss xmm0,[from]
		mulss xmm0,[millionths]
		cvtss2si eax,xmm0
		mov [whole],eax
	end iterate
	mov rax,[text_block]
	mov eax,[rax+Text.glyph_count]
	mov [found_glyphs],eax
	fastcall wsprintfW,addr report_text,<W,'proof=text',13,10,'failure=%u',13,10,'failure_frame=%u',13,10,'frames=%u',13,10,'events=%u',13,10, \
		'glyphs=%u',13,10,'curves=%u',13,10,'bands=%u',13,10,'listed=%u',13,10,'longest=%u',13,10,'crowded=%u',13,10,'unplaced=%u',13,10,'faces=%u',13,10, \
		'raised=%u',13,10,'cut=%u',13,10,'cubic_pieces=%u',13,10,'cubic_worst_thousandths=%u',13,10,'runs_held=%u',13,10,'runs_apart=%u',13,10,'apart_thousandths=%u',13,10, \
		'examined=%u',13,10,'samples=%u',13,10,'band_faults=%u',13,10,'area_faults=%u',13,10,'worst_area_thousandths=%u',13,10,'shaped=%u',13,10, \
		'kerned_thousandths=%u',13,10,'unkerned_thousandths=%u',13,10,'ligature_glyphs=%u',13,10,'conjunct_glyphs=%u',13,10,'lost=%u',13,10,'builds=%u',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],[found_glyphs],[text_curve_count],[found_bands],[found_listed],[found_longest],[found_crowded],[found_unplaced],[text_face_count], \
		[text_raised],[text_cut],[cubic_pieces],[cubic_whole],[text_runs_held],[text_runs_apart],[apart_whole],[found_examined],[found_samples],[found_band_faults],[found_area_faults],[found_worst_area],[shaped], \
		[shaped_av_whole],[shaped_a_whole],[shaped_fi],[shaped_ksha],[text_lost],[text_builds]
	mov ebx,eax
	lea rcx,[report_text]
	lea rcx,[rcx+rbx*2]
	fastcall wsprintfW,rcx,<W,'cover_faults=%u',13,10,'overlapped=%u',13,10,'shape_cut=%u',13,10,'shape_area_millionths=%u',13,10,'shape_wound_millionths=%u',13,10,'shape_covered_millionths=%u',13,10, \
		'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10,'startup_dispatches=%u',13,10,'dispatches=%u',13,10,'draws=%u',13,10,'worst_latency=%u',13,10, \
		'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		[found_cover_faults],[found_overlapped],[shape_cut],[shape_area_whole],[shape_wound_whole],[shape_covered_whole], \
		[traffic_down],[traffic_up],[startup_dispatches],[dispatch_count],[draw_count],[worst_latency],[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage]
	add eax,ebx
	fastcall machine_write_report,rax
	ret
endp

; What the shape came to when it was examined, and what its curves enclose,
; in square ems.
proc read_shape
	fastcall invalidate_buffer,addr text_sum_buffer
	mov eax,[shape_glyph]
	test eax,eax
	js .none
	imul edx,eax,sizeof.Examined
	mov r8,[text_sum_buffer.mapped]
	add r8,rdx
	imul eax,eax,sizeof.Glyph
	mov rdx,[text_glyph_buffer.mapped]
	movss xmm0,dword [rdx+rax+Glyph.area]
	andps xmm0,xword [text_absolute]
	movss [shape_area],xmm0
	iterate <found,sum>, shape_wound,Examined.wound, shape_covered,Examined.covered
		mov eax,[r8+sum]
		cvtsi2ss xmm0,rax
		mulss xmm0,[sum_to_ems]
		movss [found],xmm0
	end iterate
.none:
	ret
endp

; What each line of the pages came to, for the proof runner to hold the
; pictures to: its page, where it lies, how many glyphs and runs it was and
; how many ran backward, how much ink its outlines should come to, in pixels
; of the playfield, how far it is turned, in ten-thousandths of a radian, and
; the size it is set at. The shape is the last of them: one glyph, in the
; square of its em, and its ink what two discs cover together.
proc write_lines uses rbx rsi rdi r12
	fastcall file_begin,<W,'build\myhits_text.lines.txt'>
	mov r12,rax
	lea rsi,[lines]
	xor ebx,ebx
.line:
	iterate <whole,from>, line_top_whole,line_top, line_tall_whole,line_tall, line_ink_whole,line_ink, line_wide_whole,line_wide
		lea rax,[from]
		cvtss2si eax,dword [rax+rbx*4]
		mov [whole],eax
	end iterate
	cvtss2si eax,dword [rsi+LINE_X]
	mov [line_x_whole],eax
	cvtss2si eax,dword [rsi+LINE_Y]
	mov [line_y_whole],eax
	iterate <whole,from>, line_glyphs_now,line_glyphs, line_runs_now,line_runs, line_backward_now,line_backward, line_rows_now,line_rows
		lea rax,[from]
		mov eax,[rax+rbx*4]
		mov [whole],eax
	end iterate
	movss xmm0,dword [rsi+LINE_TURN]
	mulss xmm0,[ten_thousand]
	cvtss2si eax,xmm0
	mov [line_turned],eax
	mov eax,[rsi+LINE_FACE]
	shl eax,4
	lea rdx,[faces]
	cvtss2si eax,dword [rdx+rax+8]
	mov [line_size],eax
	fastcall wsprintfW,addr title_text,<W,'%u %u %d %d %d %d %d %u %u %u %u %u %d %u',13,10>,rbx,dword [rsi+LINE_PAGE],[line_x_whole],[line_y_whole],[line_top_whole],[line_tall_whole],[line_wide_whole], \
		[line_ink_whole],[line_glyphs_now],[line_runs_now],[line_backward_now],[line_rows_now],[line_turned],[line_size]
	lea r8d,[eax*2]
	fastcall file_more,r12,addr title_text,r8
	add rsi,LINE_BYTES
	inc ebx
	cmp ebx,LINES
	jb .line
	movss xmm0,[shape_size]
	cvtss2si eax,xmm0
	mov [line_tall_whole],eax
	mulss xmm0,xmm0
	mulss xmm0,[discs_cover]
	cvtss2si eax,xmm0
	mov [line_ink_whole],eax
	cvtss2si eax,[shape_x]
	mov [line_x_whole],eax
	cvtss2si eax,[shape_y]
	sub eax,[line_tall_whole]
	mov [line_y_whole],eax
	fastcall wsprintfW,addr title_text,<W,'%u 0 %d %d 0 %d %d %u 1 0 0 1 0 %d',13,10>,rbx,[line_x_whole],[line_y_whole],[line_tall_whole],[line_tall_whole],[line_ink_whole],[line_tall_whole]
	lea r8d,[eax*2]
	fastcall file_more,r12,addr title_text,r8
	fastcall file_done,r12
	ret
endp

; Every glyph the pages have, for whoever wants to know which one a number
; is about: which it is of all that are known, which it is in its font, how
; many curves it has, what they enclose, how often the rays found its places
; enclosed and what is drawn of it, all three in millionths of a square em,
; how many places were enclosed twice, and its box, in thousandths of an em.
proc write_glyphs uses rbx rsi rdi r12
	fastcall invalidate_buffer,addr text_sum_buffer
	fastcall file_begin,<W,'build\myhits_text.glyphs.txt'>
	mov r12,rax
	mov rsi,[text_glyph_buffer.mapped]
	xor ebx,ebx
.glyph:
	mov rax,[text_block]
	cmp ebx,[rax+Text.glyph_count]
	jae .done
	movss xmm0,dword [rsi+Glyph.area]
	andps xmm0,xword [text_absolute]
	mulss xmm0,[millionths]
	cvtss2si eax,xmm0
	mov [glyph_area],eax
	imul edx,ebx,sizeof.Examined
	add rdx,[text_sum_buffer.mapped]
	iterate <whole,sum>, glyph_wound,Examined.wound, glyph_found,Examined.covered
		mov eax,[rdx+sum]
		cvtsi2ss xmm0,rax
		mulss xmm0,[sum_to_millionths]
		cvtss2si eax,xmm0
		mov [whole],eax
	end iterate
	mov eax,[rdx+Examined.twice]
	mov [glyph_twice],eax
	iterate <whole,from>, glyph_left,Glyph.low, glyph_top,Glyph.low+4, glyph_right,Glyph.high, glyph_bottom,Glyph.high+4
		movss xmm0,dword [rsi+from]
		mulss xmm0,[thousand]
		cvtss2si eax,xmm0
		mov [whole],eax
	end iterate
	mov eax,ebx
	shl eax,4
	lea rdx,[text_keys]
	mov eax,[rdx+rax+8]
	mov [glyph_id],eax
	fastcall wsprintfW,addr title_text,<W,'%u %u %u %u %u %u %u %d %d %d %d %u',13,10>,rbx,[glyph_id],dword [rsi+Glyph.curve_count],[glyph_area],[glyph_wound],[glyph_found],[glyph_twice], \
		[glyph_left],[glyph_top],[glyph_right],[glyph_bottom],dword [rsi+Glyph.rows]
	lea r8d,[eax*2]
	fastcall file_more,r12,addr title_text,r8
	add rsi,sizeof.Glyph
	inc ebx
	jmp .glyph
.done:
	fastcall file_done,r12
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
	cmp [test_mode],0
	je .show
	fastcall machine_measure
	fastcall snapshot_start
	fastcall scripted_run
	jmp .finish
.show:
	fastcall resize_window,1280,720
	fastcall ShowWindow,[window],SW_SHOWNORMAL
	fastcall UpdateWindow,[window]
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
	; in front or showing something other than the last frame.
	cmp [minimized],0
	jne .wait
	cmp [stale],0
	jne .draw
	fastcall GetForegroundWindow
	cmp rax,[window]
	jne .wait
.draw:
	fastcall play_frame
	test eax,eax
	jz .failed
	mov [stale],0
	test dword [root+Root.frame],31
	jnz .messages
	fastcall wsprintfW,addr title_text,<W,'myhits proof 08: text | page %u of 3 | %u glyphs known, %u set down | %u curves in %u bands, at most %u to a band | Esc quits'>, \
		[page_now],[found_glyphs],[found_placed],[text_curve_count],[found_bands],[found_longest]
	fastcall SetWindowTextW,[window],addr title_text
	jmp .messages
.wait:
	fastcall WaitMessage
	fastcall QueryPerformanceCounter,addr clock_last
	jmp .messages
.failed:
	mov [app_io_failed],1
.finish:
	fastcall free_options
	fastcall machine_stop
	fastcall machine_report_exit
	fastcall ExitProcess,rax
	int3
endp

section '.data$page' data readable writeable align 16
quarters dd 0.25,0.25,0.25,0.25
one dd 1.0
half dd 0.5
thousand dd 1000.0
ten_thousand dd 10000.0
millionths dd 1000000.0
sum_to_millionths dd 0.0596046448	; a million, over 4096 parts to a pixel and 64 by 64 pixels to a square em
sum_to_ems dd 0.0000000596046448
; The shape: two discs of radius three tenths of an em, their middles three
; tenths apart. Counted as often as it is enclosed, what they enclose is two
; discs; what they cover together is that less the lens they share, which is
; 2 r^2 acos(d / 2r) - (d / 2) sqrt(4 r^2 - d^2).
discs_enclose dd 0.565487
discs_cover dd 0.454933
shape_exact dd 0.002			; of a square em: how nearly the curves enclose what two discs do
shape_near dd 0.005			; and how nearly the device finds what it should
shape_x dd 1300.0
shape_y dd 1000.0
shape_size dd 300.0
macro disc x*,y*,r*
	local k
	k = r * 0.5522848
	dd x+r,y
	dd x+r,y+k, x+k,y+r, x,y+r
	dd x-k,y+r, x-r,y+k, x-r,y
	dd x-r,y-k, x-k,y-r, x,y-r
	dd x+k,y-r, x+r,y-k, x+r,y
end macro
DISC_BYTES := 13*8
discs:
	disc 0.35,-0.35,0.3
	disc 0.65,-0.35,0.3
far_wide dd 100000.0
circle_exact dd 0.0005
circle_near dd 0.001
; A quarter of a circle of radius one, as the cubic that draws it: from (1, 0)
; to (0, 1).
circle dd 1.0,0.0, 1.0,0.5522848, 0.5522848,1.0, 0.0,1.0
header_buffer GpuBuffer
line_format dq 0
measured_string dq 0
direct_pipeline dq 0
text_pipeline dq 0
formats rq 32
iterate name, events_seen,proof_failure,proof_failure_frame,startup_dispatches,last_latency,worst_latency,page_now,examine_groups,measured_units, \
	shape_glyph,shape_cut,shape_area,shape_wound,shape_covered,shape_area_whole,shape_wound_whole,shape_covered_whole,found_cover_faults,found_overlapped,glyph_wound,glyph_twice, \
	shaped,shaped_a,shaped_av,shaped_fi,shaped_lam,shaped_ksha,shaped_a_whole,shaped_av_whole,apart_whole,cubic_whole,cubic_first,cubic_cut,cubic_pieces,cubic_worst, \
	found_listed,found_crowded,found_longest,found_unplaced,found_examined,found_band_faults,found_area_faults,found_worst_area,found_samples,found_glyphs,found_bands,found_placed,found_built, \
	glyph_area,glyph_found,glyph_left,glyph_top,glyph_right,glyph_bottom,glyph_id,line_top_whole,line_tall_whole,line_ink_whole,line_wide_whole,line_x_whole,line_y_whole,line_glyphs_now,line_runs_now,line_backward_now,line_rows_now,line_turned,line_size
	name dd 0
end iterate

; What the pages are set in. A script the family has no glyphs for is the
; system's to find a font for.
family_segoe du 'Segoe UI',0
family_arial du 'Arial',0
family_calibri du 'Calibri',0
family_times du 'Times New Roman',0
	align 8
faces:
	page_face segoe64,family_segoe,64.0
	page_face arial48,family_arial,48.0
	page_face calibri48,family_calibri,48.0
	page_face segoe56,family_segoe,56.0
	page_face segoe40,family_segoe,40.0
	page_face segoe22,family_segoe,22.0
	page_face segoe13,family_segoe,13.0
	iterate <size,em>, 7,7.0, 9,9.0, 11,11.0, 14,14.0, 18,18.0, 24,24.0, 32,32.0, 48,48.0, 72,72.0, 96,96.0
		page_face segoe#size,family_segoe,em
	end iterate
	page_face times36,family_times,36.0
	page_face segoe700,family_segoe,700.0,700
FACES := page.faces
assert FACES <= 32

; What the pages say. What is not Latin is written as its code units, so
; that this file is the same whichever way an editor shows it.
page_said said_pangram,'Sphinx of black quartz, judge my vow.'
page_said said_kerned,'AVATAR  WAVE  To.  Ty.  LT  PA'
page_said said_ligated,'office  affluent  fjord  waffle'
; as-salamu alaykum: peace be upon you
page_said said_arabic,0627h,0644h,0633h,0644h,0627h,0645h,' ',0639h,0644h,064Ah,0643h,0645h
; shalom olam: hello, world
page_said said_hebrew,05E9h,05DCh,05D5h,05DDh,' ',05E2h,05D5h,05DCh,05DDh
; namaste duniya: hello, world
page_said said_devanagari,0928h,092Eh,0938h,094Dh,0924h,0947h,' ',0926h,0941h,0928h,093Fh,092Fh,093Eh
; sawatdi chao lok: hello, people of the world
page_said said_thai,0E2Ah,0E27h,0E31h,0E2Ah,0E14h,0E35h,0E0Ah,0E32h,0E27h,0E42h,0E25h,0E01h
; Greek, Cyrillic, Arabic, Hebrew, Devanagari and Japanese in one line of a Latin font
page_said said_mixed,'Latin  ',0395h,03BBh,03BBh,03B7h,03BDh,03B9h,03BAh,03ACh,'  ',041Ah,0438h,0440h,0438h,043Bh,043Bh,0438h,0446h,0430h,'  ', \
	0627h,0644h,0639h,0631h,0628h,064Ah,0629h,'  ',05E2h,05D1h,05E8h,05D9h,05EAh,'  ',0939h,093Fh,0928h,094Dh,0926h,0940h,'  ',65E5h,672Ch,8A9Eh
page_said said_paragraph,'The system shapes the text and the device draws it. Each glyph is its outline, a few quadratic curves, and every pixel finds for itself how much of it ', \
	'the outline covers: at any size, at any angle, with nothing drawn beforehand and no texture anywhere. A line of Arabic runs the other way, a Devanagari ', \
	'syllable is put together out of order, an f and an i become one shape, and none of that is this program',27h,'s doing.'
page_said said_small,'Small text is where a method shows what it is made of. Nine pixels to the em leaves a stem less than a pixel wide, and the letters are still ', \
	'letters: a pixel the outline only grazes is given its share and no more, from two rays that agree, and a glyph',27h,'s box is drawn half a pixel ', \
	'larger than it is so that no such pixel is left out.'
page_said said_huge,'g'
; (It begins well out from the point it turns about, so that no two of the
; twelve have a pixel between them and each can be measured by itself.)
page_said said_turned,'            outlines, not texels'
page_said said_serif,'Any angle, any size: Times, turned.'
page_said said_a,'A'
page_said said_v,'V'
page_said said_av,'AV'
page_said said_fi,'fi'
page_said said_lam,0644h
page_said said_lams,0644h,0644h,0644h
page_said said_ksha,0915h,094Dh,0937h
	align 8
WHITE := 0FFFFFFFFh
lines:
	; The first page: scripts.
	page_line 0,segoe64,60.0,16.0,1800.0,WHITE,0,said_pangram
	page_line 0,arial48,60.0,110.0,1800.0,WHITE,0,said_kerned
	page_line 0,calibri48,60.0,180.0,1800.0,WHITE,0,said_ligated
	page_line 0,segoe56,60.0,250.0,1800.0,WHITE,0,said_arabic
	page_line 0,segoe56,60.0,340.0,1800.0,WHITE,0,said_hebrew
	page_line 0,segoe56,60.0,430.0,1800.0,WHITE,0,said_devanagari
	page_line 0,segoe56,60.0,530.0,1800.0,WHITE,0,said_thai
	page_line 0,segoe40,60.0,640.0,1800.0,WHITE,0,said_mixed
	page_line 0,segoe22,60.0,730.0,1100.0,WHITE,0,said_paragraph
	page_line 0,segoe13,60.0,900.0,1100.0,WHITE,0,said_small
	; The second: sizes.
	page_line 1,segoe7,60.0,20.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe9,60.0,40.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe11,60.0,62.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe14,60.0,88.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe18,60.0,120.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe24,60.0,160.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe32,60.0,210.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe48,60.0,270.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe72,60.0,350.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe96,60.0,460.0,1800.0,WHITE,0,said_pangram
	page_line 1,segoe9,60.0,640.0,700.0,WHITE,0,said_small
	page_line 1,segoe7,60.0,760.0,600.0,WHITE,0,said_small
	; The third: angles, and one glyph larger than anything is.
	page_line 2,segoe700,1120.0,80.0,1800.0,0FF4080FFh,0,said_huge
	iterate <turn,ink>, 0.0001,0FFFFFFFFh, 0.5236,0FFA0E0FFh, 1.0472,0FF80FFC0h, 1.5708,0FFFFE080h, 2.0944,0FFFF80A0h, 2.618,0FFFFA0FFh, \
		3.1416,0FFFFFFFFh, 3.6652,0FFA0E0FFh, 4.1888,0FF80FFC0h, 4.7124,0FFFFE080h, 5.236,0FFFF80A0h, 5.7596,0FFFFA0FFh
		page_line 2,segoe32,520.0,520.0,1800.0,ink,turn,said_turned
	end iterate
	page_line 2,times36,80.0,1010.0,1800.0,WHITE,-0.12,said_serif
LINES := page.lines
iterate name, line_glyphs,line_runs,line_backward,line_advance,line_wide,line_rows,line_top,line_tall,line_ink
	name rd LINES
end iterate

section '.rdata$page_spirv' data readable align 4
iterate <name,module>, text_count_code,text_count, text_place_code,text_place, text_fill_code,text_fill, text_examine_code,text_examine, text_judge_code,text_judge, direct_code,direct, \
	text_vertex_code,text_vertex, text_fragment_code,text_fragment
	align 4
	name file 'build\myhits_text_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
