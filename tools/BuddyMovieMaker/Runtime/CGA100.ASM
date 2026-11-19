; Original 8086 CGA100 attribute writers; interrupts remain enabled.
.8086
.MODEL SMALL
.CODE
PUBLIC _Cga100, _CgaRow, _CgaBatch
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
