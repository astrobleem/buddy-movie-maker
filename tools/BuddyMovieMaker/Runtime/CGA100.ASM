; Original 8086 CGA100 attribute writers; interrupts remain enabled.
.8086
.MODEL SMALL
.CODE
PUBLIC _Cga100, _CgaRow, _CgaBatch, _CgaRuns, _CgaCheck
EXTRN _CgaPoll:NEAR
_CgaRow PROC NEAR
    push bp
    mov bp,sp
    push si
    push di
    push es
    mov ax,0b800h
    mov es,ax
    mov si,[bp+4]
    mov di,[bp+6]
    mov cx,[bp+8]
    cld
cg_row:
    lodsb
    mov es:[di],al
    add di,2
    loop cg_row
    pop es
    pop di
    pop si
    pop bp
    ret
_CgaRow ENDP
_CgaBatch PROC NEAR
    push bp
    mov bp,sp
    push bx
    push si
    push di
    push es
    mov ax,0b800h
    mov es,ax
    mov si,[bp+4]
    mov di,[bp+6]
    mov bx,[bp+8]
    mov cx,bx
    shr cx,1
    shr cx,1
    cld
    jcxz cg_tail
cg_batch:
    lodsw
    mov es:[di],al
    mov es:[di+2],ah
    lodsw
    mov es:[di+4],al
    mov es:[di+6],ah
    add di,8
    loop cg_batch
cg_tail:
    mov cx,bx
    and cx,3
    jcxz cg_done
cg_byte:
    lodsb
    mov es:[di],al
    add di,2
    loop cg_byte
cg_done:
    pop es
    pop di
    pop si
    pop bx
    pop bp
    ret
_CgaBatch ENDP
; Validate a bounded packet without writing VRAM. Return fills only on success.
_CgaCheck PROC NEAR
    push bp
    mov bp,sp
    push bx
    push si
    push di
    mov si,[bp+4]
    mov cx,[bp+6]
    mov di,8000
    xor bx,bx
    cld
check_next:
    or cx,cx
    jz check_end
    cmp cx,2
    jb check_bad
    lodsw
    sub cx,2
    mov dx,ax
    and dx,7fffh
    jz check_bad
    cmp dx,di
    ja check_bad
    sub di,dx
    test ax,8000h
    jz check_literal
    jcxz check_bad
    inc si
    dec cx
    add bx,dx
    jmp check_next
check_literal:
    cmp dx,cx
    ja check_bad
    add si,dx
    sub cx,dx
    jmp check_next
check_end:
    or di,di
    jnz check_bad
    mov di,[bp+8]
    mov [di],bx
    mov ax,1
    jmp short check_exit
check_bad:
    xor ax,ax
check_exit:
    pop di
    pop si
    pop bx
    pop bp
    ret
_CgaCheck ENDP
; Input is prevalidated by CgaCheck. Each command fills or copies attribute cells.
; SI: packet, DI: even VRAM byte offset, BX: cells until control poll.
_CgaRuns PROC NEAR
    push bp
    mov bp,sp
    push bx
    push si
    push di
    push es
    mov ax,0b800h
    mov es,ax
    mov si,[bp+4]
    xor di,di
    mov bx,512
    cld
run_command:
    cmp di,16000
    jae run_done
    lodsw
    mov dx,ax
    and dx,7fffh
    test ax,8000h
    jz run_literal
    lodsb
    mov ah,al
    mov al,0deh
run_fill:
    mov cx,dx
    cmp cx,bx
    jbe run_fill_count
    mov cx,bx
run_fill_count:
    sub dx,cx
    sub bx,cx
    rep stosw
    or bx,bx
    jnz run_fill_more
    call run_poll
    jz run_done
run_fill_more:
    or dx,dx
    jnz run_fill
    jmp run_command
run_literal:
    lodsb
    mov es:[di+1],al
    add di,2
    dec bx
    jnz run_literal_more
    call run_poll
    jz run_done
run_literal_more:
    dec dx
    jnz run_literal
    jmp run_command
run_done:
    pop es
    pop di
    pop si
    pop bx
    pop bp
    ret
_CgaRuns ENDP
; Preserve the current fill word and command state. POP leaves test flags.
run_poll PROC NEAR
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    call _CgaPoll
    or ax,ax
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    mov bx,512
    ret
run_poll ENDP
_Cga100 PROC NEAR
    push bx
    push cx
    push dx
    push di
    push es
    mov ax,3
    int 10h
    mov dx,3d8h
    mov al,1
    out dx,al
    mov dx,3d4h
    mov ax,07100h
    out dx,ax
    mov ax,05001h
    out dx,ax
    mov ax,05a02h
    out dx,ax
    mov ax,00a03h
    out dx,ax
    mov ax,07f04h
    out dx,ax
    mov ax,00605h
    out dx,ax
    mov ax,06406h
    out dx,ax
    mov ax,07007h
    out dx,ax
    mov ax,00208h
    out dx,ax
    mov ax,00109h
    out dx,ax
    mov ax,0200ah
    out dx,ax
    mov ax,0000bh
    out dx,ax
    mov ax,0000ch
    out dx,ax
    mov ax,0000dh
    out dx,ax
    mov ax,0000eh
    out dx,ax
    mov ax,0000fh
    out dx,ax
    push ds
    mov ax,40h
    mov ds,ax
    mov byte ptr ds:[65h],09h
    pop ds
    mov dx,3d9h
    xor al,al
    out dx,al
    mov ax,0b800h
    mov es,ax
    xor di,di
    mov ax,00deh
    mov cx,8000
    cld
    rep stosw
    mov dx,3d8h
    mov al,9
    out dx,al
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    ret
_Cga100 ENDP
END
