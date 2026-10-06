; Checked top-down BGRA export; caller supplies header, written, and app_io_failed state.
proc save_bitmap uses rbx rsi rdi,filename,source,width,height
	mov [source],rdx
	mov [bitmap_file_header.info.biWidth],r8d
	neg r9d
	mov [bitmap_file_header.info.biHeight],r9d
	neg r9d
	imul r8d,r9d
	shl r8d,2
	mov [save_byte_count],r8d
	mov [bitmap_file_header.info.biSizeImage],r8d
	add r8d,54
	mov [bitmap_file_header.length],r8d
	fastcall CreateFileW,rcx,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .failed
	mov rbx,rax
	fastcall WriteFile,rbx,addr bitmap_file_header,54,addr written,0
	test eax,eax
	jz .close_failed
	cmp [written],54
	jne .close_failed
	mov rsi,[source]
	mov edi,[save_byte_count]
.write:
	test edi,edi
	jz .success
	fastcall WriteFile,rbx,rsi,rdi,addr written,0
	test eax,eax
	jz .close_failed
	mov eax,[written]
	test eax,eax
	jz .close_failed
	add rsi,rax
	sub edi,eax
	jmp .write
.success:
	fastcall CloseHandle,rbx
	test eax,eax
	jz .failed
	mov eax,1
	ret
.close_failed:
	fastcall CloseHandle,rbx
.failed:
	mov [app_io_failed],1
	xor eax,eax
	ret
endp
